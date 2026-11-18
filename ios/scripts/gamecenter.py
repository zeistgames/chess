#!/usr/bin/env python3
"""Creates Zeist Chess's Game Center achievements in App Store Connect from ios/GameCenter/achievements.json.

    python3 ios/scripts/gamecenter.py <app id>            # create what is missing, update points and words
    python3 ios/scripts/gamecenter.py <app id> --images   # also upload each image (ios/GameCenter/images/<id>.png)

Safe to run again: an achievement that exists is updated, never duplicated. Nothing is deleted. Needs the `asc`
command signed in to the team. Achievements can still be changed or removed until a version with them is released.
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST = json.load(open(os.path.join(HERE, 'GameCenter', 'achievements.json')))['achievements']
LOCALE = 'en-US'
if len(sys.argv) < 2:
    raise SystemExit(__doc__)
APP, IMAGES = sys.argv[1], '--images' in sys.argv


def asc(*args, ok=False):
    out = subprocess.run(['asc', *args, '--output', 'json'], capture_output=True, text=True)
    if out.returncode != 0:
        if ok:
            return None
        raise SystemExit(f"asc {' '.join(args[:4])} failed: {(out.stderr or out.stdout).strip()[:400]}")
    text = out.stdout.strip()
    return json.loads(text[text.index('{'):]) if '{' in text else {}


def rows(r):
    d = (r or {}).get('data', [])
    return d if isinstance(d, list) else [d]


if not rows(asc('game-center', 'details', 'list', '--app', APP)):
    asc('game-center', 'details', 'create', '--app', APP)
    print('Game Center switched on for the app')

have = {r['attributes'].get('vendorIdentifier'): r for r in rows(asc('game-center', 'achievements', 'list', '--app', APP, '--paginate'))}
made = updated = pictures = 0
for a in LIST:
    row = have.get(a['id'])
    if row is None:
        row = rows(asc('game-center', 'achievements', 'create', '--app', APP, '--reference-name', a['title'], '--vendor-id', a['id'],
                       '--points', str(a['points'])))[0]
        made += 1
    elif row['attributes'].get('points') != a['points'] or row['attributes'].get('referenceName') != a['title']:
        asc('game-center', 'achievements', 'update', '--id', row['id'], '--points', str(a['points']), '--reference-name', a['title'])
        updated += 1
    locs = rows(asc('game-center', 'achievements', 'localizations', 'list', '--achievement-id', row['id']))
    loc = next((l for l in locs if l['attributes'].get('locale') == LOCALE), None)
    words = ['--name', a['title'], '--before-earned-description', a['before'], '--after-earned-description', a['earned']]
    if loc is None:
        loc = rows(asc('game-center', 'achievements', 'localizations', 'create', '--achievement-id', row['id'], '--locale', LOCALE, *words))[0]
    else:
        at = loc['attributes']
        if (at.get('name'), at.get('beforeEarnedDescription'), at.get('afterEarnedDescription')) != (a['title'], a['before'], a['earned']):
            asc('game-center', 'achievements', 'localizations', 'update', '--id', loc['id'], *words)
    if IMAGES:
        path = os.path.join(HERE, 'GameCenter', 'images', a['id'] + '.png')
        if asc('game-center', 'achievements', 'images', 'upload', '--localization-id', loc['id'], '--file', path, ok=True) is not None:
            pictures += 1
        else:
            print('image not uploaded:', a['id'])
print(f'gamecenter ok: {len(LIST)} achievements ({made} created, {updated} updated' + (f', {pictures} images uploaded' if IMAGES else '') + ')')
