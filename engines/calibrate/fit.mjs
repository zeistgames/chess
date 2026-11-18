#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Turns the game records into ratings.
//
//   node engines/calibrate/fit.mjs [--data DIR] [<engine> ...]
//
// For every engine with games in DIR/games/<engine>.jsonl (or the engines named): per level, the maximum
// likelihood rating on Maia's scale under the logistic model, against the Maia ratings actually faced, with
// a 95% profile likelihood interval (stats.mjs), the games, the score and the longest game. A level whose
// interval lies wholly past Maia 2600 or Maia 600 is reported as above or below the scale, not as a number.
// Levels whose estimate falls below the level under them are listed.
//
// Writes engines/calibrate/results/<engine>.json and engines/calibrate/results/README.md (one table for all
// engines, then the sanity checks from results/sanity.json and the details per engine).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { verdict, outOfOrder, SCALE } from './stats.mjs';
import { DEFAULT_DATA, readJsonl, counted, fmt } from './run.mjs';
import { manifestOf, PLY_CAP } from './play.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const RESULTS = path.join(here, 'results');
const ORDER = ['zeist', 'ethereal', 'fairy-stockfish', 'stockfish-lite', 'koivisto', 'clover', 'halogen', 'arasan', 'plentychess', 'caissa', 'stockfish'];

export function fitEngine(id, records) {
  const levels = [];
  for (let level = 1; level <= 10; level++) {
    const recs = records.filter(r => r.level === level);
    if (!recs.length) continue;
    const played = recs.filter(r => r.result && !r.crash && !r.skipped);
    const v = verdict(counted(records, level));
    const at = r => (played.filter(g => g.maia === r));
    const slow = recs.find(r => r.too_slow);
    const entry = {
      level,
      status: slow && v.status === 'playing' ? 'too slow'
        : v.status === 'playing' && (recs.filter(r => r.skipped).length >= 10 || recs.filter(r => r.crash).length >= 40) ? 'failed'
        : v.status,
      rating: v.status === 'rated' || v.status === 'playing' ? round(v.best) : null,
      interval: [round(v.lo), round(v.hi)],
      estimate: round(v.best),
      games: v.games,
      score: v.score,
      wins: played.filter(g => g.score === 1).length,
      draws: played.filter(g => g.score === 0.5).length,
      losses: played.filter(g => g.score === 0).length,
      maia_faced: [...new Set(played.map(g => g.maia))].sort((a, b) => a - b),
      longest_plies: played.length ? Math.max(...played.map(g => g.plies)) : null,
      past_400_plies: played.filter(g => g.plies > 400).length,
      at_ply_cap: played.filter(g => g.reason === 'ply-cap').length,
      crashes: recs.filter(r => r.crash).length,
      skipped: recs.filter(r => r.skipped).length,
      minutes_per_game: played.length ? +(played.reduce((a, g) => a + g.ms, 0) / played.length / 60000).toFixed(2) : null,
      settings: played.length ? played[0].settings : null,
    };
    if (v.status === 'above') entry.evidence = `${at(SCALE.max).reduce((a, g) => a + g.score, 0)} of ${at(SCALE.max).length} against Maia ${SCALE.max}`;
    if (v.status === 'below') entry.evidence = `${at(SCALE.min).reduce((a, g) => a + g.score, 0)} of ${at(SCALE.min).length} against Maia ${SCALE.min}`;
    if (slow) entry.evidence = `${slow.minutes} minutes a game under Node; left for later`;
    if (entry.crashes && recs.some(r => r.crash)) entry.last_crash = recs.filter(r => r.crash).pop().error;
    levels.push(entry);
  }
  const order = outOfOrder(levels.filter(l => l.status !== 'failed' && l.status !== 'too slow').map(l => ({ level: l.level, status: l.status, best: l.estimate, lo: l.interval[0], hi: l.interval[1] })));
  let version = null;
  try { version = manifestOf(id).version; } catch { /* pack missing */ }
  return {
    engine: id, version,
    scale: `Maia 3 (UCI_Elo ${SCALE.min} to ${SCALE.max}), logistic model, 95% profile likelihood intervals`,
    fitted_at: new Date().toISOString(),
    engine_failed: records.some(r => r.engine_failed),
    levels,
    out_of_order: order,
  };
}

