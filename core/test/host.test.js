import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EngineHost, StaleError, OutOfTimeError, deadlines, parseInfo } from '../host.js';

// A fake UCI engine in the shape of a pack's worker: one line in, lines out.
class FakeWorker {
  static made = [];
  constructor(url, { slow = false } = {}) {
    this.url = url;
    this.slow = slow;
    this.terminated = false;
    this.sent = [];
    FakeWorker.made.push(this);
  }
  out(line) { if (!this.terminated) setTimeout(() => this.onmessage && this.onmessage({ data: line }), 1); }
  postMessage(line) {
    this.sent.push(line);
    if (line === 'uci') { this.out('id name Fake'); this.out('uciok'); }
    else if (line === 'isready') this.out('readyok');
    else if (line.startsWith('go')) {
      if (this.slow) return; // never answers: only ending the worker stops it
      this.out('info depth 3 multipv 1 score cp 25 nodes 100 pv e2e4 e7e5');
      this.out('info depth 3 multipv 2 score cp 10 nodes 100 pv d2d4');
      this.out('bestmove e2e4 ponder e7e5');
    }
  }
  terminate() { this.terminated = true; }
}

const manifest = { id: 'fake', version: '1', entry: 'engine.js' };

test('handshake, then a search returns the best move and its lines', async () => {
  const h = new EngineHost({ base: 'zchess://app/engines/fake/', manifest, createWorker: u => new FakeWorker(u) });
  const r = await h.search({ moves: ['e2e4'] }, { options: [['MultiPV', '2']], nodes: 500 });
  assert.equal(r.bestmove, 'e2e4');
  assert.equal(r.lines.length, 2);
  assert.equal(r.lines[1].move, 'd2d4');
  const w = FakeWorker.made.at(-1);
  assert.equal(w.url, 'zchess://app/engines/fake/engine.js');
  assert.ok(w.sent.includes('setoption name MultiPV value 2'));
  assert.ok(w.sent.includes('position startpos moves e2e4'));
  assert.ok(w.sent.includes('go nodes 500'));
});

test('stop ends the worker and the search is stale', async () => {
  let slow = true;
  const h = new EngineHost({ base: 'x://a/', manifest, createWorker: u => new FakeWorker(u, { slow }) });
  const p = h.search({}, { nodes: 10 });
  await new Promise(r => setTimeout(r, 20));
  const w = FakeWorker.made.at(-1);
  h.stop();
  await assert.rejects(p, StaleError);
  assert.ok(w.terminated);
  slow = false;
  const r = await h.search({}, { nodes: 10 }); // restarts cleanly with a fresh worker
  assert.equal(r.bestmove, 'e2e4');
  assert.notEqual(FakeWorker.made.at(-1), w);
});

test('a second search replaces the first, whose answer is dropped', async () => {
  let slow = true;
  const h = new EngineHost({ base: 'x://a/', manifest, createWorker: u => new FakeWorker(u, { slow }) });
  const first = h.search({}, { nodes: 10 });
  await new Promise(r => setTimeout(r, 20));
  const old = FakeWorker.made.at(-1);
  slow = false;
  const second = h.search({ moves: ['d2d4'] }, { nodes: 10 });
  await assert.rejects(first, StaleError);
  assert.equal((await second).bestmove, 'e2e4');
  old.terminated = false; // even if the ended worker spoke again, nothing it says is heard
  old.onmessage({ data: 'bestmove a2a3' });
});

test('a search that never ends times out and the host recovers', async () => {
  let slow = true;
  const h = new EngineHost({ base: 'x://a/', manifest, timeoutMs: 30, createWorker: u => new FakeWorker(u, { slow }) });
  h.timeoutMs = 30;
  const p = h._ask('go nodes 1', l => l.startsWith('bestmove'), 30);
  await assert.rejects(p);
  slow = false;
  assert.equal((await h.search({}, { nodes: 1 })).bestmove, 'e2e4');
});

test('info lines parse', () => {
  const i = parseInfo('info depth 12 seldepth 18 multipv 2 score mate -3 nodes 20000 nps 1 pv e7e5 g1f3');
  assert.deepEqual([i.depth, i.multipv, i.mate, i.move], [12, 2, -3, 'e7e5']);
  assert.equal(parseInfo('info depth 5 score cp 13 lowerbound nodes 9 pv a2a3').bound, 'lowerbound');
});

// An engine that ignores the clock: it posts a line at once and then thinks for as long as it likes.
class StubbornWorker extends FakeWorker {
  postMessage(line) {
    if (line.startsWith('go')) {
      this.sent.push(line);
      if (!this.silent) this.out('info depth 1 multipv 1 score cp 5 nodes 10 pv g1f3');
      return; // no bestmove until the worker is ended
    }
    super.postMessage(line);
  }
}

test('a timed search sends the clock with the node budget', async () => {
  const h = new EngineHost({ base: 'x://a/', manifest, createWorker: u => new FakeWorker(u) });
  const r = await h.search({ moves: ['e2e4'] }, { nodes: 1500 }, { wtime: 60000, btime: 59000.4, winc: 1000, binc: 1000, turn: 'b' });
  assert.equal(r.bestmove, 'e2e4');
  assert.equal(r.cut, false);
  assert.ok(FakeWorker.made.at(-1).sent.includes('go wtime 60000 btime 59000 winc 1000 binc 1000 nodes 1500'));
});

test('an engine that ignores its clock is held to it: past the soft limit its deepest line is played', async () => {
  const h = new EngineHost({ base: 'x://a/', manifest, createWorker: u => new StubbornWorker(u) });
  const began = Date.now();
  const r = await h.search({}, { nodes: 1500000 }, { wtime: 1000, btime: 1000, winc: 0, binc: 0, turn: 'w' });
  assert.equal(r.bestmove, 'g1f3');
  assert.equal(r.cut, true);
  assert.ok(Date.now() - began < 400, 'well inside its second');
  const w = FakeWorker.made.at(-1);
  assert.ok(w.terminated, 'the worker is ended, since stop would not be obeyed');
  // The next search starts a fresh worker.
  h.createWorker = u => new FakeWorker(u);
  assert.equal((await h.search({}, { nodes: 10 })).bestmove, 'e2e4');
});

test('with nothing to play by the hard limit, the engine runs out of time', async () => {
  const h = new EngineHost({ base: 'x://a/', manifest, createWorker: u => Object.assign(new StubbornWorker(u), { silent: true }) });
  const began = Date.now();
  await assert.rejects(h.search({}, { nodes: 10 }, { wtime: 300, btime: 300, winc: 0, binc: 0, turn: 'w' }), OutOfTimeError);
  const took = Date.now() - began;
  assert.ok(took >= 200 && took < 300, `ended just before the flag (${took} ms)`);
  assert.ok(FakeWorker.made.at(-1).terminated);
});

test('deadlines: soft well inside the clock, hard just before the flag', () => {
  const d = deadlines({ wtime: 180000, btime: 1, winc: 2000, binc: 0, turn: 'w' });
  assert.equal(d.hard, 180000 - 150);
  assert.equal(d.soft, Math.round(180000 * 0.08 + 1600));
  const low = deadlines({ wtime: 1, btime: 400, winc: 0, binc: 0, turn: 'b' });
  assert.ok(low.soft <= low.hard && low.hard < 400 && low.hard >= 300);
  assert.deepEqual(deadlines({ wtime: 0, btime: 0, turn: 'w' }), { soft: 0, hard: 0 });
});
