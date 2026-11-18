# Learn

The plan for the Learn tab in Zeist Chess: interactive lessons on a real board, from the first move to openings, tactics, endgames and strategy. Nothing is locked: every lesson is open to everyone from the start, with no streaks, timers or lives. Finished lessons are marked as finished.

The full curriculum is 258 lessons in six courses: Basics 19, Openings 137, Tactics 27, Checkmates 23, Endgames 29 and Strategy 23. All of it is written, in `core/lessons/`.

## How a lesson works

- A lesson is a few steps on a real board. Each step is a short explanation with highlighted squares and arrows, then you make the move yourself.
- A wrong move gets a plain line saying why, and another try. Hint shows the piece, then the move.
- A lesson ends with what it taught in one line, then Practice against an engine from that exact position at your level, and the next lesson.
- Opening lines you got wrong come back later in that opening's page, for another try. Nothing is sent as a reminder.

## Learn as you play

Beside the library, Learn can start an ordinary unrated game against your engine. When an opening is reached or a pattern happens on the board, a quiet card under the board names it and links to its lesson. A card names what has happened, never what to play next. About the player's own move it may appear right after that move; about something the opponent did, only once it has played out, after the player has replied and material has changed hands, or at the end of the game, never while the player still has a decision to make about it. Each card appears once per thing per game, and the board itself carries no marks. The cards show only in games started from Learn, never in games started from Play.

They name only what code can tell from the moves alone: openings by name, and after a move a fork, a pin, a skewer, a discovered attack, a discovered check, a double check, a hanging piece taken, back-rank mate, smothered mate, en passant, castling, promotion and stalemate. A pattern is named only when it won material or gave mate, which code can check from what happened next.

## First release: 20 lessons

Seven basics make a full legal game; five opening lessons give the opening rules, the Italian Game for 1.e4 e5 from both sides, the Queen's Gambit for 1.d4, and the Sicilian and King's Indian as defenses to 1.e4 and 1.d4; five tactics start with not leaving pieces hanging; three mates finish the games they win.

1. **The board and the pieces** (Basics): Where each piece starts, a light square in the right corner, the queen on her own color.
2. **How the pieces move: an overview** (Basics): All six pieces at a glance on one board. The lessons after it take each piece up close.
3. **Promotion and en passant** (Basics): A pawn on the last rank becomes a queen or another piece; the one capture that lands behind a pawn.
4. **Castling** (Basics): King and rook in one move, on either side.
5. **What the pieces are worth** (Basics): Pawn 1, knight 3, bishop 3, rook 5, queen 9, and why the king has no number.
6. **Check** (Basics): The king is attacked. Three ways out: move it, block, or capture the attacker.
7. **Checkmate and stalemate** (Basics): Check with no way out wins. No legal move and no check is a draw.
8. **Three rules for the opening** (Openings): Take the center, bring out the knights and bishops, castle.
9. **Italian Game: the ideas** (Openings): 1.e4 e5 2.Nf3 Nc6 3.Bc4. The bishop aims at f7 and White prepares d4.
10. **Sicilian Defense: the ideas** (Openings): 1.e4 c5. Black fights for d4 from the side, for an unbalanced game.
11. **Queen's Gambit: the ideas** (Openings): 1.d4 d5 2.c4. White offers the c-pawn to pull Black's pawn from the center.
12. **King's Indian Defense: the ideas** (Openings): 1.d4 Nf6 2.c4 g6 3.Nc3 Bg7 4.e4 d6. Black lets White build a big center, then strikes at it.
13. **Pieces left hanging** (Tactics): Before every move: checks, captures, threats, and is anything of yours or theirs undefended.
14. **The fork** (Tactics): One piece attacks two at once. The knight does it best.
15. **The pin** (Tactics): A piece cannot move without exposing a bigger one behind it.
16. **The skewer** (Tactics): A pin turned around: the bigger piece in front must move and the one behind falls.
17. **Discovered attack** (Tactics): Move one piece and uncover an attack by another.
18. **Scholar's mate and how to stop it** (Checkmates): Queen and bishop on f7 in four moves, and the moves that make it harmless.
19. **Back-rank mate** (Checkmates): A rook or queen on the last rank, the king boxed in by its own pawns.
20. **King and queen against king** (Checkmates): Push the king to the edge with the queen, then bring your king. Mind stalemate.

In the lists below, lessons in the first release are marked **(first release)**.

All six courses are written; the 20 above were the first.

## Basics (19 lessons)

The board, the moves, check and checkmate.

### The board

- **The board and the pieces** (first release): Where each piece starts, a light square in the right corner, the queen on her own color.
- **Naming the squares**: Files a to h, ranks 1 to 8: every square has a name, from a1 to h8.
- **Reading moves**: How a move is written: e4, Nf3, Bxc6, O-O, and what + and # mean.

### How the pieces move

- **How the pieces move: an overview** (first release): All six pieces at a glance on one board. The lessons after it take each piece up close.
- **The rook and the bishop**: Straight lines and diagonals, and what stops them.
- **The queen**: A rook and a bishop in one piece.
- **The knight**: The only piece that jumps. Reach any square in the fewest moves.
- **The king**: One square at a time, and never onto an attacked square.
- **The pawn**: Forward one, two on its first move, and it captures diagonally.

### Special moves

- **Promotion and en passant** (first release): A pawn on the last rank becomes a queen or another piece; the one capture that lands behind a pawn.
- **Castling** (first release): King and rook in one move, on either side.
- **When you cannot castle**: After the king or that rook has moved, out of check, through check or into check.

### Winning material

- **What the pieces are worth** (first release): Pawn 1, knight 3, bishop 3, rook 5, queen 9, and why the king has no number.
- **Good and bad trades**: When giving a piece for a piece leaves you ahead.
- **Attackers and defenders**: Count them before you capture.

### How a game ends

- **Check** (first release): The king is attacked. Three ways out: move it, block, or capture the attacker.
- **Checkmate and stalemate** (first release): Check with no way out wins. No legal move and no check is a draw.
- **Draws and resigning**: Repetition, too little material to mate, the fifty-move rule and agreement; giving up a lost game; and why running out of time is a loss unless the other side cannot mate.

### Your first games

