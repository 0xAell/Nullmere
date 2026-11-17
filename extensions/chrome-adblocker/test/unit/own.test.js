// One's own filters, read as the build reads a list: the rules Chrome is
// given, what pages hide, and each line not taken with why.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { OWN_READER } from '../../tools/build.js';
import { problemsWith, toRules } from '../../tools/lib/dnr.js';
import { parseLine } from '../../tools/lib/filters.js';
import { OWN_FIRST_ID, OWN_MOST_RULES, readOwn, whyNot } from '../../tools/lib/own.js';
import { RULE } from '../../src/shared/sites.js';
import { ownWords } from '../../src/shared/words.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

test('a filter of one\'s own becomes the rule the same line in a list would', () => {
  const own = readOwn(['! a comment', '', '||ownads.test^', '@@||adnxs.com^$domain=ownpage.test', '/banner-own/*$image,third-party'].join('\n'));
  const listed = toRules(['||ownads.test^', '@@||adnxs.com^$domain=ownpage.test', '/banner-own/*$image,third-party'].map(parseLine), { firstId: OWN_FIRST_ID });
  assert.deepEqual(own.rules, listed.rules);
  assert.equal(own.taken, 3);
  assert.deepEqual(own.refused, []);
  assert.ok(own.rules.every((rule) => rule.id >= OWN_FIRST_ID && !problemsWith(rule).length));
  assert.ok(Math.max(...Object.values(RULE)) < OWN_FIRST_ID, 'clear of the worker\'s own rules');
});

test('what one\'s own filters hide, and the exceptions they make, are a list\'s cosmetic data', () => {
  const own = readOwn(['ownpage.test##.promo', '##.own-generic-slot', '###own-banner', 'ownpage.test#@#.kept', 'ownpage.test##.card:has-text(Sponsored)', 'ownpage.test##.page:style(padding-top: 0 !important)', '@@||ownpage.test^$generichide'].join('\n'));
  assert.deepEqual(own.cosmetic.specific, { 'ownpage.test': ['.promo'] });
  assert.deepEqual(own.cosmetic.exceptions, { 'ownpage.test': ['.kept'] });
  assert.equal(own.cosmetic.procedural['ownpage.test'].length, 1);
  assert.deepEqual(own.cosmetic.styles['ownpage.test'], ['.page{padding-top:0 !important}']);
  assert.deepEqual(own.cosmetic.noGeneric, ['ownpage.test']);
  assert.deepEqual([...own.selectors].sort(), ['#own-banner', '.own-generic-slot', '.promo'], 'every selector it hides, to be written apart from the lists\'');
  assert.equal(own.taken, 7);
});

test('each line not taken is named by its number, with why', () => {
  const lines = ['||fine.test^', 'ownpage.test##+js(set, a, false)', '||pop.test^$popup', '/a(?=b)/', '*$image', '##.x {color: red}', 'example.com##div:matches-css(width: 1px)', '||x.test^$replace=/a/b/', 'not a filter $$$'];
  const own = readOwn(lines.join('\n'));
  assert.equal(own.taken, 1);
  assert.deepEqual(own.refused.map((note) => note.line), [2, 3, 4, 5, 6, 7, 8, 9]);
  assert.deepEqual(own.refused.map((note) => note.text), lines.slice(1));
  assert.match(own.refused[0].why, /scriptlet of your own/);
  assert.match(own.refused[1].why, /Pop-up filters of your own/);
  assert.match(own.refused[2].why, /regular expression/);
  assert.match(own.refused[3].why, /far too much/);
  assert.match(own.refused[4].why, /restyles must name its sites/);
  assert.match(own.refused[5].why, /way of picking an element/);
  assert.match(own.refused[6].why, /option replace/);
  assert.match(own.refused[7].why, /can't be read as a filter/);
  // One Chrome says it can't use, asked by the worker, is refused by its line too.
  const regex = readOwn('||fine.test^\n/^https?:\\/\\/own\\.test\\/[a-z]{2,}/', { rejectedRegex: ['^https?:\\/\\/own\\.test\\/[a-z]{2,}'] });
  assert.deepEqual(regex.refused.map((note) => [note.line, note.why]), [[2, whyNot('regex:rejected-by-chrome')]]);
  assert.equal(regex.rules.length, 1);
});

test('no more rules than the worker can give Chrome', () => {
  const many = Array.from({ length: OWN_MOST_RULES + 10 }, (_, index) => `/own-path-${index}/*$script`).join('\n');
  const own = readOwn(many);
  assert.equal(own.rules.length, OWN_MOST_RULES);
  assert.deepEqual(own.refused.map((note) => note.why), [whyNot('own:too-many')]);
});

test('what became of one\'s own filters is said in a line', () => {
  assert.equal(ownWords(undefined), 'None yet.');
  assert.equal(ownWords({ taken: 0, rules: 0, hidden: 0, refused: [] }), 'None yet.');
  assert.equal(ownWords({ taken: 1, rules: 1, hidden: 0, refused: [] }), '1 filter in use: 1 rule for Chrome, 0 selectors to hide.');
  assert.equal(ownWords({ taken: 4, rules: 2, hidden: 2, refused: [{}, {}, {}] }), '4 filters in use: 2 rules for Chrome, 2 selectors to hide. 3 lines do nothing; why is below.');
  assert.equal(ownWords({ taken: 0, rules: 0, hidden: 0, refused: [{}] }), 'No filter in use. 1 line does nothing; why is below.');
});

test('the modules the worker reads one\'s own filters with import only one another', () => {
  for (const file of OWN_READER) {
    const source = readFileSync(join(root, 'tools', 'lib', file), 'utf8');
    for (const [, from] of source.matchAll(/^import [^;]* from '([^']+)';$/gm)) {
      assert.ok(from.startsWith('./') && OWN_READER.includes(from.slice(2)), `${file} imports ${from}`);
    }
  }
});
