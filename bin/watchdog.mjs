#!/usr/bin/env node
// watchdog.mjs - runs every rule in claims.tsv as a shell check and records which ones fail.
//
// A rule in CLAUDE.md is a sentence. The AI can read it and still not follow it.
// This file turns each rule into a command that must exit 0, runs all of them on a
// timer, and keeps the results. Over time you can see which rules hold and which drift.
//
// How it stays honest:
//   1. Every check runs as a child process with a timeout. A check that hangs or
//      crashes is a failed check, never a silent pass.
//   2. Canaries. Before the results are trusted, the same runner is pointed at checks
//      that are built to fail. If any of them comes back GREEN, the runner is blind and
//      the verdict is BROKEN, not GREEN.
//   3. A lock stops two runs from writing at the same time. Result files are written
//      atomically: write a temp file, then rename it.
//   4. Every run appends a receipt with the result of each rule. The history command
//      reads those receipts.
//
// Commands:
//   watchdog.mjs run [--quiet]            run every check and write the verdict
//   watchdog.mjs status                   print the last verdict, one line per rule
//   watchdog.mjs add "<claim>" "<check>"  append a rule to claims.tsv and check it once
//   watchdog.mjs history [N]              per rule, how many of the last N runs were green
//
// Files, all under ~/.claude/<APP>/:
//   claims.tsv      the rules: id, claim in plain words, check command
//   verdict.json    the last run in full
//   verdict.txt     the last run in one line
//   state.json      when each rule first went red, and the previous failure set
//   receipts.jsonl  one line at the start and one at the end of every run
//
// Environment overrides (used by the tests; safe to ignore):
//   WATCHDOG_DIR               where the files above live
//   WATCHDOG_CLAIM_TIMEOUT_MS  how long one check may run (default 20000)
//   WATCHDOG_SHELL             shell that runs the checks (default bash)
//
// Exit codes for run: 0 GREEN, 1 RED, 2 BROKEN. Nothing here speaks, opens a window,
// or touches the network. It prints and writes files only.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const APP = 'rule-drift-watchdog';
const INTERVAL_MIN = 30; // the timer runs this often; a verdict older than 2 intervals is stale

const DIR = process.env.WATCHDOG_DIR || path.join(os.homedir(), '.claude', APP);
const CLAIMS = path.join(DIR, 'claims.tsv');
const VERDICT_JSON = path.join(DIR, 'verdict.json');
const VERDICT_TXT = path.join(DIR, 'verdict.txt');
const STATE = path.join(DIR, 'state.json');
const RECEIPTS = path.join(DIR, 'receipts.jsonl');
const LOCK = path.join(DIR, '.run.lock');
const CLAIM_TIMEOUT_MS = Number(process.env.WATCHDOG_CLAIM_TIMEOUT_MS) || 20000;
const SHELL = process.env.WATCHDOG_SHELL || 'bash';
const LOCK_STALE_MS = 5 * 60 * 1000;
const LEDGER_HEADER = '# id\tclaim in plain words\tcheck (must exit 0)\n';

const runId = `${Date.now()}-${process.pid}`;

// ---------------------------------------------------------------- small helpers

function receipt(fields) {
  try {
    fs.appendFileSync(RECEIPTS, JSON.stringify({ ts: new Date().toISOString(), runId, ...fields }) + '\n');
  } catch { /* a receipt that cannot be written must not stop the run */ }
}

function writeAtomic(file, body) {
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, body);
  fs.renameSync(tmp, file);
}

function loadJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function loadText(file) {
  try { return fs.readFileSync(file, 'utf8'); } catch { return ''; }
}

