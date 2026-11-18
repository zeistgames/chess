#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copies the Zeist engine's modules one way from a Zeist checkout into src/ and records the revision.
# The engine is written in Zeist's repository; changes are made there and copied here, never the other way.
#
#   engines/zeist/sync.sh [folder holding pst.js, board.js, eval.js, search.js and computer.js]
#
# The folder defaults to public/s/chess of a zeist checkout beside this repository (ZEIST_CHESS overrides it).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FROM="${1:-${ZEIST_CHESS:-$HERE/../../../zeist/public/s/chess}}"
FILES=(pst.js board.js eval.js search.js computer.js)
for f in "${FILES[@]}"; do [ -f "$FROM/$f" ] || { echo "missing $FROM/$f" >&2; exit 1; }; done
if [ -n "$(git -C "$FROM" status --porcelain -- "${FILES[@]}" 2>/dev/null)" ]; then
  echo "The engine files have uncommitted changes in $FROM. Commit them there first." >&2; exit 1
fi
REV="$(git -C "$FROM" log -1 --format=%H -- "${FILES[@]}")"
mkdir -p "$HERE/src"
for f in "${FILES[@]}"; do cp "$FROM/$f" "$HERE/src/$f"; done
{
  echo "The Zeist chess engine's modules, copied from Zeist's repository by engines/zeist/sync.sh."
  echo "Revision of the last change to them there: $REV"
  echo "Files: ${FILES[*]}"
  echo "Author: Amrith. License here: AGPL-3.0-or-later (see LICENSE at the root of this repository)."
} > "$HERE/src/SOURCE"
echo "Copied ${#FILES[@]} files at $REV."
