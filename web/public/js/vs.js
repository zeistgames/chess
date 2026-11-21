// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One engine's page under Zeist's Chess, <base><id>/ (zeist.gg/chess/vs/<id>/), drawn as Zeist's own Chess screens:
//   the start screen: the board set up, the engine, its level (1 to 10) or for Maia a rating, the side, the clock
//     (none, 10+5 or 15+10), Play, and Continue for a game in progress against it;
//   the game: the board, the players and clocks, the moves, the menu, the result.
// The engine is downloaded on the first game and kept in this browser (shelf.js); it runs here, in a Web Worker
// (engine.js). Games are kept in this browser (log.js). They are never rated and never sent anywhere. Back goes to
// Zeist's Chess.

import { Board, boardFromFEN, pieceURL } from './board.js';
import * as shelf from './shelf.js';
import * as log from './log.js';
import * as account from './account.js';
import * as material from './material.js';
import { Play, sayClock } from './play.js';
import { Game, START } from '../core/rules.js';
import { get as pref, set as setPref, BASE } from './store.js';

const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const DATA = JSON.parse($('engine-data').textContent);
const ID = DATA.id;
const SET = 'zeist';
const CLOCKS = { none: null, '10+5': { base: 600, increment: 5 }, '15+10': { base: 900, increment: 10 } };
const COLOR = { w: 'White', b: 'Black' };
const FACE = document.querySelector('#opponent .zface').innerHTML;

let theme = null;
let play = null; // the game on screen
let still = null; // the start screen's board

// Choices, kept for next time: the level or rating for each engine, the side and the clock for all of them.
function choices() {
  const all = pref('vs', {}) || {};
  const mine = (all.engines || {})[ID] || {};
  const level = Number.isInteger(mine.level) && mine.level >= 1 && mine.level <= 10 ? mine.level : 3;
  const r = DATA.range;
  const rating = r ? Math.min(r[1], Math.max(r[0], Math.round((+mine.rating || 1500) / 50) * 50)) : null;
  return { level, rating, side: ['w', 'b', 'either'].includes(all.side) ? all.side : 'either', clock: all.clock in CLOCKS ? all.clock : 'none' };
}
function choose(changes) {
  const all = pref('vs', {}) || {};
  const engines = { ...(all.engines || {}) };
  const { level, rating, ...rest } = changes;
  if (level != null || rating != null) engines[ID] = { ...(engines[ID] || {}), ...(level != null ? { level } : {}), ...(rating != null ? { rating } : {}) };
  setPref('vs', { ...all, ...rest, engines });
}

// The start screen

function drawChoices() {
  const c = choices();
  document.querySelectorAll('#lvls [data-level]').forEach(b => b.setAttribute('aria-checked', String(+b.dataset.level === c.level)));
  document.querySelectorAll('#sides [data-side]').forEach(b => b.setAttribute('aria-checked', String(b.dataset.side === c.side)));
  document.querySelectorAll('#clocks [data-clock]').forEach(b => b.setAttribute('aria-checked', String(b.dataset.clock === c.clock)));
  const r = $('rating');
  if (r) { r.value = String(c.rating); $('rating-value').textContent = String(c.rating); }
  if (still) still.render({ board: boardFromFEN(START), flipped: c.side === 'b', last: null, legal: [], mine: null });
}

let downloading = false;
function note(text) { $('home-note').textContent = text; }
function drawNote() {
  if (downloading) return;
  const e = shelf.engine(ID);
  const rating = DATA.range ? 'Plays like people at this rating.' : '';
  if (e && e.installed) { note(rating); return; }
  const size = shelf.say(DATA.bytes);
  if (shelf.wasDamaged(ID)) { note(`Its files were changed in this browser, so it was removed. Play downloads it again (${size}).`); return; }
  note(rating ? `${rating} Your first game downloads it (${size}).` : `Your first game downloads it (${size}). After that it plays offline.`);
}

async function drawResume() {
  const g = await log.current();
  $('resume').hidden = !(g && g.engineID === ID && !(play && play.record.id === g.id && play.over));
}

function radios(box, fn) {
  if (!box) return;
  box.addEventListener('click', e => { const b = e.target.closest('button'); if (b) { fn(b); drawChoices(); } });
  // Arrow keys move along a row of choices, as in any radio group.
  box.addEventListener('keydown', e => {
    if (!['ArrowLeft', 'ArrowRight'].includes(e.key)) return;
    const list = [...box.querySelectorAll('button')];
    const i = list.indexOf(document.activeElement);
    if (i < 0) return;
    e.preventDefault();
    e.stopPropagation();
    const next = list[(i + (e.key === 'ArrowRight' ? 1 : list.length - 1)) % list.length];
    next.focus();
    next.click();
  });
}

