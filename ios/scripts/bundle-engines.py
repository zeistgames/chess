#!/usr/bin/env python3
"""Copies every engine's program into the app: its manifest.json and each file that is a program or text.
Only data files (networks, weights) are left out; the app downloads those. App Review does not allow downloading
code after install, so anything that could be executed ships in the app.

The rule, the same as PackFiles in ios/ZeistChess/Engines/Packs.swift: a file is data only if its extension is not
one of js, mjs, wasm, txt, json.

Writes <dest>/<id>/ for each engine and <dest>/catalog.json ({"format": 1, "engines": [manifest, ...]}).
Usage: bundle-engines.py <engines/dist> <dest>"""
import hashlib, json, os, shutil, sys

PROGRAM = {"js", "mjs", "wasm", "txt", "json"}

# In the order the app lists them. Full Stockfish ("stockfish") is left out: its network is inside its 99 MB wasm,
# so the whole engine would ship in the app. It returns when the network is split out (docs/PLAN.md).
ENGINES = ["stockfish-lite", "fairy-stockfish", "maia", "arasan", "clover", "caissa", "plentychess", "halogen",
           "koivisto", "ethereal", "zeist"]


def is_data(path):
    ext = os.path.splitext(path)[1].lstrip(".").lower()
    return ext not in PROGRAM


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    dist, dest = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    missing = [i for i in ENGINES if not os.path.isfile(os.path.join(dist, i, "manifest.json"))]
    if missing:
        fail(f"engines/dist lacks {', '.join(missing)}. Build the packs first: engines/build-all.sh "
             f"(or engines/<id>/build.sh for one).")
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    catalog = []
    for i in ENGINES:
        src = os.path.join(dist, i)
        with open(os.path.join(src, "manifest.json"), "rb") as f:
            raw = f.read()
        m = json.loads(raw)
        if m.get("id") != i:
            fail(f"engines/dist/{i}/manifest.json names itself {m.get('id')!r}.")
        out = os.path.join(dest, i)
        os.makedirs(out)
        for e in m["files"]:
            p = e["path"]
            if p.startswith("/") or ".." in p.split("/"):
                fail(f"{i}: {p} is outside its folder.")
            if is_data(p):
                continue
            s = os.path.join(src, p)
            if not os.path.isfile(s):
                fail(f"{i}: {p} is missing from engines/dist/{i}. Rebuild it: engines/build-all.sh.")
            if os.path.getsize(s) != e["bytes"] or sha256(s) != e["sha256"].lower():
                fail(f"{i}: {p} doesn't match its manifest. Rebuild it: engines/build-all.sh.")
            d = os.path.join(out, p)
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copyfile(s, d)
        if is_data(m["entry"]):
            fail(f"{i}: its entry {m['entry']} isn't a program file.")
        # Byte for byte: its hash names the exact pack in the game log.
        with open(os.path.join(out, "manifest.json"), "wb") as f:
            f.write(raw)
        catalog.append(m)
    with open(os.path.join(dest, "catalog.json"), "w") as f:
        json.dump({"format": 1, "engines": catalog}, f, indent=1)
    print(f"engines bundled: {', '.join(ENGINES)}")


main()
