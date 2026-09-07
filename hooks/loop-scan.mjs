#!/usr/bin/env node
// loop-scan.mjs — finds the corrections you had to make more than once.
//
// Reads two files under ~/.claude/<APP>/:
//   mistakes.jsonl   records from hooks/mistake-log.mjs; a record whose verdict.kind is
//                    "complaint" is one correction (verdict.words is what you said)
//   no-log.jsonl     lines from the /no skill: { t, reason } is one correction,
//                    { t, mechanized, via } says a theme was closed with a check
//
// Corrections that share the same significant words are grouped. A group with MIN
// corrections (default 3) inside the last DAYS days (default 30) is a candidate: it should
// become a row in claims.tsv, not another note. A theme that was closed with a check and
// then shows up again is reported as a recurrence.
//
// Writes ~/.claude/<APP>/loop-candidates.md and prints the same text.
//
// Usage:  node hooks/loop-scan.mjs [--dir DIR] [--out FILE] [--days 30] [--min 3] [--quiet]
//   --dir    read the two log files from DIR instead of ~/.claude/<APP>
//   --out    write the report here instead of DIR/loop-candidates.md
//   --quiet  write the file, print only the last line ("candidates: N")
//
// Run it by hand, or on a timer. cron, once an hour:
//   10 * * * * node /ABSOLUTE/PATH/hooks/loop-scan.mjs --quiet
// Exit code is always 0, so a timer never sees a failure. Problems go to stderr.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const APP = 'rule-drift-watchdog';

// Words that carry no meaning for grouping. Add your own filler words here.
const STOP = new Set(['that', 'this', 'with', 'what', 'when', 'like', 'have', 'been', 'from',
  'want', 'look', 'good', 'really', 'again', 'something', 'make', 'making', 'keep', 'why',
  'are', 'the', 'and', 'not', 'for', 'after', 'should', 'more', 'first', 'also', 'there',
  'over', 'real', 'better', 'work', 'line', 'live', 'self', 'rule', 'need', 'just', 'will',
  'still', 'only', 'some', 'then', 'know', 'each', 'every', 'about', 'into', 'them', 'they',
  'were', 'most', 'please', 'dont', 'didnt', 'never', 'always', 'thing', 'things', 'here',
  'your', 'you', 'did', 'does', 'doing', 'done', 'used', 'using', 'same', 'twice', 'time',
  'times', 'because', 'would', 'could', 'which', 'where', 'than', 'very', 'much', 'many']);

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i > -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const QUIET = process.argv.includes('--quiet');
const DIR = arg('--dir', path.join(os.homedir(), '.claude', APP));
const OUT = arg('--out', path.join(DIR, 'loop-candidates.md'));
const DAYS = Number(arg('--days', 30));
const MIN = Number(arg('--min', 3));

// Crude stemmer, same as tools/rules-map/build.py: commits -> commit, passes -> pass,
// shipped -> ship, clarifying -> clarify.
function stem(w) {
  if (w.length > 5 && /(ss|sh|ch|x)es$/.test(w)) w = w.slice(0, -2);
  else if (w.length > 4 && w.endsWith('s') && !w.endsWith('ss')) w = w.slice(0, -1);
  if (w.length > 6 && w.endsWith('ing')) w = w.slice(0, -3);
  else if (w.length > 5 && w.endsWith('ed')) w = w.slice(0, -2);
  if (w.length > 3 && w[w.length - 1] === w[w.length - 2] && 'bdgmnprt'.includes(w[w.length - 1])) w = w.slice(0, -1);
  return w;
}
// Significant words of a sentence: letters only, 4+ chars, not in STOP, stemmed, unique.
function words(text) {
  const out = new Set();
  for (const w of String(text).toLowerCase().replace(/[^a-z]+/g, ' ').split(' ')) {
    if (w.length >= 4 && !STOP.has(w)) out.add(stem(w));
  }
  return [...out];
}
function shared(a, b) { const s = new Set(b); return a.filter((w) => s.has(w)).length; }

function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean)
    .map((l) => { try { return JSON.parse(l); } catch { return null; } })
    .filter(Boolean);
}

function slug(ws) { return ws.slice(0, 3).join('-').replace(/[^a-z-]/g, '') || 'correction'; }
function day(t) { return String(t || '').slice(0, 10); }

