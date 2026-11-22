// SPDX-License-Identifier: AGPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('worker.js', import.meta.url), 'utf8');

async function readiness(modelStatus) {
  const messages = [], errors = [];
  const self = { location: { href: 'https://test.invalid/maia/worker.js' } };
  await runInNewContext(source + "\nself.onmessage({ data: 'isready' });\nchain;", {
    self, URL, WebAssembly: { Memory: WebAssembly.Memory }, importScripts() {}, Chess: class {},
    ort: { env: { wasm: {} }, InferenceSession: { create: async () => ({}) } },
    fetch: async url => new Response(null, { status: url.endsWith('.onnx') ? modelStatus : 200 }),
    postMessage: line => messages.push(line),
    setTimeout(fn) { try { fn(); } catch (error) { errors.push(error.message); } },
  });
  return { messages, errors };
}

test('a failed model load raises a worker error instead of reporting readiness', async () => {
  const reply = await readiness(503);
  assert.ok(!reply.messages.includes('readyok'));
  assert.deepEqual(reply.errors, ['model HTTP 503']);
});

test('a loaded model reports readiness', async () => {
  assert.deepEqual(await readiness(200), { messages: ['readyok'], errors: [] });
});
