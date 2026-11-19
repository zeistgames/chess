import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parsePosition, Game, START } from '../rules.js';
import { opening } from '../openings.js';

test('a FEN is read, with missing fields filled in', () => {
  const r = parsePosition('8/8/8/4k3/8/8/4P3/4K3 w');
  assert.equal(r.kind, 'fen');
  assert.equal(r.start, '8/8/8/4k3/8/8/4P3/4K3 w - - 0 1');
  assert.equal(new Game(r.start).turn(), 'w');
});

test('a PGN is read with every position along it', () => {
  const r = parsePosition('[Event "x"]\n\n1. e4 c5 2. Nf3 d6 3. d4 cxd4 *');
  assert.equal(r.kind, 'pgn');
  assert.equal(r.start, START);
  assert.deepEqual(r.moves, ['e2e4', 'c7c5', 'g1f3', 'd7d6', 'd2d4', 'c5d4']);
  assert.equal(r.san[5], 'cxd4');
  assert.equal(r.fens.length, 7);
  // With comments and clock times, as this app writes it.
  const ours = parsePosition('1. f3 {[%clk 0:03:00.0]} e5 {[%clk 0:02:59.4]} 2. g4 {[%clk 0:02:58.2]} *');
  assert.deepEqual(ours.moves, ['f2f3', 'e7e5', 'g2g4']);
  // From a FEN tag.
  const set = parsePosition('[SetUp "1"]\n[FEN "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"]\n\n1. e4 Kd7 *');
  assert.equal(set.start, '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1');
  assert.deepEqual(set.moves, ['e2e4', 'e8d7']);
});

test('a position where the side that just moved is in check is refused', () => {
  assert.equal(parsePosition('k6R/8/8/8/8/8/8/K7 w - - 0 1').error, 'That FEN does not describe a legal position.');
  // The same pieces with Black to move is an ordinary check.
  assert.equal(parsePosition('k6R/8/8/8/8/8/8/K7 b - - 0 1').kind, 'fen');
});

test('what cannot be read gets one plain sentence', () => {
  for (const bad of ['', 'hello there', '8/8/8/8/8/8/8/8 w - - 0 1', 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x', '1. e4 e5 2. Ke3 Qh4 3. Zz9']) {
    const r = parsePosition(bad);
    assert.ok(r.error && /\.$/.test(r.error) && !r.kind, `${JSON.stringify(bad)} -> ${JSON.stringify(r)}`);
  }
  assert.match(parsePosition('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1').error, /over/); // stalemate already
});

test('openings are named by position, including transpositions', async () => {
  assert.equal((await opening(['e2e4', 'c7c5'])).name, 'Sicilian Defense');
  assert.equal((await opening(['e2e4', 'c7c5'])).eco, 'B20');
  const najdorf = await opening(['e2e4', 'c7c5', 'g1f3', 'd7d6', 'd2d4', 'c5d4', 'f3d4', 'g8f6', 'b1c3', 'a7a6']);
  assert.match(najdorf.name, /Najdorf/);
  // Out of the book: the last name stays.
  const out = await opening(['e2e4', 'c7c5', 'a2a3', 'h7h6', 'h2h3']);
  assert.match(out.name, /^Sicilian Defense/);
  assert.equal(await opening([]), null);
  // The same position by another order of moves.
  const a = await opening(['g1f3', 'd7d5', 'd2d4']);
  const b = await opening(['d2d4', 'd7d5', 'g1f3']);
  assert.equal(a.name, b.name);
});
