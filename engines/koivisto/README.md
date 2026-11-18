# Koivisto

- Upstream: https://github.com/Luecx/Koivisto, tag v9.0 (commit 2895237d7a4ff267752fb19852ce9868bdccb753).
- Code license: GPL-3.0-or-later (`LICENSE.md`, shipped as `LICENSE.txt`; source headers say "either version 3 of the License, or (at your option) any later version").
- Network: `default.net` (12,585,988 bytes) from the `networks` submodule, https://github.com/Luecx/KoivistoNetworks at commit 8cae81230c6bf36733a292ee7633602dfbbe9c49, as pinned by the tag. License MIT, the `LICENSE` of that repository, shipped as `LICENSE-networks.txt`. Shipped as a separate file.
- Patched (`patches/0001-single-threaded-worker.patch`, under `__EMSCRIPTEN__` unless noted):
  - `eval.cpp`: reads `/default.net` instead of embedding it with incbin.
  - `uci.cpp`: `mainloop()` returns after setup; `zeist_handle_line()` passes each line to `uci::processCommand()`. Koivisto's per-`go` search thread runs inline through the shared glue, so no thread code changes.
  - `syzygy/stdendian.h`: treats Emscripten like Linux for byte order.
- Built with Emscripten 6.0.9, `-O3 -msimd128 -msse2` (Koivisto's SSE2 path, translated to WASM SIMD).
- Strength: none built in. No MultiPV option.
