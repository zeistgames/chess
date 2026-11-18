# PlentyChess

- Upstream: https://github.com/Yoshie2000/PlentyChess, tag b-v8.0.0, the release "PlentyChess 8.0.0" (commit 50ad9f1b523063cbbbf599fe0547f42870fe2906).
- Code license: GPL-3.0 (`LICENSE`, shipped as `LICENSE.txt`). The sources carry no "or any later version" header, so the manifest says GPL-3.0-only.
- Network: `0178r` (the tag's `network.txt`), the 47,804,242-byte `0178r.bin` from https://github.com/Yoshie2000/PlentyNetworks/releases/tag/0178r, pinned by sha256. License GPL-3.0, the `LICENSE` of https://github.com/Yoshie2000/PlentyNetworks. The build converts it with PlentyChess's own `tools/process_net.cpp` (compiled to WASM with the engine's SIMD flags and run in Node) into `processed.bin` (53,111,616 bytes), the layout this build reads. The conversion is a transpose and permutation of the same weights.
- Patched (`patches/0001-single-threaded-worker.patch`, all under `__EMSCRIPTEN__`):
  - `nnue.cpp`: reads `/processed.bin` into an aligned buffer instead of embedding it with incbin.
  - `thread.h`: workers are created without threads; `ThreadPool::startSearching()` runs each worker's search inline.
  - `uci.cpp`: the loop body becomes `zeistUciLine()`, called once per line; the board and history are kept after setup.
- Built with Emscripten 6.0.9, `-O3 -msimd128 -mssse3 -DARCH_X86` (PlentyChess's SSSE3 path, translated to WASM SIMD).
- Strength: none built in.
