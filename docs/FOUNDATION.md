# Metacognition: a foundation

Foundation document, 12 Sep 2026. Every cited claim
comes from a source that was opened and checked on 12 Sep 2026. The owner's case appears once, as
the worked example in section 8. Open questions are marked **OPEN**.

## Abstract

Metacognition is a system that observes how an AI coding agent works for one person, records
that person's corrections and the agent's own mistakes, turns repeated corrections into
executable checks that run on a timer, and reports whether the agent's work improves. It exists
because written instructions to agents grow, get ignored, and fail silently, while the human's
corrections repeat and are forgotten. The design rests on six principles, each supported by
published evidence and each tied to one mechanism in the code.

## 1. The problem

Instruction files for coding agents are long and getting longer. In AgentIF, a 2025 benchmark
of real agent instructions, the average instruction was 1,723 words and carried 11.9
constraints, and frontier models failed a large share of them (Qi et al., 2025). Models attend
least to the middle of a long context, so rules placed there are the first to be lost (Liu et
al., 2024). Anthropic reported in 2026 that removing over 80% of the Claude Code system prompt
produced no measurable loss on its coding evaluations (Anthropic, 2026a), which is the same
finding from the other side: most of a long instruction file does no work.

On the human side, the cost shows up as repeated corrections. The owner in section 8 counted
corrections as a share of his messages: 4.5% in June 2026 and 8.3% in August, while his rules
file grew. The human forgets too. Murre and Dros (2015) replicated Ebbinghaus's forgetting
curve and found the steep early loss of new material within the first day. A correction typed
once, and not recorded, is gone from both sides of the conversation by the next session.

The result is a loop that does not close: the human corrects, the agent complies once, the
correction is forgotten, and the human corrects again.

## 2. Six principles

Each principle states a claim, the evidence for it, and the mechanism that implements it.

### P1. The owner sees the agent's state while the work happens, not after

Feedback changes behaviour when it is specific and arrives close to the action. Across 435
studies, feedback had an average effect of d = 0.48, and high-information feedback reached
d = 0.99 (Wisniewski, Zierer and Hattie, 2020; Hattie and Timperley, 2007). Feedback can also
make performance worse when it points at the person rather than the task (Kluger and DeNisi,
1996), so the signal must name the rule, not the agent. Production monitoring practice says the
same: alert on symptoms the user would notice, and make the alert name the cause (Beyer et
al., 2016).

Mechanism: every check produces a one-line verdict. The verdict is printed as the first line
of every session, before the user's question. A watchdog re-runs every check on a timer, and a
red check older than 24 hours without a recorded decision blocks the agent until someone
decides.

### P2. A correction is recorded once and never typed again

Systems that keep user preferences as free text still violate them. In TRACE, a memory
system left 57.5% of preference checks violated, while compiling the same corrections into
runtime checks cut violations from 100% to 37.6% in one setting and to 2.0% in another (Zhou et
al., 2026). Gallego (2026) reports the same direction when feedback is distilled into a memory
the agent must call. The forgetting curve applies to the human as much as the model (Murre and
Dros, 2015).

Mechanism: every correction the owner types is appended, verbatim, to a log. The agent's own
mistakes are appended to a second log. The third occurrence of the same correction becomes a
row in the checks table: a name, a plain-words claim, and a command that exits 0 when the rule
holds. A sentence can be ignored; an exit code cannot.

### P3. The owner's taste is retained across sessions and tasks

Interactive machine learning showed a decade ago that systems improve fastest when the person
teaches through corrections in the flow of work (Amershi et al., 2014). Without long-term
memory, agents lose about 30% accuracy on questions that depend on earlier sessions (Wu et
al., 2024); with the user modelled explicitly, one 2026 system reached 78.8% on a long
conversation memory benchmark (Li, 2026). Memory architectures for agents are now standard
(Packer et al., 2023; Park et al., 2023).

Mechanism: corrections that cluster around one kind of work become a skill file, so the next
task of that kind starts from the owner's accumulated taste rather than from zero. Decisions
are written to memory files with dates and the reason, and loaded at session start.

### P4. Routine decisions are handed to the system so the owner's attention is kept for judgement

Working memory holds about four chunks (Cowan, 2001; Miller, 1956), and cognitive load limits
learning and problem solving (Sweller, 1988). Every routine decision the system makes is
attention the owner keeps.

Mechanism: hooks run at fixed moments (session start, before a tool, after a stop) and make
the routine decisions: block a secret, refuse a claim that has no source, refuse to end a turn
with an unresolved red check. Timed jobs do the recurring work overnight. The owner reviews
results and decides the exceptions.

