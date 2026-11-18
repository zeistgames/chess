#!/usr/bin/env bash
# Fairy-Stockfish, standard chess, single-threaded WASM worker. Classical
# evaluation (Fairy-Stockfish uses NNUE only with a variant-named net), so the
# pack has no network file.
source "$(dirname "$0")/../tools/common.sh"

REPO="https://github.com/fairy-stockfish/Fairy-Stockfish.git"
COMMIT="e48b7537eb64e2bf47889f8acbd82f7d1eba7837"

use_emsdk
git_checkout "$REPO" "$COMMIT" "$WORK/src"
apply_patches "$WORK/src"

cd "$WORK/src/src"
SRCS=(benchmark.cpp bitbase.cpp bitboard.cpp endgame.cpp evaluate.cpp main.cpp
  material.cpp misc.cpp movegen.cpp movepick.cpp pawns.cpp position.cpp psqt.cpp
  search.cpp thread.cpp timeman.cpp tt.cpp uci.cpp ucioption.cpp tune.cpp syzygy/tbprobe.cpp
  nnue/evaluate_nnue.cpp nnue/features/half_ka_v2.cpp
  partner.cpp parser.cpp piece.cpp variant.cpp xboard.cpp
  nnue/features/half_ka_v2_variants.cpp)
CXXFLAGS="-O3 -msimd128 -std=c++17 -fno-exceptions -fno-strict-aliasing -DNDEBUG -DIS_64BIT -DUSE_POPCNT -DNO_PREFETCH -DNNUE_EMBEDDING_OFF -Wno-everything"
em_compile "$WORK/obj" "$CXXFLAGS" "${SRCS[@]}"

echo 'Module.zeistFiles = []; Module.zeistArgs = [];' > "$WORK/config.js"
start_pack
em_link "$OUT/fairy-stockfish.js" "$WORK/config.js" -- "$WORK"/obj/*.o
cp "$WORK/src/Copying.txt" "$OUT/COPYING.txt"
finish_pack
