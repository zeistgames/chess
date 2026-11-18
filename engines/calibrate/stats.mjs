// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The rating math for calibration, with no engine code, so it can be tested on its own.
//
// Model: the usual logistic (Elo) curve. A player rated r scores, on average, against an opponent rated o:
//   p(r, o) = 1 / (1 + 10^((o - r) / 400))
// Each game's score s (1, 0.5 or 0) is treated as a fractional success, so the log likelihood of r is
//   LL(r) = sum of s * ln p + (1 - s) * ln(1 - p)
// The rating is the r that maximizes LL; the 95% interval is every r with 2 * (LL(best) - LL(r)) <= 3.841
// (a profile likelihood interval, which stays honest when the score is lopsided, unlike best +- 1.96 * SE).
// A perfect or zero score has no finite best rating: the estimate is +Infinity or -Infinity and only one end
// of the interval is finite.

const K = Math.LN10 / 400;
const CHI2_95 = 3.841458820694124;

export const SCALE = { min: 600, max: 2600 };

/** Expected score of a player rated r against an opponent rated o. */
export function expected(r, o) {
  return 1 / (1 + Math.pow(10, (o - r) / 400));
}

/** games: [{ opp, score }]. The log likelihood of rating r. */
export function logLik(r, games) {
  let ll = 0;
  for (const g of games) {
    const p = expected(r, g.opp);
    if (g.score > 0) ll += g.score * Math.log(p);
    if (g.score < 1) ll += (1 - g.score) * Math.log(1 - p);
  }
  return ll;
}

/** The maximum likelihood rating, or +-Infinity for a perfect or zero score, or null with no games. */
export function mle(games) {
  const n = games.length;
  if (!n) return null;
  const total = games.reduce((a, g) => a + g.score, 0);
  if (total <= 0) return -Infinity;
  if (total >= n) return Infinity;
  const mean = games.reduce((a, g) => a + g.opp, 0) / n;
  let r = mean + 400 * Math.log10(total / (n - total));
  for (let i = 0; i < 200; i++) {
    let grad = 0, hess = 0;
    for (const g of games) {
      const p = expected(r, g.opp);
      grad += g.score - p;
      hess += p * (1 - p);
    }
    // The log likelihood is concave, so Newton converges; the step is capped to keep it steady far out.
    const step = Math.max(-400, Math.min(400, grad / (K * hess)));
    r += step;
    if (Math.abs(step) < 1e-7) break;
  }
  return r;
}

/** Bisection for f(x) = 0 on [a, b], where f changes sign. */
function root(f, a, b) {
  let fa = f(a);
  for (let i = 0; i < 200; i++) {
    const m = (a + b) / 2;
    const fm = f(m);
    if ((fm < 0) === (fa < 0)) { a = m; fa = fm; } else b = m;
    if (b - a < 1e-6) break;
  }
  return (a + b) / 2;
}

/** The 95% profile likelihood interval as [lo, hi]; an end with no bound is -Infinity or Infinity. */
export function interval(games, best = mle(games)) {
  if (best == null) return null;
  const lo0 = Math.min(...games.map(g => g.opp)) - 5000;
  const hi0 = Math.max(...games.map(g => g.opp)) + 5000;
  // At an infinite best the supremum of LL is 0 (every game scored as it was).
  const top = Number.isFinite(best) ? logLik(best, games) : 0;
  const f = r => logLik(r, games) - (top - CHI2_95 / 2);
  const lo = best === -Infinity ? -Infinity : root(f, lo0, Number.isFinite(best) ? best : hi0);
  const hi = best === Infinity ? Infinity : root(f, Number.isFinite(best) ? best : lo0, hi0);
  return [lo, hi];
}

/** Everything reported for one set of games. */
export function fit(games) {
  const n = games.length;
  const score = games.reduce((a, g) => a + g.score, 0);
  const best = mle(games);
  const ci = interval(games, best);
  return { games: n, score, best, lo: ci ? ci[0] : null, hi: ci ? ci[1] : null };
}

/**
 * Where a level stands. games: [{ opp, score }] for its finished games.
 * "above" / "below": the whole 95% interval is past Maia's top (or bottom) and enough games were played there.
 * "rated": enough games and a narrow enough interval, or the game cap was reached.
 * "playing": not yet decided.
 */
export function verdict(games, o = {}) {
  // CAL_GAMES: play at least this many games a level (and at most half as many again), for a tighter interval.
  const want = Number(process.env.CAL_GAMES) || 0;
  const { minGames = want || 40, maxGames = want ? Math.round(want * 1.5) : 64, width = want ? 0 : 240, edgeGames = 12, scale = SCALE } = o;
  const f = fit(games);
  const atTop = games.filter(g => g.opp >= scale.max).length;
  const atBottom = games.filter(g => g.opp <= scale.min).length;
  let status = 'playing';
  if (f.games && atTop >= edgeGames && f.lo > scale.max) status = 'above';
  else if (f.games && atBottom >= edgeGames && f.hi < scale.min) status = 'below';
  else if (f.games >= minGames && f.hi - f.lo <= width) status = 'rated';
  else if (f.games >= maxGames) status = 'rated';
  return { ...f, status, atTop, atBottom };
}

/**
 * The staircase: the Maia rating for the next pair, from the pairs already played.
 * pairs: [{ rating, score }] in order, score the engine's points from the pair (0 to 2).
 * A pair won 2-0 moves the rating up a full step, 1.5 half a step, 1 not at all. The step starts at step0 and
 * halves each time the direction reverses, down to minStep, so the rating settles where the engine scores 50%.
 */
export function nextRating(pairs, start, o = {}) {
  const { step0 = 300, minStep = 50, scale = SCALE } = o;
  const clamp = r => Math.min(scale.max, Math.max(scale.min, Math.round(r / 10) * 10));
  let r = clamp(start), step = step0, last = 0;
  for (const p of pairs) {
    const d = p.score - 1; // -1 .. 1
    if (d === 0) { r = clamp(p.rating); continue; }
    const dir = Math.sign(d);
    if (last && dir !== last) step = Math.max(minStep, step / 2);
    last = dir;
    r = clamp(p.rating + step * d);
  }
  return r;
}

/** Levels whose estimate is lower than the level below: [{ level, below, best, prevBest, clear }]. */
export function outOfOrder(levels) {
  const out = [];
  for (let i = 1; i < levels.length; i++) {
    const a = levels[i - 1], b = levels[i];
    const va = rank(a), vb = rank(b);
    if (va == null || vb == null) continue;
    if (vb < va) out.push({ level: b.level, below: a.level, best: b.best, prevBest: a.best, clear: b.hi < a.lo });
  }
  return out;
}

function rank(l) {
  if (l.status === 'above') return Infinity;
  if (l.status === 'below') return -Infinity;
  return Number.isFinite(l.best) ? l.best : null;
}
