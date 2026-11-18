import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as levels from '../levels.js';

const elo = { id: 'sf', strength: { uci_elo: { min: 1320, max: 3190 } }, multipv: true };
const skill = { id: 'x', strength: { type: 'skill', min: 0, max: 20 }, multipv: true };
const plain = { id: 'p', strength: 'none', multipv: true };

test('an engine with UCI_Elo gets its own option, spread over its range', () => {
  const four = levels.settings(elo, 4, 7);
  assert.deepEqual(four.options, [['UCI_LimitStrength', 'true'], ['UCI_Elo', '1320'], ['MultiPV', '1']]);
  assert.equal(four.multipv, 1);
  const nine = levels.settings(elo, 9, 7);
  assert.equal(nine.options[1][1], String(Math.round(1320 + 1870 * 5 / 6)));
  assert.equal(levels.settings(elo, 10).options[0][1], 'false');
});

test('a strong engine is made easier at its lowest levels: weakest setting plus a pick among top moves', () => {
  const one = levels.settings(elo, 1, 7);
  assert.deepEqual(one.options, [['UCI_LimitStrength', 'true'], ['UCI_Elo', '1320'], ['MultiPV', '8']]);
  assert.ok(one.temperature > levels.settings(elo, 3, 7).temperature);
  assert.ok(levels.settings(elo, 3, 7).temperature > 0);
  const gentle = { id: 'm', strength: { uci_elo: { min: 600, max: 2600 } }, multipv: true };
  assert.equal(levels.settings(gentle, 1).multipv, 1);
  assert.equal(levels.settings(gentle, 1).options[1][1], '600');
});

test('an engine with a skill level gets it', () => {
  assert.deepEqual(levels.settings(skill, 1).options[0], ['Skill Level', '0']);
  assert.deepEqual(levels.settings(skill, 10).options[0], ['Skill Level', '20']);
});

test('an engine without a strength option gets nodes and a pick among top moves', () => {
  const low = levels.settings(plain, 1, 3);
  const high = levels.settings(plain, 10, 3);
  assert.equal(low.multipv, 8);
  assert.ok(low.temperature > high.temperature);
  assert.equal(high.multipv, 1);
  assert.ok(low.nodes < high.nodes);
  assert.deepEqual(low.options, [['MultiPV', '8']]);
});

test('node budgets rise with the level', () => {
  for (let l = 2; l <= 10; l++) assert.ok(levels.settings(plain, l).nodes > levels.settings(plain, l - 1).nodes);
});

test('levels are clamped to 1..10', () => {
  assert.equal(levels.settings(plain, 0).level, 1);
  assert.equal(levels.settings(plain, 42).level, 10);
  assert.equal(levels.clamp('x'), levels.FIRST);
});

const lines = [
  { multipv: 1, cp: 40, move: 'e2e4' },
  { multipv: 2, cp: 30, move: 'd2d4' },
  { multipv: 3, cp: -20, move: 'g1f3' },
  { multipv: 4, cp: -400, move: 'f2f3' },
];

test('the pick is repeatable from the seed and ply', () => {
  const s = levels.settings(plain, 2, 12345);
  const a = levels.choose(lines, 'e2e4', s, 5);
  const b = levels.choose(lines, 'e2e4', s, 5);
  assert.equal(a, b);
});

test('the pick varies across seeds at a low level, and favors good moves', () => {
  const counts = {};
  for (let seed = 1; seed <= 400; seed++) {
    const m = levels.choose(lines, 'e2e4', levels.settings(plain, 2, seed), 0);
    counts[m] = (counts[m] || 0) + 1;
  }
  assert.ok(Object.keys(counts).length >= 3);
  assert.ok(counts['e2e4'] > (counts['f2f3'] || 0));
});

test('at the top level, or with a strength option, the best move is played', () => {
  assert.equal(levels.choose(lines, 'e2e4', levels.settings(plain, 10, 9), 0), 'e2e4');
  assert.equal(levels.choose(lines, 'e2e4', levels.settings(elo, 1, 9), 0), 'e2e4');
});

test('a forced mate is always played, and moves into a mate the best line avoids are not', () => {
  const mating = [{ multipv: 1, mate: 2, move: 'h5f7' }, { multipv: 2, cp: 300, move: 'e2e4' }];
  for (let seed = 1; seed < 50; seed++) assert.equal(levels.choose(mating, 'h5f7', levels.settings(plain, 1, seed), 0), 'h5f7');
  const blunder = [{ multipv: 1, cp: 10, move: 'a2a3' }, { multipv: 2, mate: -1, move: 'f2f3' }];
  for (let seed = 1; seed < 50; seed++) assert.equal(levels.choose(blunder, 'a2a3', levels.settings(plain, 1, seed), 0), 'a2a3');
});