- **Before every move**: What the other side's last move attacks, and the three answers: move it, guard it, or capture the attacker.

Merged and dropped when the lessons were written: Resigning and the part of Playing with a clock that can be shown on a board (time running out) are in Draws and resigning; time controls and increments are app settings, not board lessons. Your first game against an engine is dropped, because every lesson's Practice already plays on against the engine. Reading a game back is dropped, because it teaches the Games screen rather than chess.

## Openings (137 lessons)

36 openings and defenses, by first move.

### Before any opening

- **Three rules for the opening** (first release): Take the center, bring out the knights and bishops, castle.
- **Moving a piece twice**: Why it costs time, and when it is worth it.
- **The queen out early**: Why she gets chased, and how each attack on her brings a piece out.
- **Gambits**: What a pawn buys: time, open lines, the center. Played through the Danish Gambit.
- **Transpositions**: The same position reached by different move orders.
- **Learning a line**: Ideas first, then moves; why memorized moves alone fall apart.

Dropped when the lessons were written: Choosing your openings, which is advice about a repertoire rather than something a board can show; the Openings page, sorted by the side that chooses each opening, does that job.

### How each opening is taught

Every opening and defense below has the same lessons:

1. **The ideas**: What each side wants, shown on the board before any memorizing.
2. **The main line**: The opening's first moves, played by you for your side, with the reason for each.
3. **One lesson per variation**: Each listed below, from the point where it leaves the main line.
4. **Traps**: Where listed: all of an opening's traps in one lesson, each played through, and how not to fall into them.

Lesson counts below include these: two, plus one per variation, plus one for traps when an opening has any. Names and ECO codes follow the Lichess chess-openings table (CC0-1.0), which Zeist Chess already uses. Where the table's name is long, a variation is listed by the part that tells it apart (Sveshnikov Variation for the table's Lasker-Pelikan Variation, Sveshnikov Variation; Rossolimo Attack for Nyezhmetdinov-Rossolimo Attack), and one goes by its common name: the Mar del Plata Variation, which the table calls the Aronin-Taimanov Defense.

### 1.e4 e5

Open games: both sides take the center with the king's pawn.

#### Italian Game

C50, for White, 7 lessons. 1.e4 e5 2.Nf3 Nc6 3.Bc4. The bishop aims at f7 and White prepares d4. The ideas lesson is in the first release.

