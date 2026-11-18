# Engines

Each folder builds one engine pack for the app: a Web Worker that speaks UCI one line per message, its WASM and its network files. The pack contract is in `../docs/PLAN.md` ("Engine pack"); results are in `STATUS.md`.

## Layout

- `<id>/build.sh`: fetches the pinned upstream source (or release files), applies `<id>/patches/*.patch`, builds, and writes the pack to the staging folder `build/<id>/pack/`.
- `<id>/meta.json`: the manifest fields that are not computed. `tools/pack.mjs` adds `files` (path, bytes, sha256) and `total_bytes` and writes `manifest.json`.
- `<id>/README.md`: upstream URL and pinned commit, code and network licenses with where they are stated, and what was patched.
- `tools/glue/`: linked into every Emscripten port. `zeist_glue.c` runs threads inline (a non-pthread build cannot start one) and exports `zeist_uci(line)`; `worker-pre.js` turns the output into a dedicated worker, fetches network files by relative path into the in-memory file system before `main()`, and posts each output line.
- `check.mjs`: the pack check in Node, with `tools/worker-shim.cjs` emulating a dedicated worker (no `process`, no network).
- `check-webkit.mjs`: the same check in Playwright's WebKit, served under a CSP that allows no outside connections; also records time to first move and peak memory.
- `tools/promote.sh`: copies a staged pack into `dist/<id>/` only if both checks passed for its current manifest, swaps it in whole, and rewrites `dist/catalog.json`. `dist/` never holds a half-written or failing pack.

## Rebuild

One time: install Emscripten 6.0.9 (`git clone https://github.com/emscripten-core/emsdk`, then `./emsdk install 6.0.9 && ./emsdk activate 6.0.9`; emsdk needs Python 3.10 or later), and Playwright with WebKit in a folder of your choice (`npm i playwright && npx playwright install webkit`).

```sh
export EMSDK=/path/to/emsdk           # or have emcc 6.0.9 on PATH
export PLAYWRIGHT_DIR=/path/to/pw     # the folder where playwright is installed
engines/build-all.sh                  # every engine in order.json: build, check, promote
engines/build-all.sh clover halogen   # only these
```

Single steps: `engines/<id>/build.sh`, `node engines/check.mjs <id>`, `node engines/check-webkit.mjs <id>`, `engines/tools/promote.sh <id>`. Add `--dist` to either check to check what is in `dist/`.

## Additions to the contract

- `strength` is `{"type": "uci_elo", "min", "max"}` or `{"type": "none"}`. For `uci_elo` the host sends `setoption name UCI_LimitStrength value true` and `setoption name UCI_Elo value N`. Stockfish packs also name their `Skill Level` range (`skill_option`, `skill_min`, `skill_max`).
- `check_nodes` (Maia only, 1) is the node budget the check uses, since Maia does not search.
- `total_bytes` is the sum of `files[].bytes`.
- Every `catalog.json` entry is the full manifest plus `manifest` (its path), `manifest_sha256` and the check results.
