#!/bin/bash
# Uploads the engine packs in engines/dist to the R2 bucket that engines.zei.st serves.
# Packs go first and catalog.json last, so the catalog never lists a file that is not there yet.
# Needs CLOUDFLARE_ACCOUNT_ID in the environment and `cf` signed in. Uploading changes what players download:
# run it only with the owner's go-ahead.
#   bash scripts/publish-engines.sh            every pack
#   bash scripts/publish-engines.sh clover     one pack, then the catalog
set -euo pipefail
cd "$(dirname "$0")/../engines/dist"
BUCKET=${BUCKET:-zeist-chess-engines}
: "${CLOUDFLARE_ACCOUNT_ID:?Set CLOUDFLARE_ACCOUNT_ID}"
type_of() {
  case "$1" in
    *.json) echo application/json ;;
    *.js|*.mjs) echo text/javascript ;;
    *.wasm) echo application/wasm ;;
    *.txt|*.md) echo "text/plain; charset=utf-8" ;;
    *) echo application/octet-stream ;;
  esac
}
put() {
  cf r2 objects put "$1" --bucket-name "$BUCKET" --file "$1" --content-type "$(type_of "$1")" --quiet >/dev/null
  echo "  $1"
}
packs=("$@")
[ ${#packs[@]} -eq 0 ] && packs=($(ls -d */ | tr -d /))
for id in "${packs[@]}"; do
  [ -f "$id/manifest.json" ] || { echo "skipped $id: no manifest"; continue; }
  echo "$id"
  find "$id" -type f ! -name .DS_Store | sort | while read -r f; do put "$f"; done
done
put catalog.json
echo "published ${#packs[@]} packs"
