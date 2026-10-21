#!/bin/bash
# Clean Glass for Fire TV: a fast Apple TV-style home screen for Fire TV Stick (Fire OS 7), run from a Mac over Wi-Fi.
# No root, the main install switches off no Amazon packages, and one command rolls everything back.
#
# Main
#   bash firetv.sh setup <stick-ip>      install the Mac tools, fetch Glass, connect to the stick (once)
#   bash firetv.sh install               Glass home screen + safe speed settings + ad-blocking
#   bash firetv.sh uninstall             roll all of it back (Glass removed, settings restored)
#   bash firetv.sh tidy                  optional: switch off unused Amazon apps (Game Centre, Kids, Live Shopping...)
#
# Everyday
#   bash firetv.sh dock pkg1 pkg2 ...    dock apps, left to right (or arrange on the TV: Menu > Move)
#   bash firetv.sh apps                  package names of your apps
#   bash firetv.sh homekey off|on        Home opens Amazon's screen (off) or Glass (on)
#   bash firetv.sh adblock [off]         ad-blocking DNS on / off
#
# Checks (read-only)
#   bash firetv.sh state                 is the stick awake, what's on screen, crashes, smoothness
#   bash firetv.sh speedcheck NAME       memory + home-screen smoothness, saved to backup/speed-NAME.txt
#   bash firetv.sh gaptest | gaplog      how fast Glass returns after Home
#   bash firetv.sh investigate           5-minute health check: CPU, memory, storage, Wi-Fi, frames
#   bash firetv.sh remote                Bluetooth / remote state
#
# Recovery (all work without the remote)
#   bash firetv.sh key HOME|UP|DOWN|LEFT|RIGHT|OK|BACK|MENU   press remote buttons from the Mac (+ screenshot)
#   bash firetv.sh pairscreen            open the remotes settings screen (for "Add New Remote")
#   bash firetv.sh rescue                switch the Home redirect off and close Glass
#   bash firetv.sh redirectcheck         check and restart the Home redirect
#   bash firetv.sh resetall              put the stick fully back to stock and restart it

set -u

KIT="$(cd "$(dirname "$0")" && pwd)"
GLASS="$KIT/firetv-glass-launcher"
GLASS_REPO="https://github.com/ivantrj/firetv-glass-launcher.git"
GLASS_COMMIT="95523e55c3bba5d28d6d377d0a72eaee979c4c13"   # the Glass version these patches are written against
SDK="$KIT/android-sdk"
GLASS_PKG="com.ivantrj.glasslauncher"
DNS_HOST="dns.adguard-dns.com"
# First install only: the first four of these that are installed go in the dock
DOCK_DEFAULT="com.netflix.ninja com.amazon.firebat com.amazon.firetv.youtube com.disney.disneyplus in.startv.hotstar com.spotify.tv.android"
# tidy, switched off (reversible). Each stayed off through restarts on the test stick with the remote working.
TIDY_OFF="com.amazon.gamehub com.amazon.tahoe com.amazon.shoptv.client com.amazon.shoptv.firetv.client com.amazon.minitv.android.app com.amazon.bueller.music com.amazon.bueller.photos"
# tidy, only hidden from Glass: nothing changes on the system (Luna, Amazon's content-discovery tile)
TIDY_HIDE="com.amazon.spiderpork,com.amazon.vizzini.ftvcds"

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }

