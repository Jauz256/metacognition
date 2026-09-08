#!/usr/bin/env python3
"""build.py - draws every rule on the step of the work where it applies.

Inputs
  --rules      a CLAUDE.md (or any markdown). One rule per top-level bullet: a line that
               starts with "- " or "* ". Indented sub-bullets belong to their parent.
  --claims     claims.tsv, tab-separated: id, claim in plain words, check command.
               A rule that a claim enforces is a "mechanism". The rest are "notes".
  --verdict    the watchdog's verdict.json. A claim marked RED puts a red ring on its rule.
  --placement  placement.json: the steps, their keywords, optional pins and links.
               Default: the placement.json next to this script.
  --out        where to write the SVG (default ./rules-map.svg). A PNG with the same name
               is written too when Playwright for Python is installed. --no-png skips it.
  --list       print one line per rule (id, step, claims, red) and exit. Use the ids in
               placement.json pins and links.

How a rule finds its step: a pin wins; else the step whose keywords appear most in the
rule; a tie goes to the earlier step; no keyword at all puts it in step 0, "unplaced".
How a claim finds its rule: a link wins; else the rule that shares 2+ significant words
with the claim's plain-words column. A claim that matches no rule is named in the
footer of the picture, never hidden.

Standard library only. Playwright is optional and detected when the script runs.
"""
import argparse
import html
import json
import os
import re
import sys

APP = 'metacognition'
HERE = os.path.dirname(os.path.abspath(__file__))

# Words that carry no meaning when matching a claim to a rule.
STOP = {'that', 'this', 'with', 'what', 'when', 'like', 'have', 'been', 'from', 'want', 'look',
        'good', 'really', 'again', 'something', 'make', 'making', 'keep', 'why', 'are', 'the',
        'and', 'not', 'for', 'after', 'should', 'more', 'first', 'also', 'there', 'over', 'real',
        'better', 'work', 'line', 'live', 'self', 'rule', 'need', 'just', 'will', 'still', 'only',
        'some', 'then', 'know', 'each', 'every', 'about', 'into', 'them', 'they', 'were', 'most',
        'please', 'dont', 'didnt', 'never', 'always', 'thing', 'things', 'here', 'your', 'you',
        'did', 'does', 'doing', 'done', 'used', 'using', 'same', 'twice', 'time', 'times',
        'because', 'would', 'could', 'which', 'where', 'than', 'very', 'much', 'many'}


def stem(w):
    """Crude stemmer: commits -> commit, passes -> pass, shipped -> ship, clarifying -> clarify."""
    if len(w) > 5 and re.search(r'(ss|sh|ch|x)es$', w):
        w = w[:-2]
    elif len(w) > 4 and w.endswith('s') and not w.endswith('ss'):
        w = w[:-1]
    if len(w) > 6 and w.endswith('ing'):
        w = w[:-3]
    elif len(w) > 5 and w.endswith('ed'):
        w = w[:-2]
    if len(w) > 3 and w[-1] == w[-2] and w[-1] in 'bdgmnprt':
        w = w[:-1]
    return w


def words(text, min_len=4, stop=STOP):
    """Unique stems of the words in text. min_len and stop decide what counts."""
    out = []
    for w in re.sub(r'[^a-z]+', ' ', text.lower()).split():
        if len(w) >= min_len and w not in stop:
            s = stem(w)
            if s not in out:
                out.append(s)
    return out


def shared(a, b):
    return len(set(a) & set(b))


def parse_rules(path):
    """Top-level bullets become rules. Continuation lines are joined. Code fences are skipped."""
    rules, cur, fence = [], None, False
    with open(path, encoding='utf-8', errors='ignore') as f:
        for raw in f:
            line = raw.rstrip('\n')
            if line.strip().startswith('```'):
                fence = not fence
                continue
            if fence:
                continue
            m = re.match(r'^ ?[-*]\s+(.*\S)\s*$', line)
            if m:
                cur = {'text': m.group(1)}
                rules.append(cur)
            elif re.match(r'^\s{2,}[-*]\s', line):
                continue  # a sub-bullet: detail of the parent, not a rule of its own
            elif cur and re.match(r'^\s{2,}\S', line):
                cur['text'] += ' ' + line.strip()
            else:
                cur = None
    seen = {}
    for r in rules:
        t = re.sub(r'\*\*(.+?)\*\*', r'\1', r['text'])
        t = re.sub(r'`([^`]*)`', r'\1', t)
        t = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', t)
        r['text'] = re.sub(r'\s+', ' ', t).strip()
        r['words'] = words(r['text'])                       # for matching claims
        r['pwords'] = words(r['text'], min_len=3, stop=())  # for placement keywords
        plain = [w for w in re.sub(r'[^a-z]+', ' ', r['text'].lower()).split() if len(w) >= 3 and w not in STOP]
        base = '-'.join(plain[:5]) or 'rule'
        seen[base] = seen.get(base, 0) + 1
        r['id'] = base if seen[base] == 1 else '%s-%d' % (base, seen[base])
        r['claims'], r['red'], r['step'] = [], [], 0
    return rules


