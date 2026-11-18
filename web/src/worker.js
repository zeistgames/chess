// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Worker that serves Zeist Chess on the web. Everything lives under one base path (env.BASE, "/" by default),
// so the app can sit at a path on a domain it does not own: anything outside the base is not ours and gets 404.
//
//   <base>             the app (static assets from public/)
//   <base><id>         the app, opened with that engine picked on Home (ids as in catalog.json, such as "maia").
//                      <base><id>/ redirects to <base><id>, so the page's relative addresses stay in the base.
//   <base>engines/...  engine packs: catalog.json and <id>/<file>, read from the R2 bucket (env.ENGINES), or, when
//                      the bucket lacks the file and env.ENGINES_ORIGIN is set (local development), fetched from it.
//
// An engine address is one segment with no dot. The app's own folders and "engines" are reserved (RESERVED), so no
// engine id can stand for a file or a pack: files have a dot, packs sit under engines/, folders are reserved.
//
// Engine workers must be same-origin scripts and packs load their files relative to their own URL, which is why
// packs come through this origin rather than straight from engines.zei.st.

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

/** "/", "/chess/engines/" from "", "chess/engines", "/chess/engines/" and the like. */
export function normalizeBase(b) {
  const s = String(b || '/').trim().replace(/^\/*|\/*$/g, '');
  return s ? `/${s}/` : '/';
}

// The page's own policy. Engines run in workers from this origin; WebAssembly needs wasm-unsafe-eval.
// /api/me is read on the same origin (Zeist's session), nothing else is contacted.
const CSP = [
  "default-src 'self'", "script-src 'self' 'wasm-unsafe-eval'", "worker-src 'self'", "connect-src 'self'",
  "img-src 'self' data: blob:", "style-src 'self' 'unsafe-inline'", "font-src 'self'", "base-uri 'none'",
  "object-src 'none'", "frame-ancestors 'none'", "form-action 'self'",
].join('; ');

// Names directly under the base that are the app's, never an engine's. Every folder in public/ is here.
export const RESERVED = new Set(['engines', 'js', 'core', 'fonts', 'pieces', 'index', 'api', 'welcome']);
const ENGINE_ID = /^[a-z0-9][a-z0-9-]*$/;

/** True when <base><name> is an engine address. */
export function isEngineAddress(name) { return ENGINE_ID.test(name) && !RESERVED.has(name); }

const PACK_PATH = /^[a-z0-9][a-z0-9._-]*(\/[A-Za-z0-9][A-Za-z0-9._-]*)*$/;

export async function handle(request, env) {
  const url = new URL(request.url);
  const base = normalizeBase(env.BASE);
  if (request.method !== 'GET' && request.method !== 'HEAD') return text('Method not allowed', 405, { allow: 'GET, HEAD' });
  if (base !== '/' && url.pathname === base.slice(0, -1)) {
    return new Response(null, { status: 308, headers: { location: base + url.search } });
  }
  if (!url.pathname.startsWith(base)) return text('Not found', 404);
  const rest = url.pathname.slice(base.length); // no leading slash
  if (rest.startsWith('engines/')) return engines(decodeURIComponent(rest.slice('engines/'.length)), request, env);
  if (isEngineAddress(rest)) return assets('', request, env);
  if (rest.endsWith('/') && isEngineAddress(rest.slice(0, -1))) {
    return new Response(null, { status: 308, headers: { location: base + rest.slice(0, -1) + url.search } });
  }
  return assets(rest, request, env);
}

async function assets(rest, request, env) {
  const target = new URL('/' + rest, request.url);
  const res = await env.ASSETS.fetch(new Request(target, { method: request.method, headers: request.headers }));
  const headers = new Headers(res.headers);
  headers.set('x-content-type-options', 'nosniff');
  headers.set('referrer-policy', 'same-origin');
  if (rest === '' || rest.endsWith('.html')) {
    headers.set('content-security-policy', CSP);
    headers.set('cache-control', 'no-cache');
  } else if (rest === 'sw.js' || rest === 'shell.js') {
    headers.set('cache-control', 'no-cache');
  } else if (/^(fonts|pieces)\//.test(rest)) {
    headers.set('cache-control', 'public, max-age=2592000');
  } else {
    headers.set('cache-control', 'public, max-age=0, must-revalidate');
  }
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
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
