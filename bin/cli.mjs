#!/usr/bin/env node
// cli.mjs - what `npx metacognition` runs.
//
// With no arguments it installs: the code goes to ~/.claude/<APP>/, the hooks are added to
// settings.json, a timer is written, and the watchdog runs once so you see a verdict.
// Every other argument is passed straight to the watchdog: run, status, history, add.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..');
const args = process.argv.slice(2);

const first = args[0];
const installWords = new Set(['install', 'setup', undefined]);
const passThrough = new Set(['run', 'status', 'history', 'add', 'help', '--help', '-h']);

if (passThrough.has(first)) {
  const r = spawnSync(process.execPath, [path.join(HERE, 'watchdog.mjs'), ...args], { stdio: 'inherit' });
  process.exit(r.status ?? 1);
}

if (installWords.has(first) || first === '--dry-run' || first === '--uninstall' || first === '--no-hooks') {
  const flags = args.filter((a) => a.startsWith('--'));
  const r = spawnSync('bash', [path.join(ROOT, 'install.sh'), ...flags], { stdio: 'inherit' });
  process.exit(r.status ?? 1);
}

console.error(`unknown command: ${first}
usage:
  npx metacognition                 install and show the first verdict
  npx metacognition --dry-run       print what would happen, change nothing
  npx metacognition --uninstall     remove the hooks, the timer and the code
  npx metacognition --no-hooks      code, rules and timer only (after `claude plugin install`)
  npx metacognition status          print the last verdict
  npx metacognition history         how often each rule held
  npx metacognition add "<rule>" "<check command>"`);
process.exit(2);
