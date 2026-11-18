#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A plain Node server that runs the same request handler as the Worker (src/worker.js), with public/ standing in
// for the assets binding. Used by the tests and for quick local play without Cloudflare's dev server.
//
//   node scripts/serve.mjs [--port 8790] [--base /chess/engines/] [--engines <dir> | --engines-origin <url>]
//
// Engines come from engines.zei.st by default. --engines serves a folder of packs from disk instead (such as
// engines/dist after a build), for when the network or the name engines.zei.st can't be reached.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { handle, typeOf } from '../src/worker.js';

const web = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);
const opt = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const port = Number(opt('--port', process.env.PORT || 8790));
const base = opt('--base', process.env.ZC_BASE || '/');
const engineDir = opt('--engines', process.env.ZC_ENGINES_DIR || '');
const engineOrigin = opt('--engines-origin', 'https://engines.zei.st/');

/** Files from a folder, as an R2-like or assets-like source. */
function fromDisk(root) {
  const resolve = key => {
    const p = path.resolve(root, key);
    return p.startsWith(path.resolve(root) + path.sep) || p === path.resolve(root) ? p : null;
  };
  return {
    async get(key) {
      const p = resolve(key);
      if (!p || !fs.existsSync(p) || !fs.statSync(p).isFile()) return null;
      return { size: fs.statSync(p).size, body: Readable.toWeb(fs.createReadStream(p)) };
    },
    resolve,
  };
}

const pub = fromDisk(path.join(web, 'public'));
const env = {
  BASE: base,
  ASSETS: {
    async fetch(req) {
      let key = decodeURIComponent(new URL(req.url).pathname).replace(/^\//, '');
      if (key === '' || key.endsWith('/')) key += 'index.html';
      const f = await pub.get(key);
      if (!f) return new Response('Not found', { status: 404, headers: { 'content-type': 'text/plain' } });
      return new Response(req.method === 'HEAD' ? null : f.body, { headers: { 'content-type': typeOf(key), 'content-length': String(f.size) } });
    },
  },
  ...(engineDir ? { ENGINES: fromDisk(path.resolve(engineDir)) } : { ENGINES_ORIGIN: engineOrigin }),
};

const server = http.createServer(async (req, res) => {
  try {
    const url = `http://${req.headers.host || 'localhost'}${req.url}`;
    const r = await handle(new Request(url, { method: req.method, headers: req.headers }), env);
    const headers = Object.fromEntries(r.headers);
    res.writeHead(r.status, headers);
    if (!r.body) { res.end(); return; }
    Readable.fromWeb(r.body).on('error', () => res.destroy()).pipe(res);
  } catch (e) {
    res.writeHead(500, { 'content-type': 'text/plain' });
    res.end(String(e && e.stack || e));
  }
});
server.listen(port, () => {
  console.log(`Zeist Chess at http://localhost:${port}${base.startsWith('/') ? base : '/' + base}` +
    (engineDir ? ` (engines from ${engineDir})` : ` (engines from ${engineOrigin})`));
});