def parse_claims(path):
    claims = []
    if not path or not os.path.exists(path):
        return claims
    with open(path, encoding='utf-8', errors='ignore') as f:
        for line in f:
            s = line.rstrip('\n')
            if not s.strip() or s.lstrip().startswith('#'):
                continue
            cols = s.split('\t')
            if len(cols) < 2:
                continue
            claims.append({'id': cols[0].strip(), 'claim': cols[1].strip(),
                           'check': cols[2].strip() if len(cols) > 2 else '', 'words': words(cols[1])})
    return claims


def parse_verdict(path):
    """Returns (timestamp, set of red claim ids). Accepts a few shapes:
    {"ts", "items": [{"id"|"probe"|"claim"|"name", "status": "RED"|"GREEN"|..., "ok": bool}]}
    or {"red": ["id", ...]} or a bare list of items."""
    if not path or not os.path.exists(path):
        return '', set()
    with open(path, encoding='utf-8') as f:
        d = json.load(f)
    items = d if isinstance(d, list) else (d.get('items') or d.get('claims') or d.get('results') or [])
    red = set()
    for it in items:
        if not isinstance(it, dict):
            continue
        cid = it.get('id') or it.get('probe') or it.get('claim') or it.get('name')
        if cid and (str(it.get('status', '')).upper() == 'RED' or it.get('ok') is False or it.get('red') is True):
            red.add(cid)
    if isinstance(d, dict) and isinstance(d.get('red'), list):
        red.update(str(x) for x in d['red'])
    ts = (d.get('ts') or d.get('time') or d.get('at') or '') if isinstance(d, dict) else ''
    return str(ts), red


def place(rules, cfg):
    steps = cfg['steps']
    names = [s['name'] for s in steps]
    step_words = [[stem(w.lower()) for w in s.get('words', [])] for s in steps]
    pins = cfg.get('pins', {})
    for r in rules:
        pin = pins.get(r['id'])
        if pin is not None:
            if isinstance(pin, int):
                r['step'] = pin if 0 <= pin <= len(steps) else 0
            elif pin in names:
                r['step'] = names.index(pin) + 1
            continue
        scores = [shared(r['pwords'], sw) for sw in step_words]
        best = max(scores) if scores else 0
        r['step'] = scores.index(best) + 1 if best > 0 else 0


def link(rules, claims, cfg, red):
    links = cfg.get('links', {})
    by_id = {r['id']: r for r in rules}
    explicit = {}
    for rid, cids in links.items():
        for cid in (cids if isinstance(cids, list) else [cids]):
            explicit[cid] = rid
    unlinked = []
    for c in claims:
        target = by_id.get(explicit.get(c['id']))
        if target is None:
            best, best_n = None, 0
            for r in rules:
                n = shared(c['words'], r['words'])
                if n > best_n:
                    best, best_n = r, n
            target = best if best_n >= 2 else None
        if target is None:
            unlinked.append(c)
            continue
        target['claims'].append(c)
        if c['id'] in red:
            target['red'].append(c['id'])
    return unlinked


def wrap(text, width, lines):
    out, line = [], ''
    for w in text.split(' '):
        if len(line) + len(w) + 1 > width and line:
            out.append(line)
            line = w
        else:
            line = (line + ' ' + w).strip()
    out.append(line)
    if len(out) > lines:
        out = out[:lines]
        out[-1] = out[-1][:max(0, width - 3)].rstrip() + '...'
    return out


