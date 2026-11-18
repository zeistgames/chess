#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One calibration game: an engine at a level against Maia at a rating, driven as the app drives them.
//
//   node engines/calibrate/play.mjs <engine> <level> <maia-rating> [--black] [--opening K] [--seed N]
//
// Each side is the app's own EngineHost (core/host.js) over a Node worker_thread running the pack in
// engines/tools/worker-shim.cjs, the same emulation engines/check.mjs uses. The engine's settings come from
// levels.settings(manifest, level, seed) and each move from levels.choose(lines, bestmove, settings, ply),
// exactly as core/bridge.js does; Maia's from levels.atRating(maia, rating). No clocks: every search is a
// node budget, so results do not depend on the speed of the machine. The game starts from a fixed opening
// (openings.mjs) and ends by the rules (core/rules.js: mate, stalemate, insufficient material, threefold
// repetition, fifty moves), or as a draw at the ply cap.

import { Worker } from 'node:worker_threads';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { EngineHost } from '../../core/host.js';
import * as levels from '../../core/levels.js';
import { Game } from '../../core/rules.js';
import { openingFor } from './openings.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
// CAL_DIST: another folder of packs, for trying a changed engine without touching engines/dist.
export const DIST = process.env.CAL_DIST ? path.resolve(process.env.CAL_DIST) : path.join(here, '..', 'dist');
const SHIM = path.join(here, '..', 'tools', 'worker-shim.cjs');
export const PLY_CAP = 600;
const DIED = /^(at wasm:\/\/|RuntimeError\b|Aborted\(|abort\()/;

/** The pack manifest for an engine id. */
export function manifestOf(id) {
  return JSON.parse(fs.readFileSync(path.join(DIST, id, 'manifest.json'), 'utf8'));
}

/**
 * A Web Worker look-alike for EngineHost: onmessage, onerror, postMessage, terminate. A worker that dies,
 * or reports an uncaught error through the shim, calls onerror, so the host rejects the search and the game
 * is recorded as a crash.
 */
function nodeWorker(url) {
  const w = new Worker(SHIM, { workerData: { script: fileURLToPath(url) } });
  let ended = false;
  const o = {
    onmessage: null,
    onerror: null,
    postMessage(line) { w.postMessage(line); },
    terminate() { ended = true; w.terminate().catch(() => {}); },
  };
  const fail = message => { if (!ended && o.onerror) o.onerror({ message }); };
  w.on('message', data => {
    const s = String(data);
    if (s.startsWith('__shim_error')) { fail(s.slice(0, 800)); return; }
    // An engine that aborts inside WebAssembly prints a stack trace and then never answers; the app would
    // wait for its timeout. Treat the trace as the crash it is, at once.
    const trace = s.split('\n').find(l => DIED.test(l.trim()));
    if (trace) { fail('engine aborted: ' + trace.trim().slice(0, 300)); return; }
    if (o.onmessage) o.onmessage({ data: s });
  });
  w.on('error', e => fail(String(e && e.stack ? e.stack : e).slice(0, 800)));
  w.on('exit', code => fail('worker exited with code ' + code));
  return o;
}

/** One engine's worker, kept alive across games. */
export class Player {
  constructor(id, { timeoutMs = 120000 } = {}) {
    this.id = id;
    this.manifest = manifestOf(id);
    this.host = new EngineHost({
      base: pathToFileURL(path.join(DIST, id) + '/').href,
      manifest: this.manifest,
      createWorker: nodeWorker,
      timeoutMs,
    });
  }
  /** ucinewgame and isready; starts (or restarts) the worker when needed. */
  newGame() { return this.host.newGame(); }
  /** Ends the worker; the next game starts a fresh one. */
  restart() { this.host.stop(); }
  close() { this.host.stop(); }
  get starts() { return this.host.starts; }
}

/**
 * Plays one game. white and black: { player: Player, settings } where settings is what levels gives.
 * Returns { result: "1-0" | "0-1" | "1/2-1/2", reason, plies, moves, opening, ms }.
 * Throws (and the caller records a crash) when a worker dies, times out, or plays a move the rules refuse.
 */
export async function playGame({ white, black, opening, cap = PLY_CAP }) {
  const began = Date.now();
  const g = new Game();
  for (const m of opening.moves) if (!g.play(m)) throw new Error('opening move refused: ' + m);
  await white.player.newGame();
  await black.player.newGame();
  let out = null;
  while (!(out = g.outcome())) {
    const played = g.moves().map(m => m.uci);
    if (played.length >= cap) { out = { result: '1/2-1/2', reason: 'ply-cap', winner: null }; break; }
    const side = g.turn() === 'w' ? white : black;
    const s = side.settings;
    const r = await side.player.host.search({ moves: played }, s);
    let move = levels.choose(r.lines, r.bestmove, s, played.length);
    if (!g.play(move)) {
      const pick = move;
      move = r.bestmove;
      if (!g.play(move)) throw new Error(`${side.player.id} played ${pick} / ${r.bestmove}, refused at ply ${played.length}`);
    }
  }
  const moves = g.moves().map(m => m.uci);
  return { result: out.result, reason: out.reason, plies: moves.length, moves, ms: Date.now() - began };
}

/** The engine's settings for one game: levels.settings with a seed derived from level, pair and color. */
export function engineSettings(manifest, level, seed) {
  const s = levels.settings(manifest, level, seed);
  // ZEIST_SHIPPED=1: the Zeist engine's own eight levels as Zeist ships them (its Level option with that level's
  // node limit from computer.js), not Zeist Chess's ten. Keep these games in a data folder of their own.
  if (process.env.ZEIST_SHIPPED && manifest.id === 'zeist') {
    const L = Math.max(1, Math.min(8, level));
    return { ...s, level: L, options: [['Level', String(L)], ['Seed', String(seed >>> 0)]], nodes: ZEIST_SHIPPED_NODES[L - 1], multipv: 1, temperature: 0 };
  }
  return s;
}
// The node limit sent at each of the eight levels: ZEIST_SHIPPED=1 uses Zeist's table as first shipped, or give the
// eight limits yourself (ZEIST_SHIPPED=20000,20000,...) to match a trial table.
const ZEIST_SHIPPED_NODES = /,/.test(process.env.ZEIST_SHIPPED || '') ? process.env.ZEIST_SHIPPED.split(',').map(Number) : [20000, 20000, 20000, 20000, 20000, 45000, 100000, 250000];

/** Maia's settings at a rating, through levels.atRating as the app sets a rating. */
export function maiaSettings(maiaManifest, rating) {
  const s = levels.atRating(maiaManifest, rating, 1);
  if (!s) throw new Error('Maia has no rating option');
  return s;
}

/** A game seed for a level, pair and color, fixed so a replay plays the same game. */
export function gameSeed(level, pair, engineWhite) {
  return (Math.imul(pair + 1, 0x9E3779B1) ^ Math.imul(level, 0x85EBCA6B) ^ (engineWhite ? 0x51 : 0xA3)) >>> 0;
}

/**
 * One calibration game between engine (Player) at level and maia (Player) at rating.
 * Returns the record appended to the JSONL: score is the engine's points.
 */
export async function calibrationGame({ engine, maia, level, rating, pair, engineWhite }) {
  const seed = gameSeed(level, pair, engineWhite);
  const es = engineSettings(engine.manifest, level, seed);
  const ms = maiaSettings(maia.manifest, rating);
  const opening = openingFor(pair);
  const E = { player: engine, settings: es }, M = { player: maia, settings: ms };
  const r = await playGame({ white: engineWhite ? E : M, black: engineWhite ? M : E, opening });
  const score = r.result === '1/2-1/2' ? 0.5 : (r.result === '1-0') === engineWhite ? 1 : 0;
  return {
    engine: engine.id, version: engine.manifest.version, level, maia: rating, pair,
    color: engineWhite ? 'w' : 'b', seed, opening: opening.index, opening_name: opening.name,
    result: r.result, reason: r.reason, score, plies: r.plies, ms: r.ms,
    settings: { options: es.options, nodes: es.nodes, multipv: es.multipv, temperature: es.temperature },
    moves: r.moves.join(' '),
  };
}

// Command line: one game, printed as JSON.
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const args = process.argv.slice(2);
  const flag = (name, d) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : d; };
  const [id, level, rating] = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && args[i - 1] !== '--black'));
  if (!id || !level || !rating) {
    console.error('usage: node engines/calibrate/play.mjs <engine> <level> <maia-rating> [--black] [--opening K]');
    process.exit(2);
  }
  const engine = new Player(id), maia = new Player('maia');
  try {
    const rec = await calibrationGame({ engine, maia, level: +level, rating: +rating, pair: +flag('--opening', 0), engineWhite: !args.includes('--black') });
    console.log(JSON.stringify(rec));
  } finally {
    engine.close(); maia.close();
  }
  process.exit(0);
}
