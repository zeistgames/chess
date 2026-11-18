#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Finds the rating of each level of one engine on Maia's scale.
//
//   node engines/calibrate/run.mjs <engine> [--levels 1-10 | 1,4,7] [--data DIR]
//
// For each level, in order: games are played in pairs (the engine with white, then with black, from the same
// opening) against Maia at one rating. After each pair a staircase (stats.nextRating) moves Maia's rating
// toward where the engine scores 50%, with steps that halve when the direction turns. A level is done when
// stats.verdict says so: about 40 games with a 95% interval no wider than 240 points, at most 64 games, or
// clear evidence that it is above Maia 2600 or below Maia 600.
//
// Every game is appended to DIR/games/<engine>.jsonl as it finishes. Running again resumes: finished games
// are read back, the staircase is replayed from them, and play goes on from there. A game whose worker
// dies, aborts or times out is recorded as a crash, not as a result, both workers are restarted and the game
// is played again; after 3 crashes in one game it is skipped, and after 10 skipped games (or 40 crashes) in
// one level the level is given up.
//
// DIR defaults to engines/build/calibration (git-ignored).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as levels from '../../core/levels.js';
import { Player, calibrationGame, manifestOf } from './play.mjs';
import { verdict, nextRating, SCALE } from './stats.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const DEFAULT_DATA = path.join(here, '..', 'build', 'calibration');
const GAME_CRASHES = 3;
// A level is given up after this many games skipped (each crashed GAME_CRASHES times) or this many crashes.
const LEVEL_SKIPS = 10;
const LEVEL_CRASHES = 40;
// An engine whose games at a level average more than this is left for later: higher levels only get slower.
const SLOW_MINUTES = 20;

export function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  const out = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try { out.push(JSON.parse(line)); } catch { /* a line cut short by a stop: ignore it */ }
  }
  return out;
}

/** The games of one level that count, as { opp, score } for stats. */
export function counted(records, level) {
  return records.filter(r => r.level === level && r.result && !r.crash && !r.skipped).map(r => ({ opp: r.maia, score: r.score }));
}

/** Pairs of one level from its records: Map pair -> { rating, w, b, crashes: { w, b } }. */
function pairsOf(records, level) {
  const pairs = new Map();
  for (const r of records) {
    if (r.level !== level || r.pair == null) continue;
    const p = pairs.get(r.pair) || { rating: r.maia, w: null, b: null, crashes: { w: 0, b: 0 } };
    if (r.crash) p.crashes[r.color]++;
    else if (r.skipped) p[r.color] = { skipped: true };
    else if (r.result) p[r.color] = r;
    pairs.set(r.pair, p);
  }
  return pairs;
}

/** The pair's score for the staircase: both games, or twice the one that was played. */
function pairScore(p) {
  const got = [p.w, p.b].filter(g => g && !g.skipped);
  if (!got.length) return null;
  return got.length === 2 ? got[0].score + got[1].score : 2 * got[0].score;
}

/** Where a level starts: from the level below when it has a result, else from the engine's own setting. */
export function startGuess(manifest, level, below) {
  if (below) {
    if (below.status === 'above') return SCALE.max;
    if (below.status === 'below') return SCALE.min + 100;
    if (Number.isFinite(below.best)) return below.best + 150;
  }
  const s = levels.settings(manifest, level, 1);
  const elo = s.options.find(([k]) => k === 'UCI_Elo');
  if (elo && s.multipv <= 1) return +elo[1];
  if (s.options.some(([k, v]) => k === 'UCI_LimitStrength' && v === 'false')) return SCALE.max;
  return 1000;
}

function parseLevels(text) {
  if (!text) return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  const out = [];
  for (const part of text.split(',')) {
    const [a, b] = part.split('-').map(Number);
    for (let l = a; l <= (b || a); l++) out.push(l);
  }
  return out;
}

const stamp = () => new Date().toISOString().slice(0, 19);

