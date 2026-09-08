#!/bin/bash
# tests/run.sh - runs the watchdog against a throwaway HOME and checks the verdicts.
# Nothing under your real ~/.claude is read or written. Exit 0 means every check passed.
#
#   bash tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="metacognition"
WD="$ROOT/bin/watchdog.mjs"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
DIR="$HOME/.claude/$APP"
mkdir -p "$DIR"

# Fake launchctl and crontab so the installer can be run for real without touching the
# machine's scheduler. Each shim records what it was asked to do.
mkdir -p "$TMP/bin"
printf '#!/bin/bash\necho "launchctl $*" >> "%s/shim.log"\n' "$TMP" > "$TMP/bin/launchctl"
printf '#!/bin/bash\ncase "$1" in -l) cat "%s/crontab.txt" 2>/dev/null ;; -) cat > "%s/crontab.txt" ;; esac\n' "$TMP" "$TMP" > "$TMP/bin/crontab"
chmod +x "$TMP/bin/launchctl" "$TMP/bin/crontab"
export PATH="$TMP/bin:$PATH"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "PASS  $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; }
expect_contains() { # name, needle, haystack
  if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1 (expected to contain: $2)" "$3"; fi
}
expect_not_contains() {
  if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1 (must not contain: $2)" "$3"; else ok "$1"; fi
}
expect_match() { # name, extended regex, haystack
  if printf '%s' "$3" | grep -qE -- "$2"; then ok "$1"; else bad "$1 (expected to match: $2)" "$3"; fi
}
tree_hash() { # names and contents of everything under the fake home
  (cd "$HOME" && { find . | sort; find . -type f | sort | while read -r f; do cat "$f"; done; } \
    | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>console.log(require("crypto").createHash("sha1").update(d).digest("hex")))')
}
expect_eq() { # name, expected, actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
overall() { node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).overall)' "$DIR/verdict.json"; }
item_status() { node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const i=v.items.find(x=>x.id===process.argv[2]);console.log(i?i.status:"absent")' "$DIR/verdict.json" "$1"; }
ledger() { printf '# id\tclaim\tcheck\n'; for row in "$@"; do printf '%s\n' "$row"; done; }

echo "== 1. a planted false claim makes the verdict RED"
ledger "$(printf 'always-true\tholds\ttrue')" "$(printf 'planted-broken\ta rule that cannot hold\tfalse')" > "$DIR/claims.tsv"
OUT=$(node "$WD" run); CODE=$?
expect_eq "1a exit code is 1 on RED" 1 "$CODE"
expect_eq "1b verdict.json overall is RED" RED "$(overall)"
expect_eq "1c the planted rule is RED" RED "$(item_status planted-broken)"
expect_eq "1d the true rule is GREEN" GREEN "$(item_status always-true)"
expect_contains "1e verdict.txt names the app and RED" "$APP RED" "$(cat "$DIR/verdict.txt")"
expect_contains "1f stdout names the broken rule" "planted-broken" "$OUT"

echo "== 2. all-green claims make the verdict GREEN"
ledger "$(printf 'always-true\tholds\ttrue')" "$(printf 'home-exists\thome exists\ttest -d "$HOME"')" > "$DIR/claims.tsv"
OUT=$(node "$WD" run); CODE=$?
expect_eq "2a exit code is 0 on GREEN" 0 "$CODE"
expect_eq "2b verdict.json overall is GREEN" GREEN "$(overall)"
expect_contains "2c sentence says all 2 rules hold" "all 2 rules hold" "$OUT"
expect_contains "2d the change since the RED run is announced" "changed since the previous run" "$OUT"
QUIET=$(node "$WD" run --quiet)
expect_eq "2e --quiet prints nothing on GREEN" "" "$QUIET"

echo "== 3. canaries"
BLIND=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).canaries.blind.length)' "$DIR/verdict.json")
PLANTED=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).canaries.planted)' "$DIR/verdict.json")
expect_eq "3a no canary was blind on a healthy runner" 0 "$BLIND"
expect_eq "3b four canaries were planted" 4 "$PLANTED"
# A shell that says yes to everything must be caught: every canary reads GREEN, so BROKEN.
printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/yes-shell"; chmod +x "$TMP/bin/yes-shell"
OUT=$(WATCHDOG_SHELL="$TMP/bin/yes-shell" node "$WD" run); CODE=$?
expect_eq "3c a blind runner reports BROKEN" BROKEN "$(overall)"
expect_eq "3d exit code is 2 on BROKEN" 2 "$CODE"
expect_contains "3e the sentence says not to trust green" "Do not trust any green" "$OUT"

