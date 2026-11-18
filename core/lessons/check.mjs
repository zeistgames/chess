#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Checks every lesson in Learn against the format in docs/LESSONS.md.
//
//   node core/lessons/check.mjs                 shape, chess, claims and words
//   node core/lessons/check.mjs --engine        and Stockfish on every move step
//   node core/lessons/check.mjs --course tactics,checkmates   only these courses; other courses' faults are set aside
//   node core/lessons/check.mjs --scope ruy-lopez,openings-ruy   only these chapters (by id) and lessons (by how their id begins)
//
// Options: --all (go on past the first lesson with a fault), --nodes N (the engine's node budget per search,
// default 1000000), --verbose (print the engine's view of every accepted, also and wrong move), and lesson ids to
// check only those. Exit code 0 only when every lesson checked passes.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Game, START as START_FEN } from '../rules.js';
import OPENINGS from '../vendor/chess-openings/openings.js';

const here = path.dirname(fileURLToPath(import.meta.url));

// The puzzle themes a lesson may point to with `puzzles` (group ids in puzzles/themes.json).
export const THEMES = new Set(JSON.parse(fs.readFileSync(path.join(here, '../../puzzles/themes.json'), 'utf8')).groups.map(g => g.id));
export const COURSES = ['basics', 'openings', 'tactics', 'checkmates', 'endgames', 'strategy'];
export const GROUPS = {
  white: ['With the king\'s pawn', 'With the queen\'s pawn', 'Other first moves'],
  black: ['Against the king\'s pawn', 'Against the queen\'s pawn', 'Against other first moves'],
};
// The lessons about notation itself, where moves and squares may be written out without marks.
export const NOTATION_LESSONS = ['basics-squares', 'basics-reading-moves'];
// A move written in notation: a piece letter and a square ("Nf3", "Bxc6", "Qh4#"), a pawn capture ("dxc6"),
// castling ("O-O"), a promotion ("e8=Q") or a numbered move ("1.e4", "3...Bc5").
// Also a pawn move given as its square after a verb of playing ("Play e4", "answered with d6"), castling with
// zeros ("0-0"), a piece letter in lowercase or set apart ("nf3", "N f3"), and a square in capitals ("A8").
const NOTATION = new RegExp([
  /\b[KQRBN][a-h]?[1-8]?x?[a-h][1-8]\b/, /\b[a-h]x[a-h][1-8]\b/, /\b[O0]-[O0](-[O0])?\b/, /\b[a-h][18]=?[QRBNqrbn]\b/,
  /\b\d+\.(\.\.)?\s?[a-hKQRBNO]/, /\b[kqrbn]x?[a-h][1-8]\b/, /\b[KQRBN]\s+x?[a-h][1-8]\b/, /\b[A-H][1-8]\b/,
  /\b([Pp]lay|[Pp]lays|[Pp]layed|[Pp]laying|[Pp]ush|[Pp]ushes|[Pp]ushed|[Aa]nswer|[Aa]nswers|[Aa]nswered|[Mm]eets?|[Mm]et|[Aa]fter|[Tt]hen|[Ww]ith)\s+[a-h][1-8]\b/,
].map(r => r.source).join('|'));
export const VALUES = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };
export const TEXT_MAX = 140;
export const SUMMARY_MAX = 120;
export const ENGINE_MARGIN = 50; // centipawns: half a pawn
export const TAUGHT_MARGIN = 150; // a pawn and a half, for moves marked taught
export const SACRIFICE_AHEAD = 150; // a sacrifice must leave the player more than a pawn and a half ahead
export const DECISIVE = 500; // an accepted move that leaves the player this far ahead passes whatever the best is
export const AHEAD = 50; // a wins claim needs Stockfish to rate the player more than half a pawn ahead

const ID = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const SQUARE = /^[a-h][1-8]$/;
const UCI = /^[a-h][1-8][a-h][1-8][qrbn]?$/;

const LESSON_KEYS = ['id', 'course', 'title', 'line', 'side', 'steps', 'summary', 'practice', 'puzzles'];
const STEP_KEYS = {
  show: ['type', 'text', 'fen', 'marks', 'side', 'play'],
  move: ['type', 'text', 'fen', 'marks', 'side', 'accept', 'wrong', 'also', 'hint', 'after', 'reply', 'wins', 'mate', 'taught', 'sacrifice'],
  pick: ['type', 'text', 'fen', 'marks', 'side', 'accept', 'all', 'wrong', 'hint', 'after'],
};
const INDEX_KEYS = ['version', 'courses'];
const COURSE_KEYS = ['id', 'title', 'line', 'chapters'];
const CHAPTER_KEYS = ['id', 'title', 'lessons'];
const OPENING_KEYS = ['for', 'group', 'line', 'play', 'moves', 'fen'];
const ENTRY_KEYS = ['id', 'title', 'line', 'fen', 'marks', 'side'];

// ---------------------------------------------------------------------------------------------------------
// Small helpers

const isObj = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const isStr = v => typeof v === 'string' && v.length > 0;

function unknownKeys(obj, allowed) {
  return Object.keys(obj).filter(k => !allowed.includes(k));
}

/** A fault collector for one lesson (or the index). */
class Faults {
  constructor(where) { this.where = where; this.list = []; this.about = null; }
  // `about` says which course, chapter and lesson a fault in the index belongs to, so a filtered run can tell
  // whose it is without reading the message.
  add(step, msg) { this.list.push({ where: this.where, step, msg, ...(this.about ? { about: this.about } : {}) }); }
  get ok() { return this.list.length === 0; }
}

export function formatFault(f) {
  return f.step == null ? `${f.where}: ${f.msg}` : `${f.where} step ${f.step}: ${f.msg}`;
}

// ---------------------------------------------------------------------------------------------------------
// Positions

/** Pieces on the board from a Game: [{ sq, color, type }]. */
function pieces(g) {
  const b = g.board();
  const out = [];
  for (let i = 0; i < 64; i++) {
    if (!b[i]) continue;
    out.push({ sq: 'abcdefgh'[i % 8] + (8 - Math.floor(i / 8)), color: b[i][0], type: b[i][1].toLowerCase() });
  }
  return out;
}

function pieceAt(g, sq) {
  return pieces(g).find(p => p.sq === sq) || null;
}

/** Material of color minus the other side's, in points. */
export function balance(g, color) {
  let n = 0;
  for (const p of pieces(g)) n += (p.color === color ? 1 : -1) * VALUES[p.type];
  return n;
}

/**
 * Why a FEN is not a legal, plausible position, or null when it is. Uses core/rules.js for the parse and
 * for whether the side not to move stands in check.
 */
