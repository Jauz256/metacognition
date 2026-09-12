# Security

## What this software does on your machine

- It runs the commands you put in your own `claims.tsv`, every 30 minutes, as you.
- It writes files under `~/.claude/metacognition/`.
- It adds three hooks to `~/.claude/settings.json`, after backing that file up.
- It writes one timer entry, a launchd agent on macOS or one crontab line on Linux.

It does not send anything over the network. It has no account, no service and no API key.

## The thing to understand before you install

`claims.tsv` is a list of shell commands, and the watchdog runs them. Treat that file the way you
treat a shell script. Read any rule before you paste it in, especially a rule you copied from
somewhere else.

## Reporting a problem

Email the address on the GitHub profile of the repository owner, or open a private security advisory
on GitHub. Please do not open a public issue.

Include what you ran, what happened, and your operating system. You will get a reply.
