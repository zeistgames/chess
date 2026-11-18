# Stockfish

- Upstream: https://github.com/nmrugg/stockfish.js, release v19.0.1 (tag commit 0d5dd7944f88c817c07a26bc4fb1905d5f9c46d6), a WASM port of https://github.com/official-stockfish/Stockfish (Stockfish 19).
- Files: `stockfish-19-single.js` and `stockfish-19-single.wasm` from the release page, unmodified, pinned by sha256 in `build.sh`. `COPYING.txt` is the release's `Copying.txt`.
- Code license: GPL-3.0-or-later (Stockfish `Copying.txt` and source headers; stockfish.js is GPL-3.0).
- Network: `nn-1a298aa575a0.nnue`, embedded in the 99 MB WASM. License CC0-1.0, stated at https://github.com/official-stockfish/networks.
- Patched: nothing.
- Corresponding source: the tag above; `node build.js --single-threaded -f` with Emscripten 6.0.9.
- The net is inside the WASM, so for the App Store split (engine bundled, net downloaded) this pack would need a rebuild with the net loaded from a separate file. Not done yet.
- Strength: `UCI_LimitStrength` with `UCI_Elo` 1320 to 3190, and `Skill Level` 0 to 20.
