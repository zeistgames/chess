#!/usr/bin/env bash
# Ethereal 14.00, classical build (USE_NNUE=0, the upstream default without an
# EVALFILE), single-threaded WASM worker. Its only network is the small
# pawn-king net compiled in from the repository's src/weights.
source "$(dirname "$0")/../tools/common.sh"

REPO="https://github.com/AndyGrant/Ethereal.git"
COMMIT="96cde8d2f82a3ab0536bf33572405fda96f6e236"   # tag v14.00

use_emsdk
git_checkout "$REPO" "$COMMIT" "$WORK/src"
apply_patches "$WORK/src"

cd "$WORK/src/src"
SRCS=(*.c pyrrhic/tbprobe.c)
CFLAGS="-O3 -msimd128 -std=gnu11 -DNDEBUG -DUSE_NNUE=0 -DUSE_POPCNT -w"
em_compile "$WORK/obj" "$CFLAGS" "${SRCS[@]}"

echo 'Module.zeistFiles = []; Module.zeistArgs = [];' > "$WORK/config.js"
start_pack
em_link "$OUT/ethereal.js" "$WORK/config.js" -- "$WORK"/obj/*.o
cp "$WORK/src/LICENSE" "$OUT/LICENSE.txt"
finish_pack
