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

/** The app's address: the folder above js/, wherever it is served (as /chess/vs/). Each engine's page is a folder in it. */
export const BASE = new URL('../', import.meta.url).href;
export const ENGINES = new URL('engines/', BASE).href;

/** This app's own service worker, the one that checks engine files (sw.js). A page under Zeist's /chess can be
 *  controlled first by Zeist's own worker, whose scope holds this folder too; that one checks nothing here. */
export const SW_URL = new URL('sw.js', BASE).href;
export function ownWorker() {
  const c = typeof navigator !== 'undefined' && navigator.serviceWorker && navigator.serviceWorker.controller;
  return c && c.scriptURL === SW_URL ? c : null;
}
/** Waits up to ms for this app's own service worker to answer for the page (it claims the page once active).
 *  Resolves it, or null. */
export async function untilOwnWorker(ms) {
  const sw = typeof navigator !== 'undefined' && navigator.serviceWorker;
  if (!sw) return null;
  const end = Date.now() + ms;
  while (!ownWorker() && Date.now() < end) {
    await Promise.race([
      new Promise(resolve => sw.addEventListener('controllerchange', resolve, { once: true })),
      new Promise(resolve => setTimeout(resolve, Math.min(500, Math.max(0, end - Date.now())))),
    ]);
  }
  return ownWorker();
}

export const APP_VERSION = 'Web 0.1';