die()  { printf '\n\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

brew_prefix() { command -v brew >/dev/null 2>&1 || die "Homebrew is missing. Install it from https://brew.sh, then run this again."; brew --prefix; }

java_env() {
  local jdk; jdk="$(brew_prefix)/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  [ -d "$jdk" ] || die "JDK 17 not found. Run: bash firetv.sh setup <stick-ip>"
  export JAVA_HOME="$jdk"
  export PATH="$JAVA_HOME/bin:$PATH"
}

need_glass() { [ -x "$GLASS/tools/tv" ] && [ -d "$GLASS/.venv" ] || die "Not set up yet. Run: bash firetv.sh setup <stick-ip>"; }

tv() { "$GLASS/tools/tv" "$@" </dev/null | tr -d '\r'; }

cmd_setup() {
  local ip="${1:-}"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Give the stick's IP, e.g. ./firetv.sh setup 192.168.1.23 (Settings > My Fire TV > About > Network)"
  local bp; bp="$(brew_prefix)"

  say "Installing tools with Homebrew (Python, Git, JDK 17, Android command-line tools)"
  brew install python git openjdk@17 || die "brew install failed"
  brew install --cask android-commandlinetools || die "brew could not install android-commandlinetools"
  java_env

  say "Installing the Android SDK pieces the launcher build needs (~500 MB, once)"
  local sdkm="$bp/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager"
  [ -x "$sdkm" ] || sdkm="$(command -v sdkmanager || true)"
  [ -n "$sdkm" ] || die "sdkmanager not found after installing android-commandlinetools"
  yes | "$sdkm" --sdk_root="$SDK" --licenses >/dev/null 2>&1
  "$sdkm" --sdk_root="$SDK" "platforms;android-35" "build-tools;35.0.0" || die "sdkmanager failed"

  say "Fetching the Glass launcher"
  if [ ! -d "$GLASS/.git" ]; then
    git clone -q "$GLASS_REPO" "$GLASS" || die "git clone failed"
  fi
  git -C "$GLASS" checkout -q "$GLASS_COMMIT" 2>/dev/null || echo "(could not pin the tested version; using the latest)"

  say "Patching it for Fire OS 7 (Android 9): minSdk 30 -> 28"
  perl -pi -e 's/^(\s*)minSdk 30\b.*$/${1}minSdk 28          \/\/ patched for Fire OS 7 (Android 9)/' "$GLASS/launcher/app/build.gradle"
  grep -q 'minSdk 28' "$GLASS/launcher/app/build.gradle" || die "The patch did not apply; the launcher's build file has changed."
  echo "sdk.dir=$SDK" > "$GLASS/launcher/local.properties"
  # Gradle's own download redirects to release-assets.githubusercontent.com, which some ISPs block: use a mirror
  sed -i '' 's#^distributionUrl=.*#distributionUrl=https\\://mirrors.cloud.tencent.com/gradle/gradle-8.14.3-bin.zip#' "$GLASS/launcher/gradle/wrapper/gradle-wrapper.properties"

  say "Setting up the Wi-Fi ADB client"
  "$bp/bin/python3" -m venv "$GLASS/.venv" || die "could not create the Python environment"
  "$GLASS/.venv/bin/pip" install -q adb-shell || die "pip install adb-shell failed"
  echo "$ip" > "$GLASS/.tv-ip"

  say "Connecting to the stick at $ip"
  echo "Look at the TV now: on 'Allow USB debugging?' tick 'Always allow from this computer' and press OK."
  echo "If your Mac asks to let Python find devices on the local network, click Allow."
  local info; info="$(tv shell 'getprop ro.product.model; getprop ro.build.version.name; getprop ro.build.version.release')" \
    || die "Could not reach the stick. Check the IP, that ADB debugging is on, and that the Mac is on the same Wi-Fi."
  echo "$info"
  say "Setup done. Next: ./firetv.sh scan"
}

apply_patches() {
  local src="$GLASS/launcher/app/src/main/java/com/ivantrj/glasslauncher"
  # Start every build from Glass's original files, then apply all patches fresh (no leftovers from older builds)
  git -C "$GLASS" checkout -q -- launcher/app/build.gradle launcher/app/src/main/java/com/ivantrj/glasslauncher/HomeActivity.java \
      launcher/app/src/main/java/com/ivantrj/glasslauncher/AppLoader.java \
      launcher/app/src/main/res/layout/activity_home.xml launcher/app/src/main/res/xml/home_button_service.xml || die "could not reset Glass's source"
  perl -pi -e 's/^(\s*)minSdk 30\b.*$/${1}minSdk 28          \/\/ patched for Fire OS 7 (Android 9)/' "$GLASS/launcher/app/build.gradle"
  grep -q 'minSdk 28' "$GLASS/launcher/app/build.gradle" || die "Fire OS 7 patch did not apply"
  [ -f "$KIT/patches/HomeButtonService.java" ] || die "Missing patches/ folder in the kit"
  cp "$KIT/patches/HomeButtonService.java" "$KIT/patches/GlassState.java" "$KIT/patches/GlassConfig.java" "$KIT/patches/SettingsMenu.java" "$KIT/patches/GlassOrder.java" "$src/" || die "could not copy the patch files"
  "$GLASS/.venv/bin/python" - "$src/HomeActivity.java" <<'PY' || die "HomeActivity.java changed upstream; the patch does not fit"
import sys
p = sys.argv[1]
s = open(p).read()
if "GlassState.set" not in s:
    a = "        stopped = false;\n        IntentFilter timeFilter"
    b = "        stopped = true;\n        unregisterReceiver(timeReceiver);"
    assert a in s and b in s
    s = s.replace(a, "        stopped = false;\n        GlassState.set(true);\n        IntentFilter timeFilter", 1)
    s = s.replace(b, "        stopped = true;\n        GlassState.set(false);\n        unregisterReceiver(timeReceiver);", 1)
    open(p, "w").write(s)
PY
  KIT_PATCHES="$KIT/patches" "$GLASS/.venv/bin/python" - "$GLASS/launcher" <<'PY' || die "Glass's build files changed upstream; the speed patch does not fit"
import sys, os
root = sys.argv[1]
g = os.path.join(root, "app/build.gradle"); s = open(g).read()
if "debuggable false" not in s:
    a = "    lint { abortOnError false; checkReleaseBuilds false }"
    assert a in s
    s = s.replace(a, "    buildTypes { debug { debuggable false; jniDebuggable false } } // faster: lets Android pre-compile Glass\n\n" + a, 1)
    open(g, "w").write(s)
h = os.path.join(root, "app/src/main/java/com/ivantrj/glasslauncher/HomeActivity.java"); t = open(h).read()
if "GlassConfig.apply" not in t:
    b = '        if (intent.getBooleanExtra("reload", false)) { // sent by configure.sh'
    assert b in t
    t = t.replace(b, "        GlassConfig.apply(this, intent);\n" + b, 1)
    open(h, "w").write(t)
# Lighter rendering: the window already paints black, so the root's own black background is a wasted full-screen layer
lay = os.path.join(root, "app/src/main/res/layout/activity_home.xml"); x = open(lay).read()
dup = '    android:id="@+id/root"\n    android:layout_width="match_parent"\n    android:layout_height="match_parent"\n    android:background="@android:color/black"\n'
if dup in x:
    x = x.replace(dup, dup.replace('    android:background="@android:color/black"\n', ''), 1)
    open(lay, "w").write(x)
# Lightweight: the glow behind the dock switches colour instantly instead of a 500 ms half-screen repaint on every move
ha = os.path.join(root, "app/src/main/java/com/ivantrj/glasslauncher/HomeActivity.java"); z = open(ha).read()
g = "    private void animateGlow(int color, boolean animate) {\n"
if g in z and "animate = false; // lightweight" not in z:
    z = z.replace(g, g + "        animate = false; // lightweight: no glow fade\n", 1)
    open(ha, "w").write(z)
# Settings: Amazon's main Settings grid lives inside its home screen (the redirect would bounce it),
# so Glass's Settings button opens a menu of the individual settings pages, which are separate screens
mo = "    private void openMenu() {\n        menuEntries = InputsMenu.load(this);\n"
if mo in z:
    z = z.replace(mo, "    private void openMenu() { openMenu(InputsMenu.load(this)); }\n\n    private void openMenu(List<InputsMenu.Entry> entries) {\n        menuEntries = entries;\n", 1)
z = z.replace("        View pill = pills[PILL_INPUTS];\n", "        View pill = pills[topIdx];\n", 1)
z = z.replace("            else launch(new Intent(Settings.ACTION_SETTINGS));", "            else openMenu(SettingsMenu.load(this));", 1)
open(ha, "w").write(z)
# Move mode: Menu on a tile offers Move / App info; arrows move it, OK places, Back cancels; order is saved
mm = open(os.environ["KIT_PATCHES"] + "/move-mode.java.txt").read()
fa = "    private AppInfo focusedApp() {\n"
if "MOVE_ACTION" not in z:
    z = z.replace(fa, mm + fa, 1)
    z = z.replace("        if (event.getAction() != KeyEvent.ACTION_DOWN) return true;\n        if (menuOpen) {",
                  "        if (event.getAction() != KeyEvent.ACTION_DOWN) return true;\n        if (moving && !menuOpen) { moveKey(key); return true; }\n        if (menuOpen) {", 1)
    z = z.replace("            case KeyEvent.KEYCODE_MENU: openAppInfo(); break;", "            case KeyEvent.KEYCODE_MENU: openTileMenu(); break;", 1)
    z = z.replace("    private void launch(Intent intent) {\n        try {", "    private void launch(Intent intent) {\n        if (MOVE_ACTION.equals(intent.getAction())) { startMove(); return; }\n        try {", 1)
    z = z.replace("        GlassState.set(false);\n", "        GlassState.set(false);\n        if (moving) endMove(false); // leaving Glass mid-move cancels it\n", 1)
    open(ha, "w").write(z)
al = os.path.join(root, "app/src/main/java/com/ivantrj/glasslauncher/AppLoader.java"); q = open(al).read()
srt = "        result.grid.sort((a, b) -> collator.compare(a.label, b.label));\n"
if "GlassOrder.apply" not in q:
    q = q.replace(srt, srt + "        GlassOrder.apply(context, result.grid);\n", 1)
    open(al, "w").write(q)
# Grid wraps at row edges: Left on a row's first tile goes to the previous tile, Right on the last goes to the next
z = open(ha).read()
z = z.replace("        else if (zone == GRID && gridIdx % COLUMNS > 0) gridIdx--;", "        else if (zone == GRID && gridIdx > 0) gridIdx--;", 1)
z = z.replace("        else if (zone == GRID && gridIdx % COLUMNS < COLUMNS - 1 && gridIdx + 1 < gridApps.size()) gridIdx++;", "        else if (zone == GRID && gridIdx + 1 < gridApps.size()) gridIdx++;", 1)
open(ha, "w").write(z)
# No key-event filtering: the remote's keys never pass through Glass
svc = os.path.join(root, "app/src/main/res/xml/home_button_service.xml"); y = open(svc).read()
y = y.replace('android:accessibilityFlags="flagRequestFilterKeyEvents"', 'android:accessibilityFlags="flagDefault"')
y = y.replace('android:canRequestFilterKeyEvents="true"', 'android:canRequestFilterKeyEvents="false"')
open(svc, "w").write(y)
PY
  echo "Patch applied: Home now brings Glass forward without Fire OS 7's 5 second hold (if the stick allows it)."
}

cmd_launcher() {
  need_glass; java_env
  apply_patches
  # Let Java use the Mac's own network/proxy settings, like curl and brew do
  export JAVA_TOOL_OPTIONS="-Djava.net.useSystemProxies=true"
  local zip="$KIT/gradle-8.14.3-bin.zip" props="$GLASS/launcher/gradle/wrapper/gradle-wrapper.properties" u
  if ! unzip -tq "$zip" >/dev/null 2>&1; then
    say "Downloading Gradle 8.14.3 with curl"
    for u in https://services.gradle.org/distributions/gradle-8.14.3-bin.zip \
             https://mirrors.cloud.tencent.com/gradle/gradle-8.14.3-bin.zip \
             https://mirrors.aliyun.com/gradle/distributions/v8.14.3/gradle-8.14.3-bin.zip; do
      echo "trying $u"
      curl -fL --connect-timeout 15 -o "$zip" "$u" && unzip -tq "$zip" >/dev/null 2>&1 && break
      rm -f "$zip"
    done
    [ -f "$zip" ] || die "Could not download Gradle from any source. Run: curl -sI https://services.gradle.org | head -1 ; scutil --dns | grep nameserver | head -3   and paste the output."
  fi
  # Point the build at the local copy so Java never has to download it
  sed -i '' "s#^distributionUrl=.*#distributionUrl=file\\:$zip#" "$props"
  say "Building and installing the Glass launcher (first build downloads libraries, a few minutes)"
  (cd "$GLASS" && ./install.sh) || die "The launcher build or install failed. Copy the error into the chat."
  cmd_homekey off >/dev/null; sleep 2; cmd_homekey on >/dev/null   # make Android rebind the redirect after the reinstall
  say "Done. Press Home: Amazon's screen flashes for a moment, then Glass appears."
  echo "Choose your dock next: ./firetv.sh apps   then   ./firetv.sh dock pkg1 pkg2 pkg3 pkg4"
}

cmd_install() {
  need_glass; java_env
  local snap="$KIT/backup/install-before.txt" first=0
  say "Clean install: Glass home screen + safe speed settings + ad-blocking (no Amazon packages are switched off)"
  if [ ! -f "$snap" ]; then
    {
      echo "window $(tv shell 'settings get global window_animation_scale' | tr -d '\r\n')"
      echo "transition $(tv shell 'settings get global transition_animation_scale' | tr -d '\r\n')"
      echo "animator $(tv shell 'settings get global animator_duration_scale' | tr -d '\r\n')"
      echo "autoplay $(tv shell 'settings get global com.amazon.tv.settings.featured_item_video_enabled' | tr -d '\r\n')"
      echo "netflixbg $(tv shell 'cmd appops get com.netflix.ninja RUN_ANY_IN_BACKGROUND' | grep -o -E 'allow|ignore|deny|default' | head -1)"
      echo "dnsmode $(tv shell 'settings get global private_dns_mode' | tr -d '\r\n')"
      echo "dnshost $(tv shell 'settings get global private_dns_specifier' | tr -d '\r\n')"
    } > "$snap"
    echo "Saved current settings for rollback: backup/install-before.txt"
    first=1
  fi
  say "1/4 Building and installing Glass"
  # Never try to switch off Amazon's launcher (Fire OS refuses anyway; this keeps the install free of any package disabling)
  sed -i '' 's#"\$TV" shell "pm disable-user --user 0 com.amazon.tv.launcher 2>&1"#echo "skipped: Amazon launcher stays on"#' "$GLASS/install.sh"
  cmd_launcher
  tv shell "cmd package compile -m speed -f $GLASS_PKG" >/dev/null
  if [ "$first" = 1 ]; then
    say "2/4 Setting your dock"
    cmd_dock $DOCK_DEFAULT
  else
    say "2/4 Keeping your dock and app order as you arranged them"
  fi
  say "3/4 Speed settings"
  tv shell 'settings put global window_animation_scale 0.5; settings put global transition_animation_scale 0.5; settings put global animator_duration_scale 0.5' >/dev/null
  tv shell 'v=$(settings get global com.amazon.tv.settings.featured_item_video_enabled); [ "$v" != null ] && settings put global com.amazon.tv.settings.featured_item_video_enabled 0; true' >/dev/null
  tv shell 'cmd appops set com.netflix.ninja RUN_ANY_IN_BACKGROUND ignore' >/dev/null
  echo "  animations half length, featured autoplay off, Netflix can't run in the background"
  cmd_adblock
  say "4/4 Checking"
  tv shell "dumpsys package $GLASS_PKG | grep -m1 -E 'pkgFlags'; settings get secure enabled_accessibility_services; pm list packages -d"
  say "Installed. Now restart the stick (Settings > My Fire TV > Restart), then check the remote and the Home button. Roll back any time: bash firetv.sh uninstall"
}

cmd_uninstall() {
  need_glass; local snap="$KIT/backup/install-before.txt" k v
  say "Rolling back the clean install"
  if [ -f "$snap" ]; then
    while read -r k v; do
      case "$k" in
        window)     [ "$v" = null ] && tv shell 'settings delete global window_animation_scale' >/dev/null || tv shell "settings put global window_animation_scale $v" >/dev/null ;;
        transition) [ "$v" = null ] && tv shell 'settings delete global transition_animation_scale' >/dev/null || tv shell "settings put global transition_animation_scale $v" >/dev/null ;;
        animator)   [ "$v" = null ] && tv shell 'settings delete global animator_duration_scale' >/dev/null || tv shell "settings put global animator_duration_scale $v" >/dev/null ;;
        autoplay)   [ "$v" = null ] || tv shell "settings put global com.amazon.tv.settings.featured_item_video_enabled $v" >/dev/null ;;
        netflixbg)  tv shell "cmd appops set com.netflix.ninja RUN_ANY_IN_BACKGROUND ${v:-allow}" >/dev/null ;;
        dnsmode)    [ "$v" = null ] && tv shell 'settings delete global private_dns_mode' >/dev/null || tv shell "settings put global private_dns_mode $v" >/dev/null ;;
        dnshost)    [ "$v" = null ] && tv shell 'settings delete global private_dns_specifier' >/dev/null || tv shell "settings put global private_dns_specifier $v" >/dev/null ;;
      esac
    done < "$snap"
    rm -f "$snap"
  fi
  if [ -f "$KIT/backup/tidy-applied.txt" ]; then
    while read -r k; do tv shell "pm enable --user 0 $k" >/dev/null; echo "  back on: $k"; done < "$KIT/backup/tidy-applied.txt"
    rm -f "$KIT/backup/tidy-applied.txt"
  fi
  tv shell 'settings delete secure enabled_accessibility_services; settings put secure accessibility_enabled 0' >/dev/null
  tv shell 'cmd package set-home-activity com.amazon.tv.launcher/.ui.HomeActivity_vNext' >/dev/null
  tv shell "pm uninstall $GLASS_PKG" 2>&1 | tail -1
  say "Rolled back: Glass removed, ad-blocking off, Amazon's home and all settings as they were."
}

