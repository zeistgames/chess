// The chess board for Zeist: position, move generation, making and taking back moves, FEN. Pure: no DOM or
// platform calls, integers only, no dependence on object iteration order. The rules (rules.js) and the computer
// (search.js) share it.
//
// Squares are 0x88: sq = rank * 16 + file, a1 = 0, h1 = 7, a8 = 112, h8 = 119; sq & 0x88 is nonzero off the board.
// A piece is type | color << 3: types 1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king; color 0 White, 1 Black.
// A move is an integer: from | to << 7 | promotion type << 14 | flag << 17, flag 0 plain, 1 double pawn push,
// 2 en passant, 3 castling.

import { PST_MG, PST_EG, PHASE_WEIGHT, PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING } from "./pst.js";

export { PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING };
export const WHITE = 0, BLACK = 1;
export const FLAG_DOUBLE = 1, FLAG_EP = 2, FLAG_CASTLE = 3;
export const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

export const N_OFF = [33, 31, 18, 14, -14, -18, -31, -33];
export const K_OFF = [17, 16, 15, 1, -1, -15, -16, -17];
export const B_OFF = [17, 15, -15, -17];
export const R_OFF = [16, 1, -1, -16];

export const moveFrom = (m) => m & 127;
export const moveTo = (m) => (m >> 7) & 127;
export const movePromo = (m) => (m >> 14) & 7;
export const moveFlag = (m) => m >> 17;
const mk = (from, to, promo, flag) => from | (to << 7) | (promo << 14) | (flag << 17);

const FILES = "abcdefgh";
export const sqName = (sq) => FILES[sq & 7] + ((sq >> 4) + 1);
export const sqParse = (s) => {
	const f = FILES.indexOf(s[0]);
	const r = s.charCodeAt(1) - 49;
	return f < 0 || r < 0 || r > 7 || s.length !== 2 ? -1 : r * 16 + f;
};
const PROMO_LETTER = ["", "", "n", "b", "r", "q", "", ""];
export function moveUci(m) {
	return sqName(moveFrom(m)) + sqName(moveTo(m)) + PROMO_LETTER[movePromo(m)];
}

// Zobrist keys: two 32-bit halves, drawn from a fixed xorshift32 stream, so every platform gets the same keys.
let zs = 0x2545f491;
function rand32() {
	zs ^= zs << 13;
	zs ^= zs >>> 17;
	zs ^= zs << 5;
	return zs | 0;
}
export const Z_LO = new Int32Array(16 * 128), Z_HI = new Int32Array(16 * 128);
for (let i = 0; i < 16 * 128; i++) {
	Z_LO[i] = rand32();
	Z_HI[i] = rand32();
}
const ZC_LO = new Int32Array(16), ZC_HI = new Int32Array(16);
for (let i = 0; i < 16; i++) {
	ZC_LO[i] = rand32();
	ZC_HI[i] = rand32();
}
const ZE_LO = new Int32Array(8), ZE_HI = new Int32Array(8);
for (let i = 0; i < 8; i++) {
	ZE_LO[i] = rand32();
	ZE_HI[i] = rand32();
}
const ZS_LO = rand32(), ZS_HI = rand32();

// Castling rights: 1 White short, 2 White long, 4 Black short, 8 Black long. A move from or to a square keeps
// only the rights in its mask.
const CASTLE_MASK = new Int8Array(128).fill(15);
CASTLE_MASK[0] = 15 & ~2;
CASTLE_MASK[7] = 15 & ~1;
CASTLE_MASK[4] = 15 & ~3;
CASTLE_MASK[112] = 15 & ~8;
CASTLE_MASK[119] = 15 & ~4;
CASTLE_MASK[116] = 15 & ~12;

// Chebyshev distance between two squares, looked up by their 0x88 difference.
export const DIST = new Int8Array(240);
for (let a = 0; a < 128; a++) {
	if (a & 0x88) continue;
	for (let b = 0; b < 128; b++) {
		if (b & 0x88) continue;
		DIST[a - b + 119] = Math.max(Math.abs((a & 7) - (b & 7)), Math.abs((a >> 4) - (b >> 4)));
	}
}
export const dist = (a, b) => DIST[a - b + 119];

const MAX_STACK = 4096; // plies of game plus search held at once

