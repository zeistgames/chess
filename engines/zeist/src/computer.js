// The Zeist chess computer: levels and the seeded move choice. Pure: no clocks, no Math.random.
//
// computerMove(s, level, seed) gives the same move for the same state, level and seed on every platform, so a
// rated game can be replayed on the server. As in public/s/rated.js, each move draws from its own stream made
// from the seed and the ply, so a move can be worked out without the ones before it.
//
// Levels 1 to 8, the same eight in Zeist and in Zeist Chess (one table, decided 2026-11-15). Each searches to a
// fixed depth (2 plies at levels 1 and 2, 3 at 3 and 4, 4 at 5 and 6, 5 at 7 and 8) and then every capture
// sequence, then picks among the moves whose score is within `margin` centipawns of the best one, by score plus a
// seeded amount of up to `noise`. So it sees short tactics, misses longer ones and sometimes plays a second-best
// move; every level, level 8 included, varies with the seed. No level is the engine at full strength. `nodes` is a
// safety cap, set per level (20,000, or 60,000 at level 5 and 100,000 at 7 and 8) so the depth is nearly always
// reached: up to about 4% of moves stop short (level 8), almost all forced moves and mates.
// A level first runs the plain search (no margin, no noise) at its depth and nodes, and plays its move when it finds a
// forced mate, so a margin never costs a mate (search.js); the margin pass then has its own node limit.
// Strength in human terms (catalog/levels.json, each about 60 either way): about 910, 1080, 1280, 1600, 1820,
// 2040, 2150 and 2290 for levels 1 to 8, the Maia 3 setting each scored 50% against in 150 games; Maia cannot
// tell depth 4 from depth 5 well, so the step from 6 to 7 rests on games between the levels.

import { Position } from "./board.js";
import { Searcher, mix32 } from "./search.js";

export const CHESS_LEVELS = [
	{ id: "chess-1", level: 1, depth: 2, nodes: 20000, margin: 200, noise: 200 },
	{ id: "chess-2", level: 2, depth: 2, nodes: 20000, margin: 100, noise: 100 },
	{ id: "chess-3", level: 3, depth: 3, nodes: 20000, margin: 150, noise: 150 },
	{ id: "chess-4", level: 4, depth: 3, nodes: 20000, margin: 70, noise: 70 },
	{ id: "chess-5", level: 5, depth: 4, nodes: 60000, margin: 90, noise: 90 },
	{ id: "chess-6", level: 6, depth: 4, nodes: 20000, margin: 20, noise: 20 },
	{ id: "chess-7", level: 7, depth: 5, nodes: 100000, margin: 60, noise: 60 },
	{ id: "chess-8", level: 8, depth: 5, nodes: 100000, margin: 15, noise: 15 },
];

// A level by number (1 to 8) or as an object: { level } picks a listed one; { depth, nodes, margin, noise } is
// used as given.
export function levelOf(level) {
	if (typeof level === "number") return CHESS_LEVELS[Math.max(1, Math.min(8, level | 0)) - 1];
	if (level && typeof level.level === "number" && level.depth === undefined) return levelOf(level.level);
	return { depth: 64, nodes: 250000, margin: 0, noise: 0, ...level };
}

// The salt for one move: the seed and the ply mixed into 32 bits.
export const moveSalt = (seed, ply) => mix32(((seed >>> 0) ^ Math.imul(ply + 1, 0x9e3779b1)) >>> 0);

let shared = null;
const searcher = () => (shared ||= new Searcher(18));

// The board for a state, with every earlier position on its history so repetitions are seen.
export function positionOf(s) {
	const p = new Position();
	if (!p.setFen(s.start)) throw new Error("bad start position");
	for (const text of s.moves) {
		const m = p.parseUci(text);
		if (!m) throw new Error(`illegal move in history: ${text}`);
		p.make(m);
	}
	// Keep only the history since the last capture or pawn move, which is all repetition can reach.
	if (p.sp > p.halfmove) {
		const drop = p.sp - p.halfmove;
		p.histLo.copyWithin(0, drop, p.sp + 1);
		p.histHi.copyWithin(0, drop, p.sp + 1);
		p.sp = p.halfmove;
	}
	return p;
}

// The computer's move at a level, in UCI text, or null if there is none (the game is over by the board).
export function computerMove(s, level, seed) {
	return think(s, level, seed).uci;
}

// The full result of the computer's search: { uci, score (centipawns, for the side to move), depth, nodes, pv }.
export function think(s, level, seed = 0, onDepth = null) {
	const L = levelOf(level);
	const p = positionOf(s);
	const r = searcher().search(p, { depth: L.depth, nodes: L.nodes, margin: L.margin, noise: L.noise, salt: moveSalt(seed, s.ply), onDepth });
	return r;
}
