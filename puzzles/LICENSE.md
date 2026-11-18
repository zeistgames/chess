# Chess puzzle data: source, license and selection

The puzzles at zei.st/chess/puzzles are a selection from the Lichess puzzle database.

## Source

- File: `lichess_db_puzzle.csv.zst`, from https://database.lichess.org/ (section "Puzzles"), 309,751,173 bytes,
  SHA-256 `7b0d235fa40cfd7fdb7df1fec56a96b3b6ee1496b32ed2eb05be90d0ebf94253`. The page said "This file was last updated on
  2026-11-11"; the server's Last-Modified header read Sun, 01 Nov 2026 07:57:40 GMT.
- Downloaded 2026-11-14 (19:43 UTC) to a folder outside this repository. 6,193,530 puzzles.

## License

CC0. The statement at the top of https://database.lichess.org/, checked 2026-11-14, word for word:

> Database exports are released under the Creative Commons CC0 license.
> Use them for research, commercial purpose, publication, anything you like. You can download, modify and redistribute
> them, without asking for permission.

"Creative Commons CC0 license" links to https://tldrlegal.com/license/creative-commons-cc0-1.0-universal. No
attribution is required. Only the data is used: no Lichess code, and nothing from chess.js or any other chess library.
Every puzzle is checked with Zeist's own rules (`public/s/chess/rules.js`).

## How the data reads the puzzles

From the same page: the FEN is the position before the opponent's move; the position shown to the player comes after
the first move of the line, and the second move begins the solution. Every move of the solver's is the only good one,
except in mates, where any move that mates wins. Zeist plays them that way (`public/s/chess/puzzle.js`).

## Selection

Rebuilt by `node games/scripts/build_puzzles.mjs <path to lichess_db_puzzle.csv.zst>`; the same file always gives the
same output. The rules, in that script:

1. Quality: Popularity at least 92 (90 in band 1), rating deviation at most 77, at least 2,000 plays (1,000 from band 6
   up).
2. Short and clean: at most three moves of the solver's, nothing tagged `veryLong` or `equality`.
3. Eight bands by the Lichess puzzle rating, up to 900 puzzles each.
4. In each band, a weighted draw without replacement (Efraimidis and Spirakis) that favors mates in one and two
   (weight 4), one-move tactics (3), mates in three and two-move tactics (2) over three-move tactics (1), with each
   puzzle's random number from a SHA-256 hash of its id.
5. Each drawn puzzle is checked with Zeist's rules: the position parses, every move is legal, the line ends on the
   solver's move, nothing ends the game before the last move, a mate in N has N moves of the solver's and ends in mate
   by the solver, and no line ends in a draw. A puzzle that fails is dropped and the draw goes on.

| Band | Lichess rating | Eligible | Kept | Dropped | Mate in 1 | Mate in 2 | Mate in 3 | Other tactics |
|---|---|---|---|---|---|---|---|---|
| 1 | up to 899 | 695 | 695 | 0 | 126 | 253 | 34 | 282 |
| 2 | 900 to 1099 | 16,829 | 900 | 0 | 171 | 369 | 38 | 322 |
| 3 | 1100 to 1299 | 96,029 | 900 | 0 | 156 | 303 | 44 | 397 |
| 4 | 1300 to 1499 | 146,361 | 900 | 0 | 77 | 276 | 36 | 511 |
| 5 | 1500 to 1699 | 153,726 | 900 | 0 | 22 | 192 | 50 | 636 |
| 6 | 1700 to 1899 | 138,470 | 900 | 0 | 15 | 141 | 53 | 691 |
| 7 | 1900 to 2099 | 88,806 | 900 | 0 | 7 | 116 | 53 | 724 |
| 8 | 2100 to 2399 | 37,945 | 900 | 0 | 0 | 73 | 54 | 773 |

6,995 puzzles, none dropped. Checked further with `--check-all` on 2026-11-14: all 678,861 eligible puzzles in the file
pass the same checks.

## Files

