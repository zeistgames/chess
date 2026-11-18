// SPDX-License-Identifier: AGPL-3.0-or-later
// Small pieces shared by the screens: escaping, icons, the mark, sheets, downloads.

export const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const svg = (body, vb = '0 0 24 24') => `<svg viewBox="${vb}" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

export const ICON = {
  back: svg('<path d="M14.5 5.5 8 12l6.5 6.5"/>'),
  forward: svg('<path d="M9.5 5.5 16 12l-6.5 6.5"/>'),
  start: svg('<path d="M7 5.5v13"/><path d="M17 5.5 10.5 12l6.5 6.5"/>'),
  end: svg('<path d="M17 5.5v13"/><path d="M7 5.5 13.5 12 7 18.5"/>'),
  recent: svg('<path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3"/><path d="M4.2 4.6v3.3h3.3"/><path d="M12 8v4.3l2.8 1.8"/>'),
  settings: svg('<circle cx="12" cy="12" r="2.9"/><path d="M19.4 13.6a7.7 7.7 0 0 0 0-3.2l2-1.5-2-3.4-2.3 1a7.6 7.6 0 0 0-2.8-1.6L14 2.5h-4l-.3 2.4a7.6 7.6 0 0 0-2.8 1.6l-2.3-1-2 3.4 2 1.5a7.7 7.7 0 0 0 0 3.2l-2 1.5 2 3.4 2.3-1a7.6 7.6 0 0 0 2.8 1.6l.3 2.4h4l.3-2.4a7.6 7.6 0 0 0 2.8-1.6l2.3 1 2-3.4z"/>'),
  updown: svg('<path d="m8 9.5 4-4 4 4"/><path d="m8 14.5 4 4 4-4"/>'),
  check: svg('<path d="m5 12.5 4.5 4.5L19 7.5"/>'),
  stop: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8.5" y="8.5" width="7" height="7" rx="1.2" fill="currentColor"/></svg>',
  flip: svg('<path d="M7 4.5v15"/><path d="m3.5 8 3.5-3.5L10.5 8"/><path d="M17 19.5v-15"/><path d="m13.5 16 3.5 3.5 3.5-3.5"/>'),
};

/** The Zeist mark with a pawn on its inner point, as on the app's icon. */
export function mark(cls = 'mark') {
  return `<svg class="${cls}" viewBox="-3 -3 82 82" aria-hidden="true" focusable="false">
<defs><mask id="zc-pawn-cut"><rect x="-3" y="-3" width="82" height="82" fill="#fff"/><path d="${PAWN}" fill="#000" stroke="#000" stroke-width="11.2" stroke-linejoin="round"/></mask></defs>
<g mask="url(#zc-pawn-cut)" stroke="currentColor" stroke-width="4.5" stroke-linecap="round"><path d="M76 0H0M76 32H0M76 64H0M76 0v76M44 0v76M12 0v76"/></g>
<path d="${PAWN}" fill="currentColor"/></svg>`;
}

// The pawn of the icon, centered on the inner point (44, 32.4) at scale 1.12.
const PAWN = (() => {
  const cx = 44, cy = 32.4, s = 1.12, P = (x, y) => `${(cx + x * s).toFixed(2)} ${(cy + y * s).toFixed(2)}`;
  const r = 6.3 * s;
  return [
    `M${P(-6.3, -10.6)}a${r} ${r} 0 1 0 ${(12.6 * s).toFixed(2)} 0a${r} ${r} 0 1 0 ${(-12.6 * s).toFixed(2)} 0Z`,
    `M${P(-8.2, -4.6)}h${(16.4 * s).toFixed(2)}v${(3.6 * s).toFixed(2)}h${(-16.4 * s).toFixed(2)}Z`,
    `M${P(-4.9, -2)}C${P(-4.9, 5.2)} ${P(-9.6, 8.6)} ${P(-11.6, 12.4)}L${P(11.6, 12.4)}C${P(9.6, 8.6)} ${P(4.9, 5.2)} ${P(4.9, -2)}Z`,
    `M${P(-13.6, 11.4)}h${(27.2 * s).toFixed(2)}v${(4.8 * s).toFixed(2)}h${(-27.2 * s).toFixed(2)}Z`,
  ].join('');
})();

/** A sheet from the bottom of the screen. Returns close(). onClose runs once it is gone. */
export function sheet(build, { label = 'Options', onClose } = {}) {
  const back = document.createElement('div');
  back.className = 'sheet-back';
  const panel = document.createElement('div');
  panel.className = 'sheet';
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-modal', 'true');
  panel.setAttribute('aria-label', label);
  panel.innerHTML = '<div class="grip" aria-hidden="true"></div><div class="sheet-body"></div>';
  const opener = document.activeElement;
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    removeEventListener('keydown', key);
    back.classList.remove('open');
    panel.classList.remove('open');
    const done = () => { back.remove(); panel.remove(); if (onClose) onClose(); if (opener && opener.focus) opener.focus({ preventScroll: true }); };
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) done(); else setTimeout(done, 240);
  };
  const key = e => { if (e.key === 'Escape') { e.preventDefault(); close(); } };
  back.addEventListener('click', close);
  addEventListener('keydown', key);
  document.body.append(back, panel);
  build(panel.querySelector('.sheet-body'), close);
  requestAnimationFrame(() => requestAnimationFrame(() => { back.classList.add('open'); panel.classList.add('open'); }));
  const first = panel.querySelector('button, a, input');
  if (first) first.focus({ preventScroll: true });
  return close;
}

export function saveFile(name, text, type) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

const DAY = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric' });
const TIME = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit' });
const LONG = new Intl.DateTimeFormat('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
/** "Nov 14 at 6:22 AM", as the iPhone app writes it. */
export function when(iso) { const d = new Date(iso); return `${DAY.format(d)} at ${TIME.format(d)}`; }
export function longDate(iso) { return LONG.format(new Date(iso)); }
