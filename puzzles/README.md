# Puzzles

The chess puzzles Zeist Chess plays, a copy of the set Zeist shows at zei.st/chess/puzzles, so both show the same puzzles.

- **Source:** the [Lichess puzzle database](https://database.lichess.org/#puzzles), released under CC0 (public domain dedication).
- **Selection:** made in Zeist's own repository, by `games/scripts/build_puzzles.mjs` there. Fixes to the selection or the data go there, never here.
- **Record:** `LICENSE.md`, copied from Zeist, states the source file, its license and how the puzzles were chosen.
- **Copy:** `scripts/copy-puzzles.sh` copies the built files here, one way. Nothing in this folder is edited by hand except this README.

## Format

`index.json` lists eight bands of difficulty by Lichess puzzle rating, each with its files. Each file holds one band's puzzles, a hundred at most, as rows of `[id, fen, moves, mate]`:

- `id`: the Lichess puzzle id.
- `fen`: the position before the opponent's move, which is played on the board first.
- `moves`: the line in UCI, separated by spaces. The opponent's move comes first, then the solver's and the opponent's in turn, ending on the solver's.
- `mate`: N for a mate in N (1 to 3), else 0. Any move that mates counts as correct.

The app reads this format in one place, `ios/ZeistChess/Puzzles/PuzzleData.swift`.

`themes.json` sorts the same puzzles by idea: `{ set, groups: [{ id, name, themes, count, bands }] }`, where `themes` are the Lichess labels a group gathers and `bands` gives, for each difficulty band, the ids of its puzzles in that group. A puzzle may be in several groups.

`daily.json` is the daily puzzle: `{ start, puzzles }`, a fixed list of puzzle rows with the band added. The puzzle for a day is `puzzles[day % length]`, where `day` is the number of whole days from `start` to the player's own date. The list only ever grows at the end, so a past day's puzzle never changes, and no server is asked.