function round(x) { return x == null || !Number.isFinite(x) ? (x === Infinity ? 'inf' : x === -Infinity ? '-inf' : null) : Math.round(x); }

function cell(l) {
  if (!l) return '';
  if (l.status === 'above') return `above ${SCALE.max}`;
  if (l.status === 'below') return `below ${SCALE.min}`;
  if (l.status === 'failed') return 'failed';
  if (l.status === 'too slow') return 'too slow under Node';
  const r = `${fmtR(l.estimate)} (${fmtR(l.interval[0])}-${fmtR(l.interval[1])})`;
  return l.status === 'playing' ? `${r}, ${l.games} so far` : r;
}
function fmtR(x) { return x === 'inf' ? 'inf' : x === '-inf' ? '-inf' : x == null ? '-' : String(x); }

function readme(results, sanity) {
  const L = [];
  L.push('# Calibration results', '');
  L.push(`Every level of every engine rated on Maia 3's scale: Maia plays the move its network gives a player of the set rating (UCI_Elo ${SCALE.min} to ${SCALE.max}), so a number here means "scores 50% against Maia set to this". It is Maia's scale, not a Lichess or FIDE rating. Generated by \`engines/calibrate/fit.mjs\`; how the games are played is in \`engines/calibrate/run.mjs\` and \`play.mjs\`.`, '');
  L.push(`Each cell: the maximum likelihood rating and its 95% interval. "above ${SCALE.max}" / "below ${SCALE.min}": the whole interval is past the end of Maia's range, after at least 12 games there; the evidence is in the details. Levels still playing show their games so far.`, '');
  L.push(`Fitted ${new Date().toISOString().slice(0, 16).replace('T', ' ')} UTC.`, '');
  L.push('How it is run (DIR holds the game records and logs, outside the repo):', '');
  L.push('```sh');
  L.push('node --test engines/calibrate/test/*.test.mjs                 # the rating math');
  L.push('node engines/calibrate/sanity.mjs maia --low 1300 --high 1700 --data DIR');
  L.push('node engines/calibrate/sanity.mjs determinism --engine zeist');
  L.push('nohup node engines/calibrate/all.mjs --data DIR --jobs 6 > DIR/logs/all.log 2>&1 &   # every engine, resumable');
  L.push('node engines/calibrate/run.mjs <engine> --levels 1-10 --data DIR                     # one engine');
  L.push('node engines/calibrate/fit.mjs --data DIR                                            # this page');
  L.push('```', '');
  L.push('| Engine | ' + Array.from({ length: 10 }, (_, i) => `L${i + 1}`).join(' | ') + ' |');
  L.push('|---|' + '---|'.repeat(10));
  for (const r of results) {
    const by = new Map(r.levels.map(l => [l.level, l]));
    L.push(`| ${r.engine} | ` + Array.from({ length: 10 }, (_, i) => cell(by.get(i + 1))).join(' | ') + ' |');
  }
  L.push('');
  L.push('## Sanity checks', '');
  const maia = Object.entries(sanity).filter(([k]) => k.startsWith('maia_'));
  for (const [, s] of maia) {
    L.push(`- Maia ${s.high} against Maia ${s.low}, ${s.games} games: Maia ${s.high} scored ${s.score} (${(100 * s.share).toFixed(1)}%, ${s.draws} draws); the ${s.high - s.low}-point gap predicts ${(100 * s.predicted).toFixed(1)}%. Fitted from these games, Maia ${s.high} rates ${s.fitted_high} (${s.interval[0]}-${s.interval[1]}). Longest game ${s.longest} plies.`);
  }
  if (maia.length) {
    const ratios = maia.map(([, s]) => (s.fitted_high - s.low) / (s.high - s.low));
    L.push(`- So Maia's settings are closer together in strength than their numbers say: a 400-point step played like ${maia.map(([, s]) => s.fitted_high - s.low).join(', ')} Elo points (${Math.round(100 * Math.min(...ratios))}% to ${Math.round(100 * Math.max(...ratios))}% of the gap). The ratings above are Maia settings, the point where an engine level scores 50%, and stay comparable with each other. The intervals assume the logistic model, which takes each Maia point as one Elo point, so read in Maia settings they are too narrow by roughly that factor.`);
  }
  for (const [, s] of Object.entries(sanity).filter(([k]) => k.startsWith('determinism_'))) {
    L.push(`- Determinism, ${s.engine} level ${s.level} against Maia ${s.rating}, opening ${s.opening}, seed ${s.seed}: same workers after another game ${s.same_workers_same_game ? 'gave the same game' : 'gave a different game'}; fresh workers ${s.fresh_workers_same_game ? 'gave the same game' : 'gave a different game'}.${s.note ? ' ' + s.note : ''}`);
  }
  L.push('');
  for (const r of results) {
    L.push(`## ${r.engine}${r.version ? ' ' + r.version : ''}`, '');
    if (r.engine_failed) L.push('The engine did not finish a game under Node; it is left for later.', '');
    L.push('| Level | Status | Rating | 95% interval | Games | Score | W-D-L | Maia faced | Longest (plies) | Min/game | Crashes |');
    L.push('|---|---|---|---|---|---|---|---|---|---|---|');
    for (const l of r.levels) {
      const faced = l.maia_faced.length ? `${l.maia_faced[0]}-${l.maia_faced[l.maia_faced.length - 1]}` : '-';
      L.push(`| ${l.level} | ${l.status}${l.evidence ? ': ' + l.evidence : ''} | ${fmtR(l.rating)} | ${fmtR(l.interval[0])} to ${fmtR(l.interval[1])} | ${l.games} | ${l.score} | ${l.wins}-${l.draws}-${l.losses} | ${faced} | ${l.longest_plies ?? '-'}${l.at_ply_cap ? ` (${l.at_ply_cap} at the ${PLY_CAP} cap)` : ''} | ${l.minutes_per_game ?? '-'} | ${l.crashes} |`);
    }
    if (r.out_of_order.length) {
      L.push('', 'Out of order: ' + r.out_of_order.map(o => `level ${o.level} rates below level ${o.below}${o.clear ? ' (intervals do not overlap)' : ' (within the intervals)'}`).join('; ') + '.');
    }
    L.push('');
  }
  return L.join('\n');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const args = process.argv.slice(2);
  const i = args.indexOf('--data');
  const data = i >= 0 ? path.resolve(args[i + 1]) : DEFAULT_DATA;
  const named = args.filter((a, k) => !a.startsWith('--') && !(k > 0 && args[k - 1] === '--data'));
  const dir = path.join(data, 'games');
  const have = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith('.jsonl') && !f.startsWith('sanity')).map(f => f.slice(0, -6)) : [];
  const ids = (named.length ? named : have).sort((a, b) => (ORDER.indexOf(a) + 1 || 99) - (ORDER.indexOf(b) + 1 || 99));
  fs.mkdirSync(RESULTS, { recursive: true });
  const results = [];
  for (const id of ids) {
    const r = fitEngine(id, readJsonl(path.join(dir, id + '.jsonl')));
    fs.writeFileSync(path.join(RESULTS, id + '.json'), JSON.stringify(r, null, 2) + '\n');
    results.push(r);
    for (const l of r.levels) console.log(`${id} L${l.level} ${l.status} ${fmt(l.estimate === 'inf' ? Infinity : l.estimate === '-inf' ? -Infinity : l.estimate)} [${fmtR(l.interval[0])}, ${fmtR(l.interval[1])}] ${l.games} games ${l.score} pts longest ${l.longest_plies}`);
    for (const o of r.out_of_order) console.log(`${id}: level ${o.level} below level ${o.below}${o.clear ? ' (clear)' : ''}`);
  }
  const sanityFile = path.join(RESULTS, 'sanity.json');
  const sanity = fs.existsSync(sanityFile) ? JSON.parse(fs.readFileSync(sanityFile, 'utf8')) : {};
  fs.writeFileSync(path.join(RESULTS, 'README.md'), readme(results, sanity) + '\n');
}
