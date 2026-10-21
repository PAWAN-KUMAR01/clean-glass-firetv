# Set it up with an AI coding assistant

Paste this into Claude Code, Codex, Gemini CLI or any assistant that can run commands on your Mac, and fill in the
two blanks.

---

I want to install Clean Glass (https://github.com/PAWAN-KUMAR01/clean-glass-firetv) on my Fire TV Stick.

- Stick model / Fire OS version: ______ (Settings → My Fire TV → About)
- Stick IP address: ______ (Settings → My Fire TV → About → Network)

ADB debugging is on and my Mac is on the same Wi-Fi. Please:

1. Clone the repo and run `bash firetv.sh setup <ip>`. Tell me when to accept the "Allow USB debugging?" prompt on the TV.
2. Run `bash firetv.sh install` and show me the result of each step.
3. Ask me which unused Amazon apps I want gone before running `bash firetv.sh tidy`. Don't switch off anything else.
4. Ask me to restart the stick and confirm that the remote and the Home button work. If the remote stops responding, use
   the recovery commands in the README (they run from the Mac) and walk me through Amazon's remote reset. Don't keep
   changing things.
5. Remind me to turn ADB debugging off at the end.

Rules: don't disable or uninstall Amazon system packages beyond `tidy`, don't root the stick, and keep everything
reversible with `bash firetv.sh uninstall`.

---

If your stick runs **Fire OS 8**, use upstream [Fire TV Glass](https://github.com/ivantrj/firetv-glass-launcher) instead.
These patches are written for Fire OS 7.