echo "== 4. a check that reads stdin fails at once and does not eat the next rule"
ledger "$(printf 'reads-stdin\tmust not hang\tread -r line')" "$(printf 'after-it\tstill runs\ttrue')" > "$DIR/claims.tsv"
START=$(date +%s); node "$WD" run >/dev/null; TOOK=$(( $(date +%s) - START ))
expect_eq "4a stdin reader is RED" RED "$(item_status reads-stdin)"
expect_eq "4b the rule after it still ran GREEN" GREEN "$(item_status after-it)"
[ "$TOOK" -lt 15 ] && ok "4c the run did not hang (${TOOK}s)" || bad "4c the run took ${TOOK}s"

echo "== 5. a hanging check is cut off by the timeout"
ledger "$(printf 'hangs\tsleeps past the limit\tsleep 20')" > "$DIR/claims.tsv"
START=$(date +%s); OUT=$(WATCHDOG_CLAIM_TIMEOUT_MS=1000 node "$WD" run); TOOK=$(( $(date +%s) - START ))
expect_eq "5a the hanging rule is RED" RED "$(item_status hangs)"
expect_contains "5b the message says timed out" "timed out" "$OUT"
[ "$TOOK" -lt 10 ] && ok "5c the run finished in ${TOOK}s" || bad "5c the run took ${TOOK}s"

echo "== 6. ledger problems are reported, not skipped"
printf 'no tabs on this line\n' > "$DIR/claims.tsv"
node "$WD" run >/dev/null
expect_eq "6a a malformed line is a RED ledger item" RED "$(item_status ledger)"
rm "$DIR/claims.tsv"
OUT=$(node "$WD" run)
expect_contains "6b a missing ledger is RED with the path" "missing at" "$OUT"

echo "== 7. add appends a rule and checks it once"
rm -f "$DIR/claims.tsv"
OUT=$(node "$WD" add "the temp folder exists" "test -d \"$TMP\"")
expect_contains "7a add reports the new id" "added the-temp-folder-exists" "$OUT"
expect_contains "7b add runs the check once" "GREEN" "$OUT"
node "$WD" add "the temp folder exists" "false" >/dev/null
COUNT=$(grep -cv '^#' "$DIR/claims.tsv")
expect_eq "7c two rows in the ledger" 2 "$COUNT"
expect_contains "7d a repeated claim gets a numbered id" "the-temp-folder-exists-2" "$(cat "$DIR/claims.tsv")"
expect_contains "7e the header line was written" "# id	claim in plain words	check (must exit 0)" "$(head -n 1 "$DIR/claims.tsv")"

echo "== 8. history counts green runs per rule"
rm -f "$DIR/receipts.jsonl" "$DIR/state.json"
ledger "$(printf 'steady\talways holds\ttrue')" "$(printf 'flaky\tholds only when the flag file exists\ttest -f "%s/flag"' "$TMP")" > "$DIR/claims.tsv"
node "$WD" run >/dev/null; touch "$TMP/flag"; node "$WD" run >/dev/null; node "$WD" run >/dev/null
OUT=$(node "$WD" history 10)
expect_contains "8a history covers 3 runs" "last 3 runs" "$OUT"
expect_match "8b steady is 3/3" "steady +3/3 +green +100%" "$OUT"
expect_match "8c flaky is 2/3" "flaky +2/3 +green +67%" "$OUT"
OUT=$(node "$WD" history 1)
expect_contains "8d history N limits the window" "last 1 run," "$OUT"
expect_match "8e flaky is 1/1 in the last run" "flaky +1/1 +green +100%" "$OUT"

echo "== 9. status prints the verdict and calls an old one stale"
OUT=$(node "$WD" status)
expect_contains "9a status prints the sentence" "$APP GREEN" "$OUT"
expect_contains "9b status lists each rule" "GREEN  steady" "$OUT"
expect_not_contains "9c a fresh verdict is not stale" "STALE" "$OUT"

