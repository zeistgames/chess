#!/usr/bin/env bash
# Stockfish 19 lite, single-threaded: the unmodified stockfish.js v19.0.1
# release files, pinned by sha256. The small net is embedded in the WASM.
source "$(dirname "$0")/../tools/common.sh"

REL="https://github.com/nmrugg/stockfish.js/releases/download/v19.0.1"
TAG_RAW="https://raw.githubusercontent.com/nmrugg/stockfish.js/v19.0.1"

fetch "$REL/stockfish-19-lite-single.js"   ccb130d7ff29408531c47d859a49f91d59d4f482d05a53eb1a3231a4f624c91a "$WORK/stockfish-19-lite-single.js"
fetch "$REL/stockfish-19-lite-single.wasm" ee4f115bdb2d32cadf96cada104a05b5ec257d7ad6f57582190b49bc71f096de "$WORK/stockfish-19-lite-single.wasm"
fetch "$TAG_RAW/Copying.txt"               0b383d5a63da644f628d99c33976ea6487ed89aaa59f0b3257992deac1171e6b "$WORK/COPYING.txt"

start_pack
cp "$WORK/stockfish-19-lite-single.js" "$WORK/stockfish-19-lite-single.wasm" "$WORK/COPYING.txt" "$OUT/"
finish_pack
