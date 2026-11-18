// Learn as you play: what came up in a game, as cards (docs/LEARN.md, "Learn as you play"). Shared by the web and
// the app (which runs this file in its web view), so both name the same things at the same moments.
//
// Rules: only in a game started from Learn; a card names what has
// happened, never what to play next; about the player's own move it may show right after that move; about the
// opponent's, only once it has played out (the player has replied after material changed hands, or the game is
// over); a pattern is named only when it won material or gave mate, judged from what happened next, never from a
// still position. An opening card shows only after the player's own move. Each kind appears once per game.
//
// cards({ moves, player, fen, learn, over }) -> [{ key, kind, side, ply, shows, title, line, name? }]
//   moves  the game's UCI moves so far       player  "w" or "b", the side the person plays
//   learn  false for a game not started from Learn: nothing, ever
//   over   the game has ended (resigned, agreed, flagged): what was waiting to play out is shown now
// ply is the move the card is about (1 is the first move); shows is the number of moves after which it may be
// shown. Cards come in the order they may be shown.
//
// Material is judged from before the pattern's move, or from before the opponent's move before it when the pattern
// starts by taking back, so taking back in a trade never counts as winning anything.

import { Game, START } from '../rules.js';
import table from '../vendor/chess-openings/openings.js';

const VALUE = { P: 1, N: 3, B: 3, R: 5, Q: 9, K: 0 };
const NAME = { P: 'pawn', N: 'knight', B: 'bishop', R: 'rook', Q: 'queen', K: 'king' };
const COLOR = { w: 'White', b: 'Black' };
/** A tactic counts when it left its side this much ahead in material. */
const GAIN = 2;
/** A piece taken for nothing counts from this value up: a knight or more. */
const HANGING = 3;
/** The furthest a pattern looks ahead (pins: the capture two moves later, and the answer to it). */
const REACH = 6;

// Squares: 0 is a8, 63 is h1, as Game.board() gives them.
const file = i => i % 8;
const rank = i => 8 - Math.floor(i / 8);
const sq = (f, r) => (f < 0 || f > 7 || r < 1 || r > 8 ? -1 : (8 - r) * 8 + f);
const name = i => 'abcdefgh'[file(i)] + rank(i);
const index = s => sq('abcdefgh'.indexOf(s[0]), +s[1]);
const color = p => p[0];
const kind = p => p[1];
const other = c => (c === 'w' ? 'b' : 'w');

const ROOK = [[1, 0], [-1, 0], [0, 1], [0, -1]];
const BISHOP = [[1, 1], [1, -1], [-1, 1], [-1, -1]];
const KNIGHT = [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]];

function rays(k) {
  if (k === 'R') return ROOK;
  if (k === 'B') return BISHOP;
  if (k === 'Q') return ROOK.concat(BISHOP);
  return [];
}

/** The squares the piece on `from` attacks. */
export function attacks(board, from) {
  const p = board[from];
  if (!p) return [];
  const f = file(from), r = rank(from), out = [];
  const k = kind(p);
  if (k === 'P') {
    const dr = color(p) === 'w' ? 1 : -1;
    for (const df of [-1, 1]) { const t = sq(f + df, r + dr); if (t >= 0) out.push(t); }
  } else if (k === 'N' || k === 'K') {
    for (const [df, dr] of (k === 'N' ? KNIGHT : ROOK.concat(BISHOP))) { const t = sq(f + df, r + dr); if (t >= 0) out.push(t); }
  } else {
    for (const [df, dr] of rays(k)) {
      for (let n = 1; ; n++) {
        const t = sq(f + df * n, r + dr * n);
        if (t < 0) break;
        out.push(t);
        if (board[t]) break;
      }
    }
  }
  return out;
}

/** Squares of `side`'s pieces that attack `target`. */
export function attackers(board, target, side) {
  const out = [];
  for (let i = 0; i < 64; i++) if (board[i] && color(board[i]) === side && attacks(board, i).includes(target)) out.push(i);
  return out;
}

function material(board, side) {
  let n = 0;
  for (const p of board) if (p) n += (color(p) === side ? 1 : -1) * VALUE[kind(p)];
  return n;
}

function kingOf(board, side) { return board.findIndex(p => p === side + 'K'); }

