// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Zeist Chess on the web. Screens, by address after the #:
//   (none)        Home: the board, set up and waiting, the picker and Play (or Continue)
//   game          the game in progress
//   recent        finished games;  recent/<id>  one game, move by move
//   settings      account, board, pieces, engines, play, your games, about

import { Board, boardFromFEN, pieceURL, drawSwatch } from './board.js';
import * as shelf from './shelf.js';
import * as log from './log.js';
import * as account from './account.js';
import * as material from './material.js';
import { Play, sayClock, startingLevel } from './play.js';
import * as engine from './engine.js';
import { Game, START } from '../core/rules.js';
import { esc, ICON, mark, sheet, saveFile, when, longDate } from './ui.js';
import { get as pref, set as setPref, BASE, APP_VERSION, ZEIST, addressedEngine } from './store.js';

const app = document.getElementById('app');
const wide = matchMedia('(min-width: 900px) and (min-height: 560px)');

let THEMES = null, SETS = null;
let play = null; // the game in progress, when there is one
let cleanup = null;

// Look

function theme() {
  const id = pref('theme', THEMES.default);
  return THEMES.themes.find(t => t.id === id) || THEMES.themes.find(t => t.id === THEMES.default) || THEMES.themes[0];
}
function pieceSet() {
  const id = pref('pieces', SETS.default);
  return (SETS.sets.find(s => s.id === id) || SETS.sets.find(s => s.id === SETS.default) || SETS.sets[0]).id;
}

// The picker's choices, kept for next time.

function pick() {
  const p = pref('pick', {});
  return { engine: p.engine || shelf.BUILT_IN, side: p.side || 'w', mode: p.mode || 'adaptive', level: p.level || 3, rating: p.rating || 1500, tc: p.tc || null };
}
function setPick(changes) { setPref('pick', { ...pick(), ...changes }); }

function chosenEntry() {
  const p = pick();
  const list = shelf.playable();
  return list.find(e => e.manifest.id === p.engine) || list.find(e => e.builtIn) || list[0] || null;
}

function modeOf(p, entry) {
  if (p.mode === 'rating' && entry && shelf.ratings(entry.manifest)) return 'rating';
  return p.mode === 'adaptive' ? 'adaptive' : 'level';
}

function clampRating(r, range) { return Math.min(range[1], Math.max(range[0], Math.round(r / 50) * 50)); }

function summary(p, entry) {
  const side = { w: 'White', b: 'Black', either: 'Either side' }[p.side] || 'White';
  const mode = modeOf(p, entry);
  const range = entry && shelf.ratings(entry.manifest);
  const diff = mode === 'adaptive' ? `Adaptive, level ${startingLevel(entry ? entry.manifest.id : '')}`
    : mode === 'rating' ? `Rating ${clampRating(p.rating, range)}` : `Level ${p.level}`;
  return `${side}. ${diff}.${p.tc ? ` ${log.tcName(p.tc)}.` : ''}`;
}

// Routing