function startScreen() {
  still = new Board($('still'), { label: 'The board, set up', coords: false });
  still.setLook(theme, SET);
  radios($('lvls'), b => choose({ level: +b.dataset.level }));
  radios($('sides'), b => choose({ side: b.dataset.side }));
  radios($('clocks'), b => choose({ clock: b.dataset.clock }));
  const r = $('rating');
  if (r) r.addEventListener('input', () => { $('rating-value').textContent = r.value; choose({ rating: +r.value }); });
  $('go').addEventListener('click', () => start());
  $('resume').addEventListener('click', () => resume());
  drawChoices();
  drawNote();
  shelf.subscribe(() => drawNote());
}

async function start() {
  const btn = $('go');
  if (downloading) return;
  let entry = shelf.engine(ID);
  if (!entry) { await shelf.listed(); entry = shelf.engine(ID); }
  if (!entry) {
    note(navigator.onLine === false ? `${DATA.name} needs a connection once, to download. Then it plays offline.` : `${DATA.name} couldn't be loaded. Try again in a moment.`);
    return;
  }
  if (!entry.installed) {
    downloading = true;
    btn.disabled = true;
    const unsub = shelf.subscribe(() => {
      const d = shelf.download(ID);
      if (d && !d.error) note(`Getting ${DATA.name} ready. ${Math.round(d.progress * 100)}%`);
    });
    note(`Getting ${DATA.name} ready.`);
    try {
      await shelf.install(ID);
    } catch (e) {
      unsub();
      downloading = false;
      btn.disabled = false;
      note(navigator.onLine === false ? `${DATA.name} needs a connection once, to download. Then it plays offline.` : `${e.message} Try again.`);
      return;
    }
    unsub();
    downloading = false;
    btn.disabled = false;
    drawNote();
    entry = shelf.engine(ID);
  }
  const c = choices();
  const side = c.side === 'either' ? (crypto.getRandomValues(new Uint8Array(1))[0] < 128 ? 'w' : 'b') : c.side;
  if (play) { play.pause(); play = null; }
  const P = await Play.begin({ entry, player: side, level: c.level, adaptive: false, rating: DATA.range ? c.rating : null, timeControl: CLOCKS[c.clock] });
  showGame(P);
}

async function resume() {
  const g = await log.current();
  const entry = shelf.engine(ID);
  if (!g || g.engineID !== ID) { drawResume(); return; }
  if (!entry || !entry.installed) { note(`${DATA.name} isn't in this browser anymore. Play downloads it again and starts a game.`); $('resume').hidden = true; return; }
  showGame(new Play(g, entry));
}

// The game

const FIG = san => {
  const m = /^[KQRBN]/.exec(san);
  const promo = /=([QRBN])/.exec(san);
  let body = esc(m ? san.slice(1) : san);
  if (promo) body = body.replace(`=${promo[1]}`, `=<i class="fig" style="--m:url(${pieceURL(SET, 'b' + promo[1])})"></i>`);
  return m ? `<i class="fig" style="--m:url(${pieceURL(SET, 'b' + m[0])})"></i>${body}` : body;
};

const REASON = {
  stalemate: 'Stalemate: no legal move, and not in check.',
  repetition: 'The same position came up three times.',
  'fifty-move': '50 moves each with no capture or pawn move.',
  insufficient: 'Neither side has the pieces to checkmate.',
  'timeout-insufficient': 'Time ran out, but the other side has too few pieces to checkmate.',
};

function showGame(P) {
  play = P;
  $('home').hidden = true;
  $('play').hidden = false;
  $('play').classList.remove('ended');
  window.scrollTo(0, 0);
  if (!showGame.board) {
    showGame.board = new Board($('board'), { onMove: uci => { if (view == null && play) play.move(uci); }, label: 'The game board' });
    showGame.board.setLook(theme, SET);
  }
  view = null;
  flipped = P.player === 'b';
  dismissed = false;
  confirmResign = false;
  let seen = P.record.moves.length;
  P.onChange = () => { if (P.record.moves.length !== seen || P.over) { seen = P.record.moves.length; showGame.board.deselect(); } render(); };
  render();
  P.open();
  $('back').focus({ preventScroll: true });
}

