# Evals

Cases for `claude plugin eval`, Anthropic's own with-versus-without test for plugins.
Each case runs the same prompt with the plugin and without it, and the graders score both.
The delta is the number this plugin is worth. Run from the repo root:

```sh
claude plugin eval . --ablation with-without --no-publish
```

`plugin eval` is early access in Claude Code (September 2026). Until it is enabled on your
account the command prints "early access" and runs nothing.