function route() {
  const h = location.hash.replace(/^#\/?/, '');
  if (cleanup) { try { cleanup(); } catch (e) { console.error(e); } cleanup = null; }
  document.body.classList.remove('sheet-open');
  window.scrollTo(0, 0);
  const [name, arg] = h.split('/');
  if (name === 'game') return gameScreen();
  if (name === 'recent' && arg) return replayScreen(arg);
  if (name === 'recent') return recentScreen();
  if (name === 'settings') return settingsScreen(arg);
  return homeScreen();
}

function go(hash) { if (location.hash === hash) route(); else location.hash = hash; }

function topBar({ title = '', back = '#/', right = '' } = {}) {
  return `<header class="bar">
  <a class="round" href="${back}" aria-label="Back">${ICON.back}</a>
  <h1 class="bar-title">${esc(title)}</h1>
  <div class="bar-right">${right}</div>
</header>`;
}

// Home

/** The top of Home. Served under zeist.gg/chess, a quiet way back to Zeist takes the left and the name moves below. */
function homeTop() {
  const brand = `<a class="brand" href="#/" aria-label="Zeist Chess">${mark()}<span>Zeist Chess</span></a>`;
  const nav = `<nav class="top-nav">
      <a class="round" href="#/recent" aria-label="Recent games">${ICON.recent}</a>
      <a class="round" href="#/settings" aria-label="Settings">${ICON.settings}</a>
    </nav>`;
  if (!ZEIST) return `<header class="top">
    ${brand}
    ${nav}
  </header>`;
  return `<header class="top">
    <a class="to-zeist" id="to-zeist" href="${ZEIST}">${ICON.back}<span>Zeist</span></a>
    ${nav}
  </header>
  <div class="top brand-row">${brand}</div>`;
}

async function homeScreen() {
  const current = play && !play.over ? play.record : await log.current();
  const entry = chosenEntry();
  const p = pick();
  const continuing = current && !pref('pickedSince', false);
  app.innerHTML = `<div class="screen home${ZEIST ? ' in-zeist' : ''}">
  ${homeTop()}
  <div class="home-grid">
    <div class="stage">
      <div class="board-frame"><div id="home-board" class="setting-up"></div></div>
      <p class="under" id="home-under">${continuing ? esc(`Your game against ${current.engineName}, move ${Math.floor(current.moves.length / 2) + 1}.`) : ''}</p>
    </div>
    <aside class="side home-side">
      <div class="picker-inline" id="picker-inline"></div>
      <button class="card picker-card" id="picker-card" type="button" aria-haspopup="dialog">
        <span class="pc-text"><span class="pc-name">${esc(entry ? entry.manifest.name : 'No engine yet')}</span><span class="pc-sub">${esc(summary(p, entry))}</span></span>
        <span class="pc-icon">${ICON.updown}</span>
      </button>
      <button class="pill solid wide" id="play" type="button">${continuing ? 'Continue' : 'Play'}</button>
      <p class="note" id="home-note" role="status" aria-live="polite"></p>
    </aside>
  </div>
</div>`;
  const board = new Board(document.getElementById('home-board'), { label: 'The board, set up', coords: false });
  board.setLook(theme(), pieceSet());
  const fen = continuing ? current.fen : START;
  board.render({ board: boardFromFEN(fen), flipped: (continuing ? current.player : (p.side === 'b' ? 'b' : 'w')) === 'b', last: continuing ? current.moves[current.moves.length - 1] : null, legal: [], mine: null });
  requestAnimationFrame(() => document.getElementById('home-board')?.classList.remove('setting-up'));

  const refreshPicker = () => {
    const e = chosenEntry(), q = pick();
    const card = document.getElementById('picker-card');
    if (!card) return;
    card.querySelector('.pc-name').textContent = e ? e.manifest.name : 'No engine yet';
    card.querySelector('.pc-sub').textContent = summary(q, e);
    const playBtn = document.getElementById('play');
    const cont = current && !pref('pickedSince', false);
    playBtn.textContent = cont ? 'Continue' : 'Play';
    document.getElementById('home-under').textContent = cont ? `Your game against ${current.engineName}, move ${Math.floor(current.moves.length / 2) + 1}.` : '';
    if (!cont) board.render({ board: boardFromFEN(START), flipped: q.side === 'b', last: null });
  };
  const onPick = () => { if (current) setPref('pickedSince', true); refreshPicker(); };

  const layout = () => {
    const inline = document.getElementById('picker-inline');
    if (!inline) return;
    inline.innerHTML = '';
    if (wide.matches) picker(inline, { onChange: onPick, current });
  };
  layout();
  wide.addEventListener('change', layout);

  document.getElementById('picker-card').addEventListener('click', () => {
    sheet((body, close) => picker(body, { onChange: onPick, close, current }), { label: 'Choose your game' });
  });
  document.getElementById('play').addEventListener('click', () => {
    if (current && !pref('pickedSince', false)) { go('#/game'); return; }
    startGame();
  });
  // The list of engines arrives after the screen: draw the picker again when it changes.
  let known = shelf.playable().map(e => e.manifest.id + e.installed).join();
  const unsub = shelf.subscribe(() => {
    refreshPicker();
    const now = shelf.playable().map(e => e.manifest.id + e.installed).join();
    if (now !== known) { known = now; layout(); }
  });
  cleanup = () => { board.destroy(); wide.removeEventListener('change', layout); unsub(); };
}

/** Who to play and how: the engines here, the side, the difficulty and the clock. Changes are kept for next time. */
function picker(el, { onChange, close, current }) {
  const draw = () => {
    const p = pick();
    const entry = chosenEntry();
    const range = entry && shelf.ratings(entry.manifest);
    const mode = modeOf(p, entry);
    const engines = shelf.playable();
    el.innerHTML = `<div class="picker">
  <h2 class="label">Opponent</h2>
  <div class="engine-list" role="radiogroup" aria-label="Opponent">
    ${engines.map(e => `<button class="engine-pick" type="button" role="radio" aria-checked="${entry && e.manifest.id === entry.manifest.id}" data-engine="${esc(e.manifest.id)}">
      <span class="ep-text"><span class="ep-name">${esc(e.manifest.name)}</span><span class="ep-line">${esc(e.manifest.line || '')}</span></span>
      <span class="ep-check">${ICON.check}</span></button>`).join('')}
    <a class="engine-more" href="#/settings/engines">More engines <span>${ICON.forward}</span></a>
  </div>
  <h2 class="label">Play as</h2>
  ${choice('side', [['w', 'White'], ['b', 'Black'], ['either', 'Either']], p.side)}
  <h2 class="label">Difficulty</h2>
  ${choice('mode', [['adaptive', 'Adaptive'], ['level', 'Level'], ...(range ? [['rating', 'Rating']] : [])], mode)}
  <div class="mode-detail">${mode === 'adaptive'
    ? `<p class="soft">Level ${startingLevel(entry ? entry.manifest.id : '')} of 10. It moves up when you win and down when you lose, quickly at first.</p>`
    : mode === 'level'
      ? `<div class="levels" role="radiogroup" aria-label="Level">${Array.from({ length: 10 }, (_, i) => `<button type="button" role="radio" aria-label="Level ${i + 1}" aria-checked="${p.level === i + 1}" data-level="${i + 1}">${i + 1}</button>`).join('')}</div>`
      : `<div class="rating"><div class="rating-top"><span class="rating-value" id="rating-value">${clampRating(p.rating, range)}</span><span class="dim">${range[0]} to ${range[1]}</span></div>
         <input type="range" id="rating" aria-label="Rating" min="${range[0]}" max="${range[1]}" step="50" value="${clampRating(p.rating, range)}">
         <p class="soft">${entry.manifest.id === 'maia' ? 'Plays like people at this rating.' : "On this engine's own scale, not a human rating."}</p></div>`}</div>
  <h2 class="label">Clock</h2>
  <div class="clocks" role="radiogroup" aria-label="Clock">
    <button type="button" role="radio" class="chip" aria-checked="${!p.tc}" data-tc="none">No clock</button>
    ${log.PRESETS.map(([kind, list]) => list.map(tc => `<button type="button" role="radio" class="chip" aria-checked="${!!p.tc && p.tc.base === tc.base && p.tc.increment === tc.increment}" data-tc="${tc.base}+${tc.increment}" title="${kind}">${log.tcName(tc)}</button>`).join('')).join('')}
  </div>
  <p class="soft tc-detail">${p.tc ? tcDetail(p.tc) : 'Take as long as you like.'}</p>
  ${current ? `<p class="dim keep-note">Your game against ${esc(current.engineName)} stays until you start another.</p>` : ''}
  ${close ? '<button class="pill wide done" type="button" id="picker-done">Done</button>' : ''}
</div>`;
    el.querySelectorAll('[data-engine]').forEach(b => b.addEventListener('click', () => { setPick({ engine: b.dataset.engine }); onChange(); draw(); }));
    el.querySelectorAll('[data-choice="side"] button').forEach(b => b.addEventListener('click', () => { setPick({ side: b.dataset.value }); onChange(); draw(); }));
    el.querySelectorAll('[data-choice="mode"] button').forEach(b => b.addEventListener('click', () => { setPick({ mode: b.dataset.value }); onChange(); draw(); }));
    el.querySelectorAll('[data-level]').forEach(b => b.addEventListener('click', () => { setPick({ level: +b.dataset.level }); onChange(); draw(); }));
    el.querySelectorAll('[data-tc]').forEach(b => b.addEventListener('click', () => {
      const v = b.dataset.tc;
      setPick({ tc: v === 'none' ? null : { base: +v.split('+')[0], increment: +v.split('+')[1] } });
      onChange(); draw();
    }));
    const r = el.querySelector('#rating');
    if (r) {
      r.addEventListener('input', () => { el.querySelector('#rating-value').textContent = r.value; setPick({ rating: +r.value }); onChange(); });
    }
    const more = el.querySelector('.engine-more');
    if (more && close) more.addEventListener('click', () => close());
    const done = el.querySelector('#picker-done');
    if (done) done.addEventListener('click', close);
  };
  draw();
}

function tcDetail(tc) {
  const kind = log.timeClass(tc);
  const mins = tc.base / 60;
  const each = mins === 1 ? 'One minute each' : `${mins} minutes each`;
  const inc = tc.increment === 1 ? 'one second' : `${tc.increment} seconds`;
  return `${kind[0].toUpperCase() + kind.slice(1)}. ${each}${tc.increment ? `, ${inc} added after every move` : ''}.`;
}

function choice(name, options, value) {
  return `<div class="choice" data-choice="${name}" role="radiogroup">${options.map(([v, label]) =>
    `<button type="button" role="radio" aria-checked="${v === value}" data-value="${v}">${esc(label)}</button>`).join('')}</div>`;
}

async function startGame() {
  const note = document.getElementById('home-note');
  const btn = document.getElementById('play');
  const say = t => { if (note) note.textContent = t; };
  let entry = chosenEntry();
  if (!entry) { say('Download an engine in Settings to play.'); return; }
  const p = pick();
  if (!entry.installed) {
    // Stockfish Lite comes down on first play.
    btn.disabled = true;
    const unsub = shelf.subscribe(() => {
      const d = shelf.download(entry.manifest.id);
      if (d && !d.error) say(`Getting ${entry.manifest.name} ready. ${Math.round(d.progress * 100)}%`);
    });
    try {
      say(`Getting ${entry.manifest.name} ready.`);
      await shelf.install(entry.manifest.id);
    } catch (e) {
      unsub();
      btn.disabled = false;
      say(navigator.onLine === false
        ? `${entry.manifest.name} needs a connection once, to download. Then it plays offline.`
        : `${e.message} Try again.`);
      return;
    }
    unsub();
    btn.disabled = false;
    say('');
    entry = shelf.engine(entry.manifest.id);
  }
  const side = p.side === 'either' ? (Math.random() < 0.5 ? 'w' : 'b') : p.side;
  const mode = modeOf(p, entry);
  const range = shelf.ratings(entry.manifest);
  if (play) play.pause();
  play = await Play.begin({
    entry, player: side,
    level: mode === 'adaptive' ? startingLevel(entry.manifest.id) : p.level,
    adaptive: mode === 'adaptive',
    rating: mode === 'rating' ? clampRating(p.rating, range) : null,
    timeControl: p.tc,
  });
  setPref('pickedSince', false);
  go('#/game');
}

// The game

/** Small piece figures for a SAN move: "Nf3" with a knight drawn for the N. */
function sanHTML(san, set) {
  const m = /^([KQRBN])(.*)$/.exec(san);
  const promo = /=([QRBN])/.exec(san);
  let body = esc(m ? m[2] : san);
  if (promo) body = body.replace(`=${promo[1]}`, `=<img class="fig" alt="${promo[1]}" src="${pieceURL(set, 'w' + promo[1])}">`);
  return m ? `<img class="fig" alt="${m[1]}" src="${pieceURL(set, 'w' + m[1])}">${body}` : body;
}

function takenHTML(side, board, set) {
  const list = material.captured(side, board);
  const lead = material.lead(side, board);
  const other = side === 'w' ? 'b' : 'w';
  const imgs = list.map(({ kind, count }) => `<span class="taken-group">${Array.from({ length: count }, () => `<img alt="" src="${pieceURL(set, other + kind)}">`).join('')}</span>`).join('');
  const label = list.map(({ kind, count }) => `${count} ${{ P: 'pawn', N: 'knight', B: 'bishop', R: 'rook', Q: 'queen' }[kind]}${count > 1 ? 's' : ''}`).join(', ');
  return `<span class="taken" aria-label="${label ? 'Took ' + label : 'Nothing taken'}">${imgs}${lead ? `<span class="lead">+${lead}</span>` : ''}</span>`;
}

function playerRow(id) {
  return `<div class="player" id="${id}"><span class="dot"></span><span class="who"><span class="name"></span><span class="sub"></span></span><span class="taken-slot"></span><span class="clock" hidden></span></div>`;
}

function fillPlayer(el, { color, name, sub, board, set, clock, running, low }) {
  el.querySelector('.dot').className = `dot ${color}`;
  el.querySelector('.name').textContent = name;
  el.querySelector('.sub').textContent = sub || '';
  el.querySelector('.taken-slot').innerHTML = takenHTML(color, board, set);
  const c = el.querySelector('.clock');
  if (clock == null) { c.hidden = true; return; }
  c.hidden = false;
  c.textContent = sayClock(clock);
  c.classList.toggle('running', !!running);
  c.classList.toggle('low', !!low);
  c.setAttribute('aria-label', `${name}, ${Math.floor(clock / 60000)} minutes ${Math.floor(clock / 1000) % 60} seconds left`);
}

function movesHTML(san, set, at, startFEN = START) {
  const blackFirst = startFEN.split(' ')[1] === 'b';
  const rows = [];
  for (let i = 0; i < san.length; i++) {
    const ply = i + (blackFirst ? 1 : 0);
    const no = Math.floor(ply / 2) + 1;
    if (ply % 2 === 0 || i === 0) rows.push({ no, w: null, b: null });
    rows[rows.length - 1][ply % 2 === 0 ? 'w' : 'b'] = i + 1;
  }
  const cell = n => n == null ? '<span class="mv empty"></span>' : `<button type="button" class="mv${n === at ? ' at' : ''}" data-ply="${n}">${sanHTML(san[n - 1], set)}</button>`;
  return rows.map(r => `<li><span class="no">${r.no}.</span>${cell(r.w)}${cell(r.b)}</li>`).join('');
}

async function gameScreen() {
  if (!play) {
    const current = await log.current();
    const entry = current && shelf.engine(current.engineID);
    if (current && entry && entry.installed) play = new Play(current, entry);
    else if (current) {
      app.innerHTML = `<div class="screen narrow">${topBar({ title: current.engineName })}<p class="soft gap">${esc(current.engineName)} isn't in this browser anymore. Download it again in Settings to pick up this game.</p><div class="row-actions"><a class="pill" href="#/settings/engines">Settings</a></div></div>`;
      return;
    } else { go('#/'); return; }
  }
  const P = play;
  const set = pieceSet();
  let view = null; // a ply being looked at, or null for the live position
  let confirmResign = false;
  app.innerHTML = `<div class="screen game">
  ${topBar({ title: P.manifest.name, back: '#/' })}
  <div class="game-grid">
    <div class="play-col">
      <ol class="moveline" id="moveline" aria-label="Moves"></ol>
      ${playerRow('them')}
      <div class="board-frame"><div id="game-board"></div></div>
      ${playerRow('you')}
    </div>
    <aside class="side game-side">
      <div class="side-head"><h2 class="side-title">${esc(P.manifest.name)}</h2><p class="soft" id="side-level"></p></div>
      <ol class="moves" id="moves" aria-label="Moves"></ol>
      <div class="foot">
        <p class="status" id="status" role="status" aria-live="polite"></p>
        <div class="controls" id="controls"></div>
      </div>
    </aside>
  </div>
</div>`;
  const board = new Board(document.getElementById('game-board'), {
    onMove: uci => { if (view == null) P.move(uci); },
    autoQueen: () => pref('autoQueen', false),
    label: 'The game board',
  });
  board.setLook(theme(), set);
  const flipped = P.player === 'b';
  const els = {
    them: document.getElementById('them'), you: document.getElementById('you'),
    moveline: document.getElementById('moveline'), moves: document.getElementById('moves'),
    status: document.getElementById('status'), controls: document.getElementById('controls'),
    level: document.getElementById('side-level'),
  };
  const me = account.current().user;
  let lastPly = -1;

  const update = () => {
    const r = P.record;
    const n = r.moves.length;
    if (view != null && view >= n) view = null;
    const at = view == null ? n : view;
    let snap;
    if (view == null) snap = P.snap;
    else snap = Game.fromMoves(r.moves.slice(0, at), r.startFEN).snapshot();
    const live = view == null && !P.over;
    board.render({
      board: snap.board, last: at ? r.moves[at - 1] : null, check: snap.check, flipped,
      legal: live && P.myTurn ? snap.legal : [], mine: live && P.myTurn ? P.player : null,
    });
    // Players and clocks
    const t = P.clock;
    const clockAt = side => {
      if (!r.timeControl) return null;
      if (view == null) return t ? t.remaining(side) : (r.clockLeft ? r.clockLeft[side === 'w' ? 0 : 1] : null);
      // Looking back: each side's time after its last move up to here.
      for (let i = at - 1; i >= 0; i--) { const mover = (i % 2 === 0) === (r.startFEN.split(' ')[1] !== 'b') ? 'w' : 'b'; if (mover === side && r.clocks && r.clocks[i] != null) return r.clocks[i]; }
      return r.timeControl.base * 1000;
    };
    const eng = P.player === 'w' ? 'b' : 'w';
    const lowAt = t ? t.lowTime() : 0;
    fillPlayer(els.them, { color: eng, name: P.manifest.name, sub: log.difficulty(r), board: snap.board, set, clock: clockAt(eng), running: view == null && t && t.running === eng && !t.paused, low: t && clockAt(eng) < lowAt });
    fillPlayer(els.you, { color: P.player, name: me && me.handle ? me.handle : 'You', board: snap.board, set, clock: clockAt(P.player), running: view == null && t && t.running === P.player && !t.paused, low: t && clockAt(P.player) < lowAt });
    els.level.textContent = `${log.difficulty(r)}${r.timeControl ? `. ${log.tcName(r.timeControl)}` : ''}`;
    // Moves
    if (n !== lastPly || view != null || els.moves.dataset.at !== String(at)) {
      const html = movesHTML(r.san, set, at, r.startFEN);
      els.moves.innerHTML = html || '<li class="empty-moves dim">No moves yet.</li>';
      els.moveline.innerHTML = html;
      els.moves.dataset.at = String(at);
      const cur = els.moves.querySelector('.at');
      if (cur) cur.scrollIntoView({ block: 'nearest' });
      else els.moves.scrollTop = els.moves.scrollHeight;
      const curLine = els.moveline.querySelector('.at');
      if (curLine) els.moveline.scrollLeft = curLine.offsetLeft - els.moveline.clientWidth / 2;
      else els.moveline.scrollLeft = els.moveline.scrollWidth;
      lastPly = n;
    }
    // Status and controls
    if (P.over) {
      const e = P.ending();
      const moves = Math.ceil(n / 2);
      let next = '';
      if (P.nextLevel != null) {
        next = P.nextLevel > r.level ? ` Your next game is at level ${P.nextLevel}, harder.` : P.nextLevel < r.level ? ` Your next game is at level ${P.nextLevel}, easier.` : ` Your next game stays at level ${P.nextLevel}.`;
      }
      els.status.textContent = '';
      els.controls.innerHTML = `<div class="result"><h2 class="result-title">${esc(e.title)}</h2>
        <p class="soft">${esc(`${e.why} ${moves} ${moves === 1 ? 'move' : 'moves'}.${next} The game is kept in Recent.`.trim())}</p>
        <div class="row-actions"><button class="pill solid" type="button" id="again">Play again</button><a class="pill" href="#/">Home</a></div>
        <a class="quiet-link" href="#/recent/${esc(r.id)}">Go through the game</a></div>`;
      document.getElementById('again').addEventListener('click', () => { play = null; startGame(); });
      document.querySelector('.game').classList.add('over');
      return;
    }
    els.status.textContent = view != null ? `Looking at move ${Math.ceil(at / 2)}. Press the right arrow or tap the last move to come back.` : P.status();
    if (P.trouble) {
      els.controls.innerHTML = `<button class="pill solid" type="button" id="retry">Try again</button><button class="pill" type="button" id="resign">Resign</button>`;
      document.getElementById('retry').onclick = () => P.retry();
      document.getElementById('resign').onclick = () => P.resign();
    } else if (confirmResign) {
      els.controls.innerHTML = `<button class="pill solid" type="button" id="resign-yes">Resign</button><button class="pill" type="button" id="resign-no">Keep playing</button>`;
      document.getElementById('resign-yes').onclick = () => { confirmResign = false; P.resign(); };
      document.getElementById('resign-no').onclick = () => { confirmResign = false; update(); };
      els.status.textContent = 'Resign this game?';
    } else {
      els.controls.innerHTML = `${P.timed ? '' : `<button class="pill" type="button" id="undo"${P.canUndo ? '' : ' disabled'}>Undo</button>`}<button class="pill" type="button" id="resign">Resign</button>`;
      const u = document.getElementById('undo');
      if (u) u.onclick = () => { view = null; board.deselect(); P.undo(); };
      document.getElementById('resign').onclick = () => { confirmResign = true; update(); document.getElementById('resign-no')?.focus(); };
    }
  };
  // A selected piece stays selected unless the position itself changed.
  let seen = P.record.moves.length;
  P.onChange = () => { if (P.record.moves.length !== seen || P.over) { seen = P.record.moves.length; board.deselect(); } update(); };

  const onMoveClick = e => {
    const b = e.target.closest('[data-ply]');
    if (!b) return;
    const ply = +b.dataset.ply;
    view = ply >= P.record.moves.length ? null : ply;
    board.deselect();
    update();
  };
  els.moves.addEventListener('click', onMoveClick);
  els.moveline.addEventListener('click', onMoveClick);

  const key = e => {
    if (e.target.closest('input, textarea, select') || e.metaKey || e.ctrlKey || e.altKey) return;
    const n = P.record.moves.length;
    const at = view == null ? n : view;
    let next = null;
    if (e.key === 'ArrowLeft') next = Math.max(0, at - 1);
    else if (e.key === 'ArrowRight') next = Math.min(n, at + 1);
    else if (e.key === 'Home' || e.key === 'ArrowUp') next = 0;
    else if (e.key === 'End' || e.key === 'ArrowDown') next = n;
    else if (e.key === 'Escape') { board.deselect(); return; }
    else return;
    e.preventDefault();
    view = next >= n ? null : next;
    board.deselect();
    update();
  };
  addEventListener('keydown', key);

  const tick = setInterval(() => { if (P.clock && !P.over) { P.tick(); if (!P.over) update(); } }, 100);
  const vis = () => { if (document.hidden) P.pause(); else P.resume(); };
  document.addEventListener('visibilitychange', vis);
  update();
  P.open();
  cleanup = () => {
    clearInterval(tick);
    removeEventListener('keydown', key);
    document.removeEventListener('visibilitychange', vis);
    board.destroy();
    P.pause();
    P.onChange = () => {};
    if (P.over) play = null;
  };
}

// Recent

function resultWord(g) {
  const o = log.outcome(g);
  return o === 'win' ? 'Won' : o === 'loss' ? 'Lost' : o === 'draw' ? 'Draw' : 'Unfinished';
}

function signInLine() {
  const a = account.current();
  if (a.user) return '';
  if (!a.hosted) return `<p class="soft account-line">Open Zeist Chess at zeist.gg to sign in to Zeist and keep a rating and records.</p>`;
  return `<div class="account-row"><p class="soft">Sign in to Zeist to keep a rating and records.</p><a class="pill small" href="${esc(account.signInURL())}">Sign in</a></div>`;
}

async function recentScreen() {
  const games = (await log.all()).filter(g => g.result);
  app.innerHTML = `<div class="screen narrow">
  ${topBar({ title: '', back: '#/' })}
  <h1 class="page-title">Recent</h1>
  ${signInLine()}
  ${games.length ? `<h2 class="label">${games.length} ${games.length === 1 ? 'game' : 'games'}</h2>
  <ul class="game-list">${games.map(g => `<li><a class="game-row" href="#/recent/${esc(g.id)}">
    <span class="gr-main"><span class="gr-name">${esc(g.engineName)}</span><span class="gr-word">${resultWord(g)}</span></span>
    <span class="gr-sub">${esc(when(g.startedAt))} · ${esc(log.difficulty(g))}${g.timeControl ? ` · ${esc(log.tcName(g.timeControl))}` : ''}</span>
  </a></li>`).join('')}</ul>` : '<p class="dim gap">Games you finish are kept here.</p>'}
</div>`;
}

async function replayScreen(id) {
  const g = await log.get(id);
  if (!g) { go('#/recent'); return; }
  const set = pieceSet();
  const fens = [];
  const boards = [];
  const checks = [];
  const game = new Game(g.startFEN);
  boards.push(game.board()); checks.push(game.checkSquare());
  for (const m of g.moves) { if (!game.play(m)) break; boards.push(game.board()); checks.push(game.checkSquare()); }
  let ply = boards.length - 1;
  const side = g.player === 'w' ? 'White' : 'Black';
  const diff = log.difficulty(g);
  app.innerHTML = `<div class="screen game replay">
  ${topBar({ title: g.engineName, back: '#/recent' })}
  <div class="game-grid">
    <div class="play-col">
      <ol class="moveline" id="moveline" aria-label="Moves"></ol>
      ${playerRow('them')}
      <div class="board-frame"><div id="replay-board"></div></div>
      ${playerRow('you')}
    </div>
    <aside class="side game-side">
      <div class="side-head"><h2 class="side-title">${esc(g.engineName)}</h2>
      <p class="soft">${esc(`${longDate(g.startedAt)}. You played ${side} at ${diff[0].toLowerCase() + diff.slice(1)}${g.timeControl ? `, ${log.tcName(g.timeControl)}` : ''}. ${resultWord(g)}.`)}</p></div>
      <ol class="moves" id="moves" aria-label="Moves"></ol>
      <div class="foot">
        <p class="status" id="replay-move" aria-live="polite"></p>
        <div class="steps">
          <button class="pill icon-pill" type="button" id="s-start" aria-label="Start">${ICON.start}</button>
          <button class="pill icon-pill" type="button" id="s-back" aria-label="Back a move">${ICON.back}</button>
          <button class="pill icon-pill" type="button" id="s-fwd" aria-label="Forward a move">${ICON.forward}</button>
          <button class="pill icon-pill" type="button" id="s-end" aria-label="End">${ICON.end}</button>
        </div>
        <button class="quiet-link" type="button" id="export-one">Export as PGN</button>
      </div>
    </aside>
  </div>
</div>`;
  const board = new Board(document.getElementById('replay-board'), { label: 'The board at this move' });
  board.setLook(theme(), set);
  const eng = g.player === 'w' ? 'b' : 'w';
  const blackFirst = g.startFEN.split(' ')[1] === 'b';
  const moverOf = i => ((i + (blackFirst ? 1 : 0)) % 2 === 0 ? 'w' : 'b');
  const clockAt = s => {
    if (!g.timeControl) return null;
    for (let i = ply - 1; i >= 0; i--) if (moverOf(i) === s && g.clocks && g.clocks[i] != null) return g.clocks[i];
    return g.timeControl.base * 1000;
  };
  const update = () => {
    board.render({ board: boards[ply], last: ply ? g.moves[ply - 1] : null, check: checks[ply], flipped: g.player === 'b', legal: [], mine: null });
    fillPlayer(document.getElementById('them'), { color: eng, name: g.engineName, sub: diff, board: boards[ply], set, clock: clockAt(eng) });
    fillPlayer(document.getElementById('you'), { color: g.player, name: g.accountHandle || 'You', board: boards[ply], set, clock: clockAt(g.player) });
    const html = movesHTML(g.san, set, ply, g.startFEN);
    for (const id of ['moves', 'moveline']) document.getElementById(id).innerHTML = html;
    const cur = document.querySelector('#moves .at');
    if (cur) cur.scrollIntoView({ block: 'nearest' });
    const ml = document.getElementById('moveline'), cl = ml.querySelector('.at');
    ml.scrollLeft = cl ? cl.offsetLeft - ml.clientWidth / 2 : 0;
    const p = ply - 1 + (blackFirst ? 1 : 0);
    document.getElementById('replay-move').textContent = ply === 0 ? 'The start.' : `${Math.floor(p / 2) + 1}${p % 2 === 0 ? '.' : '...'} ${g.san[ply - 1]}${ply === boards.length - 1 && g.ending ? `. ${endingWord(g)}` : ''}`;
    document.getElementById('s-start').disabled = document.getElementById('s-back').disabled = ply === 0;
    document.getElementById('s-fwd').disabled = document.getElementById('s-end').disabled = ply >= boards.length - 1;
  };
  const step = d => { const n = Math.max(0, Math.min(boards.length - 1, ply + d)); if (n !== ply) { ply = n; update(); } };
  document.getElementById('s-start').onclick = () => step(-ply);
  document.getElementById('s-back').onclick = () => step(-1);
  document.getElementById('s-fwd').onclick = () => step(1);
  document.getElementById('s-end').onclick = () => step(boards.length);
  document.getElementById('export-one').onclick = () => saveFile(`Zeist Chess ${g.startedAt.slice(0, 10)} ${g.engineName}.pgn`, log.pgn(g), 'application/x-chess-pgn');
  const onMoveClick = e => { const b = e.target.closest('[data-ply]'); if (b) { ply = +b.dataset.ply; update(); } };
  document.getElementById('moves').addEventListener('click', onMoveClick);
  document.getElementById('moveline').addEventListener('click', onMoveClick);
  const key = e => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'ArrowLeft') step(-1); else if (e.key === 'ArrowRight') step(1);
    else if (e.key === 'Home' || e.key === 'ArrowUp') step(-ply); else if (e.key === 'End' || e.key === 'ArrowDown') step(boards.length);
    else return;
    e.preventDefault();
  };
  addEventListener('keydown', key);
  update();
  cleanup = () => { removeEventListener('keydown', key); board.destroy(); };
}

