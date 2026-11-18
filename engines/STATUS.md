# Engine packs: status

Updated 2026-11-14. Every pack below passed `check.mjs` (Node) and `check-webkit.mjs` (Playwright WebKit) and is in `dist/catalog.json`. Times are from load to the first `bestmove` for `position startpos moves e2e4` + `go nodes 20000` (Maia: `go nodes 1`) on the Mac mini; memory is the peak resident size of all WebKit processes, sampled every 100 ms, minus the browser's own baseline of about 310 MB ("-" means the search ended before a sample).

| Engine | id | Pack | First move, Node | First move, WebKit | Memory over baseline | Strength option | Code / net license |
|---|---|---|---|---|---|---|---|
| Stockfish Lite 19.0.1 | `stockfish-lite` | 1.8 MB | 111 ms | 100 ms | 195 MB | UCI_Elo 1320 to 3190 | GPL-3.0-or-later / CC0-1.0 |
| Stockfish 19.0.1 | `stockfish` | 94.6 MB | 395 ms | 515 ms | 851 MB | UCI_Elo 1320 to 3190 | GPL-3.0-or-later / CC0-1.0 |
| Fairy-Stockfish (master e48b753) | `fairy-stockfish` | 1.0 MB | 128 ms | 102 ms | 142 MB | UCI_Elo 500 to 2850 | GPL-3.0-or-later / no net |
| Maia 3 | `maia` | 55.0 MB | 494 ms | 393 ms | 635 MB | UCI_Elo 600 to 2600 | AGPL-3.0-or-later and others / AGPL-3.0 |
| Arasan 26.1 | `arasan` | 24.7 MB | 222 ms | 148 ms | 326 MB | UCI_Elo 1000 to 3450 | MIT / MIT |
| Clover 9.1 | `clover` | 13.6 MB | 60 ms | 67 ms | 187 MB | none | GPL-3.0-or-later / GPL-3.0 |
| Caissa 2.0 | `caissa` | 72.7 MB | 116 ms | 129 ms | 427 MB | none | MIT / MIT |
| PlentyChess 8.0.0 | `plentychess` | 51.1 MB | 207 ms | 167 ms | 273 MB | none | GPL-3.0 / GPL-3.0 |
| Halogen 16 | `halogen` | 18.7 MB | 74 ms | 59 ms | 273 MB | none | GPL-3.0 / GPL-3.0 |
| Koivisto 9.0 | `koivisto` | 12.4 MB | 57 ms | 49 ms | - | none | GPL-3.0-or-later / MIT |
| Ethereal 14.00 (classical) | `ethereal` | 0.5 MB | 54 ms | 35 ms | - | none | GPL-3.0-or-later / GPL-3.0 (in-repo PK net) |

Single-thread speed in Node on the Mac mini, `go movetime 2000` after 1. e4: Arasan about 0.77 M nodes/s, Clover 1.9 M, Caissa 1.3 M, PlentyChess 0.47 M, Halogen 0.97 M, Koivisto 2.7 M, Ethereal 2.6 M. A phone will be slower. Not yet run on an iPhone.

## Not built

- **Viridithas** (AGPL-3.0, net CC0-1.0). Stopped after reading the source. Its NNUE code has only AVX2, AVX-512 and NEON backends written with `std::arch` x86/ARM intrinsics (`src/nnue/simd.rs`, `src/nnue/geometry/*.rs`, `threat_updates.rs`, `accumulator.rs`, `transpositiontable.rs`) and no portable fallback, so a WASM build needs a new WASM SIMD backend, not a small patch. On top of that, its UCI loop reads stdin on a separate thread, search uses a thread pool, and the network is decompressed into a memory-mapped temp file. Each is patchable, but together with the SIMD backend this is a port, not a patch. The v20.0.0 net (v109, about 52 MB compressed, about 100 MB in memory) would also be heavy on a phone.
- **pawnocchio** (GPL-3.0, Zig; nets CC-BY-SA-4.0). Not attempted: no Zig toolchain is set up, and the engine uses memory-mapped nets, a thread pool and blocking stdin, which need an I/O port for a browser worker.
- **Triumviratus** (GPL-3.0, net GPL-3.0). Not attempted: the 243 MB net is too large for a phone web view (full Stockfish with a 99 MB WASM already peaks at about 850 MB over baseline in WebKit).
- Skipped for license, as the research requires: Reckless, Obsidian, Alexandria, Stormphrax, Hobbes, Berserk, Seer, RubiChess and Lc0 (no license stated for the network), Integral (no license for the code). Maia-2 (checkpoints have no stated license). Maia-1 (GPL-3.0) would need its Lc0 weights converted to ONNX; Maia-3 covers the same role.

## Known limits

- `stop` does not interrupt a search in any port (the host ends a search by ending the worker, as the contract says). `go infinite` and `go ponder` never return on their own.
- Stockfish full keeps its net inside the 99 MB WASM, so it cannot follow the App Store split (engine bundled, net downloaded) without a rebuild from source with the net as a separate file.
- PlentyChess and Halogen ship their net already converted to the layout of this build (`processed.bin`, `verbatim.nn`), made by each engine's own converter during the build.
