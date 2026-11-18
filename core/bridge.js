// The page the iPhone app runs in a hidden web view. The app sends calls as
//   window.zeist.call(id, method, args)
// and gets each answer through webkit.messageHandlers.zeist.postMessage({ id, ok, value | error }).
// The page keeps no game of its own: every call carries the moves, so a web view that restarts after
// memory pressure picks up where it was from the app's saved game.

import { Game, START } from './rules.js';
import { EngineHost, StaleError, OutOfTimeError } from './host.js';
import * as levels from './levels.js';
import { parsePosition } from './rules.js';
import { opening } from './openings.js';

let host = null; // one engine at a time; switching engines ends the other's worker

function engineFor(engine) {
  const key = engine.manifest.id + '@' + engine.manifest.version + '@' + engine.base;
  if (host && host.key === key) return host;
  if (host) host.stop();
  host = new EngineHost({ base: engine.base, manifest: engine.manifest });
  host.key = key;
  return host;
}

function game(args) {
  return Game.fromMoves(args.moves || [], args.fen || START);
}

const methods = {
  ping: () => 'pong',

  /** The position after a list of moves. */
  state: args => game(args).snapshot(),

  /** Plays one move after a list of moves. */
  play: args => {
    const g = game(args);
    if (!g.play(args.move)) throw new Error('illegal move ' + args.move);
    return g.snapshot();
  },

  /** The position after every move, for stepping through a finished game. */
  replay: args => {
    const g = new Game(args.fen || START);
    const fens = [g.fen()];
    for (const m of args.moves || []) {
      if (!g.play(m)) break;
      fens.push(g.fen());
    }
    return { fens, san: g.moves().map(m => m.san) };
  },

  /** A pasted FEN or PGN, read. */
  parse: args => parsePosition(args.text),

  /** The opening the moves are in, by name, or null. */
  opening: args => opening(args.moves || [], args.fen || START),

  settings: args => (args.rating != null && levels.atRating(args.manifest, args.rating, args.seed)) || levels.settings(args.manifest, args.level, args.seed),

  adapt: args => levels.adapt(args.level, args.result, args.step),

  levels: () => ({ lowest: levels.LOWEST, highest: levels.HIGHEST, first: levels.FIRST }),

  /** Starts an engine's worker early, so the first move comes quickly. */
  warm: async args => {
    const h = engineFor(args.engine);
    await h.start();
    return { starts: h.starts };
  },

  newGame: async args => {
    const h = engineFor(args.engine);
    await h.newGame();
    return true;
  },

  /** The engine's move in a position, at a level. */
  think: async args => {
    const g = game(args);
    if (g.outcome()) throw new Error('the game is over');
    const s = levels.fitted(args.settings || levels.settings(args.engine.manifest, args.level, args.seed), g.legal().length);
    const h = engineFor(args.engine);
    const clock = args.clock ? { ...args.clock, turn: g.turn() } : null;
    const played = args.moves || [];
    const forced = g.legal().length === 1;
    const r = await h.search({ fen: args.fen && args.fen !== START ? args.fen : null, moves: played }, s, clock);
    let move = levels.choose(r.lines, r.bestmove, s, played.length);
    if (!g.play(move)) { // never trust a pick the rules refuse
      move = r.bestmove;
      if (!g.play(move)) throw new Error('engine move refused: ' + move);
    }
    const last = played[played.length - 1];
    const pace = levels.pace({ clock, ply: played.length, forced, recapture: !!last && last.slice(2, 4) === move.slice(2, 4), seed: args.seed });
    return { move, pace, bestmove: r.bestmove, ms: r.ms, cut: r.cut, lines: r.lines.map(l => ({ multipv: l.multipv, cp: l.cp, mate: l.mate, move: l.move, depth: l.depth })), settings: s };
  },

  /** Ends any search now. */
  stop: () => { if (host) host.stop(); return true; },
};

function reply(msg) {
  const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zeist;
  if (h) h.postMessage(msg); else console.log('reply', msg);
}

window.zeist = {
  async call(id, method, args) {
    try {
      const f = methods[method];
      if (!f) throw new Error('no method ' + method);
      const value = await f(args || {});
      reply({ id, ok: true, value: value === undefined ? null : value });
    } catch (e) {
      reply({ id, ok: false, error: String(e && e.message || e), stale: e instanceof StaleError, outOfTime: e instanceof OutOfTimeError });
    }
  },
};

reply({ id: 0, ok: true, value: 'ready' });
