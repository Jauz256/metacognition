# AGENTS.md

This file is for coding agents working inside this repository. AGENTS.md takes precedence over
CLAUDE.md: the only CLAUDE.md here, `tools/rules-map/example/CLAUDE.md`, is a sample input for the
picture builder, not a rule file.

## What this project is

metacognition turns each rule in your instructions file into a command that must exit 0. It runs
them every 30 minutes and reports which rules held and which broke.

## Rules for changing this code

- Every change must keep `bash tests/run.sh` and `bash tests/run-tools.sh` passing. Run both.
- No dependencies. Node built-ins and the Python standard library only. Playwright is optional and
  detected at runtime.
- Shell checks in `claims.tsv` run with stdin closed and a 20 second limit. Never write a check that
  waits for input.
- The watchdog must never speak, open a window, or send anything over the network. It prints and it
  writes files.
- Keep the name in the single `APP` constant at the top of each script. Do not hardcode it elsewhere.
- Plain English in comments and messages. Short sentences. No jokes.

## Two examples

Example 1, one rule in `claims.tsv` (tab-separated: id, plain-words claim, check command):

```
tests-green	the test suite passes	bash tests/run.sh >/dev/null 2>&1
```

Example 2, what the watchdog prints for it when the tests fail:

```
metacognition RED: 1 of 11 rules failed. tests-green is FALSE right now: the test suite passes
```

## Before you say a change works

Run both test files and paste the last line of each. "It should work" is not a result.

## Layout

| Path | What it does |
|---|---|
| `bin/watchdog.mjs` | Runs the checks. Also `status`, `history`, `add` |
| `bin/cli.mjs` | What `npx metacognition` runs |
| `bin/tick.sh` | What the timer calls |
| `hooks/` | Session line, mistake log, loop scan |
| `tools/rules-map/build.py` | Draws the rules picture |
| `claims.tsv` | The example rules that ship |
| `install.sh` | Copies files, wires hooks, writes the timer |
