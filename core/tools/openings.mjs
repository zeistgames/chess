// Builds core/vendor/chess-openings/openings.js from the Lichess chess-openings TSV files (CC0-1.0).
//   node core/tools/openings.mjs <folder with a.tsv ... e.tsv>
// Each opening's moves are played with the rules and the position after its last move becomes the key
// (the first four fields of its FEN), so a game is named by where it stands, whatever the move order.
import fs from 'node:fs';
import path from 'node:path';
import { Game } from '../rules.js';

const dir = process.argv[2];
if (!dir) { console.error('usage: node core/tools/openings.mjs <folder with a.tsv ... e.tsv>'); process.exit(2); }
const out = {};
let n = 0;
for (const f of ['a', 'b', 'c', 'd', 'e']) {
  const lines = fs.readFileSync(path.join(dir, f + '.tsv'), 'utf8').split('\n').slice(1).filter(Boolean);
  for (const line of lines) {
    const [eco, name, pgn] = line.split('\t');
    const g = new Game();
    for (const san of pgn.replace(/\d+\.(\.\.)?/g, ' ').split(/\s+/).filter(Boolean)) {
      if (!g.playSan(san)) throw new Error(`${eco} ${name}: ${san} is not legal`);
    }
    const key = g.key();
    // The first name for a position is kept: the files list the main name before its variations' transpositions.
    if (!(key in out)) { out[key] = `${eco}|${name}`; n++; }
  }
}
const body = '// Opening names by position, from github.com/lichess-org/chess-openings (CC0-1.0). Built by core/tools/openings.mjs.\n' +
  'export default ' + JSON.stringify(out) + ';\n';
fs.writeFileSync(new URL('../vendor/chess-openings/openings.js', import.meta.url), body);
console.log(n, 'positions');