let view = null; // a ply being looked at, or null for the live position
let flipped = false;
let dismissed = false; // the result was put away to see the board
let confirmResign = false;
let resignTimer = 0;

function render() {
  const P = play;
  if (!P) return;
  const r = P.record;
  const n = r.moves.length;
  if (view != null && view >= n) view = null;
  const at = view == null ? n : view;
  const snap = view == null ? P.snap : Game.fromMoves(r.moves.slice(0, at), r.startFEN).snapshot();
  const live = view == null && !P.over;
  showGame.board.render({
    board: snap.board, last: at ? r.moves[at - 1] : null, check: snap.check, flipped,
    legal: live && P.myTurn ? snap.legal : [], mine: live && P.myTurn ? P.player : null,
  });
  const strength = log.difficulty(r);
  const tc = r.timeControl ? ` · ${log.tcName(r.timeControl)}` : '';
  $('title-sub').textContent = `${DATA.name} · ${strength} · Not rated`;
  $('side-sub').textContent = `${strength} · You play ${COLOR[P.player]}${tc} · Not rated`;
  const eng = P.player === 'w' ? 'b' : 'w';
  const top = flipped === (P.player === 'b') ? eng : P.player;
  playerRow($('top'), top, snap.board, at);
  playerRow($('bottom'), top === 'w' ? 'b' : 'w', snap.board, at);
  moves(at);
  $('say').textContent = say(at);
  $('step-back').disabled = at === 0;
  $('step-fwd').disabled = view == null;
  $('resign').hidden = P.over;
  $('undo').hidden = P.over || P.timed;
  $('undo').disabled = !P.canUndo;
  $('again-menu').hidden = !P.over;
  $('retry').hidden = !P.trouble || P.over;
  endCard();
}

function clockAt(side, at) {
  const P = play, r = P.record;
  if (!r.timeControl) return null;
  if (view == null) return P.clock ? P.clock.remaining(side) : (r.clockLeft ? r.clockLeft[side === 'w' ? 0 : 1] : null);
  // Looking back: each side's time after its last move up to there.
  const whiteFirst = r.startFEN.split(' ')[1] !== 'b';
  for (let i = at - 1; i >= 0; i--) {
    const mover = (i % 2 === 0) === whiteFirst ? 'w' : 'b';
    if (mover === side && r.clocks && r.clocks[i] != null) return r.clocks[i];
  }
  return r.timeControl.base * 1000;
}

function playerRow(el, side, board, at) {
  const P = play;
  const engine = side !== P.player;
  const turn = !P.over && view == null && P.game.turn() === side;
  const me = account.current().user;
  const name = engine ? DATA.name : (me && me.handle) || 'You';
  const meta = engine ? log.difficulty(P.record) : '';
  let pill = '';
  if (turn) pill = engine ? (P.thinking ? 'Thinking' : '') : 'Your move';
  let caps = '', prev = '';
  for (const { kind, count } of material.captured(side, board)) {
    for (let k = 0; k < count; k++) { caps += `<i class="fig${prev && prev !== kind ? ' gap' : ''}" style="--m:url(${pieceURL(SET, 'b' + kind)})"></i>`; prev = kind; }
  }
  const lead = material.lead(side, board);
  if (lead > 0) caps += `<em>+${lead}</em>`;
  const face = engine ? `<span class="zface" aria-hidden="true">${FACE}</span>` : `<span class="pface stone s${side === 'w' ? 0 : 1}" aria-hidden="true"></span>`;
  const ms = clockAt(side, at);
  let clock = '';
  if (ms != null) {
    const t = P.clock;
    const running = view == null && t && t.running === side && !t.paused && !P.over;
    const low = t && ms < t.lowTime();
    clock = `<span class="clk${running ? ' run' : ''}${low ? ' low' : ''}" role="timer" aria-label="${esc(name)}: ${Math.floor(ms / 60000)} minutes ${Math.floor(ms / 1000) % 60} seconds left">${sayClock(ms)}</span>`;
  }
  el.className = `prow${turn ? ' on' : ''}`;
  el.innerHTML = `${face}<div class="who"><b>${esc(name)}</b>${meta ? `<span>${esc(meta)}</span>` : ''}<div class="cap" aria-label="Captured">${caps}</div></div>${pill ? `<div class="st">${pill}</div>` : ''}${clock}`;
}

