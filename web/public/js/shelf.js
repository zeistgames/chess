// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The engines: the catalog from the server, and the packs kept in this browser. A pack is downloaded on purpose,
// one engine at a time: its manifest checked against the catalog's record of it (manifest_sha256), every file
// against the size and sha256 that manifest gives, and kept in Cache Storage under the same address it is served
// from (<base>engines/<id>/<file>). The service worker hands an engine only those kept files, never the network
// (sw.js). A pack counts as installed once its manifest.json is stored, which happens last.
//
// Where the files come from: straight from the packs' own server (config.js PACKS, engines.zei.st) when it answers this
// site with CORS headers, so the download never runs this site's Worker; else, or if that fails, through the Worker at
// <base>engines/, which reads the same bucket. Either way every file is checked here before it is kept.

import { ENGINES, get as pref, set as setPref, ownWorker, untilOwnWorker } from './store.js';
import { PACKS as ORIGIN } from './config.js';

export const PACKS = 'zc-packs';

// Straight from the packs' server until a request to it fails (no CORS answer, say); then the Worker, for this visit.
let direct = !!ORIGIN;
const TYPES = { js: 'text/javascript', mjs: 'text/javascript', wasm: 'application/wasm', json: 'application/json', txt: 'text/plain', nnue: 'application/octet-stream' };
const typeOf = p => TYPES[p.split('.').pop().toLowerCase()] || 'application/octet-stream';

/** A pack server file (rel, such as "maia/manifest.json" or "catalog.json"), from the packs' server or the Worker. */
async function fetchPack(rel, { signal, keyed = false } = {}) {
  if (direct) {
    try {
      const r = await fetch(ORIGIN + rel, { cache: 'no-store', mode: 'cors', credentials: 'omit', signal });
      if (r.ok) return r;
    } catch (e) { if (signal && signal.aborted) throw e; }
    direct = false;
  }
  if (keyed) await arm();
  return fetch(ENGINES + rel, { cache: 'no-store', signal, ...(keyed ? { headers: DOWNLOAD } : {}) });
}

let catalog = pref('catalog', null);
let catalogProblem = null;
const listeners = new Set();
const downloads = new Map(); // id -> { progress, controller, error }

export function subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); }
function changed() { for (const fn of listeners) { try { fn(); } catch (e) { console.error(e); } } }

/** Reads catalog.json again. Offline, the last one read stays. */
export async function refresh() {
  try {
    const r = await fetchPack('catalog.json');
    if (!r.ok) throw new Error('status ' + r.status);
    const j = await r.json();
    const list = Array.isArray(j) ? j : j.engines || j.packs;
    if (!Array.isArray(list)) throw new Error('no engines');
    catalog = list;
    setPref('catalog', list);
    catalogProblem = null;
  } catch {
    catalogProblem = navigator.onLine === false
      ? "You're offline. Engines in this browser still play."
      : "The list of engines couldn't be loaded. Engines in this browser still play.";
  }
  await rebuild();
  return catalogProblem;
}

export function problem() { return catalogProblem; }

let engines = [];
let installedCache = new Map(); // id -> { manifest, packSHA }

async function cache() { return caches.open(PACKS); }

async function readInstalled() {
  const out = new Map();
  if (!('caches' in self)) return out;
  const c = await cache();
  for (const req of await c.keys()) {
    const m = req.url.match(/engines\/([^/]+)\/manifest\.json$/);
    if (!m || !req.url.startsWith(ENGINES)) continue;
    const res = await c.match(req);
    if (!res) continue;
    const raw = await res.arrayBuffer();
    try {
      out.set(m[1], { manifest: JSON.parse(new TextDecoder().decode(raw)), packSHA: await sha256(raw) });
    } catch { /* a damaged manifest: treated as not installed */ }
  }
  return out;
}

