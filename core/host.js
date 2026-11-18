// Runs one engine pack in a Web Worker and speaks UCI to it.
//
// The pack's worker takes one UCI line per postMessage(string) and posts one line back per message.
// A search is ended by ending the worker (an engine need not obey "stop"), so starting a search while
// another runs, or calling stop(), terminates the worker; the next search starts a fresh one. Every search
// carries a token, and anything that arrives for an older token is dropped.

export class StaleError extends Error {
  constructor(message = 'stale') { super(message); this.name = 'StaleError'; }
}

function parseInfo(line) {
  // info depth 12 seldepth 18 multipv 2 score cp -31 nodes 20000 nps ... pv e7e5 g1f3
  const t = line.split(/\s+/);
  const out = { multipv: 1 };
  for (let i = 1; i < t.length; i++) {
    const k = t[i];
    if (k === 'depth') out.depth = +t[++i];
    else if (k === 'multipv') out.multipv = +t[++i];
    else if (k === 'score') {
      const kind = t[++i], v = +t[++i];
      if (kind === 'cp') out.cp = v; else if (kind === 'mate') out.mate = v;
      if (t[i + 1] === 'lowerbound' || t[i + 1] === 'upperbound') out.bound = t[++i];
    } else if (k === 'nodes') out.nodes = +t[++i];
    else if (k === 'pv') { out.pv = t.slice(i + 1); out.move = out.pv[0]; break; }
  }
  return out;
}

export class EngineHost {
  /**
   * base: the URL of the pack folder, ending in "/". manifest: the pack's manifest.json.
   * createWorker(url): how to make a worker (tests pass a fake). timeoutMs: how long a step may take.
   */
  constructor({ base, manifest, createWorker, timeoutMs = 30000, log } = {}) {
    this.base = base;
    this.manifest = manifest;
    this.createWorker = createWorker || (url => new Worker(url));
    this.timeoutMs = timeoutMs;
    this.log = log || (() => {});
    this.worker = null;
    this.token = 0;
    this.waiter = null; // { token, test(line) -> done?, resolve, reject, timer }
    this.ready = null; // a promise for a worker that has answered uciok and readyok
    this.options = {}; // what the current worker has been sent
    this.starts = 0;
  }

  get id() { return this.manifest && this.manifest.id; }

  _spawn() {
    this._kill();
    const url = new URL(this.manifest.entry, this.base).href;
    const w = this.createWorker(url);
    const token = ++this.token;
    this.starts++;
    w.onmessage = e => this._line(token, typeof e.data === 'string' ? e.data : String(e.data));
    w.onerror = e => {
      if (token !== this.token) return;
      const err = new Error('engine error: ' + (e && e.message ? e.message : 'unknown'));
      if (this.waiter) { const wt = this.waiter; this.waiter = null; clearTimeout(wt.timer); wt.reject(err); }
      this._kill();
    };
    this.worker = w;
    this.options = {};
    return token;
  }

  _kill() {
    if (this.worker) {
      try { this.worker.terminate(); } catch { /* already gone */ }
    }
    this.worker = null;
    this.ready = null;
    this.token++;
    if (this.waiter) {
      const wt = this.waiter; this.waiter = null; clearTimeout(wt.timer);
      wt.reject(new StaleError());
    }
  }

  _line(token, text) {
    if (token !== this.token) return; // from a worker already ended
    for (const line of text.split('\n')) {
      const l = line.trim();
      if (!l) continue;
      this.log(l);
      const wt = this.waiter;
      if (wt && wt.token === token && wt.test(l)) {
        this.waiter = null;
        clearTimeout(wt.timer);
        wt.resolve(l);
      }
    }
  }

  _send(line) {
    this.log('> ' + line);
    this.worker.postMessage(line);
  }

  /** Sends a line and waits for the first line that passes test. */
  _ask(line, test, timeoutMs = this.timeoutMs) {
    const token = this.token;
    return new Promise((resolve, reject) => {
      if (this.waiter) { reject(new Error('busy')); return; }
      const timer = setTimeout(() => {
        if (this.waiter && this.waiter.token === token) {
          this.waiter = null;
          reject(new Error('engine timed out on: ' + line));
          this._kill();
        }
      }, timeoutMs);
      this.waiter = { token, test, resolve, reject, timer };
      if (line != null) this._send(line);
    });
  }

  /** Starts the worker and waits for uciok and readyok. Safe to call again: it reuses a ready worker. */
  start() {
    if (this.ready) return this.ready;
    const token = this._spawn();
    const p = (async () => {
      await this._ask('uci', l => l === 'uciok');
      await this._ask('isready', l => l === 'readyok');
      if (token !== this.token) throw new StaleError();
    })();
    this.ready = p;
    p.catch(() => { if (this.ready === p) this.ready = null; });
    return p;
  }

  /** Ends any search and the worker. The next search starts a fresh worker. */
  stop() { this._kill(); }

  /** Ends the worker and starts a fresh one. */
  restart() { this._kill(); return this.start(); }

  /** Tells a fresh game is starting. */
  async newGame() {
    await this.start();
    this._send('ucinewgame');
    await this._ask('isready', l => l === 'readyok');
  }

