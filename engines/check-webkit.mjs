#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Runs the same pack check as check.mjs in a real WebKit (Playwright's webkit
// build), with the pack served from a local server under a content security
// policy that allows no outside connections. Records time to first move and
// the peak resident memory of the WebKit processes.
//
//   node engines/check-webkit.mjs <id> [...] | --all
//
// Playwright is not a dependency of this repo. Point PLAYWRIGHT_DIR at a folder
// where `npm i playwright && npx playwright install webkit` was run.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
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
const pwDir = process.env.PLAYWRIGHT_DIR;
if (!pwDir) {
  console.error("set PLAYWRIGHT_DIR to a folder where playwright and its webkit are installed");
  process.exit(2);
}
const { webkit } = createRequire(path.join(pwDir, "package.json"))("playwright");

const MIME = { ".js": "text/javascript", ".mjs": "text/javascript", ".wasm": "application/wasm", ".json": "application/json", ".html": "text/html" };
const TIMEOUT = Number(process.env.CHECK_TIMEOUT_MS || 300000);
const CSP = "default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'";

const PAGE = `<!doctype html><meta charset="utf-8"><title>check</title><script>
window.runEngine = function (url, lines, waits, timeoutMs) {
  return new Promise(function (resolve) {
    var t0 = performance.now(), out = [], marks = {}, w = new Worker(url), step = 0, timer;
    function finish(err) { clearTimeout(timer); w.terminate(); resolve({ out: out, marks: marks, error: err || null }); }
    timer = setTimeout(function () { finish("timeout at step " + step + " waiting for " + waits[step]); }, timeoutMs);
    w.onerror = function (e) { out.push("__error " + (e.message || e)); };
    function sendStep() { var l = lines[step]; for (var i = 0; i < l.length; i++) w.postMessage(l[i]); marks["sent" + step] = performance.now() - t0; }
    w.onmessage = function (ev) {
      String(ev.data).split("\\n").forEach(function (line) {
        out.push(line);
        if (step < waits.length && new RegExp(waits[step]).test(line)) {
          marks["got" + step] = performance.now() - t0;
          step++;
          if (step === waits.length) finish(); else sendStep();
        }
      });
    };
    sendStep();
  });
};
</script>`;

function serve() {
  const server = http.createServer((req, res) => {
    const u = new URL(req.url, "http://localhost");
    if (u.pathname === "/" || u.pathname === "/index.html") {
      res.writeHead(200, { "content-type": "text/html", "content-security-policy": CSP });
      return res.end(PAGE);
    }
    const m = /^\/([^/]+)\/(.+)$/.exec(decodeURIComponent(u.pathname));
    const root = m ? packDir(m[1]) : null;
    const p = m ? path.join(root, m[2]) : "";
    if (!m || !p.startsWith(root + path.sep) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, {
      "content-type": MIME[path.extname(p)] || "application/octet-stream",
      "content-length": fs.statSync(p).size,
      "content-security-policy": CSP,
    });
    fs.createReadStream(p).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

// Sum of resident memory of Playwright's WebKit processes, in bytes.
function webkitRss() {
  const out = execFileSync("ps", ["-axo", "rss=,command="], { encoding: "utf8" });
  let kb = 0;
  for (const line of out.split("\n")) {
    if (/ms-playwright\/webkit/.test(line)) kb += parseInt(line.trim().split(/\s+/)[0], 10) || 0;
  }
  return kb * 1024;
}

function sha256(file) {
  return createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

async function checkPack(browser, base, id) {
  const dir = packDir(id);
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
  const result = { id, checked_at: new Date().toISOString(), webkit: browser.version(), pass: false, steps: {} };
  result.manifest_sha256 = sha256(path.join(dir, "manifest.json"));
  const context = await browser.newContext();
  const page = await context.newPage();
  const external = [];
  page.on("request", (r) => {
    if (!r.url().startsWith(base)) external.push(r.url());
  });
  await page.goto(base + "/");
  const url = `${base}/${id}/${manifest.entry}`;
  const nodes = searchNodes(manifest);
  const baseline = webkitRss();
  let peak = baseline;
  const sampler = setInterval(() => {
    try {
      peak = Math.max(peak, webkitRss());
    } catch {}
  }, 100);

  async function one(strength) {
    const lines = [["uci"], ["isready"], ["position startpos moves e2e4", `go nodes ${nodes}`]];
    const waits = ["^uciok", "^readyok", "^bestmove"];
    if (strength) lines[1] = [...strengthCommands(manifest.strength).lines, "isready"];
    const r = await page.evaluate(([u, l, w, t]) => window.runEngine(u, l, w, t), [url, lines, waits, TIMEOUT]);
    if (r.error) throw new Error(r.error + " :: " + r.out.slice(-8).join(" | "));
    const best = r.out.find((l) => /^bestmove\b/.test(l));
    const move = best.split(/\s+/)[1];
    const complaint = strength && r.out.find((l) => !/^info /.test(l) && /unknown|no such option|invalid|error|not supported/i.test(l));
    if (complaint) throw new Error("strength option rejected: " + complaint);
    return {
      bestmove: move,
      legal: LEGAL_AFTER_E4.has(move),
      uciok_ms: Math.round(r.marks.got0),
      ready_ms: Math.round(r.marks.got1),
      first_move_ms: Math.round(r.marks.got2),
      search_ms: Math.round(r.marks.got2 - r.marks.sent2),
    };
  }

  try {
    const a = await one(false);
    result.steps.first = a;
    if (!a.legal) throw new Error(`bestmove ${a.bestmove} is not legal after 1. e4`);
    const b = await one(false);
    result.steps.second = b;
    if (b.bestmove !== a.bestmove) throw new Error(`not repeatable: ${a.bestmove} then ${b.bestmove}`);
    if (manifest.strength && manifest.strength.type !== "none") {
      const s = await one(true);
      result.steps.strength = s;
      if (!s.legal) throw new Error(`bestmove ${s.bestmove} with strength set is not legal`);
    }
    if (external.length) throw new Error("requests outside the pack: " + external.join(", "));
    result.pass = true;
  } catch (e) {
    result.error = String(e && e.message ? e.message : e);
  } finally {
    clearInterval(sampler);
    result.baseline_rss_bytes = baseline;
    result.peak_rss_bytes = peak;
    await context.close();
  }
  fs.mkdirSync(checksDir, { recursive: true });
  fs.writeFileSync(path.join(checksDir, `${id}.webkit.json`), JSON.stringify(result, null, 2) + "\n");
  return result;
}

const args = process.argv.slice(2);
let ids = args.filter((a) => !a.startsWith("--"));
if (args.includes("--all")) {
  ids = allIds();
}
if (!ids.length) {
  console.error("usage: node engines/check-webkit.mjs <id> [...] | --all");
  process.exit(2);
}
const server = await serve();
const base = `http://127.0.0.1:${server.address().port}`;
let failed = 0;
for (const id of ids) {
  // A fresh browser per pack, so the memory figure belongs to this pack.
  const browser = await webkit.launch();
  const r = await checkPack(browser, base, id);
  await browser.close();
  const f = r.steps.first || {};
  const mb = (n) => (n / 1048576).toFixed(0) + " MB";
  if (r.pass) console.log(`PASS ${id}  bestmove ${f.bestmove}  first move ${f.first_move_ms} ms  peak rss ${mb(r.peak_rss_bytes)} (baseline ${mb(r.baseline_rss_bytes)})`);
  else {
    failed++;
    console.log(`FAIL ${id}  ${r.error}`);
  }
}
server.close();
process.exit(failed ? 1 : 0);
