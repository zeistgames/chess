// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One engine at a time, run by core/host.js in a Web Worker from this origin, at the level core/levels.js sets.
// The same steps as the iPhone app's bridge (core/bridge.js): ask for the move, let the level pick among the
// engine's lines, and never play a move the rules refuse.

import { EngineHost, StaleError, OutOfTimeError } from '../core/host.js';
import * as levels from '../core/levels.js';
import { Game, START } from '../core/rules.js';
import { ENGINES, BASE, ownWorker, untilOwnWorker } from './store.js';
import { bytesOf } from './shelf.js';

export { StaleError, OutOfTimeError, levels };

let host = null;

/**
 * Waits until the service worker answers for this page. It is what hands the engine's worker only the files that
 * were checked when the pack was downloaded (sw.js); without it the worker would load them from the network.
 */
export class UnguardedError extends Error {}

async function guarded() {
  const sw = navigator.serviceWorker;
  if (!sw) throw new UnguardedError("This browser can't check an engine's files, so it can't run one here.");
  // Only this app's own worker counts: under zeist.gg the page may first be controlled by Zeist's (scope /chess),
  // which lets engine files through from the network unchecked.
  if (ownWorker()) return;
  // Already installed and active but not answering for this page, with no other worker in its place: it was loaded
  // past it, as a hard reload does. A moment's grace for one just taking over; otherwise say so at once. On a first
  // visit, or under another worker, wait for this one to activate and claim the page.
  const reg = await sw.getRegistration(BASE).catch(() => null);
  const skipped = !!(reg && reg.active && reg.active.scriptURL && !sw.controller);
  if (await untilOwnWorker(skipped ? 1000 : 15000)) return;
  throw new UnguardedError(skipped
    ? 'This page was loaded in a way that skips the check on engine files, as a hard reload does. Reload the page normally to play.'
    : "The check on engine files isn't ready in this browser yet. Reload the page to play.");
}

function hostFor(manifest) {
  const key = manifest.id + '@' + manifest.version;
  if (host && host.key === key) return host;
  if (host) host.stop();
  // Large packs take longer to compile on a phone before they answer at all.
  const big = bytesOf(manifest) > 20e6;
  host = new EngineHost({ base: ENGINES + manifest.id + '/', manifest, timeoutMs: big ? 120000 : 45000 });
  host.key = key;
  return host;
}

/** Starts the engine's worker early, so the first move comes quickly. */
export async function warm(manifest) { await guarded(); await hostFor(manifest).start(); }

export async function newGame(manifest) { await guarded(); await hostFor(manifest).newGame(); }

/** Ends any search now. */
export function stop() { if (host) host.stop(); }

/** Ends the worker for good (switching engines, leaving). */
export function release() { if (host) { host.stop(); host = null; } }

export function settingsFor(manifest, { level, rating, seed }) {
  return (rating != null && levels.atRating(manifest, rating, seed)) || levels.settings(manifest, level, seed);
}

/**
 * The engine's move after a list of moves. clock (timed games): { wtime, btime, winc, binc } in milliseconds.
 * Resolves { move, pace (how long the reply should take in all, levels.pace), bestmove, ms, cut, lines }. Rejects with StaleError when stopped, OutOfTimeError when its flag falls.
 */
export async function think({ manifest, startFEN, moves, settings, clock = null, seed = 1 }) {
  const g = Game.fromMoves(moves, startFEN);
  if (g.outcome()) throw new Error('the game is over');
  await guarded();
  const h = hostFor(manifest);
  const c = clock ? { ...clock, turn: g.turn() } : null;
  const forced = g.legal().length === 1;
  settings = levels.fitted(settings, g.legal().length);
  const r = await h.search({ fen: startFEN && startFEN !== START ? startFEN : null, moves }, settings, c);
  let move = levels.choose(r.lines, r.bestmove, settings, moves.length);
  if (!g.play(move)) {
    move = r.bestmove;
    if (!g.play(move)) throw new Error('engine move refused: ' + move);
  }
  const last = moves[moves.length - 1];
  const pace = levels.pace({ clock: c, ply: moves.length, forced, recapture: !!last && last.slice(2, 4) === move.slice(2, 4), seed });
  return { move, pace, bestmove: r.bestmove, ms: r.ms, cut: r.cut, lines: r.lines };
}
