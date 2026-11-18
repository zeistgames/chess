import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkLesson, checkIndex, checkTree, checkEngine, Engine, formatFault, winsProblem, wordProblems, losesMaterial } from '../lessons/check.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const AFTER_E4_E5 = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
const FORK = 'r1b1kbnr/pp2pppp/8/3N4/5B2/8/PPP2PPP/R4RK1 w kq - 0 1';

/** A small lesson that passes: a show, a move with a reply, a pick on the position that follows, a claim. */
function good() {
  return {
    id: 'tactics-test-fork',
    course: 'tactics',
    title: 'A test fork',
    line: 'One knight move attacks the king and the rook.',
    side: 'w',
    steps: [
      { type: 'show', fen: FORK, text: 'The knight on d5 can reach c7.', marks: { squares: ['c7'], arrows: [['d5', 'c7']] } },
      { type: 'move', text: 'Fork the king and the rook.', marks: { squares: ['f8'] }, accept: ['d5c7'], wrong: { d5e7: 'That takes a pawn, but the bishop on f8 takes the knight back.' }, reply: 'e8d7', wins: 5, after: 'Check, and the rook is attacked too.' },
      { type: 'pick', text: 'Tap the piece the knight takes next.', accept: ['a8'], all: false },
    ],
    summary: 'A fork attacks two pieces at once.',
    practice: { fen: FORK, side: 'w' },
  };
}

const messages = F => F.list.map(formatFault);
const has = (F, re) => assert.ok(F.list.some(f => re.test(f.msg)), `expected a fault matching ${re}, got: ${messages(F).join(' | ') || 'none'}`);

test('a good lesson passes', () => {
  const F = checkLesson(good(), { course: 'tactics', file: 'tactics-test-fork.json' });
  assert.deepEqual(messages(F), []);
});

test('an illegal FEN fails, naming the step', () => {
  const l = good();
  l.steps[0].fen = 'r1b1kbnr/pp2pppp/8/3N4/5B2/8/PPP2PPP/R4R2 w kq - 0 1'; // no white king
  const F = checkLesson(l);
  has(F, /^fen .*king/);
  assert.equal(F.list[0].step, 1);
  const l2 = good();
  l2.steps[0].fen = '4k3/8/8/8/8/8/8/R3K3 w - - 0 1'.replace('4k3', '4k2R'); // the side not to move is in check
  has(checkLesson(l2), /side not to move in check/);
});

test('an illegal accepted move fails', () => {
  const l = good();
  l.steps[1].accept = ['d5d7'];
  const F = checkLesson(l);
  has(F, /accepted move d5d7 is not legal here/);
  assert.equal(F.list.find(f => /d5d7/.test(f.msg)).step, 2);
});

test('a wins claim fails when a defense holds the material', () => {
  // Nxe5 takes a pawn, but Black takes the knight back: nothing is won.
  const fen = 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
  assert.match(winsProblem(fen, 'f3e5', 1), /after Nxe5 Nxe5/);
  const l = good();
  l.steps = [
    { type: 'move', fen, text: 'Take the pawn on e5.', accept: ['f3e5'], wins: 1 },
    { type: 'show', text: 'The knight is gone.' },
    { type: 'show', text: 'So was the pawn.' },
  ];
  delete l.practice;
  has(checkLesson(l), /claims it wins 1, but after Nxe5/);
  // The fork itself does win the rook.
  assert.equal(winsProblem(FORK, 'd5c7', 5), null);
});

test('a mate claim that is not checkmate fails, and a mate without the claim fails', () => {
  const l = good();
  l.steps[1].mate = true;
  has(checkLesson(l), /claims mate, but Nc7\+ is not checkmate/);
  const m = good();
  m.steps = [
    { type: 'move', fen: '6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1', text: 'Mate on the back rank.', accept: ['d1d8'] },
    { type: 'show', text: 'The king has no square.' },
    { type: 'show', text: 'The game is over.' },
  ];
  has(checkLesson(m), /is checkmate: mark the step "mate": true/);
});

