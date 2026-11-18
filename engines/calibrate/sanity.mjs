#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Checks the yardstick and the harness before trusting a calibration.
//
//   node engines/calibrate/sanity.mjs maia [--low 1300] [--high 1700] [--pairs 24] [--data DIR]
//   node engines/calibrate/sanity.mjs determinism [--engine stockfish-lite] [--level 3] [--rating 1500]
//
// maia: Maia at two ratings plays itself in pairs (each side white once per opening). If Maia's ratings
// behave like Elo ratings, the higher one scores what the gap predicts, and the rating fitted to its results
// against the lower one lands near its own. Games go to DIR/games/sanity-maia.jsonl, resumable.
//
// determinism: the same pairing, seed and opening is played twice by the same workers with another game
// between them, then once more by fresh workers. All three must give the same moves.
//
// Results are merged into engines/calibrate/results/sanity.json, which fit.mjs puts in the summary.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Player, playGame, maiaSettings, calibrationGame } from './play.mjs';
import { openingFor } from './openings.mjs';
import { expected, fit } from './stats.mjs';
import { DEFAULT_DATA, readJsonl } from './run.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const RESULTS = path.join(here, 'results', 'sanity.json');

function save(key, value) {
  fs.mkdirSync(path.dirname(RESULTS), { recursive: true });
  const all = fs.existsSync(RESULTS) ? JSON.parse(fs.readFileSync(RESULTS, 'utf8')) : {};
  // A note written by hand (why a check came out as it did) is kept when the check is run again.
  all[key] = all[key] && all[key].note ? { ...value, note: all[key].note } : value;
  fs.writeFileSync(RESULTS, JSON.stringify(all, null, 2) + '\n');
}

async function maiaCheck({ low, high, pairs, data }) {
  const file = path.join(data, 'games', 'sanity-maia.jsonl');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const have = readJsonl(file).filter(r => r.low === low && r.high === high && r.result);
  const a = new Player('maia'), b = new Player('maia');
  try {
    for (let k = 0; k < pairs; k++) {
      for (const highWhite of [true, false]) {
        if (have.some(r => r.pair === k && r.highWhite === highWhite)) continue;
        const H = { player: a, settings: maiaSettings(a.manifest, high) };
        const L = { player: b, settings: maiaSettings(b.manifest, low) };
        const opening = openingFor(k);
        const r = await playGame({ white: highWhite ? H : L, black: highWhite ? L : H, opening });
        const score = r.result === '1/2-1/2' ? 0.5 : (r.result === '1-0') === highWhite ? 1 : 0;
        const rec = { low, high, pair: k, highWhite, opening: opening.index, result: r.result, reason: r.reason, score, plies: r.plies, ms: r.ms, moves: r.moves.join(' ') };
        fs.appendFileSync(file, JSON.stringify(rec) + '\n');
        have.push(rec);
        console.log(`maia ${high} vs ${low} pair ${k} ${highWhite ? 'w' : 'b'}: ${r.result} ${r.reason} ${r.plies} plies ${(r.ms / 1000).toFixed(1)} s`);
      }
    }
  } finally { a.close(); b.close(); }
  const games = have.map(r => ({ opp: low, score: r.score }));
  const f = fit(games);
  const out = {
    low, high, games: f.games, score: f.score, share: f.score / f.games,
    predicted: expected(high, low),
    fitted_high: Math.round(f.best), interval: [Math.round(f.lo), Math.round(f.hi)],
    draws: have.filter(r => r.score === 0.5).length,
    longest: Math.max(...have.map(r => r.plies)),
    minutes_per_game: +(have.reduce((x, r) => x + r.ms, 0) / have.length / 60000).toFixed(3),
  };
  save(`maia_${low}_${high}`, out);
  console.log(JSON.stringify(out));
}

async function determinism({ engine: id, level, rating }) {
  const e = new Player(id), m = new Player('maia');
  const args = { engine: e, maia: m, level, rating, pair: 0, engineWhite: true };
  let one, two, three;
  try {
    one = await calibrationGame(args);
    await calibrationGame({ ...args, pair: 1, engineWhite: false });
    two = await calibrationGame(args);
  } finally { e.close(); m.close(); }
  const e2 = new Player(id), m2 = new Player('maia');
  try { three = await calibrationGame({ ...args, engine: e2, maia: m2 }); } finally { e2.close(); m2.close(); }
  const out = {
    engine: id, level, rating, opening: one.opening, seed: one.seed, plies: one.plies, result: one.result,
    same_workers_same_game: one.moves === two.moves,
    fresh_workers_same_game: one.moves === three.moves,
  };
  save(`determinism_${id}_L${level}`, out);
  console.log(JSON.stringify(out));
  if (!out.same_workers_same_game || !out.fresh_workers_same_game) process.exitCode = 1;
}

const args = process.argv.slice(2);
const flag = (name, d) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : d; };
const data = flag('--data') ? path.resolve(flag('--data')) : DEFAULT_DATA;
if (args[0] === 'maia') await maiaCheck({ low: +flag('--low', 1300), high: +flag('--high', 1700), pairs: +flag('--pairs', 24), data });
else if (args[0] === 'determinism') await determinism({ engine: flag('--engine', 'stockfish-lite'), level: +flag('--level', 3), rating: +flag('--rating', 1500) });
else { console.error('usage: node engines/calibrate/sanity.mjs maia | determinism [options]'); process.exit(2); }
process.exit(process.exitCode || 0);
