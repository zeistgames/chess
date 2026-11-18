# Halogen

- Upstream: https://github.com/KierenP/Halogen, tag v16 (commit fa6d24a5423a20b4530723cd0f6f76d4da0581d8).
- Code license: GPL-3.0 (`LICENSE`, shipped as `LICENSE.txt`); no "or later" header was found, so the manifest says GPL-3.0-only.
- Network: `150521a9` (the tag's default `NET_HASH`), the 19,305,792-byte `150521a9.nn` from https://github.com/KierenP/Halogen-Networks/releases/tag/150521a9, pinned by sha256. License GPL-3.0, the `LICENSE` of https://github.com/KierenP/Halogen-Networks. The build converts it with Halogen's own `tools/verbatim.cpp` (compiled to WASM with the engine's SIMD flags and run in Node) into `verbatim.nn`, the layout the engine reads; the conversion reorders the same weights.
- Patched (`patches/0001-single-threaded-worker.patch`):
  - `network/network.cpp`: under `__EMSCRIPTEN__`, reads `/verbatim.nn` at static initialization instead of embedding it with incbin.
  - `search/thread.cpp`: under `__EMSCRIPTEN__`, search threads are plain objects and each queued task runs at once on the calling thread. The `go` handler's own `std::thread` runs inline through the shared glue.
  - `main.cpp`: under `__EMSCRIPTEN__`, the UCI objects are kept after setup and `zeist_handle_line()` sends each line to `Uci::process_input()`.
  - Portability fixes for clang's libc++ (behavior unchanged): `utility/static_vector.h` returns `std::array` iterators instead of raw pointers; `chessboard/board_state.cpp` and `uci/parse.h` pass `data()` pointers to `std::from_chars`; `third-party/Pyrrhic/stdendian.h` treats Emscripten like Linux for byte order.
- Built with Emscripten 6.0.9, `-O3 -msimd128 -msse4.2 -DUSE_SSE4` (Halogen's SSE4 path, translated to WASM SIMD).
- Strength: none built in.
