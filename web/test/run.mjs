#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Plays Zeist Chess on the web headless, in Chromium and WebKit (Playwright), from a local server that runs the
// Worker's own request handler under a base path. It checks, in each browser:
//   the app loads under /chess/engines/, with "Zeist" at the top left of Home (and without it elsewhere); an
//   engine's address (/chess/engines/zeist) opens Home with that engine picked and plays it; an engine is downloaded in Settings with its files checked; several moves
//   against Stockfish Lite (fetched on first play) and against a second engine; a reload with no network picks the
//   game up and the engine still answers; a timed game runs its clocks; a finished game is found in Recent and
//   stepped through with the arrow keys; theme and pieces change and stay; a broken engine ends in a calm message
//   with the board still usable; a signed-in Zeist account shows its username (Chromium).
// Screenshots of every screen go to web/screenshots/, at phone and desktop sizes.
//
//   PLAYWRIGHT_DIR=<folder with playwright installed> node test/run.mjs [chromium] [webkit] [--engines <dir>]
//
// Engines come from engines.zei.st through the local server, or from a folder of packs with --engines.

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { fileURLToPath } from 'node:url';

const web = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const repo = path.dirname(web);
const pwDir = process.env.PLAYWRIGHT_DIR;
if (!pwDir) {
  console.error('set PLAYWRIGHT_DIR to a folder where playwright and its chromium and webkit are installed');
  process.exit(2);
}
const pw = createRequire(path.join(pwDir, 'package.json'))('playwright');
const { Game } = await import(path.join(repo, 'core/rules.js'));

const args = process.argv.slice(2);
const engineDir = args.includes('--engines') ? args[args.indexOf('--engines') + 1] : null;
const browsers = args.filter(a => a === 'chromium' || a === 'webkit');
if (!browsers.length) browsers.push('chromium', 'webkit');
const BASE_PATH = '/chess/engines/'; // as on zeist.gg: one folder under /chess/, so Home shows the way back to Zeist
const SECOND = 'ethereal'; // the second engine: small, so the test stays quick
const shots = path.join(web, 'screenshots');
fs.mkdirSync(shots, { recursive: true });
fs.mkdirSync(path.join(web, 'test-results'), { recursive: true });

const PHONE = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true };
const DESKTOP = { width: 1440, height: 900 };

let failures = 0;
const results = [];
function ok(browser, name) { results.push(`  ok    ${browser}: ${name}`); console.log(`ok    ${browser}: ${name}`); }
function fail(browser, name, e) { failures++; results.push(`  FAIL  ${browser}: ${name}: ${e && e.message || e}`); console.log(`FAIL  ${browser}: ${name}\n${e && e.stack || e}`); }
let currentPage = null;
async function step(browser, name, fn) {
  try { await fn(); ok(browser, name); return true; } catch (e) {
    fail(browser, name, e);
    if (currentPage) {
      await currentPage.screenshot({ path: path.join(web, 'test-results', `${browser}-${name.replace(/[^a-z0-9]+/gi, '-').slice(0, 50)}.png`) }).catch(() => {});
      await currentPage.context().setOffline(false).catch(() => {});
    }
    return false;
  }
}
function assert(c, msg) { if (!c) throw new Error(msg); }

async function freePort() {
  return new Promise(res => { const s = net.createServer(); s.listen(0, () => { const p = s.address().port; s.close(() => res(p)); }); });
}

const port = await freePort();
const server = spawn(process.execPath, [path.join(web, 'scripts/serve.mjs'), '--port', String(port), '--base', BASE_PATH, ...(engineDir ? ['--engines', engineDir] : [])], { stdio: ['ignore', 'pipe', 'inherit'] });
await new Promise(res => server.stdout.once('data', res));
const URL0 = `http://localhost:${port}${BASE_PATH}`;
// A second server at a base that is not under /chess/, where Home has no way back to Zeist.
const port2 = await freePort();
const server2 = spawn(process.execPath, [path.join(web, 'scripts/serve.mjs'), '--port', String(port2), '--base', '/play/', ...(engineDir ? ['--engines', engineDir] : [])], { stdio: ['ignore', 'pipe', 'inherit'] });
await new Promise(res => server2.stdout.once('data', res));
const URL2 = `http://localhost:${port2}/play/`;
console.log('serving', URL0, engineDir ? `(engines from ${engineDir})` : '(engines from engines.zei.st)');

// Page helpers

async function games(page) {
  return page.evaluate(() => new Promise((resolve, reject) => {
    const r = indexedDB.open('zeist-chess');
    r.onsuccess = () => {
      const q = r.result.transaction('games').objectStore('games').getAll();
      q.onsuccess = () => resolve(q.result.sort((a, b) => (a.startedAt < b.startedAt ? 1 : -1)));
      q.onerror = () => reject(q.error);
    };
    r.onerror = () => reject(r.error);
  }));
}
async function currentGame(page) { return (await games(page)).find(g => !g.result) || null; }

async function waitFor(fn, ms = 60000, what = 'condition') {
  const end = Date.now() + ms;
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() > end) throw new Error('timed out waiting for ' + what);
    await new Promise(r => setTimeout(r, 150));
  }
}

/** Clicks one square of the game board, by name, for a board seen from side. */
async function clickSquare(page, sel, sq, side) {
  const box = await page.locator(sel).boundingBox();
  const f = 'abcdefgh'.indexOf(sq[0]), r = 8 - Number(sq[1]);
  const c = side === 'b' ? 7 - f : f, w = side === 'b' ? 7 - r : r;
  const cell = box.width / 8;
  await page.mouse.click(box.x + (c + 0.5) * cell, box.y + (w + 0.5) * cell);
}

