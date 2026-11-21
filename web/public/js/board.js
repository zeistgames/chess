// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The board: squares and grain from a theme (core/board-themes.json), ivory and ebony pieces from a set, the last
// move in Zeist's orange, coordinates on the edge squares. Tap a piece then a square, or drag it. Pieces keep their
// identity from one position to the next, so they glide when they move instead of jumping.
//
// Squares are numbered as core/rules.js gives the board: 0 is a8, 63 is h1, row by row.

import { BASE } from './store.js';

const FILES = 'abcdefgh';
export const squareName = i => FILES[i % 8] + (8 - Math.floor(i / 8));
export const squareIndex = s => (8 - Number(s[1])) * 8 + FILES.indexOf(s[0]);

/** The board from a FEN's first field: 64 entries, "" or "wK", "bN" and so on. */
export function boardFromFEN(fen) {
  const out = [];
  for (const ch of String(fen).split(' ')[0]) {
    if (ch === '/') continue;
    if (/\d/.test(ch)) for (let k = 0; k < +ch; k++) out.push('');
    else out.push((ch === ch.toUpperCase() ? 'w' : 'b') + ch.toUpperCase());
  }
  return out.length === 64 ? out : Array(64).fill('');
}

/** A piece's picture, from the app's folder whichever page asks. */
export function pieceURL(set, piece) { return new URL(`pieces/${set}/${piece}.svg`, BASE).href; }

/** A small repeatable random sequence (xorshift), for the grain. */
function seeded(seed) {
  let s = (Math.imul(seed | 0, 0x9E3779B1) | 1) >>> 0;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return (s % 1000000) / 1000000; };
}

function rgba(hex, a) {
  const v = parseInt(String(hex).replace('#', ''), 16);
  return `rgba(${(v >> 16) & 255},${(v >> 8) & 255},${v & 255},${a})`;
}

/** Draws a theme's squares, grain and sheen on a canvas context, side by side pixels. */
export function drawGround(ctx, theme, side, { flipped = false, coords = false, cols = 8, rows = 8, offset = [0, 0] } = {}) {
  const cell = side / 8;
  const w = cell * cols, h = cell * rows;
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    const bc = c + offset[0], br = r + offset[1];
    const i = flipped ? (7 - br) * 8 + (7 - bc) : br * 8 + bc;
    const light = (Math.floor(i / 8) + (i % 8)) % 2 === 0;
    const x = c * cell, y = r * cell;
    ctx.fillStyle = light ? theme.light : theme.dark;
    ctx.fillRect(x, y, cell + 0.5, cell + 0.5);
    if (theme.grain && theme.grain.lines > 0) grain(ctx, theme.grain, x, y, cell, i, light);
  }
  const sheen = theme.grain && theme.grain.sheen != null ? theme.grain.sheen : 0.05;
  const g = ctx.createLinearGradient(0, 0, w * 0.6, h);
  g.addColorStop(0, `rgba(255,255,255,${sheen})`);
  g.addColorStop(0.5, 'rgba(0,0,0,0)');
  g.addColorStop(1, `rgba(0,0,0,${sheen * 1.3})`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  if (coords) coordinates(ctx, theme, cell, flipped);
}