cmd_tidy() {
  need_glass; local rec="$KIT/backup/tidy-applied.txt" p out
  say "Switching off apps you don't use (all were off before through a restart with the remote working)"
  for p in $TIDY_OFF; do
    printf '  %-40s ' "$p"
    if ! tv shell "pm path $p" | grep -q package:; then echo "not installed"; continue; fi
    out="$(tv shell "pm disable-user --user 0 $p 2>&1")"
    case "$out" in *"new state: disabled"*) echo "off"; grep -qx "$p" "$rec" 2>/dev/null || echo "$p" >> "$rec" ;; *) echo "left alone ($out)" ;; esac
  done
  say "Hiding Luna and 'What should I watch' from Glass (no system change)"
  tv shell "am start -n $GLASS_PKG/.HomeActivity --esa hidden $TIDY_HIDE --ez reload true" >/dev/null
  echo "  hidden: ${TIDY_HIDE//,/ }"
  say "Done. Undo: bash firetv.sh uninstall (switches them back on and shows everything)"
}

cmd_dock() {
  need_glass; [ $# -gt 0 ] || die "Give 1 to 6 package names, or 'reset'"
  local list; list="$(IFS=,; echo "$*")"
  tv shell "am start -n $GLASS_PKG/.HomeActivity --esa dock $list --ez reload true" >/dev/null
  echo "Dock set: $*"
}

cmd_apps() { need_glass; tv shell 'pm list packages -3' | sed 's/^package://' | sort; }

cmd_homekey() {
  need_glass
  local svc="$GLASS_PKG/$GLASS_PKG.HomeButtonService" cur rest
  cur="$(tv shell 'settings get secure enabled_accessibility_services')"
  if [ "${1:-}" = "off" ]; then
    rest="$(printf '%s' "$cur" | tr ':' '\n' | grep -v "^$svc\$" | grep -v '^null$' | paste -sd: -)"
    if [ -z "$rest" ]; then tv shell 'settings delete secure enabled_accessibility_services' >/dev/null
    else tv shell "settings put secure enabled_accessibility_services '$rest'" >/dev/null; fi
    say "Home now opens Amazon's home instantly. Glass is an app: find it under Apps and add it to Favourites."
  else
    case "$cur" in
      *"$svc"*) ;;
      null|"") tv shell "settings put secure enabled_accessibility_services $svc" >/dev/null ;;
      *) tv shell "settings put secure enabled_accessibility_services '$cur:$svc'" >/dev/null ;;
    esac
    tv shell 'settings put secure accessibility_enabled 1' >/dev/null
    say "Home now brings up Glass."
  fi
}