export class Position {
	constructor() {
		this.board = new Int8Array(128);
		this.side = WHITE;
		this.castle = 0;
		this.ep = -1; // en passant target square, set only when a pawn could take there
		this.halfmove = 0;
		this.fullmove = 1;
		this.king = new Int32Array(2);
		this.count = new Int8Array(16); // pieces on the board by piece code
		this.mg = 0; // material and square values, White minus Black
		this.eg = 0;
		this.phase = 0;
		this.lo = 0; // Zobrist key
		this.hi = 0;
		this.sp = 0; // stack height: positions since the root of the history
		this.histLo = new Int32Array(MAX_STACK);
		this.histHi = new Int32Array(MAX_STACK);
		this.uMove = new Int32Array(MAX_STACK);
		this.uCap = new Int8Array(MAX_STACK);
		this.uCastle = new Int8Array(MAX_STACK);
		this.uEp = new Int16Array(MAX_STACK);
		this.uHalf = new Int16Array(MAX_STACK);
		this.uMg = new Int32Array(MAX_STACK);
		this.uEg = new Int32Array(MAX_STACK);
		this.uPhase = new Int8Array(MAX_STACK);
		this.uLo = new Int32Array(MAX_STACK);
		this.uHi = new Int32Array(MAX_STACK);
	}

	clone() {
		const p = new Position();
		p.board.set(this.board);
		p.side = this.side;
		p.castle = this.castle;
		p.ep = this.ep;
		p.halfmove = this.halfmove;
		p.fullmove = this.fullmove;
		p.king.set(this.king);
		p.count.set(this.count);
		p.mg = this.mg;
		p.eg = this.eg;
		p.phase = this.phase;
		p.lo = this.lo;
		p.hi = this.hi;
		p.sp = this.sp;
		p.histLo.set(this.histLo);
		p.histHi.set(this.histHi);
		return p;
	}

	put(piece, sq) {
		this.board[sq] = piece;
		this.count[piece]++;
		this.mg += PST_MG[piece * 128 + sq];
		this.eg += PST_EG[piece * 128 + sq];
		this.phase += PHASE_WEIGHT[piece & 7];
		this.lo ^= Z_LO[piece * 128 + sq];
		this.hi ^= Z_HI[piece * 128 + sq];
		if ((piece & 7) === KING) this.king[piece >> 3] = sq;
	}

	// Sets the position from FEN. Returns false (and leaves a cleared board) if the FEN is not a legal position.
	setFen(fen) {
		this.board.fill(0);
		this.count.fill(0);
		this.mg = this.eg = this.phase = this.lo = this.hi = 0;
		this.sp = 0;
		this.ep = -1;
		this.castle = 0;
		if (typeof fen !== "string") return false;
		const parts = fen.trim().split(/\s+/);
		if (parts.length < 4 || parts.length > 6) return false;
		const rows = parts[0].split("/");
		if (rows.length !== 8) return false;
		for (let i = 0; i < 8; i++) {
			const rank = 7 - i;
			let f = 0;
			for (const ch of rows[i]) {
				if (ch >= "1" && ch <= "8") {
					f += ch.charCodeAt(0) - 48;
					continue;
				}
				const t = "pnbrqk".indexOf(ch.toLowerCase());
				if (t < 0 || f > 7) return false;
				this.put((t + 1) | (ch === ch.toLowerCase() ? 8 : 0), rank * 16 + f);
				f++;
			}
			if (f !== 8) return false;
		}
		if (this.count[KING] !== 1 || this.count[KING | 8] !== 1) return false;
		for (let f = 0; f < 8; f++) {
			const a = this.board[f] & 7, b = this.board[112 + f] & 7;
			if (a === PAWN || b === PAWN) return false;
		}
		if (parts[1] !== "w" && parts[1] !== "b") return false;
		this.side = parts[1] === "w" ? WHITE : BLACK;
		if (parts[2] !== "-") {
			if (!/^[KQkq]+$/.test(parts[2])) return false;
			for (const ch of parts[2]) this.castle |= { K: 1, Q: 2, k: 4, q: 8 }[ch];
		}
		// Keep only the rights the king and rook are still placed for.
		const b = this.board;
		if (b[4] !== (KING | 0)) this.castle &= ~3;
		if (b[7] !== (ROOK | 0)) this.castle &= ~1;
		if (b[0] !== (ROOK | 0)) this.castle &= ~2;
		if (b[116] !== (KING | 8)) this.castle &= ~12;
		if (b[119] !== (ROOK | 8)) this.castle &= ~4;
		if (b[112] !== (ROOK | 8)) this.castle &= ~8;
		this.lo ^= ZC_LO[this.castle];
		this.hi ^= ZC_HI[this.castle];
		if (parts[3] !== "-") {
			const e = sqParse(parts[3]);
			if (e < 0 || (e >> 4) !== (this.side === WHITE ? 5 : 2)) return false;
			this.setEp(e);
		}
		this.halfmove = parts.length > 4 ? Number(parts[4]) : 0;
		this.fullmove = parts.length > 5 ? Number(parts[5]) : 1;
		if (!Number.isInteger(this.halfmove) || this.halfmove < 0 || !Number.isInteger(this.fullmove) || this.fullmove < 1) return false;
		if (this.side === BLACK) {
			this.lo ^= ZS_LO;
			this.hi ^= ZS_HI;
		}
		// The side not to move may not be in check.
		if (this.attacked(this.king[this.side ^ 1], this.side)) return false;
		this.histLo[0] = this.lo;
		this.histHi[0] = this.hi;
		return true;
	}

