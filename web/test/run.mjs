#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Plays the engine pages (/chess/vs/<id>/) headless, in Chromium and WebKit (Playwright), from local servers that
// answer as Cloudflare does (scripts/serve.mjs: static files from site/, then the Worker's handler). It checks:
//   engines.json, its shape and cache lifetime; an unknown engine or the base itself going to /chess;
//   Stockfish Lite's start screen (levels 1 to 10, side, clocks none, 10+5 and 15+10) and Maia's (a rating);
//   a game at level 1 with no clock, the pack downloaded straight from the packs' server (CORS) with no request to
//   the Worker; Back to /chess and Continue; a reload with no network and the engine still answering; a 10+5 game
//   with its clocks, resigned from the menu; a broken engine ending in a calm message; packs through the Worker when
//   the packs' server sends no CORS headers; a signed-in name; and no request to /api/rated anywhere.
// Screenshots of the start and game screens, phone and desktop, go to SHOTS (default web/screenshots/).
//
//   PLAYWRIGHT_DIR=<folder with playwright installed> node test/run.mjs [chromium] [webkit] [--engines <dir>]
//
// The site must be built first (node scripts/assets.mjs, at the default base /chess/vs/). Packs come from a folder of
// packs with --engines (such as engines/dist), else from engines.zei.st.

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import http from 'node:http';
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
const engineDir = args.includes('--engines') ? path.resolve(args[args.indexOf('--engines') + 1]) : null;
const browsers = args.filter(a => a === 'chromium' || a === 'webkit');
if (!browsers.length) browsers.push('chromium', 'webkit');
const BASE = '/chess/vs/';
const SMALL = 'ethereal'; // the engine for the broken-engine and no-CORS checks: small, so they stay quick
const shots = process.env.SHOTS || path.join(web, 'screenshots');
fs.mkdirSync(shots, { recursive: true });
fs.mkdirSync(path.join(web, 'test-results'), { recursive: true });

const PHONE = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true };
const DESKTOP = { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 };

