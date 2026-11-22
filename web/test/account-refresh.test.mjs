// SPDX-License-Identifier: AGPL-3.0-or-later
import assert from 'node:assert/strict';
import test from 'node:test';

test('a long-open page follows the account after visibility and storage events', async () => {
  const events = new Map(), doc = new Map();
  globalThis.document = { hidden: false, addEventListener: (event, fn) => doc.set(event, fn) };
  globalThis.addEventListener = (event, fn) => events.set(event, fn);
  let user = { handle: 'ada', owner: 'first' };
  globalThis.fetch = async () => Response.json({ user });
  const account = await import('../public/js/account.js');
  const seen = [];
  await account.watch(a => { seen.push(a.user?.handle ?? null); });
  user = { handle: 'bea', owner: 'second' };
  await doc.get('visibilitychange')();
  user = null;
  await events.get('storage')();
  assert.deepEqual(seen, ['ada', 'bea', null]);
  assert.equal(account.current().user, null);
});