`index.json` lists the bands and their files; each file holds up to 100 puzzles of one band as
`{ band, puzzles: [[id, fen, moves, mate]] }` (moves in UCI text, mate N or 0), named by a hash of its contents.
70 files of 8,754 to 9,618 bytes and an index of 1,879 bytes: 651,522 bytes in all (Cloudflare allows 20,000 files
per Worker version on Free and 100,000 on Paid, and 25 MiB per file). A phone starts with the index and one file. The
page keeps files it has fetched in its own cache, so they play offline; the service worker does not fetch them ahead.
`lookup.json` (43,543 bytes) maps each file to the ids it holds, so the server can check a solve by reading one file;
the page never fetches it.

Two more files are read from the set by the same script and change nothing in it. Like the band files, the service
worker does not fetch them ahead.

`themes.json` (62,227 bytes): `{ set, groups: [{ id, name, themes, count, bands: { "1": "id id ..." } }] }`. The
grouping of Lichess tags is data, in `games/scripts/puzzle_themes.json`; a puzzle with any of a group's tags is in it,
and may be in several groups. Ids are listed per band in the order the band's files hold them. A group with fewer than
40 puzzles in the whole set is left out, and a tag in the grouping that the source file never has stops the build.

| Group | Lichess tags | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | All |
|---|---|---|---|---|---|---|---|---|---|---|
| Forks | fork | 162 | 138 | 130 | 108 | 105 | 111 | 71 | 58 | 883 |
| Pins | pin | 11 | 45 | 62 | 87 | 82 | 76 | 78 | 85 | 526 |
| Skewers | skewer | 22 | 19 | 18 | 16 | 15 | 11 | 10 | 17 | 128 |
| Discovered attacks | discoveredAttack, doubleCheck, discoveredCheck | 32 | 59 | 71 | 69 | 69 | 73 | 75 | 65 | 513 |
| Pieces left hanging | hangingPiece | 57 | 31 | 26 | 22 | 30 | 16 | 19 | 24 | 225 |
| Trapped pieces | trappedPiece | 1 | 1 | 5 | 18 | 16 | 23 | 20 | 13 | 97 |
| Removing the defender | capturingDefender, deflection, attraction | 19 | 64 | 88 | 111 | 110 | 103 | 80 | 77 | 652 |
| Sacrifices | sacrifice | 20 | 45 | 58 | 88 | 104 | 108 | 113 | 123 | 659 |
| Mate in one | mateIn1 | 126 | 171 | 156 | 77 | 22 | 15 | 7 | 0 | 574 |
| Mate in two | mateIn2 | 253 | 369 | 303 | 276 | 192 | 141 | 116 | 73 | 1,723 |
| Mate in three | mateIn3 | 34 | 38 | 44 | 36 | 50 | 53 | 53 | 54 | 362 |
| Back-rank mate | backRankMate | 59 | 37 | 11 | 7 | 3 | 4 | 3 | 0 | 124 |
| Passed pawns | advancedPawn, promotion | 20 | 26 | 36 | 56 | 41 | 52 | 51 | 65 | 347 |
| Endgames | endgame and the six kinds of endgame | 391 | 418 | 416 | 390 | 379 | 385 | 386 | 454 | 3,219 |

`daily.json` (67,955 bytes): `{ start, puzzles: [[id, fen, moves, mate, band]] }`, 730 rows from 2026-11-16, the
day's puzzle at `day % length`. The rules, in the script:

1. Drawn from the set's puzzles in bands 2 to 4 by the same weighted draw as the set, each puzzle's random number from
   a SHA-256 hash of its id with a salt of its own (`zeist-daily:`).
2. In that order, each day takes the first puzzle not yet listed that makes no more than two days in a row from one
   band, and no more than two in a row that are mates of the same length.
3. Append-only: a rebuild keeps every row already in `daily.json` and only adds to the end. The ids on the list are
   pinned: a rebuild stops if one is no longer in the set or its row changed, so any later selection must keep them.

The 730 rows: 278 from band 2, 242 from band 3, 210 from band 4; 137 mates in one, 364 in two, 20 in three, and 209
other tactics.