	// Sets the en passant square only if a pawn of the side to move stands next to the pawn that just moved.
	setEp(e) {
		const pawnSq = this.side === WHITE ? e - 16 : e + 16;
		const mine = PAWN | (this.side << 3);
		const b = this.board;
		if (b[pawnSq] !== (PAWN | ((this.side ^ 1) << 3))) return;
		if ((!((pawnSq - 1) & 0x88) && b[pawnSq - 1] === mine) || (!((pawnSq + 1) & 0x88) && b[pawnSq + 1] === mine)) {
			this.ep = e;
			this.lo ^= ZE_LO[e & 7];
			this.hi ^= ZE_HI[e & 7];
		}
	}

	fen() {
		const b = this.board;
		let out = "";
		for (let rank = 7; rank >= 0; rank--) {
			let empty = 0;
			for (let f = 0; f < 8; f++) {
				const p = b[rank * 16 + f];
				if (!p) {
					empty++;
					continue;
				}
				if (empty) out += empty;
				empty = 0;
				const ch = " pnbrqk"[p & 7];
				out += p & 8 ? ch : ch.toUpperCase();
			}
			if (empty) out += empty;
			if (rank) out += "/";
		}
		let c = "";
		if (this.castle & 1) c += "K";
		if (this.castle & 2) c += "Q";
		if (this.castle & 4) c += "k";
		if (this.castle & 8) c += "q";
		return `${out} ${this.side === WHITE ? "w" : "b"} ${c || "-"} ${this.ep >= 0 ? sqName(this.ep) : "-"} ${this.halfmove} ${this.fullmove}`;
	}

	// Is sq attacked by a piece of color `by`?
	attacked(sq, by) {
		const b = this.board;
		const c = by << 3;
		if (by === WHITE) {
			if ((!((sq - 15) & 0x88) && b[sq - 15] === PAWN) || (!((sq - 17) & 0x88) && b[sq - 17] === PAWN)) return true;
		} else {
			if ((!((sq + 15) & 0x88) && b[sq + 15] === (PAWN | 8)) || (!((sq + 17) & 0x88) && b[sq + 17] === (PAWN | 8))) return true;
		}
		const kn = KNIGHT | c;
		for (let i = 0; i < 8; i++) {
			const t = sq + N_OFF[i];
			if (!(t & 0x88) && b[t] === kn) return true;
		}
		const kg = KING | c;
		for (let i = 0; i < 8; i++) {
			const t = sq + K_OFF[i];
			if (!(t & 0x88) && b[t] === kg) return true;
		}
		const bi = BISHOP | c, qu = QUEEN | c, ro = ROOK | c;
		for (let i = 0; i < 4; i++) {
			const o = B_OFF[i];
			let t = sq + o;
			while (!(t & 0x88)) {
				const p = b[t];
				if (p) {
					if (p === bi || p === qu) return true;
					break;
				}
				t += o;
			}
		}
		for (let i = 0; i < 4; i++) {
			const o = R_OFF[i];
			let t = sq + o;
			while (!(t & 0x88)) {
				const p = b[t];
				if (p) {
					if (p === ro || p === qu) return true;
					break;
				}
				t += o;
			}
		}
		return false;
	}

