#!/usr/bin/env python3
"""Lights every piece set in Zeist's ivory and ebony and renders it for the app.

The sets are listed in core/piece-sets.json. Each set's source SVGs are in ios/art/pieces-<id>/, unmodified,
with a README giving the author, license and source. Every set is lit the same way: the body of an ivory piece
takes the ivory light, the body of an ebony piece the ebony light, both from above left; outlines and inner lines
take the matching ink. Only the source colors differ from set to set, so each set names its own (RULES below).

Output: ios/ZeistChess/Assets.xcassets/Pieces/<id>/<wK..bP>.imageset, one folder per set, named "<id>/wK" in code.
Needs rsvg-convert (librsvg). Run from anywhere: python3 ios/scripts/pieces.py [--preview <dir>]
"""
import json, os, re, shutil, subprocess, sys

IOS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(IOS)
ART = os.path.join(IOS, 'art')
OUT = os.path.join(IOS, 'ZeistChess', 'Assets.xcassets', 'Pieces')
LIST = os.path.join(REPO, 'core', 'piece-sets.json')
PX = 256
PIECES = [c + k for c in 'wb' for k in 'KQRBNP']

# Zeist's piece tokens (design/tokens.json: piece).
WHITE, WHITE_HI, WHITE_LO = '#eee7d6', '#fdfaf3', '#d3c9b2'
BLACK, BLACK_HI, BLACK_LO = '#1c1b18', '#4a4640', '#0c0b09'

# A soft light from above left, per shape.
DEFS = f'''<defs>
<radialGradient id="iv" cx=".36" cy=".26" r=".9" fx=".34" fy=".2">
<stop offset="0" stop-color="{WHITE_HI}"/><stop offset=".55" stop-color="{WHITE}"/><stop offset="1" stop-color="{WHITE_LO}"/></radialGradient>
<radialGradient id="eb" cx=".36" cy=".26" r=".9" fx=".34" fy=".2">
<stop offset="0" stop-color="{BLACK_HI}"/><stop offset=".5" stop-color="{BLACK}"/><stop offset="1" stop-color="{BLACK_LO}"/></radialGradient>
</defs>'''

IV, EB = 'url(#iv)', 'url(#eb)'

# Per set and side: what each source paint becomes, written "fill #fff" or "stroke #000" (colors in six-digit
# lowercase; url(#x) for gradients). "group" is the fill given to a group around the whole drawing, for shapes
# that carry no fill of their own. A value with "@" adds an opacity: "#d3c9b2@.55".
RULES = {
    'cburnett': {
        'w': {'group': None, 'fill #ffffff': IV, 'fill #000000': BLACK, 'stroke #000000': BLACK},
        'b': {'group': EB, 'fill #000000': EB, 'stroke #000000': BLACK_LO,
              'stroke #ececec': WHITE_LO + '@.78', 'fill #ececec': WHITE_LO + '@.55'},
    },
    'zeist': {
        'w': {'group': None, 'fill #ffffff': IV, 'fill #000000': BLACK, 'stroke #000000': BLACK},
        'b': {'group': None, 'fill #000000': EB, 'stroke #000000': BLACK_LO,
              'stroke #ececec': WHITE, 'fill #ececec': WHITE},
    },
    'pirouetti': {
        # No outlines in the source: a fine rim in the other ink keeps the edge on a square of the same tone.
        'w': {'group': None, 'fill #ffffff': IV, 'fill #fefefe': IV, 'fill #d1d1d1': WHITE_LO, 'rim': (BLACK, .5, .012)},
        'b': {'group': None, 'fill #383838': EB, 'fill #2e2e2e': EB, 'fill #111111': BLACK_LO, 'rim': (WHITE_LO, .42, .012)},
    },
}

ATTR = re.compile(r'\b(fill|stroke)="(#[0-9a-fA-F]{3,6}|url\(#[^)]+\)|none)"')
STYLE = re.compile(r'style="([^"]*)"')


def norm(c):
    c = c.strip()
    if c.startswith('url') or c == 'none':
        return c
    c = c.lower()
    return '#' + ''.join(ch * 2 for ch in c[1:]) if len(c) == 4 else c


def paint(prop, color, rules, missing):
    """What one paint becomes: {property: value}, or None to leave it. A rule reads "#d3c9b2" or "#d3c9b2@.55"
    (with an opacity)."""
    key = f'{prop} {norm(color)}'
    if key not in rules:
        if norm(color) != 'none':
            missing.add(key)
        return None
    value, _, alpha = rules[key].partition('@')
    out = {prop: value}
    if alpha:
        out[f'{prop}-opacity'] = alpha
    return out


