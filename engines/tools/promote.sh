#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# promote.sh <id>...: move a staged pack (engines/build/<id>/pack) into
# engines/dist/<id> after it passed both the Node and the WebKit check for its
# current manifest, then rewrite engines/dist/catalog.json. A pack that has not
# passed is never copied, and the old pack in dist stays until the new one is
# complete, so a reader of dist never sees a half-written pack.
set -euo pipefail
ENGINES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ENGINES_DIR/dist"
mkdir -p "$DIST"
for id in "$@"; do
  src="$ENGINES_DIR/build/$id/pack"
  node -e '
    const fs = require("fs"), crypto = require("crypto");
    const [src, checks, id] = process.argv.slice(1);
    const h = crypto.createHash("sha256").update(fs.readFileSync(src + "/manifest.json")).digest("hex");
    for (const k of ["node", "webkit"]) {
      const f = `${checks}/${id}.${k}.json`;
      const r = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : null;
      if (!r || !r.pass || r.manifest_sha256 !== h) { console.error(`${id}: ${k} check has not passed for this manifest`); process.exit(1); }
    }' "$src" "$ENGINES_DIR/build/checks" "$id"
  rm -rf "$DIST/.$id.tmp" "$DIST/.$id.old"
  cp -R "$src" "$DIST/.$id.tmp"
  [ -d "$DIST/$id" ] && mv "$DIST/$id" "$DIST/.$id.old"
  mv "$DIST/.$id.tmp" "$DIST/$id"
  rm -rf "$DIST/.$id.old"
  echo "promoted $id"
done
node "$ENGINES_DIR/tools/catalog.mjs"
