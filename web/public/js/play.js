// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A game against an engine: your moves, the engine's turn, the clocks, undo, resign, the end and the log.
// The same behavior as the iPhone app's GameModel (ios/ZeistChess/Play/GameModel.swift).

import { Game } from '../core/rules.js';
import * as engine from './engine.js';
import * as log from './log.js';
import * as material from './material.js';
import { get as pref, set as setPref } from './store.js';

const now = () => performance.now();

/** Two clocks. The side to move counts down; a move adds the increment to the side that made it. The clocks start
 *  with White's first move, so the first move is free. Times in milliseconds. (ios/ZeistChess/Play/Clock.swift) */
export class Clock {
  constructor(tc, left, running = null) {
    this.tc = tc;
    this.w = left ? left[0] : tc.base * 1000;
    this.b = left ? left[1] : tc.base * 1000;
    this.running = running;
    this.since = null;
    this.paused = true;
  }
  remaining(side, t = now()) {
    const left = side === 'w' ? this.w : this.b;
    return this.running === side && this.since != null ? Math.max(0, left - (t - this.since)) : Math.max(0, left);
  }
  moved(side, t = now()) {
    // Once a side's time has run out the game is over: a move made after it changes nothing.
    if (this.running === side && this.remaining(side, t) <= 0) return;
    if (this.running === side) this.set(side, this.remaining(side, t) + this.tc.increment * 1000);
    this.running = side === 'w' ? 'b' : 'w';
    this.since = this.paused ? null : t;
  }
  pause(t = now()) { if (this.paused) return; this.fold(t); this.paused = true; }
  resume(t = now()) { if (!this.paused) return; this.paused = false; if (this.running) this.since = t; }
  stop(t = now()) { this.fold(t); this.running = null; }
  flagged(t = now()) { return this.running && this.since != null && this.remaining(this.running, t) <= 0 ? this.running : null; }
  fold(t) { if (this.running) this.set(this.running, this.remaining(this.running, t)); this.since = null; }
  set(side, v) { if (side === 'w') this.w = v; else this.b = v; }
  left() { return [Math.round(this.remaining('w')), Math.round(this.remaining('b'))]; }
  lowTime() { return Math.min(20, Math.max(10, this.tc.base * 0.1)) * 1000; }
}