test('adaptive: starts at the lowest level, takes big steps first, then small ones', () => {
  assert.equal(levels.FIRST, 1);
  assert.deepEqual(levels.adapt(undefined, 'win'), { level: 4, step: 3 });
  assert.deepEqual(levels.adapt(4, 'win', 3), { level: 7, step: 3 });
  assert.deepEqual(levels.adapt(7, 'loss', 3), { level: 4, step: 2 });
  assert.deepEqual(levels.adapt(4, 'win', 2), { level: 6, step: 2 });
  assert.deepEqual(levels.adapt(6, 'loss', 2), { level: 4, step: 1 });
  assert.deepEqual(levels.adapt(5, 'draw', 1), { level: 5, step: 1 });
  assert.deepEqual(levels.adapt(5, 'win', 1), { level: 6, step: 1 });
  assert.deepEqual(levels.adapt(10, 'win', 3), { level: 10, step: 3 });
  assert.deepEqual(levels.adapt(1, 'loss', 3), { level: 1, step: 2 });
  assert.deepEqual(levels.adapt(4, 'win', 99), { level: 7, step: 3 });
});

test('a rating set by hand goes to the engine as its own option, inside its range', () => {
  const s = levels.atRating(elo, 1500, 9);
  assert.deepEqual(s.options, [['UCI_LimitStrength', 'true'], ['UCI_Elo', '1500'], ['MultiPV', '1']]);
  assert.equal(s.rating, 1500);
  assert.equal(s.multipv, 1);
  assert.equal(levels.atRating(elo, 100).rating, 1320);
  assert.equal(levels.atRating(elo, 9999).rating, 3190);
  assert.equal(levels.atRating(elo, 9999).level, 10);
  assert.equal(levels.atRating(plain, 1500), null);
});

test('pace: a share of the clock, quick in the opening, on forced moves and recaptures, never a flag', () => {
  const clock = (ms, inc = 0) => ({ wtime: ms, btime: ms, winc: inc, binc: inc, turn: 'b' });
  const avg = info => { let t = 0; for (let seed = 1; seed <= 400; seed++) t += levels.pace({ ...info, seed }); return t / 400; };
  const mid = avg({ clock: clock(60000), ply: 31 });
  assert.ok(mid > 900 && mid < 2600, 'a 1-minute game: about a second or two in the middlegame, was ' + mid);
  assert.ok(avg({ clock: clock(60000), ply: 3 }) < mid / 2, 'the opening is quick');
  assert.ok(avg({ clock: clock(60000), ply: 31, forced: true }) < mid / 3, 'a forced move is quick');
  assert.ok(avg({ clock: clock(60000), ply: 31, recapture: true }) < mid * 0.6, 'a recapture is quick');
  assert.ok(avg({ clock: clock(180000, 2000), ply: 31 }) > mid * 2, 'more time, longer thinks');
  for (let seed = 1; seed <= 400; seed++) for (const own of [200, 3000, 20000, 600000]) {
    const p = levels.pace({ clock: clock(own), ply: 40, seed });
    assert.ok(p <= own * 0.125 + 1 && p <= 16000, 'never more than an eighth of its time');
  }
  // A whole bullet game never runs the engine out of time through pacing alone.
  let own = 60000;
  for (let ply = 1; ply < 400; ply += 2) own -= levels.pace({ clock: clock(own), ply, seed: 9 });
  assert.ok(own > 0);
  assert.equal(levels.pace({ clock: clock(60000), ply: 31, seed: 5 }), levels.pace({ clock: clock(60000), ply: 31, seed: 5 }));
});

test('pace: with no clock, a short varied pause', () => {
  const seen = new Set();
  for (let seed = 1; seed <= 200; seed++) {
    const p = levels.pace({ clock: null, ply: 30, seed });
    assert.ok(p >= 400 && p <= 2200);
    seen.add(p);
  }
  assert.ok(seen.size > 20);
});

test('fitted: MultiPV never exceeds the number of legal moves', () => {
  const s = levels.settings({ id: 'x', strength: { type: 'none' } }, 1, 7);
  assert.ok(s.multipv > 1);
  const f = levels.fitted(s, 1);
  assert.equal(f.multipv, 1);
  assert.deepEqual(f.options.find(o => o[0] === 'MultiPV'), ['MultiPV', '1']);
  assert.equal(levels.fitted(s, 40), s);
});

test('settings: the Zeist engine is sent the game\'s seed', () => {
  const m = { id: 'zeist', strength: { type: 'skill', option: 'Level', min: 1, max: 8 }, multipv: false };
  assert.deepEqual(levels.settings(m, 3, 12345).options.find(o => o[0] === 'Seed'), ['Seed', '12345']);
  assert.equal(levels.settings({ id: 'clover', strength: { type: 'none' } }, 3, 12345).options.find(o => o[0] === 'Seed'), undefined);
});

test('a pack can give its own node limit for each level', () => {
  const m = { id: 'zeist', strength: { type: 'skill', option: 'Level', min: 1, max: 10, nodes: [20000, 20000, 20000, 20000, 60000, 20000, 100000, 100000, 250000, 1500000] }, multipv: false };
  for (let l = 1; l <= 10; l++) {
    const s = levels.settings(m, l, 7);
    assert.deepEqual(s.options[0], ['Level', String(l)]);
    assert.equal(s.nodes, m.strength.nodes[l - 1]);
  }
  assert.equal(levels.settings({ id: 'x', strength: { type: 'skill', min: 0, max: 20 } }, 1).nodes, 1500);
});
