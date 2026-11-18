// SPDX-License-Identifier: AGPL-3.0-or-later
// Small settings kept in this browser. Every read and write survives a browser that refuses storage.

const PREFIX = 'zc.';

export function get(key, fallback) {
  try {
    const v = localStorage.getItem(PREFIX + key);
    return v == null ? fallback : JSON.parse(v);
  } catch { return fallback; }
}

export function set(key, value) {
  try {
    if (value === undefined || value === null) localStorage.removeItem(PREFIX + key);
    else localStorage.setItem(PREFIX + key, JSON.stringify(value));
  } catch { /* private mode or full: the setting lasts this visit only */ }
}

/** The app's address: the folder the page is served from, wherever that is. */
export const BASE = new URL('./', document.baseURI).href;
export const ENGINES = new URL('engines/', BASE).href;

/** The engine named in the address, as in <base>maia, or null. The Worker serves the app there (src/worker.js). */
export function addressedEngine() {
  const rest = location.pathname.slice(new URL(BASE).pathname.length);
  return /^[a-z0-9][a-z0-9-]*$/.test(rest) ? rest : null;
}

/** Zeist, when the app is served one folder under zeist.gg's /chess/ (as /chess/engines/): its address, else null. */
export const ZEIST = /^\/chess\/[^/]+\/$/.test(new URL(BASE).pathname) ? '/chess' : null;

export const APP_VERSION = 'Web 0.1';