echo "== 10. session hook prints the verdict, and STALE when the timer stopped"
HOOK="$ROOT/hooks/session-inject.sh"
OUT=$(bash "$HOOK")
expect_contains "10a hook prints the last verdict" "$APP GREEN" "$OUT"
expect_not_contains "10b fresh verdict is not called stale" "STALE" "$OUT"
touch -t "$(date -v-3H +%Y%m%d%H%M 2>/dev/null || date -d '3 hours ago' +%Y%m%d%H%M)" "$DIR/verdict.txt"
OUT=$(bash "$HOOK")
expect_contains "10c a 3 hour old verdict is STALE" "$APP is STALE, last run" "$OUT"
expect_contains "10d the stale line still shows the verdict" "$APP GREEN" "$OUT"
mv "$DIR/verdict.txt" "$TMP/verdict.bak"
OUT=$(bash "$HOOK")
expect_contains "10e no verdict yet is said plainly" "no verdict yet" "$OUT"
mv "$TMP/verdict.bak" "$DIR/verdict.txt"

echo "== 11. the lock skips a second run"
mkdir "$DIR/.run.lock"
OUT=$(node "$WD" run); CODE=$?
expect_contains "11a a held lock is reported" "another run holds the lock" "$OUT"
expect_eq "11b a skipped run exits 0" 0 "$CODE"
rmdir "$DIR/.run.lock"

echo "== 12. the shipped claims.tsv holds on a small clean home"
rm -rf "$DIR"; mkdir -p "$DIR"
cp "$ROOT/claims.tsv" "$DIR/claims.tsv"
printf '# My rules\n- Keep answers short.\n' > "$HOME/.claude/CLAUDE.md"
printf '{\n  "hooks": {\n    "SessionStart": [\n      { "hooks": [ { "type": "command", "command": "bash \\"%s/keep-me.sh\\"" } ] }\n    ]\n  }\n}\n' "$HOME/.claude" > "$HOME/.claude/settings.json"
printf '#!/bin/bash\necho keep\n' > "$HOME/.claude/keep-me.sh"
OUT=$(cd "$HOME" && node "$WD" run); CODE=$?
expect_eq "12a shipped ledger is GREEN on a clean home" GREEN "$(overall)"
expect_contains "12b all 11 example rules ran" "all 11 rules hold" "$OUT"
# plant a fake token (built at run time so this file never contains one) and a dead hook
FAKE="$(printf 's''k-')$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24)"
printf '\nkey: %s\n' "$FAKE" >> "$HOME/.claude/CLAUDE.md"
OUT=$(cd "$HOME" && node "$WD" run)
expect_eq "12c a planted token turns no-secrets-in-rules RED" RED "$(item_status no-secrets-in-rules)"
expect_eq "12d the other rules stay GREEN" GREEN "$(item_status hooks-exist)"
printf '# My rules\n' > "$HOME/.claude/CLAUDE.md"
rm "$HOME/.claude/keep-me.sh"
OUT=$(cd "$HOME" && node "$WD" run)
expect_eq "12e a missing hook script turns hooks-exist RED" RED "$(item_status hooks-exist)"
printf '#!/bin/bash\necho keep\n' > "$HOME/.claude/keep-me.sh"

echo "== 13. install.sh --dry-run changes nothing"
BEFORE=$(tree_hash)
OUT=$(cd "$HOME" && bash "$ROOT/install.sh" --dry-run); CODE=$?
AFTER=$(tree_hash)
expect_eq "13a dry run exits 0" 0 "$CODE"
expect_contains "13b dry run says would" "would: copy bin/ and hooks/" "$OUT"
expect_contains "13c dry run ends with nothing was changed" "dry run: nothing was changed." "$OUT"
expect_eq "13d dry run left the file tree alone" "$BEFORE" "$AFTER"
expect_eq "13e dry run did not touch the shims" "" "$(cat "$TMP/shim.log" 2>/dev/null)"