test('a move both accepted and wrong, and an unknown field, fail', () => {
  const l = good();
  l.steps[1].wrong = { d5c7: 'That is the move.' };
  l.steps[1].colour = 'red';
  const F = checkLesson(l);
  has(F, /d5c7 is both accepted and wrong/);
  has(F, /unknown field "colour"/);
});

test('continuity: a step without a fen continues from the move and reply before it', () => {
  const l = good();
  l.steps[1].reply = 'e8d8';
  l.steps.push({ type: 'move', text: 'Take the rook.', accept: ['c7a8'] }); // the knight stands on c7 now
  assert.deepEqual(messages(checkLesson(l)), []);
  l.steps[3].accept = ['d5b6']; // the knight left d5 two steps ago
  has(checkLesson(l), /accepted move d5b6 is not legal here/);
  l.steps[1].reply = 'e8e7'; // e7 holds a black pawn
  has(checkLesson(l), /reply e8e7 is not legal after d5c7/);
});

test('word rules: dash, "new", exclamation mark, praise, British spelling, missing period, length', () => {
  const cases = [
    ['The knight jumps — far.', /dash/],
    ['The knight jumps – far.', /dash/],
    ['The knight jumps - far.', /dash/],
    ['The knight jumps -- far.', /dash/],
    ['Good.', /praises/],
    ['That is correct.', /praises/],
    ['Right, the rook falls.', /praises/],
    ['Nice move.', /praises/],
    ['Well done.', /praises/],
    ['A new idea.', /says "new"/],
    ['Take it!', /exclamation/],
    ['Great move.', /praises/],
    ['Take the centre.', /British spelling/],
    ['Take the rook', /does not end with a period or a question mark/],
    ['You all know this.', /plural/],
  ];
  for (const [text, re] of cases) assert.ok(wordProblems(text).some(p => re.test(p)), text);
  assert.ok(wordProblems('x'.repeat(140) + '.', { max: 140 }).some(p => /over 140/.test(p)));
  assert.deepEqual(wordProblems('Take the rook on a8.'), []);
  assert.deepEqual(wordProblems('Which piece is undefended?'), []);
  assert.deepEqual(wordProblems('Yes.'), []);
  assert.deepEqual(wordProblems('The rook moves to the right, onto a well-guarded square.'), []);
  assert.deepEqual(wordProblems('Good and bad trades', { sentence: false }), []);
  const l = good();
  l.steps[1].after = 'Brilliant!';
  const F = checkLesson(l);
  has(F, /after has an exclamation mark/);
  has(F, /after praises/);
});

test('also lines: allowed on move steps, never on an accepted or wrong move; pick may carry a hint', () => {
  const l = good();
  l.steps[1].also = { f1d1: 'That is strong too. This lesson goes on with the fork.' };
  l.steps[2].hint = 'Look at the corner.';
  assert.deepEqual(messages(checkLesson(l)), []);
  l.steps[1].also = { d5c7: 'That works.', d5e7: 'That works too.' };
  const F = checkLesson(l);
  has(F, /d5c7 is both accepted and in also/);
  has(F, /d5e7 is both wrong and in also/);
});

test('an accepted move that gives material away fails', () => {
  // The rook captures the knight on d2, but the bishop on b4 guards it.
  const fen = '7k/8/3P4/8/1b1R4/8/3n4/K7 w - - 0 1';
  assert.match(losesMaterial(fen, 'd4d2'), /2 behind/);
  assert.equal(losesMaterial(fen, 'd4b4'), null);
  const l = good();
  l.steps = [
    { type: 'move', fen, text: 'Capture the knight with the rook.', accept: ['d4d2'] },
    { type: 'show', text: 'The rook took the knight.' },
    { type: 'show', text: 'Then the bishop took the rook.' },
  ];
  delete l.practice;
  has(checkLesson(l), /accepted move Rxd2 loses material/);
});

