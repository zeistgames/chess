#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Rebuild every engine pack from pinned sources, check each one in Node and in
# WebKit, and promote only the packs that pass into engines/dist, then write
# engines/dist/catalog.json.
#
#   engines/build-all.sh            all engines in engines/order.json
#   engines/build-all.sh clover     only these
#
# Needs: Emscripten 6.0.9 (EMSDK pointing at an emsdk checkout, or emcc on
# PATH), Node 20 or later, git, curl, and Playwright with WebKit in
# PLAYWRIGHT_DIR (see check-webkit.mjs).
set -uo pipefail
cd "$(dirname "$0")"
ids=("$@")
if [ ${#ids[@]} -eq 0 ]; then
  while IFS= read -r id; do [ -x "$id/build.sh" ] && ids+=("$id"); done < <(node -e 'for (const i of require("./order.json")) console.log(i)')
fi
mkdir -p build
passed=()
for id in "${ids[@]}"; do
  echo "== $id"
  if ! "./$id/build.sh" > "build/$id.log" 2>&1; then echo "build failed: see engines/build/$id.log"; continue; fi
  node --no-warnings check.mjs "$id" || continue
  node check-webkit.mjs "$id" || continue
  passed+=("$id")
done
[ ${#passed[@]} -gt 0 ] && ./tools/promote.sh "${passed[@]}"