let failures = 0;
const results = [];
let currentPage = null;
async function step(browser, name, fn) {
  try { await fn(); results.push(`  ok    ${browser}: ${name}`); console.log(`ok    ${browser}: ${name}`); return true; } catch (e) {
    failures++;
    results.push(`  FAIL  ${browser}: ${name}: ${e && e.message || e}`);
    console.log(`FAIL  ${browser}: ${name}\n${e && e.stack || e}`);
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

// The packs' server, standing in for engines.zei.st: with CORS headers (as it will be once the bucket's rule is set)
// or without (as today). Files from --engines, else from engines.zei.st.
const packRequests = { cors: 0, plain: 0 };
async function packServer(cors) {
  const port = await freePort();
  const s = http.createServer(async (req, res) => {
    packRequests[cors ? 'cors' : 'plain']++;
    const key = decodeURIComponent(new URL(req.url, 'http://x').pathname.slice(1));
    const headers = cors ? { 'access-control-allow-origin': '*' } : {};
    try {
      let body = null;
      if (engineDir) {
        const p = path.resolve(engineDir, key);
        if (p.startsWith(engineDir + path.sep) && fs.existsSync(p) && fs.statSync(p).isFile()) body = fs.readFileSync(p);
      } else {
        const r = await fetch('https://engines.zei.st/' + key);
        if (r.ok) body = Buffer.from(await r.arrayBuffer());
      }
      if (!body) { res.writeHead(404, headers); res.end(); return; }
      res.writeHead(200, { ...headers, 'content-length': String(body.length), 'content-type': 'application/octet-stream' });
      res.end(body);
    } catch { res.writeHead(502, headers); res.end(); }
  });
  await new Promise(r => s.listen(port, '127.0.0.1', r));
  return { server: s, origin: `http://127.0.0.1:${port}/` };
}
const corsPacks = await packServer(true);
const plainPacks = await packServer(false);

// Two sites: A downloads packs from the CORS server; B is pointed at the server without CORS and falls back to its
// Worker. Every request either Worker would run for is logged, to count them.
const workerLog = { A: [], B: [] };
async function site(name, packs) {
  const port = await freePort();
  const p = spawn(process.execPath, [path.join(web, 'scripts/serve.mjs'), '--port', String(port), '--base', BASE, '--packs-origin', packs, '--zeist-stand-ins',
    ...(engineDir ? ['--engines', engineDir] : [])], { stdio: ['ignore', 'pipe', 'inherit'], env: { ...process.env, ZC_LOG: '1' } });
  await new Promise(res => p.stdout.once('data', res));
  p.stdout.on('data', d => { for (const l of String(d).split('\n')) if (l.startsWith('worker ')) workerLog[name].push(l.slice(7)); });
  return { proc: p, url: `http://localhost:${port}${BASE}`, origin: `http://localhost:${port}` };
}
const A = await site('A', corsPacks.origin);
const B = await site('B', plainPacks.origin);
console.log('serving', A.url, 'and', B.url, engineDir ? `(packs from ${engineDir})` : '(packs from engines.zei.st)');

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
async function clickSquare(page, sq, side) {
  const box = await page.locator('#board').boundingBox();
  const f = 'abcdefgh'.indexOf(sq[0]), r = 8 - Number(sq[1]);
  const c = side === 'b' ? 7 - f : f, w = side === 'b' ? 7 - r : r;
  const cell = box.width / 8;
  await page.mouse.click(box.x + (c + 0.5) * cell, box.y + (w + 0.5) * cell);
}
const PREFER = ['e2e4', 'g1f3', 'f1c4', 'b1c3', 'd2d3', 'e1g1', 'c2c3', 'h2h3', 'a2a3', 'd2d4'];
function pickMove(g) {
  const game = Game.fromMoves(g.moves, g.startFEN);
  const legal = game.legal().filter(m => !m.promotion || m.promotion === 'q');
  return (PREFER.map(u => legal.find(m => m.uci === u)).find(Boolean) || legal.find(m => m.capture) || legal[0]).uci;
}
/** Makes n moves as White, by tap or (the first) by drag, waiting each time for the engine's reply. */
async function playMoves(page, n, { drag = false } = {}) {
  for (let i = 0; i < n; i++) {
    const g = await waitFor(async () => { const c = await currentGame(page); return c && c.moves.length % 2 === (c.player === 'w' ? 0 : 1) ? c : null; }, 90000, 'my turn');
    const uci = pickMove(g);
    if (drag && i === 0) {
      const box = await page.locator('#board').boundingBox();
      const cell = box.width / 8, at = sq => [box.x + ('abcdefgh'.indexOf(sq[0]) + 0.5) * cell, box.y + (8 - Number(sq[1]) + 0.5) * cell];
      const [x1, y1] = at(uci.slice(0, 2)), [x2, y2] = at(uci.slice(2, 4));
      await page.mouse.move(x1, y1); await page.mouse.down();
      await page.mouse.move((x1 + x2) / 2, (y1 + y2) / 2, { steps: 4 }); await page.mouse.move(x2, y2, { steps: 4 });
      await page.mouse.up();
    } else {
      await clickSquare(page, uci.slice(0, 2), g.player);
      await clickSquare(page, uci.slice(2, 4), g.player);
    }
    const before = g.moves.length;
    await waitFor(async () => { const c = await currentGame(page); return !c || c.moves.length >= before + 2 || c.result; }, 90000, `the engine's reply to ${uci}`);
  }
}
async function shot(page, name) { await page.waitForTimeout(400); await page.screenshot({ path: path.join(shots, `${name}.png`) }); }
async function setUp(page, { level, side = 'w', clock = 'none' } = {}) {
  await page.waitForSelector('#go');
  if (level) await page.click(`#lvls [data-level="${level}"]`);
  await page.click(`#sides [data-side="${side}"]`);
  await page.click(`#clocks [data-clock="${clock}"]`);
}
/** Stands in for Zeist's own pages and API, which these local servers don't have. */
async function zeist(ctx, { user = null } = {}) {
  await ctx.route(/\/chess(\/(puzzles|learn))?(\?.*)?$/, r => r.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><title>Chess</title><h1>Zeist Chess stand-in</h1>' }));
  await ctx.route('**/api/me', r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ user }) }));
}

