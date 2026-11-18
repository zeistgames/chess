# Caissa

- Upstream: https://github.com/Witek902/Caissa, tag 2.0 (commit bb725799e9b19ebdaa0d584f5433fc1c3019e349).
- Code license: MIT (`LICENSE`, shipped as `LICENSE.txt`).
- Network: `eval-ml-8-152B-spsa.pnn` (75,703,872 bytes), the default net of tag 2.0, from the release https://github.com/Witek902/Caissa-Nets/releases/tag/eval-ml-8-152B-spsa, pinned by sha256 in `build.sh` and shipped as a separate file. License MIT, stated by the `LICENSE` of https://github.com/Witek902/Caissa-Nets.
- Patched (`patches/0001-single-threaded-worker.patch`, all under `__EMSCRIPTEN__`):
  - `frontend/UCI.cpp`: no search thread is started; `go` runs `DoSearch()` inline; `Loop()` returns before reading stdin; `main()` keeps the interface object and `zeist_handle_line()` sends each line to `ExecuteCommand()`; the thread join only runs when a thread exists.
  - `backend/Common.cpp`: skips the SSE denormal mode calls, which WASM does not have.
- Built without `CAISSA_EVALFILE`, so Caissa loads the net from its working directory (the worker writes it to `/`).
- Built with Emscripten 6.0.9, `-O3 -msimd128 -msse4.1` and Caissa's `USE_SSE4` path, translated to WASM SIMD.
- Strength: none built in.
