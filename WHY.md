# Why metacognition exists

Metacognition is a system that observes how an AI coding agent works for one person, records
that person's corrections and the agent's own mistakes, turns repeated corrections into
executable checks that run on a timer, and reports whether the agent's work improves.

The full foundation, with 28 references, is in [docs/FOUNDATION.md](docs/FOUNDATION.md). This
page is the short form.

## The problem

Instruction files for agents grow and get ignored. In a 2025 benchmark of real agent
instructions, the average instruction was 1,723 words with 11.9 constraints, and frontier
models failed a large share of them (Qi et al., 2025). Models attend least to the middle of a
long context (Liu et al., 2024). Anthropic removed over 80% of the Claude Code system prompt in
2026 with no measurable loss (Anthropic, 2026). Most of a long rules file does no work.

The human pays for it in repeated corrections. One owner counted them: 4.5% of his messages in
June 2026, 8.3% in August, while his rules file grew. A correction typed once and not recorded
is gone by the next session, on both sides of the conversation (Murre and Dros, 2015).

So the loop never closes: correct, comply once, forget, correct again.

## Six principles

1. **The owner sees the agent's state while the work happens.** Feedback changes behaviour when
   it is specific and close to the action (Wisniewski, Zierer and Hattie, 2020: d = 0.48 across
   435 studies, d = 0.99 for high-information feedback). Mechanism: every check gives a one-line
   verdict, printed first in every session, re-run every 30 minutes, and a red check older than
   24 hours blocks the end of a turn until a decision is recorded.

2. **A correction is recorded once and never typed again.** Compiling corrections into runtime
   checks cut preference violations from 100% to 37.6% and to 2.0% in two settings, where a
   free-text memory left 57.5% violated (Zhou et al., 2026). Mechanism: corrections and the
   agent's mistakes are logged verbatim; the third occurrence becomes a check with a command
   that exits 0 when the rule holds.

3. **The owner's taste is kept across sessions.** Agents without long-term memory lose about
   30% accuracy on questions that depend on earlier sessions (Wu et al., 2024). Mechanism:
   corrections that cluster around one kind of work become a skill file; decisions go to dated
   memory files loaded at session start.

4. **Routine decisions go to the system, judgement stays with the owner.** Working memory holds
   about four chunks (Cowan, 2001). Mechanism: hooks make the routine decisions at fixed
   moments; timed jobs do recurring work; the owner reviews.

5. **The agent reflects on its failures, with an external signal.** Reflection raised HumanEval
   from 80% to 91% (Shinn et al., 2023), but models cannot reliably self-correct without an
   outside signal (Huang et al., 2023). Mechanism: the agent's own mistake ledger, scored on
   noticing and acting; the checks table is the outside signal.

6. **Improvement is measured by counts, and every measure is watched for gaming.** Monitoring
   progress improves attainment (Harkin et al., 2016: d+ = 0.40), and any measure that becomes
   a target invites gaming (Manheim and Garrabrant, 2018). Mechanism: no measure is judged by a
   model; checks return exit codes; a check that has never gone red does not count.

## What it is not

- Not a memory tool. Memory is a part; the object is the change in behaviour.
- Not an enforcer. Today it observes, names the broken rule, and blocks the end of a turn until
  a decision is recorded. It does not correct the agent's output by itself.
- Not a second agent, not a skills framework, not a model benchmark.

## How to judge it

| Measure | Value on 12 Sep 2026 |
|---|---|
| Corrections as a share of the owner's messages | June 4.5%, August 8.3% |
| Checks proven to go red on a planted break | 11 shipped, 21 in one live system |
| Time to detect a planted break | 1 to 2 s on demand, next 30-minute tick otherwise; 10 of 10 caught, 0 false alarms in 20 clean runs |
| Red checks older than 24 h without a decision | 0 |
| Of recorded misses, how many changed a rule or check | 4 of 8 |

The success criterion is still open: correction share back under 4.5% for a named month, or no
correction repeated within 30 days.

## Related work

TRACE (Zhou et al., 2026) mines chat corrections into runtime checks and is the closest prior
work. This system adds the timer that re-checks outside any session, the agent's own mistake
ledger, the red-debt rule, and the map of every rule on the step where it applies. Linters such
as agnix score an instruction file once; they do not run. Skill frameworks such as superpowers
change what the agent does; this measures whether it did it.

## Limitations

It observes; it does not yet correct. Only shell-testable rules are covered. All numbers come
from one owner over three months. See docs/FOUNDATION.md, section 5.

References are in docs/FOUNDATION.md.
