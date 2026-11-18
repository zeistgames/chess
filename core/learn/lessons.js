// Which lesson a Learn-as-you-play card opens. The table is data (lessons.json); openings follow the index itself,
// so an opening chapter added to core/lessons/index.json is picked up with no change here.

/**
 * The lesson a card opens, or null when there is none (then the card is not shown).
 * card: from cards.js; index: core/lessons/index.json; table: lessons.json's "lessons".
 * Returns { lesson: id } or { course: 'openings', chapter: id }.
 */
export function lessonFor(card, index, table) {
  const courses = index?.courses ?? [];
  if (card.kind === 'opening') {
    const chapter = openingChapter(card.name, courses.find(c => c.id === 'openings'));
    return chapter ? { course: 'openings', chapter: chapter.id } : null;
  }
  const id = table?.[card.kind];
  if (!id) return null;
  const listed = courses.some(c => c.chapters.some(ch => ch.lessons.some(l => l.id === id)));
  return listed ? { lesson: id } : null;
}

/**
 * The opening chapter for a name from the opening table. A chapter matches when its title is the whole name, its
 * beginning ("Queen's Gambit" in "Queen's Gambit Declined: ..."), one of its ": " parts ("London System" in "Indian
 * Defense: London System"), or the start of a part before a comma ("London System, with Bd3"). The longest title
 * wins, and on a tie the one matched further into the name (the more specific).
 */
export function openingChapter(name, openings) {
  if (!name || !openings) return null;
  const parts = name.split(': ');
  let best = null, bestAt = -1;
  for (const ch of openings.chapters) {
    const t = ch.title;
    let at = -1;
    if (name === t || name.startsWith(t + ':') || name.startsWith(t + ' ')) at = 0;
    parts.forEach((p, i) => { if (p === t || p.startsWith(t + ',')) at = Math.max(at, i); });
    if (at < 0) continue;
    if (!best || t.length > best.title.length || (t.length === best.title.length && at > bestAt)) { best = ch; bestAt = at; }
  }
  return best;
}
