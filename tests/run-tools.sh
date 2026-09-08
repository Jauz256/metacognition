#!/usr/bin/env bash
# run-tools.sh - proves the loop scan and the rules-map builder do what they say.
# 1. loop-scan: a correction made 3 times (2 via /no, 1 via the hook) is one candidate;
#    a 2x correction is not; a theme closed with a check that comes back is reported.
# 2. rules-map: the example builds, has one red-ring rule, note cards, and an unplaced column,
#    and the shipped example/out.svg matches a fresh build.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
d() { node -e 'console.log(new Date(Date.now()-Number(process.argv[1])*864e5).toISOString())' "$1"; }

# --- 1. loop-scan -------------------------------------------------------------
mkdir -p "$T/state"
cat > "$T/state/no-log.jsonl" <<JSON
{"t":"$(d 20)","cwd":"/work/demo","reason":"don't use fake data in the demo"}
{"t":"$(d 12)","cwd":"/work/demo","reason":"fake data again, use the real numbers"}
{"t":"$(d 9)","cwd":"/work/demo","reason":"the layout overlaps on mobile"}
{"t":"$(d 8)","cwd":"/work/demo","reason":"mobile layout overlaps again"}
{"t":"$(d 7)","cwd":"/work/demo","reason":"wrong file name"}
{"t":"$(d 60)","cwd":"/work/demo","reason":"fake data in the chart"}
{"t":"$(d 10)","mechanized":"duplicate files","via":"no-duplicate-files"}
{"t":"$(d 5)","cwd":"/work/demo","reason":"duplicate files again, two copies of the report"}
JSON
cat > "$T/state/mistakes.jsonl" <<JSON
{"t":"$(d 15)","session":"abcd1234","made":["~/demo/index.html"],"cmds":1,"said":"done","redo_of":null,"verdict":{"t":"$(d 15)","kind":"complaint","words":"you used fake data again"}}
{"t":"$(d 14)","session":"abcd1234","made":["~/demo/index.html"],"cmds":1,"said":"redone with real numbers","redo_of":"$(d 15)","verdict":{"t":"$(d 14)","kind":"accept","words":"ok good"}}
JSON
OUT=$(node hooks/loop-scan.mjs --dir "$T/state" --out "$T/loop-candidates.md")
echo "$OUT" | grep -q '^candidates: 1$' || fail "expected exactly one candidate, got: $(echo "$OUT" | tail -1)"
grep -q 'happened 3 times' "$T/loop-candidates.md" || fail "the candidate should say it happened 3 times"
grep -q 'came back on' "$T/loop-candidates.md" || fail "a closed theme that came back was not reported"
if grep -q '^### .*layout' "$T/loop-candidates.md"; then fail "a 2x correction must not be a candidate"; fi
echo "ok  loop-scan: one candidate (3 times, two sources), 2x ignored, one recurrence reported"

# --- 2. rules-map -------------------------------------------------------------
EX=tools/rules-map/example
python3 tools/rules-map/build.py --rules "$EX/CLAUDE.md" --claims "$EX/claims.tsv" --verdict "$EX/verdict.json" --out "$T/out.svg" --no-png > "$T/build.json"
test -s "$T/out.svg" || fail "out.svg was not written"
N=$(grep -o 'class="rule mechanism broken"' "$T/out.svg" | wc -l | tr -d ' ')
[ "$N" = "1" ] || fail "expected 1 red-ring rule, got $N"
grep -q 'class="rule note"' "$T/out.svg" || fail "no note cards drawn"
grep -q 'data-step="0"' "$T/out.svg" || fail "the unplaced column is missing"
ALL=$(grep -o 'class="rule ' "$T/out.svg" | wc -l | tr -d ' ')
[ "$ALL" = "10" ] || fail "expected 10 rule cards, got $ALL"
cmp -s "$T/out.svg" "$EX/out.svg" || fail "$EX/out.svg is stale; rebuild it with the command in build.py"
echo "ok  rules-map: 10 cards, 1 red ring, notes and unplaced present, example/out.svg is current"