/** Fine, nearly parallel lines that drift slowly, over a few soft streaks: the grain of a cut board. */
function grain(ctx, g, x, y, cell, square, light) {
  const rng = seeded((g.seed || 1) * 7919 + square * 104729 + 1);
  const across = g.direction === 'alternate' && !light;
  const len = cell, breadth = cell;
  ctx.save();
  ctx.beginPath();
  ctx.rect(x, y, cell, cell);
  ctx.clip();
  const color = g.color || '#000000';
  const phase = rng() * Math.PI * 2;
  const freq = 0.35 + rng() * 0.45;
  const drift = (rng() - 0.5) * breadth * 0.18;
  const line = (base, amp, ph) => {
    ctx.beginPath();
    for (let s = 0; s <= 16; s++) {
      const t = s / 16;
      const at = base + drift * t + Math.sin(t * Math.PI * 2 * freq + ph) * amp;
      const px = across ? x + at : x + t * len, py = across ? y + t * len : y + at;
      if (s === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
  };
  ctx.lineCap = 'butt';
  for (let k = 0; k < (g.bands || 0); k++) {
    ctx.lineWidth = breadth * (0.06 + rng() * 0.14);
    line(rng() * breadth, breadth * 0.03, phase);
    ctx.strokeStyle = rgba(color, (g.band_opacity || 0.05) * (0.5 + rng()));
    ctx.stroke();
  }
  const n = Math.max(1, g.lines), gap = breadth / n, amp = (g.wave == null ? 0.5 : g.wave) * gap;
  for (let k = -1; k <= n; k++) {
    const base = (k + 0.2 + rng() * 0.6) * gap;
    ctx.lineWidth = Math.max(0.35, (g.width || 0.007) * cell * (0.5 + rng() * 1.1));
    line(base, amp * (0.7 + rng() * 0.6), phase + rng() * 0.5);
    ctx.strokeStyle = rgba(color, (g.opacity || 0.1) * (0.35 + rng() * 1.0));
    ctx.stroke();
  }
  ctx.restore();
}

/** Files and ranks, small, on the edge squares. */
function coordinates(ctx, theme, cell, flipped) {
  const c = theme.coordinates;
  ctx.font = `500 ${Math.max(8, cell * 0.17)}px Jost, system-ui, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (let k = 0; k < 8; k++) {
    const file = flipped ? 7 - k : k, rank = flipped ? k + 1 : 8 - k;
    ctx.fillStyle = rgba((7 + k) % 2 === 0 ? c.on_light : c.on_dark, c.opacity);
    ctx.fillText(FILES[file], (k + 1) * cell - cell * 0.12, 8 * cell - cell * 0.15);
    ctx.fillStyle = rgba(k % 2 === 0 ? c.on_light : c.on_dark, c.opacity);
    ctx.fillText(String(rank), cell * 0.11, k * cell + cell * 0.16);
  }
}

let nextId = 1;
const reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

export class Board {
  /**
   * root: an empty element. onMove(uci) is called for a move the player makes. autoQueen(): whether a pawn
   * reaching the last rank becomes a queen without asking.
   */
  constructor(root, { onMove = () => {}, autoQueen = () => false, label = 'Chess board', coords = true } = {}) {
    this.root = root;
    this.coords = coords;
    this.onMove = onMove;
    this.autoQueen = autoQueen;
    root.classList.add('zcb');
    root.setAttribute('role', 'img');
    root.setAttribute('aria-label', label);
    root.innerHTML = '<canvas class="ground" aria-hidden="true"></canvas><canvas class="marks" aria-hidden="true"></canvas><div class="pieces" aria-hidden="true"></div>';
    this.groundEl = root.querySelector('.ground');
    this.marksEl = root.querySelector('.marks');
    this.piecesEl = root.querySelector('.pieces');
    this.state = { board: Array(64).fill(''), last: null, check: null, flipped: false, legal: [], mine: null };
    this.ids = Array(64).fill(null);
    this.els = new Map();
    this.selected = null;
    this.drag = null;
    this.theme = null;
    this.set = 'cburnett';
    this.size = 0;
    this.ro = new ResizeObserver(() => this.layout());
    this.ro.observe(root);
    root.addEventListener('pointerdown', e => this.down(e));
    root.addEventListener('pointermove', e => this.move(e));
    root.addEventListener('pointerup', e => this.up(e));
    root.addEventListener('pointercancel', () => this.cancelDrag());
    root.addEventListener('lostpointercapture', () => { if (this.drag && this.drag.lifted) this.cancelDrag(); });
    if (document.fonts) document.fonts.load('500 12px Jost').then(() => this.drawGround()).catch(() => {});
  }

  destroy() { this.ro.disconnect(); }

  setLook(theme, set) {
    const changedSet = set && set !== this.set;
    this.theme = theme;
    if (set) this.set = set;
    if (changedSet) for (const [id, el] of this.els) el.src = pieceURL(this.set, el.dataset.piece);
    this.drawGround();
    this.drawMarks();
  }

  /** state: { board, last (uci), check (square name), flipped, legal: [{ from, to, uci, promotion }], mine: "w" | "b" | null } */
  render(state) {
    const flipChanged = state.flipped !== this.state.flipped;
    this.state = { ...this.state, ...state };
    if (!this.state.mine || !this.state.legal.length) this.selected = null;
    this.placePieces(flipChanged);
    if (flipChanged) this.drawGround();
    this.drawMarks();
  }

  layout() {
    const s = this.root.clientWidth;
    if (!s || s === this.size) return;
    this.size = s;
    this.drawGround();
    this.drawMarks();
  }

  canvas(el) {
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    const px = Math.round(this.size * dpr);
    if (el.width !== px) { el.width = px; el.height = px; }
    const ctx = el.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, this.size, this.size);
    return ctx;
  }

  drawGround() {
    if (!this.theme || !this.size) return;
    drawGround(this.canvas(this.groundEl), this.theme, this.size, { flipped: this.state.flipped, coords: this.coords });
  }

  rectOf(i) {
    const cell = this.size / 8;
    const [c, r] = this.spot(i);
    return [c * cell, r * cell, cell];
  }

  spot(i) { return this.state.flipped ? [7 - (i % 8), 7 - Math.floor(i / 8)] : [i % 8, Math.floor(i / 8)]; }

  drawMarks() {
    if (!this.theme || !this.size) return;
    const ctx = this.canvas(this.marksEl);
    const m = this.theme.marks, s = this.state;
    const cell = this.size / 8;
    if (s.last) {
      const from = squareIndex(s.last.slice(0, 2)), to = squareIndex(s.last.slice(2, 4));
      let [x, y] = this.rectOf(from);
      ctx.fillStyle = rgba(m.last, m.last_from); ctx.fillRect(x, y, cell, cell);
      [x, y] = this.rectOf(to);
      ctx.fillStyle = rgba(m.last, m.last_to); ctx.fillRect(x, y, cell, cell);
      ctx.strokeStyle = rgba(m.last, m.last_outline); ctx.lineWidth = Math.max(1.5, cell * 0.04);
      ctx.strokeRect(x + ctx.lineWidth / 2, y + ctx.lineWidth / 2, cell - ctx.lineWidth, cell - ctx.lineWidth);
    }
    const sel = this.drag && this.drag.lifted ? this.drag.from : this.selected;
    if (sel != null) {
      const [x, y] = this.rectOf(sel);
      ctx.fillStyle = rgba(m.selected, m.selected_opacity); ctx.fillRect(x, y, cell, cell);
      ctx.strokeStyle = rgba(m.selected, 0.75); ctx.lineWidth = Math.max(1.5, cell * 0.04);
      ctx.strokeRect(x + ctx.lineWidth / 2, y + ctx.lineWidth / 2, cell - ctx.lineWidth, cell - ctx.lineWidth);
    }
    if (s.check) {
      const [x, y] = this.rectOf(squareIndex(s.check));
      const g = ctx.createRadialGradient(x + cell / 2, y + cell / 2, 0, x + cell / 2, y + cell / 2, cell * 0.62);
      g.addColorStop(0, rgba(m.check, 0.95)); g.addColorStop(0.5, rgba(m.check, 0.35)); g.addColorStop(1, rgba(m.check, 0));
      ctx.fillStyle = g; ctx.fillRect(x - cell * 0.1, y - cell * 0.1, cell * 1.2, cell * 1.2);
    }
    if (sel != null) {
      for (const to of new Set(this.targets(sel).map(l => l.to))) {
        const i = squareIndex(to);
        const [x, y] = this.rectOf(i);
        const capture = !!s.board[i] || this.targets(sel).some(l => l.to === to && l.capture);
        ctx.beginPath();
        if (capture) {
          const lw = Math.max(2.5, cell * 0.075);
          ctx.arc(x + cell / 2, y + cell / 2, cell / 2 - cell * 0.04 - lw / 2, 0, Math.PI * 2);
          ctx.strokeStyle = rgba(m.hint, Math.min(1, m.hint_opacity * 1.3)); ctx.lineWidth = lw; ctx.stroke();
        } else {
          ctx.arc(x + cell / 2, y + cell / 2, cell * 0.145, 0, Math.PI * 2);
          ctx.fillStyle = rgba(m.hint, m.hint_opacity); ctx.fill();
        }
      }
    }
  }

  /** Matches pieces of the last position to this one, so each keeps its element and glides. */
  placePieces(flipChanged) {
    const nb = this.state.board;
    const old = this.prev || Array(64).fill('');
    const oldIds = this.ids;
    const ids = Array(64).fill(null);
    const used = new Set();
    for (let i = 0; i < 64; i++) if (nb[i] && old[i] === nb[i] && oldIds[i] != null) { ids[i] = oldIds[i]; used.add(oldIds[i]); }
    for (let i = 0; i < 64; i++) {
      if (!nb[i] || ids[i] != null) continue;
      let best = null, bestD = 99;
      for (let j = 0; j < 64; j++) {
        if (old[j] !== nb[i] || oldIds[j] == null || used.has(oldIds[j]) || nb[j] === old[j]) continue;
        const d = Math.hypot((i % 8) - (j % 8), Math.floor(i / 8) - Math.floor(j / 8));
        if (d < bestD) { bestD = d; best = j; }
      }
      if (best != null) { ids[i] = oldIds[best]; used.add(oldIds[best]); } else ids[i] = nextId++;
    }
    const keep = new Set(ids.filter(x => x != null));
    for (const [id, el] of this.els) {
      if (keep.has(id)) continue;
      this.els.delete(id);
      el.classList.add('gone');
      setTimeout(() => el.remove(), reduceMotion() ? 0 : 180);
    }
    for (let i = 0; i < 64; i++) {
      const id = ids[i];
      if (id == null) continue;
      let el = this.els.get(id);
      const [c, r] = this.spot(i);
      if (!el) {
        el = document.createElement('img');
        el.className = 'zcp arriving';
        el.alt = '';
        el.draggable = false;
        this.piecesEl.append(el);
        this.els.set(id, el);
        requestAnimationFrame(() => el.classList.remove('arriving'));
      }
      if (el.dataset.piece !== nb[i]) { el.dataset.piece = nb[i]; el.src = pieceURL(this.set, nb[i]); }
      if (flipChanged) el.classList.add('still');
      el.style.transform = `translate(${c * 100}%, ${r * 100}%)`;
      el.dataset.square = i;
      if (flipChanged) requestAnimationFrame(() => el.classList.remove('still'));
    }
    this.ids = ids;
    this.prev = nb.slice();
  }

  targets(i) { return (this.state.legal || []).filter(l => l.from === squareName(i)); }

  squareAt(e) {
    const r = this.root.getBoundingClientRect();
    const c = Math.floor((e.clientX - r.left) / (r.width / 8)), w = Math.floor((e.clientY - r.top) / (r.height / 8));
    if (c < 0 || c > 7 || w < 0 || w > 7) return null;
    return this.state.flipped ? (7 - w) * 8 + (7 - c) : w * 8 + c;
  }

  mineAt(i) { return i != null && this.state.mine && this.state.board[i] && this.state.board[i][0] === this.state.mine && this.targets(i).length >= 0 && this.state.legal.length > 0; }

  down(e) {
    if (e.button && e.button !== 0) return;
    if (this.promo) return;
    const i = this.squareAt(e);
    if (i == null) return;
    this.drag = { from: i, x: e.clientX, y: e.clientY, lifted: false, id: e.pointerId };
    if (this.mineAt(i)) { try { this.root.setPointerCapture(e.pointerId); } catch {} }
  }

  move(e) {
    const d = this.drag;
    if (!d || d.id !== e.pointerId) return;
    const cell = this.size / 8;
    if (!d.lifted) {
      if (Math.hypot(e.clientX - d.x, e.clientY - d.y) < Math.max(6, cell * 0.12) || !this.mineAt(d.from)) return;
      d.lifted = true;
      d.el = this.els.get(this.ids[d.from]);
      if (d.el) d.el.classList.add('lifted');
      this.selected = null;
      this.drawMarks();
    }
    if (d.el) {
      const r = this.root.getBoundingClientRect();
      const x = e.clientX - r.left - cell / 2, y = e.clientY - r.top - cell * 0.75;
      d.el.style.transform = `translate(${x}px, ${y}px) scale(1.18)`;
    }
  }

  up(e) {
    const d = this.drag;
    if (!d || d.id !== e.pointerId) return;
    this.drag = null;
    if (d.lifted) {
      const to = this.squareAt(e);
      if (d.el) d.el.classList.remove('lifted');
      if (to != null && to !== d.from && this.targets(d.from).some(l => l.to === squareName(to))) {
        if (d.el) { d.el.classList.add('still'); d.el.style.transform = `translate(${this.spot(to)[0] * 100}%, ${this.spot(to)[1] * 100}%)`; requestAnimationFrame(() => d.el && d.el.classList.remove('still')); }
        this.attempt(d.from, to);
      } else {
        this.placeBack(d);
        this.selected = d.from;
        this.drawMarks();
      }
      return;
    }
    this.tap(d.from);
  }

  placeBack(d) {
    if (!d.el) return;
    const [c, r] = this.spot(d.from);
    d.el.style.transform = `translate(${c * 100}%, ${r * 100}%)`;
  }

  cancelDrag() {
    const d = this.drag;
    this.drag = null;
    if (d && d.lifted) { if (d.el) d.el.classList.remove('lifted'); this.placeBack(d); this.drawMarks(); }
  }

  tap(i) {
    if (this.selected != null) {
      if (this.selected === i) { this.selected = null; this.drawMarks(); return; }
      if (this.targets(this.selected).some(l => l.to === squareName(i))) { this.attempt(this.selected, i); return; }
    }
    this.selected = this.mineAt(i) ? i : null;
    this.drawMarks();
  }

  /** Clears any selection, as after an engine move or when stepping through the game. */
  deselect() { this.selected = null; this.closePromo(); this.drawMarks(); }

  attempt(from, to) {
    const options = this.targets(from).filter(l => l.to === squareName(to));
    this.selected = null;
    if (!options.length) { this.drawMarks(); return; }
    if (options.length > 1) {
      if (this.autoQueen()) { this.onMove(options.find(o => o.promotion === 'q').uci); return; }
      this.openPromo(from, to);
      return;
    }
    this.drawMarks();
    this.onMove(options[0].uci);
  }

  openPromo(from, to) {
    this.closePromo();
    const color = this.state.board[from][0];
    const [c, r] = this.spot(to);
    const down = r < 4;
    const wrap = document.createElement('div');
    wrap.className = 'promo';
    const col = document.createElement('div');
    col.className = 'promo-col';
    col.style.left = `${c * 12.5}%`;
    col.style.top = down ? `${r * 12.5}%` : `${(r - 3) * 12.5}%`;
    const kinds = down ? ['q', 'r', 'b', 'n'] : ['n', 'b', 'r', 'q'];
    const names = { q: 'Queen', r: 'Rook', b: 'Bishop', n: 'Knight' };
    for (const k of kinds) {
      const b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('aria-label', names[k]);
      b.dataset.promote = k;
      b.innerHTML = `<img alt="" src="${pieceURL(this.set, color + k.toUpperCase())}">`;
      b.addEventListener('click', ev => { ev.stopPropagation(); this.closePromo(); this.onMove(squareName(from) + squareName(to) + k); });
      col.append(b);
    }
    wrap.append(col);
    wrap.addEventListener('pointerdown', ev => ev.stopPropagation());
    wrap.addEventListener('click', () => { this.closePromo(); this.render({}); });
    this.root.append(wrap);
    this.promo = wrap;
    const first = col.querySelector('button');
    if (first) first.focus({ preventScroll: true });
  }

  closePromo() { if (this.promo) { this.promo.remove(); this.promo = null; } }
}

/** A still board drawn once on a canvas, for swatches. cols and rows say how much of the board shows. */
export function drawSwatch(canvas, theme, set, { cols = 4, rows = 4, offset = [0, 0], pieces = [] } = {}) {
  const dpr = Math.min(3, window.devicePixelRatio || 1);
  const w = canvas.clientWidth || canvas.width, cell = w / cols;
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(cell * rows * dpr);
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  drawGround(ctx, theme, cell * 8, { cols, rows, offset });
  return Promise.all(pieces.map(([piece, c, r, scale = 0.9]) => new Promise(done => {
    const img = new Image();
    img.onload = () => {
      const s = cell * scale;
      ctx.save();
      ctx.shadowColor = 'rgba(0,0,0,.3)'; ctx.shadowBlur = 2; ctx.shadowOffsetY = 1;
      ctx.drawImage(img, c * cell + (cell - s) / 2, r * cell + (cell - s) / 2, s, s);
      ctx.restore();
      done();
    };
    img.onerror = done;
    img.src = pieceURL(set, piece);
  })));
}
