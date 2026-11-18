#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Draws Zeist Chess's Game Center achievement images (512 by 512 PNG) from ios/GameCenter/achievements.json.
//
//   PLAYWRIGHT_DIR=<folder with playwright and its chromium> node ios/scripts/achievements.mjs
//
// The look is Zeist's "the mark, played": the mark faintly behind, one thing on it, graphite and bone.
// - A first win shows the engine's drawing (core/faces) in bone.
// - "At its best" shows the same drawing in ebony on an ivory disc.
// - Maia's ratings show the person with the number under it; puzzle counts show the number alone.
// - Feats show one of Zeist's own pieces (the lit images the app uses).
// Game Center crops an image to a circle, so everything sits inside one.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const ios = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const repo = path.dirname(ios);
const list = JSON.parse(fs.readFileSync(path.join(ios, 'GameCenter', 'achievements.json'), 'utf8')).achievements;
const out = path.join(ios, 'GameCenter', 'images');
fs.mkdirSync(out, { recursive: true });

// The Zeist Chess mark (three lines each way with a pawn on a point), as in the app icon, fitted to a 24 by 24 box.
const PAWN = 'M36.94 20.53a7.06 7.06 0 1 0 14.11 0a7.06 7.06 0 1 0 -14.11 0ZM34.82 27.25h18.37v4.03h-18.37ZM38.51 30.16C38.51 38.22 33.25 42.03 31.01 46.29L56.99 46.29C54.75 42.03 49.49 38.22 49.49 30.16ZM28.77 45.17h30.46v5.38h-30.46Z';
const mark = (ink, ground) => `<svg x="0" y="0" width="24" height="24" viewBox="-5 -5 86 86"><path d="M76 0H0M76 32H0M76 64H0M76 0v76M44 0v76M12 0v76" stroke="${ink}" stroke-width="4.5" stroke-linecap="round" fill="none"/><path d="${PAWN}" fill="${ground}" stroke="${ground}" stroke-width="11.2" stroke-linejoin="round"/><path d="${PAWN}" fill="${ink}" stroke="none"/></svg>`;
const face = (id, best) => id === 'zeist' ? (best ? mark('#1c1b18', '#eee7d6') : mark('#f4f1ea', '#1c1a16'))
  : fs.readFileSync(path.join(repo, 'core', 'faces', id + '.svg'), 'utf8').match(/<svg[^>]*>([\s\S]*)<\/svg>/)[1];
const piece = p => 'data:image/png;base64,' + fs.readFileSync(path.join(ios, 'ZeistChess', 'Assets.xcassets', 'Pieces', 'zeist', p + '.imageset', p + '.png')).toString('base64');
const font = 'data:font/woff2;base64,' + fs.readFileSync(path.join(repo, 'web', 'public', 'fonts', 'Prata-Regular.woff2')).toString('base64');

function svg(a) {
  const i = a.image, label = i.label;
  const grid = '<g stroke="rgb(244 241 234 / .12)" stroke-width="1.1" fill="none" stroke-linecap="round"><path d="M-5 26h110M-5 50h110M-5 74h110M26 -5v110M50 -5v110M74 -5v110"/></g>';
  let body = '';
  if (i.piece) {
    if (i.piece[0] === 'b') body += '<circle cx="50" cy="50" r="30" fill="#b4ad9f"/>';
    body += `<image href="${piece(i.piece)}" x="25" y="24" width="50" height="50"/>`;
  } else if (i.face) {
    const cy = label ? 42 : 50, inner = face(i.face, i.best);
    if (i.best) {
      body += `<circle cx="50" cy="${cy}" r="25" fill="#eee7d6"/><g transform="translate(${50 - 12 * 1.6} ${cy - 12 * 1.6}) scale(1.6)" stroke="#1c1b18" fill="none" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${inner.replaceAll('fill="#000"', 'fill="#1c1b18"')}</g>`;
    } else {
      const k = label ? 1.75 : 2.05;
      body += `<g transform="translate(${50 - 12 * k} ${cy - 12 * k}) scale(${k})" stroke="#f4f1ea" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${inner.replaceAll('fill="#000"', 'fill="#f4f1ea"')}</g>`;
    }
  }
  if (label) body += `<text x="50" y="${i.face ? 79 : 60}" text-anchor="middle" font-family="Prata" font-size="${i.face ? 14 : label.length > 3 ? 27 : 31}" fill="#f4f1ea">${label}</text>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="512" height="512"><rect width="100" height="100" fill="#1c1a16"/>${grid}${body}</svg>`;
}

const require = createRequire((process.env.PLAYWRIGHT_DIR || '.') + '/');
const { chromium } = require('playwright');
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 512, height: 512 }, deviceScaleFactor: 1 });
for (const a of list) {
  await page.setContent(`<style>@font-face{font-family:Prata;src:url(${font})}html,body{margin:0;background:#1c1a16}svg{display:block}</style>${svg(a)}`);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(out, a.id + '.png'), omitBackground: false });
}
await browser.close();
console.log(`achievements ok: ${list.length} images`);
