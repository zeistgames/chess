// The Zeist chess search. Pure: no clocks, no Math.random, integers only, so the same position, limits and salt
// give the same move on every platform. Limits are a depth and a node count; nothing depends on time.
//
// Iterative deepening principal-variation alpha-beta with aspiration windows, a fixed-size transposition table
// (cleared before every search, so a search depends only on its position and history), quiescence search over
// captures and queen promotions with static exchange pruning, check extension, null-move pruning, reverse
// futility and futility pruning, late-move pruning and reductions, and move ordering by the table move, captures
// by static exchange, killer moves, counter moves and history.

import { PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING, N_OFF, K_OFF, B_OFF, R_OFF, FLAG_EP, moveUci } from "./board.js";
import { evaluate } from "./eval.js";

export const MATE = 30000;
const INF = 32000;
const MATE_BOUND = MATE - 1000;
const MAX_PLY = 96;
const SEE_VALUE = [0, 100, 325, 325, 500, 975, 20000]; // minor pieces equal, so trading one for the other is not a loss
const ABORT = { abort: true };

const BOUND_UPPER = 1, BOUND_LOWER = 2, BOUND_EXACT = 3;

// Late-move reductions, from integer logarithms (quarters of a bit) so no floating-point function is involved.
const lg4 = (x) => {
	let k = 0;
	const x4 = x * x * x * x;
	while (k < 30 && x4 >= 2 ** (k + 1)) k++;
	return k;
};
const LMR = new Int8Array(64 * 64);
for (let d = 1; d < 64; d++) for (let m = 1; m < 64; m++) LMR[d * 64 + m] = ((lg4(d) * lg4(m) + 56) / 75) | 0;

// MurmurHash3's 32-bit finalizer, for turning a salt and a move into an even spread of bits.
export function mix32(h) {
	h ^= h >>> 16;
	h = Math.imul(h, 0x85ebca6b);
	h ^= h >>> 13;
	h = Math.imul(h, 0xc2b2ae35);
	h ^= h >>> 16;
	return h >>> 0;
}

export class Searcher {
	constructor(ttBits = 18) {
		this.ttSize = 1 << ttBits;
		this.ttMask = this.ttSize - 1;
		this.ttKey = new Int32Array(this.ttSize);
		this.ttMove = new Int32Array(this.ttSize);
		this.ttScore = new Int16Array(this.ttSize);
		this.ttDepth = new Int8Array(this.ttSize);
		this.ttFlag = new Int8Array(this.ttSize);
		this.moves = new Int32Array(MAX_PLY * 256);
		this.scores = new Int32Array(MAX_PLY * 256);
		this.killers = new Int32Array(MAX_PLY * 2);
		this.history = new Int32Array(2 * 128 * 128);
		this.counter = new Int32Array(16 * 128);
		this.evals = new Int16Array(MAX_PLY);
		this.pv = new Int32Array(MAX_PLY * MAX_PLY);
		this.pvLen = new Int32Array(MAX_PLY);
		this.prevMove = new Int32Array(MAX_PLY);
		// Static evaluations by position key, so a position met again in the same search is not evaluated twice.
		this.evSize = 1 << 16;
		this.evLo = new Int32Array(this.evSize);
		this.evHi = new Int32Array(this.evSize);
		this.evVal = new Int16Array(this.evSize);
		this.evSet = new Uint8Array(this.evSize);
	}

	evaluate(p) {
		const i = p.lo & (this.evSize - 1);
		if (this.evSet[i] && this.evHi[i] === p.hi && this.evLo[i] === p.lo) return this.evVal[i];
		const v = evaluate(p);
		this.evSet[i] = 1;
		this.evLo[i] = p.lo;
		this.evHi[i] = p.hi;
		this.evVal[i] = v;
		return v;
	}

	clear() {
		this.ttKey.fill(0);
		this.ttMove.fill(0);
		this.ttScore.fill(0);
		this.ttDepth.fill(0);
		this.ttFlag.fill(0);
		this.killers.fill(0);
		this.history.fill(0);
		this.counter.fill(0);
		this.evSet.fill(0);
	}

