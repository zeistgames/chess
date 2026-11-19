// The rules of chess behind one small interface. This is the only file that may use chess.js:
// the Zeist rules replace it later, and nothing else should notice.
//
// Squares are named "a1".."h8". Moves are UCI strings ("e2e4", "e7e8q").

import { Chess, validateFen } from './vendor/chess.js/chess.js';

export const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

const FILES = 'abcdefgh';

function uciOf(m) {
  return m.from + m.to + (m.promotion || '');
}

function parseUci(uci) {
  if (typeof uci !== 'string' || !/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(uci)) return null;
  return { from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] };
}

export class Game {
  /** A game from a starting position (FEN), with no moves yet. */
  constructor(fen = START) {
    this._c = new Chess(fen);
    this._start = this._c.fen();
    this._moves = [];
  }

  /** A game from a starting position and a list of UCI moves. Throws on the first illegal move. */
  static fromMoves(moves = [], fen = START) {
    const g = new Game(fen);
    for (const m of moves) {
      if (!g.play(m)) throw new Error(`illegal move ${m} at ply ${g._moves.length}`);
    }
    return g;
  }

  /** "w" or "b": who is to move. */
  turn() { return this._c.turn(); }

  fen() { return this._c.fen(); }

  startFen() { return this._start; }

  /** 64 entries from a8 to h1, row by row: "" for empty, else color and piece, such as "wK" or "bN". */
  board() {
    const out = [];
    for (const row of this._c.board()) {
      for (const sq of row) out.push(sq ? sq.color + sq.type.toUpperCase() : '');
    }
    return out;
  }

  /** Every legal move: { uci, from, to, san, capture, promotion, castle }. */
  legal() {
    return this._c.moves({ verbose: true }).map(describe);
  }

  /** Legal moves of the piece on one square. */
  legalFrom(square) {
    return this._c.moves({ square, verbose: true }).map(describe);
  }

  /** Plays a UCI move. Returns { uci, san } or null when the move is not legal. */
  play(uci) {
    const p = parseUci(uci);
    if (!p) return null;
    let m;
    try { m = this._c.move(p); } catch { return null; }
    if (!m) return null;
    const rec = { uci: uciOf(m), san: m.san };
    this._moves.push(rec);
    return rec;
  }

  /** Plays a move written in SAN ("Nf3", "exd5", "O-O"). Returns { uci, san } or null when it is not legal. */
  playSan(san) {
    let m;
    try { m = this._c.move(san); } catch { return null; }
    if (!m) return null;
    const rec = { uci: uciOf(m), san: m.san };
    this._moves.push(rec);
    return rec;
  }

  /** The position without the move counters (the first four FEN fields), for looking it up. */
  key() { return this._c.fen().split(' ').slice(0, 4).join(' '); }

  /** Takes back the last move. Returns it, or null at the start. */
  undo() {
    const m = this._c.undo();
    if (!m) return null;
    return this._moves.pop();
  }

  /** The moves so far: [{ uci, san }]. */
  moves() { return this._moves.slice(); }

  inCheck() { return this._c.inCheck(); }

  /** The square of the king to move when it is in check, else null. */
  checkSquare() {
    if (!this._c.inCheck()) return null;
    const turn = this._c.turn();
    const b = this._c.board();
    for (let r = 0; r < 8; r++) for (let f = 0; f < 8; f++) {
      const sq = b[r][f];
      if (sq && sq.type === 'k' && sq.color === turn) return FILES[f] + (8 - r);
    }
    return null;
  }

  /**
   * null while the game goes on. Otherwise { result, reason, winner }:
   * result "1-0", "0-1" or "1/2-1/2"; reason "checkmate", "stalemate", "repetition", "fifty-move" or
   * "insufficient"; winner "w", "b" or null. Draws by repetition and the fifty-move rule end the game
   * at once, without a claim.
   */
  outcome() {
    const c = this._c;
    if (c.isCheckmate()) {
      const winner = c.turn() === 'w' ? 'b' : 'w';
      return { result: winner === 'w' ? '1-0' : '0-1', reason: 'checkmate', winner };
    }
    if (c.isStalemate()) return draw('stalemate');
    if (c.isInsufficientMaterial()) return draw('insufficient');
    if (c.isThreefoldRepetition()) return draw('repetition');
    if (c.isDrawByFiftyMoves()) return draw('fifty-move');
    return null;
  }

