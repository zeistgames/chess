#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Checks of the web app's own logic that need no browser, in node: the clock and the material rule for a falling
// flag (audit F18, F19). Run by npm test before the browser run (test/run.mjs), after scripts/assets.mjs.
//
//   node test/units.mjs
globalThis.localStorage ??= { getItem: () => null, setItem() {}, removeItem() {} };
globalThis.document ??= { querySelector: () => null, documentElement: { dataset: {} }, baseURI: 'http://x/chess/' };
globalThis.location ??= { pathname: '/chess/', hash: '', origin: 'http://x' };
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const web = pathToFileURL(path.join(path.dirname(path.dirname(fileURLToPath(import.meta.url))), 'public')).href;
const { Game } = await import(web + '/core/rules.js');
const material = await import(web + '/js/material.js');
let fails = 0;
const check = (ok, name) => { console.log((ok ? 'ok   ' : 'FAIL ') + name); if (!ok) fails++; };
const board = fen => Game.fromMoves([], fen).board();
check(material.canMate('w', board('k7/p1KB3p/8/8/8/8/8/8 b - - 0 1')) === true, 'F19 lone bishop against pawns can mate');
check(material.canMate('w', board('k7/8/2KB4/8/8/8/8/8 b - - 0 1')) === false, 'F19 king and bishop against bare king is a draw');
check(material.canMate('w', board('k7/8/2K5/8/8/8/8/8 b - - 0 1')) === false, 'F19 bare king is a draw');
check(material.canMate('w', board('kn6/8/2KN4/8/8/8/8/8 b - - 0 1')) === true, 'F19 knight against knight can mate');
// Bishops all on one color can never mate (review of F19).
check(material.canMate('w', board('k7/8/2K5/8/8/8/1B6/B7 b - - 0 1')) === false, 'F19 two bishops on one color against a bare king');
check(material.canMate('w', board('kb6/8/2K5/8/8/8/8/B7 b - - 0 1')) === false, 'F19 king and bishop against king and bishop, same color');
check(material.canMate('w', board('k7/8/2K5/8/8/8/B7/B7 b - - 0 1')) === true, 'F19 two bishops on opposite colors');
check(material.canMate('w', board('k1b5/8/2K5/8/8/8/8/B7 b - - 0 1')) === true, 'F19 bishops of opposite colors, one each');
check(material.canMate('w', board('kn6/8/2K5/8/8/8/1B6/B7 b - - 0 1')) === true, 'F19 a knight to block with');
// What Settings shows beside an engine (review of 2026-11-19, 18): both licenses, and its own folder as the source.
try {
  const shelf = await import(web + '/js/shelf.js');
  check(shelf.licensesOf({ license: 'GPL-3.0-or-later', net_license: 'CC0-1.0' }) === 'GPL-3.0-or-later. Network: CC0-1.0', 'an engine names its network license when it differs');
  check(shelf.licensesOf({ license: 'MIT', net_license: 'MIT' }) === 'MIT' && shelf.licensesOf({ license: 'GPL-3.0-or-later', net_license: 'none' }) === 'GPL-3.0-or-later', 'the same license, or no network, is named once');
  check(shelf.licensesOf({ license: 'A AND B' }) === 'A, B', 'several program licenses read as a list');
  check(shelf.packSource('fairy-stockfish') === 'https://github.com/zeistgames/chess/tree/main/engines/fairy-stockfish', 'Source is the pack folder, with its patch and build steps');
} catch (e) { console.log('FAIL could not load shelf.js: ' + e.message); fails++; }
try {
  const { Clock } = await import(web + '/js/play.js');
  const c = new Clock({ base: 60, increment: 2 }, [10, 60000], 'w');
  c.resume(0);
  check(c.flagged(11) === 'w', 'F18 white flagged');
  c.moved('w', 11);
  check(c.flagged(11) === 'w' && c.remaining('w', 11) === 0, 'F18 a move after the flag leaves it fallen');
  // A fallen flag stays fallen even when the move arrives while the clock is paused (review of F18).
  const p = new Clock({ base: 60, increment: 2 }, [0, 60000], 'w');
  p.moved('w', 5);
  check(p.remaining('w', 5) === 0 && p.running === 'w', 'F18 a paused clock with no time left gives no increment');
} catch (e) { console.log('FAIL could not load play.js: ' + e.message); fails++; }
process.exit(fails ? 1 : 0);
