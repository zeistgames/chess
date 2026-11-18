#!/usr/bin/env bash
# Caissa 2.0, single-threaded WASM worker. The network stays a separate file,
# loaded from the working directory as Caissa does without an embedded net.
source "$(dirname "$0")/../tools/common.sh"

REPO="https://github.com/Witek902/Caissa.git"
COMMIT="bb725799e9b19ebdaa0d584f5433fc1c3019e349"   # tag 2.0
NET="eval-ml-8-152B-spsa.pnn"
NET_URL="https://github.com/Witek902/Caissa-Nets/releases/download/eval-ml-8-152B-spsa/$NET"
NET_SHA256="ee9f6bbb0ef6cd1f38a13cf095340968c2ad18d0fa1359d493043e61acc829fa"

use_emsdk
git_checkout "$REPO" "$COMMIT" "$WORK/src"
apply_patches "$WORK/src"
fetch "$NET_URL" "$NET_SHA256" "$WORK/$NET"

cd "$WORK/src/src"
SRCS=(backend/*.cpp frontend/*.cpp backend/syzygy/tbprobe.cpp)
CXXFLAGS="-O3 -msimd128 -msse4.1 -std=c++20 -fno-rtti -fno-exceptions -DCONFIGURATION_FINAL -DNDEBUG -DCAISSA_VERSION=\\\"2.0\\\" -DUSE_SSE -DUSE_SSE2 -DUSE_SSE4 -DUSE_POPCNT -Wno-everything"
em_compile "$WORK/obj" "$CXXFLAGS" "${SRCS[@]}"

echo "Module.zeistFiles = [{ url: \"$NET\", path: \"/$NET\" }]; Module.zeistArgs = [];" > "$WORK/config.js"
start_pack
em_link "$OUT/caissa.js" "$WORK/config.js" -- "$WORK"/obj/*.o
cp "$WORK/$NET" "$OUT/$NET"
cp "$WORK/src/LICENSE" "$OUT/LICENSE.txt"
finish_pack
