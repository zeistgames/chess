# Plan

How Zeist Chess is put together. License facts for each engine are in its folder under `engines/`.

## Shape

| Folder | What | Notes |
|---|---|---|
| `core/` | Plain JavaScript, no build step: chess rules behind one interface, the engine host (one Web Worker per engine, UCI text in and out), levels and adaptive difficulty. | Shared later by the web app. Rules use chess.js (BSD-2) as a stand-in until the Zeist rules arrive from the main repo; nothing outside `core/rules.js` may call chess.js. |
| `ios/` | SwiftUI app, iOS 18+, bundle `st.zei.Chess`, xcodegen. Native board and screens. A hidden WKWebView runs `core/` and the engines. | Engine files are served to the web view by a `WKURLSchemeHandler` from the app bundle or Application Support. |
| `engines/` | One folder per engine: `build.sh`, patches, `README.md` with source, version and license. Output goes to `engines/dist/<id>/` (git-ignored). | `engines/STATUS.md` records what built, what failed and why. |

## Engine pack (the contract between `engines/` and the app)

`engines/dist/<id>/` holds:
- `manifest.json`: `id`, `name`, `version`, `author`, `license` (SPDX), `net_license`, `source` (URL), `line` (one plain sentence on its character), `files` (`path`, `bytes`, `sha256`), `entry` (the worker script), `strength` (`uci_elo` with min and max, or `skill` with min and max, or `none`), `multipv` (true or false), `threads` (false for now).
- The worker script: receives one UCI line per `postMessage(string)`, posts one output line per message. Single-threaded. No network access after load. `stop` need not work; the host ends a search by ending the worker.
- The WASM and network files it loads, by relative path.

`engines/dist/catalog.json` lists every manifest. The web app reads the catalog from https://engines.zei.st.

The iPhone app reads no catalog from the network (2026-11-14). App Review does not allow downloading code after install, so:

- A file is data only if its extension is not one of `js`, `mjs`, `wasm`, `txt`, `json`. The rule lives in one place in the app (`PackFiles` in `ios/ZeistChess/Engines/Packs.swift`) and is mirrored in `ios/scripts/bundle-engines.py` and `ios/scripts/packs-server.py`.
- At build time `ios/scripts/bundle-engines.py` copies each engine's `manifest.json` and its program files into the app, with a `catalog.json` made of those manifests. The build stops, naming the pack, if `engines/dist` lacks one (`engines/build-all.sh` makes them).
- Download fetches only an engine's data files from https://engines.zei.st/<id>/<file>, each checked against the sha256 in the app's manifest. Program files are served to the web view only from the app. Engines with no data file (Ethereal, Fairy-Stockfish, Stockfish Lite, Zeist) are built in.
- A git-ignored local config, or `-packs` in tests, may point development builds at `ios/scripts/serve-packs.sh`, which also serves only data files.
- Packs downloaded whole by earlier builds are kept when their data files are the ones the app's manifest names; their program files are then taken from the app. Anything else in the engines folder is removed. Games and settings are untouched.

So the app's engine versions change only with an app update. A data file published at https://engines.zei.st must never be replaced under the same address with different content while an app version that expects the old one is in use: that app would refuse it, and the engine could not be downloaded. When engines are next updated, data file addresses should carry a version or hash (for example `<id>/<version>/<file>` or the hash in the file name).

Two things the web depends on (2026-11-14):

- `catalog.json` stays at the bucket's root with `engines: [{id, name, ...}]`. The web pages, served under zeist.gg/chess/vs/, read it from engines.zei.st (or through their own Worker); Chess in Zeist reads the shorter list `/chess/vs/engines.json`, written from it when the web is built.
- An engine id is also a web address (`/chess/vs/<id>/`). These words are never used as an id: `js`, `core`, `fonts`, `pieces`, `z`, `engines`, `index`, `api`, `welcome`, `zeist`.

A pack passes when, in Node and in WebKit: `uci` answers `uciok`; `isready` answers `readyok`; `position startpos moves e2e4` then `go nodes 20000` answers a legal `bestmove`; the same search twice gives the same move.

## Levels

Every engine gets levels 1 to 10 from the host, whatever it supports: its own strength option where it has one, otherwise a node budget plus a seeded choice among its top moves (MultiPV). Adaptive play starts low for a first game and moves by a step: up after a win, down after a loss, the same level after a draw. The step starts at three levels (FIRST_STEP) and shrinks by one after every loss or draw, down to one level, so the first games take big strides and later ones small (`adapt` in `core/levels.js`). Levels are unrated until measured.
