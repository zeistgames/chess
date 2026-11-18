// Levels 1 to 10 for any engine, and adaptive difficulty.
//
// An engine with its own strength option (UCI_Elo or a skill level) gets that option, spread over its range.
// An engine without one gets a node budget and a seeded choice among its top moves (MultiPV), weighted by score:
// low levels look at more moves and accept bigger losses. Every engine also gets a node budget per level, so a
// search ends in reasonable time on a phone and the same position at the same level gives the same move.
// Levels are unrated until measured.

export const LOWEST = 1;
export const HIGHEST = 10;
/** Where adaptive play starts against an engine you have not played. */
export const FIRST = 1;
/** How far the level moves after a first game against an engine. It shrinks as the level settles. */
export const FIRST_STEP = 3;

// Node budgets by level (index 0 is level 1).
const NODES = [1500, 4000, 10000, 25000, 60000, 120000, 250000, 500000, 900000, 1500000];
// Without a strength option: how many top moves to consider, and how far below the best a move may score
// (in centipawns) and still have a real chance of being picked.
const MULTIPV = [8, 6, 5, 4, 3, 3, 3, 2, 2, 1];
const TEMPERATURE = [500, 300, 180, 100, 70, 48, 32, 20, 10, 0];
// An engine whose own weakest setting is still above this (Stockfish's is 1320) is too strong for someone starting
// out. Its lowest EASY levels hold the engine at its weakest setting and add the seeded choice among top moves;
// the remaining levels spread its own range.
const EASY_FLOOR = 900;
const EASY = 3;

export function clamp(level) {
  const n = Math.round(Number(level));
  if (!Number.isFinite(n)) return FIRST;
  return Math.min(HIGHEST, Math.max(LOWEST, n));
}

/**
 * The engine's strength option, read from a pack manifest, as { kind: "uci_elo" | "skill" | "none", min, max }.
 * Accepts { uci_elo: { min, max } }, { skill: { min, max } }, { type: "uci_elo", min, max } and "none".
 */
export function strengthOf(manifest) {
  const s = manifest && manifest.strength;
  if (!s || s === 'none') return { kind: 'none' };
  if (typeof s === 'object') {
    if (s.uci_elo) return { kind: 'uci_elo', min: +s.uci_elo.min, max: +s.uci_elo.max, option: s.uci_elo.option };
    if (s.skill) return { kind: 'skill', min: +s.skill.min, max: +s.skill.max, option: s.skill.option };
    const kind = s.type || s.kind;
    if (kind === 'uci_elo' || kind === 'skill') return { kind, min: +s.min, max: +s.max, option: s.option, nodes: Array.isArray(s.nodes) ? s.nodes : undefined };
  }
  return { kind: 'none' };
}

/**
 * What to send the engine for one game at one level: UCI options, the node budget, MultiPV and how to pick.
 * The seed makes the pick among top moves repeatable: the same game, seed and position give the same move.
 */
export function settings(manifest, level, seed = 1) {
  const L = clamp(level);
  const i = L - 1;
  const strength = strengthOf(manifest);
  const t = i / (HIGHEST - LOWEST);
  const options = [];
  let multipv = 1;
  let temperature = 0;
  if (strength.kind === 'uci_elo') {
    const easy = strength.min > EASY_FLOOR && !(manifest && manifest.multipv === false);
    const u = easy ? Math.max(0, L - EASY - 1) / (HIGHEST - EASY - 1) : t;
    const elo = Math.round(strength.min + (strength.max - strength.min) * u);
    if (L === HIGHEST) options.push(['UCI_LimitStrength', 'false']);
    else options.push(['UCI_LimitStrength', 'true'], [strength.option || 'UCI_Elo', String(elo)]);
    if (easy && L <= EASY) {
      multipv = MULTIPV[i];
      temperature = TEMPERATURE[i];
    }
  } else if (strength.kind === 'skill') {
    options.push([strength.option || 'Skill Level', String(Math.round(strength.min + (strength.max - strength.min) * t))]);
  } else {
    multipv = manifest && manifest.multipv === false ? 1 : MULTIPV[i];
    temperature = multipv > 1 ? TEMPERATURE[i] : 0;
  }
  if (multipv > 1) options.push(['MultiPV', String(multipv)]);
  else if (manifest && manifest.multipv) options.push(['MultiPV', '1']);
  // The Zeist engine draws its variety from a Seed option: each game sends its own, so games differ.
  if (manifest && (manifest.seed === true || manifest.id === 'zeist')) options.push(['Seed', String(seed >>> 0)]);
  return {
    level: L,
    strength: strength.kind,
    options,
    // A pack may give its own node limit for each level (the Zeist engine does: its levels are set by depth).
    nodes: strength.nodes && strength.nodes[i] > 0 ? strength.nodes[i] : NODES[i],
    multipv,
    temperature,
    seed: seed >>> 0,
  };
}

/**
 * What to send an engine that takes a rating directly (UCI_Elo), for players who want to set it themselves.
 * The number is on the engine's own scale. Returns null for an engine with no such option.
 */
