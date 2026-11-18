#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Writes manifest.json from engines/<id>/meta.json and the files already in
// the pack folder (by default the staging folder engines/build/<id>/pack). Sizes and sha256 are computed here.
//
//   node engines/tools/pack.mjs <id> [pack dir, default engines/build/<id>/pack]

import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const engines = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const id = process.argv[2];
if (!id) {
  console.error("usage: node engines/tools/pack.mjs <id>");
  process.exit(2);
}
const meta = JSON.parse(fs.readFileSync(path.join(engines, id, "meta.json"), "utf8"));
const dir = process.argv[3] ? path.resolve(process.argv[3]) : path.join(engines, "build", id, "pack");

function walk(d, prefix = "") {
  const out = [];
  for (const name of fs.readdirSync(d).sort()) {
    if (name.startsWith(".")) continue;
    const rel = prefix ? `${prefix}/${name}` : name;
    const full = path.join(d, name);
    if (fs.statSync(full).isDirectory()) out.push(...walk(full, rel));
    else if (rel !== "manifest.json") out.push(rel);
  }
  return out;
}

const files = walk(dir).map((rel) => {
  const buf = fs.readFileSync(path.join(dir, rel));
  return { path: rel, bytes: buf.length, sha256: createHash("sha256").update(buf).digest("hex") };
});
if (!files.some((f) => f.path === meta.entry)) {
  console.error(`entry ${meta.entry} is not in ${dir}`);
  process.exit(1);
}
const order = ["id", "name", "version", "author", "license", "net_license", "source", "line", "files", "entry", "strength", "multipv", "threads"];
const manifest = {};
for (const k of order) manifest[k] = k === "files" ? files : meta[k];
for (const k of Object.keys(meta)) if (!(k in manifest)) manifest[k] = meta[k];
manifest.id = id;
manifest.threads = false;
manifest.total_bytes = files.reduce((a, f) => a + f.bytes, 0);
for (const k of order) if (manifest[k] === undefined) {
  console.error(`meta.json for ${id} is missing ${k}`);
  process.exit(1);
}
fs.writeFileSync(path.join(dir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(`wrote ${path.relative(path.dirname(engines), path.join(dir, "manifest.json"))}: ${files.length} files, ${manifest.total_bytes} bytes`);
