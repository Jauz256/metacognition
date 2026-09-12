---
name: With no verdict yet, the answer gives the run command
tags: [hook, first-run]
plugins: ["../.."]
runs: 3
max_turns: 3
timeout_seconds: 120
env:
  WATCHDOG_DIR: ./empty
---
Is metacognition running on this machine? If not, what exactly should I run? One line.
