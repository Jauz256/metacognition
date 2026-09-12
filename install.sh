#!/bin/bash
# install.sh - puts the watchdog in ~/.claude/<APP>/ and wires it up.
#
# What it does, in order:
#   1. copies bin/ and hooks/ into ~/.claude/<APP>/
#   2. copies claims.tsv there if you do not have one yet (never overwrites yours)
#   3. adds 3 hooks to ~/.claude/settings.json (backup first; your other hooks are kept):
#      SessionStart prints the last verdict; Stop + UserPromptSubmit feed the mistake log
#   4. runs the watchdog once and prints the first verdict
#   5. installs a timer: every 30 minutes the watchdog runs, then the loop scan
#      macOS: a launchd agent in ~/Library/LaunchAgents    Linux: one crontab line
#
# Usage:
#   bash install.sh                 install from a clone
#   curl -fsSL <raw url>/install.sh | bash     install without a clone (downloads the repo)
#   bash install.sh --dry-run       print what would happen, change nothing
#   bash install.sh --uninstall     remove the hooks, the timer and the code; keep your data
#   bash install.sh --no-hooks      code + rules + timer only (use after `claude plugin install metacognition`)
#
# Asks nothing. Needs node 18 or newer on PATH.
set -eu

APP="metacognition"
REPO="${WATCHDOG_REPO:-Jauz256/$APP}"   # GitHub owner/name; only used when not run from a clone
INTERVAL_MIN=30

DEST="$HOME/.claude/$APP"
SETTINGS="$HOME/.claude/settings.json"
PLIST_LABEL="local.$APP"
PLIST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

DRY=0
UNINSTALL=0
NOHOOKS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --no-hooks) NOHOOKS=1 ;;   # the Claude Code plugin already provides the 3 hooks
    -h|--help) sed -n '2,19p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
step() { if [ "$DRY" = 1 ]; then say "  would: $*"; else say "  $*"; fi; }

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux) OS=linux ;;
  *) OS=other ;;
esac

NODE=$(command -v node || true)
if [ -z "$NODE" ]; then
  say "node was not found on PATH. Install Node 18 or newer, then run this again." >&2
  exit 1
fi
if ! "$NODE" -e 'process.exit(parseInt(process.versions.node, 10) >= 18 ? 0 : 1)'; then
  say "node $("$NODE" --version) is too old. Node 18 or newer is needed." >&2
  exit 1
fi

# Merge or remove this tool's hooks in settings.json. Everything else in the file is left
# as it is. A file that does not parse stops the installer instead of being replaced.
# Three hooks: SessionStart prints the last verdict; Stop and UserPromptSubmit feed the
# mistake log (what the AI made, what you said next).
edit_settings() { # mode: check | add | remove
  "$NODE" - "$SETTINGS" "$DEST" "$APP" "$NODE" "$1" <<'EOF'
const fs = require('fs');
const [file, dest, app, node, mode] = process.argv.slice(2);
const wanted = [
  { event: 'SessionStart', command: `bash "${dest}/hooks/session-inject.sh"`, mark: `${app}/hooks/session-inject.sh`, timeout: 5 },
  { event: 'Stop', command: `${node} "${dest}/hooks/mistake-log.mjs"`, mark: `${app}/hooks/mistake-log.mjs`, timeout: 10 },
  { event: 'UserPromptSubmit', command: `${node} "${dest}/hooks/mistake-log.mjs"`, mark: `${app}/hooks/mistake-log.mjs`, timeout: 10 },
];
let settings = {};
if (fs.existsSync(file)) settings = JSON.parse(fs.readFileSync(file, 'utf8'));
if (!settings.hooks || typeof settings.hooks !== 'object') settings.hooks = {};
let allPresent = true;
for (const w of wanted) {
  if (!Array.isArray(settings.hooks[w.event])) settings.hooks[w.event] = [];
  const list = settings.hooks[w.event];
  const isMine = (h) => typeof h.command === 'string' && h.command.includes(w.mark);
  const present = list.some((m) => (m.hooks || []).some(isMine));
  if (!present) allPresent = false;
  if (mode === 'add' && !present) list.push({ hooks: [{ type: 'command', command: w.command, timeout: w.timeout }] });
  if (mode === 'remove') {
    for (const m of list) m.hooks = (m.hooks || []).filter((h) => !isMine(h));
    settings.hooks[w.event] = list.filter((m) => (m.hooks || []).length);
  }
  if (!settings.hooks[w.event].length) delete settings.hooks[w.event];
}
if (mode === 'check') { console.log(allPresent ? 'present' : 'absent'); process.exit(0); }
if (!Object.keys(settings.hooks).length) delete settings.hooks;
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
EOF
}

backup_settings() {
  if [ -f "$SETTINGS" ]; then
    BAK="$SETTINGS.bak-$APP-$(date +%Y%m%d-%H%M%S)"
    step "back up settings.json to $BAK"
    [ "$DRY" = 1 ] || cp "$SETTINGS" "$BAK"
  fi
}

# ------------------------------------------------------------------ uninstall

