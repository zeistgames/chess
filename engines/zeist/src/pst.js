// Material and piece-square values for the Zeist chess engine, in centipawns. Pure: no DOM or platform calls.
//
// Every number here was written for Zeist from a few plain rules (pieces like the center, pawns gain as they
// advance, the king hides in the middlegame and comes out in the endgame). None is copied from a published table.
// The material values are round numbers near the usual pawn 1, minor piece 3 and a bit, rook 5, queen 9 and a half.
//
// Two scores are kept: mg for the middlegame and eg for the endgame. The evaluation blends them by phase.

export const PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6;

export const VALUE_MG = [0, 90, 320, 330, 480, 950, 0];
export const VALUE_EG = [0, 110, 300, 320, 530, 980, 0];
// Phase weight of each piece; 24 with every piece on the board, 0 with only kings and pawns.
export const PHASE_WEIGHT = [0, 0, 1, 1, 2, 4, 0];
export const PHASE_TOTAL = 24;

// The value of a piece of `type` on file f (0 = a) and rank r (0 = its own back rank), seen from its owner.
function square(type, f, r, eg) {
	const fc = Math.min(f, 7 - f);
	const rc = Math.min(r, 7 - r);
	const c = fc + rc; // 0 in a corner, 6 in the center
	switch (type) {
		case PAWN: {
			if (eg) return [0, 0, 4, 10, 18, 28, 40, 0][r];
			let v = [0, 0, 2, 6, 12, 22, 35, 0][r];
			if (f === 3 || f === 4) v += [0, -6, 2, 10, 16, 8, 0, 0][r];
			else if (f === 2 || f === 5) v += [0, 0, 2, 4, 6, 4, 0, 0][r];
			return v;
		}
		case KNIGHT:
			return eg ? c * 6 - 18 : c * 7 - 18 + (r >= 3 && r <= 5 ? 6 : 0) - (r === 0 ? 6 : 0);
		case BISHOP:
			return eg ? c * 4 - 12 : c * 4 - 10 + (f === r || f === 7 - r ? 6 : 0) - (r === 0 ? 4 : 0);
		case ROOK:
			if (eg) return r === 6 ? 10 : 0;
			return (r === 6 ? 16 : 0) + (f === 3 || f === 4 ? 4 : 0) - (f === 0 || f === 7 ? 2 : 0);
		case QUEEN:
			return eg ? c * 5 - 15 : c * 2 - 6 - (r === 0 ? 0 : 0);
		case KING:
			if (eg) return c * 9 - 27;
			if (r === 0) return [12, 20, 10, -5, 0, -5, 20, 12][f];
			if (r === 1) return [4, 6, -6, -12, -12, -6, 6, 4][f];
			return Math.max(-70, -20 * (r - 1) - 12);
	}
	return 0;
}

// PST_MG[piece * 128 + sq] and PST_EG: material plus square, positive for White's pieces and negative for Black's.
// piece = type | color << 3 (color 0 White, 1 Black); sq is a 0x88 square (rank * 16 + file, a1 = 0).
export const PST_MG = new Int16Array(16 * 128);
export const PST_EG = new Int16Array(16 * 128);
for (let color = 0; color < 2; color++) {
	for (let type = 1; type <= 6; type++) {
		const piece = type | (color << 3);
		for (let rank = 0; rank < 8; rank++) {
			for (let f = 0; f < 8; f++) {
				const sq = rank * 16 + f;
				const r = color === 0 ? rank : 7 - rank;
				const sign = color === 0 ? 1 : -1;
				PST_MG[piece * 128 + sq] = sign * (VALUE_MG[type] + square(type, f, r, false));
				PST_EG[piece * 128 + sq] = sign * (VALUE_EG[type] + square(type, f, r, true));
			}
		}
	}
}