	inCheck() {
		return this.attacked(this.king[this.side], this.side ^ 1);
	}

	// Writes pseudo-legal moves into list from index n and returns the new end. With all false: only captures and
	// queen promotions (for the quiescence search).
	gen(list, n, all) {
		const b = this.board;
		const us = this.side, them = us ^ 1;
		for (let sq = 0; sq < 128; sq++) {
			if (sq & 8) {
				sq += 7;
				continue;
			}
			const p = b[sq];
			if (!p || p >> 3 !== us) continue;
			const type = p & 7;
			if (type === PAWN) {
				const fwd = us === WHITE ? 16 : -16;
				const rank = sq >> 4;
				const last = rank === (us === WHITE ? 6 : 1);
				const t = sq + fwd;
				if (b[t] === 0) {
					if (last) {
						list[n++] = mk(sq, t, QUEEN, 0);
						if (all) {
							list[n++] = mk(sq, t, KNIGHT, 0);
							list[n++] = mk(sq, t, ROOK, 0);
							list[n++] = mk(sq, t, BISHOP, 0);
						}
					} else if (all) {
						list[n++] = mk(sq, t, 0, 0);
						if (rank === (us === WHITE ? 1 : 6) && b[t + fwd] === 0) list[n++] = mk(sq, t + fwd, 0, FLAG_DOUBLE);
					}
				}
				for (let k = -1; k <= 1; k += 2) {
					const c = t + k;
					if (c & 0x88) continue;
					const q = b[c];
					if (q && q >> 3 === them) {
						if (last) {
							list[n++] = mk(sq, c, QUEEN, 0);
							if (all) {
								list[n++] = mk(sq, c, KNIGHT, 0);
								list[n++] = mk(sq, c, ROOK, 0);
								list[n++] = mk(sq, c, BISHOP, 0);
							}
						} else list[n++] = mk(sq, c, 0, 0);
					} else if (c === this.ep) list[n++] = mk(sq, c, 0, FLAG_EP);
				}
			} else if (type === KNIGHT || type === KING) {
				const offs = type === KNIGHT ? N_OFF : K_OFF;
				for (let i = 0; i < 8; i++) {
					const t = sq + offs[i];
					if (t & 0x88) continue;
					const q = b[t];
					if (q === 0) {
						if (all) list[n++] = mk(sq, t, 0, 0);
					} else if (q >> 3 === them) list[n++] = mk(sq, t, 0, 0);
				}
				if (type === KING && all && this.castle) n = this.genCastles(list, n, sq);
			} else {
				const start = type === ROOK ? 4 : 0;
				const end = type === BISHOP ? 4 : 8;
				for (let i = start; i < end; i++) {
					const o = i < 4 ? B_OFF[i] : R_OFF[i - 4];
					let t = sq + o;
					while (!(t & 0x88)) {
						const q = b[t];
						if (q === 0) {
							if (all) list[n++] = mk(sq, t, 0, 0);
						} else {
							if (q >> 3 === them) list[n++] = mk(sq, t, 0, 0);
							break;
						}
						t += o;
					}
				}
			}
		}
		return n;
	}

	genCastles(list, n, k) {
		const b = this.board;
		const them = this.side ^ 1;
		if (this.side === WHITE) {
			if (k !== 4) return n;
			if (this.castle & 1 && b[5] === 0 && b[6] === 0 && b[7] === ROOK && !this.attacked(4, them) && !this.attacked(5, them) && !this.attacked(6, them))
				list[n++] = mk(4, 6, 0, FLAG_CASTLE);
			if (this.castle & 2 && b[3] === 0 && b[2] === 0 && b[1] === 0 && b[0] === ROOK && !this.attacked(4, them) && !this.attacked(3, them) && !this.attacked(2, them))
				list[n++] = mk(4, 2, 0, FLAG_CASTLE);
		} else {
			if (k !== 116) return n;
			if (this.castle & 4 && b[117] === 0 && b[118] === 0 && b[119] === (ROOK | 8) && !this.attacked(116, them) && !this.attacked(117, them) && !this.attacked(118, them))
				list[n++] = mk(116, 118, 0, FLAG_CASTLE);
			if (this.castle & 8 && b[115] === 0 && b[114] === 0 && b[113] === 0 && b[112] === (ROOK | 8) && !this.attacked(116, them) && !this.attacked(115, them) && !this.attacked(114, them))
				list[n++] = mk(116, 114, 0, FLAG_CASTLE);
		}
		return n;
	}