function endingWord(g) {
  return {
    checkmate: 'Checkmate', stalemate: 'Stalemate', repetition: 'A draw by repetition', 'fifty-move': 'A draw by the fifty-move rule',
    insufficient: 'A draw, neither side can checkmate', resigned: 'You resigned', timeout: 'Out of time', 'timeout-insufficient': 'A draw on time',
    abandoned: 'Left unfinished',
  }[g.ending] || '';
}

// Settings

async function settingsScreen(anchor) {
  const a = account.current();
  app.innerHTML = `<div class="screen narrow settings">
  ${topBar({ title: '', back: '#/' })}
  <h1 class="page-title">Settings</h1>

  <h2 class="label">Zeist account</h2>
  <div id="account">${a.user
    ? `<div class="account-row"><span class="who-line"><span class="acc-name">${esc(a.user.display_name || a.user.handle || 'Signed in')}</span>${a.user.handle ? `<span class="soft">@${esc(a.user.handle)}</span>` : '<span class="soft">Choose a username on zeist.gg.</span>'}</span></div>
       <p class="dim small">Your games are kept in this browser under your account. Ratings and records come in a later version.</p>`
    : signInLine()}</div>

  <h2 class="label">Board</h2>
  <div class="swatches" id="themes" role="radiogroup" aria-label="Board">${THEMES.themes.map(t => `<button type="button" role="radio" class="swatch" data-theme="${esc(t.id)}" aria-checked="${t.id === theme().id}" aria-label="${esc(t.name)} board"><canvas></canvas><span>${esc(t.name)}</span></button>`).join('')}</div>

  <h2 class="label">Pieces</h2>
  <div class="swatches pieces-sw" id="sets" role="radiogroup" aria-label="Pieces">${SETS.sets.map(s => `<button type="button" role="radio" class="swatch" data-set="${esc(s.id)}" aria-checked="${s.id === pieceSet()}" aria-label="${esc(s.name)} pieces"><canvas></canvas><span>${esc(s.name)}</span></button>`).join('')}</div>

  <h2 class="label" id="engines">Engines</h2>
  <p class="dim small" id="catalog-problem" hidden></p>
  <ul class="engine-rows" id="engine-rows"></ul>
  <div class="storage" id="storage"></div>

  <h2 class="label">Play</h2>
  <label class="toggle"><span>Engines take their time</span><input type="checkbox" id="pace" ${pref('pace', true) ? 'checked' : ''}></label>
  <label class="toggle"><span>Promote to a queen without asking</span><input type="checkbox" id="auto-queen" ${pref('autoQueen', false) ? 'checked' : ''}></label>

  <h2 class="label">Your games</h2>
  <p class="soft">Every game is kept in this browser. Export them all as PGN, which any chess app reads, or as JSON with every detail.</p>
  <div class="row-actions left"><button class="pill small" type="button" id="export-pgn">PGN</button><button class="pill small" type="button" id="export-json">JSON</button></div>

  <h2 class="label">About</h2>
  <p class="soft">Zeist Chess is open source under the GNU Affero General Public License, version 3 or later.</p>
  <p><a class="link" href="https://github.com/zeistgames/chess" rel="noopener">github.com/zeistgames/chess</a></p>
  <dl class="credits">
    <dt>Rules</dt><dd>chess.js by Jeff Hlywa. BSD-2-Clause.</dd>
    <dt>Pieces</dt><dd>${SETS.sets.map(s => `${esc(s.name)}, by ${esc(s.author)}. ${esc(s.license)}. <a class="link" href="${esc(s.source)}" rel="noopener">Source</a>`).join('<br>')}<br>Each set is lit in ivory and ebony.</dd>
    <dt>Type</dt><dd>Prata and Jost. SIL Open Font License 1.1.</dd>
    <dt>Engines</dt><dd>Each engine's authors, license and source are listed with it above.</dd>
  </dl>
  <p class="dim small">Version ${esc(APP_VERSION)}</p>
</div>`;

  const drawThemes = () => {
    document.querySelectorAll('[data-theme]').forEach(b => {
      const t = THEMES.themes.find(x => x.id === b.dataset.theme);
      drawSwatch(b.querySelector('canvas'), t, pieceSet(), { cols: 4, rows: 4, pieces: [['bN', 1, 1], ['wP', 2, 2]] });
      b.setAttribute('aria-checked', String(t.id === theme().id));
    });
    document.querySelectorAll('[data-set]').forEach(b => {
      drawSwatch(b.querySelector('canvas'), theme(), b.dataset.set, { cols: 2, rows: 1, offset: [1, 0], pieces: [['wK', 0, 0, 0.86], ['bN', 1, 0, 0.86]] });
      b.setAttribute('aria-checked', String(b.dataset.set === pieceSet()));
    });
  };
  requestAnimationFrame(drawThemes);
  document.querySelectorAll('[data-theme]').forEach(b => b.addEventListener('click', () => { setPref('theme', b.dataset.theme); drawThemes(); }));
  document.querySelectorAll('[data-set]').forEach(b => b.addEventListener('click', () => { setPref('pieces', b.dataset.set); drawThemes(); }));
  document.getElementById('pace').addEventListener('change', e => setPref('pace', e.target.checked));
  document.getElementById('auto-queen').addEventListener('change', e => setPref('autoQueen', e.target.checked));
  document.getElementById('export-pgn').onclick = async () => saveFile('Zeist Chess games.pgn', log.exportPGN(await log.all()), 'application/x-chess-pgn');
  document.getElementById('export-json').onclick = async () => saveFile('Zeist Chess games.json', log.exportJSON(await log.all()), 'application/json');

  const confirming = new Set();
  const rows = document.getElementById('engine-rows');
  const drawEngines = async () => {
    const problem = shelf.problem();
    const pe = document.getElementById('catalog-problem');
    if (!pe) return;
    pe.hidden = !problem; pe.textContent = problem || '';
    rows.innerHTML = shelf.list().map(e => engineRow(e, confirming.has(e.manifest.id))).join('');
    const used = shelf.used();
    const st = await shelf.storage();
    const s = document.getElementById('storage');
    if (s) s.innerHTML = `<div class="storage-row"><span class="soft">Downloaded engines</span><span>${used ? shelf.say(used) : 'None yet'}</span></div>
      ${used ? `<p class="dim small">${st.persisted ? 'Kept in this browser until you delete them.' : 'Kept in this browser. It may clear them if space runs short.'}${st.quota ? ` ${shelf.say(st.quota)} available here.` : ''}</p>` : ''}`;
  };
  rows.addEventListener('click', async e => {
    const b = e.target.closest('button[data-act]');
    if (!b) return;
    const id = b.dataset.id;
    const act = b.dataset.act;
    if (act === 'download' || act === 'update') shelf.install(id).catch(() => {});
    else if (act === 'stop') shelf.cancel(id);
    else if (act === 'retry') { shelf.clearFailure(id); shelf.install(id).catch(() => {}); }
    else if (act === 'delete') { confirming.add(id); drawEngines(); }
    else if (act === 'keep') { confirming.delete(id); drawEngines(); }
    else if (act === 'delete-yes') { confirming.delete(id); if (play && play.manifest.id === id) { engine.release(); } await shelf.remove(id); }
  });
  const unsub = shelf.subscribe(drawEngines);
  drawEngines();
  shelf.refresh();
  if (anchor === 'engines') requestAnimationFrame(() => document.getElementById('engines')?.scrollIntoView({ block: 'start' }));
  cleanup = () => unsub();
}