function moves(at) {
  const sans = play.record.san;
  const cur = at - 1;
  let h = '', list = '';
  for (let i = 0; i < sans.length; i++) {
    if (i % 2 === 0) h += `<span class="n">${i / 2 + 1}.</span>`;
    h += `<span class="mv${i === cur ? ' cur' : ''}" data-ply="${i + 1}">${FIG(sans[i])}</span>`;
  }
  for (let i = 0; i < sans.length; i += 2) {
    list += `<div class="r"><span class="n">${i / 2 + 1}.</span><span class="mv${i === cur ? ' cur' : ''}" data-ply="${i + 1}"><span>${FIG(sans[i])}</span></span><span class="mv${i + 1 === cur ? ' cur' : ''}" data-ply="${i + 2}"><span>${sans[i + 1] ? FIG(sans[i + 1]) : ''}</span></span></div>`;
  }
  const line = $('line');
  if (line.dataset.h !== h) {
    line.dataset.h = h;
    line.innerHTML = h || '<span class="n">Moves show here.</span>';
    $('list').innerHTML = list || '<div class="r empty"><span></span><span>Moves show here.</span></div>';
  }
  const c = line.querySelector('.cur') || line.lastElementChild;
  if (c) line.scrollLeft = c.offsetLeft + c.offsetWidth - line.clientWidth + 16;
  const tc = $('list').querySelector('.cur');
  if (tc) tc.scrollIntoView({ block: 'nearest' });
}

function say(at) {
  const P = play;
  if (P.trouble) return P.trouble;
  if (view != null) return `Move ${Math.ceil(at / 2) || 1} of ${Math.ceil(P.record.moves.length / 2)}. Forward returns to the game.`;
  if (P.over) return dismissed ? `${headline()} ${reasonLine()}` : '';
  if (P.clock && P.clock.paused && P.record.moves.length && !P.thinking) return 'The clocks are stopped.';
  if (P.game.inCheck() && P.myTurn) return 'Check.';
  if (!P.record.moves.length && P.player === 'w') return "Your move. You're White.";
  return '';
}

function headline() {
  const o = log.outcome(play.record);
  return o === 'win' ? 'You won.' : o === 'loss' ? 'You lost.' : 'Draw.';
}

function reasonLine() {
  const r = play.record;
  const moves = Math.ceil(r.moves.length / 2);
  const o = log.outcome(r);
  let line;
  if (r.ending === 'checkmate') line = `Checkmate in ${moves} move${moves === 1 ? '' : 's'}.`;
  else if (r.ending === 'resigned') line = 'You resigned.';
  else if (r.ending === 'timeout') line = o === 'win' ? `${DATA.name} ran out of time.` : 'Your time ran out.';
  else line = REASON[r.ending] || '';
  return line.replace(/\.$/, `, against ${DATA.name} at ${log.difficulty(r).toLowerCase()}.`);
}

function endCard() {
  const P = play;
  const show = P.over && !dismissed;
  $('end').hidden = !show;
  $('play').classList.toggle('ended', show);
  if (!show) return;
  $('end-title').textContent = headline();
  $('end-line').textContent = reasonLine();
}

function step(d) {
  if (!play) return;
  const n = play.record.moves.length;
  const at = Math.max(0, Math.min(n, (view == null ? n : view) + d));
  view = at >= n ? null : at;
  showGame.board.deselect();
  render();
}

function openMenu() {
  $('menu').hidden = false;
  $('menu-btn').setAttribute('aria-expanded', 'true');
  $('menu').querySelector('button:not([hidden]):not(:disabled)')?.focus();
}
function closeMenu() {
  $('menu').hidden = true;
  $('menu-btn').setAttribute('aria-expanded', 'false');
  confirmResign = false;
  clearTimeout(resignTimer);
  $('resign').querySelector('span').textContent = 'Resign';
}

