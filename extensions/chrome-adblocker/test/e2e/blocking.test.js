// The built extension, with the real EasyList and EasyPrivacy, in a real
// Chromium: requests to ad hosts and trackers never leave the browser, a
// site's own requests do, and a site let through gets everything.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { refusedBy } from '../../tools/validate.js';
import { later, launch, open, root, startServer, tabIdOf, until } from './harness.js';

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

  await page.close();
});

test('the count on the icon is what was kept from the page in front', async () => {
  const hosts = ['adnxs.com', 'ad.doubleclick.net', 'googletagmanager.com'];
  server.page('counted.test', '/', `<!doctype html><title>Counted</title><body>${later(hosts.map((host) => server.url(host, '/pixel.gif')))}</body>`);
  const { page } = await open(browser.context, server.url('counted.test'));
  const tabId = await tabIdOf(browser.worker, page);
  const state = await until(async () => {
    const answer = await browser.ask({ type: 'state', tabId });
    return answer.count === hosts.length ? answer : null;
  }, 'the count of what was blocked');
  assert.deepEqual(state, { host: 'counted.test', site: 'counted.test', filterable: true, allowed: false, paused: false, count: 3 });
  assert.equal(await browser.worker.evaluate((id) => chrome.action.getBadgeText({ tabId: id }), tabId), '3', 'as Chrome writes it on the icon');
  await page.close();
});

test('the real lists\' selectors hide their slots: generic ones by the classes and ids a page has, a site\'s own on that site', async () => {
  const data = JSON.parse(readFileSync(join(root, 'build', 'cosmetic', 'easylist.json'), 'utf8'));
  assert.ok(data.generic.simple.length > 5000 && Object.keys(data.specific).length > 1000, 'the real list was built');
  const plain = /^[.#][a-zA-Z][\w-]*$/;
  const step = Math.floor(data.generic.simple.length / 8);
  const generic = Array.from({ length: 8 }, (_, index) => data.generic.simple[index * step]).filter((selector) => plain.test(selector));
  const [site, own] = Object.entries(data.specific).find(([host, selectors]) => /^[a-z0-9-]+\.[a-z]+$/.test(host) && plain.test(selectors[0]) && !data.generic.simple.includes(selectors[0]) && !data.exceptions[host]);
  const element = (selector, index) => (selector.startsWith('#') ? `<div id="${selector.slice(1)}" data-slot="${index}">ad</div>` : `<div class="${selector.slice(1)}" data-slot="${index}">ad</div>`);
  const body = `<p data-slot="content">The page itself.</p>${[...generic, own[0]].map(element).join('')}`;
  const hiddenOn = async (host) => {
    server.page(host, '/', `<!doctype html><body>${body}</body>`);
    const { page } = await open(browser.context, server.url(host));
    await until(() => page.evaluate((n) => [...document.querySelectorAll('[data-slot]')].filter((slot) => getComputedStyle(slot).display === 'none').length >= n, generic.length), `the generic slots on ${host}`);
    const result = await page.evaluate(() => [...document.querySelectorAll('[data-slot]')].filter((slot) => getComputedStyle(slot).display === 'none').map((slot) => slot.dataset.slot));
    await page.close();
    return result;
  };
  assert.ok(generic.length >= 5, 'enough plain generic selectors were sampled');
  assert.deepEqual(await hiddenOn('elsewhere.test'), generic.map((_, index) => String(index)), 'the generic slots, and neither the page nor another site\'s slot');
  assert.deepEqual(await hiddenOn(site), [...generic, own[0]].map((_, index) => String(index)), `${site}'s own slot too, on ${site}`);
});

test('a site let through gets everything, and is filtered again when taken back', async () => {
  const ad = 'adnxs.com';
  server.page('shop.test', '/', `<!doctype html><title>Shop</title><body><script src="${server.url(ad, '/tag.js')}"></script><iframe src="${server.url('widgets.test', '/embed')}"></iframe></body>`);
  server.page('widgets.test', '/embed', `<!doctype html><body><script src="${server.url(ad, '/in-frame.js')}"></script></body>`);

  let { page, blocked } = await open(browser.context, server.url('shop.test'));
  assert.equal(blocked().length, 2, 'the page\'s ad script, and the one in another site\'s frame');
  const tabId = await tabIdOf(browser.worker, page);

  // Let through from the popup's side: the worker reloads the tab.
  server.forget();
  const reloaded = page.waitForEvent('load');
  const answer = await browser.ask({ type: 'site:set', site: 'shop.test', allowed: true, tabId });
  assert.deepEqual(answer.settings.allowlist, ['shop.test']);
  await reloaded;
  await until(() => server.reached(ad, '/tag.js'), 'the ad host to be asked once the site is let through');
  await until(() => server.reached(ad, '/in-frame.js'), 'the frame of another site inside it to be let through with it');
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
  assert.equal(blocked().length, 2);
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
