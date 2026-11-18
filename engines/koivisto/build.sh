#!/usr/bin/env bash
# Koivisto 9.0, single-threaded WASM worker. The network (from the pinned
# KoivistoNetworks submodule) stays a separate file.
source "$(dirname "$0")/../tools/common.sh"

REPO="https://github.com/Luecx/Koivisto.git"
COMMIT="2895237d7a4ff267752fb19852ce9868bdccb753"   # tag v9.0
NET="default.net"

use_emsdk
git_checkout "$REPO" "$COMMIT" "$WORK/src"
apply_patches "$WORK/src"
[ -f "$WORK/src/networks/$NET" ] || { log "network submodule missing"; exit 1; }

cd "$WORK/src/src_files"
SRCS=(attacks.cpp bitboard.cpp board.cpp eval.cpp history.cpp main.cpp move.cpp movegen.cpp newmovegen.cpp
  perft.cpp polyglot.cpp search.cpp timemanager.cpp transpositiontable.cpp uci.cpp util.cpp)
CXXFLAGS="-O3 -msimd128 -msse2 -std=c++17 -DNDEBUG -DMINOR_VERSION=0 -DMAJOR_VERSION=9 -DEVALFILE=\\\"$NET\\\" -Wno-everything"
em_compile "$WORK/obj" "$CXXFLAGS" "${SRCS[@]}"
emcc -O3 -msimd128 -msse2 -w -c syzygy/tbprobe.c -o "$WORK/obj/tbprobe.o"

echo "Module.zeistFiles = [{ url: \"$NET\", path: \"/$NET\" }]; Module.zeistArgs = [];" > "$WORK/config.js"
start_pack
em_link "$OUT/koivisto.js" "$WORK/config.js" -- "$WORK"/obj/*.o
cp "$WORK/src/networks/$NET" "$OUT/$NET"
cp "$WORK/src/LICENSE.md" "$OUT/LICENSE.txt"
cp "$WORK/src/networks/LICENSE" "$OUT/LICENSE-networks.txt"
finish_pack
