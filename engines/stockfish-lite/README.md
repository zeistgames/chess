# Stockfish Lite

- Upstream: https://github.com/nmrugg/stockfish.js, release v19.0.1 (tag commit 0d5dd7944f88c817c07a26bc4fb1905d5f9c46d6), a WASM port of https://github.com/official-stockfish/Stockfish (Stockfish 19).
- Files: `stockfish-19-lite-single.js` and `stockfish-19-lite-single.wasm` from the release page, unmodified, pinned by sha256 in `build.sh`. `COPYING.txt` is the release's `Copying.txt`.
- Code license: GPL-3.0-or-later (Stockfish `Copying.txt` and source headers; stockfish.js is GPL-3.0, https://github.com/nmrugg/stockfish.js).
- Network: `nn-61e7af4bb97d.nnue` (1,166,381 bytes), embedded in the WASM. License CC0-1.0, stated at https://github.com/official-stockfish/networks ("uploaded by the authors under the CC0 license").
- Patched: nothing.
- Corresponding source: the tag above. To rebuild the WASM from C++, install Emscripten 6.0.9 and run `node build.js --single-threaded --lite -f` in that tag (see its README).
- Strength: `UCI_LimitStrength` with `UCI_Elo` 1320 to 3190, and `Skill Level` 0 to 20. Both randomize move choice, so weakened play is not repeatable move for move.
