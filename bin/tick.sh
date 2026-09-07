#!/bin/sh
# tick.sh - what the timer runs every 30 minutes: the watchdog, then the loop scan.
# The watchdog checks every rule in claims.tsv. The loop scan reads the mistake log and
# names the corrections you have typed 3 times or more, so they can become rules.
APP="rule-drift-watchdog"
HERE=$(cd "$(dirname "$0")" && pwd)
NODE=${NODE:-$(command -v node)}
"$NODE" "$HERE/watchdog.mjs" run --quiet
[ -f "$HERE/../hooks/loop-scan.mjs" ] && "$NODE" "$HERE/../hooks/loop-scan.mjs" --quiet
exit 0