// A few sensible first moves, then anything legal that doesn't hang the queen too obviously.
const PREFER = ['e2e4', 'g1f3', 'f1c4', 'b1c3', 'd2d3', 'e1g1', 'c2c3', 'h2h3', 'a2a3', 'd2d4'];
function pickMove(g) {
  const game = Game.fromMoves(g.moves, g.startFEN);
  const legal = game.legal().filter(m => !m.promotion || m.promotion === 'q');
  return (PREFER.map(u => legal.find(m => m.uci === u)).find(Boolean) || legal.find(m => m.capture) || legal[0]).uci;
}

/** Makes n moves as White (tap a piece, tap a square), waiting each time for the engine's reply. */
async function playMoves(page, n, { drag = false } = {}) {
  for (let i = 0; i < n; i++) {
    const g = await waitFor(async () => { const c = await currentGame(page); return c && c.moves.length % 2 === (c.player === 'w' ? 0 : 1) ? c : null; }, 90000, 'my turn');
    const uci = pickMove(g);
    if (drag && i === 0) {
      const box = await page.locator('#game-board').boundingBox();
      const cell = box.width / 8, at = sq => [box.x + ('abcdefgh'.indexOf(sq[0]) + 0.5) * cell, box.y + (8 - Number(sq[1]) + 0.5) * cell];
      const [x1, y1] = at(uci.slice(0, 2)), [x2, y2] = at(uci.slice(2, 4));
      await page.mouse.move(x1, y1); await page.mouse.down();
      await page.mouse.move((x1 + x2) / 2, (y1 + y2) / 2, { steps: 4 }); await page.mouse.move(x2, y2, { steps: 4 });
      await page.mouse.up();
    } else {
      await clickSquare(page, '#game-board', uci.slice(0, 2), g.player);
      await clickSquare(page, '#game-board', uci.slice(2, 4), g.player);
    }
    const before = g.moves.length;
    await waitFor(async () => { const c = await currentGame(page); return !c || c.moves.length >= before + 2 || c.result; }, 90000, `the engine's reply to ${uci}`);
  }
}

async function shot(page, name) { await page.waitForTimeout(350); await page.screenshot({ path: path.join(shots, `${name}.png`) }); }

async function openPicker(page) {
  await page.waitForSelector('#play');
  if (await page.locator('#picker-card').isVisible()) { await page.click('#picker-card'); await page.waitForSelector('.sheet.open'); await page.waitForTimeout(400); }
}
async function closePicker(page) { if (await page.locator('#picker-done').isVisible()) { await page.click('#picker-done'); await page.waitForTimeout(350); } }
async function choose(page, selector) { await openPicker(page); await page.click(`.sheet ${selector}, .picker-inline ${selector}`); }