cmd_adblock() {
  need_glass
  if [ "${1:-on}" = "off" ]; then
    say "Switching back to normal DNS"
    tv shell 'settings put global private_dns_mode opportunistic' >/dev/null
    tv shell 'settings delete global private_dns_specifier' >/dev/null
    echo "Done."
    return
  fi
  say "Switching on AdGuard DNS ($DNS_HOST) for the whole stick"
  tv shell "settings put global private_dns_specifier $DNS_HOST" >/dev/null
  tv shell 'settings put global private_dns_mode hostname' >/dev/null
  echo "private_dns_mode = $(tv shell 'settings get global private_dns_mode')"
  echo "Checking that ad servers are now blocked..."
  sleep 3
  local host r blocked=0 total=0
  for host in aax.amazon-adsystem.com ad.doubleclick.net; do
    total=$((total+1))
    r="$(tv shell "ping -c 1 -W 2 $host 2>&1 | head -1")"
    case "$r" in
      *"(0.0.0.0)"*|*"(127.0.0.1)"*|*"unknown host"*) echo "  blocked:     $host"; blocked=$((blocked+1)) ;;
      *) echo "  NOT blocked: $host   ($r)" ;;
    esac
  done
  if [ "$blocked" -eq "$total" ]; then
    say "Ad-blocking works. Restart the stick (Settings > My Fire TV > Restart) to clear ads it already cached."
  else
    say "Some ad servers still get through. Use the manual way in README.md (static DNS in the Wi-Fi settings)."
  fi
}

