// The stand-ins a filter may give a request: each name the table knows is a
// file Stillwater has, and each file it has is one the table names.

import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { REDIRECTS, redirectFile } from '../../tools/lib/redirects.js';
import { parseList } from '../../tools/lib/filters.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const directory = join(root, 'src', 'redirects');

test('every stand-in named is a file, and every file is named', () => {
  const files = readdirSync(directory).sort();
  assert.deepEqual([...new Set(Object.values(REDIRECTS))].sort(), files);
});

test('each stand-in is what its kind of request can take', () => {
  const read = (file) => readFileSync(join(directory, file));
  assert.equal(read('noop.txt').length, 0);
  assert.deepEqual(JSON.parse(read('noop.json')), {});
  const gif = read('1x1.gif');
  assert.equal(gif.subarray(0, 6).toString('latin1'), 'GIF89a');
  assert.deepEqual([gif.readUInt16LE(6), gif.readUInt16LE(8)], [1, 1], 'one pixel by one');
  // An MP4 of VP9 and Opus, which Chromium plays as Google Chrome does.
  const video = read('noop.mp4');
  assert.equal(video.subarray(4, 8).toString('latin1'), 'ftyp');
  assert.ok(video.includes('vp09') && video.includes('Opus'), 'VP9 video and Opus sound');
  assert.ok(video.length < 4096);
  // The scripts are scripts.
  for (const file of Object.values(REDIRECTS).filter((name) => name.endsWith('.js'))) {
    assert.doesNotThrow(() => new Function(read(file).toString('utf8')), file);
  }
});

test('the surrogates answer as the scripts they stand in for', async () => {
  const run = (file, window) => new Function('window', 'setTimeout', readFileSync(join(directory, file), 'utf8'))(window, (fn) => fn());
  // The tag manager calls a page back that waits on it, before and after it loads.
  const called = [];
  const window = { dataLayer: [{ event: 'early', eventCallback: () => called.push('early') }] };
  run('googletagmanager_gtm.js', window);
  window.dataLayer.push({ event: 'late', eventCallback: () => called.push('late') }, { event: 'plain' });
  assert.deepEqual(called, ['early', 'late']);
  assert.equal(window.dataLayer.length, 3);
  // Chartbeat is told things and does nothing.
  const quiet = {};
  run('chartbeat.js', quiet);
  assert.doesNotThrow(() => quiet.pSUPERFLY.virtualPage('/x'));
  // A fingerprint is asked for and given, the same every time.
  const printed = {};
  run('fingerprint2.js', printed);
  const answers = [];
  new printed.Fingerprint2().get((hash) => answers.push(hash));
  printed.Fingerprint2.getV18({}, (hash) => answers.push(hash));
  printed.Fingerprint2.get((components) => answers.push(components.length));
  assert.equal(answers[0], answers[1]);
  assert.equal(answers[2], 0);
  assert.equal(printed.Fingerprint2.x64hash128('anything'), answers[0]);
});

test('every stand-in the real lists ask for is one Stillwater has, but those it can not give', () => {
  const lists = ['easylist.txt', 'easyprivacy.txt', 'stillwater.txt'].map((file) => readFileSync(join(root, 'lists', file), 'utf8'));
  const dropped = new Map();
  let given = 0;
  for (const text of lists) {
    const parsed = parseList(text);
    given += parsed.network.filter((filter) => filter.redirect).length;
    for (const [reason, n] of parsed.dropped) if (reason.startsWith('option:redirect') || reason.startsWith('option:rewrite')) dropped.set(reason, (dropped.get(reason) ?? 0) + n);
  }
  assert.ok(given >= 30, `${given} filters give a stand-in`);
  // Only the exception that takes back a stand-in alone is left out.
  assert.deepEqual([...dropped], [['option:redirect-rule', 1]]);
  assert.equal(redirectFile('rewrite', 'blank-js'), null, 'a rewrite names an abp-resource');
});
