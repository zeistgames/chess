// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Signed in with Zeist, when this app is served under zeist.gg: it shares Zeist's session cookie, and GET /api/me on
// the same origin says who you are. Anywhere else /api/me isn't Zeist's, and the app is simply signed out. Nothing
// else on Zeist's API is called. Offline, the last answer stays.

import { get, set } from './store.js';

let state = { hosted: get('account.hosted', false), user: get('account.me', null) };

export function current() { return state; }

export async function refresh() {
  try {
    const r = await fetch('/api/me', { credentials: 'same-origin', headers: { accept: 'application/json' }, cache: 'no-store' });
    const type = r.headers.get('content-type') || '';
    if (!r.ok || !type.includes('json')) { state = { hosted: false, user: null }; }
    else {
      const j = await r.json();
      state = j && typeof j === 'object' && 'user' in j ? { hosted: true, user: j.user || null } : { hosted: false, user: null };
    }
  } catch {
    return state; // offline: keep what was known
  }
  set('account.hosted', state.hosted);
  set('account.me', state.user);
  return state;
}

/** Refresh the visible page after returning or another tab writes storage. A later event wins over an answer in flight. */
export function watch(onAccount) {
  let reading = false, again = false;
  const update = async () => {
    again = true;
    if (reading) return;
    reading = true;
    try {
      while (again) {
        again = false;
        const account = await refresh();
        if (!again) await onAccount(account);
      }
    } finally {
      reading = false;
    }
  };
  const revisit = () => { if (!document.hidden) return update().catch(e => console.warn('account:', e)); };
  document.addEventListener('visibilitychange', revisit);
  addEventListener('storage', revisit);
  return update();
}

/** Zeist's sign-in, coming back to this page afterward. Only meaningful when served under zeist.gg. */
export function signInURL() {
  return '/welcome?return=' + encodeURIComponent(location.pathname + location.search);
}
