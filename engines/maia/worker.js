// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Maia-3 as a UCI engine in a dedicated Web Worker. Maia does not search: for
// `go` it runs the network once on the current position and plays the move
// the policy rates highest among the legal moves. UCI_Elo sets the rating the
// network imitates (600 to 2600); "Opponent Elo" sets the rating it assumes
// for the other side (0 means the same as UCI_Elo).
//
// Input encoding and move indexing follow the Maia platform
// (https://github.com/CSSLab/maia-platform-frontend, src/lib/engine/tensor.ts):
// 64 square tokens x 12 piece channels, always seen from White's side (the
// board is mirrored when Black is to move); 4352 move logits, from*64+to for
// every square pair, then 256 promotions.

"use strict";

// onnxruntime-web asks for a shared memory that may grow to 4 GB, and a shared
// memory's maximum is reserved up front. iOS limits that reservation, so cap
// it, as the Maia platform does (one position needs far less than 256 MB).
(function () {
  var MAX_PAGES = 4096;
  var Native = WebAssembly.Memory;
  var Capped = function Memory(d) {
    return new Native(d && d.shared && d.maximum > MAX_PAGES ? Object.assign({}, d, { maximum: MAX_PAGES }) : d);
  };
  Capped.prototype = Native.prototype;
  WebAssembly.Memory = Capped;
})();

importScripts("chess.js", "ort/ort.wasm.min.js");

var MODEL = "maia3_simplified.onnx";
var NAME = "Maia 3";
var ELO_MIN = 600;
var ELO_MAX = 2600;

var options = { elo: 1500, oppo: 0, multipv: 1 };
var game = new Chess();
var session = null;
var loading = null;
var chain = Promise.resolve();

function out(line) {
  postMessage(line);
}

function base(p) {
  return new URL(p, self.location.href).href;
}

function load() {
  if (!loading) {
    ort.env.logLevel = "error";
    ort.env.wasm.numThreads = 1;
    ort.env.wasm.proxy = false;
    ort.env.wasm.wasmPaths = base("ort/");
    loading = Promise.all([
      fetch(base("ort/ort-wasm-simd-threaded.wasm")).then(function (r) {
        if (!r.ok) throw new Error("runtime HTTP " + r.status);
        return r.arrayBuffer();
      }),
      fetch(base(MODEL)).then(function (r) {
        if (!r.ok) throw new Error("model HTTP " + r.status);
        return r.arrayBuffer();
      }),
    ])
      .then(function (bufs) {
        ort.env.wasm.wasmBinary = bufs[0];
        // 'basic' keeps the outputs equal to the unoptimized model's (the
        // platform measured 'all' moving the top move in a few positions).
        return ort.InferenceSession.create(new Uint8Array(bufs[1]), {
          executionProviders: ["wasm"],
          graphOptimizationLevel: "basic",
        });
      })
      .then(function (s) {
        session = s;
      })
      .catch(function (e) {
        out("info string Maia could not load: " + (e && e.message ? e.message : e));
        loading = null;
        throw e;
      });
  }
  return loading;
}

var PIECES = { p: 0, n: 1, b: 2, r: 3, q: 4, k: 5 };
var PROMO = { q: 0, r: 1, b: 2, n: 3 };

// Square index a1=0 .. h8=63, mirrored (rank flipped) when flip is set.
function sq(name, flip) {
  var f = name.charCodeAt(0) - 97;
  var r = name.charCodeAt(1) - 49;
  if (flip) r = 7 - r;
  return r * 8 + f;
}

function moveIndex(m, flip) {
  var from = sq(m.from, flip);
  var to = sq(m.to, flip);
  if (m.promotion) return 4096 + ((from & 7) * 8 + (to & 7)) * 4 + PROMO[m.promotion];
  return from * 64 + to;
}

function tokens(flip) {
  var t = new Float32Array(64 * 12);
  var b = game.board(); // b[0] is rank 8
  for (var row = 0; row < 8; row++) {
    for (var f = 0; f < 8; f++) {
      var p = b[row][f];
      if (!p) continue;
      var rank = 7 - row;
      var own = p.color === "w";
      if (flip) {
        rank = 7 - rank;
        own = !own;
      }
      t[(rank * 8 + f) * 12 + PIECES[p.type] + (own ? 0 : 6)] = 1;
    }
  }
  return t;
}

function uciMove(m) {
  return m.from + m.to + (m.promotion || "");
}