echo "== 14. install.sh for real, into the fake home (scheduler shimmed)"
rm -rf "$DIR"
OUT=$(cd "$HOME" && bash "$ROOT/install.sh"); CODE=$?
expect_eq "14a install exits 0" 0 "$CODE"
[ -f "$DIR/bin/watchdog.mjs" ] && ok "14b bin copied" || bad "14b bin copied"
[ -f "$DIR/hooks/session-inject.sh" ] && ok "14c hooks copied" || bad "14c hooks copied"
[ -f "$DIR/claims.tsv" ] && ok "14d example claims.tsv copied" || bad "14d example claims.tsv copied"
expect_contains "14e first verdict printed" "$APP GREEN: all 11 rules hold" "$OUT"
HOOKS=$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(s.hooks.SessionStart.map(m=>m.hooks.map(h=>h.command).join()).join("|"))' "$HOME/.claude/settings.json")
expect_contains "14f the pre-existing hook is kept" "keep-me.sh" "$HOOKS"
expect_contains "14g the session hook was added" "$APP/hooks/session-inject.sh" "$HOOKS"
MLOG=$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(["Stop","UserPromptSubmit"].map(e=>(s.hooks[e]||[]).map(m=>m.hooks.map(h=>h.command).join()).join("|")).join("||"))' "$HOME/.claude/settings.json")
expect_contains "14g2 the mistake-log hook was added" "mistake-log.mjs" "$MLOG"
case "$MLOG" in *mistake-log.mjs*"||"*mistake-log.mjs*) ok "14g3 both events carry the mistake-log hook" ;; *) bad "14g3 both events carry the mistake-log hook" ;; esac
[ -x "$DIR/bin/tick.sh" ] && ok "14g4 tick.sh copied and executable" || bad "14g4 tick.sh copied and executable"
sh "$DIR/bin/tick.sh" >/dev/null 2>&1 && ok "14g5 tick.sh runs the watchdog and the loop scan" || bad "14g5 tick.sh runs"
ls "$HOME/.claude"/settings.json.bak-* >/dev/null 2>&1 && ok "14h settings.json was backed up" || bad "14h settings.json was backed up"
case "$(uname -s)" in
  Darwin)
    [ -f "$HOME/Library/LaunchAgents/local.$APP.plist" ] && ok "14i plist written" || bad "14i plist written"
    expect_contains "14j launchctl load was called" "launchctl load" "$(cat "$TMP/shim.log")"
    expect_contains "14k plist runs every 1800 s" "<integer>1800</integer>" "$(cat "$HOME/Library/LaunchAgents/local.$APP.plist")" ;;
  Linux)
    expect_contains "14i crontab line written" "*/30 * * * *" "$(cat "$TMP/crontab.txt")"
    expect_contains "14j crontab line tagged" "# $APP" "$(cat "$TMP/crontab.txt")" ;;
esac
printf 'mine\tmy own rule\ttrue\n' >> "$DIR/claims.tsv"
(cd "$HOME" && bash "$ROOT/install.sh" >/dev/null)
expect_contains "14l a second install keeps the user's claims.tsv" "mine" "$(cat "$DIR/claims.tsv")"
[ -f "$DIR/claims.example.tsv" ] && ok "14m and writes claims.example.tsv" || bad "14m and writes claims.example.tsv"
N=$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(s.hooks.SessionStart.length)' "$HOME/.claude/settings.json")
expect_eq "14n a second install does not add a second hook" 2 "$N"

echo "== 15. install.sh --uninstall removes the hook and timer, keeps the data"
OUT=$(cd "$HOME" && bash "$ROOT/install.sh" --uninstall); CODE=$?
expect_eq "15a uninstall exits 0" 0 "$CODE"
HOOKS=$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(((s.hooks||{}).SessionStart||[]).map(m=>m.hooks.map(h=>h.command).join()).join("|"))' "$HOME/.claude/settings.json")
expect_not_contains "15b the session hook is gone" "session-inject.sh" "$HOOKS"
MLOG=$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(JSON.stringify(s.hooks||{}))' "$HOME/.claude/settings.json")
expect_not_contains "15b2 the mistake-log hook is gone" "mistake-log.mjs" "$MLOG"
expect_contains "15c the other hook survived" "keep-me.sh" "$HOOKS"
[ ! -d "$DIR/bin" ] && ok "15d bin removed" || bad "15d bin removed"
[ -f "$DIR/claims.tsv" ] && ok "15e claims.tsv kept" || bad "15e claims.tsv kept"
[ -f "$DIR/receipts.jsonl" ] && ok "15f receipts kept" || bad "15f receipts kept"
case "$(uname -s)" in
  Darwin) [ ! -f "$HOME/Library/LaunchAgents/local.$APP.plist" ] && ok "15g plist removed" || bad "15g plist removed" ;;
  Linux) expect_not_contains "15g crontab line removed" "# $APP" "$(cat "$TMP/crontab.txt")" ;;
esac

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