cmd_state() {
  need_glass; mkdir -p "$KIT/backup"; local f="$KIT/backup/state.txt"
  say "Waking the stick and checking what's on screen"
  tv shell 'input keyevent KEYCODE_WAKEUP' >/dev/null; sleep 3
  {
    echo "## power";  tv shell 'dumpsys power | grep -E "mWakefulness=|Display Power: state|mHoldingDisplaySuspendBlocker"'
    echo "## focus";  tv shell 'dumpsys window windows | grep -E "mCurrentFocus|mFocusedApp"'
    echo "## home redirect"; tv shell 'settings get secure enabled_accessibility_services'
    echo "## crashes since boot (last 60 lines)"; tv shell 'logcat -b crash -d | tail -60'
    echo "## app-not-responding / crash dialogs in the last 10 minutes"; tv shell 'logcat -d -v time -t 2000 | grep -E "FATAL EXCEPTION|ANR in|Process: |has died|Force finishing|AppErrorDialog|crash" | tail -40'
  } > "$f" 2>&1
  "$GLASS/tools/tv" screencap "$KIT/backup/state.png" </dev/null >/dev/null 2>&1
  cmd_speedcheck state >/dev/null
  grep -E "Total frames|Janky|90th|95th|99th" "$KIT/backup/speed-state.txt"
  say "Saved backup/state.txt and backup/state.png. Tell Claude it's done."
}

cmd_speedcheck() {
  need_glass; mkdir -p "$KIT/backup"; local f="$KIT/backup/speed-${1:-before}.txt" G="$GLASS_PKG/.HomeActivity"
  say "Measuring the stick (read-only, the TV will move through Glass for ~20 seconds)"
  {
    echo "## memory";    tv shell 'grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree" /proc/meminfo'
    echo "## storage";   tv shell 'df -h /data | tail -1'
    echo "## animation scales (window, transition, animator)"
    tv shell 'settings get global window_animation_scale; settings get global transition_animation_scale; settings get global animator_duration_scale'
    echo "## glass build flags"; tv shell "dumpsys package $GLASS_PKG | grep -m2 -E 'pkgFlags|flags='"
    echo "## biggest processes (PSS)"; tv shell 'dumpsys meminfo | sed -n "/Total PSS by process/,/Total PSS by OOM/p" | head -18'
    echo "## glass smoothness test"
    tv shell "am start -n $G >/dev/null; sleep 2; dumpsys gfxinfo $GLASS_PKG reset >/dev/null; for k in RIGHT RIGHT RIGHT RIGHT DOWN RIGHT RIGHT RIGHT DOWN LEFT LEFT UP UP LEFT LEFT; do input keyevent DPAD_\$k; sleep 0.4; done; dumpsys gfxinfo $GLASS_PKG | grep -E 'Total frames|Janky frames|percentile|Number Slow|Number High input|Number Missed'"
  } > "$f" 2>&1
  cat "$f"
  say "Saved backup/$(basename "$f"). Tell Claude it's done."
}

cmd_gaptest() {
  need_glass; mkdir -p "$KIT/backup"
  local raw="$KIT/backup/gaptest-raw.txt" out="$KIT/backup/gaptest.txt"
  local A="com.android.providers.downloads.ui/.DownloadList" G="$GLASS_PKG/.HomeActivity"
  : > "$raw"

  say "Checking what the shell is allowed to do"
  { echo "## shell permissions"
    tv shell 'dumpsys package com.android.shell | grep -i -E "STOP_APP_SWITCHES|START_ANY_ACTIVITY|REORDER_TASKS"' ; } >> "$raw"

  say "Test 1 of 2: can a shell command open Glass straight after Home? (Home redirect off for this test)"
  cmd_homekey off >/dev/null; sleep 2
  { echo "## test1 shell am start"
    tv shell "am start -n $G >/dev/null; sleep 3; am start -n $A >/dev/null; sleep 3; logcat -c; log -t GlassGap 'MARK test1 shell-start-after-home'; input keyevent KEYCODE_HOME; am start -W -n $G; sleep 7; logcat -b main -b events -d -v time -s GlassGap:I am_resume_activity:I" ; } >> "$raw"

  say "Test 2 of 2: Home with the new redirect on (this is the real fix)"
  cmd_homekey on >/dev/null; sleep 3
  { echo "## test2 service"
    tv shell "am start -n $G >/dev/null; sleep 3; am start -n $A >/dev/null; sleep 3; logcat -c; log -t GlassGap 'MARK test2 redirect-after-home'; input keyevent KEYCODE_HOME; sleep 9; logcat -b main -b events -d -v time -s GlassGap:I am_resume_activity:I" ; } >> "$raw"

  tv shell "am start -n $G" >/dev/null
  {
    echo "=== RESULT ==="
    sed -n '/^## shell permissions/,/^## test1/p' "$raw" | grep -v '^## test1'
    echo "-- test 1 output of am start -W:"
    sed -n '/^## test1/,/^## test2/p' "$raw" | grep -E "Warning|Status|Error|TotalTime|ThisTime|WaitTime" 
    echo "-- timing, test 1 then test 2:"
    sed -n '/^## test1/,$p' "$raw" | grep -E "^[0-9][0-9]-[0-9][0-9] " > "$KIT/backup/.gaplines.txt"
    "$GLASS/.venv/bin/python" "$KIT/tools/gapsummary.py" "$KIT/backup/.gaplines.txt"
  } > "$out" 2>&1
  cat "$out"
  say "Saved backup/gaptest.txt and backup/gaptest-raw.txt. Tell Claude it's done."
}