test('practice must be a position the lesson reaches', () => {
  const l = good();
  l.practice = { fen: 'r1b1kbnr/pp1Npppp/8/8/5B2/8/PPP2PPP/R4RK1 b kq - 0 1', side: 'w' }; // legal, but never shown
  has(checkLesson(l), /practice fen is not a position the lesson reaches/);
  l.practice = { fen: 'r1b2bnr/ppNkpppp/8/8/5B2/8/PPP2PPP/R4RK1 w - - 2 2', side: 'w' }; // after Nc7+ Kd7
  assert.deepEqual(messages(checkLesson(l)), []);
});

test('a step that says it wins material must carry a wins claim', () => {
  const l = good();
  delete l.steps[1].wins;
  l.steps[1].text = 'Fork the king and the rook, and win the rook.';
  has(checkLesson(l), /carries no "wins" claim/);
});

test('a pick that asks for a piece must name occupied squares', () => {
  const l = good();
  l.steps[2].accept = ['a6'];
  has(checkLesson(l), /asks for a piece, but a6 is empty/);
});

const made = [];
after(() => { for (const d of made) fs.rmSync(d, { recursive: true, force: true }); });

function tree(mutate) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lessons-'));
  made.push(dir);
  const lesson = good();
  const index = {
    version: 1,
    courses: [{
      id: 'tactics', title: 'Tactics', line: 'Forks, pins and attacks on the king.',
      chapters: [{ id: 'double-attacks', title: 'Double attacks', lessons: [{ id: lesson.id, title: lesson.title, line: lesson.line, fen: FORK, side: 'w' }] }],
    }],
  };
  mutate && mutate(index, lesson);
  fs.mkdirSync(path.join(dir, 'tactics'));
  fs.writeFileSync(path.join(dir, 'index.json'), JSON.stringify(index));
  fs.writeFileSync(path.join(dir, 'tactics', `${lesson.id}.json`), JSON.stringify(lesson));
  return dir;
}

test('a tree whose index and lesson agree passes', async () => {
  const r = await checkTree({ dir: tree() });
  assert.deepEqual(r.faults.map(formatFault), []);
  assert.equal(r.ok, true);
  assert.equal(r.passed, 1);
});

test('the index and the lesson disagreeing fails', async () => {
  const r = await checkTree({ dir: tree((index) => { index.courses[0].chapters[0].lessons[0].title = 'Another fork'; }) });
  assert.equal(r.ok, false);
  assert.ok(r.faults.some(f => /index title "Another fork" differs/.test(f.msg)), r.faults.map(formatFault).join(' | '));
  const r2 = await checkTree({ dir: tree((index, lesson) => { index.courses[0].chapters[0].lessons = []; }) });
  assert.ok(r2.faults.some(f => /missing from the index/.test(f.msg)));
  assert.ok(r2.faults.some(f => /has no lessons/.test(f.msg)));
});