### P5. The agent reflects on its own failures, with an external signal

Agents that reflect on a failed attempt do better on the next one: Reflexion raised HumanEval
pass@1 from 80% to 91% (Shinn et al., 2023), and Self-Refine reported about 20 points of
average gain across tasks (Madaan et al., 2023). The limit is also known: models cannot
reliably self-correct reasoning without an external signal (Huang et al., 2023). Experience
distilled across episodes helps (Zhao et al., 2023; Zhang et al., 2025).

Mechanism: the agent keeps its own mistake ledger and is scored on two things: noticing (did
it record the miss) and acting (did a rule or check change). The external signal is the checks
table: a deterministic exit code, not the model's opinion of itself.

### P6. Improvement is measured by counts that cannot be argued with, and every measure is watched for gaming

Monitoring goal progress improves goal attainment (d+ = 0.40 across 138 comparisons; Harkin
et al., 2016). Any measure that becomes a target invites gaming; the variants are catalogued
in Manheim and Garrabrant (2018), and the effect on social measures was named by Campbell.

Mechanism: no measure in the system is judged by a language model. Checks return exit codes.
Corrections are counted by word matching. A check that has never gone red is treated as
untested: every new check must be shown to fail on a planted break before it counts.

## 3. What it is not

- Not a memory tool. Memory is a part; the object is the change in behaviour that the memory causes.
- Not an enforcer. Today the system observes, names the broken rule, and repeats it at every session
  start until a decision is recorded (the author's own setup also blocks the end of a turn; the package
  does not ship that gate yet). It does not correct the agent's output by itself.
- Not a second agent. It is the instrumentation around one agent.
- Not a skills framework. Skills can live inside it; it is not made of them.
- Not a model benchmark. It measures one agent's work for one owner over weeks.

## 4. How to judge it

| Measure | Definition | Value on 12 Sep 2026 |
|---|---|---|
| Correction share | corrections as a share of the owner's messages, by word matching | June 4.5% (22 of 494); August 8.3% (82 of 991) |
| Checks that can fail | rows in the checks table, each proven to go red on a planted break | 11 shipped; 21 in the owner's live system |
| Time to detect | from a planted break to a red verdict | 1 to 2 s on demand; next tick on a 30-minute timer; 10 of 10 planted breaks caught, 0 false alarms in 20 clean runs |
| Red debt | red checks older than 24 h with no decision | 0 |
| Acting score | of recorded misses, how many changed a rule or check | 4 of 8 (11 Sep 2026) |

**OPEN.** The success criterion is not yet fixed. Two candidates: correction share returned
below 4.5% for a named month, or no correction repeated within 30 days. The owner decides.

## 5. Limitations

1. It observes and reports; it does not yet correct on its own. The acting score above is the
   honest number.
2. Only rules that a shell command can test are covered. Rules about tone, length, or judgement
   need a logger first.
3. n = 1. All numbers come from one owner over three months. Nothing here is a controlled study.
4. In a small test on 12 Sep 2026 (three coding tasks, 18 runs), two popular skill frameworks
   made no measurable difference against no framework; the tasks were too small to separate
   anything. The same caution applies to this system until a larger test exists.
5. Goodhart's risk is real. The correction share can be lowered by correcting less, not by the
   agent improving. That is why the checks table, not the correction share, is the primary measure.

## 6. Related work

**TRACE** (Zhou et al., 2026) is the closest prior work: it mines a user's chat corrections,
rewrites them as atomic rules, and compiles them into runtime checks for coding agents, with
benchmark results. This system shares that pipeline. What it adds: a timer that re-checks
every rule whether or not a session is running, a ledger of the agent's own mistakes with a
noticing and acting score, a red-debt rule that forces a decision on stale failures, and a
picture of every rule on the step where it applies.

**Agent memory**: MemGPT (Packer et al., 2023), Generative Agents (Park et al., 2023),
LongMemEval (Wu et al., 2024), User as Code (Li, 2026). These keep and retrieve; they do not
check.

**Instruction-file linters**: agnix (411 stars), schliff (16 stars). These score the text of an
instruction file once, statically. They do not run, and they cannot go red at 3 a.m.

**Skill frameworks and their benchmarks**: superpowers (285,525 stars), i-have-adhd (42,595),
SkillsBench (1,764; Li et al., 2026 found curated skills add 16.6 points and self-generated
skills add about nothing), SkillEvaluator (429). These change what the agent does; this system
measures whether it did it.

## 7. The documents that follow from this one

