# Plan

What is done, what is next, and what is deliberately left out. One file, kept short.

## Done

- [x] The watchdog: run every rule as a command, `status`, `history`, `add`
- [x] Canaries, so a blind watchdog reports BROKEN instead of GREEN
- [x] Three hooks: the session line, the mistake log, the loop scan
- [x] The picture: every rule on the step where it applies
- [x] The installer, with a dry run and an uninstall
- [x] `npx metacognition` as the install line
- [x] Four ready made rule sets, each tested clean and dirty
- [x] The shipped rules work with any agent, not only one
- [x] The test that runs on every change, on Linux and macOS, three Node versions

## Next

- [ ] A logo, and a short moving picture of the tool running
- [ ] READMEs in Chinese and Japanese
- [ ] A page on the web
- [ ] Publish to npm

## Left out on purpose

- No account, no service, no network call. It runs on your machine or not at all.
- No dependencies. Node built-ins and the Python standard library only.
- It does not try to make the agent obey. It measures.
