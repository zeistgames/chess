#!/bin/bash
# Copies core/ (without its tests; with Learn's lessons, core/lessons, but not their checker), the puzzles (puzzles/, without its README) and the engines' programs into the app.
# The engines: scripts/bundle-engines.py, which leaves out their data files (the app downloads those).
# Run by Xcode after the build; needs SRCROOT and the build's resource folder.
set -euo pipefail
REPO="$SRCROOT/.."
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$DEST/core"
rsync -a --delete --exclude test --exclude package.json --exclude /lessons/check.mjs "$REPO/core/" "$DEST/core/"
if [ ! -f "$REPO/core/lessons/index.json" ]; then
  echo "warning: core/lessons/index.json is missing; Learn will have no lessons." >&2
fi
if [ -f "$REPO/puzzles/index.json" ]; then
  mkdir -p "$DEST/puzzles"
  rsync -a --delete --exclude README.md "$REPO/puzzles/" "$DEST/puzzles/"
else
  echo "warning: puzzles/index.json is missing; the app will have no puzzles. Run scripts/copy-puzzles.sh." >&2
fi
/usr/bin/env python3 "$SRCROOT/scripts/bundle-engines.py" "$REPO/engines/dist" "$DEST/engines"
