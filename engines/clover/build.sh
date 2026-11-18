#!/usr/bin/env bash
# Clover 9.1, single-threaded WASM worker. The network stays a separate file.
source "$(dirname "$0")/../tools/common.sh"

REPO="https://github.com/lucametehau/CloverEngine.git"
COMMIT="e647926a8f23b6b93f7f27c01cb6f686909ec482"   # tag v9.1
NET="quantised.nnue"

use_emsdk
git_checkout "$REPO" "$COMMIT" "$WORK/src"
apply_patches "$WORK/src"

cd "$WORK/src/src"
CXXFLAGS="-O3 -msimd128 -msse2 -std=c++20 -DNDEBUG -DEVALFILE=\\\"$NET\\\" -DVERSION_NAME=\\\"9.1\\\" -I. -I3rdparty/Fathom/src -Wno-everything"
em_compile "$WORK/obj" "$CXXFLAGS" main.cpp
emcc -O3 -msimd128 -msse2 -DNDEBUG -I3rdparty/Fathom/src -Wno-everything -c 3rdparty/Fathom/src/tbprobe.c -o "$WORK/obj/tbprobe.o"

echo "Module.zeistFiles = [{ url: \"$NET\", path: \"/$NET\" }]; Module.zeistArgs = [];" > "$WORK/config.js"
start_pack
em_link "$OUT/clover.js" "$WORK/config.js" -- "$WORK"/obj/*.o
cp "$WORK/src/src/$NET" "$OUT/$NET"
cp "$WORK/src/LICENSE" "$OUT/LICENSE.txt"
finish_pack