	// Searches p (which is left as it was). limits: depth (plies, up to 64), nodes, margin and noise (centipawns,
	// for the levels: choose among moves within margin of the best, by score plus noise drawn from salt), salt.
	// Returns { move, uci, score, depth, nodes, pv, info } where info lists one line per finished depth.
	search(p, { depth = 64, nodes = 1e7, margin = 0, noise = 0, salt = 0, onDepth = null, plainFirst = true } = {}) {
		if (plainFirst && (margin > 0 || noise > 0)) {
			// A margin widens the root's scout windows, and a scout can then fail low on a mating move that the plain
			// search, with its own windows, proves (2026-11-15: level 8 missed a mate in two). So the plain search runs
			// first, with the same depth and nodes; when it finds a forced mate, its move is played. Otherwise the margin
			// pass runs from a cleared table, exactly as it would alone. The node count is both passes'.
			// On a copy: a search stopped by its node limit leaves its board mid-line.
			const plain = this.search(p.clone(), { depth, nodes });
			if (plain.score >= MATE_BOUND) return plain;
			const r = this.search(p, { depth, nodes, margin, noise, salt, onDepth, plainFirst: false });
			r.nodes += plain.nodes;
			return r;
		}
		this.clear();
		this.pos = p;
		this.nodes = 0;
		this.maxNodes = nodes;
		this.rootSp = p.sp;
		const root = p.legalMoves();
		if (root.length === 0) return { move: 0, uci: null, score: p.inCheck() ? -MATE : 0, depth: 0, nodes: 0, pv: [], info: [] };
		const n = root.length;
		const rootMoves = new Int32Array(root);
		const rootScores = new Int32Array(n);
		const exact = new Uint8Array(n);
		let done = { scores: null, exact: null, moves: null, depth: 0, best: rootMoves[0], score: 0, pv: [moveUci(rootMoves[0])] };
		const info = [];
		const maxDepth = Math.max(1, Math.min(64, depth));
		let prevScore = 0;
		try {
			for (let d = 1; d <= maxDepth; d++) {
				let alpha = -INF, beta = INF, delta = 30;
				if (d >= 4 && margin === 0 && Math.abs(prevScore) < MATE_BOUND) {
					alpha = prevScore - delta;
					beta = prevScore + delta;
				}
				let score;
				for (;;) {
					score = this.root(rootMoves, rootScores, exact, n, d, alpha, beta, margin);
					if (score <= alpha) {
						alpha = Math.max(-INF, alpha - delta);
						delta *= 2;
					} else if (score >= beta) {
						beta = Math.min(INF, beta + delta);
						delta *= 2;
					} else break;
					if (delta > 600) {
						alpha = -INF;
						beta = INF;
					}
				}
				// Order the root moves by score for the next depth: a stable insertion sort.
				for (let i = 1; i < n; i++) {
					const m = rootMoves[i], s = rootScores[i], e = exact[i];
					let j = i - 1;
					while (j >= 0 && rootScores[j] < s) {
						rootMoves[j + 1] = rootMoves[j];
						rootScores[j + 1] = rootScores[j];
						exact[j + 1] = exact[j];
						j--;
					}
					rootMoves[j + 1] = m;
					rootScores[j + 1] = s;
					exact[j + 1] = e;
				}
				prevScore = score;
				const pv = [];
				for (let i = 0; i < this.pvLen[0]; i++) pv.push(moveUci(this.pv[i]));
				if (pv[0] !== moveUci(rootMoves[0])) pv.splice(0, pv.length, moveUci(rootMoves[0]));
				done = { scores: rootScores.slice(), exact: exact.slice(), moves: rootMoves.slice(), depth: d, best: rootMoves[0], score: rootScores[0], pv };
				const line = { depth: d, score: rootScores[0], nodes: this.nodes, pv };
				info.push(line);
				if (onDepth) onDepth(line);
				if (Math.abs(score) >= MATE_BOUND && d >= 2 && MATE - Math.abs(score) < d) break; // a mate found within the depth
				if (n === 1 && d >= 2) break;
			}
		} catch (e) {
			if (e !== ABORT) throw e;
		}
		let best = done.best;
		if ((margin > 0 || noise > 0) && done.scores) {
			// Among the moves whose exact score is within margin of the best, take the highest score plus noise.
			const top = done.scores[0];
			let pick = -1, pickValue = -INF * 2;
			for (let i = 0; i < n; i++) {
				if (i > 0 && (!done.exact[i] || done.scores[i] < top - margin)) continue;
				const v = done.scores[i] + (noise ? mix32(salt ^ Math.imul(done.moves[i], 0x9e3779b1)) % (noise + 1) : 0);
				if (v > pickValue) {
					pickValue = v;
					pick = i;
				}
			}
			best = done.moves[pick];
		}
		const scoreOf = done.scores ? done.scores[done.moves.indexOf(best)] : 0;
		return { move: best, uci: moveUci(best), score: scoreOf, depth: done.depth, nodes: this.nodes, pv: best === done.best ? done.pv : [moveUci(best)], info };
	}

