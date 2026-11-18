#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Checks engine packs in Node, as the app's host would drive them.
//
//   node engines/check.mjs <id> [<id> ...]     check these packs
//   node engines/check.mjs --all               check every staged pack
//   add --dist to check the packs in engines/dist instead of engines/build/<id>/pack
//
// For each pack: files match manifest sizes and sha256; `uci` gives `uciok`;
// `isready` gives `readyok`; `position startpos moves e2e4` then
// `go nodes 20000` (Maia: `go nodes 1`) gives a legal bestmove; the same search
// in a fresh worker gives the same move; a claimed strength option is listed
// and accepted. Results go to engines/build/checks/<id>.node.json.

import { Worker } from "node:worker_threads";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { LEGAL_AFTER_E4, strengthCommands, searchNodes } from "./tools/protocol.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.join(here, "dist");
// Packs are checked in their staging folder (engines/build/<id>/pack) unless
// --dist is given. Results go to engines/build/checks/<id>.<kind>.json.
const useDist = process.argv.includes("--dist");
const packDir = (id) => (useDist ? path.join(dist, id) : path.join(here, "build", id, "pack"));
const checksDir = path.join(here, "build", "checks");
const allIds = () =>
  useDist
    ? fs.readdirSync(dist).filter((d) => fs.existsSync(path.join(dist, d, "manifest.json"))).sort()
    : fs.readdirSync(here).filter((d) => fs.existsSync(path.join(here, d, "meta.json")) && fs.existsSync(path.join(packDir(d), "manifest.json"))).sort();
const shim = path.join(here, "tools", "worker-shim.cjs");

class Engine {
  constructor(script) {
    this.lines = [];
    this.waiters = [];
    this.errors = [];
    this.started = performance.now();
    this.worker = new Worker(shim, { workerData: { script } });
    this.worker.on("message", (line) => {
      line = String(line);
      if (line.startsWith("__shim_error")) this.errors.push(line);
      for (const l of line.split("\n")) {
        this.lines.push(l);
        for (const w of this.waiters.slice()) w(l);
      }
    });
    this.worker.on("error", (e) => this.errors.push(String(e && e.stack ? e.stack : e)));
  }
  send(line) {
    this.worker.postMessage(line);
  }
  waitFor(re, ms) {
    const already = this.lines.find((l) => re.test(l));
    if (already) return Promise.resolve(already);
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => {
        this.waiters.splice(this.waiters.indexOf(fn), 1);
        reject(new Error(`timeout after ${ms} ms waiting for ${re}; errors: ${this.errors.join(" | ").slice(0, 2000)}`));
      }, ms);
      const fn = (l) => {
        if (re.test(l)) {
          clearTimeout(t);
          this.waiters.splice(this.waiters.indexOf(fn), 1);
          resolve(l);
        }
      };
      this.waiters.push(fn);
    });
  }
  // Wait for the next match that arrives after this call.
  next(re, ms) {
    const from = this.lines.length;
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => {
        this.waiters.splice(this.waiters.indexOf(fn), 1);
        reject(new Error(`timeout after ${ms} ms waiting for ${re}; errors: ${this.errors.join(" | ").slice(0, 2000)}`));
      }, ms);
      const fn = (l) => {
        if (re.test(l)) {
          clearTimeout(t);
          this.waiters.splice(this.waiters.indexOf(fn), 1);
          resolve(l);
        }
      };
      this.waiters.push(fn);
      for (const l of this.lines.slice(from)) fn(l);
    });
  }
  async close() {
    await this.worker.terminate();
  }
}

