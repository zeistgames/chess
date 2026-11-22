// SPDX-License-Identifier: AGPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');

test('a fresh error leaves the cached page usable', async () => {
  for (const status of [404, 503]) {
    const get = runInNewContext(source + '\nfresh;', {
      self: { SHELL: { version: '1' }, registration: { scope: 'https://test.invalid/' }, addEventListener() {} },
      importScripts() {}, fetch: async () => new Response('network', { status }),
      caches: { open: async () => ({ match: async () => new Response('cached') }) },
      setTimeout() {}, Response,
    });
    const page = await get('https://test.invalid/stockfish-lite/', 'shell', 4000);
    assert.equal(await page.text(), 'cached');
  }
});