function clock(iso) {
  const d = iso ? new Date(iso) : new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// ---------------------------------------------------------------- the ledger

// One rule per line, three columns separated by a tab:
//   id <TAB> claim in plain words <TAB> check command (must exit 0)
// Blank lines and lines starting with # are ignored. A line that does not have three
// columns is reported as a problem, not skipped in silence.
function parseLedger(text) {
  const rules = [];
  const problems = [];
  const seen = new Set();
  text.split('\n').forEach((line, index) => {
    if (!line.trim() || line.startsWith('#')) return;
    const cols = line.split('\t');
    if (cols.length < 3 || !cols[0].trim() || !cols[2].trim()) {
      problems.push(`line ${index + 1} does not have 3 tab-separated columns`);
      return;
    }
    const id = cols[0].trim();
    if (seen.has(id)) {
      problems.push(`line ${index + 1}: duplicate id "${id}"`);
      return;
    }
    seen.add(id);
    rules.push({ id, claim: cols[1].trim(), check: cols.slice(2).join('\t').trim() });
  });
  return { rules, problems };
}

// ---------------------------------------------------------------- running one check

// The check runs in a child shell. stdin is closed, so a check that tries to read input
// fails at once instead of hanging. Anything other than exit 0 is RED.
function runCheck(rule, timeoutMs = CLAIM_TIMEOUT_MS) {
  const started = Date.now();
  const r = spawnSync(SHELL, ['-c', rule.check], {
    timeout: timeoutMs,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, WATCHDOG_DIR: DIR, WATCHDOG_APP: APP },
  });
  const item = { id: rule.id, claim: rule.claim, status: 'RED', msg: '', ms: Date.now() - started };
  if (r.error && r.error.code === 'ETIMEDOUT') { item.msg = `timed out after ${timeoutMs} ms`; return item; }
  if (r.error) { item.msg = `could not run: ${r.error.message}`; return item; }
  if (r.signal) { item.msg = `killed by ${r.signal}`; return item; }
  if (r.status !== 0) {
    const lastLine = (r.stderr || r.stdout || '').trim().split('\n').pop() || '';
    item.msg = `exit ${r.status}` + (lastLine ? ` - ${lastLine.slice(0, 160)}` : '');
    return item;
  }
  item.status = 'GREEN';
  item.msg = 'holds';
  return item;
}

// ---------------------------------------------------------------- canaries

// Checks that are built to fail. Each one goes through the real parser and the real
// runner and must come back RED. One GREEN here means the watchdog is blind.
const CANARY_LEDGER = [
  'canary-false\ta check that exits 1 must read RED\tfalse',
  `canary-missing\ta check whose command does not exist must read RED\tno-such-command-${APP}`,
  'canary-hang\ta check that hangs must be cut off and read RED\tsleep 10',
].join('\n');
const CANARY_HANG_TIMEOUT_MS = 1000;
const CANARY_COUNT = 4; // the three rows above, plus the malformed-line parse check

function runCanaries() {
  const blind = [];
  const { rules, problems } = parseLedger(CANARY_LEDGER);
  if (problems.length || rules.length !== 3) blind.push('the canary ledger did not parse');
  for (const rule of rules) {
    const timeout = rule.id === 'canary-hang' ? CANARY_HANG_TIMEOUT_MS : CLAIM_TIMEOUT_MS;
    const item = runCheck(rule, timeout);
    if (item.status !== 'RED') blind.push(`${rule.id} read ${item.status}`);
  }
  if (parseLedger('a line with no tabs at all').problems.length !== 1) blind.push('a malformed ledger line was not reported');
  return blind;
}

// ---------------------------------------------------------------- lock

function takeLock() {
  try { fs.mkdirSync(LOCK); return true; } catch { /* someone holds it, or it is stale */ }
  try {
    if (Date.now() - fs.statSync(LOCK).mtimeMs > LOCK_STALE_MS) {
      fs.rmSync(LOCK, { recursive: true, force: true });
      fs.mkdirSync(LOCK);
      return true;
    }
  } catch { /* fall through */ }
  return false;
}

function releaseLock() {
  try { fs.rmSync(LOCK, { recursive: true, force: true }); } catch { /* nothing to do */ }
}

// ---------------------------------------------------------------- commands

function cmdRun(quiet) {
  fs.mkdirSync(DIR, { recursive: true });
  if (!takeLock()) {
    console.log(`${APP}: another run holds the lock, skipping`);
    return 0;
  }
  try {
    return runOnce(quiet);
  } finally {
    releaseLock();
  }
}

