// The Zeist chess evaluation: a tapered integer score in centipawns, from the side to move. Pure: integers only.
//
// Terms, each with a middlegame and an endgame weight, blended by how much material is left: material and piece
// squares (kept up to date by the board as moves are made), mobility, king safety (attackers near the king and the
// pawns in front of it), pawn structure (doubled, isolated, connected and passed pawns), rooks on open files and
// the seventh rank, the bishop pair, and a little for having the move. Every weight was chosen for Zeist; none
// is taken from another engine.

import { PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING, N_OFF, K_OFF, B_OFF, R_OFF, DIST, WHITE } from "./board.js";
import { PHASE_TOTAL } from "./pst.js";

const MOB_MG = [0, 0, 4, 5, 2, 1, 0];
const MOB_EG = [0, 0, 4, 5, 4, 2, 0];
const MOB_BASE = [0, 0, 4, 6, 7, 13, 0];
const ATTACK_WEIGHT = [0, 0, 2, 2, 3, 5, 0];
// Penalty for the attack weight on a king, when two or more pieces join in.
const SAFETY = new Int16Array(64);
for (let w = 0; w < 64; w++) SAFETY[w] = Math.min(500, (w * w * 3) >> 1);

const PASSED_MG = [0, 4, 8, 14, 26, 44, 70, 0];
const PASSED_EG = [0, 10, 16, 28, 48, 80, 125, 0];
const CONNECTED = [0, 0, 6, 8, 12, 20, 32, 0];

// Distance of a square from the center, 0 to 6 (for driving a lone king to the edge).
const CENTER = new Int8Array(128);
for (let sq = 0; sq < 128; sq++) {
	if (sq & 0x88) continue;
	const f = sq & 7, r = sq >> 4;
	CENTER[sq] = Math.max(3 - f, f - 4) + Math.max(3 - r, r - 4);
}

const wMin = new Int8Array(10), wMax = new Int8Array(10), wCnt = new Int8Array(10);
const bMin = new Int8Array(10), bMax = new Int8Array(10), bCnt = new Int8Array(10);
const pawnList = new Int32Array(16), pieceList = new Int32Array(32);