def draw(rules, cfg, unlinked, ts):
    esc = html.escape
    steps = cfg['steps']
    W, SX, SW, BOX = 2200, 100, 460, 130
    MX, CW, CH, GAP = 740, 620, 60, 10
    NX = MX + CW + 100
    order = list(range(1, len(steps) + 1)) + ([0] if any(r['step'] == 0 for r in rules) else [])
    y, layout = 320, []
    for st in order:
        its = [r for r in rules if r['step'] == st]
        mech = sorted([r for r in its if r['claims']], key=lambda r: (-len(r['red']), -len(r['claims']), r['text']))
        note = sorted([r for r in its if not r['claims']], key=lambda r: r['text'])
        h = max(max(len(mech), len(note), 1) * (CH + GAP), BOX + 40)
        layout.append((st, y, h, mech, note))
        y += h + 60
    total = len(rules)
    n_mech = sum(1 for r in rules if r['claims'])
    n_red = sum(1 for r in rules if r['red'])
    n_unp = sum(1 for r in rules if r['step'] == 0)
    TH = y + 120
    s = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
         'font-family="-apple-system, Segoe UI, Helvetica, Arial, sans-serif">' % (W, TH, W, TH),
         '<defs><marker id="ar" markerWidth="12" markerHeight="12" refX="10" refY="6" orient="auto">'
         '<path d="M0,0 L12,6 L0,12 z" fill="#8A8F98"/></marker></defs>',
         '<rect width="100%" height="100%" fill="#0B0E14"/>',
         '<text x="60" y="80" fill="#F2F0EA" font-size="46" font-weight="900">Every rule, on the step where it applies</text>',
         '<text x="60" y="128" fill="#C9CCD3" font-size="24">%d rules. %d have a check that runs. %d are only notes. %d broke today. %d not placed yet.</text>'
         % (total, n_mech, total - n_mech, n_red, n_unp),
         '<text x="60" y="168" fill="#C9CCD3" font-size="22">Left: the steps of one piece of work, top to bottom. Each card is one rule, wired to its step. '
         'Green card = a check in claims.tsv enforces it. Grey card = written down only. Red ring = its check failed in the last verdict.</text>',
         '<text x="%d" y="260" fill="#56C271" font-size="28" font-weight="900">A check enforces it (%d)</text>' % (MX, n_mech),
         '<text x="%d" y="260" fill="#8A8F98" font-size="28" font-weight="900">Only a note (%d)</text>' % (NX, total - n_mech)]
    prev = None
    for st, yy, h, mech, note in layout:
        cx, cy = SX, yy + h / 2 - BOX / 2
        label = '%d. %s' % (st, steps[st - 1]['name']) if st else '0. not placed yet'
        s.append('<g class="step" data-step="%d">' % st)
        s.append('<rect x="%d" y="%d" width="%d" height="%d" rx="16" fill="%s" stroke="#0B0E14" stroke-width="3"/>'
                 % (cx, cy, SW, BOX, '#E8503A' if st == 0 else '#F2F0EA'))
        for i, ln in enumerate(wrap(label, 26, 2)):
            s.append('<text x="%d" y="%d" text-anchor="middle" fill="#0B0E14" font-size="28" font-weight="900">%s</text>'
                     % (cx + SW / 2, cy + 52 + i * 32, esc(ln)))
        s.append('<text x="%d" y="%d" text-anchor="middle" fill="#0B0E14" font-size="18">%d rules</text>'
                 % (cx + SW / 2, cy + BOX - 16, len(mech) + len(note)))
        s.append('</g>')
        if prev is not None and st != 0:
            s.append('<path d="M%d,%d L%d,%d" stroke="#8A8F98" stroke-width="5" marker-end="url(#ar)"/>' % (SX + SW / 2, prev, SX + SW / 2, cy))
        prev = cy + BOX
        for x0, lst, fill, fg in ((MX, mech, '#163B2A', '#BFF0CF'), (NX, note, '#1E2230', '#D9DCE3')):
            for i, r in enumerate(lst):
                ry = yy + i * (CH + GAP)
                mid = ry + CH / 2
                broken = bool(r['red'])
                s.append('<path d="M%d,%d C%d,%d %d,%d %d,%d" fill="none" stroke="%s" stroke-width="2" opacity="0.9"/>'
                         % (cx + SW, cy + BOX / 2, cx + SW + 90, cy + BOX / 2, x0 - 90, mid, x0, mid,
                            '#E8503A' if broken else '#56C271' if r['claims'] else '#3A3F4C'))
                cls = 'rule mechanism broken' if broken else 'rule mechanism' if r['claims'] else 'rule note'
                s.append('<rect class="%s" data-id="%s" data-step="%d" x="%d" y="%d" width="%d" height="%d" rx="9" fill="%s" stroke="%s" stroke-width="%d"/>'
                         % (cls, esc(r['id']), st, x0, ry, CW, CH, fill, '#E8503A' if broken else '#0B0E14', 4 if broken else 2))
                if r['claims']:
                    s.append('<text x="%d" y="%d" fill="%s" font-size="17">%s</text>' % (x0 + 12, ry + 22, fg, esc(wrap(r['text'], 66, 1)[0])))
                    parts = ['<tspan fill="%s">%s%s</tspan>' % ('#E8503A' if c['id'] in r['red'] else '#56C271', esc(c['id']),
                                                                 ' RED' if c['id'] in r['red'] else '') for c in r['claims']]
                    s.append('<text x="%d" y="%d" font-size="15"><tspan fill="#56C271">check: </tspan>%s</text>' % (x0 + 12, ry + 46, ', '.join(parts)))
                else:
                    for j, ln in enumerate(wrap(r['text'], 68, 2)):
                        s.append('<text x="%d" y="%d" fill="%s" font-size="17">%s</text>' % (x0 + 12, ry + 22 + j * 22, fg, esc(ln)))
    foot = []
    if ts:
        foot.append('Last verdict: %s.' % ts)
    if unlinked:
        foot.append('Checks that match no rule: %s (link them in placement.json).' % ', '.join(c['id'] for c in unlinked))
    if n_unp:
        foot.append('Not placed yet: pin them to a step in placement.json.')
    s.append('<text x="60" y="%d" fill="#8A8F98" font-size="20">%s</text>' % (TH - 40, esc(' '.join(foot))))
    s.append('</svg>')
    return '\n'.join(s), W, TH


