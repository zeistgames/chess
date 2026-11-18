# Ethereal (classical)

- Upstream: https://github.com/AndyGrant/Ethereal, tag v14.00 (commit 96cde8d2f82a3ab0536bf33572405fda96f6e236).
- Code license: GPL-3.0-or-later (`LICENSE`, shipped as `LICENSE.txt`; source headers say "either version 3 of the License, or (at your option) any later version").
- Network: this is Ethereal's classical build (`USE_NNUE=0`, what its makefile builds when no `EVALFILE` is given). It uses a hand-tuned evaluation plus the small pawn-king network `src/weights/pknet_224x32x2.net` (140,459 bytes) from the repository itself, compiled into the WASM, under the repository's GPL-3.0 `LICENSE`. Ethereal's large NNUE file is not part of the repository and has no stated license, so it is not used.
- Patched (`patches/0001-single-threaded-worker.patch`):
  - `uci.c`: under `__EMSCRIPTEN__`, the loop state is static, `main()` returns after setup, and `zeist_handle_line()` runs the existing loop body once per line. Ethereal's per-`go` search thread runs inline through the shared glue.
  - `uci.c`, `syzygy.h`: two C declarations made to match their definitions (`initPKNetwork()` takes no argument; `tablebasesProbeDTZ` returns void). Native builds tolerate the mismatch; WASM traps on it. Behavior is unchanged.
  - `pyrrhic/stdendian.h`: treats Emscripten like Linux for byte order.
- Built with Emscripten 6.0.9, `-O3 -msimd128 -DUSE_POPCNT`.
- Strength: none built in.
