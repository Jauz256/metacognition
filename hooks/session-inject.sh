#!/bin/bash
# session-inject.sh - prints the watchdog's last verdict when a Claude Code session starts.
#
# install.sh wires this as a SessionStart hook. It prints one line when the verdict is
# fresh, and one more when the timer has not run for a while. It never asks anything,
# never blocks, and needs nothing but bash.
APP="rule-drift-watchdog"
INTERVAL_MIN=30
DIR="${WATCHDOG_DIR:-$HOME/.claude/$APP}"
VERDICT="$DIR/verdict.txt"
RUN="node ~/.claude/$APP/bin/watchdog.mjs run"

if [ ! -f "$VERDICT" ]; then
  echo "$APP: no verdict yet. Run: $RUN"
  exit 0
fi

# File age in seconds. stat takes different flags on macOS and Linux.
MTIME=$(stat -f %m "$VERDICT" 2>/dev/null || stat -c %Y "$VERDICT" 2>/dev/null || echo 0)
NOW=$(date +%s)
AGE=$(( NOW - MTIME ))
if [ "$AGE" -gt $(( 2 * INTERVAL_MIN * 60 )) ]; then
  WHEN=$(date -r "$MTIME" "+%Y-%m-%d %H:%M" 2>/dev/null || date -d "@$MTIME" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown time")
  echo "$APP is STALE, last run $WHEN ($(( AGE / 60 )) min ago; the timer should run every $INTERVAL_MIN min). Run: $RUN"
fi

head -n 1 "$VERDICT"
exit 0