def write_png(svg, png_path, w, h):
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        return 'png skipped: Playwright for Python is not installed (pip install playwright; playwright install chromium)'
    try:
        with sync_playwright() as pw:
            b = pw.chromium.launch()
            pg = b.new_page(viewport={'width': w, 'height': min(h, 1400)})
            pg.set_content('<html><body style="margin:0;background:#0B0E14">' + svg + '</body></html>')
            pg.wait_for_timeout(200)
            pg.screenshot(path=png_path, full_page=True)
            b.close()
        return None
    except Exception as e:  # a missing browser, a sandbox, anything: the SVG is still written
        return 'png skipped: %s' % str(e).splitlines()[0]


def main():
    ap = argparse.ArgumentParser(description='Draw every rule on the step where it applies.')
    ap.add_argument('--rules', required=True, help='CLAUDE.md, one rule per top-level bullet')
    ap.add_argument('--claims', help='claims.tsv: id, claim in plain words, check')
    ap.add_argument('--verdict', help='verdict.json from the watchdog')
    ap.add_argument('--placement', default=os.path.join(HERE, 'placement.json'))
    ap.add_argument('--out', default='rules-map.svg')
    ap.add_argument('--no-png', action='store_true', help='write the SVG only')
    ap.add_argument('--list', action='store_true', help='print rule ids and placements, write nothing')
    a = ap.parse_args()

    with open(a.placement, encoding='utf-8') as f:
        cfg = json.load(f)
    rules = parse_rules(a.rules)
    claims = parse_claims(a.claims)
    ts, red = parse_verdict(a.verdict)
    place(rules, cfg)
    unlinked = link(rules, claims, cfg, red)

    if a.list:
        for r in rules:
            step = ('%d. %s' % (r['step'], cfg['steps'][r['step'] - 1]['name'])) if r['step'] else '0. not placed'
            print('%-48s  %-18s  %s%s' % (r['id'], step, ', '.join(c['id'] for c in r['claims']) or '-',
                                           '  RED: ' + ', '.join(r['red']) if r['red'] else ''))
        for c in unlinked:
            print('%-48s  %-18s  (matches no rule)' % (c['id'], 'claim'))
        return 0

    svg, w, h = draw(rules, cfg, unlinked, ts)
    out = a.out
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(svg)
    png = None
    if not a.no_png:
        png = os.path.splitext(out)[0] + '.png'
        note = write_png(svg, png, w, h)
        if note:
            print(note, file=sys.stderr)
            png = None
    print(json.dumps({'rules': len(rules), 'mechanism': sum(1 for r in rules if r['claims']),
                      'note': sum(1 for r in rules if not r['claims']), 'red': sum(1 for r in rules if r['red']),
                      'unplaced': sum(1 for r in rules if r['step'] == 0), 'unlinked_claims': [c['id'] for c in unlinked],
                      'svg': out, 'png': png}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