async function run(name) {
  const type = pw[name];
  const browser = await type.launch();
  const ctx = await browser.newContext({ ...PHONE, serviceWorkers: 'allow' });
  const page = await ctx.newPage();
  currentPage = page;
  page.on('worker', w => w.on('console', m => { if (m.type() === 'error') console.log(`[${name} worker] ${m.text()}`); }));
  const errors = [];
  // Uncaught errors fail the run. Console errors are only reported: network failures are expected while offline,
  // and the deliberately broken engine reports its own error (WebKit passes it to the page as "broken").
  // (Playwright's own polling, refused by the page's policy after a hard reload, is not the app's error.)
  page.on('pageerror', e => e.message !== 'broken' && !/eval at evaluate/.test(e.stack || '') && errors.push('pageerror: ' + e.message + (e.stack ? '\n' + e.stack.split('\n').slice(0, 4).join('\n') : '')));
  page.on('console', m => { if (m.type() === 'error' && !/404|Failed to load resource/.test(m.text())) console.log(`[${name} console] ${m.text()}`); });
  const tag = s => `${name}-${s}`;
  const phone = name === 'chromium'; // full screenshot set from Chromium; WebKit keeps its own phone set too
  const S = async (n) => shot(page, `${name}-phone-${n}`);

  await step(name, 'loads under the base path, nothing outside it', async () => {
    const res = await page.goto(URL0);
    assert(res.ok(), 'status ' + res.status());
    await page.waitForSelector('#home-board .piece');
    await page.waitForFunction(() => document.querySelectorAll('#home-board .piece').length === 32);
    const csp = res.headers()['content-security-policy'] || '';
    assert(csp.includes("default-src 'self'"), 'no CSP');
    const root = await page.request.get(`http://localhost:${port}/`);
    assert(root.status() === 404, 'the origin root should not be ours: ' + root.status());
    await page.waitForFunction(() => navigator.serviceWorker && navigator.serviceWorker.controller, null, { timeout: 15000 }).catch(() => {});
    await S('01-home');
  });

  await step(name, 'the picker opens from its card and keeps choices', async () => {
    await openPicker(page);
    await page.waitForSelector('.engine-pick');
    await S('02-picker');
    await page.click('.sheet [data-choice="mode"] [data-value="level"]');
    await page.click('.sheet [data-level="1"]');
    await S('03-picker-level');
    await closePicker(page);
    const sub = await page.textContent('.pc-sub');
    assert(/Level 1/.test(sub), 'summary says ' + sub);
  });

  await step(name, '"Zeist" at the top left of Home leads to /chess, and only under /chess/', async () => {
    await page.goto(URL0);
    await page.waitForSelector('#to-zeist');
    assert(await page.getAttribute('#to-zeist', 'href') === '/chess', 'href: ' + await page.getAttribute('#to-zeist', 'href'));
    assert((await page.textContent('#to-zeist')).trim() === 'Zeist', 'label: ' + await page.textContent('#to-zeist'));
    assert(await page.locator('.brand-row .brand').isVisible(), 'the name sits below');
    const box = await page.locator('#home-board').boundingBox();
    assert(box.y + box.height <= PHONE.viewport.height, 'the board still fits');
    const p2 = await ctx.newPage();
    await p2.goto(URL2);
    await p2.waitForSelector('#home-board .piece');
    assert(!(await p2.locator('#to-zeist').count()), 'no way back outside /chess/');
    assert(await p2.locator('header.top .brand').isVisible(), 'the name stays at the top');
    await p2.close();
  });

  await step(name, "an engine's address opens Home with it picked, and it plays", async () => {
    const at = async (p, opts) => page.request.get(URL0 + p, { maxRedirects: 0, ...opts });
    const slash = await at('zeist/');
    assert(slash.status() === 308 && slash.headers().location === BASE_PATH + 'zeist', 'zeist/ redirects: ' + slash.status() + ' ' + slash.headers().location);
    const reserved = await at('engines');
    assert(reserved.status() === 404, 'engines is not an engine address: ' + reserved.status());
    const catalog = await at('engines/catalog.json');
    assert(catalog.ok() && (await catalog.json()), 'packs still served under engines/');
    // An id that isn't in the catalog: Home as usual.
    await page.goto(URL0 + 'no-such-engine');
    await page.waitForSelector('#play');
    assert(page.url() === URL0, 'address kept plain: ' + page.url());
    await page.goto(URL0 + 'zeist');
    await page.waitForSelector('#play');
    assert(page.url() === URL0, 'address after opening: ' + page.url());
    const picked = await page.textContent('#picker-card .pc-name');
    assert(picked.trim() === 'Zeist', 'picked: ' + picked);
    await S('01b-home-engine-address');
    await page.click('#play');
    await page.waitForSelector('#game-board .piece', { timeout: 60000 });
    await playMoves(page, 1);
    const g = await currentGame(page);
    assert(g && g.engineID === 'zeist' && g.moves.length >= 2, 'zeist game: ' + (g && g.moves.join(' ')));
  });

  await step(name, `downloads ${SECOND} in Settings, every file checked`, async () => {
    await page.goto(URL0 + '#/settings');
    await page.waitForSelector(`[data-act="download"][data-id="${SECOND}"]`);
    await S('04-settings');
    await page.click(`[data-act="download"][data-id="${SECOND}"]`);
    await page.waitForSelector(`[data-act="delete"][data-id="${SECOND}"]`, { timeout: 120000 });
    const kept = await page.evaluate(async id => (await (await caches.open('zc-packs')).keys()).filter(r => r.url.includes(`/engines/${id}/`)).length, SECOND);
    assert(kept >= 3, 'pack files kept: ' + kept);
    await page.locator('#engines').scrollIntoViewIfNeeded();
    await S('05-settings-engines');
    // The delete confirmation, then keep it.
    await page.click(`[data-act="delete"][data-id="${SECOND}"]`);
    await page.waitForSelector(`[data-act="keep"][data-id="${SECOND}"]`);
    await page.locator(`[data-engine-row="${SECOND}"]`).scrollIntoViewIfNeeded();
    await S('06-settings-delete');
    await page.click(`[data-act="keep"][data-id="${SECOND}"]`);
  });

  await step(name, 'plays Stockfish Lite, fetched on first play, by tap and by drag', async () => {
    await page.goto(URL0);
    await page.waitForSelector('#play');
    await choose(page, '[data-engine="stockfish-lite"]');
    await closePicker(page);
    await page.click('#play');
    await page.waitForSelector('#game-board .piece', { timeout: 60000 });
    await playMoves(page, 4, { drag: true });
    const g = await currentGame(page);
    assert(g && g.engineID === 'stockfish-lite' && g.moves.length >= 8, 'moves: ' + (g && g.moves.join(' ')));
    assert(g.packSHA && g.packSHA.length === 64 && g.engineSettings && g.seed, 'record fields');
    await S('07-game');
  });

  await step(name, 'arrow keys step back through the game in progress', async () => {
    await page.keyboard.press('ArrowLeft');
    await page.keyboard.press('ArrowLeft');
    await page.waitForSelector('#moveline .mv.at');
    const status = await page.textContent('#status');
    assert(/Looking at move/.test(status), 'status: ' + status);
    await S('08-game-looking-back');
    await page.keyboard.press('End');
  });

  await step(name, 'Home offers Continue for the game in progress', async () => {
    await page.click('.bar a.round');
    await page.waitForSelector('#play');
    assert((await page.textContent('#play')).trim() === 'Continue', 'button says ' + await page.textContent('#play'));
    await S('09-home-continue');
  });

  await step(name, `plays ${SECOND}, a second engine`, async () => {
    await choose(page, `[data-engine="${SECOND}"]`);
    await page.waitForTimeout(300);
    await closePicker(page);
    assert((await page.textContent('#play')).trim() === 'Play', 'button should say Play after a change');
    await page.click('#play');
    await page.waitForSelector('#game-board .piece');
    await playMoves(page, 3);
    const g = await currentGame(page);
    assert(g.engineID === SECOND && g.moves.length >= 6, 'second engine game');
    const all = await games(page);
    assert(all.some(x => x.engineID === 'stockfish-lite' && x.ending === 'abandoned'), 'the first game is kept as abandoned');
  });

  await step(name, 'reloads with no network and continues the game', async () => {
    await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 15000 });
    await page.goto(URL0);
    await page.waitForSelector('#play');
    await ctx.setOffline(true);
    await page.reload();
    await page.waitForSelector('#play');
    assert((await page.textContent('#play')).trim() === 'Continue', 'Continue offline');
    await S('10-offline-home');
    await page.click('#play');
    await page.waitForSelector('#game-board .piece');
    const before = (await currentGame(page)).moves.length;
    await playMoves(page, 2);
    assert((await currentGame(page)).moves.length >= before + 4, 'engine answered offline');
    await ctx.setOffline(false);
  });

  await step(name, 'resigns, sees the result, finds the game in Recent and steps through it', async () => {
    await page.click('#resign');
    await page.waitForSelector('#resign-yes');
    await S('11-game-resign');
    await page.click('#resign-yes');
    await page.waitForSelector('.result-title');
    await S('12-game-end');
    const id = (await games(page))[0].id;
    await page.goto(URL0 + '#/recent');
    await page.waitForSelector('.game-row');
    const rows = await page.locator('.game-row').count();
    assert(rows >= 2, 'rows: ' + rows);
    await S('13-recent');
    await page.click(`a[href="#/recent/${id}"]`);
    await page.waitForSelector('#replay-board .piece');
    const end = await page.textContent('#replay-move');
    await page.keyboard.press('ArrowLeft');
    await page.keyboard.press('ArrowLeft');
    const back = await page.textContent('#replay-move');
    assert(end !== back, 'arrow keys move');
    await page.keyboard.press('Home');
    assert((await page.textContent('#replay-move')).includes('The start'), 'Home goes to the start');
    await page.keyboard.press('ArrowRight');
    await S('14-replay');
  });

  await step(name, 'a timed game runs its clocks and the engine plays on its clock', async () => {
    await page.goto(URL0);
    await choose(page, '[data-tc="60+1"]');
    await page.waitForTimeout(200);
    await S('15-picker-clock');
    await closePicker(page);
    await page.click('#play');
    await page.waitForSelector('#game-board .piece');
    await playMoves(page, 2);
    const g = await currentGame(page);
    assert(g.timeControl && g.timeControl.base === 60 && g.timeClass === 'bullet', 'time control kept');
    assert(g.clocks && g.clocks.length === g.moves.length, 'a clock reading for every move');
    const shown = await page.textContent('#you .clock');
    assert(/^\d:\d\d/.test(shown.trim()), 'clock shows ' + shown);
    assert(!(await page.locator('#undo').count()), 'no undo with a clock');
    await S('16-game-clock');
    await page.click('#resign'); await page.click('#resign-yes');
    await page.waitForSelector('.result-title');
    await choose(page, '[data-tc="none"]').catch(() => {});
  });

  await step(name, 'theme and pieces change and stay', async () => {
    await page.goto(URL0 + '#/settings');
    await page.click('[data-theme="walnut"]');
    await page.click('[data-set="pirouetti"]');
    await page.waitForTimeout(300);
    await S('17-settings-walnut-round');
    await page.goto(URL0);
    await page.reload();
    await page.waitForSelector('#home-board .piece');
    const src = await page.getAttribute('#home-board .piece', 'src');
    assert(src.includes('pieces/pirouetti/'), 'pieces: ' + src);
    await S('18-home-walnut-round');
    await page.goto(URL0 + '#/settings');
    await page.click('[data-theme="bone"]');
    await page.click('[data-set="cburnett"]');
  });

  await step(name, 'a broken engine ends in a calm message, the board stays usable', async () => {
    // Damage the downloaded pack's program, as a crash or lack of memory would end it.
    await page.evaluate(async id => {
      const c = await caches.open('zc-packs');
      for (const r of await c.keys()) if (r.url.includes(`/engines/${id}/`) && r.url.endsWith(`${id}.js`)) await c.put(r, new Response('throw new Error("broken")', { headers: { 'content-type': 'text/javascript' } }));
    }, SECOND);
    await page.goto(URL0);
    await choose(page, `[data-engine="${SECOND}"]`);
    await page.click('.sheet [data-choice="side"] [data-value="b"], .picker-inline [data-choice="side"] [data-value="b"]');
    await closePicker(page);
    await page.click('#play');
    await page.waitForSelector('#retry', { timeout: 90000 });
    const status = await page.textContent('#status');
    assert(/stopped before it could move/.test(status), 'status: ' + status);
    await S('19-engine-failed');
    await page.click('#resign');
    await page.waitForSelector('.result-title');
    // Delete and download again: the pack is whole once more.
    // Bytes that no longer match: the service worker removed the pack, so it is offered for download again.
    await page.goto(URL0 + '#/settings');
    await page.waitForSelector(`[data-act="download"][data-id="${SECOND}"]`);
    await page.click(`[data-act="download"][data-id="${SECOND}"]`);
    await page.waitForSelector(`[data-act="delete"][data-id="${SECOND}"]`, { timeout: 120000 });
    await choose(page, '[data-choice="side"] [data-value="w"]').catch(() => {});
  });

  await step(name, 'export writes PGN with the game', async () => {
    await page.goto(URL0 + '#/settings');
    const [dl] = await Promise.all([page.waitForEvent('download'), page.click('#export-pgn')]);
    const file = await dl.path();
    const text = fs.readFileSync(file, 'utf8');
    assert(/\[Event "Zeist Chess"\]/.test(text) && /\[Site "Web"\]/.test(text) && /TimeControl "60\+1"/.test(text) && /%clk/.test(text), 'PGN content');
  });

  // Desktop: the same screens with the board on the left and a column beside it.
  if (phone) {
    await step(name, 'desktop screens', async () => {
      await page.setViewportSize(DESKTOP);
      const D = n => shot(page, `${name}-desktop-${n}`);
      await page.goto(URL0);
      await page.waitForSelector('.picker-inline .engine-pick');
      await D('01-home');
      await page.click('.picker-inline [data-choice="mode"] [data-value="rating"]').catch(() => {});
      await page.click('.picker-inline [data-engine="stockfish-lite"]');
      await page.click('.picker-inline [data-choice="mode"] [data-value="rating"]');
      await D('02-home-rating');
      await page.click('.picker-inline [data-choice="mode"] [data-value="level"]');
      await page.click('.picker-inline [data-tc="180+2"]');
      await page.click('#play');
      await page.waitForSelector('#game-board .piece');
      await playMoves(page, 5);
      await D('03-game-clock');
      await page.keyboard.press('ArrowLeft');
      await page.keyboard.press('ArrowLeft');
      await page.keyboard.press('ArrowLeft');
      await D('04-game-looking-back');
      await page.keyboard.press('End');
      await page.click('#resign'); await page.click('#resign-yes');
      await page.waitForSelector('.result-title');
      await D('05-game-end');
      await page.goto(URL0);
      await page.click('.picker-inline [data-tc="none"]');
      await page.click('#play');
      await page.waitForSelector('#game-board .piece');
      await playMoves(page, 3);
      await D('06-game');
      await page.goto(URL0 + '#/recent');
      await page.waitForSelector('.game-row');
      await D('07-recent');
      await page.click('.game-row');
      await page.waitForSelector('#replay-board .piece');
      await D('08-replay');
      await page.goto(URL0 + '#/settings');
      await page.waitForSelector('.engine-row');
      await D('09-settings');
      await page.locator('#engines').scrollIntoViewIfNeeded();
      await D('10-settings-engines');
      await page.setViewportSize(PHONE.viewport);
    });
  }

  // Audit F07: only the bytes the catalog lists ever run.
  const TAMPER = 'fairy-stockfish';
  await step(name, "a pack whose manifest isn't the catalog's is refused, even when its own checksums hold", async () => {
    await page.goto(URL0 + '#/settings');
    await page.waitForSelector(`[data-act="download"][data-id="${TAMPER}"]`);
    await page.evaluate(id => {
      // The server answers with another manifest: its entry is a different program, listed with that program's
      // own size and sha256, so every file matches the manifest it came with.
      const real = window.fetch.bind(window);
      const evil = new TextEncoder().encode('postMessage("evil")');
      window.__tampered = (async () => {
        const d = await crypto.subtle.digest('SHA-256', evil);
        return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
      })();
      window.fetch = async (input, init) => {
        const url = String(input && input.url || input);
        if (url.endsWith(`/engines/${id}/manifest.json`)) {
          const m = await (await real(input, init)).json();
          m.entry = 'evil.js';
          m.files = [...m.files, { path: 'evil.js', bytes: evil.byteLength, sha256: await window.__tampered }];
          return new Response(JSON.stringify(m), { headers: { 'content-type': 'application/json' } });
        }
        if (url.endsWith(`/engines/${id}/evil.js`)) return new Response(evil, { headers: { 'content-type': 'text/javascript' } });
        return real(input, init);
      };
    }, TAMPER);
    await page.click(`[data-act="download"][data-id="${TAMPER}"]`);
    await page.waitForSelector(`[data-act="retry"][data-id="${TAMPER}"]`, { timeout: 60000 });
    const kept = await page.evaluate(async id => (await (await caches.open('zc-packs')).keys()).map(r => r.url).filter(u => u.includes(`/engines/${id}/`)), TAMPER);
    assert(kept.length === 0, 'nothing of it is kept: ' + kept.join(', '));
    await page.reload();
  });

  await step(name, 'a pack file not downloaded here is never handed out from the network', async () => {
    await page.waitForFunction(() => navigator.serviceWorker && navigator.serviceWorker.controller, null, { timeout: 15000 });
    const r = await page.evaluate(async id => {
      const res = await fetch(`engines/${id}/${id}.js`);
      return { ok: res.ok, status: res.status };
    }, TAMPER);
    assert(!r.ok, 'an undownloaded program was served: ' + r.status);
    const listed = await page.evaluate(async id => (await fetch(`engines/${id}/manifest.json`)).ok, SECOND);
    assert(listed, 'a downloaded pack is still served');
  });

  await step(name, "an engine's worker cannot fetch past the checks with the shelf's download mark", async () => {
    // A worker of this page, as an engine's code would be, asks for a file no manifest here lists. The worker is a
    // same-origin script (the page's policy allows no other), put in the app's folder for this step only.
    const file = path.join(web, 'public', 'zz-test-worker.js');
    fs.writeFileSync(file, "const u = new URL(location.href).searchParams.get('u');\n" +
      "fetch(u, { headers: { 'x-zc-download': '1' } }).then(r => postMessage(r.status), e => postMessage('error ' + e.message));\n");
    let r;
    try {
      r = await page.evaluate(async id => {
        const url = new URL(`engines/${id}/${id}.js`, document.baseURI).href;
        const w = new Worker(new URL('zz-test-worker.js?u=' + encodeURIComponent(url), document.baseURI).href);
        return new Promise(res => { w.onmessage = e => { w.terminate(); res(e.data); }; w.onerror = e => res('worker error ' + (e.message || '')); setTimeout(() => res('no answer'), 10000); });
      }, TAMPER);
    } finally { fs.rmSync(file, { force: true }); }
    assert(r === 404, 'the worker got: ' + r);
  });

  await step(name, 'bytes overwritten in the packs cache are refused, and the pack is downloaded again', async () => {
    // Cache Storage belongs to the whole site: another script on it could write to zc-packs.
    const r = await page.evaluate(async id => {
      const c = await caches.open('zc-packs');
      const key = (await c.keys()).find(k => k.url.includes(`/engines/${id}/`) && k.url.endsWith(`${id}.js`));
      await c.put(key, new Response('postMessage("not checked")', { headers: { 'content-type': 'text/javascript' } }));
      const res = await fetch(key.url);
      const manifest = await c.match(new URL('manifest.json', key.url).href);
      return { status: res.status, kept: !!manifest };
    }, SECOND);
    assert(r.status === 404, 'served: ' + r.status);
    assert(!r.kept, 'the pack is marked for download again');
    await page.goto(URL0 + '#/settings');
    await page.waitForSelector(`[data-act="download"][data-id="${SECOND}"]`);
    const said = await page.textContent(`[data-engine-row="${SECOND}"]`);
    await page.click(`[data-act="download"][data-id="${SECOND}"]`);
    await page.waitForSelector(`[data-act="delete"][data-id="${SECOND}"]`, { timeout: 120000 });
    assert(/changed in this browser/.test(said), 'the row says why: ' + said);
  });

  // The catalog the page reads, and the copy kept in Cache Storage, both made to say something else for one engine.
  const recatalog = (id, how) => page.evaluate(async ({ id, how }) => {
    const real = window.__realFetch || (window.__realFetch = window.fetch.bind(window));
    const url = new URL('engines/catalog.json', document.baseURI).href;
    const base = await (await real(url, { cache: 'no-store' })).json();
    const c = JSON.parse(JSON.stringify(base));
    if (how === 'moved') for (const e of c.engines) if (e.id === id) { e.version += '-later'; e.manifest_sha256 = 'f'.repeat(64); }
    if (how === 'dropped') c.engines = c.engines.filter(e => e.id !== id);
    const body = how === 'real' ? JSON.stringify(base) : JSON.stringify(c);
    await (await caches.open('zc-meta')).put(url, new Response(body, { headers: { 'content-type': 'application/json' } }));
    window.fetch = how === 'real' ? real : async (input, init) => {
      const u = String(input && input.url || input);
      if (u.endsWith('/engines/catalog.json')) return new Response(body, { headers: { 'content-type': 'application/json' } });
      return real(input, init);
    };
    await (await import('./js/shelf.js')).refresh();
  }, { id, how });
  // Starts an engine's worker from the page, as a game would. True when it answers.
  const starts = id => page.evaluate(async id => {
    const shelf = await import('./js/shelf.js');
    const engine = await import('./js/engine.js');
    engine.release();
    try { await engine.warm(shelf.engine(id).manifest); return true; } catch (e) { return String(e && e.message || e); } finally { engine.release(); }
  }, id);

  await step(name, 'the catalog moving on never removes an installed pack: it starts online and offline, and the update is offered', async () => {
    // (Settings first: in WebKit, opening an address that differs only after # loads the page again.)
    await page.goto(URL0 + '#/settings');
    await page.waitForSelector(`[data-act="delete"][data-id="${SECOND}"]`);
    await recatalog(SECOND, 'moved');
    const offer = await page.waitForSelector(`[data-act="update"][data-id="${SECOND}"]`, { timeout: 10000 }).then(h => h.textContent()).catch(() => '');
    const online = await starts(SECOND);
    await ctx.setOffline(true);
    const offline = await starts(SECOND);
    await ctx.setOffline(false);
    const kept = await page.evaluate(async id => !!(await (await caches.open('zc-packs')).match(new URL(`engines/${id}/manifest.json`, document.baseURI).href)), SECOND);
    await recatalog(SECOND, 'real');
    assert(online === true, 'online: ' + online);
    assert(offline === true, 'offline: ' + offline);
    assert(kept, 'the pack is still installed');
    assert(/Update to version .*-later/.test(offer), 'the update is offered: ' + offer);
  });

  await step(name, 'the catalog dropping an engine leaves its installed pack playable', async () => {
    await page.goto(URL0 + '#/settings');
    await page.waitForSelector(`[data-act="delete"][data-id="${SECOND}"]`);
    await recatalog(SECOND, 'dropped');
    await page.waitForTimeout(500);
    const listed = await page.locator(`[data-act="delete"][data-id="${SECOND}"]`).count();
    const ok = await starts(SECOND);
    await recatalog(SECOND, 'real');
    assert(ok === true, 'it starts: ' + ok);
    assert(listed === 1, 'it is still listed as in this browser');
  });

  await step(name, 'the pack and the catalog copy both rewritten in the cache are refused: only pinned manifests run', async () => {
    const r = await page.evaluate(async id => {
      const hex = async b => [...new Uint8Array(await crypto.subtle.digest('SHA-256', b))].map(x => x.toString(16).padStart(2, '0')).join('');
      const packs = await caches.open('zc-packs');
      const at = p => new URL(`engines/${id}/${p}`, document.baseURI).href;
      const m = await (await packs.match(at('manifest.json'))).json();
      const evil = new TextEncoder().encode('postMessage("evil")');
      m.version += '-evil';
      m.files = [...m.files, { path: 'evil.js', bytes: evil.byteLength, sha256: await hex(evil) }];
      const raw = new TextEncoder().encode(JSON.stringify(m));
      await packs.put(at('evil.js'), new Response(evil, { headers: { 'content-type': 'text/javascript' } }));
      await packs.put(at('manifest.json'), new Response(raw, { headers: { 'content-type': 'application/json' } }));
      // The catalog copy kept in Cache Storage rewritten to agree with it.
      const curl = new URL('engines/catalog.json', document.baseURI).href;
      const meta = await caches.open('zc-meta');
      const c = await (await meta.match(curl)).json();
      for (const e of c.engines) if (e.id === id) { e.version = m.version; e.manifest_sha256 = await hex(raw); e.files = m.files; }
      await meta.put(curl, new Response(JSON.stringify(c), { headers: { 'content-type': 'application/json' } }));
      const out = { evil: (await fetch(at('evil.js'))).status, entry: (await fetch(at(`${id}.js`))).status };
      for (const k of await packs.keys()) if (k.url.startsWith(at(''))) await packs.delete(k);
      return out;
    }, SECOND);
    await recatalog(SECOND, 'real');
    assert(r.evil === 404, 'a file only the rewritten manifest lists: ' + r.evil);
    assert(r.entry === 404, 'an unpinned manifest: ' + r.entry);
    await page.goto(URL0 + '#/settings');
    await page.reload();
    await page.waitForSelector(`[data-act="download"][data-id="${SECOND}"]`);
    await page.click(`[data-act="download"][data-id="${SECOND}"]`);
    await page.waitForSelector(`[data-act="delete"][data-id="${SECOND}"]`, { timeout: 120000 });
  });

  await step(name, "a version the app doesn't know yet asks for a reload and isn't installed", async () => {
    await page.goto(URL0 + '#/settings');
    await page.waitForSelector(`[data-act="download"][data-id="${TAMPER}"]`);
    await page.evaluate(async id => {
      // The server lists a version published after this app was: catalog and manifest agree, but no pin covers it.
      const real = window.__realFetch || (window.__realFetch = window.fetch.bind(window));
      const hex = async b => [...new Uint8Array(await crypto.subtle.digest('SHA-256', b))].map(x => x.toString(16).padStart(2, '0')).join('');
      const c = await (await real('engines/catalog.json', { cache: 'no-store' })).json();
      const e = c.engines.find(x => x.id === id);
      const m = { ...e };
      for (const k of ['manifest', 'manifest_sha256', 'checks']) delete m[k];
      m.version += '-newer';
      const raw = new TextEncoder().encode(JSON.stringify(m));
      e.version = m.version; e.manifest_sha256 = await hex(raw);
      const body = JSON.stringify(c);
      window.fetch = async (input, init) => {
        const u = String(input && input.url || input);
        if (u.endsWith('/engines/catalog.json')) return new Response(body, { headers: { 'content-type': 'application/json' } });
        if (u.endsWith(`/engines/${id}/manifest.json`)) return new Response(raw, { headers: { 'content-type': 'application/json' } });
        return real(input, init);
      };
      await (await import('./js/shelf.js')).refresh();
    }, TAMPER);
    await page.click(`[data-act="download"][data-id="${TAMPER}"]`);
    await page.waitForSelector(`[data-act="retry"][data-id="${TAMPER}"]`, { timeout: 60000 });
    const row = await page.textContent(`[data-engine-row="${TAMPER}"]`);
    const kept = await page.evaluate(async id => {
      const c = await caches.open('zc-packs');
      let any = false;
      for (const r of await c.keys()) if (r.url.includes(`/engines/${id}/`)) { any = true; await c.delete(r); }
      return any;
    }, TAMPER);
    await page.evaluate(() => { window.fetch = window.__realFetch; localStorage.clear(); });
    await page.reload();
    assert(/reload/i.test(row), 'the row says to reload: ' + row);
    assert(!kept, 'nothing was installed');
  });

  await step(name, "a pack updated since it was chosen isn't installed without asking", async () => {
    await page.goto(URL0 + '#/settings');
    await page.waitForSelector(`[data-act="download"][data-id="${TAMPER}"]`);
    await page.evaluate(async id => {
      // The server has moved on to another version since this page read the list.
      const real = window.fetch.bind(window);
      const hex = async b => [...new Uint8Array(await crypto.subtle.digest('SHA-256', b))].map(x => x.toString(16).padStart(2, '0')).join('');
      const m = { ...(await (await real('engines/catalog.json')).json()).engines.find(e => e.id === id) };
      for (const k of ['manifest', 'manifest_sha256', 'checks']) delete m[k];
      m.version = m.version + '-later';
      const raw = new TextEncoder().encode(JSON.stringify(m));
      const sha = await hex(raw);
      window.fetch = async (input, init) => {
        const url = String(input && input.url || input);
        if (url.endsWith(`/engines/${id}/manifest.json`)) return new Response(raw, { headers: { 'content-type': 'application/json' } });
        if (url.endsWith('/engines/catalog.json')) {
          const c = await (await real(input, init)).json();
          for (const e of c.engines) if (e.id === id) { e.version = m.version; e.manifest_sha256 = sha; }
          return new Response(JSON.stringify(c), { headers: { 'content-type': 'application/json' } });
        }
        return real(input, init);
      };
    }, TAMPER);
    await page.click(`[data-act="download"][data-id="${TAMPER}"]`);
    await page.waitForSelector(`[data-act="retry"][data-id="${TAMPER}"]`, { timeout: 60000 });
    const row = await page.textContent(`[data-engine-row="${TAMPER}"]`);
    assert(/-later/.test(row), 'the row shows the version there is now: ' + row);
    const kept = await page.evaluate(async id => (await (await caches.open('zc-packs')).keys()).some(r => r.url.includes(`/engines/${id}/`)), TAMPER);
    assert(!kept, 'nothing was installed');
    await page.evaluate(() => localStorage.clear());
    await page.reload();
  });

  await step(name, 'a game keeps the owner it was started under (audit F10)', async () => {
    const c3 = await browser.newContext({ ...PHONE });
    const p3 = await c3.newPage();
    await p3.goto(URL0);
    await p3.waitForSelector('#home-board .piece');
    const r = await p3.evaluate(async () => {
      const log = await import('./js/log.js');
      // The stored record itself, whoever it is shown to.
      const owner = id => new Promise((res, rej) => {
        const o = indexedDB.open('zeist-chess');
        o.onerror = () => rej(o.error);
        o.onsuccess = () => { const r = o.result.transaction('games').objectStore('games').get(id); r.onsuccess = () => { o.result.close(); res((r.result && r.result.account) || null); }; };
      });
      const base = { player: 'w', engine: { manifest: { id: 'test', name: 'Test', version: '1' } }, level: 1, adaptive: false, settings: { level: 1 }, seed: 1 };
      // Started signed in as A; A's session ends while the board is open; the board saves; B signs in.
      log.setAccount({ owner: 'owner-A', handle: 'a' });
      const a = log.begin(base);
      await log.save(a);
      log.setAccount(null);
      await log.save({ ...a, moves: ['e2e4'] });
      const afterSignOut = await owner(a.id);
      log.setAccount({ owner: 'owner-B', handle: 'b' });
      await log.stamp('owner-B', 'b');
      const afterB = await owner(a.id);
      // A guest game: claimed once, by the first account to sign in.
      log.setAccount(null);
      const g = log.begin(base);
      await log.save(g);
      await log.stamp('owner-B', 'b');
      log.setAccount({ owner: 'owner-C', handle: 'c' });
      await log.save({ ...g, moves: ['e2e4'] });
      await log.stamp('owner-C', 'c');
      const guest = await owner(g.id);
      // Games lists only the games of whoever is signed in; signed out, only guest games.
      const h = log.begin(base);
      log.setAccount(null);
      await log.save(h);
      const listed = async () => (await log.all()).map(x => x.id);
      log.setAccount({ owner: 'owner-B', handle: 'b' });
      const forB = await listed();
      log.setAccount(null);
      const forGuest = await listed();
      log.setAccount({ owner: 'owner-A', handle: 'a' });
      const forA = await listed();
      const view = { bSeesA: forB.includes(a.id), bSeesGuest: forB.includes(h.id), guestSeesA: forGuest.includes(a.id), guestSeesGuest: forGuest.includes(h.id), aSeesA: forA.includes(a.id), bOpensA: false };
      log.setAccount({ owner: 'owner-B', handle: 'b' });
      view.bOpensA = !!(await log.get(a.id));
      log.setAccount(null);
      await log.remove(h.id);
      await log.remove(a.id); await log.remove(g.id);
      return { afterSignOut, afterB, guest, view };
    });
    await c3.close();
    assert(r.afterSignOut === 'owner-A', "a copy saved signed out keeps A: " + r.afterSignOut);
    assert(r.afterB === 'owner-A', "A's game never becomes B's: " + r.afterB);
    assert(r.guest === 'owner-B', 'a guest game is claimed once: ' + r.guest);
    const v = r.view;
    assert(!v.bSeesA && !v.bSeesGuest && !v.bOpensA, "B sees only B's games: " + JSON.stringify(v));
    assert(!v.guestSeesA && v.guestSeesGuest, 'signed out, only guest games: ' + JSON.stringify(v));
    assert(v.aSeesA, "A's games come back for A");
  });

  if (name === 'chromium') {
    await step(name, 'a forced reload that skips the service worker says at once what to do', async () => {
      // A hard reload (shift-reload): the browser loads the page past its service worker.
      await page.goto(URL0);
      await page.waitForSelector('#home-board .piece');
      const cdp = await ctx.newCDPSession(page);
      await Promise.all([page.waitForEvent('load'), cdp.send('Page.reload', { ignoreCache: true })]);
      await cdp.detach();
      await page.waitForSelector('#home-board .piece');
      const r = await page.evaluate(async () => {
        const engine = await import('./js/engine.js');
        const t = performance.now();
        try { await engine.warm({ id: 'zeist', version: '1', entry: 'zeist.js', files: [] }); return { ok: true }; }
        catch (e) { return { ok: false, ms: performance.now() - t, message: e.message }; }
      });
      const controlled = await page.evaluate(() => !!navigator.serviceWorker.controller);
      assert(!controlled, 'the page should be loaded past the service worker');
      assert(!r.ok, 'an engine started without the service worker');
      assert(r.ms < 3000, 'it took ' + Math.round(r.ms) + ' ms to say so');
      assert(/reload/i.test(r.message) && !/try again/i.test(r.message), 'message: ' + r.message);
      await page.reload();
    });

    await step(name, 'signed in under Zeist: the username shows, games carry the account', async () => {
      const c2 = await browser.newContext({ ...PHONE });
      await c2.route('**/api/me', r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ user: { handle: 'quietknight', display_name: 'A. Player', owner: 'owner-test-1' }, providers: { google: true } }) }));
      const p2 = await c2.newPage();
      await p2.goto(URL0 + '#/settings');
      await p2.waitForSelector('.acc-name');
      assert((await p2.textContent('#account')).includes('@quietknight'), 'username shown');
      await shot(p2, `${name}-phone-20-settings-signed-in`);
      await c2.route('**/api/me', r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ user: null, providers: { google: true } }) }));
      await p2.goto(URL0 + '#/recent');
      await p2.reload();
      await p2.waitForSelector('.account-row a');
      const href = await p2.getAttribute('.account-row a', 'href');
      assert(href.startsWith('/welcome?return=' + encodeURIComponent(BASE_PATH)), 'sign-in link: ' + href);
      await shot(p2, `${name}-phone-21-recent-signed-out-on-zeist`);
      await c2.close();
    });
  }

  if (errors.length) fail(name, 'no page errors', new Error(errors.slice(0, 5).join('\n')));
  else ok(name, 'no page errors');
  await browser.close();
}

try {
  for (const b of browsers) await run(b);
} finally {
  server.kill();
  server2.kill();
}
console.log('\n' + results.join('\n'));
console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