async function rebuild() {
  installedCache = await readInstalled();
  const out = [];
  const seen = new Set();
  for (const m of catalog || []) {
    if (seen.has(m.id)) continue;
    seen.add(m.id);
    const inst = installedCache.get(m.id);
    // An installed pack stays the version it was installed from: its kept manifest, whose sha256 was the catalog
    // entry's manifest_sha256 then, and whose version it names. A different version listed now is offered as an
    // update, never applied or removed on its own.
    const update = inst && m.manifest_sha256 && String(m.manifest_sha256).toLowerCase() !== inst.packSHA ? m : null;
    out.push(inst ? { manifest: inst.manifest, listed: m, installed: true, packSHA: inst.packSHA, update } : { manifest: m, listed: m, installed: false });
  }
  for (const [id, inst] of installedCache) {
    if (!seen.has(id)) out.push({ manifest: inst.manifest, installed: true, packSHA: inst.packSHA });
  }
  engines = out;
  changed();
}

let reading = null; // the catalog read that load() started
export async function load() { await rebuild(); reading = refresh(); }
/** The catalog read load() started, once it is done. */
export function listed() { return reading || Promise.resolve(catalogProblem); }

export function list() { return engines; }
export function engine(id) { return engines.find(e => e.manifest.id === id) || null; }
export function download(id) { return downloads.get(id) || null; }

/** Zeist Chess's source. */
export const REPOSITORY = 'https://github.com/zeistgames/chess';
/** Where a pack's source is: its folder in the repository, which names the upstream version, carries the changes made
 *  to it and the steps that build it. The upstream address alone (the manifest's `source`) leaves those out. */
export function packSource(id) { return `${REPOSITORY}/tree/main/engines/${id}`; }
/** The licenses to show beside an engine: the program's, and the network's where it has one under other terms. */
export function licensesOf(m) {
  if (!m.license) return '';
  const program = m.license.replace(/ AND /g, ', ');
  const n = m.net_license;
  return !n || n === 'none' || n === m.license ? program : `${program}. Network: ${n}`;
}

export function bytesOf(m) { return m.total_bytes || (m.files || []).reduce((a, f) => a + f.bytes, 0); }

/** Bytes kept by downloaded packs (as their manifests count them). */
export function used() {
  let n = 0;
  for (const e of engines) if (e.installed) n += bytesOf(e.manifest);
  return n;
}

export async function sha256(buf) {
  const d = await crypto.subtle.digest('SHA-256', buf);
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}

export class PackError extends Error {}

/** A key for this page's downloads, which the service worker lets through to the network to be checked here. It
 *  stays in this page: an engine's worker can't read it (sw.js). */
const KEY = [...crypto.getRandomValues(new Uint8Array(24))].map(b => b.toString(16).padStart(2, '0')).join('');
const DOWNLOAD = { 'x-zc-download': KEY };

// A pack whose files the service worker found changed: removed there, said here, offered for download again.
// Kept in this browser's settings, so a reload still says it.
const removed = new Set(pref('damaged', []) || []);
function keepRemoved() { setPref('damaged', removed.size ? [...removed] : null); }
/** Whether this pack was removed because its files were changed in this browser. */
export function wasDamaged(id) { return removed.has(id); }
if (typeof navigator !== 'undefined' && navigator.serviceWorker) {
  navigator.serviceWorker.addEventListener('message', e => {
    if (e.data && e.data.type === 'zc-pack-removed') {
      if (e.data.id) { removed.add(String(e.data.id)); keepRemoved(); }
      rebuild();
    }
  });
  navigator.serviceWorker.startMessages(); // WebKit holds messages until asked
}

/** Whether the service worker pins this manifest (sw.js): true or false; null when no service worker answers for
 *  this page (it enforces the pins itself when it serves the pack). One that answers for the page but doesn't reply
 *  in time counts as false: a reload sets it right. */
async function pinnedHere(id, sha) {
  const sw = ownWorker();
  if (!sw) return null;
  return new Promise(resolve => {
    const ch = new MessageChannel();
    ch.port1.onmessage = e => resolve(e.data?.pinned === true && e.data.packLayout === 2);
    setTimeout(() => resolve(false), 10000);
    sw.postMessage({ type: 'zc-pinned', id, sha, packLayout: 2 }, [ch.port2]);
  });
}

