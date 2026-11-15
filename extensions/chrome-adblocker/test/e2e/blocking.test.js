// The built extension, with the real EasyList and EasyPrivacy, in a real
// Chromium: requests to ad hosts and trackers never leave the browser, a
// site's own requests do, and a site let through gets everything.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { refusedBy } from '../../tools/validate.js';
import { launch, open, root, startServer, tabIdOf, until } from './harness.js';

let server;
let browser;

before(async () => {
  server = await startServer();
  browser = await launch();
});

after(async () => {
  await browser?.close();
  await server?.close();
});

/** Hosts the built rules block for every site: a sample from the lists themselves, so a refresh can't quietly empty the test. */
function blockedHosts(list, howMany) {
  const rules = JSON.parse(readFileSync(join(root, 'build', 'rules', `${list}.json`), 'utf8'));
  const whole = rules.find((rule) => rule.action.type === 'block' && rule.condition.requestDomains?.length > 1000 && !rule.condition.initiatorDomains && !rule.condition.resourceTypes);
  assert.ok(whole, `${list} has a rule blocking many hosts outright`);
  const hosts = whole.condition.requestDomains;
  const step = Math.floor(hosts.length / howMany);
  return Array.from({ length: howMany }, (_, index) => hosts[index * step]);
}

test('the extension loads with its three rulesets enabled, and Chrome takes every rule the build made', async () => {
  const state = await browser.worker.evaluate(async () => {
    const dnr = chrome.declarativeNetRequest;
    const enabled = await dnr.getEnabledRulesets();
    const withAll = await dnr.getAvailableStaticRuleCount();
    await dnr.updateEnabledRulesets({ disableRulesetIds: enabled });
    const withNone = await dnr.getAvailableStaticRuleCount();
    await dnr.updateEnabledRulesets({ enableRulesetIds: enabled });
    return { enabled, taken: withNone - withAll, guaranteed: dnr.GUARANTEED_MINIMUM_STATIC_RULES, dynamic: await dnr.getDynamicRules() };
  });
  assert.deepEqual(state.enabled.sort(), ['easylist', 'easyprivacy', 'stillwater']);
  const lists = JSON.parse(readFileSync(join(root, 'build', 'lists.json'), 'utf8'));
  assert.ok(lists.totals.rules > 5000, 'the real lists were built');
  assert.equal(state.taken, lists.totals.rules, 'Chrome counted every rule: it refused none');
  assert.ok(lists.totals.rules < state.guaranteed, `inside the ${state.guaranteed} rules Chrome guarantees an extension`);
  assert.equal(lists.limits.guaranteedRules, state.guaranteed);
  assert.deepEqual(state.dynamic, [], 'nothing let through yet');
});

test('lists/rejected.json names exactly what this Chromium refuses', async () => {
  // Built with rejected.json left out, so anything refused now is new.
  const refused = await refusedBy(browser);
  assert.deepEqual({ regex: refused.regex, selectors: refused.selectors }, { regex: [], selectors: [] }, 'run: npm run build && node tools/validate.js && npm run build');
  assert.ok(refused.asked.selectors > 10000 && refused.asked.regex > 0);
});

test('ad hosts and trackers are blocked; the site\'s own requests go through', async () => {
  const ads = [...blockedHosts('easylist', 6), 'ad.doubleclick.net', 'pagead2.googlesyndication.com', 'adnxs.com'];
  const trackers = [...blockedHosts('easyprivacy', 6), 'scorecardresearch.com'];
  const tags = [...ads, ...trackers].map((host, index) => (index % 2 ? `<script src="${server.url(host, '/tag.js')}"></script>` : `<img src="${server.url(host, '/pixel.gif')}">`));
  server.page('news.test', '/', `<!doctype html><title>News</title><body><h1>News</h1>
    <script src="/site.js"></script><img src="/photo.png"><script src="${server.url('cdn.news.test', '/lib.js')}"></script>
    ${tags.join('\n')}</body>`);
  server.forget();

  const { page, blocked } = await open(browser.context, server.url('news.test'));
  const stopped = blocked().map((url) => new URL(url).hostname).sort();
  assert.deepEqual(stopped, [...ads, ...trackers].sort(), 'each was stopped by the extension, and nothing else was');
  for (const host of [...ads, ...trackers]) assert.equal(server.reached(host), false, `${host} was never asked`);
  assert.deepEqual(await page.evaluate(() => window.ran), ['news.test/site.js', 'cdn.news.test/lib.js'], 'the site\'s own scripts ran');
  assert.ok(server.reached('news.test', '/photo.png'));

  // The count on the icon is what was kept from this page.
  const tabId = await tabIdOf(browser.worker, page);
  const state = await until(async () => {
    const answer = await browser.ask({ type: 'state', tabId });
    return answer.count === ads.length + trackers.length ? answer : null;
  }, 'the count of what was blocked');
  assert.deepEqual({ ...state, count: undefined }, { host: 'news.test', site: 'news.test', filterable: true, allowed: false, paused: false, count: undefined });
  await page.close();
});

