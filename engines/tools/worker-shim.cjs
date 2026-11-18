// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Runs an engine pack's worker script inside a Node worker_thread, in a plain
// vm context that looks like a dedicated Web Worker: self, postMessage,
// onmessage, addEventListener, importScripts, location and a fetch that only
// reads files next to the script. There is no process, require or global, so
// Emscripten output takes its worker path, as it does in WKWebView.
//
// Network access is refused: fetch of anything outside the pack fails.

"use strict";

const { parentPort, workerData } = require("node:worker_threads");
const vm = require("node:vm");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL, fileURLToPath } = require("node:url");

const scriptPath = path.resolve(workerData.script);
const packDir = path.dirname(scriptPath);
const scriptURL = pathToFileURL(scriptPath);

const MIME = {
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".wasm": "application/wasm",
  ".json": "application/json",
};

function resolveLocal(input) {
  const raw = typeof input === "string" ? input : input && input.url ? input.url : String(input);
  const u = new URL(raw, scriptURL);
  if (u.protocol !== "file:") throw new Error("network access refused: " + u.href);
  const p = fileURLToPath(u);
  if (!p.startsWith(packDir + path.sep) && p !== packDir) {
    throw new Error("access outside the pack refused: " + p);
  }
  return p;
}

// import() from worker code (onnxruntime-web loads its Emscripten glue this
// way) is served by Node's own loader, for files inside the pack only.
const dynImport = vm.constants.USE_MAIN_CONTEXT_DEFAULT_LOADER;

const listeners = [];
const sandbox = {
  console,
  setTimeout,
  clearTimeout,
  setInterval,
  clearInterval,
  setImmediate,
  queueMicrotask,
  structuredClone,
  WebAssembly,
  TextDecoder,
  TextEncoder,
  URL,
  Blob,
  Response,
  Request,
  Headers,
  AbortController,
  ReadableStream,
  WritableStream,
  TransformStream,
  MessageChannel,
  MessagePort,
  Event: globalThis.Event,
  EventTarget,
  atob,
  btoa,
  performance,
  crypto: globalThis.crypto,
  navigator: { hardwareConcurrency: 1, userAgent: "zeist-check" },
  onmessage: null,
  onerror: null,
  close() {
    process.exit(0);
  },
  postMessage(data) {
    parentPort.postMessage(data);
  },
  addEventListener(type, fn) {
    if (type === "message") listeners.push(fn);
  },
  removeEventListener(type, fn) {
    const i = listeners.indexOf(fn);
    if (i >= 0) listeners.splice(i, 1);
  },
  fetch(input) {
    try {
      const p = resolveLocal(input);
      const buf = fs.readFileSync(p);
      const type = MIME[path.extname(p)] || "application/octet-stream";
      return Promise.resolve(
        new Response(buf, { status: 200, headers: { "content-type": type, "content-length": String(buf.length) } })
      );
    } catch (e) {
      return Promise.reject(new TypeError(String(e.message || e)));
    }
  },
  importScripts(...urls) {
    for (const u of urls) {
      const p = resolveLocal(u);
      vm.runInContext(fs.readFileSync(p, "utf8"), context, { filename: p, importModuleDynamically: dynImport });
    }
  },
};
sandbox.self = sandbox;
// Emscripten detects a worker by this global.
sandbox.WorkerGlobalScope = function WorkerGlobalScope() {};
sandbox.DedicatedWorkerGlobalScope = sandbox.WorkerGlobalScope;
// Synchronous XHR is used by some Emscripten builds inside workers.
sandbox.XMLHttpRequest = function XMLHttpRequest() {
  const xhr = {
    readyState: 0,
    status: 0,
    responseType: "",
    response: null,
    onload: null,
    onerror: null,
    onreadystatechange: null,
    open(method, url) {
      xhr._url = url;
    },
    overrideMimeType() {},
    setRequestHeader() {},
    send() {
      try {
        const buf = fs.readFileSync(resolveLocal(xhr._url));
        xhr.status = 200;
        xhr.readyState = 4;
        xhr.response =
          xhr.responseType === "arraybuffer" ? buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length) : buf.toString("latin1");
        xhr.responseText = typeof xhr.response === "string" ? xhr.response : "";
        if (xhr.onreadystatechange) xhr.onreadystatechange();
        if (xhr.onload) xhr.onload();
      } catch (e) {
        xhr.status = 404;
        xhr.readyState = 4;
        if (xhr.onerror) xhr.onerror(e);
      }
    },
  };
  return xhr;
};

const loc = new URL(scriptURL.href);
sandbox.location = {
  href: loc.href,
  origin: "file://",
  protocol: loc.protocol,
  host: "",
  hostname: "",
  pathname: loc.pathname,
  search: "",
  hash: "",
  toString() {
    return loc.href;
  },
};

const context = vm.createContext(sandbox, { name: "engine-worker" });

parentPort.on("message", (data) => {
  const ev = { data, type: "message", target: sandbox };
  if (typeof sandbox.onmessage === "function") sandbox.onmessage(ev);
  for (const fn of listeners.slice()) fn(ev);
});

process.on("uncaughtException", (e) => {
  parentPort.postMessage("__shim_error " + (e && e.stack ? e.stack : String(e)));
});
process.on("unhandledRejection", (e) => {
  parentPort.postMessage("__shim_error " + (e && e.stack ? e.stack : String(e)));
});

vm.runInContext(fs.readFileSync(scriptPath, "utf8"), context, { filename: scriptPath, importModuleDynamically: dynImport });
