import assert from 'node:assert/strict';
import { test } from 'node:test';
import { grouped, hostOf, isAllowed, RULE, siteFromInput, siteOf, userRules, USER_PRIORITY, withSite } from '../../src/shared/sites.js';
import { PRIORITY, problemsWith } from '../../tools/lib/dnr.js';

test('the host of a page that can be filtered', () => {
  assert.equal(hostOf('https://News.Example.com/a?b#c'), 'news.example.com');
  assert.equal(hostOf('http://localhost:8080/'), 'localhost');
  for (const url of ['chrome://extensions', 'chrome-extension://abc/popup.html', 'about:blank', 'file:///tmp/a.html', '', undefined, 'not a url']) {
    assert.equal(hostOf(url), '', String(url));
  }
});

test('a site is a host without its www', () => {
  assert.equal(siteOf('WWW.Example.com'), 'example.com');
  assert.equal(siteOf('news.example.com.'), 'news.example.com');
  assert.equal(siteOf('wwwx.example.com'), 'wwwx.example.com');
});

test('what is typed as a site: a host or a whole address', () => {
  assert.equal(siteFromInput(' Example.com '), 'example.com');
  assert.equal(siteFromInput('https://www.example.com/path?q=1'), 'example.com');
  assert.equal(siteFromInput('bücher.example'), 'xn--bcher-kva.example');
  assert.equal(siteFromInput('localhost:3000'), 'localhost');
  for (const bad of ['', '   ', 'two words', 'http://', 'exa$mple.com', '-.com']) assert.equal(siteFromInput(bad), '', bad);
});

test('a site let through takes its subdomains with it, and nothing else', () => {
  const list = ['example.com', 'news.test'];
  assert.equal(isAllowed(list, 'example.com'), true);
  assert.equal(isAllowed(list, 'www.example.com'), true);
  assert.equal(isAllowed(list, 'shop.example.com'), true);
  assert.equal(isAllowed(list, 'notexample.com'), false);
  assert.equal(isAllowed(list, 'example.com.evil.test'), false);
  assert.equal(isAllowed([], 'example.com'), false);
  assert.equal(isAllowed(list, ''), false);
});

test('adding and removing a site keeps the list in order, each once', () => {
  assert.deepEqual(withSite(['b.test'], 'a.test', true), ['a.test', 'b.test']);
  assert.deepEqual(withSite(['a.test', 'b.test'], 'a.test', true), ['a.test', 'b.test']);
  assert.deepEqual(withSite(['a.test', 'b.test'], 'a.test', false), ['b.test']);
  assert.deepEqual(withSite(undefined, 'a.test', false), []);
});

test('the user\'s rules outrank every rule a list can make, and are rules Chrome takes', () => {
  assert.ok(USER_PRIORITY === PRIORITY.user && USER_PRIORITY > PRIORITY.important);
  assert.deepEqual(userRules({ allowlist: [], paused: false }), []);
  const rules = userRules({ allowlist: ['example.com', 'news.test'], paused: true });
  assert.deepEqual(rules.map((rule) => rule.id), [RULE.allowlist, RULE.paused]);
  assert.deepEqual(rules[0], { id: 1, priority: 1000, action: { type: 'allowAllRequests' }, condition: { requestDomains: ['example.com', 'news.test'], resourceTypes: ['main_frame'] } });
  assert.deepEqual(problemsWith(rules[0]), []);
  // The pause is meant to match every page: the one thing problemsWith would call too broad.
  assert.deepEqual(problemsWith(rules[1]), ['matches every request']);
  assert.deepEqual(rules[1].condition, { resourceTypes: ['main_frame', 'sub_frame'] });
});

test('counts are grouped in threes', () => {
  assert.deepEqual([0, 7, 999, 1000, 12345, 1234567].map(grouped), ['0', '7', '999', '1,000', '12,345', '1,234,567']);
  assert.equal(grouped('42'), '42');
  assert.equal(grouped(undefined), '0');
});