if [ "$UNINSTALL" = 1 ]; then
  say "$APP: uninstall"
  if [ "$OS" = mac ] && [ -f "$PLIST" ]; then
    step "unload and delete $PLIST"
    if [ "$DRY" = 0 ]; then launchctl unload "$PLIST" 2>/dev/null || true; rm -f "$PLIST"; fi
  elif [ "$OS" = linux ] && command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q "# $APP\$"; then
    step "remove the $APP line from crontab"
    if [ "$DRY" = 0 ]; then (crontab -l 2>/dev/null | grep -v "# $APP\$" || true) | crontab -; fi
  else
    step "no timer found, nothing to remove"
  fi
  if [ -f "$SETTINGS" ] && [ "$(edit_settings check)" = present ]; then
    backup_settings
    step "remove the 3 hooks from settings.json"
    [ "$DRY" = 1 ] || edit_settings remove
  else
    step "none of the 3 hooks found in settings.json, nothing to remove"
  fi
  step "delete $DEST/bin and $DEST/hooks"
  [ "$DRY" = 1 ] || rm -rf "$DEST/bin" "$DEST/hooks"
  say "kept your data: $DEST/claims.tsv, receipts.jsonl, verdict files. Delete the folder yourself if you want them gone."
  [ "$DRY" = 1 ] && say "dry run: nothing was changed."
  exit 0
fi

# ------------------------------------------------------------------ install

say "$APP: install into $DEST"

# Where do the files come from? A clone next to this script, or a download.
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/bin/watchdog.mjs" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -z "$SRC" ]; then
  URL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
  if [ "$DRY" = 1 ]; then
    step "download $URL to a temp folder"
  else
    TMP=$(mktemp -d)
    step "download $URL"
    curl -fsSL "$URL" | tar -xz -C "$TMP"
    SRC=$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    [ -f "$SRC/bin/watchdog.mjs" ] || { say "download did not contain bin/watchdog.mjs" >&2; exit 1; }
  fi
fi

# 1. code
step "copy bin/ and hooks/ to $DEST/"
if [ "$DRY" = 0 ]; then
  mkdir -p "$DEST/bin" "$DEST/hooks"
  cp -R "$SRC/bin/." "$DEST/bin/"
  cp -R "$SRC/hooks/." "$DEST/hooks/"
  chmod +x "$DEST/bin/"*.mjs "$DEST/bin/"*.sh "$DEST/hooks/"*.sh "$DEST/hooks/"*.mjs 2>/dev/null || true
fi

# 2. rules
if [ -f "$DEST/claims.tsv" ]; then
  step "keep your existing $DEST/claims.tsv (the example file goes to claims.example.tsv)"
  [ "$DRY" = 1 ] || cp "$SRC/claims.tsv" "$DEST/claims.example.tsv"
else
  step "copy the example claims.tsv to $DEST/claims.tsv"
  [ "$DRY" = 1 ] || cp "$SRC/claims.tsv" "$DEST/claims.tsv"
fi

# 3. hooks
if [ -f "$SETTINGS" ]; then
  if ! "$NODE" -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$SETTINGS" 2>/dev/null; then
    say "$SETTINGS is not valid JSON. Fix it first; nothing was changed." >&2
    exit 1
  fi
fi
if [ "$NOHOOKS" = 1 ]; then
  step "skip the 3 hooks in settings.json (--no-hooks: the Claude Code plugin provides them)"
elif [ "$(edit_settings check 2>/dev/null || echo absent)" = present ]; then
  step "the 3 hooks are already in settings.json, leave them"
else
  backup_settings
  step "add 3 hooks to settings.json: SessionStart (verdict), Stop + UserPromptSubmit (mistake log)"
  [ "$DRY" = 1 ] || edit_settings add
fi

# 4. first run
step "run the watchdog once: $NODE $DEST/bin/watchdog.mjs run"
if [ "$DRY" = 0 ]; then
  say ""
  "$NODE" "$DEST/bin/watchdog.mjs" run || true
  say ""
fi

# 5. timer
case "$OS" in
  mac)
    step "write $PLIST (every $INTERVAL_MIN min, also at login: watchdog, then loop-scan) and load it with launchctl"
    if [ "$DRY" = 0 ]; then
      mkdir -p "$(dirname "$PLIST")"
      cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$DEST/bin/tick.sh</string>
  </array>
  <key>WorkingDirectory</key><string>$HOME</string>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>$(( INTERVAL_MIN * 60 ))</integer>
  <key>StandardOutPath</key><string>$DEST/timer.log</string>
  <key>StandardErrorPath</key><string>$DEST/timer.log</string>
</dict>
</plist>
EOF
      launchctl unload "$PLIST" 2>/dev/null || true
      launchctl load "$PLIST"
    fi
    ;;
  linux)
    CRON_LINE="*/$INTERVAL_MIN * * * * /bin/sh $DEST/bin/tick.sh >> $DEST/timer.log 2>&1 # $APP"
    if command -v crontab >/dev/null 2>&1; then
      step "add one crontab line: $CRON_LINE"
      if [ "$DRY" = 0 ]; then
        (crontab -l 2>/dev/null | grep -v "# $APP\$" || true; echo "$CRON_LINE") | crontab -
      fi
    else
      step "crontab is not available; add this line to your scheduler yourself: $CRON_LINE"
    fi
    ;;
  *)
    step "no timer for $(uname -s); run this every $INTERVAL_MIN min yourself: /bin/sh $DEST/bin/tick.sh"
    ;;
esac

if [ "$DRY" = 1 ]; then
  say "dry run: nothing was changed."
else
  say "done. Every new Claude Code session now starts with the last verdict."
  say "  status:   node $DEST/bin/watchdog.mjs status"
  say "  history:  node $DEST/bin/watchdog.mjs history"
  say "  rules:    $DEST/claims.tsv"
fi