function engineRow(e, confirming) {
  const m = e.manifest, id = esc(m.id);
  const d = shelf.download(m.id);
  const size = e.installed ? `${shelf.say(shelf.bytesOf(m))} in this browser` : e.builtIn ? `${shelf.say(shelf.bytesOf(m))}, downloaded on first play` : shelf.say(shelf.bytesOf(m));
  let action = '';
  if (d && !d.error) {
    const pct = Math.round(d.progress * 100);
    action = `<button class="ring" type="button" data-act="stop" data-id="${id}" aria-label="Downloading, ${pct} percent. Stop" style="--p:${d.progress}"><span class="ring-track"></span>${ICON.stop}</button>`;
  } else if (d && d.error) action = `<button class="pill small" type="button" data-act="retry" data-id="${id}">Retry</button>`;
  else if (e.installed && e.update && !confirming) action = `<button class="pill small" type="button" data-act="update" data-id="${id}">Update to version ${esc(e.update.version)}</button>
    <button class="text-btn" type="button" data-act="delete" data-id="${id}">Delete</button>`;
  else if (e.installed && !confirming) action = `<button class="text-btn" type="button" data-act="delete" data-id="${id}">Delete</button>`;
  else if (!e.installed) action = `<button class="pill small" type="button" data-act="download" data-id="${id}">Download</button>`;
  return `<li class="engine-row" data-engine-row="${id}">
  <div class="er-text">
    <div class="er-head"><span class="er-name">${esc(m.name)}</span>${m.version && m.version.length <= 9 ? `<span class="dim small">${esc(m.version)}</span>` : ''}</div>
    ${m.line ? `<p class="soft er-line">${esc(m.line)}</p>` : ''}
    <p class="dim small">${esc(size)}${m.source ? ` · <a class="link" href="${esc(m.source)}" rel="noopener">Source</a>` : ''}</p>
    ${m.license ? `<p class="dim small">${esc(m.license.replace(/ AND /g, ', '))}${m.author ? `. ${esc(m.author)}` : ''}</p>` : ''}
    ${d && d.error ? `<p class="soft small">${esc(d.error)} Try again.</p>` : ''}
    ${!e.installed && !d && shelf.wasDamaged(m.id) ? `<p class="soft small">Its files were changed in this browser, so it was removed. Download it again.</p>` : ''}
    ${confirming ? `<div class="confirm"><p class="soft small">Delete ${esc(m.name)}? It frees ${shelf.say(shelf.bytesOf(m))}. You can download it again.</p>
      <div class="row-actions left"><button class="pill small" type="button" data-act="delete-yes" data-id="${id}">Delete</button><button class="pill small" type="button" data-act="keep" data-id="${id}">Keep</button></div></div>` : ''}
  </div>
  <div class="er-action">${action}</div>
</li>`;
}