export function fenProblem(fen) {
  if (!isStr(fen)) return 'is missing';
  const parts = fen.trim().split(/\s+/);
  if (parts.length !== 6) return 'needs all six FEN fields';
  let g;
  try { g = new Game(fen); } catch (e) { return 'is not a legal FEN (' + String(e.message || e).split('\n')[0] + ')'; }
  const ps = pieces(g);
  for (const c of ['w', 'b']) {
    const mine = ps.filter(p => p.color === c);
    const name = c === 'w' ? 'White' : 'Black';
    if (mine.filter(p => p.type === 'k').length !== 1) return `${name} needs exactly one king`;
    if (mine.length > 16) return `${name} has more than 16 pieces`;
    const pawns = mine.filter(p => p.type === 'p').length;
    if (pawns > 8) return `${name} has more than 8 pawns`;
    const extra = ['q', 'r', 'b', 'n'].reduce((n, t) => n + Math.max(0, mine.filter(p => p.type === t).length - (t === 'q' ? 1 : 2)), 0);
    if (extra > 8 - pawns) return `${name} has more promoted pieces than missing pawns`;
  }
  if (ps.some(p => p.type === 'p' && (p.sq[1] === '1' || p.sq[1] === '8'))) return 'has a pawn on the first or last rank';
  const kings = ps.filter(p => p.type === 'k');
  const [a, b] = kings.map(k => k.sq);
  if (Math.abs(a.charCodeAt(0) - b.charCodeAt(0)) <= 1 && Math.abs(+a[1] - +b[1]) <= 1) return 'has the kings next to each other';
  // The side not to move must not be in check: flip the turn and ask the rules.
  const flipped = [parts[0], parts[1] === 'w' ? 'b' : 'w', '-', '-', '0', '1'].join(' ');
  let f;
  try { f = new Game(flipped); } catch { f = null; }
  if (f && f.inCheck()) return 'has the side not to move in check';
  // Castling rights need the king and rook at home.
  const at = sq => ps.find(p => p.sq === sq);
  const home = { K: ['e1', 'h1', 'w'], Q: ['e1', 'a1', 'w'], k: ['e8', 'h8', 'b'], q: ['e8', 'a8', 'b'] };
  if (parts[2] !== '-') {
    for (const ch of parts[2]) {
      const h = home[ch];
      if (!h) return 'has a castling field it cannot have';
      const k = at(h[0]), r = at(h[1]);
      if (!k || k.type !== 'k' || k.color !== h[2] || !r || r.type !== 'r' || r.color !== h[2]) return `has castling right ${ch} without the king and rook at home`;
    }
  }
  // An en passant square needs the pawn that just moved two squares.
  if (parts[3] !== '-') {
    const ep = parts[3];
    const mover = parts[1] === 'w' ? 'b' : 'w';
    const pawnSq = ep[0] + (mover === 'b' ? '5' : '4');
    const p = at(pawnSq);
    if ((mover === 'b' && ep[1] !== '6') || (mover === 'w' && ep[1] !== '3') || !p || p.type !== 'p' || p.color !== mover || at(ep)) return 'has an en passant square with no pawn that just moved two squares';
  }
  return null;
}

function san(fen, uci) {
  const g = new Game(fen);
  const r = g.play(uci);
  return r ? r.san : uci;
}

/** Plays moves from a FEN; returns the Game or { error }. */
function playLine(fen, moves) {
  const g = new Game(fen);
  for (let i = 0; i < moves.length; i++) {
    if (!UCI.test(moves[i]) || !g.play(moves[i])) return { error: `${moves[i]} is not legal (move ${i + 1} of the line)` };
  }
  return { game: g };
}

/** Plays "1.e4 e5 2.Nf3" from the start; returns the Game or { error }. */
export function playNotation(text) {
  const g = new Game();
  const tokens = String(text).trim().split(/\s+/).map(t => t.replace(/^\d+\.(\.\.)?/, '')).filter(Boolean);
  for (const t of tokens) if (!g.playSan(t)) return { error: `${t} is not legal` };
  return { game: g };
}

// ---------------------------------------------------------------------------------------------------------
// Claims

/**
 * Material for the side to move once the captures on the board have settled: a small capture-only search
 * where either side may stop capturing (standing pat) when that suits it.
 */
function settled(g, alpha, beta, depth) {
  const stand = balance(g, g.turn());
  if (depth === 0 || stand >= beta) return stand;
  if (stand > alpha) alpha = stand;
  for (const m of g.legal()) {
    if (!m.capture && !m.promotion) continue;
    g.play(m.uci);
    const o = g.outcome();
    const v = o ? (o.reason === 'checkmate' ? 1000 : 0) : -settled(g, -beta, -alpha, depth - 1);
    g.undo();
    if (v >= beta) return v;
    if (v > alpha) alpha = v;
  }
  return alpha;
}

/**
 * Checks a `wins` claim: after the move and every possible answer, the player has a next move such that after
 * every answer to that, and once the captures that follow have settled, they are ahead of where they started
 * by at least `need` points; or the player mates. Returns null when it holds, else a sentence naming the
 * defense that refutes it.
 */
