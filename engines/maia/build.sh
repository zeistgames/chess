#!/usr/bin/env bash
# Maia-3 as a UCI worker: the Maia platform's ONNX export of Maia-3, run with a
# pinned onnxruntime-web (WASM backend, one thread), with chess.js for legal
# moves. No compiling: everything is fetched, pinned by sha256, and copied.
source "$(dirname "$0")/../tools/common.sh"

PLATFORM="https://raw.githubusercontent.com/CSSLab/maia-platform-frontend/8b91abf4646788ed53edd471a37c20b8d8c94d94"
fetch "$PLATFORM/public/maia3/maia3_simplified.onnx" 405bf76c15727dad8728b352c06a8f3c1b80fb2760e8d666b32485c63d75b856 "$WORK/maia3_simplified.onnx"
fetch "$PLATFORM/LICENSE" 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986 "$WORK/LICENSE-maia-platform.txt"
fetch "https://raw.githubusercontent.com/CSSLab/maia3/1e13597c42d4858b7cfd7cfdae01e297263364b2/LICENSE" 8486a10c4393cee1c25392769ddd3b2d6c242d6ec7928e1414efff7dfb2f07ef "$WORK/LICENSE-maia3.txt"
fetch "https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-1.23.0.tgz" 7e0074d9319fdef002bcf28ef73eb119dd6302083fa0395ec560cb4e5ca0970b "$WORK/ort.tgz"
fetch "https://raw.githubusercontent.com/microsoft/onnxruntime/v1.23.0/LICENSE" 2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c "$WORK/LICENSE-onnxruntime.txt"
fetch "https://registry.npmjs.org/chess.js/-/chess.js-0.12.1.tgz" fae7e1150d2180c0b9bc2fa742bbe3d88066ada8bb11ebf176a2939a9693dade "$WORK/chessjs.tgz"

rm -rf "$WORK/ort" "$WORK/chessjs" && mkdir -p "$WORK/ort" "$WORK/chessjs"
tar xzf "$WORK/ort.tgz" -C "$WORK/ort"
tar xzf "$WORK/chessjs.tgz" -C "$WORK/chessjs"

start_pack
mkdir -p "$OUT/ort"
cp "$SRC_DIR/worker.js" "$OUT/worker.js"
cp "$WORK/maia3_simplified.onnx" "$OUT/"
cp "$WORK/chessjs/package/chess.js" "$OUT/chess.js"
cp "$WORK/chessjs/package/LICENSE" "$OUT/LICENSE-chess.js.txt"
for f in ort.wasm.min.js ort-wasm-simd-threaded.mjs ort-wasm-simd-threaded.wasm; do
  cp "$WORK/ort/package/dist/$f" "$OUT/ort/$f"
done
cp "$WORK/LICENSE-onnxruntime.txt" "$WORK/LICENSE-maia3.txt" "$WORK/LICENSE-maia-platform.txt" "$OUT/"
finish_pack