/** "3:00", "0:42", "0:09.4" under ten seconds, "1:05:00" over an hour. */
export function sayClock(ms) {
  const s = Math.max(0, ms) / 1000;
  if (s < 10) { const t = Math.floor(s * 10); return `0:0${Math.floor(t / 10)}.${t % 10}`; }
  const whole = Math.floor(s), h = Math.floor(whole / 3600), m = Math.floor((whole % 3600) / 60), sec = whole % 60;
  const p = n => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${p(m)}:${p(sec)}` : `${m}:${p(sec)}`;
}

/** Where an adaptive game against this engine starts: its own record, else core's first level. */
export function startingLevel(id) { return pref('level.' + id, null) ?? engine.levels.FIRST; }

export class Play {
  constructor(record, entry, onChange = () => {}) {
    this.record = record;
    this.entry = entry;
    this.manifest = entry.manifest;
    this.onChange = onChange;
    this.game = Game.fromMoves(record.moves, record.startFEN);
    this.thinking = false;
    this.trouble = null;
    this.request = 0;
    this.nextLevel = null;
    this.clock = null;
    this.ready = Promise.resolve();
    if (record.timeControl && !record.result) {
      const running = record.moves.length ? this.game.turn() : null;
      this.clock = new Clock(record.timeControl, record.clockLeft, running);
    }
  }

  /** Starts a game: picks the seed, asks core for the engine's settings, saves it. Any game in progress ends. */
  static async begin({ entry, player, level, adaptive, rating, timeControl }, onChange) {
    const old = await log.current();
    if (old) await log.abandon(old.id);
    const seed = crypto.getRandomValues(new Uint32Array(1))[0] || 1;
    const settings = engine.settingsFor(entry.manifest, { level, rating: adaptive ? null : rating, seed });
    const rec = log.begin({
      player, engine: entry, packSHA: entry.packSHA, level: settings.level, adaptive,
      rating: adaptive ? undefined : settings.rating, settings, seed, timeControl,
    });
    await log.save(rec);
    return new Play(rec, entry, onChange);
  }

  get player() { return this.record.player; }
  get over() { return !!this.record.result; }
  get timed() { return !!this.record.timeControl; }
  get snap() { return this.game.snapshot(); }
  get myTurn() { return !this.over && this.game.turn() === this.player && !this.thinking; }
  get canUndo() { return !this.over && !this.timed && this.record.moves.length >= (this.player === 'w' ? 1 : 2) && !this.busy; }

  changed() { try { this.onChange(this); } catch (e) { console.error(e); } }

  async save() {
    if (this.clock) this.record.clockLeft = this.clock.left();
    this.record = await log.save(this.record);
  }

  /** On opening the game: the clock runs again and the engine thinks if it is its turn. */
  async open() {
    if (this.over) return;
    const o = this.game.outcome();
    if (o) { await this.finish(o); return; }
    // The engine starts once, before any search: a move made meanwhile waits for it.
    this.ready = engine.newGame(this.manifest).catch(e => { if (!(e instanceof engine.StaleError)) throw e; });
    try { await this.ready; } catch (e) { console.warn('engine:', e); this.trouble = this.engineTrouble(e); this.changed(); return; }
    if (this.clock) this.clock.resume();
    this.engineIfDue();
    this.changed();
  }

  /** Leaving the screen, or the page going out of sight: the clock stops and any search ends; the game stays. */
  pause() {
    this.request++;
    if (this.thinking) { this.thinking = false; engine.stop(); }
    if (this.clock && !this.over) { this.clock.pause(); this.save(); }
  }

  resume() {
    if (this.over) return;
    if (this.clock) this.clock.resume();
    this.engineIfDue();
    this.changed();
  }

  /** Called often while a clock runs: a flag that falls ends the game. */
  tick() {
    if (!this.clock || this.over) return;
    const f = this.clock.flagged();
    if (f) this.flag(f);
  }

  async move(uci) {
    if (!this.myTurn) return false;
    const ok = await this.apply(uci, false);
    return ok;
  }

  async apply(uci, byEngine) {
    const side = this.game.turn();
    // A move from a side whose time has already run out is not played: its flag falls instead.
    if (this.clock && this.clock.flagged() === side) { this.flag(side); return false; }
    const rec = this.game.play(uci);
    if (!rec) { this.trouble = "That move couldn't be played."; this.changed(); return false; }
    if (this.clock) {
      this.clock.moved(side);
      this.record.clocks = [...(this.record.clocks || []), Math.round(this.clock.remaining(side))];
    }
    this.record.moves = [...this.record.moves, rec.uci];
    this.record.san = [...this.record.san, rec.san];
    this.record.fen = this.game.fen();
    this.trouble = null;
    const o = this.game.outcome();
    if (o) { await this.finish(o); return true; }
    this.save();
    this.changed();
    if (!byEngine) this.engineIfDue();
    return true;
  }

  engineIfDue() {
    if (this.over || this.game.turn() === this.player || this.thinking || (this.clock && this.clock.paused)) return;
    this.thinking = true;
    this.trouble = null;
    const id = ++this.request;
    const began = now();
    this.changed();
    (async () => {
      try { await this.ready; } catch { /* reported by open(); the search below starts the engine afresh */ }
      for (let attempt = 1; ; attempt++) {
        try {
          const clock = this.clock ? {
            wtime: this.clock.remaining('w'), btime: this.clock.remaining('b'),
            winc: this.clock.tc.increment * 1000, binc: this.clock.tc.increment * 1000,
          } : null;
          const r = await engine.think({ manifest: this.manifest, startFEN: this.record.startFEN, moves: this.record.moves, settings: this.record.engineSettings, clock, seed: this.record.seed });
          if (id !== this.request) return;
          // The engine takes its time like a person would (levels.pace), unless replies are set to instant;
          // then a beat with no clock, and nothing when its own clock is running.
          const wait = (pref('pace', true) ? r.pace : this.clock ? 0 : 450) - (now() - began);
          if (wait > 0) await new Promise(res => setTimeout(res, wait));
          if (id !== this.request) return;
          this.thinking = false;
          await this.apply(r.move, true);
          return;
        } catch (e) {
          if (id !== this.request || e instanceof engine.StaleError) return;
          if (e instanceof engine.OutOfTimeError) { this.thinking = false; this.flag(this.game.turn()); return; }
          console.warn('engine:', e);
          if (attempt < 2 && !this.clock && !(e instanceof engine.UnguardedError)) { engine.release(); continue; }
          // A worker that crashed or ran out of memory: say so calmly, keep the board, offer the ways on.
          this.thinking = false;
          this.trouble = this.engineTrouble(e);
          if (this.clock) this.clock.pause();
          this.changed();
          return;
        }
      }
    })();
  }

  engineTrouble(e) {
    if (e instanceof engine.UnguardedError) return e.message;
    return `${this.manifest.name} stopped before it could move, perhaps for lack of memory. Try again, or play a smaller engine.`;
  }

  retry() {
    this.trouble = null;
    engine.release();
    if (this.clock) this.clock.resume();
    this.engineIfDue();
    this.changed();
  }

  undo() {
    if (!this.canUndo) return;
    this.request++;
    if (this.thinking) { this.thinking = false; engine.stop(); }
    const moves = this.record.moves.slice(0, -1);
    if (moves.length % 2 !== (this.player === 'w' ? 0 : 1)) moves.pop();
    this.game = Game.fromMoves(moves, this.record.startFEN);
    this.record.moves = moves;
    this.record.san = this.game.moves().map(m => m.san);
    this.record.fen = this.game.fen();
    this.record.undos = (this.record.undos || 0) + 1;
    this.trouble = null;
    this.save();
    this.changed();
    this.engineIfDue();
  }

  resign() {
    if (this.over) return;
    const winner = this.player === 'w' ? 'b' : 'w';
    this.finish({ result: winner === 'w' ? '1-0' : '0-1', reason: 'resigned', winner });
  }

  /** side's time is up: it loses, unless the other side couldn't checkmate, which makes a draw. */
  flag(side) {
    if (this.over) return;
    const other = side === 'w' ? 'b' : 'w';
    if (this.clock) this.clock.set(side, 0);
    if (material.canMate(other, this.game.board())) this.finish({ result: other === 'w' ? '1-0' : '0-1', reason: 'timeout', winner: other, flagged: side });
    else this.finish({ result: '1/2-1/2', reason: 'timeout-insufficient', winner: null, flagged: side });
  }

  async finish(o) {
    this.request++;
    if (this.thinking) { this.thinking = false; engine.stop(); }
    if (this.clock) this.clock.stop();
    this.record.result = o.result;
    this.record.ending = o.reason;
    this.record.endedAt = log.now();
    this.flagged = o.flagged || null;
    await this.save();
    const result = log.outcome(this.record) || 'draw';
    if (this.record.adaptive) {
      const id = this.record.engineID;
      const r = engine.levels.adapt(this.record.level, result, pref('step.' + id, undefined));
      setPref('level.' + id, r.level);
      setPref('step.' + id, r.step);
      this.nextLevel = r.level;
    }
    this.changed();
  }

  // Words

  status() {
    if (this.trouble) return this.trouble;
    if (this.over) return '';
    if (this.thinking) return `${this.manifest.name} is thinking.`;
    if (this.clock && this.clock.paused && this.record.moves.length) return 'The clocks are stopped.';
    if (this.game.inCheck()) return 'Check. Your move.';
    if (!this.record.moves.length && this.player === 'w') return 'You play White. Your move.';
    return 'Your move.';
  }

  ending() {
    const r = this.record, name = this.manifest.name;
    const res = log.outcome(r);
    const flaggedYou = res === 'loss' ? true : res === 'win' ? false : null;
    const why = {
      checkmate: 'Checkmate.',
      stalemate: 'Stalemate.',
      repetition: 'The same position three times.',
      'fifty-move': 'Fifty moves without a capture or a pawn move.',
      insufficient: 'Neither side can checkmate.',
      resigned: 'You resigned.',
      timeout: flaggedYou === false ? `${name} ran out of time.` : flaggedYou ? 'Your time ran out.' : 'Out of time.',
      'timeout-insufficient': 'Time ran out, with too little left on the board to checkmate.',
    }[r.ending] || '';
    const out = log.outcome(r);
    const title = out === 'win' ? 'You won.' : out === 'loss' ? `${name} won.` : 'A draw.';
    return { title, why };
  }
}