function gameControls() {
  $('menu-btn').addEventListener('click', () => ($('menu').hidden ? openMenu() : closeMenu()));
  $('scrim').addEventListener('click', closeMenu);
  $('flip').addEventListener('click', () => { flipped = !flipped; closeMenu(); render(); });
  $('undo').addEventListener('click', () => { closeMenu(); view = null; showGame.board.deselect(); play.undo(); });
  $('again-menu').addEventListener('click', () => { closeMenu(); again(); });
  $('resign').addEventListener('click', () => {
    if (!confirmResign) {
      confirmResign = true;
      $('resign').querySelector('span').textContent = 'Tap again to resign';
      resignTimer = setTimeout(() => { confirmResign = false; $('resign').querySelector('span').textContent = 'Resign'; }, 5000);
      return;
    }
    closeMenu();
    play.resign();
  });
  $('step-back').addEventListener('click', () => step(-1));
  $('step-fwd').addEventListener('click', () => step(1));
  $('retry').addEventListener('click', () => play && play.retry());
  $('end-again').addEventListener('click', () => again());
  $('end-see').addEventListener('click', () => { dismissed = true; render(); });
  const onPly = e => {
    const b = e.target.closest('[data-ply]');
    if (!b || !play) return;
    const ply = +b.dataset.ply;
    view = ply >= play.record.moves.length ? null : ply;
    showGame.board.deselect();
    render();
  };
  $('line').addEventListener('click', onPly);
  $('list').addEventListener('click', onPly);
  addEventListener('keydown', e => {
    if ($('play').hidden || !play || $('rules').open || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'Escape') { if (!$('menu').hidden) closeMenu(); else showGame.board.deselect(); return; }
    if (e.target.closest('input, textarea, select, [role="radiogroup"]')) return;
    const n = play.record.moves.length;
    let next = null;
    if (e.key === 'ArrowLeft') next = Math.max(0, (view == null ? n : view) - 1);
    else if (e.key === 'ArrowRight') next = Math.min(n, (view == null ? n : view) + 1);
    else if (e.key === 'Home' || e.key === 'ArrowUp') next = 0;
    else if (e.key === 'End' || e.key === 'ArrowDown') next = n;
    else if (e.key === 'Enter' && play.over && !dismissed) { again(); return; }
    else return;
    e.preventDefault();
    view = next >= n ? null : next;
    showGame.board.deselect();
    render();
  });
  // The clocks stop while the game is out of sight, and when leaving: the game is kept.
  setInterval(() => { if (play && play.clock && !play.over && !$('play').hidden) { play.tick(); if (!play.over) render(); } }, 100);
  document.addEventListener('visibilitychange', () => { if (!play || $('play').hidden) return; if (document.hidden) play.pause(); else play.resume(); });
  addEventListener('pagehide', () => { if (play && !play.over) play.pause(); });
  $('back').addEventListener('click', () => { if (play && !play.over) play.pause(); });
  $('end-home').addEventListener('click', () => { if (play && !play.over) play.pause(); });
}

function again() {
  $('play').hidden = true;
  $('home').hidden = false;
  if (play) play.pause();
  play = null;
  drawResume();
  start();
}

// How to play, with the engine's license and source, and the space it takes here

function rules() {
  const dlg = $('rules');
  const kept = () => {
    const e = shelf.engine(ID);
    $('kept').hidden = !(e && e.installed);
    if (e && e.installed) $('kept-line').textContent = `It takes ${shelf.say(shelf.bytesOf(e.manifest))} in this browser.`;
  };
  const open = () => { kept(); if (play && !play.over && !$('play').hidden) play.pause(); dlg.showModal(); };
  $('home-rules').addEventListener('click', open);
  $('open-rules').addEventListener('click', open);
  $('close-rules').addEventListener('click', () => dlg.close());
  dlg.addEventListener('close', () => { if (play && !play.over && !$('play').hidden) play.resume(); });
  $('remove').addEventListener('click', async () => {
    const g = await log.current();
    if (g && g.engineID === ID) await log.abandon(g.id);
    await shelf.remove(ID);
    kept();
    drawResume();
    drawNote();
  });
}

// Start

async function main() {
  theme = (await (await fetch(new URL('core/board-themes.json', BASE))).json()).themes.find(t => t.id === 'bone');
  log.setAccount(account.current().user);
  startScreen();
  gameControls();
  rules();
  await shelf.load();
  drawNote();
  drawResume();
  account.refresh().then(async a => {
    log.setAccount(a.user);
    if (a.user && a.user.owner) await log.stamp(a.user.owner, a.user.handle);
    if (!play) drawResume();
    else render();
  });
  if ('serviceWorker' in navigator) {
    // updateViaCache 'none': each update check fetches sw.js and shell.js (with the engine pins) from the network.
    navigator.serviceWorker.register(new URL('sw.js', BASE), { scope: BASE, updateViaCache: 'none' }).catch(e => console.warn('service worker:', e));
  }
}

main().catch(e => {
  console.error(e);
  note(`Chess couldn't start here. Reload to try again.`);
});

