# rule-drift-watchdog

Your AI reads your rules and ignores them. This measures which ones, every 30 minutes, and
draws it.

Built by a 21-year-old solo founder in Bangkok who got tired of repeating himself to his AI.

**The number.** In August 2026, 82 of 991 messages to Claude Code were corrections: 8.3%.
In June it was 22 of 494: 4.5%. Counted by matching phrases like "again", "redo" and
"not what I" in the messages. No AI judged it. Adding rules to CLAUDE.md did not bring it
down. It went up. So the rules became checks, and the checks run on a timer.

![Every rule on the step where it applies](docs/rules-map.png)

**One line to install** (macOS or Linux, Node 18 or newer, asks nothing):

```sh
curl -fsSL https://raw.githubusercontent.com/Jauz256/rule-drift-watchdog/main/install.sh | bash
```

**What it does**

1. Turns a rule into a check: one row in `claims.tsv`, with a command that exits 0 when the
   rule holds.
2. Runs every check every 30 minutes, and prints the verdict at the start of each session.
3. Logs every correction you type, names the ones you typed 3 times, and draws the map.

**How you will know it works:** the first red light on a rule you thought was followed.

## What you see

At the start of a session, one line:

```text
rule-drift-watchdog RED: 2 of 11 rules broken: claude-md-short (exit 1); memory-index (exit 1)
  RED    claude-md-short: exit 1
  RED    memory-index: exit 1
  (changed since the previous run)
```

`watchdog.mjs status` shows one line per rule. `watchdog.mjs history` shows how often each
rule held over the last runs. That per-rule pass rate is the drift meter.

```text
  memory-index                 0/4   green   0%  RED now
  claude-md-short              1/4   green  25%
  hooks-exist                  4/4   green 100%
```

## The loop

| step | what happens | file |
|---|---|---|
| rule | a line in your CLAUDE.md | your file |
| check | the rule in plain words, then a command that must exit 0 | `claims.tsv` |
| watchdog | runs every check every 30 min, writes the verdict | `bin/watchdog.mjs` |
| red light | the verdict is printed when a session starts | `hooks/session-inject.sh` |
| mistake log | what the AI made, and what you said next | `hooks/mistake-log.mjs`, `/no` |
| loop scan | a correction typed 3 times becomes a check to add | `hooks/loop-scan.mjs` |
| picture | every rule on its step: mechanism, note, or broken | `tools/rules-map/build.py` |

The long version is in [docs/how-it-works.md](docs/how-it-works.md).

## Add a rule

```sh
node ~/.claude/rule-drift-watchdog/bin/watchdog.mjs add \
  "no console.log in src/" \
  "! git grep -qE 'console\.log\(' -- 'src/*.ts'"
```

The row lands in `~/.claude/rule-drift-watchdog/claims.tsv` and is checked once right away.
Rows are tab-separated: `id`, `claim in plain words`, `check`. The shipped file holds 11
example rules; delete the ones that do not fit you.

## Draw the map

```sh
python3 ~/.claude/rule-drift-watchdog/tools/rules-map/build.py \
  --rules ~/.claude/CLAUDE.md \
  --claims ~/.claude/rule-drift-watchdog/claims.tsv \
  --verdict ~/.claude/rule-drift-watchdog/verdict.json \
  --out rules-map.svg
```

Every top-level bullet in CLAUDE.md becomes a card. A card with a matching claim is green.
A card whose check failed gets a red ring. Cards the builder cannot place go to step 0 until
you pin them in `placement.json`. A PNG is written next to the SVG when Playwright is
installed; otherwise only the SVG.

## What gets installed

- `~/.claude/rule-drift-watchdog/`: the code, `claims.tsv`, `verdict.json`, `mistakes.jsonl`,
  `receipts.jsonl`, `loop-candidates.md`.
- Three hooks in `~/.claude/settings.json`: SessionStart (prints the verdict), Stop and
  UserPromptSubmit (the mistake log). Your other hooks are kept. The file is backed up first.
- One timer: a launchd agent on macOS, one crontab line on Linux. Every 30 minutes it runs
  the watchdog, then the loop scan.

`bash install.sh --dry-run` prints all of that and changes nothing.
`bash install.sh --uninstall` removes the hooks, the timer and the code, and keeps your data.

## What it does not do

It does not make the AI obey. It measures which rules held, which broke, and which were
never checked at all. The watchdog also checks itself: four planted failures must come back
red on every run, or the verdict says BROKEN instead of GREEN.

## Credits

- u/thabxi's MISTAKES.md post on r/ClaudeCode: the honest log of what went wrong is the
  lesson. The mistake log here is that idea, built.
- [obra/superpowers](https://github.com/obra/superpowers): the skill pattern the `/no` skill
  follows.
- everything-claude-code: its `doctor` command was the first health check in a Claude Code
  setup.
- Nate Herk's AIS-OS: "how you will know it works" written as things you feel, not a score.

## License

MIT.