export function evaluate(p) {
	const b = p.board, c = p.count;
	let mg = p.mg, eg = p.eg;

	// Pawn files, indexed file + 1 so that files -1 and 8 read as empty.
	for (let f = 0; f < 10; f++) {
		wMin[f] = 8; wMax[f] = -1; wCnt[f] = 0;
		bMin[f] = 8; bMax[f] = -1; bCnt[f] = 0;
	}
	// One pass over the board: pawn files, and a list of the pawns and of the other pieces (kings left out).
	let np = 0, nq = 0;
	for (let sq = 0; sq < 128; sq++) {
		if (sq & 8) { sq += 7; continue; }
		const q = b[sq];
		if (!q) continue;
		const type = q & 7;
		if (type !== PAWN) {
			if (type !== KING) pieceList[nq++] = sq;
			continue;
		}
		pawnList[np++] = sq;
		const f = (sq & 7) + 1, r = sq >> 4;
		if (q === PAWN) {
			wCnt[f]++;
			if (r < wMin[f]) wMin[f] = r;
			if (r > wMax[f]) wMax[f] = r;
		} else {
			bCnt[f]++;
			if (r < bMin[f]) bMin[f] = r;
			if (r > bMax[f]) bMax[f] = r;
		}
	}

	const wk = p.king[0], bk = p.king[1];
	let wAttackers = 0, wWeight = 0, bAttackers = 0, bWeight = 0; // attacks on the black and white king zones

	for (let i = 0; i < np + nq; i++) {
		const sq = i < np ? pawnList[i] : pieceList[i - np];
		const q = b[sq];
		const type = q & 7, color = q >> 3;
		const f = sq & 7, r = sq >> 4;
		if (type === PAWN) {
			const fi = f + 1;
			if (color === WHITE) {
				if (wCnt[fi] > 1 && r === wMin[fi]) { mg -= 10 * (wCnt[fi] - 1); eg -= 20 * (wCnt[fi] - 1); }
				if (!wCnt[fi - 1] && !wCnt[fi + 1]) { mg -= 10; eg -= 15; }
				else if (b[sq - 15] === PAWN || b[sq - 17] === PAWN || b[sq + 1] === PAWN || b[sq - 1] === PAWN) { mg += CONNECTED[r]; eg += CONNECTED[r]; }
				if (bMax[fi - 1] <= r && bMax[fi] <= r && bMax[fi + 1] <= r) {
					mg += PASSED_MG[r];
					let e = PASSED_EG[r];
					const front = sq + 16;
					if (r >= 3) e += (DIST[front - bk + 119] * 5 - DIST[front - wk + 119] * 2) * (r - 2);
					if (b[front]) e -= e >> 2;
					eg += e;
				}
			} else {
				const rr = 7 - r;
				if (bCnt[fi] > 1 && r === bMax[fi]) { mg += 10 * (bCnt[fi] - 1); eg += 20 * (bCnt[fi] - 1); }
				if (!bCnt[fi - 1] && !bCnt[fi + 1]) { mg += 10; eg += 15; }
				else if (b[sq + 15] === (PAWN | 8) || b[sq + 17] === (PAWN | 8) || b[sq + 1] === (PAWN | 8) || b[sq - 1] === (PAWN | 8)) { mg -= CONNECTED[rr]; eg -= CONNECTED[rr]; }
				if (wMin[fi - 1] >= r && wMin[fi] >= r && wMin[fi + 1] >= r) {
					mg -= PASSED_MG[rr];
					let e = PASSED_EG[rr];
					const front = sq - 16;
					if (rr >= 3) e += (DIST[front - wk + 119] * 5 - DIST[front - bk + 119] * 2) * (rr - 2);
					if (b[front]) e -= e >> 2;
					eg -= e;
				}
			}
			continue;
		}
		// Mobility: squares not held by own pieces and not covered by enemy pawns. Attacks near the enemy king.
		const enemyKing = color === WHITE ? bk : wk;
		const enemyPawn = color === WHITE ? PAWN | 8 : PAWN;
		const pawnA = color === WHITE ? 15 : -15, pawnB = color === WHITE ? 17 : -17;
		let mob = 0, zone = 0;
		if (type === KNIGHT) {
			for (let i = 0; i < 8; i++) {
				const t = sq + N_OFF[i];
				if (t & 0x88) continue;
				const v = b[t];
				if (v && v >> 3 === color) continue;
				if (DIST[t - enemyKing + 119] <= 1) zone++;
				if (!((t + pawnA) & 0x88) && b[t + pawnA] === enemyPawn) continue;
				if (!((t + pawnB) & 0x88) && b[t + pawnB] === enemyPawn) continue;
				mob++;
			}
		} else {
			const start = type === ROOK ? 4 : 0, end = type === BISHOP ? 4 : 8;
			for (let i = start; i < end; i++) {
				const o = i < 4 ? B_OFF[i] : R_OFF[i - 4];
				let t = sq + o;
				while (!(t & 0x88)) {
					const v = b[t];
					if (v && v >> 3 === color) break;
					if (DIST[t - enemyKing + 119] <= 1) zone++;
					if (!(((t + pawnA) & 0x88) === 0 && b[t + pawnA] === enemyPawn) && !(((t + pawnB) & 0x88) === 0 && b[t + pawnB] === enemyPawn)) mob++;
					if (v) break;
					t += o;
				}
			}
		}
		const sign = color === WHITE ? 1 : -1;
		mg += sign * (mob - MOB_BASE[type]) * MOB_MG[type];
		eg += sign * (mob - MOB_BASE[type]) * MOB_EG[type];
		if (zone) {
			if (color === WHITE) { wAttackers++; wWeight += ATTACK_WEIGHT[type] * Math.min(zone, 3); }
			else { bAttackers++; bWeight += ATTACK_WEIGHT[type] * Math.min(zone, 3); }
		}
		if (type === ROOK) {
			const fi = f + 1;
			const own = color === WHITE ? wCnt[fi] : bCnt[fi];
			const their = color === WHITE ? bCnt[fi] : wCnt[fi];
			if (!own) {
				mg += sign * (their ? 12 : 25);
				eg += sign * (their ? 6 : 10);
			}
			const rr = color === WHITE ? r : 7 - r;
			const kr = color === WHITE ? bk >> 4 : 7 - (wk >> 4);
			if (rr === 6 && kr === 7) { mg += sign * 15; eg += sign * 25; }
		}
	}

	// King safety, in the middlegame only: attackers near the king, and the pawns in front of it.
	if (wAttackers >= 2 && c[QUEEN]) mg += SAFETY[Math.min(63, wWeight)];
	if (bAttackers >= 2 && c[QUEEN | 8]) mg -= SAFETY[Math.min(63, bWeight)];
	mg += shelter(b, wk, WHITE) - shelter(b, bk, 1);

	if (c[BISHOP] >= 2) { mg += 30; eg += 50; }
	if (c[BISHOP | 8] >= 2) { mg -= 30; eg -= 50; }

	const phase = Math.min(p.phase, PHASE_TOTAL);
	let v = ((mg * phase + eg * (PHASE_TOTAL - phase)) / PHASE_TOTAL) | 0;

	// Endgames: drive a lone king to the edge; scale down advantages that cannot be turned into a win.
	const wPawns = c[PAWN], bPawns = c[PAWN | 8];
	const wNp = c[KNIGHT] * 3 + c[BISHOP] * 3 + c[ROOK] * 5 + c[QUEEN] * 9;
	const bNp = c[KNIGHT | 8] * 3 + c[BISHOP | 8] * 3 + c[ROOK | 8] * 5 + c[QUEEN | 8] * 9;
	if (!bPawns && !bNp && wNp >= 5) v += 10 * CENTER[bk] + 4 * (14 - manhattan(wk, bk)) + 200;
	else if (!wPawns && !wNp && bNp >= 5) v -= 10 * CENTER[wk] + 4 * (14 - manhattan(wk, bk)) + 200;
	if (v > 0 && !wPawns && wNp - bNp <= 3) v >>= 3;
	else if (v < 0 && !bPawns && bNp - wNp <= 3) v = -((-v) >> 3);
	else if (c[BISHOP] === 1 && c[BISHOP | 8] === 1 && wNp === 3 && bNp === 3 && oppositeBishops(b)) v = (v / 2) | 0;

	return (p.side === WHITE ? v : -v) + 10;
}

const manhattan = (a, b) => Math.abs((a & 7) - (b & 7)) + Math.abs((a >> 4) - (b >> 4));

function oppositeBishops(b) {
	let w = -1, k = -1;
	for (let sq = 0; sq < 128; sq++) {
		if (sq & 8) { sq += 7; continue; }
		if (b[sq] === BISHOP) w = ((sq >> 4) + (sq & 7)) & 1;
		else if (b[sq] === (BISHOP | 8)) k = ((sq >> 4) + (sq & 7)) & 1;
	}
	return w !== k;
}

// Pawns in front of a king on its first two ranks: a bonus for each, a penalty for each missing one.
function shelter(b, k, color) {
	const r = k >> 4;
	const rr = color === WHITE ? r : 7 - r;
	if (rr > 1) return -20;
	const fwd = color === WHITE ? 16 : -16;
	const pawn = PAWN | (color << 3);
	let s = 0;
	const f = k & 7;
	for (let df = -1; df <= 1; df++) {
		const ff = f + df;
		if (ff < 0 || ff > 7) continue;
		const one = k + df + fwd, two = one + fwd;
		if (b[one] === pawn) s += 12;
		else if (b[two] === pawn) s += 6;
		else s -= 12;
	}
	return s;
}

export { K_OFF };