export async function runEngine(id, { levelList, data = DEFAULT_DATA, log = console.log, slowMinutes = SLOW_MINUTES } = {}) {
  const file = path.join(data, 'games', id + '.jsonl');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const records = readJsonl(file);
  const append = rec => { fs.appendFileSync(file, JSON.stringify(rec) + '\n'); records.push(rec); };
  const manifest = manifestOf(id);
  let engine = null, maia = null;
  const players = () => {
    if (!engine) { engine = new Player(id); maia = new Player('maia'); }
    return { engine, maia };
  };
  const summary = [];
  try {
    let below = null;
    if (records.some(r => r.engine_failed || r.too_slow)) {
      log(`${stamp()} ${id}: left for later by an earlier run (engine_failed or too_slow in the records); delete that line to try again`);
      return summary;
    }
    levels: for (const level of levelList) {
      // A level's start is fixed by its first game, so a resumed run follows the same staircase.
      const first = records.find(r => r.level === level && r.start != null);
      const start = first ? first.start : startGuess(manifest, level, below);
      let v;
      for (;;) {
        const pairs = pairsOf(records, level);
        const crashes = [...pairs.values()].reduce((a, p) => a + p.crashes.w + p.crashes.b, 0);
        const skips = records.filter(r => r.level === level && r.skipped).length;
        v = verdict(counted(records, level));
        if (v.status !== 'playing') break;
        if (skips >= LEVEL_SKIPS || crashes >= LEVEL_CRASHES) { v.status = 'failed'; break; }
        // Finish a pair cut short by a stop or a skipped game before starting the next.
        const keys = [...pairs.keys()].sort((a, b) => a - b);
        let k = keys.find(key => { const p = pairs.get(key); return !p.w || !p.b; });
        let rating;
        if (k != null) rating = pairs.get(k).rating;
        else {
          k = keys.length ? keys[keys.length - 1] + 1 : 0;
          const done = keys.map(key => ({ rating: pairs.get(key).rating, score: pairScore(pairs.get(key)) })).filter(p => p.score != null);
          rating = nextRating(done, start);
        }
        const p = pairs.get(k) || { w: null, b: null, crashes: { w: 0, b: 0 } };
        const color = !p.w ? 'w' : 'b';
        if (p.crashes[color] >= GAME_CRASHES) {
          append({ engine: id, level, pair: k, color, maia: rating, skipped: true, at: stamp() });
          continue;
        }
        const { engine: E, maia: M } = players();
        try {
          const rec = await calibrationGame({ engine: E, maia: M, level, rating, pair: k, engineWhite: color === 'w' });
          rec.start = start;
          rec.at = stamp();
          append(rec);
          const f = verdict(counted(records, level));
          log(`${stamp()} ${id} L${level} pair ${k}${color} vs Maia ${rating}: ${rec.result} ${rec.reason} ${rec.plies} plies ${(rec.ms / 1000).toFixed(1)} s` +
            ` | ${f.games} games ${f.score}/${f.games} est ${fmt(f.best)} [${fmt(f.lo)}, ${fmt(f.hi)}]`);
          const timed = records.filter(r => r.level === level && r.result && r.ms);
          const minutes = timed.reduce((a, r) => a + r.ms, 0) / Math.max(1, timed.length) / 60000;
          if (timed.length >= 2 && minutes > slowMinutes) {
            append({ engine: id, level, too_slow: true, minutes: +minutes.toFixed(1), at: stamp() });
            log(`${stamp()} ${id} L${level}: ${minutes.toFixed(1)} minutes a game under Node, over ${slowMinutes}; leaving this engine for later`);
            summary.push({ level, ...f, status: 'too slow' });
            break levels;
          }
        } catch (e) {
          const error = String(e && e.message ? e.message : e).slice(0, 600);
          append({ engine: id, level, pair: k, color, maia: rating, start, crash: true, error, at: stamp() });
          log(`${stamp()} ${id} L${level} pair ${k}${color}: CRASH ${error}`);
          E.restart(); M.restart();
        }
      }
      log(`${stamp()} ${id} L${level} ${v.status}: ${v.games} games, ${v.score} points, est ${fmt(v.best)} [${fmt(v.lo)}, ${fmt(v.hi)}]`);
      summary.push({ level, ...v });
      if (v.status === 'failed' && !counted(records, level).length) {
        log(`${stamp()} ${id}: no game finished at level ${level}; giving up on this engine for now`);
        append({ engine: id, level, engine_failed: true, at: stamp() });
        break;
      }
      below = v.status === 'failed' ? below : v;
    }
  } finally {
    if (engine) engine.close();
    if (maia) maia.close();
  }
  return summary;
}

export function fmt(x) {
  if (x == null) return '-';
  if (x === Infinity) return '+inf';
  if (x === -Infinity) return '-inf';
  return String(Math.round(x));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const args = process.argv.slice(2);
  const flag = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
  const id = args[0];
  if (!id || id.startsWith('--')) {
    console.error('usage: node engines/calibrate/run.mjs <engine> [--levels 1-10] [--data DIR]');
    process.exit(2);
  }
  const data = flag('--data') ? path.resolve(flag('--data')) : DEFAULT_DATA;
  const levelList = parseLevels(flag('--levels'));
  console.log(`${stamp()} ${id}: levels ${levelList.join(',')}, data ${data}, pid ${process.pid}`);
  await runEngine(id, { levelList, data });
  console.log(`${stamp()} ${id}: finished`);
  process.exit(0);
}
