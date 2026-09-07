#!/usr/bin/env node
// mistake-log.mjs — records a correction pair: what the AI made, what you said next, the redo.
//
// Two hook events, one file:
//   Stop              the AI finished a turn. Record what it made (files written or edited,
//                     files a shell command wrote) and the last thing it said.
//   UserPromptSubmit  you typed the next message. That message becomes the verdict on the
//                     last open record: "complaint", "accept" or "neutral". If the turn
//                     after a complaint is a redo, it is linked to the complained record.
//
// The pair (first try -> complaint -> redo -> accept) is the lesson, with the WHAT in it.
// hooks/loop-scan.mjs reads the complaints and finds the ones you had to say 3 times.
//
// Wire it in ~/.claude/settings.json (use the absolute path of this file):
//
//   "hooks": {
//     "Stop": [
//       { "matcher": "*", "hooks": [ { "type": "command", "command": "node /ABSOLUTE/PATH/hooks/mistake-log.mjs" } ] }
//     ],
//     "UserPromptSubmit": [
//       { "matcher": "*", "hooks": [ { "type": "command", "command": "node /ABSOLUTE/PATH/hooks/mistake-log.mjs" } ] }
//     ]
//   }
//
// Output: ~/.claude/<APP>/mistakes.jsonl, one JSON object per line:
//   { t, session, made: [paths], cmds, said, redo_of, verdict: { t, kind, words } | null }
//
// Reads the hook payload from stdin. Never blocks the AI: every error is swallowed and
// written to ~/.claude/<APP>/hook-errors.log. Exit code is always 0.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const APP = 'rule-drift-watchdog';

// Word lists that decide the verdict. Edit them to match how you talk.
// A message that matches COMPLAINT is a correction. A message that starts like ACCEPT is a yes.
const COMPLAINT = /(^\/no\b|\bwrong\b|\bmistake\b|\bbad\b|\bnot (good|right|correct|working|clear|what i)\b|don'?t like|didn'?t (ask|want|say|mean)|\bbroken\b|\bugly\b|why (did|didn'?t|don'?t) you|\bstill (wrong|broken|not)\b|are you sure|double.?check|\bfix it\b|\bredo\b|\bundo\b|\brevert\b|\bwtf\b|\bagain and again\b|\bnot this\b)/i;
const ACCEPT = /^(y|yes|yeah|yep|ok|okay|good|nice|great|perfect|done|cool|correct|thanks|thank you|love it|looks good|lgtm|that'?s it|good job)\b/i;

const H = os.homedir();
const DIR = path.join(H, '.claude', APP);
const FILE = path.join(DIR, 'mistakes.jsonl');

function readAll() {
  if (!fs.existsSync(FILE)) return [];
  return fs.readFileSync(FILE, 'utf8').split('\n').filter(Boolean)
    .map((l) => { try { return JSON.parse(l); } catch { return null; } })
    .filter(Boolean);
}
function writeAll(rows) {
  fs.mkdirSync(DIR, { recursive: true });
  fs.writeFileSync(FILE, rows.map((r) => JSON.stringify(r)).join('\n') + '\n');
}
function shortHome(p) { return p.startsWith(H) ? '~' + p.slice(H.length) : p; }

// The transcript path comes in the payload. If it is missing, derive it the way the CLI
// names project folders: the working directory with "/" and "." turned into "-".
function transcriptPath(input) {
  if (input.transcript_path && fs.existsSync(input.transcript_path)) return input.transcript_path;
  const cwd = String(input.cwd || process.cwd()).replace(/[/.]/g, '-');
  return path.join(H, '.claude', 'projects', cwd, `${input.session_id}.jsonl`);
}

// Files a shell command wrote: only when the command redirects, moves, copies or writes.
const WRITES = /(^|[^>])>>?\s*["'~./]|\bmv\s|\bcp\s|\btee\s|writeFile|json\.dump|open\([^)]*['"]w/;
const PATH_RE = /(?:~|\.{0,2})\/[^\s"'`)]+?\.[a-z0-9]{1,6}\b/g;
const SKIP = /^(\/dev\/|\/tmp\/|\/private\/tmp\/)|\.jsonl$|settings\.json$/;

function onStop(input, sid, now) {
  const tpath = transcriptPath(input);
  if (!fs.existsSync(tpath)) return;
  const lines = fs.readFileSync(tpath, 'utf8').split('\n');
  // The turn starts at the last real user message (typed text, not a tool result).
  let start = 0;
  for (let i = lines.length - 1; i >= 0; i--) {
    let d; try { d = JSON.parse(lines[i]); } catch { continue; }
    if (d.type !== 'user') continue;
    const c = d.message && d.message.content;
    if (typeof c === 'string' || (Array.isArray(c) && c.some((b) => b && b.type === 'text'))) { start = i; break; }
  }
  const made = new Set(); let said = ''; let cmds = 0;
  for (let i = start; i < lines.length; i++) {
    let d; try { d = JSON.parse(lines[i]); } catch { continue; }
    if (d.type !== 'assistant') continue;
    const c = d.message && d.message.content; if (!Array.isArray(c)) continue;
    for (const b of c) {
      if (b && b.type === 'text' && b.text && b.text.trim()) said = b.text.trim();
      if (!b || b.type !== 'tool_use') continue;
      const inp = b.input || {};
      if ((b.name === 'Write' || b.name === 'Edit' || b.name === 'MultiEdit' || b.name === 'NotebookEdit') && (inp.file_path || inp.notebook_path)) {
        made.add(shortHome(inp.file_path || inp.notebook_path));
      }
      if (b.name === 'Bash' && inp.command) {
        cmds++;
        const cmd = String(inp.command);
        if (WRITES.test(cmd)) for (const m of cmd.match(PATH_RE) || []) if (!SKIP.test(m)) made.add(shortHome(m));
      }
    }
  }
  const rows = readAll();
  // If the previous record in this session got a complaint, this turn is its redo.
  let redo_of = null;
  for (let i = rows.length - 1; i >= 0; i--) {
    if (rows[i].session !== sid) continue;
    if (rows[i].verdict && rows[i].verdict.kind === 'complaint') redo_of = rows[i].t;
    break;
  }
  rows.push({ t: now, session: sid, made: [...made].slice(0, 20), cmds, said: said.replace(/\s+/g, ' ').slice(0, 400), redo_of, verdict: null });
  writeAll(rows);
}

function onPrompt(input, sid, now) {
  const words = String(input.prompt || '').replace(/\s+/g, ' ').trim().slice(0, 600);
  if (!words) return;
  let kind = 'neutral';
  if (COMPLAINT.test(words)) kind = 'complaint';
  else if (ACCEPT.test(words)) kind = 'accept';
  const rows = readAll();
  for (let i = rows.length - 1; i >= 0; i--) {
    if (rows[i].session === sid && rows[i].verdict === null) {
      rows[i].verdict = { t: now, kind, words };
      writeAll(rows);
      return;
    }
  }
}

try {
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  const sid = String(input.session_id || 'unknown').slice(0, 8);
  const now = new Date().toISOString();
  if (input.hook_event_name === 'Stop') onStop(input, sid, now);
  else if (input.hook_event_name === 'UserPromptSubmit') onPrompt(input, sid, now);
} catch (e) {
  try { fs.mkdirSync(DIR, { recursive: true }); fs.appendFileSync(path.join(DIR, 'hook-errors.log'), `mistake-log.mjs ${new Date().toISOString()} ${e.message}\n`); } catch {}
}
process.exit(0);