cmd_gaplog() {
  need_glass; mkdir -p "$KIT/backup"
  if [ "${1:-}" = "clear" ]; then tv shell 'logcat -c; log -t GlassGap "MARK real-remote-test"' >/dev/null; echo "Log cleared. Now open an app, press Home on the REAL remote, wait 8 seconds, then run ./firetv.sh gaplog"; return; fi
  tv shell 'logcat -b main -b events -d -v time -s GlassGap:I am_resume_activity:I' > "$KIT/backup/gaplog.txt"
  "$GLASS/.venv/bin/python" "$KIT/tools/gapsummary.py" "$KIT/backup/gaplog.txt" | tee "$KIT/backup/gaplog-summary.txt"
  say "Saved backup/gaplog.txt. Tell Claude it's done."
}

cmd_investigate() {
  need_glass
  local d="$KIT/backup/investigate" G="$GLASS_PKG/.HomeActivity" comp
  mkdir -p "$d"
  say "Thorough check of the stick: about 5 minutes. Don't touch the remote until it says Done - the TV will open and close apps by itself."

  say "1/8 System, processor and temperature"
  tv shell 'getprop ro.product.model; getprop ro.build.version.name; getprop ro.build.version.release; uptime; cat /proc/loadavg; wm size; wm density; echo "## cpu"; grep -E "^processor|Hardware|CPU part|CPU implementer" /proc/cpuinfo; for c in /sys/devices/system/cpu/cpu[0-9]*; do echo "$c online=$(cat $c/online 2>/dev/null) gov=$(cat $c/cpufreq/scaling_governor 2>/dev/null) cur=$(cat $c/cpufreq/scaling_cur_freq 2>/dev/null) max=$(cat $c/cpufreq/scaling_max_freq 2>/dev/null) hwmax=$(cat $c/cpufreq/cpuinfo_max_freq 2>/dev/null)"; done; echo "## devfreq"; for f in /sys/class/devfreq/*; do echo "$f cur=$(cat $f/cur_freq 2>/dev/null) max=$(cat $f/max_freq 2>/dev/null) gov=$(cat $f/governor 2>/dev/null)"; done; echo "## thermal"; for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type 2>/dev/null) $(cat $z/temp 2>/dev/null)"; done; for z in /sys/class/thermal/cooling_device*; do echo "$(cat $z/type 2>/dev/null) cur=$(cat $z/cur_state 2>/dev/null) max=$(cat $z/max_state 2>/dev/null)"; done' > "$d/system.txt" 2>&1

  say "2/8 Memory, swapping and log spam (the stick sits idle for 20 seconds)"
  tv shell 'cat /proc/meminfo; echo "## swaps"; cat /proc/swaps; echo "## zram mm_stat"; cat /sys/block/zram0/mm_stat 2>/dev/null; echo "## lmk"; cat /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null; getprop | grep -i -E "lmk|low_ram|zram|swap"; echo "## vmstat start"; grep -E "^(pswpin|pswpout|pgmajfault|allocstall[a-z_]*|pgsteal_kswapd[a-z_]*|pgsteal_direct[a-z_]*|workingset_refault) " /proc/vmstat; logcat -c; sleep 20; echo "## vmstat after 20s"; grep -E "^(pswpin|pswpout|pgmajfault|allocstall[a-z_]*|pgsteal_kswapd[a-z_]*|pgsteal_direct[a-z_]*|workingset_refault) " /proc/vmstat; echo "## log lines in 20s idle, by tag"; logcat -d -v brief | sed -E "s/\(.*//" | sort | uniq -c | sort -rn | head -30; echo "## crash buffer"; logcat -b crash -d | tail -40' > "$d/memory-idle.txt" 2>&1

  say "3/8 Memory per app"
  tv shell 'dumpsys meminfo' > "$d/meminfo.txt" 2>&1
  tv shell "dumpsys meminfo $GLASS_PKG; echo '## amazon launcher'; dumpsys meminfo com.amazon.tv.launcher" > "$d/meminfo-launchers.txt" 2>&1

  say "4/8 What runs in the background"
  tv shell 'dumpsys cpuinfo; echo "## top"; top -b -n 1 | head -45; echo "## procstats last 3h"; dumpsys procstats --hours 3 | head -300; echo "## top alarms"; dumpsys alarm | sed -n "/Top Alarms/,/Alarm Stats/p" | head -40' > "$d/background.txt" 2>&1

  tv shell 'dumpsys activity services | grep -E "^ *\* ServiceRecord" | sed -E "s/.*ServiceRecord\{[0-9a-f]+ u[0-9]+ //; s/\}$//" | sort | uniq -c | sort -rn' > "$d/services.txt" 2>&1
  tv shell 'echo "## enabled"; pm list packages -e | sed "s/^package://" | sort; echo "## disabled"; pm list packages -d | sed "s/^package://" | sort; echo "## user-installed"; pm list packages -3 | sed "s/^package://" | sort' > "$d/packages-now.txt" 2>&1

  say "5/8 Storage, network and settings"
  tv shell 'df -h /data /system /cache 2>/dev/null; echo "## diskstats"; dumpsys diskstats; echo "## wifi"; dumpsys wifi | grep -m 6 -E "mWifiInfo|RSSI|Link speed|Frequency"; echo "## ping"; ping -c 4 -W 2 8.8.8.8 | tail -2; ping -c 2 -W 3 www.google.com | tail -2; echo "## settings"; settings get global window_animation_scale; settings get global transition_animation_scale; settings get global animator_duration_scale; settings get global always_finish_activities; settings get global private_dns_mode; getprop | grep -E "debug.hwui|ro.hwui|ro.config.low_ram|dalvik.vm.heap|dalvik.vm.dex2oat|ro.sf.lcd_density|pm.dexopt"; echo "## setting keys of interest"; (settings list global; settings list secure; settings list system) | grep -i -E "autoplay|usage|monitor|recommend|featured|telemetry|metrics|analytics|ads_|_ads|anim"' > "$d/storage-network-settings.txt" 2>&1
  tv shell 'dumpsys package dexopt' > "$d/dexopt.txt" 2>&1

  say "6/8 App start times (Prime Video, Netflix, YouTube, Hotstar are each closed and reopened)"
  : > "$d/launch.txt"
  for comp in com.amazon.firebat/com.amazon.pyrocore.IgnitionActivity com.netflix.ninja/.MainActivity com.amazon.firetv.youtube/dev.cobalt.app.MainActivity in.startv.hotstar/com.hotstar.MainActivity; do
    echo "## $comp" >> "$d/launch.txt"
    tv shell "am start -W -S -n $comp 2>&1 | grep -E 'Status|TotalTime|WaitTime|Warning|Error'; sleep 5; am start -n $G >/dev/null; sleep 3" >> "$d/launch.txt" 2>&1
  done

  say "7/8 Home screen smoothness, frame by frame"
  tv shell "am start -n $G >/dev/null; sleep 3; dumpsys gfxinfo $GLASS_PKG reset >/dev/null; for k in RIGHT RIGHT RIGHT DOWN RIGHT RIGHT DOWN LEFT UP UP LEFT LEFT; do input keyevent DPAD_\$k; sleep 0.5; done; dumpsys gfxinfo $GLASS_PKG framestats" > "$d/glass-gfx.txt" 2>&1

  say "8/8 Screenshots of the home screen (normal, then with overdraw colouring)"
  "$GLASS/tools/tv" screencap "$d/glass.png" </dev/null >/dev/null 2>&1
  trap "\"$GLASS/tools/tv\" shell 'setprop debug.hwui.overdraw false; service call activity 1599295570' >/dev/null 2>&1" EXIT
  tv shell 'setprop debug.hwui.overdraw show; service call activity 1599295570 >/dev/null; sleep 1; input keyevent DPAD_RIGHT; sleep 1; input keyevent DPAD_LEFT; sleep 2' >/dev/null
  "$GLASS/tools/tv" screencap "$d/overdraw.png" </dev/null >/dev/null 2>&1
  tv shell 'setprop debug.hwui.overdraw false; service call activity 1599295570 >/dev/null; sleep 1; input keyevent DPAD_RIGHT; sleep 1; input keyevent DPAD_LEFT' >/dev/null
  trap - EXIT
  ls -la "$d"
  say "Done. Saved everything in backup/investigate/. Tell Claude it's done."
}