function runOnce(quiet) {
  receipt({ phase: 'start' });
  const started = Date.now();
  const state = loadJson(STATE, {});
  const items = [];

  const ledgerText = fs.existsSync(CLAIMS) ? loadText(CLAIMS) : null;
  if (ledgerText === null) {
    items.push({ id: 'ledger', claim: 'claims.tsv exists', status: 'RED', msg: `missing at ${CLAIMS}`, ms: 0 });
  } else {
    const { rules, problems } = parseLedger(ledgerText);
    for (const p of problems) {
      items.push({ id: 'ledger', claim: 'every row in claims.tsv has 3 columns', status: 'RED', msg: p, ms: 0 });
    }
    if (rules.length === 0 && problems.length === 0) {
      items.push({ id: 'ledger', claim: 'claims.tsv has at least one rule', status: 'RED', msg: 'no rules found', ms: 0 });
    }
    for (const rule of rules) items.push(runCheck(rule));
  }

  const blind = runCanaries();
  const reds = items.filter((i) => i.status === 'RED');
  const ruleIds = [...new Set(items.map((i) => i.id))];

  // Remember when each rule first went red, so a long-standing failure says so.
  const now = Date.now();
  const redSince = state.redSince || {};
  for (const r of reds) if (!redSince[r.id]) redSince[r.id] = now;
  for (const id of Object.keys(redSince)) if (!reds.some((r) => r.id === id)) delete redSince[id];
  for (const r of reds) {
    const hours = Math.floor((now - redSince[r.id]) / 3600000);
    if (hours >= 24) r.msg += ` (red for ${hours} h)`;
  }

  const overall = blind.length ? 'BROKEN' : reds.length ? 'RED' : 'GREEN';
  let sentence;
  if (overall === 'BROKEN') {
    sentence = `${APP} BROKEN: the runner did not catch its own planted failures (${blind.join('; ')}). Do not trust any green until this is fixed.`;
  } else if (overall === 'RED') {
    const shown = reds.slice(0, 3).map((r) => `${r.id} (${r.msg})`).join('; ');
    const more = reds.length > 3 ? `; and ${reds.length - 3} more` : '';
    sentence = `${APP} RED: ${reds.length} of ${ruleIds.length} rules broken: ${shown}${more}`;
  } else {
    sentence = `${APP} GREEN: all ${ruleIds.length} rules hold (${clock().slice(11)}).`;
  }

  // The failure set, not just the colour. A new failure joining an old one is a change.
  const failKey = [overall, ...reds.map((r) => r.id).sort(), ...blind].join('|');
  const changed = state.lastFailKey !== undefined && state.lastFailKey !== failKey;

  const verdict = {
    app: APP,
    ts: new Date().toISOString(),
    overall,
    sentence,
    changed,
    intervalMin: INTERVAL_MIN,
    rules: ruleIds.length,
    items,
    canaries: { planted: CANARY_COUNT, blind },
    tookMs: Date.now() - started,
  };
  writeAtomic(VERDICT_JSON, JSON.stringify(verdict, null, 2) + '\n');
  writeAtomic(VERDICT_TXT, sentence + '\n');

  // One status per rule id for the history command. A rule with any RED row is RED.
  const claims = {};
  for (const id of ruleIds) claims[id] = items.some((i) => i.id === id && i.status === 'RED') ? 'RED' : 'GREEN';
  receipt({ phase: 'end', overall, reds: reds.length, blind: blind.length, tookMs: verdict.tookMs, claims });

  state.lastOverall = overall;
  state.lastFailKey = failKey;
  state.lastRunTs = verdict.ts;
  state.redSince = redSince;
  try { writeAtomic(STATE, JSON.stringify(state, null, 2) + '\n'); } catch { /* state is a convenience, not the verdict */ }

  if (!quiet || overall !== 'GREEN') {
    console.log(sentence);
    if (!quiet) for (const r of reds) console.log(`  RED    ${r.id}: ${r.msg}`);
    if (changed) console.log(`  (changed since the previous run)`);
  }
  return overall === 'GREEN' ? 0 : overall === 'RED' ? 1 : 2;
}

function cmdStatus() {
  const v = loadJson(VERDICT_JSON, null);
  if (!v || !v.ts) {
    console.log(`${APP}: no verdict yet. Run: node ${process.argv[1]} run`);
    return 1;
  }
  const ageMin = Math.max(0, Math.round((Date.now() - Date.parse(v.ts)) / 60000));
  const stale = ageMin > 2 * INTERVAL_MIN;
  console.log(v.sentence);
  console.log(`last run ${clock(v.ts)} (${ageMin} min ago)` + (stale ? ` - STALE, the timer should run every ${INTERVAL_MIN} min` : ''));
  for (const i of v.items || []) {
    console.log(`  ${i.status.padEnd(6)} ${i.id.padEnd(26)} ${i.claim}${i.status === 'RED' ? ` - ${i.msg}` : ''}`);
  }
  if (v.canaries && v.canaries.blind && v.canaries.blind.length) {
    console.log(`  canaries blind: ${v.canaries.blind.join('; ')}`);
  }
  return 0;
}

