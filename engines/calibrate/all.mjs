#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Runs the calibration for every engine, a few at a time, at low priority.
//
//   node engines/calibrate/all.mjs [--data DIR] [--jobs 6] [--nice 15] [<engine> ...]
//
// Each engine is one `run.mjs` process (levels 1 to 10 in order, resuming from its JSONL), started under
// `nice`, with its log in DIR/logs/<engine>.log. At most --jobs run at once; engines start in the order
// below, lightest packs first. After each engine ends, fit.mjs is run to refresh the results. The process
// id of this launcher is written to DIR/all.pid. Stopping it (or any run.mjs) loses at most the games in
// progress; starting it again resumes.

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_DATA } from './run.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
// Lightest packs first; the two largest last.
const ORDER = ['zeist', 'ethereal', 'fairy-stockfish', 'stockfish-lite', 'koivisto', 'clover', 'halogen', 'arasan', 'plentychess', 'caissa', 'stockfish'];

const args = process.argv.slice(2);
const flag = (name, d) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : d; };
const data = path.resolve(flag('--data', DEFAULT_DATA));
const jobs = Math.max(1, Math.min(6, +flag('--jobs', 6)));
const niceness = String(flag('--nice', 15));
const named = args.filter((a, k) => !a.startsWith('--') && !(k > 0 && args[k - 1].startsWith('--')));
const queue = named.length ? named : ORDER.slice();
const logs = path.join(data, 'logs');
fs.mkdirSync(logs, { recursive: true });
fs.writeFileSync(path.join(data, 'all.pid'), String(process.pid) + '\n');
const stamp = () => new Date().toISOString().slice(0, 19);
const say = m => console.log(`${stamp()} ${m}`);

function node(script, extra, logFile) {
  const out = fs.openSync(logFile, 'a');
  const child = spawn('nice', ['-n', niceness, process.execPath, '--disable-warning=ExperimentalWarning', path.join(here, script), ...extra], { stdio: ['ignore', out, out] });
  return new Promise(resolve => child.on('exit', code => { fs.closeSync(out); resolve(code); }));
}

const running = new Set();
const children = [];
process.on('SIGTERM', () => process.exit(143));

say(`calibration: ${queue.join(', ')}; ${jobs} at a time, nice ${niceness}, data ${data}`);
async function worker() {
  while (queue.length) {
    const id = queue.shift();
    running.add(id);
    say(`start ${id}`);
    const code = await node('run.mjs', [id, '--data', data], path.join(logs, id + '.log'));
    running.delete(id);
    say(`end ${id} (exit ${code}); still running: ${[...running].join(', ') || 'none'}`);
    await node('fit.mjs', ['--data', data], path.join(logs, 'fit.log'));
  }
}
for (let i = 0; i < jobs; i++) children.push(worker());
await Promise.all(children);
say('calibration: all engines ended');
