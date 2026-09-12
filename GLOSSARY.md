# Glossary

One meaning per word. If a word here is used another way anywhere in this repository, that is a bug.

| Word | Meaning |
|---|---|
| metacognition | The system: the checks, the timer, the logs, the map. Also the psychology term: knowing about your own thinking (Flavell, 1979). |
| agent | The AI that does the work for the owner. The system observes it. |
| owner | The one person the agent works for. |
| rule | One line in the owner's instructions file, written for the agent. |
| check (claim) | One row in `claims.tsv`: an id, a plain-words claim, and a command that exits 0 when the claim is true. |
| verdict | The one-line result of running every check: GREEN, or RED with the failing checks named. |
| tick | One run of the watchdog on the timer, every 30 minutes. |
| watchdog | `bin/watchdog.mjs`: runs the checks, writes the verdict, keeps the history. |
| red debt | A red check older than 24 hours with no recorded decision. Blocks the end of a turn. |
| receipt | A recorded decision on a red check: "fixed", or "debt" with one plain sentence why not now. |
| correction | A message from the owner that says the last output was wrong. Counted by word matching ("again", "redo", "not what I"). |
| mistake log | The agent's own record of what it got wrong, with the owner's verdict. |
| noticing score | Of recorded misses, how many were recorded at all. |
| acting score | Of recorded misses, how many changed a rule or a check. |
| planted break | A rule broken on purpose to prove the check goes red. |
| map | The picture of every rule on the step of a task where it applies (ask, plan, build, test, commit). |
| skill | A file of instructions the agent loads for one kind of work. In this system, skills are built from corrections. |
| hook | A command that runs at a fixed moment in the agent's session (start, before a tool, after a stop). |
