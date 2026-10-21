# Security

**ADB debugging.** While it's on, any device on your Wi-Fi can ask to connect to the stick. A connection still needs
the "Allow USB debugging?" prompt on the TV to be accepted. Turn ADB debugging off when you're not using this kit
(Settings → My Fire TV → Developer options).

**What the kit can do.** It runs `adb shell` commands as the stick's shell user. It can't root the stick or touch
other devices. The main install changes one app (Glass), a few settings and one app permission, all reversible with
`bash firetv.sh uninstall`.

**Network.** Ad-blocking uses AdGuard's public DNS (`dns.adguard-dns.com`), which then resolves the stick's DNS
lookups. `bash firetv.sh adblock off` reverts it.

**Reporting.** Please report security problems privately through GitHub's "Report a vulnerability" on this
repository, not in a public issue.
