// SPDX-License-Identifier: AGPL-3.0-or-later
//
// UCI for the Zeist chess engine, one line per message, as a dedicated worker. build.sh puts the engine's own
// files (board, evaluation, search, levels) in front of this file, inside one function, so everything here can
// use them by name.
//
// Options: Level 1 to 10 (default 10) and Seed (default 0). Levels 1 to 8 are Zeist's own (CHESS_LEVELS in
// computer.js), the same opponents as in Zeist. Levels 9 and 10 are the full engine, every move its best; they
// differ only in the node limit the app sends. The engine never reads a clock:
//   go nodes N    searches N nodes at the level's choice rules
//   go depth N    searches to depth N
//   go            (with or without clock fields, which are ignored) uses the level's own fixed budget
// The seed for a move is mixed with the number of moves given after `position`, as in the Zeist rated game, so
// the same position, moves, level and seed always give the same bestmove.

const post = (line) => self.postMessage(line);
let level = 10;
// The full engine, for levels above Zeist's eight.
const FULL = { depth: 64, nodes: 250000, margin: 0, noise: 0 };
let seed = 0;
let game = { start: START_FEN, moves: [], ply: 0 };

function setPosition(words) {
	let i = 1;
	let start;
	if (words[i] === "startpos") {
		start = START_FEN;
		i++;
	} else if (words[i] === "fen") {
		const fen = words.slice(i + 1, i + 7).join(" ");
		const p = new Position();
		if (!p.setFen(fen)) {
			post("info string illegal fen");
			return;
		}
		start = p.fen();
		i += 7;
		while (i < words.length && words[i] !== "moves") i++;
	} else return;
	const moves = [];
	if (words[i] === "moves") {
		const p = new Position();
		p.setFen(start);
		for (const text of words.slice(i + 1)) {
			const m = p.parseUci(text);
			if (!m) {
				post(`info string illegal move ${text}`);
				break;
			}
			p.make(m);
			moves.push(text);
		}
	}
	game = { start, moves, ply: moves.length };
}

function go(words) {
	const L = level > 8 ? { ...FULL } : { ...levelOf(level) };
	const n = words.indexOf("nodes"), d = words.indexOf("depth");
	if (d > 0) {
		L.depth = Math.max(1, Math.min(64, Number(words[d + 1]) | 0));
		L.nodes = 1e9;
	}
	if (n > 0) L.nodes = Math.max(1, Number(words[n + 1]) | 0);
	const r = think(game, L, seed, (x) => {
		const score = Math.abs(x.score) >= MATE - 1000 ? `mate ${x.score > 0 ? (MATE - x.score + 1) >> 1 : -((MATE + x.score) >> 1)}` : `cp ${x.score}`;
		post(`info depth ${x.depth} score ${score} nodes ${x.nodes} pv ${x.pv.join(" ")}`);
	});
	post(`bestmove ${r.uci || "0000"}`);
}

function handle(line) {
	const words = line.trim().split(/\s+/);
	switch (words[0]) {
		case "uci":
			post("id name Zeist 1.1");
			post("id author Amrith");
			post("option name Level type spin default 10 min 1 max 10");
			post("option name Seed type spin default 0 min 0 max 4294967295");
			post("uciok");
			break;
		case "isready":
			post("readyok");
			break;
		case "ucinewgame":
			game = { start: START_FEN, moves: [], ply: 0 };
			break;
		case "setoption": {
			const name = words.slice(words.indexOf("name") + 1, words.indexOf("value") > 0 ? words.indexOf("value") : undefined).join(" ").toLowerCase();
			const value = Number(words[words.indexOf("value") + 1]);
			if (name === "level" && Number.isFinite(value)) level = Math.max(1, Math.min(10, value | 0));
			else if (name === "seed" && Number.isFinite(value)) seed = value >>> 0;
			else post(`info string unknown option ${name}`);
			break;
		}
		case "position":
			setPosition(words);
			break;
		case "go":
			go(words);
			break;
		default:
			break;
	}
}

self.onmessage = (e) => {
	for (const line of String(e.data).split("\n")) if (line.trim()) handle(line);
};