let report = '';
let candidates = [];
try {
  const now = Date.now();
  const since = new Date(now - DAYS * 86400000).toISOString();

  // 1) Collect every correction with its date and source.
  const corrections = [];
  for (const r of readJsonl(path.join(DIR, 'mistakes.jsonl'))) {
    if (r.verdict && r.verdict.kind === 'complaint' && r.verdict.words) {
      corrections.push({ t: r.verdict.t || r.t || '', text: String(r.verdict.words).replace(/^\/no\s*/i, ''), src: 'mistakes' });
    }
  }
  const mechanized = [];
  for (const r of readJsonl(path.join(DIR, 'no-log.jsonl'))) {
    if (r.mechanized) mechanized.push({ t: r.t || r.ts || '', theme: String(r.mechanized), via: r.via || '?' });
    else if (r.reason || r.verbatim) corrections.push({ t: r.t || r.ts || '', text: String(r.reason || r.verbatim), src: 'no-log' });
  }
  for (const c of corrections) c.words = words(c.text);
  corrections.sort((a, b) => (a.t < b.t ? -1 : a.t > b.t ? 1 : 0));
  const recent = corrections.filter((c) => c.t >= since && c.words.length);

  // 2) Group: a correction joins the group whose seed shares 2+ words with it
  //    (or all of its words, for one-word corrections). Otherwise it starts a group.
  const groups = [];
  for (const c of recent) {
    let best = null, bestN = 0;
    for (const g of groups) {
      const n = shared(c.words, g.seed);
      const full = n === c.words.length && n === g.seed.length;
      if ((n >= 2 || full) && n > bestN) { best = g; bestN = n; }
    }
    if (best) best.members.push(c); else groups.push({ seed: c.words, members: [c] });
  }

  // 3) A group is closed if a "mechanized" theme shares 2+ words (or all) with its seed and
  //    is dated after the group's last member. Otherwise, 3+ members = candidate.
  const closedBy = (g) => mechanized.find((m) => {
    const mw = words(m.theme); const n = shared(mw, g.seed);
    return (n >= 2 || (n === mw.length && n > 0)) && m.t >= g.members[g.members.length - 1].t;
  });
  candidates = groups.filter((g) => g.members.length >= MIN && !closedBy(g))
    .sort((a, b) => b.members.length - a.members.length);

  // 4) Recurrence: a closed theme whose words appear in a later correction.
  const alerts = [];
  for (const m of mechanized) {
    const mw = words(m.theme);
    for (const c of corrections) {
      if (c.t > m.t && shared(mw, c.words) >= Math.min(2, mw.length) && mw.length) {
        alerts.push(`- theme "${m.theme}" (closed ${day(m.t)} via ${m.via}) came back on ${day(c.t)}: "${c.text.slice(0, 120)}"`);
      }
    }
  }

  // 5) Write the report.
  const lines = [];
  lines.push(`# Loop candidates — ${day(new Date().toISOString())}`);
  lines.push('');
  lines.push(`${recent.length} corrections in the last ${DAYS} days (${corrections.filter((c) => c.src === 'mistakes').length} from mistakes.jsonl, ${corrections.filter((c) => c.src === 'no-log').length} from no-log.jsonl, all time). ${mechanized.length} themes closed with a check.`);
  lines.push('Grouping is by shared words. Treat each candidate as a pointer to reread the log, not a verdict.');
  lines.push('');
  lines.push(`## Should become a check (${candidates.length})`);
  lines.push('');
  if (!candidates.length) lines.push(`No correction repeated ${MIN} times in ${DAYS} days.`);
  candidates.forEach((g, i) => {
    const last = g.members[g.members.length - 1];
    const dates = g.members.map((c) => day(c.t)).join(', ');
    const claim = last.text.replace(/[\t\n\r]+/g, ' ').trim().slice(0, 140);
    lines.push(`### ${i + 1}. "${claim}"`);
    lines.push(`This correction happened ${g.members.length} times (${dates}). It is still only a note. It should become a check.`);
    const others = g.members.slice(0, -1).map((c) => `"${c.text.replace(/\s+/g, ' ').trim().slice(0, 100)}"`);
    if (others.length) lines.push(`Other wordings: ${others.join('; ')}`);
    lines.push('Suggested claims.tsv row. Replace the third column with a command that exits 0 when the rule holds; until then the row is red on purpose:');
    lines.push('');
    lines.push(`    ${slug(g.seed)}\t${claim}\tfalse # TODO: a command that exits 0 when this rule holds`);
    lines.push('');
  });
  lines.push('## Came back after it was closed');
  lines.push('');
  lines.push(alerts.length ? alerts.join('\n') : 'No closed theme came back.');
  lines.push('');
  lines.push('Next: paste the row into claims.tsv, write the check, run the watchdog once, then append a "mechanized" line with the /no skill (step 4).');
  report = lines.join('\n') + '\n';
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, report);
} catch (e) {
  process.stderr.write(`loop-scan: ${e.message}\n`);
}
if (!QUIET && report) process.stdout.write(report + '\n');
process.stdout.write(`candidates: ${candidates.length}\n`);
process.exit(0);
