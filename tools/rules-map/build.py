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


THEMES = {
    # BRAND.md: red, black, white; green and red only as the pass/fail signal inside a drawing.
    'light': dict(bg='#FFFFFF', ink='#111111', muted='#6B7280', card='#F7F7F7', line='#E5E7EB', rail='#D1D5DB',
                  green='#16A34A', red='#DC2626', mono='#374151'),
    'dark': dict(bg='#0A0A0A', ink='#F2F2F2', muted='#8A8F98', card='#141414', line='#2A2A2A', rail='#3A3A3A',
                 green='#30D158', red='#FF453A', mono='#C9CCD3'),
}
SANS = "Inter, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "'JetBrains Mono', Menlo, Consolas, monospace"


def draw(rules, cfg, unlinked, ts, theme='light'):
    """One picture: a numbered rail of steps down the left, every rule as a card in the band of
    its step. Left column = rules a check enforces (green bar, red when the check failed).
    Right column = rules that are written down only (grey bar). No wires: the band is the link."""
    esc = html.escape
    T = THEMES.get(theme, THEMES['light'])
    steps = cfg['steps']
    W = 1200
    RAIL_X, NAME_X = 72, 104           # circle centre, step name
    C1, C1W, C2, C2W = 300, 440, 770, 380   # the two card columns
    GAP, BAND_GAP = 10, 30
    TOP = 218                          # first band
    order = list(range(1, len(steps) + 1)) + ([0] if any(r['step'] == 0 for r in rules) else [])

    def card_h(r):
        if r['claims']:
            return 30 + 21 * len(wrap(r['text'], 54, 2)) + 22   # text lines + the check line
        return 30 + 21 * len(wrap(r['text'], 48, 2))

    y, layout = TOP, []
    for st in order:
        its = [r for r in rules if r['step'] == st]
        mech = sorted([r for r in its if r['claims']], key=lambda r: (-len(r['red']), -len(r['claims']), r['text']))
        note = sorted([r for r in its if not r['claims']], key=lambda r: r['text'])
        h1 = sum(card_h(r) + GAP for r in mech)
        h2 = sum(card_h(r) + GAP for r in note)
        h = max(h1, h2, 56)
        layout.append((st, y, h, mech, note))
        y += h + BAND_GAP
    total = len(rules)
    n_mech = sum(1 for r in rules if r['claims'])
    n_red = sum(1 for r in rules if r['red'])
    n_unp = sum(1 for r in rules if r['step'] == 0)
    TH = y + 40

    s = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="%s">'
         % (W, TH, W, TH, SANS),
         '<rect width="100%%" height="100%%" fill="%s"/>' % T['bg'],
         '<text x="60" y="64" fill="%s" font-size="30" font-weight="700" letter-spacing="-0.02em">Every rule, on the step where it applies</text>' % T['ink']]
    parts = ['%d rules' % total, '%d enforced by a check' % n_mech, '%d written down only' % (total - n_mech)]
    if n_red:
        parts.append('<tspan fill="%s" font-weight="600">%d failing now</tspan>' % (T['red'], n_red))
    if n_unp:
        parts.append('%d not placed yet' % n_unp)
    s.append('<text x="60" y="96" fill="%s" font-size="16">%s</text>' % (T['muted'], '  ·  '.join(parts)))
    s.append('<text x="60" y="124" fill="%s" font-size="14">Down the left: the steps of one piece of work. Each card is one rule, in the band of its step.</text>' % T['muted'])
    # column headers: name on one line, meaning on the next, so the two columns never collide
    s.append('<circle cx="%d" cy="%d" r="5" fill="%s"/>' % (C1 + 6, 160, T['green']))
    s.append('<text x="%d" y="165" fill="%s" font-size="15" font-weight="600">Enforced by a check</text>' % (C1 + 18, T['ink']))
    s.append('<text x="%d" y="184" fill="%s" font-size="12.5">a command that exits 0 when the rule holds. Red: it failed in the last verdict.</text>' % (C1 + 18, T['muted']))
    s.append('<circle cx="%d" cy="%d" r="5" fill="%s"/>' % (C2 + 6, 160, T['rail']))
    s.append('<text x="%d" y="165" fill="%s" font-size="15" font-weight="600">Written down only</text>' % (C2 + 18, T['ink']))
    s.append('<text x="%d" y="184" fill="%s" font-size="12.5">no check yet, so nobody knows if it holds.</text>' % (C2 + 18, T['muted']))
    s.append('<line x1="%d" y1="198" x2="%d" y2="198" stroke="%s" stroke-width="1"/>' % (60, W - 60, T['line']))

    # the rail: one line through every placed step, a circle per step
    placed = [(st, yy) for st, yy, h, m, n in layout if st != 0]
    if len(placed) > 1:
        s.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="2"/>'
                 % (RAIL_X, placed[0][1] + 18, RAIL_X, placed[-1][1] + 18, T['rail']))
    for st, yy, h, mech, note in layout:
        cy = yy + 18
        if st == 0:
            s.append('<circle cx="%d" cy="%d" r="16" fill="%s" stroke="%s" stroke-width="2" stroke-dasharray="4 3"/>' % (RAIL_X, cy, T['bg'], T['rail']))
            s.append('<text x="%d" y="%d" text-anchor="middle" fill="%s" font-size="14" font-weight="700">?</text>' % (RAIL_X, cy + 5, T['muted']))
            name = 'not placed yet'
        else:
            s.append('<circle cx="%d" cy="%d" r="16" fill="%s"/>' % (RAIL_X, cy, T['ink']))
            s.append('<text x="%d" y="%d" text-anchor="middle" fill="%s" font-size="14" font-weight="700">%d</text>' % (RAIL_X, cy + 5, T['bg'], st))
            name = steps[st - 1]['name']
        for i, ln in enumerate(wrap(name, 16, 2)):
            s.append('<text x="%d" y="%d" fill="%s" font-size="17" font-weight="600">%s</text>' % (NAME_X, cy + 6 + i * 20, T['ink'] if st else T['muted'], esc(ln)))
        s.append('<text x="%d" y="%d" fill="%s" font-size="13">%d %s</text>' % (NAME_X, cy + 28 + (20 if len(wrap(name, 16, 2)) > 1 else 0), T['muted'], len(mech) + len(note), 'rule' if len(mech) + len(note) == 1 else 'rules'))
        if st != 0 and st != layout[-1][0] and not (layout[-1][0] == 0 and st == layout[-2][0]):
            pass
        # a faint band line under each step except the last
        if (st, yy) != (layout[-1][0], layout[-1][1]):
            s.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>' % (C1, yy + h + BAND_GAP / 2, W - 60, yy + h + BAND_GAP / 2, T['line']))
        for x0, cw, lst in ((C1, C1W, mech), (C2, C2W, note)):
            ry = yy
            for r in lst:
                ch = card_h(r)
                broken = bool(r['red'])
                bar = T['red'] if broken else T['green'] if r['claims'] else T['rail']
                dash = ' stroke-dasharray="5 4"' if st == 0 else ''
                cls = 'rule mechanism broken' if broken else 'rule mechanism' if r['claims'] else 'rule note'
                s.append('<rect class="%s" data-id="%s" data-step="%d" x="%d" y="%d" width="%d" height="%d" rx="8" fill="%s" stroke="%s" stroke-width="%s"%s/>'
                         % (cls, esc(r['id']), st, x0, ry, cw, ch, T['card'], T['red'] if broken else T['line'], '1.5' if broken else '1', dash))
                s.append('<rect x="%d" y="%d" width="4" height="%d" rx="2" fill="%s"/>' % (x0 + 10, ry + 12, ch - 24, bar))
                lines = wrap(r['text'], 54 if r['claims'] else 48, 2)
                for j, ln in enumerate(lines):
                    s.append('<text x="%d" y="%d" fill="%s" font-size="15">%s</text>' % (x0 + 26, ry + 27 + j * 21, T['ink'], esc(ln)))
                if r['claims']:
                    cy2 = ry + 27 + len(lines) * 21
                    items = []
                    for c in r['claims']:
                        if c['id'] in r['red']:
                            items.append('<tspan fill="%s" font-weight="700">%s  failing</tspan>' % (T['red'], esc(c['id'])))
                        else:
                            items.append('<tspan fill="%s">%s</tspan>' % (T['mono'], esc(c['id'])))
                    s.append('<text x="%d" y="%d" font-family="%s" font-size="12.5"><tspan fill="%s">check </tspan>%s</text>'
                             % (x0 + 26, cy2, MONO, T['muted'], '<tspan fill="%s">, </tspan>'.join(items) % (() if len(items) < 2 else tuple([T['muted']] * (len(items) - 1)))))
                ry += ch + GAP
    foot = []
    if ts:
        foot.append('Last verdict %s' % ts.replace('T', ' ').replace('Z', ' UTC'))
    foot.append('Drawn from CLAUDE.md, claims.tsv and verdict.json by tools/rules-map/build.py')
    if unlinked:
        foot.append('Checks that match no rule: %s' % ', '.join(c['id'] for c in unlinked))
    if n_unp:
        foot.append('Pin unplaced rules to a step in placement.json')
    s.append('<text x="60" y="%d" fill="%s" font-size="12.5">%s</text>' % (TH - 16, T['muted'], esc('  ·  '.join(foot))))
    s.append('</svg>')
    return '\n'.join(s), W, TH


def write_png(svg, png_path, w, h, theme='light'):
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        return 'png skipped: Playwright for Python is not installed (pip install playwright; playwright install chromium)'
    bg = THEMES.get(theme, THEMES['light'])['bg']
    try:
        with sync_playwright() as pw:
            b = pw.chromium.launch()
            pg = b.new_page(viewport={'width': w, 'height': min(h, 1400)}, device_scale_factor=2)
            pg.set_content('<html><head><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=JetBrains+Mono:wght@400;700&display=swap"></head>'
                           '<body style="margin:0;background:%s">%s</body></html>' % (bg, svg))
            try:
                pg.evaluate('document.fonts.ready')
                pg.wait_for_timeout(1200)   # fonts arrive from the network; offline, the fallback face is used
            except Exception:
                pass
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
    ap.add_argument('--theme', choices=('light', 'dark'), default='light', help='light (white page) or dark (black page)')
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

    svg, w, h = draw(rules, cfg, unlinked, ts, a.theme)
    out = a.out
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(svg)
    png = None
    if not a.no_png:
        png = os.path.splitext(out)[0] + '.png'
        note = write_png(svg, png, w, h, a.theme)
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
