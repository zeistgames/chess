#!/usr/bin/env bash
# Halogen 16, single-threaded WASM worker. The released net is converted to
# this build's layout with Halogen's own tools/verbatim.cpp, compiled to WASM
# with the engine's SIMD flags and run under Node.
source "$(dirname "$0")/../tools/common.sh"

REPO="https://github.com/KierenP/Halogen.git"
COMMIT="fa6d24a5423a20b4530723cd0f6f76d4da0581d8"   # tag v16
NET_ID="150521a9"
NET_SHA256="150521a9957beb7fe90395dd5b134f75cde4e6dfc95e5d5fdee80031e7c7c9cb"

use_emsdk
git_checkout "$REPO" "$COMMIT" "$WORK/src"
apply_patches "$WORK/src"
fetch "https://github.com/KierenP/Halogen-Networks/releases/download/$NET_ID/$NET_ID.nn" "$NET_SHA256" "$WORK/$NET_ID.nn"

cd "$WORK/src/src"
ARCH="-msimd128 -msse4.2 -DUSE_SSE4"
BASE="-O3 -DNDEBUG -I. -std=c++20 -fno-exceptions -ffp-contract=off -DEVALFILE=\\\"verbatim.nn\\\" -Wno-everything"

# 1. Convert the net to verbatim.nn for this SIMD layout.
em++ $BASE $ARCH -sNODERAWFS=1 -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=8MB tools/verbatim.cpp -o "$WORK/verbatim.js"
( cd "$WORK" && node verbatim.js "$NET_ID.nn" verbatim.nn )

# 2. The engine.
SRCS=(main.cpp chessboard/board_state.cpp chessboard/game_state.cpp evaluation/evaluate.cpp
  movegen/move.cpp movegen/movegen.cpp network/network.cpp numa/numa.cpp search/cuckoo.cpp
  search/data.cpp search/history.cpp search/search.cpp search/staged_movegen.cpp
  search/static_exchange_evaluation.cpp search/syzygy.cpp search/zobrist.cpp search/limit/time.cpp
  search/transposition/table.cpp search/transposition/entry.cpp search/thread.cpp
  test/static_exchange_evaluation_test.cpp third-party/Pyrrhic/tbprobe.cpp uci/uci.cpp
  datagen/datagen.cpp datagen/encode.cpp utility/arch.cpp)
em_compile "$WORK/obj" "$BASE $ARCH" "${SRCS[@]}"

echo 'Module.zeistFiles = [{ url: "verbatim.nn", path: "/verbatim.nn" }]; Module.zeistArgs = [];' > "$WORK/config.js"
start_pack
em_link "$OUT/halogen.js" "$WORK/config.js" -- "$WORK"/obj/*.o
cp "$WORK/verbatim.nn" "$OUT/verbatim.nn"
cp "$WORK/src/LICENSE" "$OUT/LICENSE.txt"
finish_pack