WHY.md (this document, cut to 800 words for the repository), PRINCIPLES.md (section 2 as seven
lines), NON-GOALS (section 3), GLOSSARY.md, docs/adr/ (one record per decision: hooks not
prose; watchdog on a timer; rules as a checks table), and a metrics file once the OPEN
criterion is fixed.

## 8. Worked example: one owner, three months

A solo founder in Bangkok began in July 2026 with one complaint: most outputs did not satisfy
him. He logged every correction (58 explicit ones by September) and every mistake the agent
recorded (250). He wrote 21 rules as commands and ran them every 30 minutes (1,190 runs by
10 Sep). Corrections rose from 4.5% to 8.3% of his messages between June and August while
rules were added as text, which is what led to the checks. Two skills built only from his
corrections, one for presentations and one for research, now produce work he accepts. On 12
Sep, ten planted rule breaks were caught 10 of 10 with no false alarms. On the same day his
own verdict was that the system watches well and corrects badly, which is the limitation in
section 5 and the next thing to build.

## References

Amershi, S., Cakmak, M., Knox, W. B. and Kulesza, T. (2014). Power to the People: The Role of Humans in Interactive Machine Learning. AI Magazine, 35(4).
Anthropic (2026a). The new rules of context engineering for Claude 5 generation models. claude.com/blog.
Anthropic (2026b). Steering Claude Code: skills, hooks, rules, subagents, and more. claude.com/blog.
Beyer, B., Jones, C., Petoff, J. and Murphy, N. R. (2016). Site Reliability Engineering, chapter Monitoring Distributed Systems. O'Reilly. sre.google.
Campbell, D. T. Assessing the impact of planned social change. Evaluation and Program Planning. doi 10.1016/0149-7189(79)90048-X.
Cowan, N. (2001). The magical number 4 in short-term memory. Behavioral and Brain Sciences. doi 10.1017/S0140525X01003922.
Gallego, V. (2026). Distilling Feedback into Memory-as-a-Tool. arXiv:2601.05960.
Harkin, B. et al. (2016). Does monitoring goal progress promote goal attainment? A meta-analysis. Psychological Bulletin, 142(2).
Hattie, J. and Timperley, H. (2007). The Power of Feedback. Review of Educational Research, 77(1). doi 10.3102/003465430298487.
Huang, J. et al. (2023). Large Language Models Cannot Self-Correct Reasoning Yet. arXiv:2310.01798.
Kluger, A. N. and DeNisi, A. (1996). The effects of feedback interventions on performance. Psychological Bulletin, 119(2).
Li, X. et al. (2026). SkillsBench. arXiv:2602.12670.
Li, Y. (2026). User as Code. arXiv:2606.16707.
Liu, N. F. et al. (2024). Lost in the Middle: How Language Models Use Long Contexts. TACL. arXiv:2307.03172.
Madaan, A. et al. (2023). Self-Refine: Iterative Refinement with Self-Feedback. arXiv:2303.17651.
Manheim, D. and Garrabrant, S. (2018). Categorizing Variants of Goodhart's Law. arXiv:1803.04585.
Miller, G. A. (1956). The magical number seven, plus or minus two. Psychological Review, 63.
Murre, J. M. J. and Dros, J. (2015). Replication and Analysis of Ebbinghaus' Forgetting Curve. PLOS ONE. doi 10.1371/journal.pone.0120644.
Packer, C. et al. (2023). MemGPT: Towards LLMs as Operating Systems. arXiv:2310.08560.
Park, J. S. et al. (2023). Generative Agents: Interactive Simulacra of Human Behavior. UIST. arXiv:2304.03442.
Qi, Y. et al. (2025). AgentIF: Benchmarking Instruction Following of Large Language Models in Agentic Scenarios. arXiv:2505.16944.
Shinn, N. et al. (2023). Reflexion: Language Agents with Verbal Reinforcement Learning. NeurIPS. arXiv:2303.11366.
Sweller, J. (1988). Cognitive Load During Problem Solving. Cognitive Science, 12.
Wisniewski, B., Zierer, K. and Hattie, J. (2020). The Power of Feedback Revisited. Frontiers in Psychology. doi 10.3389/fpsyg.2019.03087.
Wu, D. et al. (2024). LongMemEval. arXiv:2410.10813.
Zhang, Q. et al. (2025). Agentic Context Engineering. arXiv:2510.04618.
Zhao, A. et al. (2023). ExpeL: LLM Agents Are Experiential Learners. arXiv:2308.10144.
Zhou, Y. et al. (2026). Getting Better at Working With You (TRACE). arXiv:2606.13174.
