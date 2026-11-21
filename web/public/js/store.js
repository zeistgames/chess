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

export const APP_VERSION = 'Web 0.1';