cmd_redirectcheck() {
  need_glass; local f="$KIT/backup/redirect.txt"
  say "Checking the Home redirect service, then restarting it"
  {
    echo "## before"; tv shell 'settings get secure enabled_accessibility_services; settings get secure accessibility_enabled'
    tv shell 'dumpsys accessibility | grep -i -E "glass|Bound services|Enabled services|Crashed" | head -15'
    echo "## glass process"; tv shell "pidof $GLASS_PKG || echo not running"
    echo "## glass crashes"; tv shell "logcat -b crash -d | grep -A12 -i glasslauncher | tail -40"
    echo "## glass log"; tv shell 'logcat -d -v time -s GlassGap:I | tail -20'
  } > "$f" 2>&1
  cmd_homekey off >/dev/null; sleep 2; cmd_homekey on >/dev/null; sleep 3
  {
    echo "## after restart"; tv shell 'dumpsys accessibility | grep -i -E "glass|Bound services|Enabled services" | head -10'
    tv shell 'logcat -d -v time -s GlassGap:I | tail -10'
  } >> "$f" 2>&1
  cat "$f"
  say "Saved backup/redirect.txt. Tell Claude it's done."
}

cmd_rescue() {
  need_glass; mkdir -p "$KIT/backup"; local f="$KIT/backup/rescue.txt"
  say "1/3 Reading the stick's state (about 20 seconds)"
  {
    echo "## uptime"; tv shell 'uptime'
    echo "## power"; tv shell 'dumpsys power | grep -E "mWakefulness=|Display Power: state"'
    echo "## focus"; tv shell 'dumpsys window windows | grep -E "mCurrentFocus|mFocusedApp"'
    echo "## activities"; tv shell 'dumpsys activity activities | grep -E "mResumedActivity|mFocusedActivity|Run #" | head -15'
    echo "## input devices"; tv shell 'dumpsys input | sed -n "/Event Hub State/,/Input Reader State/p" | grep -E "^ +-?[0-9]+: " | head -20'
    echo "## input dispatcher"; tv shell 'dumpsys input | grep -E "FocusedApplication|FocusedWindow|PendingEvent|InboundQueue|Waiting|timeout" | head -20'
    echo "## glass log"; tv shell 'logcat -d -v time -s GlassGap:I | tail -40'
    echo "## crash buffer"; tv shell 'logcat -b crash -d | tail -60'
    echo "## errors"; tv shell 'logcat -d -v time | grep -E "FATAL|ANR in|has died|Force finishing|Watchdog|not responding|Exception" | tail -50'
  } > "$f" 2>&1
  "$GLASS/tools/tv" screencap "$KIT/backup/rescue.png" </dev/null >/dev/null 2>&1
  say "2/3 Switching the Home redirect off and closing Glass"
  cmd_homekey off >/dev/null
  tv shell "am force-stop $GLASS_PKG" >/dev/null
  say "3/3 Done. Try the remote now. Tell Claude what the TV shows and whether the remote responds."
}