// Start

async function main() {
  const [t, s] = await Promise.all([
    fetch(new URL('core/board-themes.json', BASE)).then(r => r.json()),
    fetch(new URL('core/piece-sets.json', BASE)).then(r => r.json()),
  ]);
  THEMES = t; SETS = s;
  await shelf.load();
  // <base><id>: open Home with that engine picked, then keep the plain address.
  const named = addressedEngine();
  if (named) {
    history.replaceState(history.state, '', BASE + location.hash);
    if (await shelf.offerWhenListed(named)) { setPick({ engine: named }); setPref('pickedSince', true); }
  }
  addEventListener('hashchange', route);
  log.setAccount(account.current().user); // before the first screen: games are listed for whoever is signed in
  route();
  account.refresh().then(async a => {
    log.setAccount(a.user);
    if (a.user && a.user.owner) await log.stamp(a.user.owner, a.user.handle);
    const h = location.hash;
    if (h.startsWith('#/settings') || h.startsWith('#/recent')) { if (!h.match(/^#\/recent\/./)) route(); }
    else if ((h === '' || h === '#/' || h === '#') && !play) route(); // Continue belongs to whoever is signed in
  });
  if ('serviceWorker' in navigator) {
    // updateViaCache 'none': each update check fetches sw.js and shell.js (with the engine pins) from the network.
    navigator.serviceWorker.register(new URL('sw.js', BASE), { scope: BASE, updateViaCache: 'none' }).catch(e => console.warn('service worker:', e));
  }
}

main().catch(e => {
  console.error(e);
  app.innerHTML = `<div class="screen narrow"><h1 class="page-title">Zeist Chess</h1><p class="soft">Zeist Chess couldn't start here. Reload to try again.</p></div>`;
});