test('a site let through gets everything, and is filtered again when taken back', async () => {
  const ad = 'adnxs.com';
  server.page('shop.test', '/', `<!doctype html><title>Shop</title><body><script src="${server.url(ad, '/tag.js')}"></script></body>`);

  let { page, blocked } = await open(browser.context, server.url('shop.test'));
  assert.equal(blocked().length, 1);
  const tabId = await tabIdOf(browser.worker, page);

  // Let through from the popup's side: the worker reloads the tab.
  server.forget();
  const reloaded = page.waitForEvent('load');
  const answer = await browser.ask({ type: 'site:set', site: 'shop.test', allowed: true, tabId });
  assert.deepEqual(answer.settings.allowlist, ['shop.test']);
  await reloaded;
  await until(() => server.reached(ad, '/tag.js'), 'the ad host to be asked once the site is let through');
  assert.deepEqual(await page.evaluate(() => window.ran), [`${ad}/tag.js`]);
  assert.equal((await browser.ask({ type: 'state', tabId })).allowed, true);
  await page.close();

  // Its subdomains go with it; another site is still filtered.
  server.page('www.shop.test', '/', `<!doctype html><body><script src="${server.url(ad, '/tag.js')}"></script></body>`);
  ({ page, blocked } = await open(browser.context, server.url('www.shop.test')));
  assert.equal(blocked().length, 0);
  await page.close();
  server.page('other.test', '/', `<!doctype html><body><script src="${server.url(ad, '/tag.js')}"></script></body>`);
  ({ page, blocked } = await open(browser.context, server.url('other.test')));
  assert.equal(blocked().length, 1);
  await page.close();

  // Taken back: filtered again.
  await browser.ask({ type: 'site:set', site: 'shop.test', allowed: false });
  ({ page, blocked } = await open(browser.context, server.url('shop.test')));
  assert.equal(blocked().length, 1);
  assert.deepEqual(await browser.worker.evaluate(() => chrome.declarativeNetRequest.getDynamicRules()), []);
  await page.close();
});

test('paused, everything goes through everywhere; resumed, it is filtered again', async () => {
  const ad = 'adnxs.com';
  server.page('paused.test', '/', `<!doctype html><body><script src="${server.url(ad, '/tag.js')}"></script></body>`);
  await browser.ask({ type: 'settings:set', patch: { paused: true } });
  let { page, blocked } = await open(browser.context, server.url('paused.test'));
  assert.equal(blocked().length, 0);
  await page.close();
  await browser.ask({ type: 'settings:set', patch: { paused: false } });
  ({ page, blocked } = await open(browser.context, server.url('paused.test')));
  assert.equal(blocked().length, 1);
  await page.close();
});

test('a web page cannot ask the worker to change anything', async () => {
  // Only a content script could even try; the worker answers pages' scripts with nothing but what to hide.
  const { page } = await open(browser.context, server.url('news.test', '/plain'));
  const before = await browser.ask({ type: 'overview' });
  const tabId = await tabIdOf(browser.worker, page);
  const answer = await browser.worker.evaluate(
    (id) =>
      chrome.scripting.executeScript({
        target: { tabId: id },
        func: () => chrome.runtime.sendMessage({ type: 'site:set', site: 'news.test', allowed: true }).then((reply) => reply ?? 'no answer', () => 'no answer'),
      }),
    tabId,
  );
  assert.equal(answer[0].result, 'no answer');
  assert.deepEqual((await browser.ask({ type: 'overview' })).settings, before.settings);
  await page.close();
});
