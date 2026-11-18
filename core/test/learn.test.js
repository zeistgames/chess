// Learn as you play: the shared cases (core/learn/cases.json, also read by the app's tests), the lesson table, and
// the words.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cards } from '../learn/cards.js';
import { lessonFor, openingChapter } from '../learn/lessons.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = p => JSON.parse(fs.readFileSync(path.join(here, p), 'utf8'));
const CASES = read('../learn/cases.json').cases;
const TABLE = read('../learn/lessons.json').lessons;
const INDEX = read('../lessons/index.json');
const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

const brief = c => ({ kind: c.kind, side: c.side, ply: c.ply, shows: c.shows, title: c.title, line: c.line, ...(c.name ? { name: c.name } : {}) });
const run = (c, moves, over) => cards({ moves, player: c.player, fen: c.fen ?? START, learn: c.learn !== false, over }).map(brief);

for (const c of CASES) {
  test(`case: ${c.name}`, () => {
    assert.deepEqual(run(c, c.moves, !!c.over), c.cards);
    // Move by move: exactly the cards whose moment has come, never one early (and never about the opponent while
    // the player still has to answer it).
    for (let n = 0; n < c.moves.length; n++) {
      assert.deepEqual(run(c, c.moves.slice(0, n), false), c.cards.filter(x => x.shows <= n), `after ${n} moves`);
    }
  });
}

test('the cases cover what the spec names, and the negatives', () => {
  const kinds = new Set(CASES.flatMap(c => c.cards.map(x => x.kind)));
  for (const k of ['opening', 'fork', 'pin', 'skewer', 'discovered-attack', 'castling', 'en-passant', 'hanging', 'back-rank-mate',
                   'smothered-mate', 'discovered-check', 'double-check', 'stalemate', 'promotion', 'underpromotion']) assert.ok(kinds.has(k), k);
  assert.ok(CASES.some(c => c.learn === false && c.cards.length === 0), 'nothing outside Learn');
  assert.ok(CASES.some(c => c.cards.length === 0 && c.learn !== false), 'a pattern that wins nothing gives no card');
});

test('the cache gives the same cards as a fresh look, move by move and after a move is taken back', () => {
  const c = CASES.find(x => x.moves.length > 40);
  const all = run(c, c.moves, false);
  for (let n = 30; n <= c.moves.length; n++) run(c, c.moves.slice(0, n), false);
  assert.deepEqual(run(c, c.moves.slice(0, 20), false), c.cards.filter(x => x.shows <= 20), 'taken back to move 20');
  assert.deepEqual(run(c, c.moves, false), all);
});

test('every lesson the table names is in the index', () => {
  const ids = new Set(INDEX.courses.flatMap(c => c.chapters.flatMap(ch => ch.lessons.map(l => l.id))));
  for (const [kind, id] of Object.entries(TABLE)) assert.ok(ids.has(id), `${kind} names ${id}, not in core/lessons/index.json`);
});

test('a card opens its lesson; an opening its chapter by title; none when there is none', () => {
  assert.deepEqual(lessonFor({ kind: 'fork' }, INDEX, TABLE), { lesson: 'tactics-fork' });
  assert.equal(lessonFor({ kind: 'nothing-known' }, INDEX, TABLE), null);
  const openings = { chapters: [{ id: 'qg', title: "Queen's Gambit" }, { id: 'qgd', title: "Queen's Gambit Declined" }, { id: 'sic', title: 'Sicilian Defense' }] };
  assert.equal(openingChapter('Sicilian Defense: Najdorf Variation', openings).id, 'sic');
  assert.equal(openingChapter("Queen's Gambit Declined: Exchange Variation", openings).id, 'qgd', 'the longest title');
  assert.equal(openingChapter("Queen's Gambit Accepted", openings).id, 'qg');
  assert.equal(openingChapter("King's Pawn Game", openings), null);
  assert.equal(openingChapter('Sicilian', openings), null, 'a title is never matched by a part of it');
  assert.equal(lessonFor({ kind: 'opening', name: 'Nowhere Opening' }, INDEX, TABLE), null);
  const more = { chapters: [{ id: 'qg', title: "Queen's Gambit" }, { id: 'albin', title: 'Albin Countergambit' }, { id: 'london', title: 'London System' }] };
  assert.equal(openingChapter("Queen's Gambit Declined: Albin Countergambit", more).id, 'albin', 'a part is more specific');
  assert.equal(openingChapter('London System, with Bd3', more).id, 'london', 'a part before a comma');
  assert.equal(openingChapter('Indian Defense: London System', more).id, 'london', 'a later part');
  assert.equal(openingChapter('Indian Defense: London System, with e3', more).id, 'london');
});

test('the words: plain, ending with a period, no exclamation marks or dashes', () => {
  for (const c of CASES) {
    for (const x of cards({ moves: c.moves, player: c.player, fen: c.fen ?? START, over: true })) {
      if (x.kind === 'opening') continue;
      assert.match(x.line, /^[A-Z][^!—–]*\.$/, x.line);
      assert.ok(!/ - |--/.test(x.line), x.line);
      assert.ok(!/\bnew\b|good|great|nice|well done|brilliant/i.test(x.line), x.line);
    }
  }
});
