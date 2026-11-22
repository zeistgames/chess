// SPDX-License-Identifier: AGPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../public/js/shelf.js', import.meta.url), 'utf8')
  .replace(/^import .*\n/gm, '').replace(/^export /gm, '');
const ENGINES = 'https://site.invalid/engines/';
const base = ENGINES + 'sample/';
const hash = async data => Buffer.from(await crypto.subtle.digest('SHA-256', Buffer.from(data))).toString('hex');

test('a quota failure at publication keeps the previous pack', async () => {
  const old = JSON.stringify({ id: 'sample', version: '1' });
  const manifest = { id: 'sample', version: '2', entry: 'worker.js',
    files: [{ path: 'worker.js', bytes: 3, sha256: await hash('new') }] };
  const next = JSON.stringify(manifest), manifestURL = base + 'manifest.json';
  const listed = { ...manifest, manifest_sha256: await hash(next) };
  const installed = new Map([[manifestURL, new Response(old)], [base + 'worker.js', new Response('old')]]);
  const stage = new Map();
  let full = true;
  const asCache = entries => ({
    keys: async () => [...entries.keys()].map(url => new Request(url)),
    match: async url => entries.get(url.url || url)?.clone(),
    put: async (url, value) => {
      const key = url.url || url;
      if (full && key === manifestURL) throw new DOMException('cache quota', 'QuotaExceededError');
      entries.set(key, value.clone());
    },
    delete: async url => entries.delete(url.url || url),
  });
  const shelf = runInNewContext(source + '\n({ install, readInstalled });', {
    ENGINES, ORIGIN: null, pref: key => key === 'catalog' ? [listed] : null, setPref() {},
    ownWorker: () => null, untilOwnWorker: async () => null, self: { caches: true },
    caches: { open: async name => asCache(name === 'zc-packs' ? installed : stage) },
    fetch: async url => new Response(url.endsWith('/manifest.json') ? next : 'new'),
    navigator: { locks: { request: async (name, options, callback) => {
      assert.equal(name, 'zc-packs:sample');
      assert.equal(options.signal.aborted, false);
      return callback();
    } } }, crypto, TextDecoder, AbortController, Blob, URL, Response,
  });
  await assert.rejects(shelf.install('sample'), /room/i);
  assert.equal(await installed.get(manifestURL).clone().text(), old);
  assert.equal(await installed.get(base + 'worker.js').clone().text(), 'old');
  assert.equal(installed.size, 2);
  full = false;
  await shelf.install('sample');
  assert.equal((await shelf.readInstalled()).get('sample').manifest.version, '2');
  assert.equal(installed.size, 2, 'old files are gone once the replacement is published');
});

test('startup reclaims abandoned stages and preserves published and live generations', async () => {
  const manifestURL = base + 'manifest.json';
  const current = base + '.pack-current/worker.js';
  const abandoned = base + '.pack-abandoned/worker.js';
  const orphan = ENGINES + 'unused/.pack-orphan/network.nnue';
  const busy = ENGINES + 'busy/.pack-live/worker.js';
  const legacy = ENGINES + 'legacy/worker.js';
  const foreign = 'https://other.invalid/engines/sample/.pack-foreign/worker.js';
  const rows = new Map([
    [manifestURL, new Response(JSON.stringify({ id: 'sample', version: '2' }), { headers: { 'x-zc-generation': 'current' } })],
    ...[current, abandoned, orphan, busy, legacy, foreign].map(url => [url, new Response('file')]),
  ]);
  const shelf = runInNewContext(source + '\n({ load, listed });', {
    ENGINES, ORIGIN: null, pref: () => null, setPref() {}, self: { caches: true },
    caches: { open: async () => ({
      keys: async () => [...rows.keys()].map(url => new Request(url)),
      match: async key => rows.get(key.url || key)?.clone(),
      delete: async key => rows.delete(key.url || key),
    }) },
    navigator: { locks: { request: async (name, options, callback) => {
      assert.equal(options.ifAvailable, true);
      return callback(name.endsWith(':busy') ? null : {});
    } } },
    fetch: async () => new Response('[]'), crypto, TextDecoder,
  });
  await shelf.load();
  await shelf.listed();
  assert.deepEqual([...rows.keys()], [manifestURL, current, busy, legacy, foreign]);
});