function sha256(file) {
  return createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

async function search(script, manifest, { strength } = {}) {
  const e = new Engine(script);
  const r = { log: [] };
  try {
    e.send("uci");
    await e.waitFor(/^uciok\b/, 180000);
    r.uciok_ms = Math.round(performance.now() - e.started);
    if (strength) {
      const cmds = strengthCommands(manifest.strength);
      for (const name of cmds.names) {
        const re = new RegExp("^option name " + name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + " type ", "i");
        if (!e.lines.some((l) => re.test(l))) throw new Error(`strength option "${name}" is not listed by uci`);
      }
      const mark = e.lines.length;
      for (const c of cmds.lines) e.send(c);
      e.send("isready");
      await e.next(/^readyok\b/, 60000);
      const complaint = e.lines.slice(mark).find((l) => !/^info /.test(l) && /unknown|no such option|invalid|error|not supported/i.test(l));
      if (complaint) throw new Error("strength option rejected: " + complaint);
      r.strength_commands = cmds.lines;
    } else {
      e.send("isready");
      await e.next(/^readyok\b/, 120000);
    }
    r.ready_ms = Math.round(performance.now() - e.started);
    e.send("position startpos moves e2e4");
    const goAt = performance.now();
    e.send(`go nodes ${searchNodes(manifest)}`);
    const best = await e.next(/^bestmove\b/, 300000);
    r.search_ms = Math.round(performance.now() - goAt);
    r.first_move_ms = Math.round(performance.now() - e.started);
    r.bestmove = best.split(/\s+/)[1];
    r.legal = LEGAL_AFTER_E4.has(r.bestmove);
    r.errors = e.errors;
  } finally {
    r.log = e.lines.filter((l) => !/^info .*(currmove|hashfull)/.test(l)).slice(-40);
    await e.close();
  }
  return r;
}

async function checkPack(id) {
  const dir = packDir(id);
  const result = { id, checked_at: new Date().toISOString(), node: process.version, pass: false, steps: {} };
  if (!fs.existsSync(path.join(dir, "manifest.json"))) {
    result.error = "no manifest.json: the pack was not built";
    return result;
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
  const manifestHash = sha256(path.join(dir, "manifest.json"));
  result.manifest_sha256 = manifestHash;
  try {
    for (const k of ["id", "name", "version", "author", "license", "net_license", "source", "line", "files", "entry", "strength", "multipv", "threads"]) {
      if (!(k in manifest)) throw new Error("manifest is missing " + k);
    }
    if (manifest.id !== id) throw new Error("manifest id does not match folder");
    for (const f of manifest.files) {
      const p = path.join(dir, f.path);
      const st = fs.statSync(p);
      if (st.size !== f.bytes) throw new Error(`${f.path}: ${st.size} bytes, manifest says ${f.bytes}`);
      if (sha256(p) !== f.sha256) throw new Error(`${f.path}: sha256 does not match manifest`);
      if (/\.m?js$/.test(f.path) && f.bytes > 25 * 1024 * 1024) throw new Error(`${f.path}: JS file over 25 MiB`);
    }
    if (!manifest.files.some((f) => f.path === manifest.entry)) throw new Error("entry is not in files");
    result.steps.files = "ok";
    const script = path.join(dir, manifest.entry);

    const a = await search(script, manifest);
    result.steps.first = a;
    if (!a.legal) throw new Error(`bestmove ${a.bestmove} is not legal after 1. e4`);
    const b = await search(script, manifest);
    result.steps.second = b;
    if (b.bestmove !== a.bestmove) throw new Error(`not repeatable: ${a.bestmove} then ${b.bestmove}`);
    if (manifest.strength && manifest.strength.type !== "none") {
      const s = await search(script, manifest, { strength: true });
      result.steps.strength = s;
      if (!s.legal) throw new Error(`bestmove ${s.bestmove} with strength set is not legal`);
    }
    result.pass = true;
  } catch (e) {
    result.error = String(e && e.message ? e.message : e);
  }
  fs.mkdirSync(checksDir, { recursive: true });
  fs.writeFileSync(path.join(checksDir, `${id}.node.json`), JSON.stringify(result, null, 2) + "\n");
  return result;
}

const args = process.argv.slice(2);
let ids = args.filter((a) => !a.startsWith("--"));
if (args.includes("--all")) {
  ids = allIds();
}
if (!ids.length) {
  console.error("usage: node engines/check.mjs <id> [...] | --all");
  process.exit(2);
}
let failed = 0;
for (const id of ids) {
  const r = await checkPack(id);
  const f = r.steps.first || {};
  if (r.pass) {
    console.log(`PASS ${id}  bestmove ${f.bestmove}  uciok ${f.uciok_ms} ms  first move ${f.first_move_ms} ms  search ${f.search_ms} ms`);
  } else {
    failed++;
    console.log(`FAIL ${id}  ${r.error}`);
  }
}
process.exit(failed ? 1 : 0);
