# Lessons: the format

How a lesson in Learn is written, stored and checked. The curriculum itself is in `LEARN.md`. Lessons are data, shared by the iPhone app and the web: no lesson has code of its own.

## Where they live

- `core/lessons/index.json`: the courses, their chapters and the lessons that exist, in order.
- `core/lessons/<course>/<id>.json`: one lesson.
- `core/lessons/check.mjs`: checks every lesson (below). Nothing ships unless it passes.

Only lessons that exist are listed. Nothing is ever shown as locked or coming.

## index.json

```json
{
  "version": 1,
  "courses": [
    {
      "id": "basics",
      "title": "Basics",
      "line": "The board, the moves, check and checkmate.",
      "chapters": [
        {
          "id": "the-board",
          "title": "The board",
          "lessons": [
            { "id": "basics-board", "title": "The board and the pieces", "line": "Where each piece starts.", "fen": "<position for its small board>", "marks": { "squares": ["h1"] }, "side": "w" }
          ]
        }
      ]
    }
  ]
}
```

- Course ids: `basics`, `openings`, `tactics`, `checkmates`, `endgames`, `strategy`.
- An opening is a chapter of `openings`. Its chapter carries extra fields:
  - `for`: "white" or "black", the side that chooses this opening (the Italian Game is White's choice, the Sicilian Defense is Black's). The Openings page is sorted by it: openings to play as White, openings to play as Black.
  - `group`: the plain heading it is listed under on that side, in words, not notation: "With the king's pawn", "With the queen's pawn", "Other first moves" for White; "Against the king's pawn", "Against the queen's pawn", "Against other first moves" for Black.
  - `line`: one plain sentence saying what the opening is about, with no notation in it ("The bishop takes aim at Black's weakest square and White gets ready to open the center.").
  - `play`: the moves that reach the opening, in UCI, from the usual start. The app plays them on the board one at a time when the opening's page opens, and the player can step back and forth through them.
  - `moves`: the same moves in plain notation ("1.e4 e5 2.Nf3 Nc6 3.Bc4"). Shown small, for those who read it; nothing depends on it.
  - `fen`: the position after `play`.
- A lesson's `fen`, `marks` and `side` draw its small board in a list. `title` and `line` must equal the lesson file's.

## A lesson

```json
{
  "id": "tactics-fork",
  "course": "tactics",
  "title": "The fork",
  "line": "One piece attacks two at once. The knight does it best.",
  "side": "w",
  "steps": [],
  "summary": "A fork attacks two pieces at once, and only one can be saved.",
  "practice": { "fen": "<position>", "side": "w" },
  "puzzles": "forks"
}
```

- `id`: lowercase letters, digits and hyphens, starting with the course id. The file is `<id>.json` in the course's folder.
- `side`: whose side is at the bottom of the board, "w" or "b". A step may override it.
- `steps`: 3 to 10 of them.
- `summary`: one line shown at the end, 120 characters at most.
- `puzzles`: optional. The id of the puzzle theme that practices this lesson's idea (`forks`, `pins`, `mate2` and the others in `puzzles/themes.json`). The end of the lesson then offers puzzles from that theme. Set it only where a theme is truly about the lesson's idea.
- `practice`: optional. The position to play on against an engine, and the side the player takes. It must be a legal position with the game still going, and it is the position the end of the lesson shows on its board, so choose the one the lesson leads to. Leave it out where playing on teaches nothing (a lesson about how a knight moves).

## Steps

Every step has `type` and `text`. `text` is what the player reads above the board: 140 characters at most, one or two short sentences.

A step's position is its `fen` if it has one. Without `fen`, it continues from the step before: the position after that step's move and reply. The first step must have `fen`.

Optional on any step: `marks` and `side`.

```json
"marks": { "squares": ["f7"], "arrows": [["c4", "f7"]] }
```

`squares` are ringed, `arrows` are drawn from the first square to the second. Marks stay for as long as the step is open, through wrong tries too, and go when the lesson moves on.

### show

Something to read and look at. The player taps Next.

```json
{ "type": "show", "fen": "...", "text": "The bishop on c4 looks at f7, guarded only by the king.", "marks": { "squares": ["f7"], "arrows": [["c4", "f7"]] } }
```

A `show` step may carry `play`: a list of moves in UCI ("e2e4") played on the board one after another when the step opens, to show a line. The next step without `fen` continues from the position after them.

### move

The player makes a move.

```json
{
  "type": "move",
  "text": "Fork the king and the rook with the knight.",
  "accept": ["d5c7"],
  "wrong": { "d5f6": "That is check, but the pawn on g7 takes the knight." },
  "hint": "Look for a square that attacks e8 and a8 at once.",
  "after": "Check, and the rook on a8 is attacked too.",
  "reply": "e8d8",
  "wins": 5
}
```

