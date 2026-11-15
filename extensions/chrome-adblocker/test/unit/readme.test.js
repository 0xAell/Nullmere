// The README states numbers. This holds them to what the lists build to,
// so a refresh of the lists can't leave it saying something untrue.

import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { blocksHosts, build } from '../../tools/build.js';

const root = new URL('../../', import.meta.url).pathname;
const grouped = (number) => number.toLocaleString('en-US');

test('the README\'s numbers are the build\'s', (t) => {
  const out = mkdtempSync(join(tmpdir(), 'stillwater-readme-'));
  t.after(() => rmSync(out, { recursive: true, force: true }));
  const { lists, totals, source } = build({ out, quiet: true });
  const readme = readFileSync(join(root, 'README.md'), 'utf8');
  const says = (words) => assert.ok(readme.includes(words), `README.md should say: ${words}`);

  const rules = lists.flatMap((list) => JSON.parse(readFileSync(join(out, 'rules', `${list.id}.json`), 'utf8')));
  const hostRules = rules.filter(blocksHosts);
  const hosts = lists.reduce((sum, list) => sum + list.hosts, 0);
  says(`${grouped(totals.filters)} filters from EasyList`);
  says(`become ${grouped(totals.rules)} rules`);
  says(`${grouped(hosts)} hosts are blocked by ${grouped(hostRules.length)} of those rules`);
  says(`| ${grouped(totals.cosmetic)} selectors.`);

  const left = (...prefixes) => lists.reduce((sum, list) => sum + Object.entries(list.dropped).reduce((n, [reason, count]) => n + (prefixes.some((prefix) => reason.startsWith(prefix)) ? count : 0), 0), 0);
  const cosmetic = lists.map((list) => JSON.parse(readFileSync(join(out, 'cosmetic', `${list.id}.json`), 'utf8')));
  const generic = cosmetic.reduce((sum, data) => sum + data.generic.always.length + data.generic.simple.length + Object.values(data.generic.keyed).reduce((n, list) => n + list.length, 0), 0);
  const worded = new Set(cosmetic.flatMap((data) => Object.values(data.procedural).flatMap((plans) => plans.map((plan) => plan.raw))));
  says(`The ${grouped(generic)} generic ones`);
  says(`| ${grouped(worded.size)} filters pick an element`);
  says(`| ${grouped(totals.popups)} filters name the addresses of pop-up ads.`);
  assert.equal(left('option:popup', 'popup:'), 0, 'no pop-up filter is left out, so the README has no row for them');

  // What was left out, by the README's own rows.
  const rows = [
    ['Redirects and rewrites (`$redirect`, `$rewrite`)', left('option:redirect', 'option:rewrite')],
    ['Scriptlets and procedural filters beyond `:has-text`', left('cosmetic:scriptlet', 'cosmetic:procedural', 'cosmetic:snippet')],
    ['Regular expressions Chrome refuses', left('regex:')],
    ['Hiding exceptions for part of a site', left('hide-exception:')],
  ];
  for (const [name, count] of rows) says(`| ${name} | ${grouped(count)} |`);
  const all = lists.reduce((sum, list) => sum + Object.values(list.dropped).reduce((n, count) => n + count, 0), 0);
  const others = all - rows.reduce((sum, [, count]) => sum + count, 0);
  says(`| Others | ${grouped(others)} |`);
  says(`That is ${grouped(all)} of ${grouped(totals.filters)} filters, ${((all / totals.filters) * 100).toFixed(1)}%.`);

  const day = new Date(source.committed).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
  says(`as they stood on ${day}`);
  says(`[\`${source.commit.slice(0, 8)}\`](https://github.com/easylist/easylist/commit/${source.commit})`);

  const { version } = JSON.parse(readFileSync(join(root, 'src', 'manifest.json'), 'utf8'));
  says(`dist/nullmere-stillwater-${version}.zip`);
  assert.equal(JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version, version, 'package.json and the manifest name one version');
});
