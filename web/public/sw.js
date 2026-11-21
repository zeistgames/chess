// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Keeps Zeist Chess working with no network:
//   the app shell (listed in shell.js): from the network when it answers, else from the copy kept here;
//   engines/catalog.json: the same, when packs come through this site's Worker;
//   engine pack files: only from the packs downloaded by js/shelf.js (Cache Storage "zc-packs", written by js/shelf.js),
//   only the files their manifest lists, and never from the network. Cache Storage belongs to the whole site, so
//   nothing in it is trusted: every time a pack file is served, its kept manifest must hash to a value pinned in this
//   service worker's own script (self.PINS, from shell.js, written at build time by scripts/assets.mjs), and the file
//   must match that manifest's size and sha256. A manifest not pinned is not served and not removed (it may be a
//   version a later deploy of the app pins). A file that fails its pinned manifest is damage: the pack is removed and
//   the open page says so. The catalog is never consulted here, so a catalog that moves on or drops an engine never
//   touches an installed pack. The shelf's own downloads go to the network to be checked there, only with a key a
//   window of this app gave this service worker (x-zc-download): never for an engine's worker.
// Everything outside this app's folder, such as Zeist's /api/me, passes through untouched.

importScripts('shell.js');

const SCOPE = self.registration.scope;
const SHELL_CACHE = 'zc-shell-' + self.SHELL.version;
const META = 'zc-meta';
const PACKS = 'zc-packs';

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const c = await caches.open(SHELL_CACHE);
    await c.addAll(self.SHELL.files.map(f => new Request(new URL(f, SCOPE), { cache: 'reload' })));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const k of await caches.keys()) if (k.startsWith('zc-shell-') && k !== SHELL_CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

/** The network, but not for longer than ms; then whatever the cache has. */
async function fresh(request, cacheName, ms, fallback) {
  const c = await caches.open(cacheName);
  const net = fetch(request).then(res => {
    if (res.ok && res.type === 'basic') c.put(fallback || request, res.clone());
    return res;
  });
  const timer = new Promise(resolve => setTimeout(resolve, ms, null));
  try {
    const first = await Promise.race([net, timer]);
    if (first) return first;
    const kept = await c.match(fallback || request, { ignoreSearch: true });
    return kept || await net;
  } catch {
    const kept = await c.match(fallback || request, { ignoreSearch: true });
    if (kept) return kept;
    return new Response('Offline, and not kept here.', { status: 503, headers: { 'content-type': 'text/plain' } });
  }
}

const missing = () => new Response('Not downloaded here.', { status: 404, headers: { 'content-type': 'text/plain' } });

async function sha256(buf) {
  const d = await crypto.subtle.digest('SHA-256', buf);
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}

const PINS = self.PINS || {};

/** Whether a kept manifest (its sha256) is one this app pins for the engine. */
function pinned(id, sha) { return !!(PINS[id] && Object.hasOwn(PINS[id], sha)); }

/** A pack whose own files fail its pinned manifest: removed, and the open page says so (js/shelf.js). */
async function damaged(c, base, id) {
  for (const k of await c.keys()) if (k.url.startsWith(base)) await c.delete(k);
  for (const w of await self.clients.matchAll({ type: 'window' })) w.postMessage({ type: 'zc-pack-removed', id });
  return missing();
}

/** A file of a downloaded pack (<id>/<path>): served only when the kept manifest is pinned and lists it, and the
 *  file's bytes are the ones it gives. Checked every time it is served: a verdict kept from an earlier serve wouldn't
 *  see bytes written since. */
async function packFile(rest) {
  const slash = rest.indexOf('/');
  if (slash < 1) return missing();
  const id = rest.slice(0, slash), file = rest.slice(slash + 1);
  const c = await caches.open(PACKS);
  const base = new URL('engines/' + id + '/', SCOPE).href;
  const mr = await c.match(base + 'manifest.json');
  if (!mr) return missing();
  const raw = await mr.clone().arrayBuffer();
  if (!pinned(id, await sha256(raw))) return missing(); // not a pack this app knows: never served, never removed
  if (file === 'manifest.json') return mr;
  let m;
  try { m = JSON.parse(new TextDecoder().decode(raw)); } catch { return missing(); }
  const f = (m.files || []).find(x => x.path === file);
  if (!f) return missing();
  const kept = await c.match(base + file);
  if (!kept) return damaged(c, base, id);
  const b = await kept.clone().arrayBuffer();
  if (b.byteLength !== f.bytes || (await sha256(b)) !== String(f.sha256).toLowerCase()) return damaged(c, base, id);
  return kept;
}

/** Keys the app's windows gave this service worker for their downloads. Lost when it stops; the shelf gives its
 *  key again before every request (js/shelf.js arm). */
const keys = new Set();

self.addEventListener('message', event => {
  const d = event.data;
  // Whether a manifest is pinned, so the shelf can say a version needs the app reloaded before downloading it.
  if (d && d.type === 'zc-pinned' && event.ports && event.ports[0]) { event.ports[0].postMessage(pinned(String(d.id), String(d.sha))); return; }
  if (!d || d.type !== 'zc-download-key' || typeof d.key !== 'string' || d.key.length < 32) return;
  // Only a window of this app: never an engine's worker.
  const src = event.source;
  if (!src || src.type !== 'window' || !String(src.url).startsWith(SCOPE)) return;
  keys.add(d.key);
  if (event.ports && event.ports[0]) event.ports[0].postMessage('armed');
});

/** The shelf's own download, passed to the network only with a key a window of this app gave, never from a worker.
 *  (A dedicated worker's requests can carry its page's client id, so the id alone can't tell them apart.) */
async function download(event) {
  if (!keys.has(event.request.headers.get('x-zc-download'))) return missing();
  const client = event.clientId ? await self.clients.get(event.clientId) : null;
  if (client && client.type !== 'window') return missing();
  return fetch(event.request);
}

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET' || !req.url.startsWith(SCOPE)) return;
  const rel = req.url.slice(SCOPE.length).split(/[?#]/)[0];
  if (rel.startsWith('engines/')) {
    if (rel === 'engines/catalog.json') { event.respondWith(fresh(req, META, 5000)); return; }
    if (req.headers.has('x-zc-download')) { event.respondWith(download(event)); return; } // checked by the shelf
    event.respondWith(packFile(rel.slice('engines/'.length)));
    return;
  }
  // Each engine's page (<id>/) is in the shell, so it opens offline as any other file of it does.
  event.respondWith(fresh(req, SHELL_CACHE, 4000));
});