/** Squares strictly between two squares on one line, or [] when they are not on a line. */
function between(a, z) {
  const fa = file(a), ra = rank(a), fz = file(z), rz = rank(z);
  if (!(fa === fz || ra === rz || Math.abs(fz - fa) === Math.abs(rz - ra))) return [];
  const df = Math.sign(fz - fa), dr = Math.sign(rz - ra), n = Math.max(Math.abs(fz - fa), Math.abs(rz - ra));
  const out = [];
  for (let s = 1; s < n; s++) out.push(sq(fa + df * s, ra + dr * s));
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// The game, replayed: boards[k] is the board after k moves; plays[k - 1] is what move k did.

function extend(G, moves) {
  while (G.plays.length < moves.length) {
    const m = moves[G.plays.length];
    const before = G.g.board(), mover = G.g.turn();
    if (!G.g.play(m)) break;
    const after = G.g.board();
    const from = index(m.slice(0, 2)), to = index(m.slice(2, 4));
    G.plays.push({ uci: m, mover, from, to, piece: before[from], took: before[to] || null, before, after,
                   check: G.g.inCheck(), promotion: m[4] || null, key: G.g.key() });
    G.boards.push(after);
    G.outcomes.push(G.g.outcome());
  }
}

/** Where the piece standing on `square` after ply k is after each later ply, until it is taken. */
function track(G, square, k, last) {
  const path = [square];
  let at = square;
  for (let j = k + 1; j <= last && at >= 0; j++) {
    const p = G.plays[j - 1];
    if (p.to === at && p.from !== at) at = -1;          // taken
    else if (p.from === at) at = p.to;                   // moved
    else if (kind(p.piece) === 'P' && file(p.from) !== file(p.to) && !p.took && p.to === at + (p.mover === 'w' ? -8 : 8)) at = -1;
    path.push(at);
  }
  return path;
}

/**
 * Material for `side` after ply j, against before ply k. When move k takes back on a square the opponent has just
 * taken on (or `strict`), against before the opponent's move instead, so taking back in a trade never counts.
 */
function gainAt(G, k, side, j, strict = false) {
  const p = G.plays[k - 1], last = G.plays[k - 2];
  const back = strict || (p.took && last && last.took && last.to === p.to);
  const base = G.boards[Math.max(0, back ? k - 2 : k - 1)];
  return material(G.boards[Math.min(j, G.plays.length)], side) - material(base, side);
}

/** A checkmate by `side` at ply j, if the game has one there. */
function mateBy(G, j, side) {
  const o = G.outcomes[j];
  return !!(o && o.reason === 'checkmate' && o.winner === side);
}

/** `side` was mated somewhere in plies a..b. */
function matedIn(G, side, a, b) {
  for (let j = a; j <= Math.min(b, G.plays.length); j++) if (mateBy(G, j, other(side))) return true;
  return false;
}

// ---------------------------------------------------------------------------------------------------------------
// Words. Said from the player's side: "Your knight", "the knight", Black's and White's pieces by color.

function piecesOf(side, player, names) {
  const list = names.length <= 1 ? names.join('') : names.slice(0, -1).join(', ') + ' and ' + names[names.length - 1];
  return side === player ? `your ${list}` : `${COLOR[side]}'s ${list}`;
}
const mine = (side, player, piece) => (side === player ? `Your ${piece}` : `${COLOR[side]}'s ${piece}`);

// ---------------------------------------------------------------------------------------------------------------
// Patterns. Each looks at move k and what happened after it, and returns { kind, at, line } where `at` is the ply
// after which what happened is settled, or null.

function fork(G, k) {
  const p = G.plays[k - 1];
  const b = p.after, me = p.mover, them = other(me);
  const piece = b[p.to];
  if (!piece || mateBy(G, k, me)) return null;            // a move that mates is a mate, not a fork
  // Targets are the king and pieces (never pawns), each worth more than the forking piece or left undefended.
  const targets = attacks(b, p.to).filter(t => b[t] && color(b[t]) === them && kind(b[t]) !== 'P').filter(t => {
    const v = kind(b[t]);
    return v === 'K' || VALUE[v] > VALUE[kind(piece)] || attackers(b, t, them).length === 0;
  });
  if (targets.length < 2) return null;
  const q = G.plays[k + 1];
  if (!q || q.from !== p.to) return null;
  // With the king among the targets, the reply forced, the forking piece giving mate next counts as the fork's win.
  const kingTarget = targets.some(t => kind(b[t]) === 'K');
  const mate = mateBy(G, k + 2, me) && kingTarget;
  // Otherwise two plies later the forking piece takes one of them where it stands.
  if (!mate && (!q.took || !targets.includes(q.to) || G.boards[k + 1][q.to] !== b[q.to])) return null;
  if (!mate && (gainAt(G, k, me, k + 3) < GAIN || matedIn(G, me, k + 1, k + 3) || G.plays.length < k + 3 && !G.over)) return null;
  const names = targets.map(t => NAME[kind(b[t])]);
  const end = mate ? (q.took ? `, then took the ${NAME[kind(q.took)]} with mate.` : ', then gave mate.') : `, and took the ${NAME[kind(q.took)]}.`;
  return { kind: 'fork', at: mate ? k + 2 : k + 3,
           line: `${mine(me, G.player, NAME[kind(piece)])} on ${name(p.to)} attacked ${piecesOf(them, G.player, names)} at once${end}` };
}

/**
 * The two enemy pieces a slider on `from` lines up along each of its lines: [first, second] squares.
 */
function lineups(b, from, them) {
  const out = [];
  const f = file(from), r = rank(from);
  for (const [df, dr] of rays(kind(b[from]))) {
    let first = -1, second = -1;
    for (let n = 1; ; n++) {
      const t = sq(f + df * n, r + dr * n);
      if (t < 0) break;
      if (!b[t]) continue;
      if (first < 0) { if (color(b[t]) !== them) break; first = t; continue; }
      if (color(b[t]) === them) second = t;
      break;
    }
    if (first >= 0 && second >= 0) out.push([first, second]);
  }
  return out;
}

const isPin = (b, first, second) => {
  const a = kind(b[first]), z = kind(b[second]);
  return a !== 'K' && a !== 'P' && (z === 'K' || VALUE[z] > VALUE[a]);
};

/**
 * A pin used: the move pins a piece, or attacks a piece already pinned; and within the next two moves the pinning
 * side wins the pinned piece or the one behind it.
 */
function pin(G, k) {
  const p = G.plays[k - 1];
  const b = p.after, me = p.mover, them = other(me);
  if (mateBy(G, k, me)) return null;
  for (let y = 0; y < 64; y++) {
    if (!b[y] || color(b[y]) !== me || !'RBQ'.includes(kind(b[y]))) continue;
    for (const [first, second] of lineups(b, y, them)) {
      if (!isPin(b, first, second)) continue;
      if (y !== p.to && !attacks(b, p.to).includes(first)) continue;
      const won = pinWon(G, k, y, first, second);
      if (!won) continue;
      return { kind: 'pin', at: won.at,
               line: `${mine(me, G.player, NAME[kind(b[y])])} pinned ${piecesOf(them, G.player, [NAME[kind(b[first])]])} to ${them === G.player ? 'your' : COLOR[them] + "'s"} ${NAME[kind(b[second])]}, and ${won.mate ? 'took it with mate' : 'won the ' + NAME[kind(won.took)]}.` };
    }
  }
  // A check answered by a block: the piece that blocked is pinned by the piece that gave check.
  const reply = G.plays[k];
  if (p.check && reply && b[p.to] && 'RBQ'.includes(kind(b[p.to])) && G.boards[k + 1]?.[p.to] === b[p.to]) {
    const after = G.boards[k + 1];
    for (const [first, second] of lineups(after, p.to, them)) {
      if (first !== reply.to || !isPin(after, first, second)) continue;
      const won = pinWon(G, k, p.to, first, second, k + 1);
      if (!won) continue;
      return { kind: 'pin', at: won.at,
               line: `${mine(me, G.player, NAME[kind(b[p.to])])} gave check and pinned ${piecesOf(them, G.player, [NAME[kind(after[first])]])} that blocked it to ${them === G.player ? 'your' : COLOR[them] + "'s"} ${NAME[kind(after[second])]}, and ${won.mate ? 'took it with mate' : 'won the ' + NAME[kind(won.took)]}.` };
    }
  }
  return null;
}

/** Skewers: a slider that moved to its square attacks a piece with a lesser one behind it. */
function line(G, k) {
  const p = G.plays[k - 1];
  const b = p.after, me = p.mover, them = other(me);
  const piece = b[p.to];
  if (!piece || !'RBQ'.includes(kind(piece)) || mateBy(G, k, me)) return null;
  const f = file(p.to), r = rank(p.to);
  for (const [df, dr] of rays(kind(piece))) {
    let first = -1, second = -1;
    for (let n = 1; ; n++) {
      const t = sq(f + df * n, r + dr * n);
      if (t < 0) break;
      if (!b[t]) continue;
      if (first < 0) { if (color(b[t]) !== them) break; first = t; continue; }
      if (color(b[t]) === them) second = t;
      break;
    }
    if (first < 0 || second < 0) continue;
    const a = kind(b[first]), z = kind(b[second]);
    if (z !== 'P' && (a === 'K' || VALUE[a] > VALUE[z])) {
      // The front piece stepped aside, and the same piece took the one behind it.
      const q = G.plays[k + 1];
      if (q && q.from === p.to && q.to === second && q.took && G.boards[k + 1][first] !== b[first] &&
          gainAt(G, k, me, k + 3) >= GAIN && !matedIn(G, me, k + 1, k + 3) && (G.plays.length >= k + 3 || G.over)) {
        return { kind: 'skewer', at: k + 3,
                 line: `${mine(me, G.player, NAME[kind(piece)])} attacked ${piecesOf(them, G.player, [NAME[a]])} and took the ${NAME[z]} behind it.` };
      }
    }
  }
  return null;
}

/**
 * A pin is named when, within the next two moves of the pinning side, it takes the pinned piece (wherever it went)
 * or the piece behind it, and stays ahead after the answer.
 */
function pinWon(G, k, y, first, second, from = k) {
  const me = G.plays[k - 1].mover;
  const last = Math.min(k + 4, G.plays.length);
  const pinned = track(G, first, from, last), behind = track(G, second, from, last);
  for (let j = k + 2; j <= last; j += 2) {
    const q = G.plays[j - 1];
    if (!q.took || q.mover !== me) continue;
    const at = j - from - 1; // index in the tracks of the position before ply j
    if (q.to !== pinned[at] && q.to !== behind[at]) continue;
    // Taken where it was pinned: the pinning piece must still be in place. The pin kept the piece from leaving when
    // it was attacked; a king that steps out of the line afterwards is too late to save it.
    if (q.to === pinned[at] && pinned[at] === first) {
      const now = G.boards[j - 1], then = G.boards[from];
      if (now[y] !== then[y]) continue;
    }
    const settle = j + 1;
    if (G.plays.length < settle && !G.over) return null;
    if (gainAt(G, k, me, settle) < GAIN || matedIn(G, me, k + 1, settle)) return null;
    return { at: Math.min(settle, Math.max(j, G.plays.length)), took: q.took, mate: mateBy(G, j, me) };
  }
  return null;
}

/** A piece moved out of a line and uncovered an attack (or a check) by another. */
function discovered(G, k) {
  const p = G.plays[k - 1];
  const before = p.before, b = p.after, me = p.mover, them = other(me);
  const uncovered = [];
  for (let y = 0; y < 64; y++) {
    if (y === p.to || !b[y] || color(b[y]) !== me || !'RBQ'.includes(kind(b[y]))) continue;
    for (const t of attacks(b, y)) {
      if (!b[t] || color(b[t]) !== them || kind(b[t]) === 'P') continue;
      if (attacks(before, y).includes(t) || !between(y, t).includes(p.from)) continue;
      uncovered.push({ by: y, target: t });
    }
  }
  if (!uncovered.length) return null;
  const king = kingOf(b, them);
  const checks = uncovered.filter(u => u.target === king);
  const movedChecks = p.check && attacks(b, p.to).includes(king);
  const mate = mateBy(G, k, me) || mateBy(G, k + 2, me);
  const settled = G.plays.length >= k + 3 || G.over;
  const won = settled && gainAt(G, k, me, k + 3) >= GAIN && !matedIn(G, me, k + 1, k + 3);
  const at = mateBy(G, k, me) ? k : mateBy(G, k + 2, me) ? k + 2 : k + 3;
  const q2 = G.plays[k + 1];
  const end = mate ? ', and mate followed.' : q2 && q2.mover === me && q2.took ? `, and won the ${NAME[kind(q2.took)]}.` : ', and won material.';
  const moved = (p.mover === G.player ? 'your ' : COLOR[me] + "'s ") + NAME[kind(p.piece)];
  if (checks.length && movedChecks) {
    if (!(mate || won)) return null;
    return { kind: 'double-check', at,
             line: `${mine(me, G.player, NAME[kind(p.piece)])} and ${me === G.player ? 'your' : 'its'} ${NAME[kind(b[checks[0].by])]} gave check at once${end}` };
  }
  if (checks.length) {
    if (!(mate || won)) return null;
    return { kind: 'discovered-check', at, line: `Moving ${moved} gave check with ${me === G.player ? 'your' : 'its'} ${NAME[kind(b[checks[0].by])]}${end}` };
  }
  // A discovered attack: the uncovered piece takes its target two plies later.
  const q = G.plays[k + 1];
  const hit = q && q.took ? uncovered.find(u => u.by === q.from && u.target === q.to) : null;
  if (!hit || !(mate || won)) return null;
  return { kind: 'discovered-attack', at,
           line: `Moving ${moved} uncovered an attack by ${me === G.player ? 'your' : 'its'} ${NAME[kind(b[hit.by])]} on ${piecesOf(them, G.player, [NAME[kind(b[hit.target])]])}${mate ? ', and mate followed.' : `, and won the ${NAME[kind(q.took)]}.`}` };
}

/**
 * A piece of a knight or more taken where nothing defended it: not a recapture, not a trade, and still ahead two
 * moves later with no mate against the side that took it (so a sacrifice that won is not called a free piece).
 */
function hanging(G, k) {
  const p = G.plays[k - 1];
  if (!p.took || VALUE[kind(p.took)] < HANGING) return null;
  const me = p.mover, them = other(me);
  if (attackers(p.before, p.to, them).length || mateBy(G, k, me)) return null;   // a capture that mates is named as the mate
  const last = G.plays[k - 2];
  if (last && (last.to === p.to || last.took || last.check)) return null;     // a recapture, a trade, or a forced capture
  const settle = k + 4;
  if (G.plays.length < settle && !G.over) return null;
  for (const j of [k + 2, settle]) if (gainAt(G, k, me, j, true) < HANGING) return null;
  if (matedIn(G, me, k + 1, k + 5)) return null;
  return { kind: 'hanging', at: Math.min(settle, Math.max(k + 1, G.plays.length)),
           line: `${mine(me, G.player, NAME[kind(p.piece)])} took ${piecesOf(them, G.player, [NAME[kind(p.took)]])} on ${name(p.to)}, which nothing defended.` };
}

function mates(G, k) {
  const p = G.plays[k - 1];
  if (!mateBy(G, k, p.mover)) return null;
  const b = p.after, them = other(p.mover);
  const king = kingOf(b, them);
  const near = attacks(b, king);
  const you = p.mover === G.player;
  if (kind(p.piece) === 'N' && near.every(t => b[t] && color(b[t]) === them)) {
    return { kind: 'smothered-mate', at: k,
             line: you ? 'Your knight gave mate to a king hemmed in by its own pieces.' : 'The knight gave mate to your king, hemmed in by your own pieces.' };
  }
  const back = them === 'w' ? 1 : 8;
  const checker = b[p.to];
  if (checker && 'RQ'.includes(kind(checker)) && rank(king) === back && rank(p.to) === back) {
    const ahead = near.filter(t => rank(t) !== back);
    if (ahead.length && ahead.every(t => b[t] && color(b[t]) === them)) {
      const by = ahead.every(t => kind(b[t]) === 'P') ? 'pawns' : 'pieces';
      return { kind: 'back-rank-mate', at: k,
               line: you ? `Your ${NAME[kind(checker)]} gave mate on the back rank, the king boxed in by its own ${by}.`
                         : `The ${NAME[kind(checker)]} gave mate on your back rank, your king boxed in by your own ${by}.` };
    }
  }
  return null;
}

/** Moves worth naming whatever they won: castling, en passant, promotion. */
function events(G, k) {
  const p = G.plays[k - 1];
  const out = [];
  const you = p.mover === G.player;
  if (kind(p.piece) === 'K' && Math.abs(file(p.to) - file(p.from)) === 2) {
    out.push({ kind: 'castling', line: you ? 'You castled: the king and a rook moved in one move.' : `${COLOR[p.mover]} castled: the king and a rook moved in one move.` });
  }
  if (kind(p.piece) === 'P' && file(p.to) !== file(p.from) && !p.took) {
    out.push({ kind: 'en-passant', line: you ? 'Your pawn took a pawn that had just moved two squares past it.' : `${COLOR[p.mover]}'s pawn took your pawn as it moved two squares past it.` });
  }
  if (p.promotion) {
    const who = you ? 'Your' : `${COLOR[p.mover]}'s`;
    out.push(p.promotion === 'q'
      ? { kind: 'promotion', line: `${who} pawn reached the last rank and became a queen.` }
      : { kind: 'underpromotion', line: `${who} pawn reached the last rank and became a ${NAME[p.promotion.toUpperCase()]}, not a queen.` });
  }
  for (const e of out) e.at = k;
  return out;
}

function stalemate(G, k) {
  const o = G.outcomes[k];
  return o && o.reason === 'stalemate'
    ? { kind: 'stalemate', at: k, line: `${COLOR[other(G.plays[k - 1].mover)]} had no legal move and was not in check, so the game is drawn.` }
    : null;
}

const TITLE = {
  fork: 'A fork', pin: 'A pin', skewer: 'A skewer', 'discovered-attack': 'A discovered attack',
  'discovered-check': 'A discovered check', 'double-check': 'A double check', hanging: 'A piece taken for nothing',
  'back-rank-mate': 'Back-rank mate', 'smothered-mate': 'Smothered mate', castling: 'Castling', 'en-passant': 'En passant',
  promotion: 'Promotion', underpromotion: 'Underpromotion', stalemate: 'Stalemate',
};

const TACTICS = new Set(['fork', 'pin', 'skewer', 'discovered-attack', 'discovered-check', 'double-check']);

/** Everything found about move k: { kind, at, line }. */
function detect(G, k) {
  const out = [];
  const tactic = fork(G, k) || line(G, k) || pin(G, k) || discovered(G, k);
  if (tactic) out.push(tactic);
  const m = mates(G, k);
  if (m) out.push(m);
  // A capture that finished a tactic two plies earlier is part of it, not a piece taken for nothing.
  if (!tactic && !(k > 2 && G.tactics.get(k - 2))) { const h = hanging(G, k); if (h) out.push(h); }
  out.push(...events(G, k));
  const s = stalemate(G, k);
  if (s) out.push(s);
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// One game at a time is kept, so each new move looks only at the moves whose outcome is still open.

let memo = null;

function game(moves, fen, player, over) {
  const fresh = !memo || memo.fen !== fen || memo.player !== player || memo.moves.length > moves.length ||
    memo.moves.some((m, i) => m !== moves[i]);
  if (fresh) {
    memo = { fen, player, moves: [], G: { g: new Game(fen), boards: [], plays: [], outcomes: [null], tactics: new Map() }, settled: new Map() };
    memo.G.boards.push(memo.G.g.board());
  }
  extend(memo.G, moves);
  memo.moves = memo.G.plays.map(p => p.uci);
  memo.G.player = player;
  memo.G.over = over || memo.G.outcomes[memo.G.plays.length] != null;
  return memo;
}

/** The cards of a game, in the order they may be shown. */
export function cards({ moves = [], player = 'w', fen = START, learn = true, over = false } = {}) {
  if (!learn) return [];
  const M = game(moves, fen, player, over);
  const G = M.G;
  const n = G.plays.length;
  const found = [];
  const add = (c, k) => {
    const side = G.plays[k - 1].mover;
    // About the opponent: only once the player has replied after it played out. The end of the game shows all.
    let shows = c.at;
    if (side !== player && (shows - k) % 2 === 0) shows += 1;
    if (shows > n) { if (!G.over) return; shows = n; }
    found.push({ key: c.kind, kind: c.kind, side: side === player ? 'player' : 'opponent', ply: k, shows, title: TITLE[c.kind], line: c.line });
  };

  // Openings: each name the table gives along the way, shown after the player's own move.
  let last = null;
  for (let k = 1; k <= n; k++) {
    const hit = table[G.plays[k - 1].key];
    if (!hit) continue;
    const [eco, full] = hit.split('|');
    if (full === last) continue;
    last = full;
    const side = G.plays[k - 1].mover;
    let shows = side === player ? k : k + 1;
    if (shows > n) { if (!G.over) continue; shows = n; }
    found.push({ key: 'opening:' + full, kind: 'opening', side: side === player ? 'player' : 'opponent', ply: k, shows,
                 title: full.split(':')[0], line: null, name: full, eco });
  }

  for (let k = 1; k <= n; k++) {
    // What happened at a move settled long ago, in a game still going, is kept from the last call.
    const final = k + REACH <= n;
    let list = final ? M.settled.get(k) : null;
    if (!list) {
      list = detect(G, k);
      if (final) M.settled.set(k, list);
    }
    G.tactics.set(k, list.some(c => TACTICS.has(c.kind)));
    for (const c of list) add(c, k);
  }

  // Once per kind (openings once per name), the first time it happened.
  const seen = new Set();
  return found
    .sort((a, b) => a.shows - b.shows || a.ply - b.ply)
    .filter(c => (seen.has(c.key) ? false : (seen.add(c.key), true)));
}