	move(piece, from, to) {
		const i = piece * 128;
		this.board[to] = piece;
		this.board[from] = 0;
		this.mg += PST_MG[i + to] - PST_MG[i + from];
		this.eg += PST_EG[i + to] - PST_EG[i + from];
		this.lo ^= Z_LO[i + from] ^ Z_LO[i + to];
		this.hi ^= Z_HI[i + from] ^ Z_HI[i + to];
	}

	remove(piece, sq) {
		const i = piece * 128 + sq;
		this.board[sq] = 0;
		this.count[piece]--;
		this.mg -= PST_MG[i];
		this.eg -= PST_EG[i];
		this.phase -= PHASE_WEIGHT[piece & 7];
		this.lo ^= Z_LO[i];
		this.hi ^= Z_HI[i];
	}

	// Makes a pseudo-legal move. Returns false if it leaves the mover's king in check; take it back with unmake()
	// either way.
	make(m) {
		const b = this.board;
		const from = m & 127, to = (m >> 7) & 127, promo = (m >> 14) & 7, flag = m >> 17;
		const us = this.side;
		const p = b[from];
		const sp = this.sp;
		this.uMove[sp] = m;
		this.uCastle[sp] = this.castle;
		this.uEp[sp] = this.ep;
		this.uHalf[sp] = this.halfmove;
		this.uMg[sp] = this.mg;
		this.uEg[sp] = this.eg;
		this.uPhase[sp] = this.phase;
		this.uLo[sp] = this.lo;
		this.uHi[sp] = this.hi;
		let cap;
		if (flag === FLAG_EP) {
			const cs = us === WHITE ? to - 16 : to + 16;
			cap = b[cs];
			this.remove(cap, cs);
		} else {
			cap = b[to];
			if (cap) this.remove(cap, to);
		}
		this.uCap[sp] = cap;
		this.move(p, from, to);
		if (promo) {
			this.remove(p, to);
			this.put(promo | (us << 3), to);
		}
		if ((p & 7) === KING) {
			this.king[us] = to;
			if (flag === FLAG_CASTLE) {
				const rook = ROOK | (us << 3);
				if (to > from) this.move(rook, from + 3, from + 1);
				else this.move(rook, from - 4, from - 1);
			}
		}
		const nc = this.castle & CASTLE_MASK[from] & CASTLE_MASK[to];
		if (nc !== this.castle) {
			this.lo ^= ZC_LO[this.castle] ^ ZC_LO[nc];
			this.hi ^= ZC_HI[this.castle] ^ ZC_HI[nc];
			this.castle = nc;
		}
		if (this.ep >= 0) {
			this.lo ^= ZE_LO[this.ep & 7];
			this.hi ^= ZE_HI[this.ep & 7];
			this.ep = -1;
		}
		this.halfmove = cap || (p & 7) === PAWN ? 0 : this.halfmove + 1;
		if (us === BLACK) this.fullmove++;
		this.side = us ^ 1;
		this.lo ^= ZS_LO;
		this.hi ^= ZS_HI;
		if (flag === FLAG_DOUBLE) this.setEp((from + to) >> 1);
		this.sp = sp + 1;
		this.histLo[sp + 1] = this.lo;
		this.histHi[sp + 1] = this.hi;
		return !this.attacked(this.king[us], us ^ 1);
	}

