#!/usr/bin/env bash
# Stockfish 19, single-threaded, full net: the unmodified stockfish.js v19.0.1
# release files, pinned by sha256. The full net (nn-1a298aa575a0) is embedded
# in the WASM.
source "$(dirname "$0")/../tools/common.sh"

REL="https://github.com/nmrugg/stockfish.js/releases/download/v19.0.1"
TAG_RAW="https://raw.githubusercontent.com/nmrugg/stockfish.js/v19.0.1"

fetch "$REL/stockfish-19-single.js"   8071dee87312f74805a859de933e1a1ef465579ab1a51fbd597388cdce9d444d "$WORK/stockfish-19-single.js"
fetch "$REL/stockfish-19-single.wasm" 991bede2f253ebb08ff01fcc48270f4b9c8e66b12d5bd5f8d6f52eb3e3b3a740 "$WORK/stockfish-19-single.wasm"
fetch "$TAG_RAW/Copying.txt"          0b383d5a63da644f628d99c33976ea6487ed89aaa59f0b3257992deac1171e6b "$WORK/COPYING.txt"

start_pack
cp "$WORK/stockfish-19-single.js" "$WORK/stockfish-19-single.wasm" "$WORK/COPYING.txt" "$OUT/"
finish_pack