	root(moves, scores, exact, n, depth, alpha, beta, margin) {
		const p = this.pos;
		const alpha0 = alpha;
		let best = -INF;
		this.pvLen[0] = 0;
		for (let i = 0; i < n; i++) {
			const m = moves[i];
			p.make(m);
			this.prevMove[1] = m;
			let s;
			if (i === 0) s = -this.negamax(depth - 1, -beta, -alpha0, 1, true, true);
			else {
				const lim = Math.max(alpha0, best - margin);
				s = -this.negamax(depth - 1, -lim - 1, -lim, 1, false, true);
				if (s > lim && s < beta) s = -this.negamax(depth - 1, -beta, -lim, 1, true, true);
				exact[i] = s > lim && s < beta ? 1 : 0;
			}
			if (i === 0) exact[0] = s > alpha0 && s < beta ? 1 : 0;
			p.unmake();
			scores[i] = s;
			if (s > best) {
				best = s;
				this.pv[0] = m;
				for (let k = 1; k < this.pvLen[1]; k++) this.pv[k] = this.pv[MAX_PLY + k];
				this.pvLen[0] = Math.max(1, this.pvLen[1]);
			}
			if (s >= beta) {
				for (let k = i + 1; k < n; k++) {
					scores[k] = -INF;
					exact[k] = 0;
				}
				break;
			}
		}
		return best;
	}

