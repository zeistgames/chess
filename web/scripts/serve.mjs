#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A plain Node server that answers as Cloudflare does for this Worker: a file of site/ (built by scripts/assets.mjs)
// when there is one, with the headers site/_headers gives it and a redirect to add the slash to a page's folder;
// otherwise the Worker's own handler (src/worker.js). Used by the tests and for quick local play.
//
//   node scripts/serve.mjs [--port 8790] [--base /chess/vs/] [--engines <dir> | --engines-origin <url>]
//                          [--packs-origin <url>]
//
// --base must be the base the site was built with (ZC_BASE). Engines come from engines.zei.st through the Worker's
// handler by default; --engines serves a folder of packs from disk instead (such as engines/dist after a build).
// --packs-origin stands in for a site built with ZC_PACKS: js/config.js names that origin and the pages' policy lets
// them connect to it.

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
const base = opt('--base', process.env.ZC_BASE || '/chess/vs/');
const engineDir = opt('--engines', process.env.ZC_ENGINES_DIR || '');
const engineOrigin = opt('--engines-origin', 'https://engines.zei.st/');
const packsOrigin = opt('--packs-origin', '');
const root = path.join(web, 'site');

/** Files from a folder, as an R2-like source. */
function fromDisk(dir) {
  const resolve = key => {
    const p = path.resolve(dir, key);
    return p.startsWith(path.resolve(dir) + path.sep) ? p : null;
  };
  return {
    async get(key) {
      const p = resolve(key);
      if (!p || !fs.existsSync(p) || !fs.statSync(p).isFile()) return null;
      return { size: fs.statSync(p).size, body: Readable.toWeb(fs.createReadStream(p)) };
    },
  };
}

// site/_headers: "path pattern" lines, each followed by indented "Name: value" lines. :name matches one segment, *
// anything.
const rules = [];
for (const line of fs.readFileSync(path.join(root, '_headers'), 'utf8').split('\n')) {
  if (!line.trim() || line.startsWith('#')) continue;
  if (!/^\s/.test(line)) {
    const re = new RegExp('^' + line.trim().replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/:\w+/g, '[^/]+') + '$');
    rules.push({ re, headers: [] });
  } else {
    const i = line.indexOf(':');
    rules.at(-1).headers.push([line.slice(0, i).trim().toLowerCase(), line.slice(i + 1).trim()]);
  }
}

const env = {
  BASE: base,
  HOME: '/chess',
  ...(engineDir ? { ENGINES: fromDisk(path.resolve(engineDir)) } : { ENGINES_ORIGIN: engineOrigin }),
};

function asset(pathname) {
  const p = path.resolve(root, '.' + decodeURIComponent(pathname));
  if (!p.startsWith(root + path.sep) || path.basename(p) === '_headers') return null;
  if (pathname.endsWith('/')) { const f = path.join(p, 'index.html'); return fs.existsSync(f) ? { file: f } : null; }
  if (fs.existsSync(p) && fs.statSync(p).isFile()) return { file: p };
  if (fs.existsSync(path.join(p, 'index.html'))) return { redirect: pathname + '/' };
  return null;
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(`http://${req.headers.host || 'localhost'}${req.url}`);
    const a = (req.method === 'GET' || req.method === 'HEAD') ? asset(url.pathname) : null;
    if (a && a.redirect) { res.writeHead(307, { location: a.redirect + url.search }); res.end(); return; }
    if (a) {
      const headers = { 'content-type': typeOf(a.file), 'cache-control': 'public, max-age=0, must-revalidate' };
      for (const r of rules) if (r.re.test(url.pathname)) for (const [k, v] of r.headers) headers[k] = v;
      let body = fs.readFileSync(a.file);
      if (packsOrigin) {
        const origin = new URL(packsOrigin).origin;
        if (headers['content-security-policy']) headers['content-security-policy'] = headers['content-security-policy'].replace("connect-src 'self'", `connect-src 'self' ${origin}`);
        if (url.pathname === base + 'js/config.js') body = Buffer.from(String(body).replace(/export const PACKS = [^;]*;/, `export const PACKS = ${JSON.stringify(origin + '/')};`));
      }
      headers['content-length'] = String(body.length);
      res.writeHead(200, headers);
      res.end(req.method === 'HEAD' ? undefined : body);
      return;
    }
    // ZC_LOG=1: one line for every request the Worker itself would run for (the tests count them).
    if (process.env.ZC_LOG) console.log(`worker ${req.method} ${url.pathname}`);
    const r = await handle(new Request(url, { method: req.method, headers: req.headers }), env);
    res.writeHead(r.status, Object.fromEntries(r.headers));
    if (!r.body) { res.end(); return; }
    Readable.fromWeb(r.body).on('error', () => res.destroy()).pipe(res);
  } catch (e) {
    res.writeHead(500, { 'content-type': 'text/plain' });
    res.end(String(e && e.stack || e));
  }
});
server.listen(port, () => {
  console.log(`Zeist Chess at http://localhost:${port}${base}<engine>/` +
    (engineDir ? ` (engines from ${engineDir})` : ` (engines from ${engineOrigin})`) + (packsOrigin ? `, packs downloaded from ${packsOrigin}` : ''));
});
