#!/bin/bash
# For development: serves the engines' data files from engines/dist (only those; see packs-server.py) over Tailscale,
# under its own path:
#   https://<this machine>.<tailnet>.ts.net/zeist-chess-packs/
# A local server on 127.0.0.1:8799 with Tailscale forwarding HTTPS to it, as Zeist's install link is served.
# Writes that URL into ios/Config.local.xcconfig (git-ignored) as PACKS_URL_LOCAL, which only Debug builds use.
# Release builds use https://engines.zei.st. Run from the repo root. The unit and UI tests use the local server alone.
set -euo pipefail
PORT=${PORT:-8799}
MOUNT=/zeist-chess-packs
DIST="$(cd "$(dirname "$0")/../.." && pwd)/engines/dist"
[ -d "$DIST" ] || { echo "No engines/dist yet."; exit 1; }
if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
  nohup python3 "$(dirname "$0")/packs-server.py" "$PORT" "$DIST" >/dev/null 2>&1 &
  sleep 1
fi
tailscale serve --bg --set-path "$MOUNT" "http://127.0.0.1:$PORT" >/dev/null
HOST=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
URL="https://$HOST$MOUNT"
CFG="$(dirname "$0")/../Config.local.xcconfig"
printf 'PACKS_URL_LOCAL = %s\n' "${URL/https:\/\//https:/\$()/}" > "$CFG"
echo "packs ok: $URL"
