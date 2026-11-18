# Fairy-Stockfish

- Upstream: https://github.com/fairy-stockfish/Fairy-Stockfish, commit e48b7537eb64e2bf47889f8acbd82f7d1eba7837 (master, 2026-11-14). The last tagged release, fairy_sf_14, is from 2021, so the pack pins master.
- Code license: GPL-3.0-or-later (`Copying.txt` and source headers), shipped as `COPYING.txt`.
- Network: none. Fairy-Stockfish uses NNUE only when given a net named after the variant; standard chess here plays with its classical evaluation, so no net file is fetched or embedded.
- Patched (`patches/0001-single-threaded-worker.patch`, under `#ifdef __EMSCRIPTEN__` only):
  - `thread.cpp`: no native thread is started; `start_searching()` runs the search inline.
  - `uci.cpp`: the loop state is static and `zeist_handle_line()` runs one UCI line through the existing dispatch.
  - `main.cpp`: returns after setup without tearing the engine down, so the worker keeps it.
- Built with Emscripten 6.0.9, `-O3 -msimd128`, linked with `tools/glue/` (inline threads, `zeist_uci` export, worker message glue).
- Strength: `UCI_LimitStrength` with `UCI_Elo` 500 to 2850, and `Skill Level` -20 to 20. Both randomize move choice.
