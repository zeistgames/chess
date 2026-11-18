#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# The Zeist engine: plain JavaScript, written for Zeist. Its modules are in src/, copied one way from the Zeist
# repository by sync.sh (src/SOURCE names the revision). This script joins them with uci.js into one worker
# script. Nothing is compiled, and nothing outside this repository is needed.
source "$(dirname "$0")/../tools/common.sh"

SRC="$SRC_DIR/src"
FILES=(pst.js board.js eval.js search.js computer.js)
for f in "${FILES[@]}"; do [ -f "$SRC/$f" ] || { log "missing $SRC/$f"; exit 1; }; done

start_pack
{
  echo "// SPDX-License-Identifier: AGPL-3.0-or-later"
  echo "// The Zeist chess engine as a UCI worker. Built by engines/zeist/build.sh from the engine's own modules"
  echo "// (${FILES[*]}) and engines/zeist/uci.js; the modules' import and export lines are removed."
  echo "(function () {"
  echo "\"use strict\";"
  for f in "${FILES[@]}"; do
    echo "// ---- $f"
    # Drop import lines and re-export lists; keep each declaration without its export keyword.
    sed -E -e '/^import /d' -e '/^export \{.*\};$/d' -e 's/^export //' "$SRC/$f"
  done
  echo "// ---- uci.js"
  cat "$SRC_DIR/uci.js"
  echo "})();"
} > "$OUT/zeist.js"
cp "$ENGINES_DIR/../LICENSE" "$OUT/LICENSE.txt"
finish_pack
