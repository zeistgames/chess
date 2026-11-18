# Clover

- Upstream: https://github.com/lucametehau/CloverEngine, tag v9.1 (commit e647926a8f23b6b93f7f27c01cb6f686909ec482).
- Code license: GPL-3.0-or-later (repository `LICENSE`, shipped as `LICENSE.txt`; source headers say "either version 3 of the License, or (at your option) any later version").
- Network: `src/quantised.nnue` (13,806,144 bytes) from the same tag, shipped as a separate file. It is part of the repository, with no separate license, so it is under the repository's GPL-3.0 `LICENSE` (https://github.com/lucametehau/CloverEngine/blob/v9.1/LICENSE), as the research table records.
- Patched (`patches/0001-single-threaded-worker.patch`):
  - `net.h`: under `__EMSCRIPTEN__`, reads the network from `/quantised.nnue` instead of embedding it with incbin.
  - `thread.h`: under `__EMSCRIPTEN__`, no search thread is started; `ThreadPool::search()` runs the search inline.
  - `uci.h`, `main.cpp`: under `__EMSCRIPTEN__`, the UCI loop body becomes `UCI::zeist_line()`, called once per line; the `UCI` object is kept after `main()`.
  - `search.h`: `checkers() != 0` written as `!= 0ULL` (three places) so clang can pick the operator; behavior is unchanged.
- Built with Emscripten 6.0.9, `-O3 -msimd128 -msse2` (Clover's SSE2 path, translated to WASM SIMD).
- Strength: none built in. The host limits it with node budgets and MultiPV.
