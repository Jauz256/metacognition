# Changelog

## 0.1.0, not yet released

The first version.

- The watchdog runs each rule in `claims.tsv` as a command that must exit 0.
- `status` prints the last verdict. `history` shows the pass rate for each rule over recent runs.
- `add` appends a rule and checks it once.
- Four planted failures run on every pass. If they come back green, the verdict is BROKEN instead.
- A session hook prints the verdict when you open a session, and says so when the timer has stopped.
- A mistake log records what the agent made and what you said next.
- A loop scan names a correction that repeats three times in 30 days.
- A picture puts every rule on the step where it applies, marked enforced, note, or broken today.
- `install.sh` has `--dry-run` and `--uninstall`, and backs up `settings.json` before touching it.
- 11 example rules ship, and none of them are personal.