const requests = []; // every URL any page asked for, to check that /api/rated never is

async function run(name) {
  const browser = await pw[name].launch();
  const ctx = await browser.newContext({ ...PHONE, serviceWorkers: 'allow' });
  await zeist(ctx);
  ctx.on('request', r => requests.push(r.url()));
  const page = await ctx.newPage();
  currentPage = page;
  const errors = [];
  // Network failures while the test has cut the network are expected (WebKit reports some as page errors).
  let offline = false;
  page.on('pageerror', e => !offline && e.message !== 'broken' && !/eval at evaluate/.test(e.stack || '') && errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/404|Failed to load resource|CORS|Access-Control|access control|due to access/i.test(m.text())) console.log(`[${name} console] ${m.text()}`); });
  const S = n => shot(page, `${name}-phone-${n}`);

  await step(name, 'engines.json lists the engines, without Zeist, for five minutes', async () => {
    const r = await page.request.get(A.url + 'engines.json');
    assert(r.ok(), 'status ' + r.status());
    assert(/max-age=300/.test(r.headers()['cache-control'] || ''), 'cache-control: ' + r.headers()['cache-control']);
    const j = await r.json();
    assert(j.format === 1 && Array.isArray(j.engines) && j.engines.length >= 5, 'shape');
    for (const e of j.engines) {
      assert(Object.keys(e).sort().join() === 'bytes,id,line,name', 'fields: ' + Object.keys(e));
      assert(/^[a-z0-9][a-z0-9-]*$/.test(e.id) && e.name && typeof e.line === 'string' && e.bytes > 0, 'entry ' + JSON.stringify(e));
    }
    assert(!j.engines.some(e => e.id === 'zeist'), 'Zeist is not listed');
    assert(j.engines[0].id === 'stockfish-lite', 'display order starts with Stockfish Lite');
  });

  await step(name, 'an unknown engine, the base and Zeist go to /chess', async () => {
    const bad = await page.request.get(A.url + 'engines/%E0', { maxRedirects: 0 });
    assert(bad.status() === 404, 'a malformed pack address: ' + bad.status());
    for (const u of [A.url, A.url.slice(0, -1)]) {
      const r = await page.request.get(u, { maxRedirects: 0 });
      assert(r.status() === 301 && r.headers().location === '/chess', `${u}: ${r.status()} ${r.headers().location}`);
    }
    for (const p of ['no-such-engine/', 'zeist/', 'index.html', 'js/']) {
      const r = await page.request.get(A.url + p, { maxRedirects: 0 });
      assert(r.status() === 302 && r.headers().location === '/chess', `${p}: ${r.status()} ${r.headers().location}`);
    }
    const slash = await page.request.get(A.url + 'maia', { maxRedirects: 0 });
    assert([301, 307, 308].includes(slash.status()) && slash.headers().location.endsWith('/maia/'), 'maia gets its slash: ' + slash.status());
  });

  await step(name, "Stockfish Lite's start screen: levels 1 to 10, side, three clocks", async () => {
    // (Each choice row is one stop for Tab: checked below once the page is up.)
    const res = await page.goto(A.url + 'stockfish-lite/');
    assert(res.ok(), 'status ' + res.status());
    const csp = res.headers()['content-security-policy'] || '';
    assert(csp.includes("default-src 'self'") && csp.includes("'wasm-unsafe-eval'"), 'CSP: ' + csp);
    await page.waitForFunction(() => document.querySelectorAll('#still .zcp').length === 32);
    assert((await page.textContent('#opponent b')).trim() === 'Stockfish Lite', 'name');
    // Search and share cards
    const seo = JSON.parse(fs.readFileSync(path.join(web, 'seo.json'), 'utf8'));
    const listed = (await (await page.request.get(A.url + 'engines.json')).json()).engines.find(e => e.id === 'stockfish-lite');
    const want = { ...seo.default, ...(seo.engines['stockfish-lite'] || {}) };
    const fill = t => t.replace(/\{name\}/g, want.name || listed.name).replace(/\{line\}/g, listed.line).trim();
    assert(await page.title() === 'Play Chess vs Stockfish Lite Online | Zeist', 'the agreed title: ' + await page.title());
    assert(await page.title() === fill(want.title), 'title: ' + await page.title());
    assert((await page.textContent('h1')).trim() === fill(want.h1), 'h1');
    const meta = sel => page.getAttribute(sel, 'content');
    assert(await page.getAttribute('link[rel=canonical]', 'href') === 'https://zeist.gg/chess/vs/stockfish-lite/', 'canonical');
    assert(/^index,follow/.test(await meta('meta[name=robots]')), 'robots');
    const desc = await meta('meta[name=description]');
    assert(desc === fill(want.description) && desc.length > 20, 'description: ' + desc);
    assert(await meta('meta[property="og:title"]') === fill(want.title).replace(/ \| Zeist$/, '') && await meta('meta[property="og:url"]') === 'https://zeist.gg/chess/vs/stockfish-lite/', 'og');
    assert(/^https:\/\/zeist\.gg\/g\/chess-og\.jpg/.test(await meta('meta[property="og:image"]')), 'og image');
    assert((await page.textContent('#opp-tag, #opponent em')).trim() === 'Not rated', 'not rated');
    const levels = await page.$$eval('#lvls button', b => b.map(x => x.textContent.trim()));
    assert(levels.join() === '1,2,3,4,5,6,7,8,9,10', 'levels: ' + levels);
    assert(!(await page.locator('#rating').count()), 'no rating for Stockfish Lite');
    const clocks = await page.$$eval('#clocks button', b => b.map(x => x.textContent.trim()));
    assert(clocks.join() === 'None,10+5,15+10', 'clocks: ' + clocks);
    const sides = await page.$$eval('#sides button', b => b.map(x => x.textContent.trim()));
    assert(sides.join() === 'White,Black,Either', 'sides: ' + sides);
    await page.click('#lvls [data-level="6"]');
    assert(await page.getAttribute('#lvls [data-level="6"]', 'aria-checked') === 'true', 'level 6 picked');
    const stops = await page.$$eval('#lvls button, #sides button, #clocks button', b => b.filter(x => x.tabIndex === 0).length);
    assert(stops === 3, 'one tab stop a row: ' + stops);
    await page.focus('#lvls [data-level="6"]');
    await page.keyboard.press('ArrowRight');
    assert(await page.getAttribute('#lvls [data-level="7"]', 'aria-checked') === 'true', 'arrow keys move the level');
    await page.click('#lvls [data-level="6"]');
    await page.click('#clocks [data-clock="15+10"]');
    await page.click('#sides [data-side="b"]');
    await page.reload();
    await page.waitForSelector('#go');
    assert(await page.getAttribute('#lvls [data-level="6"]', 'aria-checked') === 'true', 'level kept');
    assert(await page.getAttribute('#clocks [data-clock="15+10"]', 'aria-checked') === 'true', 'clock kept');
    assert(/downloads it \(1\.9 MB\)/.test(await page.textContent('#home-note')), 'note: ' + await page.textContent('#home-note'));
    await page.click('#sides [data-side="either"]');
    await page.click('#clocks [data-clock="none"]');
    await page.waitForTimeout(500);
    await S('01-start-stockfish-lite');
  });

  await step(name, "Maia's start screen: a rating instead of levels", async () => {
    await page.goto(A.url + 'maia/');
    await page.waitForSelector('#rating');
    assert(!(await page.locator('#lvls').count()), 'no levels for Maia');
    assert((await page.textContent('#opponent b')).trim() === 'Maia 3', 'name');
    assert(await page.title() === 'Play Chess vs Maia Online | Zeist', 'title: ' + await page.title());
    assert((await page.textContent('h1')).trim() === 'Chess vs Maia', 'heading: ' + await page.textContent('h1'));
    const [min, max] = await page.$eval('#rating', r => [+r.min, +r.max]);
    assert(min < 1500 && max > 1500, `range ${min} to ${max}`);
    await page.$eval('#rating', r => { r.value = '1700'; r.dispatchEvent(new Event('input', { bubbles: true })); });
    assert((await page.textContent('#rating-value')).trim() === '1700', 'value shown');
    assert(/Plays like people at this rating/.test(await page.textContent('#home-note')), 'note');
    await page.$eval('#rating', r => { r.value = '1500'; r.dispatchEvent(new Event('input', { bubbles: true })); });
    await S('02-start-maia');
  });

  await step(name, 'a game at level 1 with no clock, the pack straight from the packs\' server', async () => {
    const before = { worker: workerLog.A.length, cors: packRequests.cors };
    await page.goto(A.url + 'stockfish-lite/');
    await page.waitForFunction(() => !!navigator.serviceWorker && !!navigator.serviceWorker.controller, null, { timeout: 15000 }).catch(() => {});
    await setUp(page, { level: 1, side: 'w', clock: 'none' });
    await page.click('#go');
    await page.waitForSelector('#play:not([hidden]) #board .zcp', { timeout: 90000 });
    await playMoves(page, 3, { drag: true });
    const g = await currentGame(page);
    assert(g && g.engineID === 'stockfish-lite' && g.level === 1 && !g.timeControl && g.moves.length >= 6, 'record: ' + JSON.stringify(g && { e: g.engineID, l: g.level, tc: g.timeControl, m: g.moves.length }));
    assert(g.packSHA && g.packSHA.length === 64, 'pack sha kept');
    const sub = await page.textContent('#title-sub');
    assert(sub === 'Stockfish Lite · Level 1 · Not rated', 'title: ' + sub);
    assert(packRequests.cors > before.cors, 'files came from the packs\' server');
    const ran = workerLog.A.slice(before.worker).filter(l => l.includes(BASE)); // Zeist's own /api/me and /chess aren't this Worker's
    assert(!ran.length, 'the Worker ran for: ' + ran.join(', '));
    await S('03-game-level-1');
  });

  await step(name, 'Back goes to /chess, and Continue picks the game up', async () => {
    await page.click('#back');
    await page.waitForURL(u => new URL(u).pathname === '/chess');
    await page.goto(A.url + 'stockfish-lite/');
    await page.waitForSelector('#resume:not([hidden])');
    await page.click('#resume');
    await page.waitForSelector('#play:not([hidden]) #board .zcp');
    const g = await currentGame(page);
    assert(g && g.moves.length >= 6, 'same game');
  });

  await step(name, 'reloads with no network and the engine still answers', async () => {
    await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 15000 });
    await ctx.setOffline(true);
    offline = true;
    try {
      await page.reload();
      await page.waitForSelector('#resume:not([hidden])');
      await page.click('#resume');
      await page.waitForSelector('#play:not([hidden]) #board .zcp');
      const before = (await currentGame(page)).moves.length;
      await playMoves(page, 1);
      assert((await currentGame(page)).moves.length >= before + 2, 'engine answered offline');
    } finally {
      await ctx.setOffline(false);
      await page.waitForTimeout(500);
      offline = false;
    }
  });

  await step(name, 'a 10+5 game runs its clocks; resigning from the menu ends it', async () => {
    await page.goto(A.url + 'stockfish-lite/');
    await setUp(page, { level: 1, side: 'w', clock: '10+5' });
    await page.click('#go');
    await page.waitForSelector('#play:not([hidden]) #board .zcp');
    await playMoves(page, 2);
    const g = await currentGame(page);
    assert(g.timeControl && g.timeControl.base === 600 && g.timeControl.increment === 5, 'time control: ' + JSON.stringify(g.timeControl));
    assert(g.clocks && g.clocks.length === g.moves.length, 'a clock reading for every move');
    const clocks = await page.$$eval('.prow .clk', c => c.map(x => x.textContent.trim()));
    assert(clocks.length === 2 && clocks.every(t => /^\d+:\d\d$/.test(t)), 'clocks: ' + clocks);
    assert(/10\+5/.test(await page.textContent('#side-sub')), 'side line names the clock');
    const all = await games(page);
    assert(all.some(x => x.engineID === 'stockfish-lite' && x.ending === 'abandoned'), 'the earlier game is kept as abandoned');
    await S('04-game-10-5');
    await page.click('#menu-btn');
    assert(await page.locator('#undo').isHidden(), 'no take-back with a clock');
    await page.click('#resign');
    assert(/again/.test(await page.textContent('#resign')), 'asks again');
    await S('05-game-menu');
    await page.click('#resign');
    await page.waitForSelector('#end:not([hidden])');
    assert((await page.textContent('#end-title')).trim() === 'You lost.', 'end title');
    assert(/resigned/.test(await page.textContent('#end-line')), 'end line');
    assert(await page.getAttribute('#end-home', 'href') === '/chess', 'Chess goes to /chess');
    await S('06-game-end');
  });

  await step(name, 'a broken engine ends in a calm message, the board stays usable', async () => {
    await page.goto(A.url + SMALL + '/');
    await setUp(page, { level: 1, side: 'b', clock: 'none' });
    await page.click('#go');
    await page.waitForSelector('#play:not([hidden]) #board .zcp', { timeout: 90000 });
    await waitFor(async () => { const c = await currentGame(page); return c && c.engineID === SMALL && c.moves.length >= 1; }, 90000, 'its first move');
    await page.evaluate(async id => {
      const c = await caches.open('zc-packs');
      for (const r of await c.keys()) if (r.url.includes(`/engines/${id}/`) && /\.js$/.test(r.url)) await c.put(r, new Response('throw new Error("broken")', { headers: { 'content-type': 'text/javascript' } }));
    }, SMALL);
    await page.reload();
    await page.waitForSelector('#go');
    await page.click('#sides [data-side="b"]');
    await page.click('#go');
    await page.waitForSelector('#play:not([hidden])');
    // Changed bytes: the service worker removes the pack and the game says so, or the worker fails and it says so.
    const said = await waitFor(async () => {
      const t = (await page.textContent('#say')) || '';
      return /stopped before it could move|reload|Reload/.test(t) ? t : null;
    }, 90000, 'a calm message');
    assert(said, 'message');
    await page.click('#menu-btn');
    await page.click('#resign'); await page.click('#resign');
    await page.waitForSelector('#end:not([hidden])');
  });

  // Packs through the Worker when the packs' server sends no CORS headers.
  await step(name, 'without CORS on the packs\' server, packs come through the Worker', async () => {
    const p2 = await ctx.newPage();
    currentPage = p2;
    const before = workerLog.B.length;
    await p2.goto(B.url + SMALL + '/');
    await p2.waitForFunction(() => !!navigator.serviceWorker && !!navigator.serviceWorker.controller, null, { timeout: 15000 }).catch(() => {});
    await setUp(p2, { level: 1, side: 'w', clock: 'none' });
    await p2.click('#go');
    await p2.waitForSelector('#play:not([hidden]) #board .zcp', { timeout: 90000 });
    await playMoves(p2, 1);
    const ran = workerLog.B.slice(before);
    assert(ran.some(l => l.includes(`/engines/${SMALL}/`)), 'the Worker served the pack: ' + ran.join(', '));
    await p2.close();
    currentPage = page;
  });

  await step(name, 'no uncaught errors on the page', async () => { assert(!errors.length, errors.join('\n')); });
  await ctx.close();

  // Arriving from Zeist's /chess, whose service worker answers for /chess/vs/ too until this app's own takes over: the
  // first game must wait for this app's worker (which checks the pins and the files), never run under Zeist's.
  await step(name, "from Zeist's /chess, under Zeist's service worker, the first game waits for this app's", async () => {
    const z = await browser.newContext({ ...PHONE, serviceWorkers: 'allow' });
    z.on('request', r => requests.push(r.url()));
    const p = await z.newPage();
    currentPage = p;
    await p.goto(A.origin + '/chess');
    await p.waitForFunction(() => navigator.serviceWorker.controller && navigator.serviceWorker.controller.scriptURL.endsWith('/chess/sw.js'), null, { timeout: 15000 });
    await p.goto(A.url + SMALL + '/');
    const first = await p.evaluate(() => navigator.serviceWorker.controller && navigator.serviceWorker.controller.scriptURL);
    assert(first && first.endsWith('/chess/sw.js'), "the page starts under Zeist's worker: " + first);
    const notes = [];
    await p.exposeFunction('zcNote', t => notes.push(t));
    await p.evaluate(() => new MutationObserver(() => window.zcNote(document.getElementById('home-note').textContent)).observe(document.getElementById('home-note'), { childList: true, characterData: true, subtree: true }));
    await setUp(p, { level: 1, side: 'w', clock: 'none' });
    await p.click('#go');
    await p.waitForSelector('#play:not([hidden]) #board .zcp', { timeout: 90000 });
    await playMoves(p, 1);
    const now = await p.evaluate(() => navigator.serviceWorker.controller && navigator.serviceWorker.controller.scriptURL);
    assert(now && now.endsWith('/chess/vs/sw.js'), "this app's worker answers now: " + now);
    assert(!notes.some(t => /reload/i.test(t)), 'no reload message: ' + notes.join(' | '));
    const kept = await p.evaluate(async id => (await (await caches.open('zc-packs')).keys()).filter(r => r.url.includes(`/engines/${id}/`)).length, SMALL);
    assert(kept >= 3, 'pack kept: ' + kept);
    await z.close();
  });

  // Desktop, signed in: the start screen and a game, with the board on the left and a column beside it.
  await step(name, 'desktop, signed in: start and game screens', async () => {
    const d = await browser.newContext({ ...DESKTOP, serviceWorkers: 'allow' });
    await zeist(d, { user: { handle: 'ada', owner: 'test-owner' } });
    d.on('request', r => requests.push(r.url()));
    const p = await d.newPage();
    currentPage = p;
    await p.goto(A.url + 'stockfish-lite/');
    await p.waitForFunction(() => document.querySelectorAll('#still .zcp').length === 32);
    await p.click('#lvls [data-level="6"]');
    await shot(p, `${name}-desktop-01-start-stockfish-lite`);
    await p.goto(A.url + 'maia/');
    await p.waitForSelector('#rating');
    await shot(p, `${name}-desktop-02-start-maia`);
    await p.goto(A.url + 'stockfish-lite/');
    await setUp(p, { level: 6, side: 'w', clock: '10+5' });
    await p.click('#go');
    await p.waitForSelector('#play:not([hidden]) #board .zcp', { timeout: 90000 });
    await playMoves(p, 2);
    // Playwright can't stand in for /api/me under WebKit once a service worker answers for the page.
    if (name === 'chromium') {
      const names = await p.$$eval('.prow .who b', b => b.map(x => x.textContent.trim()));
      assert(names.includes('ada'), 'signed-in name: ' + names);
    }
    await shot(p, `${name}-desktop-03-game`);
    await d.close();
  });

  await step(name, 'no request to /api/rated', async () => {
    // Seen by the browser, and by the servers (which also see what Playwright can't watch under a service worker).
    const rated = [...requests, ...workerLog.A, ...workerLog.B].filter(u => /\/api\/rated/.test(u));
    assert(!rated.length, rated.join(', '));
    assert(name !== 'chromium' || requests.some(u => /\/api\/me$/.test(u)), 'the page did read /api/me');
  });
  await browser.close();
}

try {
  for (const b of browsers) await run(b);
} finally {
  A.proc.kill(); B.proc.kill();
  corsPacks.server.close(); plainPacks.server.close();
}
console.log('\n' + results.join('\n'));
const own = workerLog.A.filter(l => l.includes(BASE));
console.log(`\nWorker runs on site A (packs from the CORS server), under ${BASE}: ${own.length}${own.length ? ': ' + [...new Set(own)].join(', ') : ''}`);
console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
