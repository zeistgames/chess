// Opening names, looked up by position, so the web, the app and the main Zeist app name openings the same way.
// The table is the Lichess chess-openings data (CC0-1.0), vendored in vendor/chess-openings.

import { Game, START } from './rules.js';

let table = null;
async function load() {
  if (!table) table = (await import('./vendor/chess-openings/openings.js')).default;
  return table;
}

/**
 * The opening a game is in: the named position reached last along its moves, as { eco, name, ply }, or null.
 * A game that leaves the book keeps the last name it had.
 */
export async function opening(moves = [], fen = START) {
  const t = await load();
  const g = new Game(fen);
  let found = null;
  const at = ply => {
    const hit = t[g.key()];
    if (hit) { const [eco, name] = hit.split('|'); found = { eco, name, ply }; }
  };
  for (let i = 0; i < moves.length; i++) {
    if (!g.play(moves[i])) break;
    at(i + 1);
  }
  return found;
}
