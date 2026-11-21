// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Worker behind Zeist Chess's engine pages, zeist.gg/chess/vs/<id>/. Everything it serves is under one base path
// (env.BASE, "/chess/vs/"). The pages, engines.json and every file of the app are static assets (web/site/, written
// by scripts/assets.mjs, headers from site/_headers): Cloudflare serves them without running this Worker. It runs only
// for what no asset answers:
//
//   <base>engines/...  engine packs: catalog.json and <id>/<file>, read from the R2 bucket (env.ENGINES), or, when the
//                      bucket lacks the file and env.ENGINES_ORIGIN is set (local development), fetched from it. Used
//                      only while the packs' own server (engines.zei.st) doesn't answer this site with CORS headers;
//                      after that the browser downloads packs from it directly (js/shelf.js, js/config.js).
//   the base           a permanent redirect (301) to Zeist's Chess (env.HOME, "/chess"), with or without its slash.
//   anything else      a temporary redirect (302) there: an unknown engine, an old link.
//
// The engines themselves never run here: they run in the player's browser.

const TYPES = {
  html: 'text/html; charset=utf-8', js: 'text/javascript; charset=utf-8', mjs: 'text/javascript; charset=utf-8',
  css: 'text/css; charset=utf-8', json: 'application/json; charset=utf-8', wasm: 'application/wasm',
  svg: 'image/svg+xml', png: 'image/png', woff2: 'font/woff2', txt: 'text/plain; charset=utf-8',
  webmanifest: 'application/manifest+json', onnx: 'application/octet-stream',
};

export function typeOf(name) {
  const ext = name.toLowerCase().split('.').pop();
  return TYPES[ext] || 'application/octet-stream';
}

/** "/", "/chess/vs/" from "", "chess/vs", "/chess/vs/" and the like. */
export function normalizeBase(b) {
  const s = String(b || '/').trim().replace(/^\/*|\/*$/g, '');
  return s ? `/${s}/` : '/';
}

const PACK_PATH = /^[a-z0-9][a-z0-9._-]*(\/[A-Za-z0-9][A-Za-z0-9._-]*)*$/;

export async function handle(request, env) {
  const url = new URL(request.url);
  const base = normalizeBase(env.BASE);
  if (request.method !== 'GET' && request.method !== 'HEAD') return text('Method not allowed', 405, { allow: 'GET, HEAD' });
  if (url.pathname.startsWith(base + 'engines/')) {
    let key;
    try { key = decodeURIComponent(url.pathname.slice(base.length + 'engines/'.length)); } catch { return text('Not found', 404); }
    return engines(key, request, env);
  }
  const home = env.HOME || '/chess';
  // The base itself, with or without its slash, is Chess for good (Amrith, 2026-11-21): a permanent redirect.
  if (url.pathname === base || url.pathname === base.slice(0, -1)) return new Response(null, { status: 301, headers: { location: home } });
  // Anything else unknown (an engine that isn't listed, an old link) may become a page later: a temporary one.
  return new Response(null, { status: 302, headers: { location: home, 'cache-control': 'no-store' } });
}

async function engines(key, request, env) {
  if (!PACK_PATH.test(key) || key.includes('..')) return text('Not found', 404);
  const headers = new Headers({
    'content-type': typeOf(key),
    'x-content-type-options': 'nosniff',
    // The catalog and manifests change when a pack is published; the files they list are checked by sha256.
    'cache-control': /(^catalog|manifest)\.json$|\/manifest\.json$/.test(key) ? 'public, max-age=300' : 'public, max-age=86400',
  });
  if (env.ENGINES) {
    const obj = await env.ENGINES.get(key);
    if (obj) {
      headers.set('content-length', String(obj.size));
      if (obj.httpEtag) headers.set('etag', obj.httpEtag);
      return new Response(request.method === 'HEAD' ? null : obj.body, { headers });
    }
  }
  if (env.ENGINES_ORIGIN) {
    const up = await fetch(new URL(key, normalizeOrigin(env.ENGINES_ORIGIN)), { method: request.method });
    if (!up.ok) return text('Not found', up.status === 404 ? 404 : 502);
    const len = up.headers.get('content-length');
    if (len) headers.set('content-length', len);
    return new Response(up.body, { headers });
  }
  return text('Not found', 404);
}

function normalizeOrigin(o) { return String(o).replace(/\/*$/, '/'); }

function text(body, status, extra = {}) {
  return new Response(body, { status, headers: { 'content-type': 'text/plain; charset=utf-8', ...extra } });
}

export default { fetch: (request, env) => handle(request, env) };