test('an opening chapter must match its play, moves, fen, group and the opening table', () => {
  const lesson = good();
  lesson.course = 'openings'; lesson.id = 'openings-test';
  const lessons = new Map([[lesson.id, { lesson, course: 'openings' }]]);
  const chapter = () => ({
    id: 'italian-game', title: 'Italian Game', for: 'white', group: 'With the king\'s pawn',
    line: 'The bishop takes aim at Black\'s weakest square.',
    play: ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4'], moves: '1.e4 e5 2.Nf3 Nc6 3.Bc4',
    fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3',
    lessons: [{ id: lesson.id, title: lesson.title, line: lesson.line, fen: FORK, side: 'w' }],
  });
  const index = ch => ({ version: 1, courses: [{ id: 'openings', title: 'Openings', line: 'Openings and defenses, by first move.', chapters: [ch] }] });
  const faults = ch => checkIndex(index(ch), lessons).list.map(f => f.msg);
  assert.deepEqual(faults(chapter()), []);
  let ch = chapter(); ch.title = 'Ruy Lopez';
  assert.ok(faults(ch).some(m => /calls this "Italian Game", not "Ruy Lopez"/.test(m)));
  ch = chapter(); ch.fen = AFTER_E4_E5;
  assert.ok(faults(ch).some(m => /fen is not the position after play/.test(m)));
  ch = chapter(); ch.moves = '1.e4 e5 2.Nf3 Nc6 3.Bb5';
  assert.ok(faults(ch).some(m => /are not the same moves as play/.test(m)));
  ch = chapter(); ch.play = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c5'];
  assert.ok(faults(ch).some(m => /play from the start: f1c5 is not legal/.test(m)));
  ch = chapter(); ch.group = 'Against the king\'s pawn';
  assert.ok(faults(ch).some(m => /group "Against the king's pawn" is not one of/.test(m)));
  ch = chapter(); ch.for = 'either';
  assert.ok(faults(ch).some(m => /for must be white or black/.test(m)));
  ch = chapter(); ch.line = 'After 1.e4 e5 the bishop comes out.';
  assert.ok(faults(ch).some(m => /line gives a move in notation/.test(m)));
});

test('nothing depends on notation: moves in notation and unmarked squares fail, except in the notation lessons', () => {
  for (const text of ['Play Nf3.', 'Then Bxc6.', 'Castle with O-O.', 'After 1.e4 the center is open.', 'Black takes dxc6.', 'Promote with e8=Q.']) {
    assert.ok(wordProblems(text).some(p => /notation/.test(p)), text);
  }
  for (const text of ['Play e4.', 'Black answered with d6.', 'Castle 0-0.', 'Castle long, 0-0-0.', 'Then nf3.', 'Then N f3.', 'The rook on A8.']) {
    assert.ok(wordProblems(text).some(p => /notation/.test(p)), text);
  }
  for (const text of ['Bring the knight out.', 'The pawn on e4 moves.', 'Attack the pawn on e4 with the knight.', 'A bishop and a knight.', 'Be careful with the king.', 'Move to d6.', 'Then the queen takes on f7.', 'The rook on a8 is attacked.']) {
    assert.deepEqual(wordProblems(text), [], text);
  }
  const l = good();
  l.steps[1].text = 'Fork the king and the rook: play Nc7.';
  has(checkLesson(l), /text gives a move in notation \("Nc7"\)/);
  const m = good();
  m.steps[1].text = 'Jump to c7 and fork the king and the rook.';
  has(checkLesson(m), /text names c7, which is not marked/);
  m.steps[1].marks = { squares: ['f8'], arrows: [['d5', 'c7']] };
  assert.deepEqual(messages(checkLesson(m)), []);
  m.steps[1].marks = { arrows: [['d5', 'c7']] };
  // Hints, after lines, wrong and also lines are held to the same rule; the summary names no squares.
  m.steps[1].hint = 'The king on e8 is the target.';
  m.steps[1].wrong = { d5e7: 'That takes a pawn, but the bishop on f8 takes the knight back.' };
  m.steps[1].also = { f1d1: 'That works too, from d1.' };
  m.summary = 'A fork on c7 attacks two pieces.';
  const F = checkLesson(m);
  has(F, /hint names e8, which is not marked/);
  has(F, /wrong line for d5e7 names f8, which is not marked/);
  has(F, /also line for f1d1 names d1, which is not marked/);
  has(F, /summary names c7; a summary names no squares/);
  const n = good();
  n.id = 'basics-reading-moves'; n.course = 'basics';
  n.steps[1].text = 'Play Nc7: the knight goes to c7.';
  assert.ok(!checkLesson(n).list.some(f => /notation|not marked/.test(f.msg)));
});

const SHIPPED = 258;

test('the lessons in core/lessons pass', async () => {
  const r = await checkTree({ dir: path.join(here, '..', 'lessons'), all: true });
  assert.deepEqual(r.faults.map(formatFault), []);
  assert.equal(r.lessons, SHIPPED, 'the number of shipped lessons changed: update SHIPPED');
  assert.equal(r.passed, SHIPPED);
});