cmd_remote() {
  need_glass; mkdir -p "$KIT/backup"; local f="$KIT/backup/remote.txt"
  say "Reading the stick's Bluetooth and remote state (read-only, about 20 seconds)"
  {
    echo "## uptime"; tv shell 'uptime'
    echo "## bluetooth setting"; tv shell 'settings get global bluetooth_on'
    echo "## bluetooth manager"; tv shell 'dumpsys bluetooth_manager | head -150'
    echo "## input devices"; tv shell 'dumpsys input | sed -n "/Event Hub State/,/Input Reader State/p" | grep -E "^ +-?[0-9]+: " | head -20'
    echo "## remote-related packages (E=on, D=off)"
    tv shell 'for p in com.android.bluetooth com.amazon.device.blepa com.amazon.autopairservice com.amazon.accessoryconfigservice com.amazon.fireinputdevices com.amazon.device.bluetoothkeymaplib com.amazon.device.bluetoothpa com.amazon.tv.keypolicymanager com.amazon.tv.oobe com.amazon.tv.ffsprovisioneeclient com.amazon.whisperjoin.middleware.np com.amazon.tv.matter com.amazon.tv.mattercohost com.amazon.hedwig com.amazon.spiderpork com.amazon.recess com.amazon.cloud9; do if pm list packages -d | grep -qx "package:$p"; then echo "D $p"; elif pm list packages | grep -qx "package:$p"; then echo "E $p"; else echo "- $p"; fi; done'
    echo "## all disabled packages"; tv shell 'pm list packages -d | sed "s/package://" | sort'
    echo "## bluetooth / pairing log"; tv shell 'logcat -d -v time | grep -i -E "bluetooth|bt_|hidhost|hid_|pair|bond|remote|blepa|autopair|gatt|woble" | tail -120'
  } > "$f" 2>&1
  say "Saved backup/remote.txt. Tell Claude it's done."
}

cmd_key() {
  need_glass; [ $# -gt 0 ] || die "Use: bash firetv.sh key HOME | UP | DOWN | LEFT | RIGHT | OK | BACK | MENU (several allowed)"
  local k
  for k in "$@"; do
    case "$k" in
      UP|DOWN|LEFT|RIGHT) k="DPAD_$k" ;;
      OK|SELECT|CENTER) k="DPAD_CENTER" ;;
    esac
    tv shell "input keyevent KEYCODE_$k" >/dev/null; echo "pressed $k"
  done
  "$GLASS/tools/tv" screencap "$KIT/backup/screen-now.png" </dev/null >/dev/null 2>&1 && echo "Screenshot: backup/screen-now.png"
}

cmd_pairscreen() {
  need_glass; local f="$KIT/backup/pairscreen.txt" comp
  say "Finding Amazon's remote settings screen on the stick"
  tv shell 'input keyevent KEYCODE_WAKEUP' >/dev/null
  {
    echo "## settings activities about remotes / controllers / bluetooth"
    tv shell 'dumpsys package com.amazon.tv.settings.v2 | grep -i -E "Activity" | grep -i -E "controller|remote|bluetooth|pair|accessor" | grep -o "com.amazon.tv.settings.v2/[A-Za-z0-9_.$]*" | sort -u'
    echo "## intent actions with remote / controller"
    tv shell 'dumpsys package com.amazon.tv.settings.v2 | grep -i -E "Action: \".*(controller|remote|bluetooth|pair|accessor)" | sort -u | head -20'
  } > "$f" 2>&1
  cat "$f"
  comp="$(grep -m1 -i -E "remote" "$f" | grep -o "com.amazon.tv.settings.v2/[A-Za-z0-9_.$]*")"
  [ -z "$comp" ] && comp="$(grep -m1 -i -E "controller" "$f" | grep -o "com.amazon.tv.settings.v2/[A-Za-z0-9_.$]*")"
  if [ -n "$comp" ]; then
    echo "Opening $comp"; tv shell "am start -n '$comp'" 2>&1 | tail -2
  else
    echo "No direct screen found; opening main Settings"; tv shell 'am start -a android.settings.SETTINGS' 2>&1 | tail -2
  fi
  sleep 3
  "$GLASS/tools/tv" screencap "$KIT/backup/screen-now.png" </dev/null >/dev/null 2>&1
  say "Saved backup/pairscreen.txt and a screenshot. Tell Claude it's done."
}

cmd_resetall() {
  need_glass; local f="$KIT/backup/resetall.txt" p
  say "Putting the stick back to stock: everything this kit changed is undone"
  {
    echo "## 1. re-enable every package that is switched off (except NFC, which was off from the factory)"
    for p in $(tv shell 'pm list packages -d' | sed 's/^package://' | grep -v -x com.android.nfc); do
      printf '  %-50s ' "$p"; tv shell "pm enable --user 0 $p 2>&1" | tail -1
    done
    echo "## 2. settings back to defaults"
    tv shell 'settings put global window_animation_scale 1.0; settings put global transition_animation_scale 1.0; settings delete global animator_duration_scale; settings put global private_dns_mode opportunistic; settings delete global private_dns_specifier; cmd appops set com.netflix.ninja RUN_ANY_IN_BACKGROUND allow; wm size reset; wm density reset; settings put secure screensaver_enabled 1'
    echo "  animations, DNS, Netflix background, screen size, screensaver: default"
    echo "## 3. remove Glass and give Home back to Amazon"
    tv shell 'settings delete secure enabled_accessibility_services; settings put secure accessibility_enabled 0'
    tv shell 'pm enable --user 0 com.amazon.tv.launcher; pm enable --user 0 com.amazon.firehomestarter; cmd package set-home-activity com.amazon.tv.launcher/.ui.HomeActivity_vNext' 2>&1 | tail -1
    tv shell "pm uninstall $GLASS_PKG" 2>&1 | tail -1
    echo "## 4. still switched off now:"; tv shell 'pm list packages -d'
  } 2>&1 | tee "$f"
  say "Restarting the stick (about 2 minutes). Then press any remote button; if nothing, hold Home for 10 seconds."
  tv shell 'reboot' >/dev/null 2>&1 || true
  echo "If the stick didn't restart by itself, unplug its power for 10 seconds."
}

case "${1:-}" in
  setup)         shift; cmd_setup "$@" ;;
  install)       cmd_install ;;
  uninstall)     cmd_uninstall ;;
  tidy)          cmd_tidy ;;
  dock)          shift; cmd_dock "$@" ;;
  apps)          cmd_apps ;;
  homekey)       shift; cmd_homekey "$@" ;;
  adblock)       shift; cmd_adblock "$@" ;;
  state)         cmd_state ;;
  speedcheck)    shift; cmd_speedcheck "$@" ;;
  gaptest)       cmd_gaptest ;;
  gaplog)        shift; cmd_gaplog "$@" ;;
  investigate)   cmd_investigate ;;
  remote)        cmd_remote ;;
  key)           shift; cmd_key "$@" ;;
  pairscreen)    cmd_pairscreen ;;
  rescue)        cmd_rescue ;;
  redirectcheck) cmd_redirectcheck ;;
  resetall)      cmd_resetall ;;
  *) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
