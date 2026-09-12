---
description: Run the rule watchdog now and show which rules are red
allowed-tools: Bash(node *)
---

Run the watchdog once and report the result in plain words.

!`node "${CLAUDE_PLUGIN_ROOT}/bin/watchdog.mjs" run 2>&1 | head -40`

Read the output above. Say, in under 80 words: how many rules were checked, which ones are RED (name each), and the one command that fixes or explains each RED one. If there is no ledger yet, say that the rules file is missing and give the install command from the plugin README.