  /** Everything a board needs to draw this position and take the next move. */
  snapshot() {
    const moves = this._moves;
    return {
      fen: this.fen(),
      start: this._start,
      turn: this.turn(),
      board: this.board(),
      legal: this.legal(),
      check: this.checkSquare(),
      last: moves.length ? moves[moves.length - 1].uci : null,
      moves: moves.map(m => m.uci),
      san: moves.map(m => m.san),
      outcome: this.outcome(),
    };
  }

  /** Counts leaf positions to a depth, through this interface only (for tests). */
  perft(depth) {
    if (depth === 0) return 1;
    const list = this.legal();
    if (depth === 1) return list.length;
    let n = 0;
    for (const m of list) {
      this.play(m.uci);
      n += this.perft(depth - 1);
      this.undo();
    }
    return n;
  }
}

function draw(reason) {
  return { result: '1/2-1/2', reason, winner: null };
}

function describe(m) {
  return {
    uci: uciOf(m),
    from: m.from,
    to: m.to,
    san: m.san,
    capture: Boolean(m.captured),
    promotion: m.promotion || null,
    castle: m.flags.includes('k') ? 'king' : m.flags.includes('q') ? 'queen' : null,
  };
}

/**
 * Reads a position someone pasted: a FEN, or a PGN (its moves, from its FEN tag or the usual start).
 * Returns { kind: "fen", start } or { kind: "pgn", start, moves, san, fens }, or { error } with one plain sentence.
 */
export function parsePosition(text) {
  const t = String(text || '').trim();
  if (!t) return { error: 'Paste a FEN or a PGN.' };
  const looksLikeFen = /^[pnbrqkPNBRQK1-8]+(\/[pnbrqkPNBRQK1-8]+){7}(\s|$)/.test(t);
  if (looksLikeFen) {
    // A FEN without counters or castling gets the usual ones.
    const parts = t.split(/\s+/);
    const fen = [parts[0], parts[1] || 'w', parts[2] || '-', parts[3] || '-', parts[4] || '0', parts[5] || '1'].join(' ');
    const v = validateFen(fen);
    if (!v.ok) return { error: 'That FEN does not describe a legal position.' };
    let c;
    try { c = new Chess(fen); } catch { return { error: 'That FEN does not describe a legal position.' }; }
    // The side that just moved cannot have left its own king in check: the king could be taken.
    const them = c.turn() === 'w' ? 'b' : 'w';
    const king = c.board().flat().find((p) => p && p.type === 'k' && p.color === them);
    if (!king || c.isAttacked(king.square, c.turn())) return { error: 'That FEN does not describe a legal position.' };
    if (c.isGameOver()) return { error: 'The game is already over in that position.' };
    return { kind: 'fen', start: c.fen() };
  }
  const c = new Chess();
  try { c.loadPgn(t); } catch { return { error: 'That is neither a FEN nor a PGN this app can read.' }; }
  const history = c.history({ verbose: true });
  const headers = c.getHeaders();
  let start = headers.FEN || START;
  try { start = new Chess(start).fen(); } catch { return { error: 'The PGN starts from a position that is not legal.' }; }
  if (!history.length && !headers.FEN) return { error: 'That is neither a FEN nor a PGN this app can read.' };
  const g = new Game(start);
  const fens = [g.fen()];
  for (const m of history) { g.play(uciOf(m)); fens.push(g.fen()); }
  return { kind: 'pgn', start, moves: g.moves().map(m => m.uci), san: g.moves().map(m => m.san), fens };
}