/** Gives the service worker this page's key, again before every request: it forgets keys when it stops. */
async function arm() {
  const sw = ownWorker(); // never another worker (Zeist's, at /chess): the key stays with this app's
  if (!sw) return; // no service worker answers for this page: its requests go to the network as they are
  await new Promise(resolve => {
    const ch = new MessageChannel();
    ch.port1.onmessage = resolve;
    setTimeout(resolve, 2000);
    sw.postMessage({ type: 'zc-download-key', key: KEY }, [ch.port2]);
  });
}

/** Whether a manifest, as downloaded (raw bytes, parsed m), is the one the catalog lists for its engine. */
async function matchesCatalog(listed, raw, m) {
  if (!listed || m.id !== listed.id) return false;
  if (listed.manifest_sha256) return (await sha256(raw)) === String(listed.manifest_sha256).toLowerCase();
  // A catalog without the manifest's checksum: the parts that decide what runs must be the same.
  const files = x => JSON.stringify((x.files || []).map(f => [f.path, f.bytes, String(f.sha256).toLowerCase()]));
  return m.version === listed.version && m.entry === listed.entry && files(m) === files(listed);
}

/** Downloads a pack, checks every file, and keeps it. Resolves when it is installed. */
export async function install(id) {
  if (downloads.has(id) && !downloads.get(id).error) return downloads.get(id).promise;
  const controller = new AbortController();
  const state = { progress: 0, controller, error: null };
  downloads.set(id, state);
  changed();
  state.promise = (async () => {
    const base = ENGINES + id + '/'; // where it is kept and served from, wherever it is downloaded from
    const c = await cache();
    // Stage under a unique address. Only the canonical manifest can make these files visible to the worker.
    const generation = crypto.randomUUID();
    const stage = base + '.pack-' + generation + '/';
    const manifestURL = base + 'manifest.json';
    const written = [];
    let published = false;
    try {
      // This app's own worker, which checks the pins, should answer for the page before anything is kept: on a first
      // visit from Zeist's /chess it takes over a moment after the page loads.
      await untilOwnWorker(15000);
      const mr = await fetchPack(id + '/manifest.json', { signal: controller.signal, keyed: true });
      if (!mr.ok) throw new PackError(mr.status === 404 ? "This engine isn't on the server." : 'The download failed.');
      const raw = await mr.arrayBuffer();
      let m;
      try { m = JSON.parse(new TextDecoder().decode(raw)); } catch { throw new PackError("This pack's manifest can't be read."); }
      // Only the pack the catalog lists runs: its manifest must be that one, byte for byte. A catalog read earlier may
      // be out of date, so read it again once before refusing.
      const listedNow = () => (catalog || []).find(e => e.id === id);
      const chosen = listedNow();
      if (!(await matchesCatalog(chosen, raw, m))) {
        await refresh();
        const now = listedNow();
        if (!(await matchesCatalog(now, raw, m))) throw new PackError("This pack's manifest doesn't match the list.");
        // The server has moved on since this was chosen: show what there is now and let them choose again.
        if (!chosen || chosen.version !== now.version || chosen.manifest_sha256 !== now.manifest_sha256) {
          throw new PackError(`${now.name || id} has been updated to version ${now.version} since this list was shown.`);
        }
      }
      // A version published after this app was deployed: the service worker won't run it until the app is reloaded.
      if ((await pinnedHere(id, await sha256(raw))) === false) {
        throw new PackError(`Version ${m.version} of ${m.name || id} needs the app to be reloaded. Reload the page, then download it.`);
      }
      const total = Math.max(1, m.files.reduce((a, f) => a + f.bytes, 0));
      let done = 0;
      for (const f of m.files) {
        if (f.path.includes('..') || f.path.startsWith('/') || /^[a-z]+:/i.test(f.path)) throw new PackError('This pack has a file outside its folder.');
        const url = new URL(f.path, base).href;
        if (!url.startsWith(base)) throw new PackError('This pack has a file outside its folder.');
        const r = await fetchPack(url.slice(ENGINES.length), { signal: controller.signal, keyed: true });
        if (!r.ok) throw new PackError('The download failed.');
        const chunks = [];
        let got = 0;
        const reader = r.body.getReader();
        for (;;) {
          const { done: end, value } = await reader.read();
          if (end) break;
          chunks.push(value);
          got += value.byteLength;
          state.progress = (done + Math.min(got, f.bytes)) / total;
          changed();
        }
        const blob = new Blob(chunks);
        if (blob.size !== f.bytes || (await sha256(await blob.arrayBuffer())) !== String(f.sha256).toLowerCase()) {
          throw new PackError("A file didn't match its checksum.");
        }
        const staged = stage + url.slice(base.length);
        await c.put(staged, new Response(blob, { headers: { 'content-type': typeOf(f.path), 'content-length': String(blob.size) } }));
        written.push(staged);
        done += f.bytes;
        state.progress = done / total;
        changed();
      }
      // Publish the manifest last. The one replacement put selects the whole version at once.
      if (controller.signal.aborted) throw new PackError('stopped');
      const previous = await c.match(manifestURL);
      await c.put(manifestURL, new Response(raw, { headers: {
        'content-type': 'application/json', 'x-zc-generation': generation,
      } }));
      published = true;
      if (previous) {
        const old = previous.headers.get('x-zc-generation');
        const dir = old ? base + '.pack-' + old + '/' : base;
        for (const k of await c.keys()) {
          if (k.url !== manifestURL && k.url.startsWith(dir) && (old || !k.url.startsWith(base + '.pack-'))) {
            await c.delete(k).catch(() => {});
          }
        }
      }
      if (removed.delete(id)) keepRemoved();
      downloads.delete(id);
      persist();
      await rebuild();
    } catch (e) {
      if (!published) for (const u of written) await c.delete(u).catch(() => {});
      if (controller.signal.aborted) { downloads.delete(id); changed(); throw new PackError('stopped'); }
      state.error = e instanceof PackError ? e.message
        : navigator.onLine === false ? "You're offline."
        : /quota/i.test(String(e && (e.name + e.message))) ? "There isn't room for it in this browser."
        : 'The download failed.';
      changed();
      throw new PackError(state.error);
    }
  })();
  state.promise.catch(() => {});
  return state.promise;
}