	unmake() {
		const sp = --this.sp;
		const m = this.uMove[sp];
		const from = m & 127, to = (m >> 7) & 127, promo = (m >> 14) & 7, flag = m >> 17;
		const b = this.board;
		const us = this.side ^ 1;
		this.side = us;
		let p = b[to];
		if (promo) {
			this.count[p]--;
			p = PAWN | (us << 3);
			this.count[p]++;
		}
		b[from] = p;
		b[to] = 0;
		if ((p & 7) === KING) {
			this.king[us] = from;
			if (flag === FLAG_CASTLE) {
				const rook = ROOK | (us << 3);
				if (to > from) {
					b[from + 3] = rook;
					b[from + 1] = 0;
				} else {
					b[from - 4] = rook;
					b[from - 1] = 0;
				}
			}
		}
		const cap = this.uCap[sp];
		if (cap) {
			const cs = flag === FLAG_EP ? (us === WHITE ? to - 16 : to + 16) : to;
			b[cs] = cap;
			this.count[cap]++;
		}
		if (us === BLACK) this.fullmove--;
		this.castle = this.uCastle[sp];
		this.ep = this.uEp[sp];
		this.halfmove = this.uHalf[sp];
		this.mg = this.uMg[sp];
		this.eg = this.uEg[sp];
		this.phase = this.uPhase[sp];
		this.lo = this.uLo[sp];
		this.hi = this.uHi[sp];
	}

	// Passing the turn, for the search's null-move test. The move counter is reset so repetition checks stop here.
	makeNull() {
		const sp = this.sp;
		this.uMove[sp] = 0;
		this.uCap[sp] = 0;
		this.uCastle[sp] = this.castle;
		this.uEp[sp] = this.ep;
		this.uHalf[sp] = this.halfmove;
		this.uLo[sp] = this.lo;
		this.uHi[sp] = this.hi;
		if (this.ep >= 0) {
			this.lo ^= ZE_LO[this.ep & 7];
			this.hi ^= ZE_HI[this.ep & 7];
			this.ep = -1;
		}
		this.side ^= 1;
		this.lo ^= ZS_LO;
		this.hi ^= ZS_HI;
		this.halfmove = 0;
		this.sp = sp + 1;
		this.histLo[sp + 1] = this.lo;
		this.histHi[sp + 1] = this.hi;
	}

	unmakeNull() {
		const sp = --this.sp;
		this.side ^= 1;
		this.ep = this.uEp[sp];
		this.halfmove = this.uHalf[sp];
		this.lo = this.uLo[sp];
		this.hi = this.uHi[sp];
	}

	// For the search: is this position a draw by repetition? A position seen before at or after `root` (inside the
	// search) counts at once; one seen only before the search must have been seen twice there (a third occurrence).
	repeated(root = 0) {
		const stop = this.sp - this.halfmove;
		let before = 0;
		for (let i = this.sp - 2; i >= stop && i >= 0; i -= 2) {
			if (this.histLo[i] === this.lo && this.histHi[i] === this.hi) {
				if (i >= root || ++before === 2) return true;
			}
		}
		return false;
	}

	// Neither side can ever mate: no pawns, rooks or queens, and either at most one minor piece in all, or only
	// bishops, all on squares of one color.
	insufficient() {
		const c = this.count;
		if (c[PAWN] || c[PAWN | 8] || c[ROOK] || c[ROOK | 8] || c[QUEEN] || c[QUEEN | 8]) return false;
		const minors = c[KNIGHT] + c[KNIGHT | 8] + c[BISHOP] + c[BISHOP | 8];
		if (minors <= 1) return true;
		if (c[KNIGHT] || c[KNIGHT | 8]) return false;
		let light = 0, dark = 0;
		for (let sq = 0; sq < 128; sq++) {
			if (sq & 8) {
				sq += 7;
				continue;
			}
			if ((this.board[sq] & 7) === BISHOP) {
				if (((sq >> 4) + (sq & 7)) & 1) light++;
				else dark++;
			}
		}
		return light === 0 || dark === 0;
	}

	// Every legal move, in generation order.
	legalMoves() {
		const list = new Int32Array(256);
		const n = this.gen(list, 0, true);
		const out = [];
		for (let i = 0; i < n; i++) {
			if (this.make(list[i])) out.push(list[i]);
			this.unmake();
		}
		return out;
	}

	// The legal move written in UCI text, or 0.
	parseUci(text) {
		if (typeof text !== "string" || !/^[a-h][1-8][a-h][1-8][nbrq]?$/.test(text)) return 0;
		for (const m of this.legalMoves()) if (moveUci(m) === text) return m;
		return 0;
	}
}