function go() {
  return load().then(function () {
    var legal = game.moves({ verbose: true });
    if (!legal.length) {
      out("bestmove 0000");
      return;
    }
    var flip = game.turn() === "b";
    var elo = options.elo;
    var oppo = options.oppo > 0 ? options.oppo : elo;
    var feeds = {
      tokens: new ort.Tensor("float32", tokens(flip), [1, 64, 12]),
      elo_self: new ort.Tensor("float32", Float32Array.from([elo]), [1]),
      elo_oppo: new ort.Tensor("float32", Float32Array.from([oppo]), [1]),
    };
    return session.run(feeds).then(function (res) {
      var logits = res.logits_move.data;
      var wdl = res.logits_value.data; // loss, draw, win for the side to move
      var ranked = legal
        .map(function (m) {
          return { move: uciMove(m), logit: logits[moveIndex(m, flip)] };
        })
        .sort(function (a, b) {
          return b.logit - a.logit || (a.move < b.move ? -1 : 1);
        });
      var max = ranked[0].logit;
      var sum = 0;
      ranked.forEach(function (r) {
        r.p = Math.exp(r.logit - max);
        sum += r.p;
      });
      var mw = Math.max(wdl[0], wdl[1], wdl[2]);
      var el = Math.exp(wdl[0] - mw), ed = Math.exp(wdl[1] - mw), ew = Math.exp(wdl[2] - mw);
      var win = (ew + 0.5 * ed) / (el + ed + ew);
      var w = Math.min(0.999, Math.max(0.001, win));
      var cp = Math.round(400 * Math.log10(w / (1 - w)));
      var n = Math.min(options.multipv, ranked.length);
      var policy = [];
      for (var i = 0; i < n; i++) {
        out("info depth 1 seldepth 1 multipv " + (i + 1) + " score cp " + cp + " nodes 1 nps 1 time 0 pv " + ranked[i].move);
        policy.push(ranked[i].move + " " + (ranked[i].p / sum).toFixed(4));
      }
      out("info string policy " + policy.join(" "));
      out("bestmove " + ranked[0].move);
    });
  });
}

function position(args) {
  var i = 0;
  var g;
  if (args[0] === "startpos") {
    g = new Chess();
    i = 1;
  } else if (args[0] === "fen") {
    var fen = [];
    for (i = 1; i < args.length && args[i] !== "moves"; i++) fen.push(args[i]);
    g = new Chess();
    if (!g.load(fen.join(" "))) {
      out("info string invalid fen: " + fen.join(" "));
      return;
    }
  } else {
    return;
  }
  if (args[i] === "moves") {
    for (i = i + 1; i < args.length; i++) {
      var m = args[i];
      var done = g.move({ from: m.slice(0, 2), to: m.slice(2, 4), promotion: m.length > 4 ? m[4] : undefined });
      if (!done) {
        out("info string illegal move: " + m);
        break;
      }
    }
  }
  game = g;
}

function setoption(line) {
  var m = /^setoption\s+name\s+(.+?)(?:\s+value\s+(.*))?$/i.exec(line);
  if (!m) return;
  var name = m[1].trim().toLowerCase();
  var value = (m[2] || "").trim();
  var n = parseInt(value, 10);
  if (name === "uci_elo") {
    if (!isNaN(n)) options.elo = Math.max(ELO_MIN, Math.min(ELO_MAX, n));
  } else if (name === "opponent elo") {
    if (!isNaN(n)) options.oppo = n <= 0 ? 0 : Math.max(ELO_MIN, Math.min(ELO_MAX, n));
  } else if (name === "multipv") {
    if (!isNaN(n)) options.multipv = Math.max(1, Math.min(10, n));
  } else if (name === "uci_limitstrength") {
    // Maia always plays at a rating; accepted for hosts that send it.
  } else {
    out("info string unknown option: " + m[1]);
  }
}

function handle(line) {
  line = line.trim();
  var args = line.split(/\s+/);
  var cmd = args.shift();
  switch (cmd) {
    case "uci":
      out("id name " + NAME);
      out("id author CSSLab, University of Toronto (Maia-3)");
      out("option name UCI_LimitStrength type check default true");
      out("option name UCI_Elo type spin default 1500 min " + ELO_MIN + " max " + ELO_MAX);
      out("option name Opponent Elo type spin default 0 min 0 max " + ELO_MAX);
      out("option name MultiPV type spin default 1 min 1 max 10");
      out("uciok");
      return;
    case "isready":
      return load().then(
        function () {
          out("readyok");
        },
        function () {
          out("readyok");
        }
      );
    case "setoption":
      return setoption(line);
    case "ucinewgame":
      game = new Chess();
      return;
    case "position":
      return position(args);
    case "go":
      return go();
    case "stop":
    case "ponderhit":
      return;
    case "quit":
      close();
      return;
    case "":
      return;
    default:
      out("info string unknown command: " + line);
  }
}

self.onmessage = function (ev) {
  var line = String(ev.data);
  chain = chain.then(function () {
    return handle(line);
  }).catch(function (e) {
    out("info string error: " + (e && e.message ? e.message : e));
  });
};

// Start loading at once, so the first isready does not wait for all of it.
load().catch(function () {});