export function cancel(id) { const d = downloads.get(id); if (d && d.controller) d.controller.abort(); }
export function clearFailure(id) { const d = downloads.get(id); if (d && d.error) { downloads.delete(id); changed(); } }

/** Removes a downloaded pack and frees its space. */
export async function remove(id) {
  const c = await cache();
  for (const req of await c.keys()) if (req.url.startsWith(ENGINES + id + '/')) await c.delete(req);
  await rebuild();
}

/** Asks once, quietly, for storage the browser won't clear on its own, after the first download. */
async function persist() {
  try {
    if (pref('persistAsked', false) || !navigator.storage || !navigator.storage.persist) return;
    setPref('persistAsked', true);
    if (!(await navigator.storage.persisted())) await navigator.storage.persist();
  } catch { /* not offered here */ }
}

export async function storage() {
  const out = { persisted: false, quota: null };
  try {
    if (navigator.storage && navigator.storage.persisted) out.persisted = await navigator.storage.persisted();
    if (navigator.storage && navigator.storage.estimate) {
      const e = await navigator.storage.estimate();
      out.quota = e.quota; out.usage = e.usage;
    }
  } catch { /* unknown */ }
  return out;
}

/** "1.9 MB", "99 MB", "620 KB". */
export function say(bytes) {
  if (bytes < 1e6) return `${Math.max(1, Math.round(bytes / 1e3))} KB`;
  if (bytes < 1e7) return `${(bytes / 1e6).toFixed(1)} MB`;
  if (bytes < 1e9) return `${Math.round(bytes / 1e6)} MB`;
  return `${(bytes / 1e9).toFixed(1)} GB`;
}

/** The ratings an engine can be set to directly, on its own scale, or null. */
export function ratings(m) {
  const s = m && m.strength;
  if (!s || typeof s !== 'object') return null;
  const o = s.uci_elo || ((s.type || s.kind) === 'uci_elo' ? s : null);
  if (!o || !(+o.min < +o.max)) return null;
  return [+o.min, +o.max];
}
