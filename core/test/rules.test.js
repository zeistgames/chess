import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game, START } from '../rules.js';

// Perft counts from the Chess Programming Wiki (https://www.chessprogramming.org/Perft_Results).
test('perft from the start to depth 3', () => {
  const g = new Game();
  assert.equal(g.perft(1), 20);
  assert.equal(g.perft(2), 400);
  assert.equal(g.perft(3), 8902);
});

test('perft, Kiwipete (castling, pins, en passant, promotion)', () => {
  const g = new Game('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
  assert.equal(g.perft(1), 48);
  assert.equal(g.perft(2), 2039);
  assert.equal(g.perft(3), 97862);
});

test('perft, position 3 (en passant discovered checks along a rank)', () => {
  const g = new Game('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1');
  assert.equal(g.perft(1), 14);
  assert.equal(g.perft(2), 191);
  assert.equal(g.perft(3), 2812);
});

test('perft, position 5 (promotion with check)', () => {
  const g = new Game('rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8');
  assert.equal(g.perft(1), 44);
  assert.equal(g.perft(2), 1486);
  assert.equal(g.perft(3), 62379);
});

test('legal moves from a square, and illegal moves refused', () => {
  const g = new Game();
  assert.deepEqual(g.legalFrom('e2').map(m => m.uci).sort(), ['e2e3', 'e2e4']);
  assert.deepEqual(g.legalFrom('e7'), []); // not Black's turn
  assert.equal(g.play('e2e5'), null);
  assert.equal(g.play('nonsense'), null);
  assert.deepEqual(g.play('e2e4'), { uci: 'e2e4', san: 'e4' });
  assert.equal(g.turn(), 'b');
});

test('apply, undo and the move list', () => {
  const g = Game.fromMoves(['e2e4', 'e7e5', 'g1f3', 'b8c6']);
  assert.deepEqual(g.moves().map(m => m.san), ['e4', 'e5', 'Nf3', 'Nc6']);
  assert.equal(g.fen(), 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3');
  g.undo();
  assert.equal(g.moves().length, 3);
  assert.throws(() => Game.fromMoves(['e2e4', 'e2e4']));
});

test('castling, en passant and promotion are described', () => {
  const g = new Game('r3k2r/8/8/3pP3/8/8/p7/R3K2R w KQkq d6 0 1');
  const ucis = g.legal().map(m => m.uci);
  assert.ok(ucis.includes('e1g1') && ucis.includes('e1c1'));
  const ep = g.legal().find(m => m.uci === 'e5d6');
  assert.ok(ep && ep.capture);
  assert.equal(g.legal().find(m => m.uci === 'e1g1').castle, 'king');
  const p = new Game('8/P7/8/8/8/8/8/k6K w - - 0 1');
  assert.deepEqual(p.legalFrom('a7').map(m => m.uci).sort(), ['a7a8b', 'a7a8n', 'a7a8q', 'a7a8r']);
});

test('checkmate', () => {
  const g = Game.fromMoves(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
  assert.deepEqual(g.outcome(), { result: '0-1', reason: 'checkmate', winner: 'b' });
  assert.equal(g.checkSquare(), 'e1');
  assert.equal(g.legal().length, 0);
});

test('stalemate', () => {
  const g = new Game('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
  assert.equal(g.outcome().reason, 'stalemate');
  assert.equal(g.outcome().result, '1/2-1/2');
});

test('an en passant square counts toward repetition only when the capture is legal', () => {
  // After e2e4 the d4 pawn stands beside it but is pinned along the rank (king a4, rook h4): taking en passant would
  // open the rank. The position after e4 is the same position the shuffles return to, so the third time is a draw.
  const pinned = Game.fromMoves('e2e4 a4a5 g1f3 a5a4 f3g1 a4a5 g1f3 a5a4 f3g1'.split(' '), '8/8/8/8/k2p3R/8/4P3/4K1N1 w - - 0 1');
  assert.equal(pinned.outcome()?.reason, 'repetition');
  // With the capture legal, the first position differs, so the same moves reach it only twice.
  const free = Game.fromMoves('e2e4 e8d8 g1f3 d8e8 f3g1 e8d8 g1f3 d8e8 f3g1'.split(' '), '4k3/8/8/8/3p4/8/4P3/4K1N1 w - - 0 1');
  assert.equal(free.outcome(), null);
  free.play('e8d8'); free.play('g1f3'); free.play('d8e8'); free.play('f3g1');
  assert.equal(free.outcome()?.reason, 'repetition');
});

test('threefold repetition', () => {
  const g = Game.fromMoves(['g1f3', 'g8f6', 'f3g1', 'f6g8', 'g1f3', 'g8f6', 'f3g1']);
  assert.equal(g.outcome(), null);
  g.play('f6g8');
  assert.equal(g.outcome().reason, 'repetition');
});

test('fifty-move rule', () => {
  const g = new Game('8/8/8/8/8/2k5/8/K1R5 w - - 99 80');
  assert.equal(g.outcome(), null);
  g.play('c1c2');
  assert.equal(g.outcome().reason, 'fifty-move');
});

test('checkmate on the hundredth half-move is still checkmate', () => {
  const g = new Game('k7/8/1K6/8/8/8/8/7R w - - 99 80');
  g.play('h1h8');
  assert.equal(g.outcome().reason, 'checkmate');
});

test('insufficient material', () => {
  assert.equal(new Game('8/8/8/8/8/2k5/8/K1b5 w - - 0 1').outcome().reason, 'insufficient');
  assert.equal(new Game('8/8/8/8/8/2k5/8/K1n5 w - - 0 1').outcome().reason, 'insufficient');
  assert.equal(new Game('8/8/8/8/8/2k5/8/K1r5 w - - 0 1').outcome(), null);
});

test('snapshot has what a board needs', () => {
  const s = Game.fromMoves(['e2e4']).snapshot();
  assert.equal(s.board.length, 64);
  assert.equal(s.board[0], 'bR');
  assert.equal(s.board[63], 'wR');
  assert.equal(s.board[36], 'wP'); // e4
  assert.equal(s.turn, 'b');
  assert.equal(s.last, 'e2e4');
  assert.equal(s.legal.length, 20);
  assert.equal(s.start, START);
  assert.deepEqual(s.san, ['e4']);
});