- `accept`: one or more moves in UCI. Any of them is right. A promotion carries its piece ("e7e8q").
- `wrong`: optional. A line for particular wrong moves. Any other wrong move gets the app's own neutral line ("Not the move this lesson is after."). A line here must be true of that move: say what it loses or misses. Never praise a move that loses something, and never put a `wrong` line on a move that is about as good as the accepted one: that is what `also` is for.
- `also`: optional. A line for particular moves that are good but are not the one this lesson follows ("That stops it too. This lesson goes on with g6."). The move goes back and the player tries again, as with a wrong move, but the line says plainly that it works.
- `taught`: optional, true. The accepted move is one good choice among several, played to show an idea (an opening's main line). The engine check then only requires that it is not a mistake.
- `sacrifice`: optional, true. The accepted move gives material up on purpose (a bishop takes a guarded pawn with check to open the king). Without it the checker faults any accepted move that loses material. With it, the engine check must rate the move within half a pawn of the best and the player more than a pawn and a half ahead after it, so only sacrifices that truly work can be taught.
- `hint`: optional. Shown on the first tap of Hint. The second tap shows the move itself (the first in `accept`).
- `after`: optional. One line shown once the move is played.
- `reply`: optional. The opponent's answer in UCI, played after a short pause. If `accept` has more than one move, `reply` may be an object from each accepted move to its reply.
- `wins`: a claim, checked: after the move, against every possible answer, the player comes out ahead by at least this many points of material (pawn 1, knight 3, bishop 3, rook 5, queen 9) once the captures that follow have been played out. Required on every step whose words say something is won. With the engine check on, Stockfish must agree the player is ahead.
- `mate`: true, required whenever the accepted move is checkmate; checked.

The move is always made by the side at the bottom of the board. If the accepted moves lead to different positions, the next step has its own `fen`.

When the player makes the right move, the reply is played and the lesson goes on to the next step by itself after a short pause; the `after` line stays under the board until the player's next move. Back and Next are always there to step either way. Next is never locked: on a `move` step the player has not solved, Next plays the first accepted move for them.

### pick

The player taps squares instead of moving: "Tap every square this knight can reach", "Which piece is undefended?".

```json
{ "type": "pick", "fen": "...", "text": "Tap the piece that is not defended.", "accept": ["c5"], "all": false, "wrong": { "e5": "The pawn on d6 defends it." }, "after": "Nothing guards the bishop on c5." }
```

- `accept`: the right squares. Every square that fits the words must be in it: if the text asks for "the piece on a light square", every such piece is accepted.
- `all`: optional. False (the default) means any one of them finishes the step. True means the player must find every one (each right tap stays lit).
- `hint`: optional, as on a move step. The second tap of Hint lights the answers.

## What the checker checks

`node core/lessons/check.mjs` reads the index and every lesson and stops on the first lesson with a fault, naming it.

- Shape: every field above, nothing unknown, lengths within limits, ids and files agree, the index and the lesson agree on title and line, no lesson listed twice or missing.
- Chess, with `core/rules.js`: every `fen` is a legal position (one king each, the side not to move is not in check, no pawns on the first or last rank). Every move in `accept`, `wrong`, `reply` and `play` is legal where it is played. No move is in both `accept` and `wrong`. Continuity holds through steps without `fen`. Marks name real squares; an arrow's squares differ. `pick` squares are on the board, and a `pick` that asks for a piece names occupied squares.
- Claims: `mate` is checkmate. `wins` holds against every answer. An opening's `fen` is the position after its `moves`, and its name matches the opening table in `core/vendor`: the table's whole name, its beginning, or one of its parts ("London System" for the table's "Queen's Pawn Game: London System").
- Words: plain American English, no dashes used as punctuation (em-dash, en-dash, a spaced hyphen or a double hyphen), never "new", no exclamation marks, no emoji, no praise ("good", "great", "nice", "well done", "correct", "right" as a verdict; a plain "Yes." is allowed), every sentence ending with a period or a question mark. `hint`, `after`, `wrong` and `also` lines are 140 characters at most.
- Engine check, `node core/lessons/check.mjs --engine`: for every `move` step in every course, Basics included, Stockfish (from `engines/dist`) is asked about the position. An accepted move must be within half a pawn of its best move; with `"taught": true` it must be within a pawn and a half. An accepted move that leaves the player five pawns or more ahead passes even when a bigger win exists. An accepted move never loses material: a lesson about how a piece captures must capture something that is safe to take. A move in `also` must be within half a pawn of the best. A move in `wrong` must be more than half a pawn worse than the best. In Basics, where a beginner may find any sound move, every legal move within half a pawn of the accepted one must be accepted or carry an `also` or `wrong` line, unless the step's words name the move. `practice` must be a position the lesson reaches. A lesson is not finished until it passes this check.

## Writing rules

- One idea per lesson. A lesson takes two to four minutes.
- Start from something the player can see: a position, a ring, an arrow. Then ask for a move.
- Every position is a legal one that could come from a game. Prefer positions from real openings and plain endings over composed curiosities.
- Say what a piece does, not what the player should feel. No praise beyond a plain "Yes." or the `after` line.
- Notation in text is plain: "Nf3", "the knight on f3", "f7". Name squares in lowercase.
- A lesson for a beginner uses no term it has not explained, in that lesson or one before it in the course.
- Nothing depends on reading notation. Many players never learn it and remember chess by sight. Text names pieces in words ("the knight", "your bishop") and every square or move it mentions is also shown on the board with a ring or an arrow. A move is never given only as "Nf3": write "bring the knight out" and draw the arrow. Square names may appear beside a mark, never instead of one. This holds for every line a step can show (`text`, `hint`, `after`, `wrong`, `also`) and for `summary`, which has no board marks and so names no squares at all. The one lesson about notation is the exception.
- An opening's first lesson begins from the usual starting position. The player makes each of the opening's moves in turn, with an arrow showing the move and one line saying why, and the other side's moves are played for them. Only then does the lesson go on to ideas and mistakes.