	negamax(depth, alpha, beta, ply, isPv, allowNull) {
		const p = this.pos;
		this.pvLen[ply] = ply;
		if (ply >= MAX_PLY - 1) return this.evaluate(p);
		if (++this.nodes > this.maxNodes) throw ABORT;
		if (p.halfmove >= 100 || p.repeated(this.rootSp) || p.insufficient()) return 0;
		// Mate distance pruning.
		const mAlpha = Math.max(alpha, -MATE + ply), mBeta = Math.min(beta, MATE - ply - 1);
		if (mAlpha >= mBeta) return mAlpha;
		const inCheck = p.inCheck();
		if (inCheck) depth++;
		if (depth <= 0) {
			this.nodes--;
			return this.quiesce(alpha, beta, ply);
		}

		const slot = p.lo & this.ttMask;
		let ttMove = 0;
		if (this.ttKey[slot] === p.hi && this.ttFlag[slot]) {
			ttMove = this.ttMove[slot];
			if (!isPv && this.ttDepth[slot] >= depth) {
				let s = this.ttScore[slot];
				if (s > MATE_BOUND) s -= ply;
				else if (s < -MATE_BOUND) s += ply;
				const f = this.ttFlag[slot];
				if (f === BOUND_EXACT || (f === BOUND_LOWER && s >= beta) || (f === BOUND_UPPER && s <= alpha)) return s;
			}
		}

		const staticEval = inCheck ? -INF : this.evaluate(p);
		this.evals[ply] = staticEval;
		const improving = !inCheck && ply >= 2 && staticEval > this.evals[ply - 2];

		if (!isPv && !inCheck) {
			// Reverse futility: far enough above beta that a quiet move will not bring it back.
			if (depth <= 6 && staticEval - 80 * depth + (improving ? 30 : 0) >= beta && Math.abs(beta) < MATE_BOUND) return staticEval;
			// Null move: if passing still holds beta, a real move will too. Not with only king and pawns (zugzwang).
			if (allowNull && depth >= 3 && staticEval >= beta && this.hasPieces(p.side)) {
				const r = 3 + ((depth / 6) | 0) + Math.min(2, ((staticEval - beta) / 200) | 0);
				p.makeNull();
				this.prevMove[ply + 1] = 0;
				const s = -this.negamax(depth - 1 - r, -beta, -beta + 1, ply + 1, false, false);
				p.unmakeNull();
				if (s >= beta) return s >= MATE_BOUND ? beta : s;
			}
		}

		// Internal iterative reduction: without a table move, a deep node is searched a ply shallower.
		if (!ttMove && depth >= 5) depth--;

		const base = ply * 256;
		const n = p.gen(this.moves, base, true);
		this.scoreMoves(base, n, ttMove, ply, false);
		const alpha0 = alpha;
		let best = -INF, bestMove = 0, legal = 0, quietsTried = 0;
		const futile = !isPv && !inCheck && depth <= 3 && staticEval + 90 + 100 * depth <= alpha;
		const lmpLimit = 3 + depth * depth * (improving ? 2 : 1);
		const prev = this.prevMove[ply];
		for (let i = base; i < n; i++) {
			const m = this.pick(i, n);
			const quiet = this.isQuiet(m);
			if (legal > 0 && quiet && !inCheck && best > -MATE_BOUND) {
				if (futile) continue;
				if (!isPv && depth <= 4 && quietsTried >= lmpLimit) continue;
			}
			if (!p.make(m)) {
				p.unmake();
				continue;
			}
			legal++;
			if (quiet) quietsTried++;
			this.prevMove[ply + 1] = m;
			const givesCheck = p.inCheck();
			let s;
			if (legal === 1) s = -this.negamax(depth - 1, -beta, -alpha, ply + 1, isPv, true);
			else {
				let r = 0;
				if (depth >= 3 && quiet && !inCheck && !givesCheck && legal > (isPv ? 3 : 2)) {
					r = LMR[Math.min(depth, 63) * 64 + Math.min(legal, 63)];
					if (isPv) r--;
					if (!improving) r++;
					if (m === this.killers[ply * 2] || m === this.killers[ply * 2 + 1]) r--;
					const h = this.history[(p.side ^ 1) * 16384 + (m & 16383)];
					if (h > 4000) r--;
					else if (h < -4000) r++;
					if (r < 0) r = 0;
					if (r > depth - 2) r = depth - 2;
				}
				s = -this.negamax(depth - 1 - r, -alpha - 1, -alpha, ply + 1, false, true);
				if (r > 0 && s > alpha) s = -this.negamax(depth - 1, -alpha - 1, -alpha, ply + 1, false, true);
				if (isPv && s > alpha && s < beta) s = -this.negamax(depth - 1, -beta, -alpha, ply + 1, true, true);
			}
			p.unmake();
			if (s > best) {
				best = s;
				bestMove = m;
				if (s > alpha) {
					alpha = s;
					if (isPv) {
						const row = ply * MAX_PLY, next = (ply + 1) * MAX_PLY;
						this.pv[row + ply] = m;
						for (let k = ply + 1; k < this.pvLen[ply + 1]; k++) this.pv[row + k] = this.pv[next + k];
						this.pvLen[ply] = this.pvLen[ply + 1];
					}
					if (s >= beta) {
						if (quiet) this.reward(m, ply, depth, prev, base, i);
						break;
					}
				}
			}
		}
		if (legal === 0) return inCheck ? -MATE + ply : 0;

		const flag = best >= beta ? BOUND_LOWER : best > alpha0 ? BOUND_EXACT : BOUND_UPPER;
		this.ttKey[slot] = p.hi;
		this.ttMove[slot] = bestMove;
		this.ttScore[slot] = best > MATE_BOUND ? best + ply : best < -MATE_BOUND ? best - ply : best;
		this.ttDepth[slot] = depth;
		this.ttFlag[slot] = flag;
		return best;
	}