const engineThere = fs.existsSync(path.join(here, '..', '..', 'engines', 'dist', 'stockfish', 'manifest.json'));

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const opening = step => ({
  id: 'openings-test', course: 'openings', title: 'A test opening', line: 'The first move.', side: 'w', summary: 'The first move.',
  steps: [{ type: 'move', fen: START, text: 'Play a first move.', ...step }, { type: 'show', text: 'One move in.' }, { type: 'show', text: 'Black to move.' }],
});

test('engine: wrong, also, taught and wins are held to Stockfish', { skip: !engineThere && 'no Stockfish in engines/dist' }, async () => {
  const engine = new Engine({ nodes: 200000 });
  await engine.open();
  const run = async l => { const F = checkLesson(l); assert.deepEqual(messages(F), []); return (await checkEngine(l.id, F.moveSteps, engine)).list.map(f => f.msg); };
  try {
    // A wrong line on the best move, and an accepted move far below it.
    const bad = good();
    bad.steps[1] = { type: 'move', text: 'Make room for the king.', accept: ['h2h3'], wrong: { d5c7: 'Not this one.' } };
    bad.steps.length = 2;
    bad.steps.push({ type: 'show', text: 'The pawn has moved.' });
    let m = await run(bad);
    assert.ok(m.some(x => /wrong line for Nc7\+ .*within half a pawn/.test(x)), m.join(' | '));
    assert.ok(m.some(x => /more than half a pawn below Nc7\+/.test(x)), m.join(' | '));
    // A wrong line on a move about as good as the accepted one: use also.
    m = await run(opening({ accept: ['e2e4'], wrong: { d2d4: 'Not this one.' } }));
    assert.ok(m.some(x => /wrong line for d4 .*use also/.test(x)), m.join(' | '));
    m = await run(opening({ accept: ['e2e4'], also: { d2d4: 'That is a fine start too. This lesson goes on with the king\'s pawn.' } }));
    assert.deepEqual(m, []);
    // An also line on a weak move fails.
    m = await run(opening({ accept: ['e2e4'], also: { g2g4: 'That works.' } }));
    assert.ok(m.some(x => /also line for g4 .*make it wrong/.test(x)), m.join(' | '));
    // Na3 is too weak to accept, but within a pawn and a half when taught.
    m = await run(opening({ accept: ['b1a3'] }));
    assert.ok(m.some(x => /more than half a pawn below/.test(x)), m.join(' | '));
    m = await run(opening({ accept: ['b1a3'], taught: true }));
    assert.deepEqual(m, []);
    // A wins claim that holds on material, but Stockfish does not see the player ahead (Black has play for the pawn).
    const gambit = good();
    gambit.steps = [
      { type: 'move', fen: 'rnbqkb1r/pppp1ppp/5n2/4p2Q/4P3/8/PPPP1PPP/RNB1KBNR w KQkq - 2 3', text: 'Take the pawn with check.', accept: ['h5e5'], wins: 1 },
      { type: 'show', text: 'A pawn up.' },
      { type: 'show', text: 'Black is behind in material.' },
    ];
    delete gambit.practice;
    m = await run(gambit);
    assert.ok(m.some(x => /claims it wins 1, but Stockfish rates Qxe5\+ .*not ahead/.test(x)), m.join(' | '));
    // Basics: a move about as good as the accepted one, which the words do not exclude, needs an also or wrong line.
    const castle = { id: 'basics-test', course: 'basics', title: 'A test castle', line: 'Castle.', side: 'w', summary: 'Castle.',
      steps: [{ type: 'move', fen: 'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4', text: 'Castle on the short side.', accept: ['e1g1'] },
        { type: 'show', text: 'Castled.' }, { type: 'show', text: 'The king is safe.' }] };
    let F = checkLesson(castle);
    assert.deepEqual(messages(F), []);
    m = (await checkEngine(castle.id, F.moveSteps, engine, () => {}, 'basics')).list.map(f => f.msg);
    assert.ok(m.some(x => /c3 .*about as good as the accepted move/.test(x)), m.join(' | '));
    // Words that name the move ("Play O-O", in the notation lesson) leave no other move that fits them.
    castle.id = 'basics-reading-moves';
    castle.steps[0].text = 'Play O-O.';
    F = checkLesson(castle);
    m = (await checkEngine(castle.id, F.moveSteps, engine, () => {}, 'basics')).list.map(f => f.msg);
    assert.deepEqual(m, []);
    // The good lesson passes.
    assert.deepEqual(await run(good()), []);
  } finally {
    engine.close();
  }
});

