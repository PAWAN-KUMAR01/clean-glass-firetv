# Changelog

## 1.0.0 (2026-10-21)

First release, tested on a Fire TV Stick 3rd gen (AFTSSS), Fire OS 7.7.1.6.

- Glass home screen patched for Fire OS 7 (minSdk 28), built non-debuggable and pre-compiled.
- Home returns to Glass in under a second: `AppTask.moveToFront()` gets around Fire OS 7's 5-second app-switch hold.
- Settings button opens a menu of Amazon's settings pages, since the main Settings grid lives inside Amazon's home.
- Menu → Move to arrange tiles. The dock and grid order are saved.
- Left and Right wrap across grid rows.
- Lighter rendering: duplicate background removed, instant dock glow.
- Key filtering removed from the Home redirect, which now sees only window events.
- Safe speed settings, ad-blocking DNS, optional `tidy`, full `uninstall` rollback.
- Recovery commands that work without the remote: `key`, `pairscreen`, `rescue`, `redirectcheck`, `resetall`.