	quiesce(alpha, beta, ply) {
		const p = this.pos;
		if (++this.nodes > this.maxNodes) throw ABORT;
		if (ply >= MAX_PLY - 1) return this.evaluate(p);
		const inCheck = p.inCheck();
		let best;
		if (inCheck) best = -MATE + ply;
		else {
			best = this.evaluate(p);
			if (best >= beta) return best;
			if (best + 1100 < alpha) return best; // even a queen would not help
			if (best > alpha) alpha = best;
		}
		const base = ply * 256;
		const n = p.gen(this.moves, base, inCheck);
		this.scoreMoves(base, n, 0, ply, true);
		const stand = best;
		for (let i = base; i < n; i++) {
			const m = this.pick(i, n);
			if (!inCheck) {
				const victim = m >> 17 === FLAG_EP ? PAWN : p.board[(m >> 7) & 127] & 7;
				if (!((m >> 14) & 7) && stand + SEE_VALUE[victim] + 150 <= alpha) continue;
				if (this.scores[i] < 0) continue; // loses material by exchange
			}
			if (!p.make(m)) {
				p.unmake();
				continue;
			}
			const s = -this.quiesce(-beta, -alpha, ply + 1);
			p.unmake();
			if (s > best) {
				best = s;
				if (s > alpha) {
					alpha = s;
					if (s >= beta) break;
				}
			}
		}
		return best;
	}

	hasPieces(side) {
		const c = this.pos.count, o = side << 3;
		return c[KNIGHT | o] + c[BISHOP | o] + c[ROOK | o] + c[QUEEN | o] > 0;
	}

	isQuiet(m) {
		return !this.pos.board[(m >> 7) & 127] && !((m >> 14) & 7) && m >> 17 !== FLAG_EP;
	}

	// Move scores: table move first, then winning and even captures and queen promotions by victim and attacker,
	// then killers, the counter move, quiet moves by history, and captures that lose material last.
	scoreMoves(base, n, ttMove, ply, captures) {
		const p = this.pos, b = p.board, sc = this.scores, mv = this.moves;
		const k1 = this.killers[ply * 2], k2 = this.killers[ply * 2 + 1];
		const prev = this.prevMove[ply];
		const cm = prev ? this.counter[b[(prev >> 7) & 127] * 128 + ((prev >> 7) & 127)] : 0;
		const hist = p.side * 16384;
		for (let i = base; i < n; i++) {
			const m = mv[i];
			if (m === ttMove) {
				sc[i] = 1 << 30;
				continue;
			}
			const to = (m >> 7) & 127, promo = (m >> 14) & 7;
			const victim = m >> 17 === FLAG_EP ? PAWN : b[to] & 7;
			if (victim || promo) {
				const attacker = b[m & 127] & 7;
				let s = 1 << 26;
				s += SEE_VALUE[victim] * 16 - attacker + (promo === QUEEN ? 9000 : 0);
				if (promo && promo !== QUEEN) s = -(1 << 26) + promo;
				else if (victim && SEE_VALUE[attacker] > SEE_VALUE[victim] && this.see(m) < 0) s = captures ? -1 : -(1 << 25) + SEE_VALUE[victim];
				sc[i] = s;
			} else if (m === k1) sc[i] = 1 << 24;
			else if (m === k2) sc[i] = (1 << 24) - 1;
			else if (m === cm) sc[i] = (1 << 24) - 2;
			else sc[i] = this.history[hist + (m & 16383)];
		}
	}

	pick(i, n) {
		const sc = this.scores, mv = this.moves;
		let bi = i, bs = sc[i];
		for (let j = i + 1; j < n; j++) {
			if (sc[j] > bs) {
				bs = sc[j];
				bi = j;
			}
		}
		if (bi !== i) {
			const t = mv[i];
			mv[i] = mv[bi];
			mv[bi] = t;
			sc[bi] = sc[i];
			sc[i] = bs;
		}
		return mv[i];
	}

