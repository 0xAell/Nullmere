// Scriptlet filters read, and the files they become: their arguments as
// the lists write them, the names the lists use, the sites they are for,
// and what a file does when it runs.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseLine, parseList } from '../../tools/lib/filters.js';
import { NAMES, SCRIPTLETS, patternsFor, readArguments, readScriptlet, scriptletSource } from '../../tools/lib/scriptlets.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

test('arguments are read as the lists write them', () => {
  assert.deepEqual(readArguments('set, navigator.globalPrivacyControl, false'), ['set', 'navigator.globalPrivacyControl', 'false']);
  assert.deepEqual(readArguments(`rmnt, script, '"data-adm-url"'`), ['rmnt', 'script', '"data-adm-url"'], 'quotes taken off, what is in them kept');
  assert.deepEqual(readArguments('set-cookie, GPC, 1, , reload, 1'), ['set-cookie', 'GPC', '1', '', 'reload', '1'], 'an empty one kept in its place');
  assert.deepEqual(readArguments('acs, a, b\\, c'), ['acs', 'a', 'b, c'], 'an escaped comma is a comma');
  assert.deepEqual(readArguments(`set, x, "a, b"`), ['set', 'x', 'a, b']);
  assert.deepEqual(readArguments(`aost, decodeURI, /(?=^(?!.*\\.js))/`), ['aost', 'decodeURI', '/(?=^(?!.*\\.js))/']);
});

test('each scriptlet the lists use is known by its names, and what Stillwater has not written is not', () => {
  for (const name of ['set', 'acs', 'aost', 'rmnt', 'set-local-storage-item', 'set-cookie', 'cookie-remover', 'no-fetch-if', 'no-xhr-if', 'aeld']) {
    assert.ok(SCRIPTLETS[NAMES[name]], name);
  }
  assert.equal(readScriptlet('+js(acs, document.createElement, admiral)').method, 'abortCurrentScript');
  assert.equal(readScriptlet('+js(abort-current-script.js, x)').method, 'abortCurrentScript', 'a name written with .js');
  assert.deepEqual(readScriptlet('+js(json-edit, ..props)'), { unknown: 'json-edit' });
  // `set` gives only plain values: anything else might be code.
  assert.equal(readScriptlet('+js(set, ncbi.sg, {})').method, 'setConstant');
  assert.equal(readScriptlet("+js(set, gnt.x.adm, '')").method, 'setConstant');
  assert.ok(readScriptlet('+js(set, x, alert(1))').unknown);
  assert.ok(readScriptlet('+js(set, x)').unknown);
});

test('a scriptlet filter is for the hosts it names, and only those', () => {
  const filter = parseLine('cnn.com,~edition.cnn.com,news.example##+js(set, admiral, noopFunc)');
  assert.deepEqual([filter.kind, filter.method, filter.args], ['scriptlet', 'setConstant', ['admiral', 'noopFunc']]);
  assert.deepEqual([filter.include, filter.exclude], [['cnn.com', 'news.example'], ['edition.cnn.com']]);
  assert.deepEqual(patternsFor(filter.include), ['*://*.cnn.com/*', '*://*.news.example/*']);
  // An entity is left out of the hosts; with nothing else named the filter goes.
  assert.deepEqual(parseLine('ticketmaster.*,x.com##+js(set, a, false)').include, ['x.com']);
  for (const [line, reason] of [
    ['ticketmaster.*##+js(set, a, false)', 'cosmetic:scriptlet-entity'],
    ['##+js(set, a, false)', 'cosmetic:scriptlet-generic'],
    ['site.example#@#+js(set, a, false)', 'cosmetic:scriptlet-exception'],
    ['site.example##+js(json-edit, ..props)', 'cosmetic:scriptlet'],
    ['site.example##^script:has-text(NREUM)', 'cosmetic:scriptlet'],
  ]) {
    assert.equal(parseLine(line).reason, reason, line);
  }
});

test('a scriptlet\'s file runs it with its arguments and adds nothing to the page', () => {
  const source = scriptletSource({ method: 'setConstant', args: ['wall.config.enabled', 'false'], raw: 'site.example##+js(set, wall.config.enabled, false)' });
  assert.ok(source.startsWith('// Nullmere Stillwater: site.example##+js(set, wall.config.enabled, false)\n'));
  const window = {};
  new Function('window', source)(window);
  assert.deepEqual(Object.getOwnPropertyNames(window), ['wall'], 'only the property it waits on');
  // Made later, and set again: the value holds.
  window.wall = { config: { enabled: true } };
  assert.equal(window.wall.config.enabled, false);
  window.wall.config.enabled = true;
  assert.equal(window.wall.config.enabled, false);

  // Each scriptlet's file is a script, for every scriptlet there is.
  for (const method of Object.keys(SCRIPTLETS)) {
    assert.doesNotThrow(() => new Function(scriptletSource({ method, args: ['a', 'b'], raw: 'x' })), method);
  }
});

test('every scriptlet filter of the real lists is built but two Stillwater has not written', () => {
  const lists = ['easylist.txt', 'easyprivacy.txt', 'stillwater.txt'].map((file) => parseList(readFileSync(join(root, 'lists', file), 'utf8')));
  const built = lists.reduce((sum, list) => sum + list.scriptlets.length, 0);
  const left = lists.reduce((sum, list) => sum + [...list.dropped].filter(([reason]) => reason.startsWith('cosmetic:scriptlet')).reduce((n, [, count]) => n + count, 0), 0);
  assert.equal(built, 29);
  assert.equal(left, 2, 'json-edit, and the HTML filtering of ##^');
  // Admiral's walls, on the sites that name it.
  assert.ok(lists[1].scriptlets.filter((filter) => filter.args.some((arg) => arg.includes('admiral'))).length >= 4);
});
