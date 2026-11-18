#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Writes engines/dist/catalog.json: every pack whose current manifest passed
// both the Node check and the WebKit check. Packs that did not pass are left
// out and named on stderr.
//
//   node engines/tools/catalog.mjs

import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const engines = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dist = path.join(engines, "dist");
const order = JSON.parse(fs.readFileSync(path.join(engines, "order.json"), "utf8"));

function readCheck(id, kind) {
  const p = path.join(engines, "build", "checks", `${id}.${kind}.json`);
  return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : null;
}

const ids = fs
  .readdirSync(dist)
  .filter((d) => !d.startsWith(".") && fs.existsSync(path.join(dist, d, "manifest.json")))
  .sort((a, b) => (order.indexOf(a) + 1 || 999) - (order.indexOf(b) + 1 || 999) || a.localeCompare(b));

const entries = [];
for (const id of ids) {
  const mpath = path.join(dist, id, "manifest.json");
  const hash = createHash("sha256").update(fs.readFileSync(mpath)).digest("hex");
  const node = readCheck(id, "node");
  const webkit = readCheck(id, "webkit");
  const ok = (c) => c && c.pass && c.manifest_sha256 === hash;
  if (!ok(node) || !ok(webkit)) {
    console.error(`left out ${id}: node ${ok(node) ? "pass" : "not passed"}, webkit ${ok(webkit) ? "pass" : "not passed"}`);
    continue;
  }
  const manifest = JSON.parse(fs.readFileSync(mpath, "utf8"));
  entries.push({
    ...manifest,
    manifest: `${id}/manifest.json`,
    manifest_sha256: hash,
    checks: {
      node: { first_move_ms: node.steps.first.first_move_ms, bestmove: node.steps.first.bestmove },
      webkit: {
        first_move_ms: webkit.steps.first.first_move_ms,
        bestmove: webkit.steps.first.bestmove,
        peak_rss_bytes: webkit.peak_rss_bytes ?? null,
      },
    },
  });
}
const catalog = { format: 1, generated_at: new Date().toISOString(), engines: entries };
// Written to a temporary name and renamed, so a reader never sees half a file.
const tmp = path.join(dist, ".catalog.json.tmp");
fs.writeFileSync(tmp, JSON.stringify(catalog, null, 2) + "\n");
fs.renameSync(tmp, path.join(dist, "catalog.json"));
console.log(`wrote engines/dist/catalog.json with ${entries.length} engines: ${entries.map((e) => e.id).join(", ")}`);