	// A quiet move that caused a cutoff: a killer, the counter move to the last move, and more history; the quiet
	// moves tried before it get less.
	reward(m, ply, depth, prev, base, at) {
		const k = ply * 2;
		if (this.killers[k] !== m) {
			this.killers[k + 1] = this.killers[k];
			this.killers[k] = m;
		}
		const p = this.pos;
		if (prev) this.counter[p.board[(prev >> 7) & 127] * 128 + ((prev >> 7) & 127)] = m;
		const bonus = Math.min(1600, depth * depth * 16);
		const h = this.history, side = p.side * 16384;
		const add = (mm, b) => {
			const idx = side + (mm & 16383);
			h[idx] += b - ((h[idx] * Math.abs(b)) / 16384) | 0;
		};
		add(m, bonus);
		for (let j = base; j < at; j++) {
			const o = this.moves[j];
			if (o !== m && this.isQuiet(o)) add(o, -bonus);
		}
	}

	// Static exchange: the material won or lost by a capture after every recapture on its square, least valuable
	// piece first. The board is restored before returning.
	see(m) {
		const b = this.pos.board;
		const from = m & 127, to = (m >> 7) & 127;
		const gain = this.seeGain;
		const removed = this.seeRemoved;
		let nr = 0;
		let side = this.pos.side;
		let depth = 0;
		gain[0] = SEE_VALUE[b[to] & 7];
		let attackerSq = from;
		let attackerValue = SEE_VALUE[b[from] & 7];
		for (;;) {
			depth++;
			gain[depth] = attackerValue - gain[depth - 1];
			removed[nr++] = attackerSq;
			removed[nr++] = b[attackerSq];
			b[attackerSq] = 0;
			side ^= 1;
			if (Math.max(-gain[depth - 1], gain[depth]) < 0) break;
			attackerSq = this.leastAttacker(to, side);
			if (attackerSq < 0) break;
			attackerValue = SEE_VALUE[b[attackerSq] & 7];
		}
		for (let i = nr - 2; i >= 0; i -= 2) b[removed[i]] = removed[i + 1];
		while (--depth) gain[depth - 1] = -Math.max(-gain[depth - 1], gain[depth]);
		return gain[0];
	}

	leastAttacker(sq, side) {
		const b = this.pos.board, c = side << 3;
		const pawn = PAWN | c;
		if (side === 0) {
			if (!((sq - 15) & 0x88) && b[sq - 15] === pawn) return sq - 15;
			if (!((sq - 17) & 0x88) && b[sq - 17] === pawn) return sq - 17;
		} else {
			if (!((sq + 15) & 0x88) && b[sq + 15] === pawn) return sq + 15;
			if (!((sq + 17) & 0x88) && b[sq + 17] === pawn) return sq + 17;
		}
		for (let i = 0; i < 8; i++) {
			const t = sq + N_OFF[i];
			if (!(t & 0x88) && b[t] === (KNIGHT | c)) return t;
		}
		let bestSq = -1, bestType = 7;
		for (let i = 0; i < 8; i++) {
			const o = i < 4 ? B_OFF[i] : R_OFF[i - 4];
			let t = sq + o;
			while (!(t & 0x88)) {
				const v = b[t];
				if (v) {
					if (v >> 3 === side) {
						const ty = v & 7;
						const ok = ty === QUEEN || (i < 4 ? ty === BISHOP : ty === ROOK);
						if (ok && ty < bestType) {
							bestType = ty;
							bestSq = t;
						}
					}
					break;
				}
				t += o;
			}
		}
		if (bestSq >= 0) return bestSq;
		for (let i = 0; i < 8; i++) {
			const t = sq + K_OFF[i];
			if (!(t & 0x88) && b[t] === (KING | c)) return t;
		}
		return -1;
	}
}

Searcher.prototype.seeGain = new Int32Array(40);
Searcher.prototype.seeRemoved = new Int32Array(80);
