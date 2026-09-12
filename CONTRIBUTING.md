# Contributing

Thanks for looking. This is a small project and changes are welcome.

## Before you open a pull request

1. Run the tests.

```sh
bash tests/run.sh
bash tests/run-tools.sh
```

Both must end with a passing line. Paste that line in your pull request.

2. Keep the project dependency free. Node built-ins and the Python standard library only.

3. Write plain English in comments, messages and documentation. Short sentences.

## Adding a rule to the shipped `claims.tsv`

A good shipped rule is true for almost everyone, not just for you. It must:

- Exit 0 when the rule holds, and non zero when it does not.
- Finish in under 20 seconds.
- Never wait for input, because stdin is closed.
- Do nothing except read. A check must never change a file.
- Skip cleanly when it does not apply, for example outside a git repository.

## Reporting a bug

Open an issue with the output of:

```sh
npx github:jazzs-thoughts/metacognition status
node --version
```

## Anything sensitive

See SECURITY.md. Do not open a public issue for a security problem.
