---
name: no
description: Use when the user types /no <reason> — log the reason verbatim, acknowledge in one line, then redo the work with the reason applied. Do not use for ordinary questions or when the user is only choosing between options.
disallowed-tools: WebFetch, WebSearch
---

# /no — log the correction, then fix it

The reason the user gives is what the system learns from. Three moves, in this order.

## 1. Log it first, verbatim

Append one JSON line to `~/.claude/<APP>/no-log.jsonl` before doing anything else.
The reason is arbitrary text: pass it as an argument, never paste it inside shell quotes.

```bash
APP=metacognition
node -e 'const fs=require("fs"),os=require("os"),p=require("path");const f=p.join(os.homedir(),".claude",process.argv[1],"no-log.jsonl");fs.mkdirSync(p.dirname(f),{recursive:true});fs.appendFileSync(f,JSON.stringify({t:new Date().toISOString(),cwd:process.cwd(),reason:process.argv[2]})+"\n")' "$APP" "<the reason, word for word>"
```

Run it from the current working directory. `cwd` says which project the correction belongs to.

## 2. Acknowledge in one line

One line that proves the reason was understood. No defending. No explaining. No apology paragraph.

## 3. Redo

- If the reason means the last output was wrong, redo it now with the reason applied. Overwrite the same file; never make a second version beside the first.
- If the reason states a standing rule ("never do X", "always Y"), offer to add it to the rules file in one line. Write it only on a yes.
- Otherwise, nothing more this turn. Finding repeats is the job of `hooks/loop-scan.mjs`, not this turn.

## 4. When a check closes it

A correction that repeats should become a check, not another note. When you and the user add a
row to `claims.tsv` for it, append a closing line so the scan can tell "closed" from "still open":

```bash
APP=metacognition
node -e 'const fs=require("fs"),os=require("os"),p=require("path");fs.appendFileSync(p.join(os.homedir(),".claude",process.argv[1],"no-log.jsonl"),JSON.stringify({t:new Date().toISOString(),mechanized:process.argv[2],via:process.argv[3]})+"\n")' "$APP" "<theme, a few words>" "<claim id in claims.tsv>"
```

If the same theme shows up in a later `/no`, the scan reports it as a recurrence: the check did not hold.

## Never

- Never argue with the reason or soften it in the log. Word for word.
- Never skip the log because the fix is quick. The log is the product; the fix is the side effect.
