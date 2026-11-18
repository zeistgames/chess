// SPDX-License-Identifier: AGPL-3.0-or-later
// What each side has taken and who is ahead, from a position (board as core/rules.js gives it: "wP", "bQ", "").
// The same counting as the iPhone app (ios/ZeistChess/Play/Material.swift).

const KINDS = ['P', 'N', 'B', 'R', 'Q'];
const VALUE = { P: 1, N: 3, B: 3, R: 5, Q: 9 };
const START = { P: 8, N: 2, B: 2, R: 2, Q: 1 };

function count(side, board) {
  const c = {};
  for (const p of board) if (p && p[0] === side) c[p[1]] = (c[p[1]] || 0) + 1;
  return c;
}

/** The pieces of side no longer on the board: [{ kind, count }], pawns first. Promoted pieces stand for pawns. */
export function lost(side, board) {
  const c = count(side, board);
  const promoted = ['N', 'B', 'R', 'Q'].reduce((a, k) => a + Math.max(0, (c[k] || 0) - START[k]), 0);
  const out = [];
  for (const k of KINDS) {
    const n = k === 'P' ? Math.max(0, 8 - (c.P || 0) - promoted) : Math.max(0, START[k] - (c[k] || 0));
    if (n > 0) out.push({ kind: k, count: n });
  }
  return out;
}

/** What side has captured: the other side's lost pieces. */
export function captured(side, board) { return lost(side === 'w' ? 'b' : 'w', board); }

/** How far side is ahead in material, or 0. */
export function lead(side, board) {
  let b = 0;
  for (const p of board) if (p && VALUE[p[1]]) b += p[0] === 'w' ? VALUE[p[1]] : -VALUE[p[1]];
  return Math.max(0, side === 'w' ? b : -b);
}

/** Whether side could still checkmate by some series of legal moves (used when the other side's flag falls).
 *  A bare king cannot; a king with one bishop or one knight cannot against a bare king, but can when the other side
 *  has anything left to hem its own king in. Anything more can. (ios/ZeistChess/Play/Material.swift) */
export function canMate(side, board) {
  if (bishopsOnOneColor(board)) return false;
  const c = count(side, board);
  if ((c.P || 0) + (c.R || 0) + (c.Q || 0) > 0) return true;
  const minors = (c.N || 0) + (c.B || 0);
  if (minors !== 1) return minors >= 2;
  const them = count(side === 'w' ? 'b' : 'w', board);
  return Object.keys(them).some(k => k !== 'K' && them[k] > 0);
}

/** A dead position: nothing on the board but kings and bishops, and every bishop on squares of one color. No series
 *  of moves can mate then, for either side, however many bishops there are. */
function bishopsOnOneColor(board) {
  const colors = new Set();
  for (let i = 0; i < board.length; i++) {
    const p = board[i];
    if (!p || p[1] === 'K') continue;
    if (p[1] !== 'B') return false;
    colors.add((i % 8 + Math.floor(i / 8)) % 2);
  }
  return colors.size === 1;
}