# --- the shipped rules must work for any agent, not only Claude Code -------------
# The engine was always generic, but nine of eleven shipped rules named one tool.
# These four homes prove the claim in the README. Each runs from inside its own home.
agent_home() { # $1 = label, $2 = setup command, $3 = expected word in the verdict
  local T
  T=$(mktemp -d)
  mkdir -p "$T/.claude/metacognition"
  cp "$ROOT/claims.tsv" "$T/.claude/metacognition/"
  ( eval "$2" )
  # the watchdog exits non-zero when a rule is RED, and that is a pass here, so swallow it
  OUT=$( cd "$T" && HOME="$T" node "$ROOT/bin/watchdog.mjs" run 2>&1 | tail -3 || true )
  rm -rf "$T"
  case "$OUT" in
    *"$3"*) echo "ok  agent home: $1" ;;
    *) echo "FAIL agent home: $1 — wanted $3, got: $OUT"; fail "agent home $1" ;;
  esac
}
agent_home "Codex, AGENTS.md only"   'printf "# rules\n- answer first\n" > "$T/AGENTS.md"'          GREEN
agent_home "Cursor, .cursorrules"    'printf "be brief\n" > "$T/.cursorrules"'                       GREEN
agent_home "Gemini CLI"              'mkdir -p "$T/.gemini"; printf "be brief\n" > "$T/.gemini/GEMINI.md"' GREEN
agent_home "no agent file at all"    'true'                                                           RED

# --- the shipped example rule sets must pass clean and catch dirty ---------------
# An untested example rule set is worse than none: it teaches people a broken check.
example_set() { # $1 = file, $2 = expected word
  local T
  T=$(mktemp -d)
  mkdir -p "$T/.claude/metacognition" "$T/repo/src"
  cp "$ROOT/examples/$1" "$T/.claude/metacognition/claims.tsv"
  (
    cd "$T/repo" && git init -q
    if [ "$2" = GREEN ]; then
      printf 'export const a = 1;\n' > src/a.js
      printf '{"name":"x","license":"MIT","scripts":{"test":"echo ok"}}\n' > package.json
      printf '{}\n' > package-lock.json
      printf 'def f():\n    return 1\n' > src/a.py
      printf 'requests==2.0\n' > requirements.txt
      printf '# Notes\n\nReal words here.\n' > notes.md
      mkdir -p output && printf 'x\n' > output/chart.png
      printf '# Plan\n\n- [x] first task\n' > PLAN.md
      printf '# Changelog\n\n- first release\n' > CHANGELOG.md
      printf '# Rules\n\nAnswer first, then explain.\n' > AGENTS.md
    else
      printf 'console.log("x");\n' > src/a.js
      printf 'import pdb\nexcept:\n' > src/a.py
      printf '{"name":"x"}\n' > package.json
      printf 'requests\n' > requirements.txt
      printf '# Notes\n\nTODO write this.\nThe report is in a machine folder that no one else has\n' > notes.md
      printf 'x\n' > chart.png
      printf 'x\n' > chart-2.png
      mkdir -p test-results && printf 'old\n' > test-results/last.txt
      touch -t 202401010000 test-results/last.txt
    fi
    git add -A -f && git -c user.email=t@t -c user.name=t commit -qm x
  ) >/dev/null 2>&1
  OUT=$( cd "$T/repo" && HOME="$T" node "$ROOT/bin/watchdog.mjs" run 2>&1 | tail -3 || true )
  rm -rf "$T"
  case "$OUT" in
    *"$2"*) echo "ok  example set: $1 is $2 as expected" ;;
    *) echo "FAIL example set: $1 — wanted $2, got: $OUT"; fail "example set $1" ;;
  esac
}
for f in javascript.tsv python.tsv writing.tsv agent-discipline.tsv; do
  example_set "$f" GREEN
  example_set "$f" RED
done

echo "PASS"
