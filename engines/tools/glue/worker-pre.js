// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Prepended to every Emscripten engine port. Makes the output a dedicated Web
// Worker that speaks UCI one line per message:
// - each line posted to the worker goes to the exported zeist_uci();
// - each line the engine prints is posted back as one message (stderr lines
//   are posted as "info string ...");
// - network files listed in Module.zeistFiles are fetched by relative path,
//   written into the in-memory file system before main() runs, and removed
//   again after main() (set keep: true on an entry to keep it).
// A build adds a config pre-js before this one that sets Module.zeistFiles and
// Module.zeistArgs.

var Module = typeof Module != "undefined" ? Module : {};
(function () {
  var base = self.location.href;
  var queue = [];
  var ready = false;
  function out(s) {
    s = String(s);
    if (s.length) postMessage(s);
  }
  Module.print = out;
  Module.printErr = function (s) {
    s = String(s);
    if (s.length) postMessage("info string " + s);
  };
  Module.noInitialRun = true;
  Module.locateFile = function (p) {
    return new URL(p, base).href;
  };
  Module.preRun = (Module.preRun || []).concat([
    function () {
      (Module.zeistFiles || []).forEach(function (f) {
        var dep = "zeist:" + f.url;
        Module.addRunDependency(dep);
        fetch(new URL(f.url, base).href)
          .then(function (r) {
            if (!r.ok) throw new Error("HTTP " + r.status);
            return r.arrayBuffer();
          })
          .then(function (b) {
            var dir = f.path.substring(0, f.path.lastIndexOf("/"));
            if (dir) Module.FS.mkdirTree(dir);
            Module.FS.writeFile(f.path, new Uint8Array(b));
            Module.removeRunDependency(dep);
          })
          .catch(function (e) {
            out("info string could not load " + f.url + ": " + e);
          });
      });
    },
  ]);
  function isExit(e) {
    return e && (e.name === "ExitStatus" || e instanceof Error === false && typeof e.status === "number");
  }
  function run(line) {
    try {
      Module.ccall("zeist_uci", null, ["string"], [line]);
    } catch (e) {
      if (isExit(e)) {
        close();
        return;
      }
      out("info string engine error: " + e + " " + (e.stack||""));
    }
  }
  function drain() {
    while (ready && queue.length) run(queue.shift());
  }
  Module.onRuntimeInitialized = function () {
    try {
      Module.callMain(Module.zeistArgs || []);
    } catch (e) {
      if (!isExit(e)) out("info string engine error at start: " + e + " " + (e.stack || ""));
    }
    // Engines read their network during main(). Drop the in-memory file
    // afterwards so the phone does not hold the network twice.
    (Module.zeistFiles || []).forEach(function (f) {
      if (f.keep) return;
      try {
        Module.FS.unlink(f.path);
      } catch (e) {}
    });
    ready = true;
    drain();
  };
  self.onmessage = function (ev) {
    queue.push(String(ev.data));
    drain();
  };
})();