function cmdAdd(claim, check) {
  if (!claim || !check) {
    console.error(`usage: watchdog.mjs add "<claim in plain words>" "<check command that must exit 0>"`);
    return 2;
  }
  if (/[\t\r\n]/.test(claim) || /[\t\r\n]/.test(check)) {
    console.error('the claim and the check must not contain tabs or newlines');
    return 2;
  }
  fs.mkdirSync(DIR, { recursive: true });
  let text = loadText(CLAIMS);
  const existing = parseLedger(text).rules.map((r) => r.id);
  const base = claim.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter(Boolean).slice(0, 4).join('-') || 'rule';
  let id = base;
  for (let n = 2; existing.includes(id); n++) id = `${base}-${n}`;
  if (!text) text = LEDGER_HEADER;
  if (!text.endsWith('\n')) text += '\n';
  writeAtomic(CLAIMS, `${text}${id}\t${claim}\t${check}\n`);
  console.log(`added ${id} to ${CLAIMS}`);
  const item = runCheck({ id, claim, check });
  console.log(`${item.status.padEnd(6)} ${id}: ${item.msg}`);
  return 0;
}

// The rule-drift meter: for each rule, how many of the last N completed runs were green.
// Worst rules first.
function cmdHistory(arg) {
  const n = Number(arg) > 0 ? Number(arg) : 48;
  const runs = [];
  for (const line of loadText(RECEIPTS).split('\n')) {
    if (!line.trim()) continue;
    try {
      const o = JSON.parse(line);
      if (o.phase === 'end' && o.claims) runs.push(o);
    } catch { /* a damaged line is skipped */ }
  }
  const last = runs.slice(-n);
  if (!last.length) {
    console.log(`${APP}: no completed runs yet in ${RECEIPTS}`);
    return 1;
  }
  const current = parseLedger(loadText(CLAIMS)).rules.map((r) => r.id);
  const ids = new Set(current);
  for (const r of last) for (const id of Object.keys(r.claims)) ids.add(id);

  const rows = [];
  for (const id of ids) {
    let green = 0;
    let seen = 0;
    let lastStatus = '';
    for (const r of last) {
      const s = r.claims[id];
      if (!s) continue;
      seen++;
      if (s === 'GREEN') green++;
      lastStatus = s;
    }
    rows.push({ id, green, seen, lastStatus, inLedger: current.includes(id) });
  }
  const rate = (r) => (r.seen ? r.green / r.seen : 1);
  rows.sort((a, b) => rate(a) - rate(b) || a.id.localeCompare(b.id));

  console.log(`${APP} history: last ${last.length} run${last.length === 1 ? '' : 's'}, ${clock(last[0].ts)} to ${clock(last[last.length - 1].ts)}`);
  for (const r of rows) {
    let note = '';
    if (!r.inLedger) note = 'no longer in claims.tsv';
    else if (!r.seen) note = 'no runs yet';
    else if (r.lastStatus === 'RED') note = 'RED now';
    const count = r.seen
      ? `${String(r.green).padStart(3)}/${String(r.seen).padEnd(3)} green ${String(Math.round((100 * r.green) / r.seen)).padStart(3)}%`
      : '  -                 ';
    console.log(`  ${r.id.padEnd(26)} ${count}  ${note}`.trimEnd());
  }
  return 0;
}

function usage() {
  console.log([
    `${APP}`,
    '  watchdog.mjs run [--quiet]            run every check and write the verdict',
    '  watchdog.mjs status                   print the last verdict',
    '  watchdog.mjs add "<claim>" "<check>"  append a rule to claims.tsv',
    '  watchdog.mjs history [N]              pass rate per rule over the last N runs (default 48)',
    `files: ${DIR}`,
  ].join('\n'));
}

// ---------------------------------------------------------------- main

const args = process.argv.slice(2);
const quiet = args.includes('--quiet');
const words = args.filter((a) => a !== '--quiet');
const command = words[0] || 'run';
let code = 0;
switch (command) {
  case 'run': code = cmdRun(quiet); break;
  case 'status': code = cmdStatus(); break;
  case 'add': code = cmdAdd(words[1], words[2]); break;
  case 'history': code = cmdHistory(words[1]); break;
  case 'help': case '-h': case '--help': usage(); break;
  default: usage(); code = 2;
}
process.exit(code);
