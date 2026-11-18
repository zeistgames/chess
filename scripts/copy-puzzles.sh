#!/bin/bash
# Copies Zeist's puzzle set into puzzles/, one way. The set is chosen and built in Zeist's own repository
# (games/scripts/build_puzzles.mjs there, from the Lichess puzzle database, CC0); fixes go there, never here.
#
#   scripts/copy-puzzles.sh [source folder]
#
# The source defaults to ../zeist/public/s/chess/puzzles beside this repository (ZEIST_PUZZLES overrides it).
# index.json and the files it lists are copied, with themes.json and daily.json when present. A listed file that is missing or does not parse is left out
# and named; the app skips anything it cannot read, so a half-built source still gives a usable copy.
# puzzles/README.md is this repository's own and is kept.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-${ZEIST_PUZZLES:-$ROOT/../zeist/public/s/chess/puzzles}}"
DEST="$ROOT/puzzles"
[ -f "$SRC/index.json" ] || { echo "No index.json in $SRC. Nothing copied." >&2; exit 1; }
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Check the set with Node and write the copy to $TMP: index.json, then every listed file that parses.
node - "$SRC" "$TMP" <<'JS'
const fs = require("fs"), path = require("path");
const [src, out] = process.argv.slice(2);
let index;
try { index = JSON.parse(fs.readFileSync(path.join(src, "index.json"), "utf8")); }
catch (e) { console.error("index.json does not parse: " + e.message); process.exit(1); }
if (!Array.isArray(index.bands)) { console.error("index.json has no bands."); process.exit(1); }
const problems = [];
const uci = /^[a-h][1-8][a-h][1-8][qrbn]?$/;
let total = 0;
for (const b of index.bands) {
  let rows = 0, bad = 0;
  const kept = [];
  for (const f of b.files ?? []) {
    let d;
    try { d = JSON.parse(fs.readFileSync(path.join(src, f), "utf8")); }
    catch (e) { problems.push(`${f}: ${e.code === "ENOENT" ? "missing" : "does not parse"}`); continue; }
    if (!Array.isArray(d.puzzles)) { problems.push(`${f}: no puzzles`); continue; }
    if (d.band !== b.band) problems.push(`${f}: says band ${d.band}, listed under ${b.band}`);
    for (const p of d.puzzles) {
      const ok = Array.isArray(p) && p.length >= 4 && typeof p[0] === "string" && typeof p[1] === "string" &&
        typeof p[2] === "string" && p[2].split(" ").length >= 2 && p[2].split(" ").length % 2 === 0 &&
        p[2].split(" ").every((m) => uci.test(m)) && Number.isInteger(p[3]);
      ok ? rows++ : bad++;
    }
    fs.copyFileSync(path.join(src, f), path.join(out, f));
    kept.push(f);
  }
  if (rows !== b.count) problems.push(`band ${b.band}: index says ${b.count}, files hold ${rows}`);
  if (bad) problems.push(`band ${b.band}: ${bad} rows the app will skip`);
  b.files = kept;
  total += rows;
  console.log(`band ${b.band} (rating ${(b.rating ?? []).join("-")}): ${rows} puzzles in ${kept.length} files`);
}
fs.writeFileSync(path.join(out, "index.json"), JSON.stringify(index) + "\n");
console.log(`${total} puzzles in all. Source: ${index.source ?? "not stated"}.`);
for (const p of problems) console.log("note: " + p);
JS

[ -f "$SRC/LICENSE.md" ] && cp "$SRC/LICENSE.md" "$TMP/LICENSE.md"
# The themes (which puzzles belong to which idea) and the daily list, when the source has them and they parse.
for f in themes.json daily.json; do
  if [ -f "$SRC/$f" ] && node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$SRC/$f" 2>/dev/null; then
    cp "$SRC/$f" "$TMP/$f"; echo "$f copied."
  else
    echo "note: $f is missing or does not parse; left out."
  fi
done
# The streak cases both apps test against and the small board for each theme sit one folder up in Zeist
# (its build clears the puzzles folder).
for f in streak-cases.json theme-boards.json; do
  if [ -f "$SRC/../$f" ] && node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$SRC/../$f" 2>/dev/null; then
    cp "$SRC/../$f" "$TMP/$f"; echo "$f copied."
  else
    echo "note: $f is missing or does not parse; left out."
  fi
done
# Replace the data, keep the README.
find "$DEST" -maxdepth 1 -type f ! -name README.md -delete
cp "$TMP"/* "$DEST/"
echo "Copied to puzzles/."
