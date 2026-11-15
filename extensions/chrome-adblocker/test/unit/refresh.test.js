import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { assemble } from '../../tools/refresh-lists.js';
import { parseList } from '../../tools/lib/filters.js';

test('a list is assembled as its template sets it out, with where it came from under its first line', () => {
  const files = {
    'template_header.txt': '!\n! Licence: https://easylist.to/pages/licence.html\n',
    'easylist/general.txt': '/banner-ads/*\r\n##.ad-box\n\n',
    'easylist/servers.txt': '||ads.example^\n',
  };
  const template = ['[Adblock Plus 2.0]', '! Title: Test', '! Last modified: %timestamp%', '%include easylist:template_header.txt%', '!---- General ----!', '%include easylist:easylist/general.txt%', '  %include easylist:easylist/servers.txt%  ', ''].join('\n');
  const text = assemble((path) => files[path], template, '15 Nov 2026 20:58 UTC', ['Assembled for a test', 'at commit abc.']);
  assert.equal(
    text,
    [
      '[Adblock Plus 2.0]',
      '! Assembled for a test',
      '! at commit abc.',
      '! Title: Test',
      '! Last modified: 15 Nov 2026 20:58 UTC',
      '! *** easylist:template_header.txt ***',
      '!',
      '! Licence: https://easylist.to/pages/licence.html',
      '!---- General ----!',
      '! *** easylist:easylist/general.txt ***',
      '/banner-ads/*',
      '##.ad-box',
      '! *** easylist:easylist/servers.txt ***',
      '||ads.example^',
      '',
    ].join('\n'),
  );
  const list = parseList(text);
  assert.deepEqual([list.network.length, list.cosmetic.length], [2, 1]);
});

test('the lists kept in lists/ say where they came from, keep their licence line, and match sources.json', () => {
  const sources = JSON.parse(readFileSync(new URL('../../lists/sources.json', import.meta.url), 'utf8'));
  assert.match(sources.commit, /^[0-9a-f]{40}$/);
  assert.match(sources.licence, /GPL-3\.0-or-later OR CC-BY-SA-3\.0/);
  for (const list of sources.lists) {
    const head = readFileSync(new URL(`../../lists/${list.file}`, import.meta.url), 'utf8').split('\n').slice(0, 14).join('\n');
    assert.ok(head.includes(`at commit ${sources.commit}`), `${list.file} names its commit`);
    assert.ok(head.includes(`! Title: ${list.title}`), `${list.file} is ${list.title}`);
    assert.ok(head.includes('! Licence: https://easylist.to/pages/licence.html'), `${list.file} keeps its licence line`);
  }
});