export function winsProblem(fen, move, need) {
  const g = new Game(fen);
  const me = g.turn();
  const base = balance(g, me);
  if (!g.play(move)) return `${move} is not legal`;
  const o = g.outcome();
  if (o) return o.reason === 'checkmate' ? null : `the move ends the game in a draw (${o.reason})`;
  const memo = new Map(); // settled material by position: lines reach the same positions in other orders
  const leaf = () => {
    const k = g.key();
    // Only whether the gain is kept matters, so the search is asked that one question (a narrow window): fast.
    if (!memo.has(k)) memo.set(k, settled(g, base + need - 1, base + need, 6));
    return memo.get(k);
  };
  for (const r1 of g.legal()) {
    g.play(r1.uci);
    const o1 = g.outcome();
    let held = false;
    if (!o1) {
      // Captures and checks first: they are the moves most likely to cash in.
      const mine = g.legal().sort((x, y) => (y.capture - x.capture) || (/\+|#/.test(y.san) - /\+|#/.test(x.san)));
      for (const m2 of mine) {
        g.play(m2.uci);
        const o2 = g.outcome();
        if (o2 && o2.reason === 'checkmate') { held = true; g.undo(); break; }
        if (!o2) {
          let worst = Infinity;
          // Captures first: they are the answers most likely to refute.
          for (const r2 of g.legal().sort((x, y) => y.capture - x.capture)) {
            g.play(r2.uci);
            // Any end of the game here (the player mated, or a draw) means the gain was not kept.
            const v = g.outcome() ? -Infinity : leaf() - base;
            g.undo();
            if (v < worst) worst = v;
            if (worst < need) break;
          }
          if (worst >= need) { held = true; g.undo(); break; }
        }
        g.undo();
      }
    }
    g.undo();
    if (!held) return `after ${san(fen, move)} ${r1.san}, nothing keeps a gain of ${need} within two moves`;
  }
  return null;
}

/** Why a move gives material away once the captures that follow are played out, or null. */
export function losesMaterial(fen, move) {
  const g = new Game(fen);
  const me = g.turn();
  const base = balance(g, me);
  if (!g.play(move)) return `${move} is not legal`;
  if (g.outcome()) return null;
  const after = -settled(g, -Infinity, Infinity, 6); // the opponent moves first: their best captures
  if (after < base) return `after the captures that follow, the player is ${base - after} behind where they started`;
  return null;
}

function isMate(fen, move) {
  const g = new Game(fen);
  if (!g.play(move)) return false;
  const o = g.outcome();
  return Boolean(o && o.reason === 'checkmate');
}

// ---------------------------------------------------------------------------------------------------------
// Words

const BRITISH = ['colour', 'colours', 'behaviour', 'centre', 'centres', 'defence', 'defences', 'favourite', 'realise', 'realised',
  'organise', 'honour', 'neighbour', 'neighbours', 'grey', 'programme', 'analyse', 'analysed', 'manoeuvre', 'manoeuvres', 'armour',
  'travelled', 'cancelled', 'whilst', 'amongst', 'licence', 'practise', 'recognise', 'apologise', 'learnt', 'spelt', 'cheque'];
// Praise anywhere, and verdicts: "good", "correct" or "right" said of the player's move.
const PRAISE = /\b(great|excellent|well done|nice|perfect|brilliant|awesome|good job|bravo|amazing|fantastic|superb|congratulations)\b/i;
const VERDICT = /(^|[.?]\s+)(good|correct|right)\b|\b(that is|that's|this is|you are|you're|is|was) (good|correct|right)\b|\bcorrect\b|\b(good|nice|right) (move|choice|job|try|idea)\b/i;
const PLURAL_YOU = /\b(you all|y'all|yourselves|you guys|you two|you both)\b/i;
const EMOJI = /\p{Extended_Pictographic}/u;

/** Problems with one piece of text. sentence: it must end with a period or a question mark. */
export function wordProblems(text, { sentence = true, max = null, notation = true } = {}) {
  const out = [];
  if (notation && typeof text === 'string' && NOTATION.test(text)) out.push(`gives a move in notation ("${text.match(NOTATION)[0]}"); say it in words and draw it`);
  if (typeof text !== 'string' || !text.trim()) return ['is empty'];
  if (/[\u2014\u2013]| - |--/.test(text)) out.push('has a dash used as punctuation; use a comma, colon or period');
  if (/\bnew\b/i.test(text)) out.push('says "new"');
  if (text.includes('!')) out.push('has an exclamation mark');
  if (EMOJI.test(text)) out.push('has an emoji');
  if (PLURAL_YOU.test(text)) out.push('addresses the reader in the plural');
  if (PRAISE.test(text)) out.push(`praises ("${text.match(PRAISE)[0]}")`);
  else if (sentence && VERDICT.test(text)) out.push(`praises ("${text.match(VERDICT)[0].trim()}")`);
  const brit = text.toLowerCase().match(/[a-z]+/g)?.find(w => BRITISH.includes(w));
  if (brit) out.push(`uses British spelling ("${brit}")`);
  if (/\s{2,}/.test(text) || text !== text.trim()) out.push('has stray spaces');
  if (sentence && !/[.?]$/.test(text)) out.push('does not end with a period or a question mark');
  if (max && text.length > max) out.push(`is ${text.length} characters, over ${max}`);
  return out;
}

function words(faults, step, label, text, opts) {
  for (const p of wordProblems(text, opts)) faults.add(step, `${label} ${p}`);
}

// ---------------------------------------------------------------------------------------------------------
// Marks

function checkMarks(faults, step, marks, label = 'marks') {
  if (marks === undefined) return;
  if (!isObj(marks)) { faults.add(step, `${label} must be an object`); return; }
  for (const k of unknownKeys(marks, ['squares', 'arrows'])) faults.add(step, `${label} has an unknown field "${k}"`);
  if (marks.squares !== undefined) {
    if (!Array.isArray(marks.squares)) faults.add(step, `${label}.squares must be a list`);
    else for (const s of marks.squares) if (!SQUARE.test(s)) faults.add(step, `${label}.squares names "${s}", not a square`);
  }
  if (marks.arrows !== undefined) {
    if (!Array.isArray(marks.arrows)) faults.add(step, `${label}.arrows must be a list`);
    else for (const a of marks.arrows) {
      if (!Array.isArray(a) || a.length !== 2 || !SQUARE.test(a[0]) || !SQUARE.test(a[1])) faults.add(step, `${label}.arrows has ${JSON.stringify(a)}, not two squares`);
      else if (a[0] === a[1]) faults.add(step, `${label}.arrows has an arrow from ${a[0]} to itself`);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------
// One lesson

/**
 * Checks one lesson. ctx: { course, file } (the course folder it was found in and its file name), both
 * optional. Returns a Faults whose list is empty when the lesson passes. Also returns, on faults.moveSteps,
 * every move step with the position it starts from, for the engine check.
 */
export function checkLesson(lesson, ctx = {}) {
  const id = lesson && isStr(lesson.id) ? lesson.id : (ctx.file || 'lesson');
  const F = new Faults(id);
  F.moveSteps = [];
  const plain = !NOTATION_LESSONS.includes(id); // outside the notation lessons, nothing depends on notation
  const words = (faults, step, label, text, opts = {}) => {
    for (const p of wordProblems(text, { notation: plain, ...opts })) faults.add(step, `${label} ${p}`);
  };
  if (!isObj(lesson)) { F.add(null, 'is not an object'); return F; }
  for (const k of unknownKeys(lesson, LESSON_KEYS)) F.add(null, `has an unknown field "${k}"`);
  if (!isStr(lesson.id) || !ID.test(lesson.id)) F.add(null, 'id must be lowercase letters, digits and hyphens');
  if (!COURSES.includes(lesson.course)) F.add(null, `course "${lesson.course}" is not one of ${COURSES.join(', ')}`);
  else if (isStr(lesson.id) && !lesson.id.startsWith(lesson.course + '-')) F.add(null, `id must start with "${lesson.course}-"`);
  if (ctx.course && lesson.course !== ctx.course) F.add(null, `is in the ${ctx.course} folder but says course "${lesson.course}"`);
  if (ctx.file && ctx.file !== `${lesson.id}.json`) F.add(null, `file ${ctx.file} does not match id ${lesson.id}`);
  if (!isStr(lesson.title)) F.add(null, 'title is missing'); else words(F, null, 'title', lesson.title, { sentence: false, max: 60 });
  if (!isStr(lesson.line)) F.add(null, 'line is missing'); else words(F, null, 'line', lesson.line, {});
  if (lesson.side !== 'w' && lesson.side !== 'b') F.add(null, 'side must be "w" or "b"');
  if (!isStr(lesson.summary)) F.add(null, 'summary is missing'); else {
    words(F, null, 'summary', lesson.summary, { max: SUMMARY_MAX });
    // The summary is read with no board to mark, so it names no squares.
    if (plain) for (const sq of new Set(lesson.summary.match(/\b[a-h][1-8]\b/g) || [])) F.add(null, `summary names ${sq}; a summary names no squares`);
  }

  if (lesson.puzzles !== undefined && !THEMES.has(lesson.puzzles)) F.add(null, `puzzles "${lesson.puzzles}" is not a theme in puzzles/themes.json (${[...THEMES].join(', ')})`);
  if (lesson.practice !== undefined) {
    const p = lesson.practice;
    if (!isObj(p)) F.add(null, 'practice must be an object');
    else {
      for (const k of unknownKeys(p, ['fen', 'side'])) F.add(null, `practice has an unknown field "${k}"`);
      if (p.side !== 'w' && p.side !== 'b') F.add(null, 'practice side must be "w" or "b"');
      const why = fenProblem(p.fen);
      if (why) F.add(null, `practice fen ${why}`);
      else if (new Game(p.fen).outcome()) F.add(null, 'practice fen is a finished game');
    }
  }

  const steps = lesson.steps;
  if (!Array.isArray(steps)) { F.add(null, 'steps must be a list'); return F; }
  if (steps.length < 3 || steps.length > 10) F.add(null, `has ${steps.length} steps; a lesson has 3 to 10`);

  const reached = new Set(); // every position the lesson shows, for the practice check
  const seen = f => reached.add(f.split(' ').slice(0, 4).join(' '));
  let cur = null; // the FEN the next step without its own fen starts from
  let ambiguous = false; // the step before had several accepted moves leading to different positions
  steps.forEach((s, i) => {
    const n = i + 1;
    if (!isObj(s)) { F.add(n, 'is not an object'); cur = null; return; }
    const keys = STEP_KEYS[s.type];
    if (!keys) { F.add(n, `type "${s.type}" is not show, move or pick`); cur = null; return; }
    for (const k of unknownKeys(s, keys)) F.add(n, `has an unknown field "${k}"`);
    if (!isStr(s.text)) F.add(n, 'text is missing'); else words(F, n, 'text', s.text, { max: TEXT_MAX });
    if (s.side !== undefined && s.side !== 'w' && s.side !== 'b') F.add(n, 'side must be "w" or "b"');
    const side = s.side || lesson.side;
    checkMarks(F, n, s.marks);
    // Every square any line of the step names is shown on the board: ringed, or at either end of an arrow.
    if (plain) {
      const shown = new Set([...((s.marks && s.marks.squares) || []), ...((s.marks && s.marks.arrows) || []).flat()]);
      const lines = [['text', s.text], ['hint', s.hint], ['after', s.after],
        ...Object.entries(isObj(s.wrong) ? s.wrong : {}).map(([k, v]) => [`wrong line for ${k}`, v]),
        ...Object.entries(isObj(s.also) ? s.also : {}).map(([k, v]) => [`also line for ${k}`, v])];
      for (const [label, line] of lines) {
        if (!isStr(line)) continue;
        for (const sq of new Set(line.match(/\b[a-h][1-8]\b/g) || [])) if (!shown.has(sq)) F.add(n, `${label} names ${sq}, which is not marked on the board`);
      }
    }

    let fen;
    if (s.fen !== undefined) {
      const why = fenProblem(s.fen);
      if (why) { F.add(n, `fen ${why}`); cur = null; return; }
      fen = s.fen;
    } else if (i === 0) {
      F.add(n, 'the first step must have a fen'); cur = null; return;
    } else if (ambiguous) {
      F.add(n, 'needs a fen: the step before accepts moves that lead to different positions'); cur = null; return;
    } else if (!cur) {
      F.add(n, 'has no fen and the step before gives no position to continue from'); return;
    } else fen = cur;
    ambiguous = false;
    seen(fen);
    const g = new Game(fen);

    if (s.type === 'show') {
      cur = fen;
      if (s.play !== undefined) {
        if (!Array.isArray(s.play) || !s.play.length) { F.add(n, 'play must be a list of moves'); cur = null; return; }
        const r = playLine(fen, s.play);
        if (r.error) { F.add(n, `play: ${r.error}`); cur = null; return; }
        cur = r.game.fen();
        seen(cur);
      }
      return;
    }

    if (s.type === 'pick') {
      cur = fen;
      if (!Array.isArray(s.accept) || !s.accept.length) { F.add(n, 'accept must list at least one square'); return; }
      if (new Set(s.accept).size !== s.accept.length) F.add(n, 'accept lists a square twice');
      for (const sq of s.accept) if (!SQUARE.test(sq)) F.add(n, `accept names "${sq}", not a square`);
      if (s.all !== undefined && typeof s.all !== 'boolean') F.add(n, 'all must be true or false');
      // A pick that asks for a piece (and not for squares) must name squares with pieces on them.
      const asksPiece = !/\bsquares?\b/i.test(s.text || '') && /\b(piece|pieces|pawn|pawns|knight|knights|bishop|bishops|rook|rooks|queen|queens|king|kings)\b/i.test(s.text || '');
      if (asksPiece) for (const sq of s.accept) if (SQUARE.test(sq) && !pieceAt(g, sq)) F.add(n, `asks for a piece, but ${sq} is empty`);
      if (s.wrong !== undefined) {
        if (!isObj(s.wrong)) F.add(n, 'wrong must be an object');
        else for (const [sq, line] of Object.entries(s.wrong)) {
          if (!SQUARE.test(sq)) F.add(n, `wrong names "${sq}", not a square`);
          if (s.accept.includes(sq)) F.add(n, `${sq} is both accepted and wrong`);
          if (!isStr(line)) F.add(n, `wrong line for ${sq} is empty`); else words(F, n, `wrong line for ${sq}`, line, { max: TEXT_MAX });
        }
      }
      if (s.hint !== undefined) { if (!isStr(s.hint)) F.add(n, 'hint must be text'); else words(F, n, 'hint', s.hint, { max: TEXT_MAX }); }
      if (s.after !== undefined) { if (!isStr(s.after)) F.add(n, 'after must be text'); else words(F, n, 'after', s.after, { max: TEXT_MAX }); }
      return;
    }

    // move
    if (g.turn() !== side) F.add(n, `the player is on ${side === 'w' ? 'White' : 'Black'}'s side but ${g.turn() === 'w' ? 'White' : 'Black'} is to move`);
    if (!Array.isArray(s.accept) || !s.accept.length) { F.add(n, 'accept must list at least one move'); cur = null; return; }
    if (new Set(s.accept).size !== s.accept.length) F.add(n, 'accept lists a move twice');
    const legal = new Set(g.legal().map(m => m.uci));
    let bad = false;
    for (const m of s.accept) if (!legal.has(m)) { F.add(n, `accepted move ${m} is not legal here`); bad = true; }
    if (s.wrong !== undefined) {
      if (!isObj(s.wrong)) F.add(n, 'wrong must be an object');
      else for (const [m, line] of Object.entries(s.wrong)) {
        if (!legal.has(m)) F.add(n, `wrong move ${m} is not legal here`);
        if (s.accept.includes(m)) F.add(n, `${m} is both accepted and wrong`);
        if (!isStr(line)) F.add(n, `wrong line for ${m} is empty`); else words(F, n, `wrong line for ${m}`, line, { max: TEXT_MAX });
      }
    }
    if (s.also !== undefined) {
      if (!isObj(s.also)) F.add(n, 'also must be an object');
      else for (const [m, line] of Object.entries(s.also)) {
        if (!legal.has(m)) F.add(n, `also move ${m} is not legal here`);
        if (s.accept.includes(m)) F.add(n, `${m} is both accepted and in also`);
        if (s.wrong && s.wrong[m] !== undefined) F.add(n, `${m} is both wrong and in also`);
        if (!isStr(line)) F.add(n, `also line for ${m} is empty`); else words(F, n, `also line for ${m}`, line, { max: TEXT_MAX });
      }
    }
    if (s.hint !== undefined) { if (!isStr(s.hint)) F.add(n, 'hint must be text'); else words(F, n, 'hint', s.hint, { max: TEXT_MAX }); }
    if (s.after !== undefined) { if (!isStr(s.after)) F.add(n, 'after must be text'); else words(F, n, 'after', s.after, { max: TEXT_MAX }); }
    if (s.taught !== undefined && s.taught !== true) F.add(n, 'taught, when given, is true');
    if (s.mate !== undefined && s.mate !== true) F.add(n, 'mate, when given, is true');
    if (s.wins !== undefined && !(Number.isInteger(s.wins) && s.wins > 0)) F.add(n, 'wins must be a whole number of points above 0');
    if (bad) { cur = null; return; }

    // Replies, and where the next step starts.
    const replyFor = m => (isObj(s.reply) ? s.reply[m] : s.reply);
    if (s.reply !== undefined && !isStr(s.reply) && !isObj(s.reply)) F.add(n, 'reply must be a move or an object of moves');
    if (isObj(s.reply)) for (const k of Object.keys(s.reply)) if (!s.accept.includes(k)) F.add(n, `reply is given for ${k}, which is not accepted`);
    const ends = new Set();
    for (const m of s.accept) {
      const after = new Game(fen);
      after.play(m);
      seen(after.fen());
      const r = replyFor(m);
      if (r !== undefined) {
        if (after.outcome()) F.add(n, `reply ${r} comes after ${m} has ended the game`);
        else if (!UCI.test(r) || !after.play(r)) F.add(n, `reply ${r} is not legal after ${m}`);
      }
      seen(after.fen());
      ends.add(after.fen());
    }
    cur = [...ends][0];
    if (ends.size > 1) ambiguous = true;

    // Claims.
    for (const m of s.accept) {
      const mates = isMate(fen, m);
      if (s.mate && !mates) F.add(n, `claims mate, but ${san(fen, m)} is not checkmate`);
      if (!s.mate && mates) F.add(n, `${san(fen, m)} is checkmate: mark the step "mate": true`);
      if (s.wins) {
        const why = winsProblem(fen, m, s.wins);
        if (why) F.add(n, `claims it wins ${s.wins}, but ${why}`);
      }
    }
    // An accepted move never gives material away: once the captures on the board are played out, the player
    // is not behind where they started. Moves marked taught (gambits, main lines) are left to the engine.
    if (s.sacrifice !== undefined && s.sacrifice !== true) F.add(n, 'sacrifice must be true or left out');
    if (s.sacrifice && s.taught) F.add(n, 'a step is a sacrifice or taught, not both');
    if (s.sacrifice && s.accept.every(m => !losesMaterial(fen, m))) F.add(n, 'is marked a sacrifice, but the move gives nothing up');
    // A sacrifice gives material up on purpose; the engine check must then find the player clearly ahead.
    if (!s.taught && !s.wins && !s.mate && !s.sacrifice) for (const m of s.accept) {
      const why = losesMaterial(fen, m);
      if (why) F.add(n, `accepted move ${san(fen, m)} loses material: ${why}`);
    }
    if (!s.wins && !s.mate && /\b(win|wins|winning|won)\b/i.test(`${s.text} ${s.after || ''}`)) {
      F.add(n, 'says it wins something but carries no "wins" claim');
    }
    F.moveSteps.push({ n, fen, step: s });
  });
  // The practice position is where the lesson leads: it must be one the lesson reaches.
  const p = lesson.practice;
  if (isObj(p) && isStr(p.fen) && !fenProblem(p.fen) && !reached.has(p.fen.split(' ').slice(0, 4).join(' '))) {
    F.add(null, 'practice fen is not a position the lesson reaches');
  }
  return F;
}

// ---------------------------------------------------------------------------------------------------------
// The index

/** Checks the index on its own and against the lessons. lessons: Map id -> { lesson, course }. */
export function checkIndex(index, lessons) {
  const F = new Faults('index');
  if (!isObj(index)) { F.add(null, 'is not an object'); return F; }
  for (const k of unknownKeys(index, INDEX_KEYS)) F.add(null, `has an unknown field "${k}"`);
  if (index.version !== 1) F.add(null, 'version must be 1');
  if (!Array.isArray(index.courses) || !index.courses.length) { F.add(null, 'courses must be a list'); return F; }
  const listed = new Set();
  let lastCourse = -1;
  for (const c of index.courses) {
    F.about = null;
    if (!isObj(c)) { F.add(null, 'a course is not an object'); continue; }
    F.about = { course: c.id };
    const where = `course ${c.id}`;
    for (const k of unknownKeys(c, COURSE_KEYS)) F.add(null, `${where} has an unknown field "${k}"`);
    const ci = COURSES.indexOf(c.id);
    if (ci < 0) F.add(null, `${where} is not one of ${COURSES.join(', ')}`);
    else if (ci <= lastCourse) F.add(null, `${where} is out of order or listed twice`);
    lastCourse = Math.max(lastCourse, ci);
    if (!isStr(c.title)) F.add(null, `${where} has no title`); else words(F, null, `${where} title`, c.title, { sentence: false });
    if (!isStr(c.line)) F.add(null, `${where} has no line`); else words(F, null, `${where} line`, c.line, {});
    if (!Array.isArray(c.chapters) || !c.chapters.length) { F.add(null, `${where} has no chapters`); continue; }
    const chapterIds = new Set();
    for (const ch of c.chapters) {
      F.about = { course: c.id };
      if (!isObj(ch)) { F.add(null, `${where} has a chapter that is not an object`); continue; }
      F.about = { course: c.id, chapter: ch.id };
      const cw = `${where}, chapter ${ch.id}`;
      const opening = OPENING_KEYS.some(k => ch[k] !== undefined);
      for (const k of unknownKeys(ch, opening ? [...CHAPTER_KEYS, ...OPENING_KEYS] : CHAPTER_KEYS)) F.add(null, `${cw} has an unknown field "${k}"`);
      if (!isStr(ch.id) || !ID.test(ch.id)) F.add(null, `${cw}: id must be lowercase letters, digits and hyphens`);
      else if (chapterIds.has(ch.id)) F.add(null, `${cw} is listed twice`);
      chapterIds.add(ch.id);
      if (!isStr(ch.title)) F.add(null, `${cw} has no title`); else words(F, null, `${cw} title`, ch.title, { sentence: false });
      if (opening) {
        if (c.id !== 'openings') F.add(null, `${cw} has opening fields outside the openings course`);
        for (const k of OPENING_KEYS) if (ch[k] === undefined) F.add(null, `${cw} is an opening but has no ${k}`);
        if (ch.for !== undefined && !GROUPS[ch.for]) F.add(null, `${cw}: for must be white or black, the side that chooses the opening`);
        else if (ch.group !== undefined && !GROUPS[ch.for].includes(ch.group)) F.add(null, `${cw}: group "${ch.group}" is not one of ${GROUPS[ch.for].join(', ')}`);
        if (ch.line !== undefined) { if (!isStr(ch.line)) F.add(null, `${cw} line must be text`); else words(F, null, `${cw} line`, ch.line, {}); }
        if (ch.group !== undefined && isStr(ch.group) && NOTATION.test(ch.group)) F.add(null, `${cw} group has notation in it`);
        if (ch.play !== undefined) {
          if (!Array.isArray(ch.play) || !ch.play.length) F.add(null, `${cw}: play must be a list of moves`);
          else {
            const r = playLine(START_FEN, ch.play);
            if (r.error) F.add(null, `${cw}: play from the start: ${r.error}`);
            else {
              if (ch.fen !== r.game.fen()) F.add(null, `${cw}: fen is not the position after play (${r.game.fen()})`);
              const hit = OPENINGS[r.game.key()];
              const name = hit ? hit.split('|')[1] : null;
              if (!name) F.add(null, `${cw}: the opening table has no name for the position after play`);
              else if (name !== ch.title && !name.startsWith(ch.title + ':') && !name.split(': ').includes(ch.title)) F.add(null, `${cw}: the opening table calls this "${name}", not "${ch.title}"`);
              if (isStr(ch.moves)) {
                const m = playNotation(ch.moves);
                if (m.error) F.add(null, `${cw}: moves "${ch.moves}": ${m.error}`);
                else if (m.game.moves().map(x => x.uci).join(' ') !== ch.play.join(' ')) F.add(null, `${cw}: moves "${ch.moves}" are not the same moves as play`);
              }
            }
          }
        }
      }
      if (!Array.isArray(ch.lessons) || !ch.lessons.length) { F.add(null, `${cw} has no lessons; only lessons that exist are listed`); continue; }
      for (const e of ch.lessons) {
        F.about = { course: c.id, chapter: ch.id };
        if (!isObj(e)) { F.add(null, `${cw} has a lesson that is not an object`); continue; }
        F.about = { course: c.id, chapter: ch.id, lesson: e.id };
        const ew = `lesson ${e.id}`;
        for (const k of unknownKeys(e, ENTRY_KEYS)) F.add(null, `${ew} has an unknown field "${k}"`);
        if (listed.has(e.id)) F.add(null, `${ew} is listed twice`);
        listed.add(e.id);
        const why = fenProblem(e.fen);
        if (why) F.add(null, `${ew}: fen ${why}`);
        if (e.side !== 'w' && e.side !== 'b') F.add(null, `${ew}: side must be "w" or "b"`);
        checkMarks(F, null, e.marks, `${ew} marks`);
        const found = lessons && lessons.get(e.id);
        if (!found) { F.add(null, `${ew} is listed but has no file in ${c.id}/`); continue; }
        if (found.lesson.course !== c.id) F.add(null, `${ew} is listed under ${c.id} but its course is ${found.lesson.course}`);
        if (found.lesson.title !== e.title) F.add(null, `${ew}: the index title "${e.title}" differs from the lesson's "${found.lesson.title}"`);
        if (found.lesson.line !== e.line) F.add(null, `${ew}: the index line differs from the lesson's`);
      }
    }
  }
  if (lessons) for (const id of lessons.keys()) if (!listed.has(id)) { F.about = { course: lessons.get(id).course, lesson: id }; F.add(null, `lesson ${id} has a file but is missing from the index`); }
  F.about = null;
  return F;
}

// ---------------------------------------------------------------------------------------------------------
// Loading

/** Reads index.json and every lesson file under dir. Returns { index, lessons, faults }. */
export function loadTree(dir = here) {
  const faults = [];
  let index = null;
  try { index = JSON.parse(fs.readFileSync(path.join(dir, 'index.json'), 'utf8')); } catch (e) {
    faults.push({ where: 'index', step: null, msg: `cannot be read (${e.message})` });
  }
  const lessons = new Map();
  for (const course of COURSES) {
    const cdir = path.join(dir, course);
    if (!fs.existsSync(cdir)) continue;
    for (const file of fs.readdirSync(cdir).filter(f => f.endsWith('.json')).sort()) {
      let lesson;
      try { lesson = JSON.parse(fs.readFileSync(path.join(cdir, file), 'utf8')); } catch (e) {
        faults.push({ where: `${course}/${file}`, step: null, msg: `cannot be read (${e.message})`, about: { course, lesson: file.replace(/\.json$/, '') } });
        continue;
      }
      const id = lesson && lesson.id ? lesson.id : file.replace(/\.json$/, '');
      if (lessons.has(id)) faults.push({ where: id, step: null, msg: 'exists twice', about: { course, lesson: id } });
      lessons.set(id, { lesson, course, file });
    }
  }
  return { index, lessons, faults };
}

/** Lesson ids in index order (then any not in the index). */
function order(index, lessons) {
  const ids = [];
  for (const c of (index && index.courses) || []) for (const ch of c.chapters || []) for (const e of ch.lessons || []) if (e && lessons.has(e.id) && !ids.includes(e.id)) ids.push(e.id);
  for (const id of lessons.keys()) if (!ids.includes(id)) ids.push(id);
  return ids;
}

// ---------------------------------------------------------------------------------------------------------
// The engine

/** A score for the side to move, as a number: mates are large and ordered. */
function scoreValue(line) {
  if (line.mate !== undefined) return line.mate > 0 ? 100000 - line.mate : -100000 - line.mate;
  return line.cp;
}

/**
 * Asks Stockfish through the calibration Player (engines/calibrate/play.mjs) and the app's EngineHost.
 * Every search starts from a cleared hash with a fixed node budget, so results repeat.
 */
export class Engine {
  constructor({ nodes = 1000000 } = {}) { this.nodes = nodes; this.player = null; this.cache = new Map(); }
  async open() {
    const { Player } = await import('../../engines/calibrate/play.mjs');
    this.player = new Player('stockfish');
  }
  close() { if (this.player) this.player.close(); }
  /** { move, score } for the side to move at fen; score in centipawns (mates as large numbers). */
  async best(fen) {
    const key = 'b ' + fen;
    if (this.cache.has(key)) return this.cache.get(key);
    await this.player.newGame();
    const r = await this.player.host.search({ fen }, { options: [['MultiPV', '1']], nodes: this.nodes });
    const line = r.lines.find(l => l.multipv === 1) || r.lines[0];
    const out = { move: r.bestmove, score: line ? scoreValue(line) : 0 };
    this.cache.set(key, out);
    return out;
  }
  /** Every legal move's score at fen from one search (MultiPV over all of them): { uci: score }. */
  async all(fen) {
    const key = 'm ' + fen;
    if (this.cache.has(key)) return this.cache.get(key);
    const n = new Game(fen).legal().length;
    await this.player.newGame();
    const r = await this.player.host.search({ fen }, { options: [['MultiPV', String(n)]], nodes: this.nodes * 2 });
    const out = {};
    for (const l of r.lines) if (l.move) out[l.move] = scoreValue(l);
    this.cache.set(key, out);
    return out;
  }

  /** The score of one move for the side that plays it. */
  async after(fen, move) {
    const key = 'a ' + fen + ' ' + move;
    if (this.cache.has(key)) return this.cache.get(key);
    const g = new Game(fen);
    g.play(move);
    const o = g.outcome();
    let score;
    if (o) score = o.reason === 'checkmate' ? 100000 : 0;
    else score = -(await this.best(g.fen())).score;
    this.cache.set(key, score);
    return score;
  }
}

function showScore(v) {
  if (v === 100000) return 'checkmate';
  if (v >= 90000) return `mate in ${100000 - v}`;
  if (v <= -90000) return `mated in ${100000 + v}`;
  return (v >= 0 ? '+' : '') + (v / 100).toFixed(2);
}

/**
 * True when the step's words name its move outright, so no other move fits them: the text gives an accepted
 * move in notation ("Play Nf3"), or names its destination square when every legal move to that square is
 * accepted or has an also or wrong line ("Push the pawn to e8").
 */
function namesTheMove(fen, step) {
  const text = step.text || '';
  const legal = new Game(fen).legal();
  const covered = new Set([...step.accept, ...Object.keys(step.also || {}), ...Object.keys(step.wrong || {})]);
  for (const m of step.accept) {
    const name = san(fen, m).replace(/[+#]$/, '');
    if (new RegExp(`(^|[^A-Za-z0-9])${name.replace(/[-=]/g, c => '\\' + c)}($|[^A-Za-z0-9])`).test(text)) return true;
    const to = m.slice(2, 4);
    if (new RegExp(`\\b${to}\\b`).test(text) && legal.filter(x => x.to === to).every(x => covered.has(x.uci))) return true;
  }
  return false;
}

/** How far a score falls short of the best, in centipawns; two forced mates for the mover count as equal. */
function shortfall(best, got) {
  if (best >= 90000 && got >= 90000) return 0;
  return best - got;
}

/**
 * The engine check for one lesson's move steps. Returns faults; log gets one line per move looked at.
 * Accepted moves: within half a pawn of the best (a pawn and a half when taught). Also: within half a pawn.
 * Wrong: more than half a pawn worse. Wins: Stockfish rates the player more than half a pawn ahead.
 */
export async function checkEngine(lessonId, moveSteps, engine, log = () => {}, course = null) {
  const F = new Faults(lessonId);
  let looked = 0;
  for (const { n, fen, step } of moveSteps) {
    looked++;
    const best = await engine.best(fen);
    const bestScore = await engine.after(fen, best.move);
    const bestName = `${san(fen, best.move)} at ${showScore(bestScore)}`;
    for (const m of step.accept) {
      const v = m === best.move ? bestScore : await engine.after(fen, m);
      log(`${lessonId} step ${n}: accept ${san(fen, m)} ${showScore(v)}, best ${bestName}`);
      const margin = step.taught ? TAUGHT_MARGIN : ENGINE_MARGIN;
      // A move that leaves the player five pawns up is winning plainly; a still bigger win elsewhere is no fault.
      if (shortfall(bestScore, v) > margin && v < DECISIVE) {
        F.add(n, `Stockfish rates ${san(fen, m)} at ${showScore(v)}, more than ${step.taught ? 'a pawn and a half' : 'half a pawn'} below ${bestName}`);
      }
      if (step.sacrifice && v <= SACRIFICE_AHEAD) F.add(n, `is marked a sacrifice, but Stockfish rates ${san(fen, m)} at ${showScore(v)}, not clearly ahead`);
      if (step.wins && v <= AHEAD) F.add(n, `claims it wins ${step.wins}, but Stockfish rates ${san(fen, m)} at ${showScore(v)}, not ahead`);
    }
    // Basics: a beginner who plays a move as good as the accepted one is never told no. Every such move is
    // accepted, or carries an also or wrong line. One search scores every move on the same footing.
    // In Basics every move is scored by one search, so the scan, also and wrong use the same footing.
    const all = course === 'basics' ? await engine.all(fen) : null;
    const top = all ? Math.max(...step.accept.map(m => all[m] ?? -Infinity)) : null;
    const scoreOf = async m => (all && all[m] !== undefined ? all[m] : m === best.move ? bestScore : engine.after(fen, m));
    const ref = all ? top : bestScore;
    if (all && !namesTheMove(fen, step)) {
      const covered = new Set([...step.accept, ...Object.keys(step.also || {}), ...Object.keys(step.wrong || {})]);
      for (const [m, v] of Object.entries(all)) {
        if (covered.has(m)) continue;
        // Against an accepted mate in one only another mate in one is as good; otherwise two forced mates are.
        const equal = top === 99999 ? v === 99999 : shortfall(top, v) <= ENGINE_MARGIN;
        if (equal) F.add(n, `${san(fen, m)} (${showScore(v)}) is about as good as the accepted move but is not accepted and has no also or wrong line`);
      }
    }
    for (const m of Object.keys(step.also || {})) {
      const v = await scoreOf(m);
      log(`${lessonId} step ${n}: also ${san(fen, m)} ${showScore(v)}`);
      if (shortfall(ref, v) > ENGINE_MARGIN && v < DECISIVE) F.add(n, `has an also line for ${san(fen, m)} at ${showScore(v)}, more than half a pawn below ${bestName}: make it wrong`);
    }
    for (const m of Object.keys(step.wrong || {})) {
      const v = await scoreOf(m);
      log(`${lessonId} step ${n}: wrong ${san(fen, m)} ${showScore(v)}`);
      if (shortfall(ref, v) <= ENGINE_MARGIN) F.add(n, `has a wrong line for ${san(fen, m)} at ${showScore(v)}, within half a pawn of ${bestName}: use also, or drop the line`);
    }
  }
  F.looked = looked;
  return F;
}

// ---------------------------------------------------------------------------------------------------------
// Everything

/**
 * Checks a tree of lessons. Options: dir, engine (an Engine, or null for no engine check), all (go on past
 * the first faulty lesson), only (lesson ids), log. Returns { ok, faults, lessons, passed, engineSteps }.
 */
export async function checkTree({ dir = here, engine = null, all = false, only = null, courses = null, scope = null, log = () => {} } = {}) {
  const { index, lessons, faults } = loadTree(dir);
  // With courses or a scope given, faults that belong to other courses or chapters are set aside, so several
  // people can write at once. Whose a fault is comes from its `about` record, never from its words; a fault
  // with no owner (the index cannot be read, its version is wrong) is everyone's and is always kept.
  // A lesson may be listed in more than one chapter by mistake: every listing counts, so the fault shows
  // to whoever checks any of those chapters.
  const chaptersOf = new Map();
  for (const c of (index && index.courses) || []) for (const ch of (c && c.chapters) || []) for (const e of (ch && ch.lessons) || []) if (e && e.id) chaptersOf.set(e.id, [...(chaptersOf.get(e.id) || []), ch.id]);
  const inScope = id => !scope || scope.some(x => id.startsWith(x) || (chaptersOf.get(id) || []).includes(x));
  // A lesson belongs to the course of its folder, of its own `course` field and of its id: a file in the wrong
  // folder is still checked by whoever checks the course it claims.
  const coursesOf = id => { const l = lessons.get(id); return l ? [l.course, l.lesson && l.lesson.course, String(id).split('-')[0]] : [String(id).split('-')[0]]; };
  const inCourses = id => !courses || coursesOf(id).some(c => courses.includes(c));
  const mine = f => {
    const a = f.about;
    if (!a || (!a.course && !a.lesson)) return true;
    if (courses && a.course && !courses.includes(a.course) && !(a.lesson && inCourses(a.lesson))) return false;
    if (!scope) return true;
    if (a.lesson) return inScope(a.lesson) || (a.chapter !== undefined && scope.includes(a.chapter));
    if (a.chapter !== undefined) return scope.includes(a.chapter);
    return true; // about a whole course: kept
  };
  // A course or scope that names nothing is a mistake in the command, not a pass.
  const naming = [];
  for (const c of courses || []) if (!COURSES.includes(c)) naming.push({ where: 'command', step: null, msg: `--course ${c} is not one of ${COURSES.join(', ')}` });
  const chapterIds = new Set([...chaptersOf.values()].flat());
  for (const x of scope || []) if (!chapterIds.has(x) && ![...lessons.keys()].some(id => id.startsWith(x))) naming.push({ where: 'command', step: null, msg: `--scope ${x} names no chapter and no lesson` });
  if (naming.length) return { ok: false, faults: naming, lessons: 0, passed: 0, engineSteps: 0 };
  const loadFaults = faults.filter(mine);
  const out = { ok: false, faults: [...loadFaults], lessons: 0, passed: 0, engineSteps: 0 };
  if (loadFaults.length && !all) return out;
  if (index) {
    const fi = checkIndex(index, lessons).list.filter(mine);
    out.faults.push(...fi);
    if (fi.length && !all) return out;
  }
  for (const id of order(index, lessons)) {
    if (only && !only.includes(id)) continue;
    if (!inCourses(id)) continue;
    if (!inScope(id)) continue;
    const { lesson, course, file } = lessons.get(id);
    out.lessons++;
    const F = checkLesson(lesson, { course, file });
    let list = F.list;
    if (F.ok && engine) {
      const E = await checkEngine(id, F.moveSteps, engine, log, lesson.course);
      out.engineSteps += E.looked;
      list = E.list;
    }
    out.faults.push(...list);
    if (list.length) { if (!all) return out; } else out.passed++;
  }
  if (out.lessons === 0 && !out.faults.length) out.faults.push({ where: 'command', step: null, msg: 'no lesson was checked' });
  out.ok = out.faults.length === 0;
  return out;
}

// ---------------------------------------------------------------------------------------------------------
// Command line

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const args = process.argv.slice(2);
  const has = f => args.includes(f);
  const ni = args.indexOf('--nodes');
  const nodes = ni >= 0 ? Number(args[ni + 1]) : 1000000;
  const ci = args.indexOf('--course');
  const courses = ci >= 0 ? String(args[ci + 1] || '').split(',').filter(Boolean) : null;
  const si = args.indexOf('--scope');
  const scope = si >= 0 ? String(args[si + 1] || '').split(',').filter(Boolean) : null;
  const only = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && ['--nodes', '--course', '--scope'].includes(args[i - 1])));
  let engine = null;
  if (has('--engine')) { engine = new Engine({ nodes }); await engine.open(); }
  const verbose = has('--verbose');
  let r;
  try {
    r = await checkTree({ engine, all: has('--all'), only: only.length ? only : null, courses, scope, log: verbose ? l => console.log('  ' + l) : () => {} });
  } finally {
    if (engine) engine.close();
  }
  for (const f of r.faults) console.log(formatFault(f));
  const tail = engine ? `, ${r.engineSteps} move steps checked by Stockfish at ${nodes} nodes` : '';
  console.log(`${r.passed} of ${r.lessons} lessons pass${tail}.${r.ok ? '' : ' Faults above.'}`);
  process.exit(r.ok ? 0 : 1);
}
