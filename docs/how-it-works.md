# How it works

Your rules file says "never ship debug statements". The AI reads it and ships them anyway. Nothing tells you. This closes that loop.

## The loop

1. **Rule.** A line in your CLAUDE.md. Words only.
2. **Check.** A row in `claims.tsv`: the rule in plain words, then a command that exits 0 when the rule holds. A rule with a row is a *mechanism*. A rule without one is a *note*.
3. **Watchdog.** `bin/watchdog.mjs` runs every row every 30 minutes and writes `verdict.json`: GREEN, AMBER or RED per claim.
4. **Red light.** A red claim is a rule that broke today. It is shown at the start of your next session.
5. **Mistake logged.** `hooks/mistake-log.mjs` saves what the AI made and reads your next message as the verdict. The `/no` skill logs `/no <reason>` word for word before anything else happens.
6. **Loop scan.** `hooks/loop-scan.mjs` groups corrections that say the same thing. One you typed 3 times in 30 days is a candidate: it should become a check, not another note. The scan writes the claims.tsv row for you to finish.
7. **New check.** You paste the row and write the command. From then on the machine catches it before you do.
8. **The picture.** `tools/rules-map/build.py` draws every rule on the step where it applies: read the ask, plan, build, verify, show, learn. Green cards have a check. Grey cards are notes. A red ring is a check that failed in the last verdict. Rules it cannot place wait in "not placed yet" until you pin them.

## How you will know it works

Three things you will feel, not a score.

1. **The first red light on a rule you thought was followed.** You wrote it months ago. The verdict says it did not hold, with the command that proved it.
2. **A correction you typed three times shows up as a candidate**, with dates and a row ready to paste. You did not have to notice the pattern yourself.
3. **The picture shows how many of your rules are only notes.** Most of them, the first time. That count is the work ahead, and you can watch it fall.

## What it does not do

It does not make the AI obey. It measures which rules held, which broke, and which were never checked at all.
