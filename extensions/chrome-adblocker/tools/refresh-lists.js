#!/usr/bin/env node
// Brings lists/ up to date with EasyList and EasyPrivacy.
//
// The lists are assembled from the EasyList authors' own repository,
// https://github.com/easylist/easylist, the way its templates set them
// out (the same sections, in the same order, as the lists published at
// easylist.to), at one commit that lists/sources.json then names. So the
// rules this extension ships can always be traced to an exact state of
// the upstream lists, and built again from it.
//
//   node tools/refresh-lists.js                  clone the repository's latest
//   node tools/refresh-lists.js --from <path>    use a checkout already here
//
// After a refresh: `npm run build`, then `npm run check` (which asks a
// real Chromium whether it takes every regular expression and selector),
// and commit lists/.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPOSITORY = 'https://github.com/easylist/easylist';
const LISTS = [
  { id: 'easylist', title: 'EasyList', template: 'easylist.template', file: 'easylist.txt', homepage: 'https://easylist.to/' },
  { id: 'easyprivacy', title: 'EasyPrivacy', template: 'easyprivacy.template', file: 'easyprivacy.txt', homepage: 'https://easylist.to/' },
];

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const git = (cwd, ...args) => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();

/** A list as its template sets it out, each `%include%` replaced by the file it names. */
export function assemble(read, template, stamp, provenance) {
  const out = [];
  for (const line of template.split(/\r?\n/)) {
    const include = /^%include easylist:(.+)%$/.exec(line.trim());
    if (include) {
      out.push(`! *** easylist:${include[1]} ***`);
      out.push(read(include[1]).replace(/\r\n/g, '\n').trimEnd());
    } else {
      out.push(line.replace('%timestamp%', stamp));
    }
    // The provenance goes straight under the list's own first line.
    if (out.length === 1) out.push(...provenance.map((words) => `! ${words}`));
  }
  return `${out.join('\n').trimEnd()}\n`;
}

function main() {
  const from = process.argv.indexOf('--from');
  let checkout = from === -1 ? null : resolve(process.argv[from + 1]);
  let temporary = null;
  if (!checkout) {
    temporary = mkdtempSync(join(tmpdir(), 'easylist-'));
    console.log(`Cloning ${REPOSITORY} ...`);
    execFileSync('git', ['clone', '--quiet', '--depth', '1', REPOSITORY, temporary], { stdio: 'inherit' });
    checkout = temporary;
  }
  try {
    const commit = git(checkout, 'rev-parse', 'HEAD');
    const committed = new Date(git(checkout, 'log', '-1', '--format=%cI')).toISOString();
    const stamp = new Date(committed).toUTCString().replace(/^\w+, /, '').replace(/:\d\d GMT$/, ' UTC');
    const read = (path) => readFileSync(join(checkout, path), 'utf8');
    for (const list of LISTS) {
      const provenance = [
        `Assembled by Nullmere Stillwater (tools/refresh-lists.js) from ${REPOSITORY}`,
        `at commit ${commit}, as ${list.template} sets the list out. Unmodified otherwise.`,
      ];
      const text = assemble(read, read(list.template), stamp, provenance);
      writeFileSync(join(root, 'lists', list.file), text);
      console.log(`${list.title}: ${text.split('\n').length - 1} lines`);
    }
    const sources = {
      repository: REPOSITORY,
      commit,
      committed,
      licence: 'GPL-3.0-or-later OR CC-BY-SA-3.0 (or later); see https://easylist.to/pages/licence.html',
      lists: LISTS.map(({ id, title, file, homepage }) => ({ id, title, file, homepage })),
    };
    writeFileSync(join(root, 'lists', 'sources.json'), `${JSON.stringify(sources, null, 2)}\n`);
    console.log(`lists/sources.json: commit ${commit.slice(0, 12)}, ${committed}`);
  } finally {
    if (temporary) rmSync(temporary, { recursive: true, force: true });
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
