#!/usr/bin/env bash
# Arasan 26.1, single-threaded WASM worker. The network file stays separate
# and is fetched by the worker into its in-memory file system.
source "$(dirname "$0")/../tools/common.sh"

REPO="https://github.com/jdart1/arasan-chess.git"
COMMIT="0c0bebd04b5e5b99560cfd0998fd1cc48a97f8a9"   # tag v26.1
NET="arasanv8-20261005.nnue"

use_emsdk
git_checkout "$REPO" "$COMMIT" "$WORK/src"
apply_patches "$WORK/src"

cd "$WORK/src/src"
SRCS=(arasanx.cpp tester.cpp bench.cpp protocol.cpp
  input.cpp globals.cpp board.cpp boardio.cpp material.cpp
  chess.cpp attacks.cpp
  bitutil.cpp chessio.cpp epdrec.cpp bhash.cpp
  scoring.cpp see.cpp
  movearr.cpp notation.cpp options.cpp bitprobe.cpp
  bookread.cpp bookwrit.cpp
  search.cpp searchc.cpp learn.cpp
  movegen.cpp hash.cpp calctime.cpp eco.cpp legal.cpp
  stats.cpp threadp.cpp threadc.cpp evaluate.cpp syzygy.cpp)
CXXFLAGS="-O3 -msimd128 -msse2 -std=c++17 -fno-strict-aliasing -DNDEBUG -D_64BIT -DUSE_INTRINSICS -DARASAN_VERSION=26.1 -DSIMD -DSSE2 -DSMP_STATS -DSYZYGY_TBS -I. -Innue -DNETWORK=$NET -Wno-everything"
em_compile "$WORK/obj" "$CXXFLAGS" "${SRCS[@]}"
em++ $CXXFLAGS -x c++ -c syzygy/src/tbprobe.c -o "$WORK/obj/tbprobe.o"

echo "Module.zeistFiles = [{ url: \"$NET\", path: \"/$NET\", keep: true }]; Module.zeistArgs = [];" > "$WORK/config.js"
start_pack
em_link "$OUT/arasan.js" "$WORK/config.js" -- "$WORK"/obj/*.o
cp "$WORK/src/network/$NET" "$OUT/$NET"
cp "$WORK/src/LICENSE" "$OUT/LICENSE.txt"
finish_pack