  /**
   * One search. position: { fen, moves } (fen omitted means the start). s: from levels.settings().
   * clock (timed games): { wtime, btime, winc, binc } in milliseconds, and turn ("w" or "b"). The engine is sent
   * its clock together with the level's node budget, so it manages its own time and weak levels stay weak.
   * No pack can be interrupted by "stop", so the host also holds each search to the engine's clock
   * (levels.deadlines): past the soft limit it takes the deepest line seen so far and ends the worker; at the hard
   * limit, just before the engine's flag, with nothing to play, it ends the worker and rejects with OutOfTimeError.
   * Resolves { bestmove, lines, ms, cut }. Rejects with StaleError when stopped or replaced by another search.
   */
  async search(position, s, clock = null) {
    if (this.waiter) this._kill(); // one search at a time: the older one is now stale
    await this.start();
    const token = this.token;
    for (const [name, value] of (s && s.options) || []) {
      if (this.options[name] !== value) {
        this._send(`setoption name ${name} value ${value}`);
        this.options[name] = value;
      }
    }
    await this._ask('isready', l => l === 'readyok');
    const moves = (position && position.moves) || [];
    const fen = position && position.fen;
    this._send(`position ${fen ? 'fen ' + fen : 'startpos'}${moves.length ? ' moves ' + moves.join(' ') : ''}`);
    const lines = new Map();
    const began = Date.now();
    const nodes = (s && s.nodes) || 20000;
    const timed = clock && Number.isFinite(+clock.wtime) && Number.isFinite(+clock.btime);
    const go = timed
      ? `go wtime ${ms(clock.wtime)} btime ${ms(clock.btime)} winc ${ms(clock.winc)} binc ${ms(clock.binc)} nodes ${nodes}`
      : `go nodes ${nodes}`;
    const sorted = () => [...lines.values()].sort((a, b) => a.multipv - b.multipv);
    const asked = this._ask(go, l => {
      if (l.startsWith('info ') && l.includes(' pv ')) {
        const info = parseInfo(l);
        if (!info.bound) lines.set(info.multipv, info);
      }
      return l.startsWith('bestmove');
    }, timed ? deadlines(clock).hard + 1000 : Math.max(this.timeoutMs, 60000));
    if (!timed) {
      const done = await asked;
      if (token !== this.token) throw new StaleError();
      return { bestmove: done.split(/\s+/)[1], lines: sorted(), ms: Date.now() - began, cut: false };
    }
    // Timed: whichever comes first, the engine's answer or its limits.
    const { soft, hard } = deadlines(clock);
    let softTimer, hardTimer, poll;
    const limit = new Promise((resolve, reject) => {
      const take = () => {
        const best = lines.get(1);
        if (!best || !best.move) return false;
        resolve({ cut: true });
        return true;
      };
      softTimer = setTimeout(() => {
        if (take()) return;
        // Nothing to play yet: wait for a first line, or the hard limit.
        poll = setInterval(() => { if (take()) clearInterval(poll); }, 10);
        hardTimer = setTimeout(() => { clearInterval(poll); if (!take()) reject(new OutOfTimeError()); }, Math.max(0, hard - soft));
      }, soft);
    });
    let done;
    try {
      done = await Promise.race([asked.then(l => ({ line: l })), limit]);
    } catch (e) {
      if (e instanceof OutOfTimeError && token === this.token) { asked.catch(() => {}); this._kill(); }
      throw e;
    } finally {
      clearTimeout(softTimer); clearTimeout(hardTimer); clearInterval(poll);
    }
    if (done.cut) {
      if (token !== this.token) throw new StaleError();
      const kept = sorted();
      asked.catch(() => {}); // the search ends with its worker
      this._kill();
      return { bestmove: lines.get(1).move, lines: kept, ms: Date.now() - began, cut: true };
    }
    if (token !== this.token) throw new StaleError();
    return { bestmove: done.line.split(/\s+/)[1], lines: sorted(), ms: Date.now() - began, cut: false };
  }
}

/** The engine ran out of its own time with nothing to play. Its flag falls. */
export class OutOfTimeError extends Error {
  constructor(message = 'out of time') { super(message); this.name = 'OutOfTimeError'; }
}

function ms(v) { return Math.max(0, Math.round(Number(v) || 0)); }

/**
 * How long one search may run on the engine's own clock (milliseconds): soft, after which the host plays the
 * deepest line it has, and hard, just before the flag, after which the engine has lost on time. Engines that
 * manage their time answer well before soft; soft is for those that ignore the clock.
 */
export function deadlines(clock) {
  const own = ms(clock.turn === 'b' ? clock.btime : clock.wtime);
  const inc = ms(clock.turn === 'b' ? clock.binc : clock.winc);
  const hard = Math.max(0, own - Math.min(150, own * 0.25));
  const soft = Math.min(hard, Math.max(Math.min(100, own * 0.5), Math.min(own * 0.08 + inc * 0.8, own * 0.4)));
  return { soft: Math.round(soft), hard: Math.round(hard) };
}

export { parseInfo };
