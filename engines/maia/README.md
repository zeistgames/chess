# Maia 3

Maia-3 is a transformer trained on Lichess games to predict the move a human of a given rating would play. This pack runs it as a UCI engine.

- Model: `maia3_simplified.onnx` (45,683,686 bytes, 22.7 million fp16 parameters, opset 17) from https://github.com/CSSLab/maia-platform-frontend at commit 8b91abf4646788ed53edd471a37c20b8d8c94d94 (`public/maia3/`). Which published Maia-3 size it matches is not verified; its parameter count is closest to Maia3-23M.
- Model license: AGPL-3.0. The Hugging Face model cards (for example https://huggingface.co/UofTCSSLab/Maia3-5M) say "see repo for code/weights license", and the repo https://github.com/CSSLab/maia3 (commit 1e13597c42d4858b7cfd7cfdae01e297263364b2) carries the AGPL-3.0 `LICENSE`, shipped as `LICENSE-maia3.txt`. The platform repo that hosts this ONNX export is GPL-3.0 (`LICENSE-maia-platform.txt`).
- Code: `worker.js` is this repo's (AGPL-3.0-or-later). Its input encoding and move indexing follow the platform's `src/lib/engine/tensor.ts` (GPL-3.0). Vendored: onnxruntime-web 1.23.0 from npm (MIT, `LICENSE-onnxruntime.txt`; the version the Maia platform uses) and chess.js 0.12.1 from npm (BSD-2-Clause, `LICENSE-chess.js.txt`) for legal moves.
- Patched: nothing upstream. The worker caps onnxruntime's shared WebAssembly memory at 256 MB, as the platform does for iPhones, runs one thread, and uses graph optimization level `basic`.
- How it plays: `go` (any limits) runs the network once and plays the legal move with the highest policy, so it is repeatable. `info` lines carry the top moves (`MultiPV` 1 to 10), a score from the value head, and an `info string policy` line with probabilities.
- Strength: `UCI_Elo` 600 to 2600 is the rating Maia imitates. `Opponent Elo` (0 means the same) is the rating it assumes for the other side. `UCI_LimitStrength` is accepted and has no effect.