export function atRating(manifest, rating, seed = 1) {
  const strength = strengthOf(manifest);
  if (strength.kind !== 'uci_elo') return null;
  const elo = Math.min(strength.max, Math.max(strength.min, Math.round(Number(rating)) || strength.min));
  const t = strength.max > strength.min ? (elo - strength.min) / (strength.max - strength.min) : 1;
  const i = Math.round(t * (HIGHEST - LOWEST));
  const options = [['UCI_LimitStrength', 'true'], [strength.option || 'UCI_Elo', String(elo)]];
  if (manifest && manifest.multipv) options.push(['MultiPV', '1']);
  return { level: i + 1, rating: elo, strength: 'uci_elo', options, nodes: NODES[i], multipv: 1, temperature: 0, seed: seed >>> 0 };
}

/** A small seeded generator (mulberry32). */
export function random(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A mate score in centipawns, so mates sort above everything and sooner mates above later ones. */
function value(line) {
  if (line.mate != null) return line.mate > 0 ? 100000 - line.mate * 100 : -100000 - line.mate * 100;
  return line.cp == null ? 0 : line.cp;
}

/**
 * Picks the move to play. lines are the engine's final MultiPV lines: [{ multipv, cp, mate, move }].
 * With one line, or no temperature, it is the engine's best move. Otherwise each line is weighted by how far
 * it scores below the best, and the seed (mixed with the ply) chooses. A move that loses to a forced mate
 * the best line avoids is never picked.
 */
export function choose(lines, bestmove, s, ply = 0) {
  const usable = (lines || []).filter(l => l && l.move);
  if (!s || s.multipv <= 1 || s.temperature <= 0 || usable.length < 2) return bestmove;
  const sorted = usable.slice().sort((a, b) => value(b) - value(a)).slice(0, s.multipv);
  const best = value(sorted[0]);
  const pool = sorted.filter(l => !(l.mate != null && l.mate < 0 && best > -100000 + 10000));
  if (best >= 100000 - 10000) return sorted[0].move; // a forced mate is always played
  const weights = pool.map(l => Math.exp(-(best - value(l)) / s.temperature));
  const total = weights.reduce((a, b) => a + b, 0);
  const r = random((s.seed ^ Math.imul(ply + 1, 0x9E3779B1)) >>> 0)() * total;
  let acc = 0;
  for (let k = 0; k < pool.length; k++) {
    acc += weights[k];
    if (r < acc) return pool[k].move;
  }
  return pool[pool.length - 1].move;
}

/**
 * Adaptive difficulty. Play starts easy and finds the player's level quickly: a win moves up by the step, a loss
 * moves down by it, a draw stays. The step starts at FIRST_STEP and shrinks by one after every loss or draw, down
 * to one level, so the first games take big strides and later games small ones.
 * result is "win", "loss" or "draw", from the player's side. level is the level of the game just played, or
 * undefined for an engine never played (then the game was at FIRST). Returns { level, step } for the next game.
 */
export function adapt(level, result, step) {
  const L = level == null ? FIRST : clamp(level);
  let S = Math.round(Number(step));
  if (!Number.isFinite(S) || S < 1) S = FIRST_STEP;
  S = Math.min(S, FIRST_STEP);
  if (result === 'win') return { level: clamp(L + S), step: S };
  if (result === 'loss') return { level: clamp(L - S), step: Math.max(1, S - 1) };
  return { level: L, step: Math.max(1, S - 1) };
}

/**
 * How long the engine should take over a move, in milliseconds, so that it answers like a person across the board
 * rather than at once. Engines find their move in a moment; without this a clock never matters.
 * info: { clock: { wtime, btime, winc, binc, turn } or null, ply (moves played so far), forced (only one legal
 * move), recapture (it takes back on the square just moved to), seed }.
 * With a clock: a share of its own time, as if about forty moves remain, quick in the opening, on forced moves and
 * recaptures, now and then a long think, faster as its time runs low; never more than an eighth of what it has.
 * With no clock: a short, varied pause. The same seed and ply always give the same pace.
 */
export function pace(info) {
  const ply = info.ply || 0;
  const r = random(((info.seed >>> 0) ^ Math.imul(ply + 7, 0x85EBCA6B)) >>> 0);
  let k = 0.55 + r() * 0.9;                       // ordinary variety
  if (ply >= 16 && !info.forced && !info.recapture && r() < 0.12) k *= 2.2; // a long think
  if (ply < 10) k *= 0.3; else if (ply < 20) k *= 0.65;
  if (info.forced) k *= 0.2; else if (info.recapture) k *= 0.4;
  const c = info.clock;
  if (!c) return Math.round(Math.min(2200, Math.max(400, 900 * k)));
  const own = Math.max(0, Number(c.turn === 'b' ? c.btime : c.wtime) || 0);
  const inc = Math.max(0, Number(c.turn === 'b' ? c.binc : c.winc) || 0);
  const base = Math.min(7000, own / 40 + inc * 0.6);
  const floor = own < 10000 ? 120 : 300;
  return Math.round(Math.max(0, Math.min(own * 0.125, 16000, Math.max(floor, base * k))));
}

/**
 * The same settings for a position with only `legal` moves to choose from: MultiPV never asks for more lines than
 * there are moves. Clover, asked for more, answers with moves that do not exist and then stops.
 */
export function fitted(s, legal) {
  if (!s || !(s.multipv > legal) || legal < 1) return s;
  return { ...s, multipv: legal, options: (s.options || []).map(o => (o[0] === 'MultiPV' ? ['MultiPV', String(legal)] : o)) };
}
