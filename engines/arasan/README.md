# Arasan

- Upstream: https://github.com/jdart1/arasan-chess, tag v26.1 (commit 0c0bebd04b5e5b99560cfd0998fd1cc48a97f8a9).
- Code license: MIT (`LICENSE`, shipped as `LICENSE.txt`).
- Network: `arasanv8-20261005.nnue` (25,024,576 bytes) from the repo's `network` directory at the same tag, shipped as a separate file that the worker fetches into its in-memory file system. License MIT: the same `LICENSE` says it covers "the contents of the src, book, doc, prj, tests, and network directories" (https://github.com/jdart1/arasan-chess/blob/v26.1/LICENSE).
- Patched (`patches/0001-single-threaded-worker.patch`, under `#ifdef __EMSCRIPTEN__` only):
  - `arasanx.cpp`: after setup, keeps the `Protocol` object and returns; `zeist_handle_line()` passes each line to it.
  - `protocol.cpp`, `protocol.h`: `Protocol::zeistLine()` queues one command and runs the existing `do_all_pending()`.
  - `input.cpp`: `checkInput()` returns false, since nothing arrives during a search.
- With one thread Arasan already searches on the calling thread, so no thread code changes. Opening book and ECO files are not shipped; Arasan warns and plays without them.
- Built with Emscripten 6.0.9, `-O3 -msimd128 -msse2` (Arasan's SSE2 path, translated to WASM SIMD), Syzygy support compiled in but no tablebases shipped.
- Strength: `UCI_LimitStrength` with `UCI_Elo` 1000 to 3450.
