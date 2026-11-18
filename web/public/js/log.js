// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Every game, kept in this browser (IndexedDB) and written at every move. A record has the same fields, with the
// same names, as the iPhone app's GameRecord (ios/ZeistChess/Log/GameLog.swift), so games from both can go to a
// Zeist profile the same way later. Nothing is sent anywhere in this version.

import { APP_VERSION } from './store.js';

export const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

let dbp = null;
function db() {
  if (!dbp) {
    dbp = new Promise((resolve, reject) => {
      const req = indexedDB.open('zeist-chess', 1);
      req.onupgradeneeded = () => {
        const s = req.result.createObjectStore('games', { keyPath: 'id' });
        s.createIndex('startedAt', 'startedAt');
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }
  return dbp;
}

async function tx(mode, fn) {
  const d = await db();
  return new Promise((resolve, reject) => {
    const t = d.transaction('games', mode);
    const out = fn(t.objectStore('games'));
    t.oncomplete = () => resolve(out && 'result' in out ? out.result : undefined);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}

/** Every game, newest first. */
/** Every game kept in this browser, whoever played it, newest first. */
async function stored() {
  const list = await tx('readonly', s => s.getAll());
  return (list || []).sort((a, b) => (a.startedAt < b.startedAt ? 1 : -1));
}

/** Whether a game is shown now: the games of whoever is signed in; signed out, only guest games. Another account's
 *  games stay stored and come back when it signs in. (ios/ZeistChess/Log/GameLog.swift) */
function shown(g) { return (g.account || null) === (account ? account.owner : null); }

/** The games of whoever is signed in, newest first. */
export async function all() { return (await stored()).filter(shown); }

export async function get(id) { const g = await tx('readonly', s => s.get(id)); return g && shown(g) ? g : undefined; }

/** The game still going, if any. */
export async function current() { return (await all()).find(g => !g.result) || null; }

let account = null;
/** Signed in, games carry the account's owner tag; finished ones wait to be sent to Zeist (not built yet). */
export function setAccount(a) { account = a && a.owner ? a : null; }

/**
 * A game belongs to the account it was started under, kept here: a copy saved without an owner never clears it, and
 * an account's game never passes to another. A game started signed out is claimed once, by the first account that
 * signs in (stamp). The same rule as the iPhone app (ios/ZeistChess/Log/GameLog.swift).
 */
export async function save(r) {
  const rec = clean({ ...r });
  const kept = await tx('readonly', s => s.get(rec.id));
  if (kept && kept.account) {
    rec.account = kept.account;
    if (kept.accountHandle) rec.accountHandle = kept.accountHandle; else delete rec.accountHandle;
  } else if (!kept && !rec.account && account) {
    rec.account = account.owner; if (account.handle) rec.accountHandle = account.handle;
  }
  if (rec.result && rec.ending !== 'abandoned' && rec.account && !rec.upload) rec.upload = 'waiting';
  await tx('readwrite', s => s.put(rec));
  return rec;
}

/** Games played signed out move to the account at sign-in: every guest game in this browser, finished or not, joins
 *  whoever signs in first, as a guest's puzzle progress does (the rule Zeist and Zeist Chess share, as in the iPhone
 *  app). The consequence on a shared browser: games someone else played here signed out become the account's, and
 *  once claimed they stay that account's (save never moves an owned game). Signing out doesn't give them back. */
export async function stamp(owner, handle) {
  for (const g of await stored()) {
    if (g.account) continue;
    await save({ ...g, account: owner, ...(handle ? { accountHandle: handle } : {}) });
  }
}

/** Ends an unfinished game without a result, so it stays in the log. */
export async function abandon(id) {
  const g = await get(id);
  if (!g || g.result) return;
  await save({ ...g, result: '*', ending: 'abandoned', endedAt: now() });
}

export async function remove(id) { return tx('readwrite', s => s.delete(id)); }

export function now() { return new Date().toISOString(); }

/** A record for a game about to start. */
export function begin({ player, engine, packSHA, level, adaptive, rating, settings, seed, timeControl }) {
  const m = engine.manifest;
  const rec = {
    id: crypto.randomUUID().toUpperCase(),
    startedAt: now(),
    startFEN: START,
    fen: START,
    moves: [],
    san: [],
    player,
    engineID: m.id,
    engineName: m.name,
    engineVersion: m.version,
    packSHA,
    level,
    adaptive,
    rating,
    engineSettings: settings,
    seed,
    undos: 0,
    appVersion: APP_VERSION,
  };
  if (timeControl) {
    rec.timeControl = { base: timeControl.base, increment: timeControl.increment };
    rec.timeClass = timeClass(timeControl);
    rec.clocks = [];
    rec.clockLeft = [timeControl.base * 1000, timeControl.base * 1000];
  }
  return rec;
}

/** Leaves out empty fields, as the iPhone app's JSON does for its optional ones. */
function clean(r) {
  for (const k of Object.keys(r)) if (r[k] === null || r[k] === undefined) delete r[k];
  return r;
}

/** From the player's side: "win", "loss", "draw" or null. */
export function outcome(g) {
  if (g.result === '1-0') return g.player === 'w' ? 'win' : 'loss';
  if (g.result === '0-1') return g.player === 'b' ? 'win' : 'loss';
  if (g.result === '1/2-1/2') return 'draw';
  return null;
}

export function difficulty(g) {
  return g.rating != null ? `Rating ${g.rating}` : `Level ${g.level}${g.adaptive ? ', adaptive' : ''}`;
}

// Time controls, as the iPhone app has them (ios/ZeistChess/Play/Clock.swift).

/** Bullet, blitz, rapid or classical, by the expected length of a game of 40 moves, as Lichess counts. */
export function timeClass(tc) {
  const expected = tc.base + 40 * tc.increment;
  if (expected < 180) return 'bullet';
  if (expected < 480) return 'blitz';
  if (expected < 1500) return 'rapid';
  return 'classical';
}

/** "3 min" without increment, "3+2" with one. */
export function tcName(tc) {
  const m = tc.base % 60 === 0 ? String(tc.base / 60) : tc.base < 60 ? `${tc.base}s` : (tc.base / 60).toFixed(1);
  return tc.increment === 0 ? (tc.base % 60 === 0 ? `${m} min` : m) : `${m}+${tc.increment}`;
}

const mins = (m, inc = 0) => ({ base: m * 60, increment: inc });
export const PRESETS = [
  ['Bullet', [mins(1), mins(1, 1), mins(2, 1)]],
  ['Blitz', [mins(3), mins(3, 2), mins(5), mins(5, 3)]],
  ['Rapid', [mins(10), mins(15, 10)]],
];

// Export

export function exportJSON(games) {
  return JSON.stringify(games.slice().sort((a, b) => (a.startedAt < b.startedAt ? -1 : 1)), null, 2);
}

export function exportPGN(games) {
  return games.slice().sort((a, b) => (a.startedAt < b.startedAt ? -1 : 1)).map(pgn).join('\n');
}

function clk(ms) {
  const t = Math.floor(Math.max(0, ms) / 100), tenths = t % 10, whole = Math.floor(t / 10);
  const p = n => String(n).padStart(2, '0');
  return `${Math.floor(whole / 3600)}:${p(Math.floor((whole % 3600) / 60))}:${p(whole % 60)}.${tenths}`;
}

/** One game as PGN, the same as the iPhone app writes it. */
export function pgn(g) {
  const d = new Date(g.startedAt);
  const p = n => String(n).padStart(2, '0');
  const you = g.accountHandle || 'You';
  const them = `${g.engineName} ${g.engineVersion}, level ${g.level}`;
  const tags = [
    ['Event', 'Zeist Chess'], ['Site', 'Web'], ['Date', `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())}`], ['Round', '-'],
    ['White', g.player === 'w' ? you : them], ['Black', g.player === 'w' ? them : you], ['Result', g.result || '*'],
  ];
  if (g.startFEN !== START) tags.push(['SetUp', '1'], ['FEN', g.startFEN]);
  if (g.ending) tags.push(['Termination', g.ending.startsWith('timeout') ? 'time forfeit' : g.ending]);
  tags.push(['TimeControl', g.timeControl ? `${g.timeControl.base}+${g.timeControl.increment}` : '-']);
  tags.push(['Annotator', `Zeist Chess ${g.appVersion}`]);
  const head = tags.map(([k, v]) => `[${k} "${String(v).replace(/"/g, "'")}"]`).join('\n') + '\n\n';
  const blackFirst = g.startFEN.split(' ')[1] === 'b';
  const startNo = Number(g.startFEN.split(' ').pop()) || 1;
  const body = [];
  (g.san || []).forEach((s, i) => {
    const ply = i + (blackFirst ? 1 : 0), no = startNo + Math.floor(ply / 2);
    body.push(ply % 2 === 0 ? `${no}. ${s}` : i === 0 ? `${no}... ${s}` : s);
    if (g.clocks && g.clocks[i] != null) body.push(`{[%clk ${clk(g.clocks[i])}]}`);
  });
  body.push(g.result || '*');
  const lines = [];
  let line = '';
  for (const w of body) {
    if (line.length + w.length + 1 > 79) { lines.push(line); line = w; } else line = line ? line + ' ' + w : w;
  }
  if (line) lines.push(line);
  return head + lines.join('\n') + '\n';
}
