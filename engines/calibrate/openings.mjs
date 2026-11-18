// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The fixed list of short openings every calibration game starts from: four plies each, main lines that
// leave both sides an even game, no gambits that drop material for long, no two reaching the same position.
// Pair k at any level of any engine starts from OPENINGS[k % OPENINGS.length], so engines meet the same
// starts and two deterministic players still play different games. Names are from the Lichess
// chess-openings table vendored in core/ (CC0), looked up when the list was made.

export const OPENINGS = [
  { moves: "e2e4 e7e5 g1f3 b8c6", name: "C44 King's Knight Opening: Normal Variation" },
  { moves: "d2d4 d7d5 c2c4 e7e6", name: "D30 Queen's Gambit Declined" },
  { moves: "e2e4 c7c5 g1f3 d7d6", name: "B50 Sicilian Defense: Modern Variations" },
  { moves: "d2d4 g8f6 c2c4 g7g6", name: "E60 Indian Defense: West Indian Defense" },
  { moves: "e2e4 e7e6 d2d4 d7d5", name: "C00 French Defense" },
  { moves: "c2c4 e7e5 b1c3 g8f6", name: "A22 English Opening: King's English Variation, Two Knights Variation" },
  { moves: "e2e4 c7c6 d2d4 d7d5", name: "B12 Caro-Kann Defense" },
  { moves: "d2d4 g8f6 c2c4 e7e6", name: "A50 Indian Defense: Normal Variation" },
  { moves: "e2e4 e7e5 g1f3 g8f6", name: "C42 Petrov's Defense" },
  { moves: "g1f3 d7d5 g2g3 g8f6", name: "A05 King's Indian Attack" },
  { moves: "e2e4 c7c5 g1f3 b8c6", name: "B30 Sicilian Defense: Old Sicilian" },
  { moves: "d2d4 d7d5 c2c4 c7c6", name: "D10 Slav Defense" },
  { moves: "e2e4 d7d6 d2d4 g8f6", name: "B00 Pirc Defense" },
  { moves: "d2d4 g8f6 g1f3 d7d5", name: "D02 Queen's Pawn Game: Symmetrical Variation" },
  { moves: "e2e4 c7c5 b1c3 b8c6", name: "B23 Sicilian Defense: Closed, Traditional" },
  { moves: "c2c4 c7c5 g1f3 b8c6", name: "A30 English Opening: Symmetrical Variation" },
  { moves: "e2e4 g7g6 d2d4 f8g7", name: "B06 Modern Defense" },
  { moves: "d2d4 d7d5 c1f4 g8f6", name: "D00 Queen's Pawn Game: Accelerated London System" },
  { moves: "e2e4 e7e5 b1c3 g8f6", name: "C26 Vienna Game: Falkbeer Variation" },
  { moves: "d2d4 g8f6 c1g5 e7e6", name: "A45 Trompowsky Attack: Classical Defense" },
  { moves: "e2e4 c7c5 g1f3 e7e6", name: "B40 Sicilian Defense: French Variation" },
  { moves: "c2c4 g8f6 b1c3 e7e6", name: "A17 English Opening: Anglo-Indian Defense, Hedgehog System" },
  { moves: "e2e4 d7d5 e4d5 d8d5", name: "B01 Scandinavian Defense: Mieses-Kotrč Variation" },
  { moves: "d2d4 d7d5 c2c4 d5c4", name: "D20 Queen's Gambit Accepted" },
  { moves: "e2e4 e7e5 f1c4 g8f6", name: "C24 Bishop's Opening: Berlin Defense" },
  { moves: "g1f3 g8f6 c2c4 g7g6", name: "A15 English Opening: Anglo-Indian Defense, King's Indian Formation" },
  { moves: "e2e4 c7c5 c2c3 g8f6", name: "B22 Sicilian Defense: Alapin Variation" },
  { moves: "d2d4 f7f5 c2c4 g8f6", name: "A84 Dutch Defense: Normal Variation" },
  { moves: "e2e4 g8f6 e4e5 f6d5", name: "B02 Alekhine Defense: Normal Variation" },
  { moves: "d2d4 g8f6 c2c4 c7c5", name: "A56 Benoni Defense" },
  { moves: "e2e4 e7e6 g1f3 d7d5", name: "C00 French Defense: Knight Variation" },
  { moves: "c2c4 e7e6 b1c3 d7d5", name: "A13 English Opening: Agincourt Defense" },
  { moves: "e2e4 c7c6 b1c3 d7d5", name: "B10 Caro-Kann Defense" },
  { moves: "d2d4 d7d5 e2e3 g8f6", name: "D00 Queen's Pawn Game" },
  { moves: "e2e4 c7c5 g1f3 g7g6", name: "B27 Sicilian Defense: Hyperaccelerated Dragon" },
  { moves: "d2d4 g8f6 c2c4 d7d6", name: "A53 Old Indian Defense" },
  { moves: "e2e4 e7e5 g1f3 d7d6", name: "C41 Philidor Defense" },
  { moves: "g2g3 d7d5 f1g2 g8f6", name: "A00 Hungarian Opening" },
  { moves: "e2e4 c7c5 d2d4 c5d4", name: "B21 Sicilian Defense: Smith-Morra Gambit" },
  { moves: "d2d4 g7g6 c2c4 f8g7", name: "A40 Queen's Pawn Game: Modern Defense" },
  { moves: "g1f3 d7d5 c2c4 e7e6", name: "A13 English Opening: Agincourt Defense" },
  { moves: "b2b3 e7e5 c1b2 b8c6", name: "A01 Nimzo-Larsen Attack: Modern Variation" },
  { moves: "e2e4 d7d6 d2d4 g7g6", name: "B00 Pirc Defense" },
  { moves: "d2d4 g8f6 g1f3 e7e6", name: "A46 Indian Defense: Knights Variation" },
  { moves: "c2c4 g7g6 b1c3 f8g7", name: "A10 English Opening: Great Snake Variation" },
  { moves: "e2e4 e7e5 b1c3 b8c6", name: "C25 Vienna Game: Max Lange Defense" },
  { moves: "d2d4 g8f6 g1f3 g7g6", name: "A48 East Indian Defense" },
  { moves: "g1f3 g8f6 g2g3 g7g6", name: "A05 King's Indian Attack: Symmetrical Defense" },
];

/** The opening for pair k, as { index, moves: [uci], name }. */
export function openingFor(k) {
  const index = ((k % OPENINGS.length) + OPENINGS.length) % OPENINGS.length;
  const o = OPENINGS[index];
  return { index, moves: o.moves.split(' '), name: o.name };
}
