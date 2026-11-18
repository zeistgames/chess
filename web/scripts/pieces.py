#!/usr/bin/env python3
"""Lit piece images for the web, from the same sources and the same lighting as the iPhone app.

Reads the sets in core/piece-sets.json and their source SVGs in ios/art/pieces-<id>/, and lights each one with
ios/scripts/pieces.py (imported, not copied, so both apps always draw the same pieces). The iPhone app renders
PNGs; the web keeps the lit drawings as SVG, sharp at any size.

Output: web/public/pieces/<id>/<wK..bP>.svg. Run: python3 web/scripts/pieces.py
"""
import importlib.util, json, os, re, sys

WEB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(WEB)
OUT = os.path.join(WEB, 'public', 'pieces')

spec = importlib.util.spec_from_file_location('ios_pieces', os.path.join(REPO, 'ios', 'scripts', 'pieces.py'))
lit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lit)


def main():
    os.makedirs(OUT, exist_ok=True)
    done = []
    for set_id in lit.sets():
        dest = os.path.join(OUT, set_id)
        os.makedirs(dest, exist_ok=True)
        for key in lit.PIECES:
            with open(os.path.join(lit.ART, f'pieces-{set_id}', f'{key}.svg')) as f:
                svg = lit.light(f.read(), lit.RULES[set_id][key[0]])
            # Gradient and filter ids are per file, but an inline copy would share them: keep them unique.
            svg = re.sub(r'\bid="(iv|eb|rim)"', lambda m: f'id="{m.group(1)}-{key}"', svg)
            svg = re.sub(r'url\(#(iv|eb|rim)\)', lambda m: f'url(#{m.group(1)}-{key})', svg)
            with open(os.path.join(dest, f'{key}.svg'), 'w') as f:
                f.write(svg)
        done.append(set_id)
    print('pieces ok:', ', '.join(done))


if __name__ == '__main__':
    sys.exit(main())
