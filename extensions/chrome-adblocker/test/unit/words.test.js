import assert from 'node:assert/strict';
import { test } from 'node:test';
import { limitWords, listDetail, sourceWords, SWITCHES, wording } from '../../src/shared/words.js';
import { DEFAULTS } from '../../src/shared/settings.js';

const still = { host: 'www.news.example', site: 'news.example', filterable: true, allowed: false, paused: false, count: 1204 };

test('the popup\'s words for a page being filtered', () => {
  const words = wording(still);
  assert.deepEqual([words.name, words.count, words.label, words.site, words.act], ['still', '1,204', 'Requests kept from this page', 'news.example', 'Let this site through']);
  assert.equal(wording({ ...still, count: 1 }).label, 'Request kept from this page');
  assert.equal(wording({ ...still, count: 0 }).count, '0');
  assert.match(words.moon, /filtering news\.example.*let this site through/i);
});

test('the popup\'s words where nothing is kept: let through, paused, not a page to filter', () => {
  const allowed = wording({ ...still, allowed: true, count: 0 });
  assert.deepEqual([allowed.name, allowed.count, allowed.label, allowed.act], ['allowed', '', 'Let through', 'Still this site again']);
  const paused = wording({ ...still, paused: true, allowed: true });
  assert.deepEqual([paused.name, paused.label, paused.act], ['paused', 'Paused', 'Resume'], 'the pause is said first: resuming is what to do about it');
  const none = wording({ host: '', site: '', filterable: false, allowed: false, paused: true, count: 0 });
  assert.deepEqual([none.name, none.site, none.act], ['none', '', ''], 'nothing to press on a page that can\'t be filtered');
});

const lists = {
  source: { commit: '4f2a9139d44ec4e71d82ca48f86fc2a717ba603f', committed: '2026-11-15T20:58:48.000Z' },
  limits: { guaranteedRules: 30000, regexRules: 1000 },
  lists: [
    { id: 'easylist', title: 'EasyList', filters: 78487, rules: 3771, cosmetic: 30468, dropped: { 'option:popup': 2969, 'cosmetic:procedural': 294, 'cosmetic:style': 40, 'option:rewrite': 7, 'hide-exception:pattern': 13 } },
    { id: 'easyprivacy', title: 'EasyPrivacy', filters: 56658, rules: 9201, cosmetic: 0, dropped: { 'cosmetic:scriptlet': 31, 'option:redirect': 29, 'option:redirect-rule': 1, 'option:rewrite': 1 } },
    { id: 'stillwater', title: 'Stillwater supplement', filters: 0, rules: 0, cosmetic: 0, dropped: {} },
  ],
};

test('a list in a line', () => {
  assert.equal(listDetail(lists.lists[0]), '78,487 filters · 3,771 rules for Chrome · 30,468 selectors to hide');
  assert.equal(listDetail(lists.lists[1]), '56,658 filters · 9,201 rules for Chrome');
  assert.equal(listDetail(lists.lists[2]), 'Nothing in it yet.');
});

test('where the lists came from, and the rules in use of those enabled', () => {
  assert.equal(
    sourceWords(lists, ['easylist', 'easyprivacy', 'stillwater']),
    'The lists as they stood on 15 November 2026 (commit 4f2a9139 of the EasyList authors\' repository). 12,972 of the 30,000 rules Chrome guarantees an extension are in use.',
  );
  assert.match(sourceWords(lists, ['easylist']), /3,771 of the 30,000/);
});

test('what it cannot do is said with the build\'s own numbers', () => {
  const words = limitWords(lists);
  assert.equal(words.length, 5);
  const numbers = words[1][1];
  assert.match(numbers, /2,969 that close pop-up windows/);
  assert.match(numbers, /38 that redirect or rewrite/, '7 + 29 + 1 + 1');
  assert.match(numbers, /365 that need a script/, '294 + 40 + 31');
  for (const [lead, rest] of words) assert.ok(lead.length > 10 && rest.length > 20);
});

test('every switch keeps a setting that exists', () => {
  for (const { key, title, detail } of SWITCHES) {
    assert.equal(typeof DEFAULTS[key], 'boolean', key);
    assert.ok(title && detail);
  }
  assert.deepEqual(SWITCHES.map((item) => item.key), ['cosmetic', 'youtube', 'badge', 'paused']);
});
