// SPDX-License-Identifier: AGPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import { handle } from '../src/worker.js';

test('the next pack file tries the direct server after a fallback', async () => {
  const source = readFileSync(new URL('../public/js/shelf.js', import.meta.url), 'utf8')
    .replace(/^import .*\n/gm, '').replace(/^export /gm, '');
  const seen = [];
  const get = runInNewContext(source + '\nfetchPack;', {
    ORIGIN: 'https://packs.invalid/', ENGINES: 'https://site.invalid/engines/', pref: () => null, crypto,
    fetch: async url => { seen.push(url); return new Response('data', { status: seen.length === 1 ? 503 : 200 }); },
  });
  await get('sample/manifest.json');
  await get('sample/worker.js');
  assert.deepEqual(seen, [
    'https://packs.invalid/sample/manifest.json',
    'https://site.invalid/engines/sample/manifest.json',
    'https://packs.invalid/sample/worker.js',
  ]);
});

test('the pack Worker treats a failed upstream read as a temporary failure for that request', async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    if (++calls === 1) throw new Error('upstream unavailable');
    return new Response('next file');
  };
  try {
    const env = { BASE: '/', ENGINES_ORIGIN: 'https://packs.invalid' };
    const request = path => new Request('https://site.invalid/engines/sample/' + path);
    assert.equal((await handle(request('manifest.json'), env)).status, 502);
    assert.equal(await (await handle(request('worker.js'), env)).text(), 'next file');
  } finally { globalThis.fetch = original; }
});
