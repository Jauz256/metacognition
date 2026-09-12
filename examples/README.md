# Ready made rule sets

Copy the lines you want into your own `~/.claude/metacognition/claims.tsv`, or point the watchdog
at one of these files to try it:

```sh
cp examples/javascript.tsv ~/.claude/metacognition/claims.tsv
npx github:jazzs-thoughts/metacognition run
```

Each file is tab separated: `id`, the rule in plain words, then the command that must exit 0.

| File | For |
|---|---|
| `javascript.tsv` | A JavaScript or TypeScript project |
| `python.tsv` | A Python project |
| `writing.tsv` | Writing, notes and documents, not code |
| `agent-discipline.tsv` | Any project where an AI agent does the work: where files land, whether the work was planned, whether it was proved |

Every check here reads only. None of them change a file. All of them skip cleanly when they do not
apply, so a rule about tests does nothing in a repository with no tests.
