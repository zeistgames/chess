#!/usr/bin/env bash
# PlentyChess 8.0.0, single-threaded WASM worker. The released net is
# converted to this build's SIMD layout with PlentyChess's own process_net
# tool, itself compiled to WASM with the same flags and run under Node.
source "$(dirname "$0")/../tools/common.sh"

REPO="https://github.com/Yoshie2000/PlentyChess.git"
COMMIT="50ad9f1b523063cbbbf599fe0547f42870fe2906"   # tag b-v8.0.0 (release PlentyChess 8.0.0)
NET_ID="0178r"
NET_SHA256="663e0531ac71c6c7c6d3bc4f1fac923bf69136f9786fa1da5c4ac25382aee54b"

use_emsdk
git_checkout "$REPO" "$COMMIT" "$WORK/src"
apply_patches "$WORK/src"
fetch "https://github.com/Yoshie2000/PlentyNetworks/releases/download/$NET_ID/$NET_ID.bin" "$NET_SHA256" "$WORK/$NET_ID.bin"

ARCHFLAGS="-msimd128 -mssse3 -DARCH_X86"

# 1. Convert the net (raw SLEB128 file) to processed.bin for this SIMD layout.
cd "$WORK/src/tools"
em++ -O2 -std=c++17 $ARCHFLAGS -Wno-everything -sNODERAWFS=1 -sINITIAL_MEMORY=536870912 -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=8MB process_net.cpp -o "$WORK/process_net.js"
( cd "$WORK" && node process_net.js false "$NET_ID.bin" processed.bin )

# 2. The engine.
cd "$WORK/src"
SRCS=(src/engine.cpp src/board.cpp src/move.cpp src/uci.cpp src/search.cpp src/thread.cpp src/evaluation.cpp src/tt.cpp src/magic.cpp src/bitboard.cpp src/history.cpp src/nnue.cpp src/time.cpp src/spsa.cpp src/zobrist.cpp src/datagen.cpp src/threat-inputs.cpp src/debug.cpp)
CXXFLAGS="-O3 $ARCHFLAGS -std=c++17 -fcommon -fno-exceptions -fno-rtti -DNDEBUG -DEVALFILE=\\\"processed.bin\\\" -Wno-everything"
em_compile "$WORK/obj" "$CXXFLAGS" "${SRCS[@]}"
emcc -O3 $ARCHFLAGS -w -c src/fathom/src/tbprobe.c -o "$WORK/obj/tbprobe.o"

echo 'Module.zeistFiles = [{ url: "processed.bin", path: "/processed.bin" }]; Module.zeistArgs = [];' > "$WORK/config.js"
start_pack
em_link "$OUT/plentychess.js" "$WORK/config.js" -- "$WORK"/obj/*.o
cp "$WORK/processed.bin" "$OUT/processed.bin"
cp "$WORK/src/LICENSE" "$OUT/LICENSE.txt"
finish_pack