// A filtered run never hides a fault of the lessons it selects, and a selection that names nothing fails.
test('course and scope filters keep the faults of what they select', async () => {
  const os = await import('node:os');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lessons-'));
  fs.cpSync(path.join(here, '..', 'lessons'), tmp, { recursive: true });
  const file = path.join(tmp, 'index.json');
  const index = JSON.parse(fs.readFileSync(file, 'utf8'));
  const chapter = index.courses[0].chapters[0];
  chapter.lessons[0].title += ' changed';
  fs.writeFileSync(file, JSON.stringify(index));
  const id = chapter.lessons[0].id;
  for (const opts of [{ scope: [chapter.id] }, { courses: [index.courses[0].id] }, { only: [id] }, {}]) {
    const r = await checkTree({ dir: tmp, all: true, ...opts });
    assert.ok(r.faults.some(f => f.msg.includes('index title')), `the changed title is reported with ${JSON.stringify(opts)}`);
  }
  // Another course's run is not disturbed by it.
  const other = await checkTree({ dir: tmp, all: true, courses: ['checkmates'] });
  assert.deepEqual(other.faults, []);
  for (const opts of [{ courses: ['zzz-typo'] }, { scope: ['no-such-chapter'] }, { only: ['no-such-lesson'] }]) {
    const r = await checkTree({ dir: tmp, all: true, ...opts });
    assert.equal(r.ok, false, `a selection that names nothing fails: ${JSON.stringify(opts)}`);
  }
  // A lesson file moved into another course's folder is still caught by a run of the course it claims.
  const tmp2 = fs.mkdtempSync(path.join(os.tmpdir(), 'lessons-'));
  fs.cpSync(path.join(here, '..', 'lessons'), tmp2, { recursive: true });
  fs.renameSync(path.join(tmp2, 'tactics', 'tactics-fork.json'), path.join(tmp2, 'checkmates', 'tactics-fork.json'));
  for (const c of ['tactics', 'checkmates']) {
    const r = await checkTree({ dir: tmp2, all: true, courses: [c] });
    assert.ok(r.faults.some(f => f.where === 'tactics-fork'), `the misplaced lesson is reported with --course ${c}`);
  }
  fs.rmSync(tmp2, { recursive: true });
  // A lesson listed in two chapters is reported to a run of either chapter.
  const tmp3 = fs.mkdtempSync(path.join(os.tmpdir(), 'lessons-'));
  fs.cpSync(path.join(here, '..', 'lessons'), tmp3, { recursive: true });
  const index3 = JSON.parse(fs.readFileSync(path.join(tmp3, 'index.json'), 'utf8'));
  const [first, second] = index3.courses[0].chapters;
  second.lessons.push(first.lessons[0]);
  fs.writeFileSync(path.join(tmp3, 'index.json'), JSON.stringify(index3));
  for (const ch of [first.id, second.id]) {
    const r = await checkTree({ dir: tmp3, all: true, scope: [ch] });
    assert.ok(r.faults.some(f => f.msg.includes('listed twice')), `the double listing is reported with --scope ${ch}`);
  }
  fs.rmSync(tmp3, { recursive: true });
  fs.rmSync(tmp, { recursive: true });
});