def light(svg, rules):
    """Repaints one SVG. Fails loudly on a paint the set's rules don't name, so nothing slips through unlit."""
    svg = svg.replace(' style="color-scheme:light only"', '')
    missing = set()

    def restyle(m):
        decls = {}
        for d in m.group(1).split(';'):
            k, _, v = d.partition(':')
            if k.strip():
                decls[k.strip()] = v.strip()
        for prop in ('fill', 'stroke'):
            if prop in decls:
                got = paint(prop, decls[prop], rules, missing)
                if got:
                    decls.update(got)
        return 'style="' + ';'.join(f'{k}:{v}' for k, v in decls.items()) + '"'

    def reattr(m):
        got = paint(m.group(1), m.group(2), rules, missing)
        return ' '.join(f'{k}="{v}"' for k, v in got.items()) if got else m.group(0)

    svg = STYLE.sub(restyle, svg)
    svg = ATTR.sub(reattr, svg)
    if missing:
        raise SystemExit(f'unlit paints: {sorted(missing)}')
    group = f' fill="{rules["group"]}"' if rules.get('group') else ''
    defs = DEFS
    if rules.get('rim'):
        # A rim around the whole outline: the drawing's shape grown a little, in one tone, behind the drawing.
        color, alpha, share = rules['rim']
        box = re.search(r'viewBox="([^"]+)"', svg).group(1).split()
        radius = float(box[2]) * share
        defs = defs.replace('</defs>', f'<filter id="rim" x="-10%" y="-10%" width="120%" height="120%">'
                            f'<feMorphology in="SourceAlpha" operator="dilate" radius="{radius:.4g}" result="grown"/>'
                            f'<feFlood flood-color="{color}" flood-opacity="{alpha}"/><feComposite in2="grown" operator="in"/>'
                            f'<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>')
        group += ' filter="url(#rim)"'
    svg = re.sub(r'(<svg[^>]*>)', lambda m: m.group(1) + defs + f'<g{group}>', svg, count=1)
    return svg.replace('</svg>', '</g></svg>')


def sets():
    with open(LIST) as f:
        return [s['id'] for s in json.load(f)['sets']]


def render(set_id, out_dir, catalog):
    src = os.path.join(ART, f'pieces-{set_id}')
    if set_id not in RULES:
        raise SystemExit(f'{set_id}: no lighting rules in pieces.py')
    for key in PIECES:
        with open(os.path.join(src, f'{key}.svg')) as f:
            svg = light(f.read(), RULES[set_id][key[0]])
        if catalog:
            dest = os.path.join(out_dir, set_id, f'{key}.imageset')
            os.makedirs(dest, exist_ok=True)
            png = os.path.join(dest, f'{key}.png')
            with open(os.path.join(dest, 'Contents.json'), 'w') as f:
                json.dump({'images': [{'idiom': 'universal', 'filename': f'{key}.png'}],
                           'info': {'author': 'xcode', 'version': 1}}, f)
        else:
            os.makedirs(os.path.join(out_dir, set_id), exist_ok=True)
            png = os.path.join(out_dir, set_id, f'{key}.png')
        subprocess.run(['rsvg-convert', '-w', str(PX), '-h', str(PX), '-o', png], input=svg.encode(), check=True)
    # Shrink losslessly when a PNG optimizer is around.
    if catalog and shutil.which('oxipng'):
        subprocess.run(['oxipng', '-q', '-o', '4', '-r', os.path.join(out_dir, set_id)], check=True)


def main():
    args = sys.argv[1:]
    if args[:1] == ['--preview']:
        for s in args[2:] or sets():
            render(s, args[1], catalog=False)
        print('preview ok:', args[1])
        return
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    with open(os.path.join(OUT, 'Contents.json'), 'w') as f:
        json.dump({'info': {'author': 'xcode', 'version': 1}, 'properties': {'provides-namespace': False}}, f)
    for s in sets():
        os.makedirs(os.path.join(OUT, s))
        with open(os.path.join(OUT, s, 'Contents.json'), 'w') as f:
            json.dump({'info': {'author': 'xcode', 'version': 1}, 'properties': {'provides-namespace': True}}, f)
        render(s, OUT, catalog=True)
    print('pieces ok:', ', '.join(sets()))


if __name__ == '__main__':
    sys.exit(main())
