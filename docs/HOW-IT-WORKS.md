# How it works

Everything runs from a Mac over ADB on Wi-Fi (port 5555), using the
[adb-shell](https://pypi.org/project/adb-shell/) Python package, because macOS Local Network privacy often blocks the stock
`adb` binary. Glass is built on the Mac with Gradle and the Android SDK, then installed and pre-compiled on the stick.

## The 5-second Home delay

Fire OS won't let a third-party launcher replace Amazon's home. `com.amazon.tv.launcher` is a protected package with
a priority-950 HOME filter. So Glass runs an accessibility service that watches for Amazon's home window and brings
Glass back on top.

On Fire OS 7 (Android 9) that took about **5 seconds** after every Home press. The stick's log showed why:

```
W/ActivityManager: Activity start request from 10104 stopped
```

Pressing Home calls `stopAppSwitches()`. For the next 5 seconds (`APP_SWITCH_DELAY_TIME`), any activity start from a caller
without `STOP_APP_SWITCHES` is held. The service's `startActivity()` waited out the full hold every time.

`ActivityManager.AppTask.moveToFront()` isn't subject to that check on Android 9, because it runs with the system's
identity. Glass's service now moves Glass's existing task to the front, and falls back to `startActivity()` only when
there's no task yet (the first launch after boot, when no hold is active). Measured on the stick:

| | Amazon home on screen → Glass in front |
|---|---|
| Before (`startActivity`) | 4.9–5.0 s |
| After (`moveToFront`), simulated Home | 0.23 s |
| After, real remote, coming from a heavy app | about 2 s |

`bash firetv.sh gaptest` reproduces these numbers.

## Settings

Fire OS 7 draws its main Settings grid **inside Amazon's home app**, as a tab of `HomeActivity_vNext`. Opening it from
Glass looked to the redirect like "Amazon's home appeared", so it bounced straight back. Pressing Home inside that grid
sends no window change and no `CLOSE_SYSTEM_DIALOGS` broadcast, so there's nothing to detect.

The individual settings pages are separate activities in `com.amazon.tv.settings.v2`, for example `NetworkActivity`,
`DisplayAndSoundsActivity` and `ControllersAndBluetoothActivity`. Glass's Settings button opens a menu of those, built only from
pages that are installed and exported. Home from any of them shows Amazon's home for a moment, and the redirect brings Glass back.

## Rendering

On a 4 × Cortex-A53 stick with a PowerVR GPU, frame timing showed Glass's own work at under 1 ms per frame. The slow
frames were spent waiting on the GPU: about 9 ms waiting for a free buffer, plus 12–15 ms of drawing. The Android overdraw view
showed the bottom half of the screen painted 3–5 times per frame. The changes:

- Glass's root view drew a black background on top of the window's black background. The duplicate is removed.
- The dock glow faded over 500 ms, rebuilding a half-screen radial gradient on every frame. It now switches colour
  instantly.
- Glass is built non-debuggable, so ART uses compiled code, and it's pre-compiled with `cmd package compile -m speed`.

## Input

The accessibility service doesn't request key filtering (`flagRequestFilterKeyEvents` is removed). It receives only
window-state events from `com.amazon.tv.launcher`, so remote presses never pass through it.

## Speed settings

All of these are reversible and saved before the first change:

- `window_animation_scale`, `transition_animation_scale`, `animator_duration_scale` set to 0.5
- `com.amazon.tv.settings.featured_item_video_enabled` set to 0 (Amazon home trailers)
- `RUN_ANY_IN_BACKGROUND ignore` for Netflix. On the test stick it held a background service at about 89 MB for half the time.
- Private DNS: `dns.adguard-dns.com`

## Patches

`apply_patches` in `firetv.sh` resets Glass's touched files to the pinned commit, then applies:

| File | Change |
|---|---|
| `build.gradle` | `minSdk 28` (Fire OS 7) and a non-debuggable debug build, keeping the signature |
| `HomeButtonService.java` | Replaced with the `moveToFront` redirect |
| `GlassState.java` | New: lets the redirect know whether Glass is on screen |
| `GlassConfig.java` | New: dock and hidden apps set by intent (`--esa dock …`) |
| `SettingsMenu.java` | New: the Settings menu |
| `GlassOrder.java`, `move-mode.java.txt` | New: Menu → Move and the saved order |
| `HomeActivity.java` | Hooks for all of the above, wrapping Left/Right, instant glow |
| `activity_home.xml` | Duplicate background removed |
| `home_button_service.xml` | Key filtering off |