- Classical Variation, Center Attack (3...Bc5 4.c3 Nf6 5.d4 exd4 6.cxd4): the main line: two pawns side by side in the center, and Black's answer in the center.
- Giuoco Pianissimo (3...Bc5 4.d3): d3 and a slow build-up, the modern main line.
- Evans Gambit (3...Bc5 4.b4): A pawn for time and the center, and the knight sacrifice on f7 when Black is careless.
- Two Knights Defense (3...Nf6 4.Ng5 d5 5.exd5 Na5): Black counterattacks e4, then gives a pawn and chases the bishop (the Polerio Defense).
- Fried Liver Attack (3...Nf6 4.Ng5 d5 5.exd5 Nxd5 6.Nxf7): The knight sacrifice on f7 and the king walk that follows.
- Trap: The Blackburne Shilling Gambit (3...Nd4 4.Nxe5 Qg5 5.Nxf7 Qxg2 6.Rf1 Qxe4+ 7.Be2 Nf3#): Taking the e5 pawn walks into mate. The table calls 3...Nd4 the Blackburne-Kostić Gambit.

Merged: the main line is the Center Attack, so they are one lesson; the Polerio Defense is the main line of the Two Knights Defense, so they are one lesson.

#### Ruy Lopez

C60, for White, 7 lessons. 1.e4 e5 2.Nf3 Nc6 3.Bb5. Pressure on the knight that defends e5, for a long time.

- Closed (3...a6 4.Ba4 Nf6 5.O-O Be7 6.Re1 b5 7.Bb3 d6 8.c3 O-O 9.h3 Na5 10.Bc2 c5 11.d4): The main line: slow maneuvering on both wings.
- Exchange Variation (3...a6 4.Bxc6): White gives the bishop for a better pawn structure.
- Berlin Defense (3...Nf6): Solid, often heading for an early queen trade.
- Open (3...a6 4.Ba4 Nf6 5.O-O Nxe4): Black takes the pawn and plays actively.
- Marshall Attack (3...a6 4.Ba4 Nf6 5.O-O Be7 6.Re1 b5 7.Bb3 O-O 8.c3 d5): Black gives a pawn to attack the white king.
- Trap: Noah's Ark Trap (3...a6 4.Ba4 d6 5.d4 b5 6.Bb3 Nxd4 7.Nxd4 exd4 8.Qxd4 c5 9.Qd5 Be6 10.Qc6+ Bd7 11.Qd5 c4): Black's pawns trap the bishop on b3.

Merged: the main line is the Closed Ruy Lopez, so they are one lesson. The ideas lesson shows the pressure on e5 with the Tarrasch Trap.

#### Scotch Game

C45, for White, 4 lessons. 1.e4 e5 2.Nf3 Nc6 3.d4 exd4 4.Nxd4. White opens the center at once.

- Classical Variation (4...Bc5): The bishop hits the knight on d4.
- Mieses Variation (4...Nf6 5.Nxc6 bxc6 6.e5): Black attacks e4; White trades and pushes e5.
- Scotch Gambit (1.e4 e5 2.Nf3 Nc6 3.d4 exd4 4.Bc4): Development before taking the pawn back.

Merged: the main line is four moves long, so it is in the ideas lesson; the Schmidt Variation (4...Nf6) leads straight into the Mieses, so they are one lesson.

#### Four Knights Game

C47, for White, 4 lessons. 1.e4 e5 2.Nf3 Nc6 3.Nc3 Nf6. All four knights out, symmetrical and sound.

- Spanish Variation (4.Bb5): The bishop pins the knight, as in the Ruy Lopez, and Black answers with the knight jump to d4.
- Scotch Variation (4.d4): The center opened with all knights out.
- Meeting the Halloween Gambit (4.Nxe5): A knight for the center and a chase. Engines rate it unsound and masters almost never play it, so this one lesson is seen from Black's side, and says so in its title.

Merged: the main line is the opening's four moves, so it is in the ideas lesson, which also shows why copying the other side goes wrong.

#### Petrov's Defense

C42, for Black, 4 lessons. 1.e4 e5 2.Nf3 Nf6. Black counterattacks e4 instead of defending e5.

- Three Knights Game (3.Nc3): White defends e4 and develops; Black pins the knight and wins the pawn back.
- Modern Attack (3.d4): White opens the center at once.
- Trap: The Damiano Variation (3.Nxe5 Nxe4 4.Qe2 Nf6 5.Nc6+): Taking back on e4 too soon lets the queen out; one more slip loses Black's queen to a discovered check, and the right answer (4...Qe7) still leaves White a small edge.

Merged: the main line is the Classical Attack (3.Nxe5 d6 4.Nf3 Nxe4 5.d4 d5 6.Bd3), and it is the ideas lesson.

#### Philidor Defense

C41, for Black, 3 lessons. 1.e4 e5 2.Nf3 d6. A solid pawn on d6 holds e5.

- Hanham Variation (3.d4 Nd7): Black keeps the pawn on e5, and must guard d5 against the queen.
- Trap: Légal's mate (3.Bc4 Bg4 4.Nc3 Nc6 5.Nxe5 Bxd1 6.Bxf7+ Ke7 7.Nd5#): White gives the queen and mates with three minor pieces. Played with 4...Nc6, the version club players meet; taking the knight (5...Nxe5) wins a piece instead.

Merged: the ideas lesson plays the main line, which is the Exchange Variation (3.d4 exd4).

#### King's Gambit

C30, for White, 4 lessons. 1.e4 e5 2.f4. A pawn for the f-file and a fast attack.

- King's Gambit Accepted (2...exf4 3.Nf3 g5 4.h4 g4 5.Ne5): Black takes and tries to keep the pawn; White breaks up the pawns.
- King's Gambit Declined: Classical Variation (2...Bc5): The bishop stops White from castling short.
- Falkbeer Countergambit (2...d5): Black answers with a gambit of its own.

Merged: the ideas lesson plays the main line (2...exf4 3.Nf3 d5 4.exd5 Nf6 5.Bc4 Nxd5 6.O-O Be7 7.d4 O-O 8.Bxd5 Qxd5 9.Bxf4).

#### Vienna Game

C25, for White, 3 lessons. 1.e4 e5 2.Nc3. The knight first, with f4 in mind.

- Vienna Gambit (2...Nf6 3.f4 d5): The King's Gambit idea with a knight already out.
- Max Lange Defense (2...Nc6 3.Bc4 Nf6 4.d3, and 3...Bc5 4.Qg4): Black develops the other knight first; the bishop aims at f7 and the pawn on f2 waits to push.

Merged: the main line is short, so it is in the ideas lesson, which plays 2...Nf6 3.f4 exf4 4.e5, the reply club players choose most; the Vienna Gambit lesson plays the masters' 3...d5.

#### Bishop's Opening

C23, for White, 1 lesson. 1.e4 e5 2.Bc4. The bishop out first, keeping the f-pawn free.

Merged: the ideas lesson, the main line and the Berlin Defense (2...Nf6) are one lesson, since the Berlin is Black's main answer and the main line follows it.

### 1.e4, other replies

Semi-open games: Black answers 1.e4 with something other than 1...e5. Every lesson here is played from Black's side, including the variations White chooses (the Alapin, the Grand Prix, the Advance): they teach how Black meets them. An opening's ideas lesson also plays its main line, so the two are one lesson.

#### Sicilian Defense

B20, for Black, 14 lessons. 1.e4 c5. Black fights for d4 from the side, for an unbalanced game. The ideas lesson is in the first release and plays the main line up to 5...a6.

- Najdorf Variation (2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 a6 6.Be3 e5 7.Nb3 Be6 8.f3 Be7 9.Qd2 O-O 10.O-O-O Nbd7 11.g4 b5): ...a6, then ...e5 kicks the knight, the bishop on e6 guards d5, and the pawn race on opposite wings.
- Dragon Variation (5...g6 6.Be3 Bg7 7.f3 O-O 8.Qd2 Nc6 9.O-O-O d5 10.exd5 Nxd5 11.Nxc6 bxc6): The bishop on the long diagonal, the ...d5 break, and the b-file toward White's king.
- Classical Variation (5...Nc6 6.Bc4 Qb6 7.Nb3 e6 8.O-O Be7 9.Be3 Qc7 10.f4 a6): Both knights out, the queen chases the knight from d4, and pawns go forward on the queen's side.
- Scheveningen Variation (5...e6 6.g4 h6): A small center on d6 and e6, and ...d5 against the Keres Attack.
- Sveshnikov Variation (2.Nf3 Nc6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 e5 6.Ndb5 d6 7.Bg5 a6 8.Na3 b5): Black takes a hole on d5 for activity and the ...f5 break.
- Taimanov and Kan Variations (2.Nf3 e6 3.d4 cxd4 4.Nxd4 Nc6 or 4...a6): e6 and ...Qc7, flexible, and the knight and bishop to e5 and c5. One lesson: the Kan is the same plan with the knight later.
- Accelerated Dragon (2.Nf3 Nc6 3.d4 cxd4 4.Nxd4 g6): The fianchetto first, so ...d5 comes in one move.
- Alapin Variation (2.c3 d5): The pawn on c3 takes the knight's square, so the queen can take back on d5.
- Closed Variation (2.Nc3 Nc6 3.g3): White keeps the center closed; both bishops on the long diagonals and a knight on d4.
- Grand Prix Attack (2.Nc3 Nc6 3.f4): The bishop on c4 aims at f7; ...e6 blunts it and ...d5 hits it.
- Smith-Morra Gambit, with the Siberian Trap (2.d4 cxd4 3.c3 dxc3 4.Nxc3 Nc6 5.Nf3 e6 6.Bc4 Qc7 7.O-O Nf6 8.Qe2 Ng4 9.h3 Nd4): Black takes the pawns, develops, and a careless h3 (a fifth of club games here) meets the knight jump that wins the queen or mates. The trap is the gambit's ending, so the two are one lesson.
- Rossolimo Attack (2.Nf3 Nc6 3.Bb5 g6 4.Bxc6 dxc6): The bishop takes the knight; Black gets two bishops and open lines.
- Moscow Variation (2.Nf3 d6 3.Bb5+ Bd7): A check to trade bishops; Black builds a share of the center.

#### French Defense

C00, for Black, 7 lessons. 1.e4 e6 2.d4 d5. A solid pawn chain; Black hits White's center later.

- The ideas, with the main line: e6 and d5, the shut-in bishop on c8, and ...c5 against the chain's base.
- Advance Variation (3.e5 c5 4.c3 Nc6 5.Nf3 Qb6 6.Bd3 cxd4 7.cxd4 Bd7): Pressure on d4, and the trap 7...Nxd4? 8.Nxd4 Qxd4 9.Bb5+ that ...Bd7 avoids.
- Exchange Variation (3.exd5 exd5): Symmetrical and open; the bishop on c8 is free.
- Tarrasch Variation (3.Nd2 Nf6 4.e5 Nfd7): The knight to d2 avoids the pin; ...c5 and then ...f6 hit the chain at both ends.
- Winawer Variation (3.Nc3 Bb4 4.e5 c5 5.a3 Bxc3+ 6.bxc3): The pin and doubled pawns for White, then the queen on a5 hits them.
- Classical Variation (3.Nc3 Nf6 4.Bg5 Be7 5.e5 Nfd7): The knight hits e4, the bishop breaks the pin, ...c5.
- Rubinstein Variation (3.Nc3 dxe4 4.Nxe4 Nd7 5.Nf3 Ngf6): Black gives up the center for easy development and trades White's best knight.

#### Caro-Kann Defense

B12, for Black, 7 lessons. 1.e4 c6 2.d4 d5. Like the French, with the light-squared bishop free.

- The ideas, with the main line (3.Nc3 dxe4 4.Nxe4 Bf5): The bishop that the French shuts in comes out with a hit on the knight.
- Classical Variation (4...Bf5 5.Ng3 Bg6 6.h4 h6 7.Nf3 Nd7 8.h5 Bh7 9.Bd3 Bxd3): Keeping the bishop safe from the h-pawn, then trading it.
- Advance Variation (3.e5 Bf5 4.Nf3 e6 5.Be2 c5): The bishop comes out first, then ...c5 and ...Qb6 hit d4.
- Karpov Variation, with the smothered mate on d6 (4...Nd7 5.Nf3 Ngf6; the trap 5.Qe2 Ngf6?? 6.Nd6#): Knight to d7 first, then Ngf6, and the queen trap where ...Ndf6 keeps d7 free for the king. The trap is this variation's typical mistake, so the two are one lesson.
- Exchange Variation (3.exd5 cxd5 4.Bd3 Nc6 5.c3 Nf6 6.Bf4 Bg4): A quiet symmetrical structure; the bishop comes out before ...e6.
- Panov Attack (3.exd5 cxd5 4.c4 Nf6 5.Nc3 e6): White plays for an isolated pawn and activity; Black's knight blockades d5.
- Two Knights Attack (1.e4 c6 2.Nc3 d5 3.Nf3 Bg4 4.h3 Bxf3): Both knights before d4; Black gives the bishop and builds the center.

#### Scandinavian Defense

B01, for Black, 3 lessons. 1.e4 d5. Black challenges e4 on the first move.

- The ideas, with the main line (2.exd5 Qxd5 3.Nc3 Qa5): The queen takes back and retreats to a5, and the pieces come out around her. The main line is the opening's first moves, so it is in the ideas lesson.
- Gubinsky-Melts Defense (2.exd5 Qxd5 3.Nc3 Qd6): The queen retreats to d6, and ...a6 keeps the knight off b5.
- Modern Variation (2.exd5 Nf6 3.d4 Nxd5 4.c4 Nb6 5.Nf3 g6 6.Nc3 Bg7 7.c5 Nd5): Black takes back with the knight later; when White's pawns chase it, it settles on d5 in front of them.

#### Pirc Defense

B07, for Black, 3 lessons. 1.e4 d6 2.d4 Nf6 3.Nc3 g6. Black lets White build a center and attacks it later.

- The ideas, with the Classical Variation (4.Nf3 Bg7 5.Be2 O-O 6.O-O Bg4): Calm development is the main line, so the two are one lesson; it ends on the ...e5 strike.
- Austrian Attack (4.f4 Bg7 5.Nf3 O-O): Three pawns in the center; Black hits them with ...c5.
- 150 Attack (4.Be3 c6 5.Qd2 b5 6.Bd3 Nbd7 7.Nf3 e5): White brings bishop and queen out together; Black takes space on the queen's side and strikes with ...e5. Added because club players meet it more than any other line.

#### Modern Defense

B06, for Black, 1 lesson. 1.e4 g6. The bishop to g7 before anything else.

- The ideas, with the main line (2.d4 Bg7 3.Nc3 d6 4.Be3 a6 5.Qd2 b5): The main line is short, so the two are one lesson; it ends on the ...c5 strike.

#### Alekhine Defense

B02, for Black, 4 lessons. 1.e4 Nf6. Black invites White's pawns forward to attack them.

- The ideas, with the main line (2.e5 Nd5 3.d4 d6 4.c4 Nb6): The main line is short, so the two are one lesson.
- Modern Variation (4.Nf3 dxe5 5.Nxe5 g6): Development over pawns, and the trap 5...Nd7? 6.Nxf7 that ...g6 avoids.
- Four Pawns Attack (4.c4 Nb6 5.f4 dxe5 6.fxe5 Nc6): White takes all the space offered; Black's pieces attack it.
- Exchange Variation (4.c4 Nb6 5.exd6 cxd6): White trades on d6; Black takes back toward the center and strikes with ...e5.

### 1.d4 d5

Closed games: both sides take the center with the queen's pawn.

#### Queen's Gambit

D06, for White, 7 lessons. 1.d4 d5 2.c4. White offers the c-pawn to pull Black's pawn from the center. The ideas lesson is in the first release; it plays the main line's first moves too, so the two are one lesson.

- Queen's Gambit Accepted (2...dxc4 3.Nf3 Nf6 4.e3 e6 5.Bxc4 c5 6.O-O a6 7.a4): Black takes, and White develops and takes the pawn back.
- Declined: Orthodox Defense (2...e6 3.Nc3 Nf6 4.Bg5 Be7 5.e3 O-O 6.Nf3 Nbd7 7.Rc1 c6 8.Bd3 dxc4 9.Bxc4 Nd5): The classical main line: the rook on the c-file and the fight for a tempo.
- Declined: Exchange Variation (2...e6 3.Nc3 Nf6 4.cxd5 exd5): White trades on d5 and plays the minority attack.
- Declined: Tartakower Defense (2...e6 3.Nc3 Nf6 4.Bg5 Be7 5.e3 O-O 6.Nf3 h6 7.Bh4 b6): Black makes room for the bishop with ...b6; White trades on d5, the bishop comes out to e6, and White presses on the c-file.
- Declined: Ragozin Defense (2...e6 3.Nc3 Nf6 4.Nf3 Bb4): A pin, as in the Nimzo-Indian; White trades on d5 and castles out of it.
- Traps, one lesson: Holding the gambit pawn (2...dxc4 3.e3 b5 4.a4 c6 5.axb5 cxb5 6.Qf3): Black keeps the pawn with ...b5 and loses a piece on the long diagonal. The Elephant Trap (2...e6 3.Nc3 Nf6 4.Bg5 Nbd7 5.cxd5 exd5 6.Nxd5 Nxd5 7.Bxd8 Bb4+ 8.Qd2 Bxd2+ 9.Kxd2 Kxd8): taking on d5 looks like it wins a pawn, but loses a piece; the player finds 6.e3 instead.

#### Slav Defense

D10, for Black, 3 lessons. 1.d4 d5 2.c4 c6. c6 holds d5 and keeps the bishop free. The ideas and the main line are one lesson (3.Nf3 Nf6 4.e3 Bf5 5.Nc3 e6 6.Nh4 Bg6).

- Czech Variation (3.Nf3 Nf6 4.Nc3 dxc4 5.a4 Bf5): Black takes on c4, develops the bishop and pins the knight; White's early e4 loses a pawn.
- Exchange Variation (3.cxd5 cxd5): Symmetrical and quiet; ...Bb4 meets the queen's attack on b7.

#### Semi-Slav Defense

D43, for Black, 3 lessons. 1.d4 d5 2.c4 c6 3.Nf3 Nf6 4.Nc3 e6. The Slav and the Queen's Gambit Declined in one. The ideas and the main line are one lesson (5.e3 Nbd7 6.Qc2 Bd6 7.Bd3 O-O 8.O-O dxc4 9.Bxc4 e5).

- Meran Variation (5.e3 Nbd7 6.Bd3 dxc4 7.Bxc4 b5): Black takes on c4 and expands on the queenside, chasing the bishop, then strikes with ...c5.
- Botvinnik Variation (5.Bg5 dxc4 6.e4 b5 7.e5 h6 8.Bh4 g5 9.Nxg5 hxg5 10.Bxg5 Nbd7): Sharp: both sides attack.

#### Tarrasch Defense

D32, for Black, 2 lessons. 1.d4 d5 2.c4 e6 3.Nc3 c5. Black accepts an isolated pawn for free piece play.

- The ideas (4.cxd5 exd5 5.Nf3 Nc6 6.dxc5 d4 7.Na4 Bxc5 8.Nxc5 Qa5+): the strike at the center, and ...d4 when White grabs the pawn on c5.
- The main line (6.g3 Nf6 7.Bg2 Be7 8.O-O O-O 9.Bg5 cxd4 10.Nxd4 h6 11.Be3 Re8): the isolated pawn on d5 and open lines for every piece.

#### Albin Countergambit

D08, for Black, 2 lessons. 1.d4 d5 2.c4 e5. Black answers the gambit with one of its own. The ideas and the main line are one lesson (3.dxe5 d4 4.Nf3 Nc6 5.g3 Nge7 6.Bg2 Ng6 7.O-O Ngxe5).

- Trap: The Lasker Trap (3.dxe5 d4 4.e3 Bb4+ 5.Bd2 dxe3 6.Bxb4 exf2+ 7.Ke2 fxg1=N+ 8.Rxg1 Bg4+): The pawn takes on g1 and becomes a knight, with check.

#### London System

D02, for White, 2 lessons. 1.d4 d5 2.Nf3 Nf6 3.Bf4. The same setup against almost anything: Bf4, e3, c3. The ideas and the main line are one lesson; it also meets the early ...Qb6 against b2 (3...c5 4.e3 Qb6 5.Nc3 Qxb2 6.Nb5).

- London System against the King's Indian setup (1.d4 Nf6 2.Nf3 g6 3.Bf4): The same plan when Black fianchettoes, with h3 to keep the bishop.

### 1.d4 Nf6

Indian defenses: Black controls the center with pieces first.

#### King's Indian Defense

E70, for Black, 5 lessons. 1.d4 Nf6 2.c4 g6 3.Nc3 Bg7 4.e4 d6. Black lets White build a big center, then strikes at it. The ideas lesson is in the first release; it already plays the Orthodox Variation's moves (5.Nf3 O-O 6.Be2 e5), so the main line and the Orthodox Variation are one lesson with it, and the Mar del Plata Variation goes on from there.

- Mar del Plata Variation (5.Nf3 O-O 6.Be2 e5 7.O-O Nc6 8.d5 Ne7 9.Ne1 Nd7 10.Be3 f5 11.f3 f4 12.Bf2 g5): The center locks; White on the queenside, Black storms the kingside.
- Sämisch Variation (5.f3 O-O 6.Be3 e5 7.d5 Nh5 8.Qd2 f5 9.O-O-O Nd7): f3 holds e4; Black closes the center and the kings castle on opposite wings.
- Four Pawns Attack (5.f4 O-O 6.Nf3 c5 7.d5 e6 8.Be2 exd5 9.cxd5 Re8 10.e5 dxe5 11.fxe5 Ng4): White takes as much center as there is, and Black attacks the pawns at once.
- Fianchetto Variation (1.d4 Nf6 2.c4 g6 3.Nf3 Bg7 4.g3 O-O 5.Bg2 d6 6.O-O Nc6 7.Nc3 a6 8.d5 Na5 9.Nd2 c5 10.Qc2 Rb8 11.b3 b5): White fianchettoes too, so Black plays on the queenside.

#### Nimzo-Indian Defense

E20, for Black, 4 lessons. 1.d4 Nf6 2.c4 e6 3.Nc3 Bb4. The pin on c3 stops e4. The main line is the opening's first three moves, so the ideas and the main line are one lesson; it ends on 4.e4? Nxe4, the pinned knight unable to take back.

- Rubinstein System (4.e3 O-O 5.Bd3 d5 6.Nf3 c5 7.O-O Nc6 8.a3 Bxc3 9.bxc3 dxc4 10.Bxc4 Qc7 11.Bd3 e5): Flexible development, and Black takes its share of the center.
- Classical Variation (4.Qc2 O-O 5.a3 Bxc3+ 6.Qxc3 b6 7.Bg5 Bb7 8.f3 h6 9.Bh4 d5): The queen avoids doubled pawns; Black fights for e4 with pieces.
- Sämisch Variation (4.a3 Bxc3+ 5.bxc3 c5 6.e3 Nc6 7.Bd3 O-O 8.Ne2 b6 9.e4 Ne8 10.O-O Ba6 11.f4 f5): Doubled pawns for the bishop pair; Black attacks c4 and blocks the kingside.

#### Queen's Indian Defense

E12, for Black, 3 lessons. 1.d4 Nf6 2.c4 e6 3.Nf3 b6. The bishop on b7 watches e4. The ideas and the main line are one lesson (4.Nc3 Bb7), ending on the common 5.e4? Nxe4.

- Fianchetto Variation (4.g3 Bb7 5.Bg2 Be7 6.O-O O-O 7.Nc3 Ne4 8.Qc2 Nxc3 9.Qxc3 c5 10.Rd1 d6): Bishops facing each other on the long diagonal; Black trades a knight on e4.
- Petrosian Variation (4.a3 Bb7 5.Nc3 d5 6.cxd5 Nxd5 7.Qc2 Nxc3 8.bxc3 Be7 9.e4): a3 keeps the black bishop off b4; and 7.e4, a rare gambit before the queen guards e4, loses a pawn.

#### Bogo-Indian Defense

E11, for Black, 1 lesson. 1.d4 Nf6 2.c4 e6 3.Nf3 Bb4+. A check to trade or misplace a White piece. The main line is short, so the ideas and the main line are one lesson (4.Bd2 Qe7 5.g3 Nc6 6.Bg2 Bxd2+ 7.Nbxd2 d6 8.O-O e5).

#### Grünfeld Defense

D80, for Black, 3 lessons. 1.d4 Nf6 2.c4 g6 3.Nc3 d5. Black gives White the center to attack it with pieces. The ideas and the main line are one lesson; it meets 4.Bf4 Bg7 5.e3 c5 6.dxc5 Qa5, as the Exchange and Russian lessons cover the other main lines.

- Exchange Variation (4.cxd5 Nxd5 5.e4 Nxc3 6.bxc3 Bg7 7.Nf3 c5 8.Rb1 O-O): White's big center against the bishop on g7; and 8.d5? Bxc3+, the bishop taking the rook on a1.
- Russian Variation (4.Nf3 Bg7 5.Qb3 dxc4 6.Qxc4 O-O 7.e4 a6 8.Be2 b5 9.Qb3 c5 10.dxc5 Bb7 11.e5 Nfd7): The queen pressures d5; Black chases it with pawns.

#### Benoni Defense

A60, for Black, 2 lessons. 1.d4 Nf6 2.c4 c5 3.d5 e6 4.Nc3 exd5 5.cxd5 d6. Unbalanced: a queenside majority for Black, a central one for White. The opening table has no name for the position after 5...d6, so the chapter's moves stop at 3...e6, which it names Benoni Defense: Modern Variation. The ideas and the main line are one lesson; it goes on to the sharp 6.e4 g6 7.f4 Bg7 8.Bb5+, where Black blocks with the f6 knight (8...Nfd7), not the b8 one.

- Classical Variation (6.e4 g6 7.Nf3 Bg7 8.Be2 O-O 9.O-O Re8 10.Nd2): The rook and knight aim at e4; and 10.a4? Nxe4 when White forgets it.

#### Benko Gambit

A57, for Black, 2 lessons. 1.d4 Nf6 2.c4 c5 3.d5 b5. A pawn for open files on the queenside. The ideas lesson plays the Accepted line (4.cxb5 a6 5.bxa6 Bxa6 6.Nc3 d6 7.e4 Bxf1 8.Kxf1 g6), so the Accepted variation is one lesson with it.

- The main line (9.g3 Bg7 10.Kg2 O-O 11.Nf3 Nbd7 12.Re1 Qa5 13.h3 Rfb8): Queen, rooks and bishop against White's queenside.

#### Budapest Gambit

A51, for Black, 1 lesson. 1.d4 Nf6 2.c4 e5. A pawn for quick piece play. The opening table names it Indian Defense: Budapest Gambit; the chapter is titled by the part that tells it apart. The ideas and the main line are one lesson (3.dxe5 Ng4 4.Bf4 Nc6 5.Nf3 Bb4+ 6.Nbd2 Qe7 7.a3 Ngxe5), ending on its trap, 8.axb4?? Nd3#.

#### Catalan Opening

E00, for White, 3 lessons. 1.d4 Nf6 2.c4 e6 3.g3. The Queen's Gambit with a bishop on g2. The ideas and the main line are one lesson (3...d5 4.Bg2 Be7 5.Nf3 O-O 6.O-O Nbd7 7.Qc2).

- Open Defense (3...d5 4.Bg2 Be7 5.Nf3 O-O 6.O-O dxc4 7.Qc2): Black takes the pawn on c4; the usual 7...a6 gives it back, and holding it with 7...b5 8.a4 c6? opens the long diagonal to 10.Ng5.
- Closed (3...d5 4.Bg2 Be7 5.Nf3 O-O 6.O-O Nbd7 7.Qc2 c6 8.Nbd2 b6 9.e4 Bb7 10.e5): Black keeps the pawn on d5, and White pushes e4 and e5.

### 1.d4 f5

The Dutch: Black fights for e4 with the f-pawn from the first move.

#### Dutch Defense

A80, for Black, 4 lessons. 1.d4 f5. Black fights for e4 with the f-pawn. The ideas and the main line are one lesson, with the classical setup and the queen's swing to h5 (2.c4 Nf6 3.g3 e6 4.Bg2 Be7 5.Nf3 O-O 6.O-O d6 7.Nc3 Qe8 8.b3 Qh5).

- Leningrad Variation (2.c4 Nf6 3.g3 g6 4.Bg2 Bg7 5.Nf3 O-O 6.O-O d6 7.Nc3 Qe8 8.b3 e5): The bishop on g7, and the e5 push.
- Stonewall Variation (2.c4 Nf6 3.g3 e6 4.Bg2 d5 5.Nf3 c6 6.O-O Bd6 7.Nc3 O-O 8.Qc2 Ne4 9.Rb1 Nd7): Pawns on c6, d5, e6 and f5: a hold on e4, and a hole on e5.
- Staunton Gambit (2.e4 fxe4 3.Nc3 Nf6 4.Bg5 Nc6 5.d5 Ne5 6.Qd4 Nf7 7.Bxf6 exf6 8.Nxe4 f5): White's gambit against it; Black takes, and 3...d5? 4.Qh5+ is the mistake to avoid.

### Other first moves

Flank openings: White starts with something other than 1.e4 or 1.d4.

#### English Opening

A10, for White, 4 lessons. 1.c4. The c-pawn first, control of d5 from the side. The ideas and the main line are one lesson (1...e5 2.Nc3 Nc6 3.g3 g6 4.Bg2 Bg7 5.d3 d6 6.Rb1 and b4).

- King's English (1...e5 2.Nc3 Nf6 3.g3 d5 4.cxd5 Nxd5 5.Bg2): A Sicilian with colors reversed.
- Symmetrical Variation (1...c5): Black copies the pawn; White breaks the symmetry with d4.
- Anglo-Indian Defense (1...Nf6 2.Nc3 e6 3.e4 d5 4.e5): The knight first, choices later; White takes the center.

#### Réti Opening

A09, for White, 1 lesson. 1.Nf3 d5 2.c4. The knight first, then c4 against d5. The main line is short, so the ideas and the main line are one lesson (2...c6 3.b3 Nf6 4.g3 Bf5 5.Bg2 e6 6.Bb2 Nbd7 7.O-O, the Anglo-Slav Variation).

#### King's Indian Attack

A07, for White, 1 lesson. 1.Nf3 d5 2.g3. A King's Indian setup for White, against almost anything. The ideas and the main line are one lesson (2...Nf6 3.Bg2 e6 4.O-O Be7 5.d3 O-O 6.Nbd2 c5 7.e4 Nc6 8.Re1 b5 9.e5).

#### Bird Opening

A02, for White, 2 lessons. 1.f4. The f-pawn first, control of e5. The ideas and the main line are one lesson (1...d5 2.Nf3 Nf6 3.e3 g6 4.b3 Bg7 5.Bb2 O-O 6.Be2 c5 7.O-O Nc6 8.Ne5).

- From's Gambit (1...e5 2.fxe5 d6 3.exd6 Bxd6 4.Nf3): Black's sharpest reply, and the mate after 4.Nc3 Qh4+.

## Tactics (27 lessons)

Forks, pins and attacks on the king.

### Seeing the board

- **Pieces left hanging** (first release): Before every move: checks, captures, threats, and is anything of yours or theirs undefended.

### Double attacks

- **The fork** (first release): One piece attacks two at once. The knight does it best, and a fork with check is the strongest kind.
- **Queen and pawn forks**: The queen attacks in eight directions; the pawn, the smallest piece, attacks two bigger ones.

### Lines

- **The pin** (first release): A piece cannot move without exposing a bigger one behind it: not at all when the king is behind, at a cost when it is the queen.
- **Breaking a pin**: Block, move the piece behind, or attack the pinning piece.
- **The skewer** (first release): A pin turned around: the bigger piece in front must move and the one behind falls.
- **X-ray**: A piece working through another piece on the same line.

### Discoveries

- **Discovered attack** (first release): Move one piece and uncover an attack by another.
- **Discovered and double check**: The uncovered piece gives check, so the moving piece can take anything; when both give check, only a king move answers it.
- **The windmill**: Discovered checks one after another, taking a piece each time.

### Removing the guard

- **Removing the defender**: Capture or chase the piece that holds everything together.
- **Deflection and overloading**: Pull a defender away from the square it guards, often one defender with two jobs.
- **Decoy**: Give something up to lure a piece onto a square where it can be hit.
- **Interference**: Put a piece between a defender and what it defends.
- **Clearance**: Move a piece out of the way of another.

### More ideas

- **Trapped pieces**: A piece with no safe square, usually a bishop or a knight on the edge.
- **The in-between move**: Before recapturing, a stronger move first.
- **Desperado**: A piece that is lost anyway takes something with it.
- **Quiet moves**: A combination where the key move is not a check or a capture.
- **Underpromotion**: When a knight or a rook is better than a queen.
- **Perpetual check**: Saving a lost game with checks that never end.

### Calculating

- **Seeing the defense**: Look for your opponent's best reply, not the one you hope for.

### Attacking the king

- **Sacrifices on f7 and f2**: The weakest squares in the opening, guarded only by the king.
- **The Greek gift**: The bishop sacrifice on h7 (or h2), followed by the knight and the queen: give a piece to win more.
- **The double bishop sacrifice**: Both bishops given up on h7 and g7 to strip the king.
- **Pawn storms**: Throwing pawns at the castled king, opening a file for the rooks; with the kings on opposite wings, whoever attacks first.
- **Defending an attack**: Trade attackers and counterattack in the center.

## Checkmates (23 lessons)

Patterns that finish a game.

### The first mates

- **Fool's mate**: The fastest mate there is, in two moves, and the pawn moves that allow it.
- **Scholar's mate and how to stop it** (first release): Queen and bishop on f7 in four moves, and the moves that make it harmless.
- **Back-rank mate** (first release): A rook or queen on the last rank, the king boxed in by its own pawns.

### Mates you must know

- **King and queen against king** (first release): Push the king to the edge with the queen, then bring your king. Mind stalemate.
- **King and rook against king**: The box that shrinks, and the opposition for the final check.
- **Two rooks**: The ladder: rooks taking turns on the ranks.
- **Two bishops**: Side by side, they drive the king into a corner.
- **Bishop and knight**: The hardest basic mate: the corner of the bishop's color.

### Patterns

- **Smothered mate**: A knight mates a king hemmed in by its own pieces.
- **Arabian and hook mates**: A rook right next to the king, guarded by a knight, in the corner (Arabian) or on the edge with a pawn guarding the knight (hook).
- **Anastasia's mate**: Knight and rook against a king on the edge.
- **Greco's and Morphy's mates**: Bishop and rook against the king in the corner: the rook checks with the bishop guarding g8 (Greco), or the bishop checks on the long diagonal with the rook holding the file (Morphy).
- **Opera mate**: Rook and bishop, after Morphy's game at the Paris opera in 1858.
- **Boden's mate**: Two bishops on crossing diagonals.
- **Blackburne's mate**: Two bishops and a knight around the castled king.
- **Epaulette mate**: The king's own rooks on either side block it in.
- **Damiano's and dovetail mates**: The queen next to the king on a diagonal, guarded by a pawn (Damiano) or a piece (dovetail), with the king's own pieces behind it.
- **Lolli's mate**: A pawn on f6 and the queen landing on g7.
- **Légal's mate**: A queen given up so that the minor pieces mate.

Merged when the lessons were written: hook mate into Arabian (the same rook guarded by a knight), Morphy's mate into Greco's (the same bishop and rook against the cornered king), and dovetail into Damiano's (the same guarded queen on the diagonal).

### Finding mate

- **Mate in one**: Every check, and which one ends it.
- **Mate in two: checks first**: A check that leaves one reply, then mate.
- **Mate in two: a quiet move**: The first move threatens; every answer allows mate.
- **Mate in three**: Longer lines, still forcing.

## Endgames (29 lessons)

Kings, pawns and rooks at the end.

### King and pawns

- **The square of the pawn**: Can the king catch it? Draw the square and see.
- **The opposition**: Kings facing each other: whoever has to move must give way.
- **Key squares**: Lead with the king: the squares that make the pawn promote, and the king in front of the pawn.
- **King and pawn against king**: The defense: in front of the pawn, the opposition holds the draw.
- **Rook pawns**: Why an a- or h-pawn is often a draw.
- **Triangulation**: Losing a move with the king to hand over the turn.
- **The outside passed pawn**: A pawn far away that pulls the enemy king off.
- **Breakthroughs**: Three pawns against three, and the sacrifice that makes a queen.

### Queen endings

- **Queen against pawn**: Usually a win; with their king close, a bishop or rook pawn on the seventh can draw.
- **Queen against rook**: A win, with patience: the rook strays from its king, and a check catches both.

### Rook endings

- **Rook against pawn**: When the king gets there in time.
- **Cutting off the king**: A rook that keeps the defending king away.
- **The Lucena position**: Build a bridge and the pawn promotes.
- **The Philidor position**: The rook on the third rank holds the draw.
- **Short side defense**: Checks from the long side, king on the short side.
- **The Vancura position**: The rook from the side against a rook pawn.
- **Rooks behind passed pawns**: Behind your own pawn, and behind the enemy's; in front of a pawn a rook is passive.
- **Rook against bishop, rook against knight**: Usually drawn, and the traps on the way.

### Minor pieces

- **Bishops of opposite colors**: Often a draw even a pawn or two down.
- **Bishops of the same color**: Where your pawns belong when both bishops run on the same color.
- **The wrong rook pawn**: Bishop and rook pawn draw when the bishop cannot cover the corner.
- **Knight against pawns**: The knight is slow to cross the board; the bishop stops a pawn from afar.
- **Two knights cannot force mate**: Against a bare king, the defender always has a way out.

### Principles

- **Use the king**: In the endgame the king is a strong piece.
- **Passed pawns must be pushed**: And blockaded when they are not yours.
- **Trading into a won ending**: Which pieces to trade when ahead.
- **Zugzwang**: Every move makes it worse, and spare pawn moves decide who runs out first.
- **Fortresses**: A position the stronger side cannot break.
- **Stalemate tricks**: The last resource when losing, and how not to fall for it.

## Strategy (23 lessons)

Pawns, pieces and plans.

### Pawns

- **Pawn structure**: Pawns in groups, called islands. The fewer islands, the fewer weak pawns.
- **The isolated pawn**: No pawns of its own beside it: block it, trade pieces, then win it.
- **Doubled pawns**: Two pawns on one file: when they hurt and when they do not.
- **The backward pawn**: A pawn its neighbors cannot defend.
- **Hanging pawns**: Two pawns side by side with no pawns of their own beside them.
- **Passed pawns**: A pawn no pawn can stop, and the extra pawns on one side that make one.
- **Pawn chains**: Pawns guarding each other on a diagonal. Attack the base of the chain.
- **The minority attack**: Two pawns against three, pushed to leave Black a weak pawn.

### Pieces

- **Good and bad bishops**: A bishop blocked by its own pawns, and what to do with it.
- **The bishop pair**: Two bishops on an open board. Keep them, and open lines for them.
- **Open files**: Rooks belong where the pawns have gone.
- **The seventh rank**: A rook on the seventh attacks pawns and boxes in the king.
- **Your worst piece**: Find the piece doing the least, and give it a better square.

### Space and squares

- **Space**: Pawns in the center give your pieces room and take it from theirs.
- **Weak squares**: Squares no enemy pawn can attack, and the knight that settles in one.

### Planning

- **Making a plan**: Look at the pawns, find a target, bring the pieces.
- **Prophylaxis**: Ask what your opponent wants, and stop it first.
- **Two weaknesses**: One weakness can be defended. Two usually cannot.
- **The initiative**: Threats that leave your opponent no time, and when time is worth a pawn.
- **King safety**: Pawn shields, open lines, and when to leave the king in the center.

### Classic games

- **The Immortal Game**: Anderssen against Kieseritzky, London 1851: a bishop, both rooks and the queen given for mate.
- **The Evergreen Game**: Anderssen against Dufresne, Berlin 1852: an attack down the open lines.
- **The Opera Game**: Morphy against the Duke of Brunswick and Count Isouard, Paris 1858: development wins.
