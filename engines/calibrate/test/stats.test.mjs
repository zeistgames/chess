// SPDX-License-Identifier: AGPL-3.0-or-later
// node --test engines/calibrate/test/*.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { expected, mle, interval, fit, verdict, nextRating, outOfOrder } from '../stats.mjs';

const at = (opp, wins, draws, losses) => [
  ...Array(wins).fill({ opp, score: 1 }),
  ...Array(draws).fill({ opp, score: 0.5 }),
  ...Array(losses).fill({ opp, score: 0 }),
];
const near = (a, b, tol = 0.01) => assert.ok(Math.abs(a - b) <= tol, `${a} is not within ${tol} of ${b}`);

test('expected score follows the logistic curve', () => {
  near(expected(1500, 1500), 0.5, 1e-12);
  near(expected(1900, 1500), 1 / (1 + 10 ** -1), 1e-12); // 400 points ahead: 10 to 1
  near(expected(1500, 1900) + expected(1900, 1500), 1, 1e-12);
});

test('an even score against one opponent rates at that opponent', () => {
  near(mle(at(1500, 10, 0, 10)), 1500, 1e-6);
  near(mle(at(1500, 0, 20, 0)), 1500, 1e-6);
});

test('a 75% score against one opponent rates 400 * log10(3) above it', () => {
  near(mle(at(1500, 15, 0, 5)), 1500 + 400 * Math.log10(3), 1e-6);
  near(mle(at(1500, 10, 10, 0)), 1500 + 400 * Math.log10(3), 1e-6); // draws count as half points
});

test('even scores against opponents placed symmetrically rate at their middle', () => {
  near(mle([...at(1400, 3, 0, 3), ...at(1600, 3, 0, 3)]), 1500, 1e-6);
});

test('the maximum likelihood rating is where expected and actual scores agree', () => {
  const games = [...at(1200, 4, 1, 1), ...at(1500, 2, 2, 3), ...at(1800, 0, 1, 5)];
  const r = mle(games);
  const exp = games.reduce((a, g) => a + expected(r, g.opp), 0);
  const act = games.reduce((a, g) => a + g.score, 0);
  near(exp, act, 1e-6);
});

test('the profile likelihood interval for 20 of 40 against one opponent', () => {
  // 20 ln p + 20 ln(1 - p) drops by 3.841 / 2 where 4p(1 - p) = exp(-1.92073 / 20).
  const q = Math.exp(-3.841458820694124 / 2 / 20);
  const p = (1 + Math.sqrt(1 - q)) / 2;
  const half = 400 * Math.log10(p / (1 - p));
  near(half, 108.5, 0.1);
  const [lo, hi] = interval(at(1500, 20, 0, 20));
  near(lo, 1500 - half, 1e-3);
  near(hi, 1500 + half, 1e-3);
});

test('a perfect score has an infinite estimate and a finite lower bound', () => {
  const games = at(2600, 12, 0, 0);
  assert.equal(mle(games), Infinity);
  const [lo, hi] = interval(games);
  assert.equal(hi, Infinity);
  // 12 ln p = -1.92073 at the lower bound.
  const p = Math.exp(-3.841458820694124 / 2 / 12);
  near(lo, 2600 + 400 * Math.log10(p / (1 - p)), 1e-3);
  assert.equal(mle(at(600, 0, 0, 5)), -Infinity);
  assert.equal(interval(at(600, 0, 0, 5))[0], -Infinity);
  assert.equal(mle([]), null);
});

test('verdicts: above the scale, below it, rated, still playing', () => {
  assert.equal(verdict(at(2600, 12, 0, 0)).status, 'above');
  assert.equal(verdict(at(2600, 3, 0, 0)).status, 'playing'); // too few games at the top
  assert.equal(verdict(at(600, 0, 1, 12)).status, 'below');
  assert.equal(verdict([...at(1400, 10, 0, 10), ...at(1600, 10, 0, 10)]).status, 'rated');
  assert.equal(verdict(at(1500, 6, 0, 6)).status, 'playing');
  const f = fit(at(1500, 15, 0, 5));
  assert.equal(f.games, 20);
  assert.equal(f.score, 15);
});

test('the staircase moves toward 50% and its step halves on reversals', () => {
  assert.equal(nextRating([], 1234), 1230);
  assert.equal(nextRating([{ rating: 1200, score: 2 }], 1200), 1500);
  assert.equal(nextRating([{ rating: 1200, score: 1.5 }], 1200), 1350);
  assert.equal(nextRating([{ rating: 1200, score: 1 }], 1200), 1200);
  // up 300, then down: step halves to 150
  assert.equal(nextRating([{ rating: 1200, score: 2 }, { rating: 1500, score: 0 }], 1200), 1350);
  // held to Maia's range
  assert.equal(nextRating([{ rating: 2500, score: 2 }], 2500), 2600);
  assert.equal(nextRating([{ rating: 700, score: 0 }], 700), 600);
});

test('levels out of order are reported', () => {
  const levels = [
    { level: 1, status: 'rated', best: 900, lo: 850, hi: 950 },
    { level: 2, status: 'rated', best: 1200, lo: 1100, hi: 1300 },
    { level: 3, status: 'rated', best: 1000, lo: 900, hi: 1150 },
    { level: 4, status: 'above', best: Infinity, lo: 2700, hi: Infinity },
    { level: 5, status: 'rated', best: 2500, lo: 2400, hi: 2600 },
  ];
  assert.deepEqual(outOfOrder(levels).map(x => [x.level, x.clear]), [[3, false], [5, true]]);
});
