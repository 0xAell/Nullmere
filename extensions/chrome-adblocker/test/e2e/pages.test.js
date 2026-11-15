// The popup and the options page, in the built extension in Chromium:
// what they show, and that pressing things does what it says.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { complaints, later, launch, open, root, startServer, tabIdOf, until } from './harness.js';

let server;
let browser;
const AD = 'adnxs.com';
const lists = JSON.parse(readFileSync(join(root, 'build', 'lists.json'), 'utf8'));

before(async () => {
  server = await startServer();
  browser = await launch();
  server.page('news.test', '/', `<!doctype html><title>News</title><body>${later([server.url(AD, '/a.gif'), server.url('ad.doubleclick.net', '/b.gif')])}</body>`);
});

after(async () => {
  await browser?.close();
  await server?.close();
});

/** The popup as it would open over a tab. */
async function popupFor(tabId) {
  const popup = await browser.context.newPage();
  await popup.setViewportSize({ width: 340, height: 520 });
  await popup.goto(browser.extensionUrl(`popup/popup.html?tab=${tabId}`));
  await popup.waitForFunction(() => document.getElementById('lake').dataset.state !== 'loading');
  return popup;
}

const read = (popup) =>
  popup.evaluate(() => ({
    state: document.getElementById('lake').dataset.state,
    count: document.getElementById('count').hidden ? null : document.getElementById('count').textContent,
    label: document.getElementById('count-label').textContent,
    site: document.getElementById('site').textContent.trim(),
    words: document.getElementById('words').textContent,
    act: document.getElementById('act').hidden ? null : document.getElementById('act').textContent,
    pressed: document.getElementById('moon').getAttribute('aria-pressed'),
    moon: document.getElementById('moon').getAttribute('aria-label'),
    newMoon: document.getElementById('moon').classList.contains('new'),
    disabled: document.getElementById('moon').disabled,
  }));

test('the popup shows what was kept from the page in front, and lets its site through and back', async () => {
  const { page } = await open(browser.context, server.url('news.test'));
  const tabId = await tabIdOf(browser.worker, page);
  const popup = await popupFor(tabId);
  await until(async () => (await read(popup)).count === '2', 'the popup to count both requests');
  assert.deepEqual(await read(popup), {
    state: 'still',
    count: '2',
    label: 'Requests kept from this page',
    site: 'news.test',
    words: 'The water is still.',
    act: 'Let this site through',
    pressed: 'true',
    moon: 'Stillwater is filtering news.test. Press to let this site through.',
    newMoon: false,
    disabled: false,
  });

  // Let through with the button: the tab is reloaded and the ad host asked.
  server.forget();
  await popup.click('#act');
  await until(async () => (await read(popup)).state === 'allowed', 'the popup to show the site let through');
  assert.deepEqual({ ...(await read(popup)), moon: null }, { state: 'allowed', count: null, label: 'Let through', site: 'news.test', words: 'Nothing is kept from this site.', act: 'Still this site again', pressed: 'false', moon: null, newMoon: true, disabled: false });
  await until(() => server.reached(AD, '/a.gif'), 'the tab to reload with the ad host let through');

  // And back, with the moon itself, from the keyboard.
  await popup.focus('#moon');
  await popup.keyboard.press('Enter');
  await until(async () => (await read(popup)).state === 'still', 'the popup to show the site filtered again');
  await until(async () => (await read(popup)).count === '2', 'the reloaded page to be filtered again');
  assert.deepEqual((await browser.ask({ type: 'overview' })).settings.allowlist, []);
  await popup.close();
  await page.close();
});

test('on a subdomain of a site let through, the popup names that site and stills it', async () => {
  await browser.ask({ type: 'site:set', site: 'news.test', allowed: true });
  server.page('live.news.test', '/', `<!doctype html><title>Live</title><body>${later([server.url(AD, '/a.gif'), server.url('ad.doubleclick.net', '/b.gif')])}</body>`);
  server.forget();
  const { page } = await open(browser.context, server.url('live.news.test'));
  await until(() => server.reached(AD, '/a.gif'), 'the subdomain to be let through with its site');
  const popup = await popupFor(await tabIdOf(browser.worker, page));
  assert.deepEqual([(await read(popup)).state, (await read(popup)).site, (await read(popup)).moon], ['allowed', 'news.test', 'news.test is let through. Press to filter it again.']);

  // Pressing stills it: it is news.test that goes, since nothing less would.
  await popup.click('#act');
  await until(async () => (await read(popup)).state === 'still', 'the popup to show the page filtered again');
  assert.deepEqual((await browser.ask({ type: 'overview' })).settings.allowlist, []);
  assert.equal((await read(popup)).site, 'live.news.test');
  await until(async () => (await read(popup)).count === '2', 'the reloaded page to be filtered again');
  await popup.close();
  await page.close();
});

test('the popup says when Stillwater is paused, and resumes', async () => {
  const { page } = await open(browser.context, server.url('news.test'));
  const tabId = await tabIdOf(browser.worker, page);
  await browser.ask({ type: 'settings:set', patch: { paused: true } });
  const popup = await popupFor(tabId);
  assert.deepEqual([(await read(popup)).state, (await read(popup)).act, (await read(popup)).words], ['paused', 'Resume', 'Stillwater is paused everywhere.']);
  await popup.click('#act');
  await until(async () => (await read(popup)).state === 'still', 'the popup to show Stillwater at work again');
  assert.equal((await browser.ask({ type: 'overview' })).settings.paused, false);
  await popup.close();
  await page.close();
});

test('on a page that cannot be filtered the popup offers nothing to press', async () => {
  const own = await browser.context.newPage();
  await own.goto(browser.extensionUrl('options/options.html'));
  const tabId = await tabIdOf(browser.worker, own);
  const popup = await popupFor(tabId);
  const shown = await read(popup);
  assert.deepEqual([shown.state, shown.count, shown.act, shown.disabled, shown.site], ['none', null, null, true, '']);
  assert.equal(await popup.evaluate(() => document.getElementById('version').textContent), JSON.parse(readFileSync(join(root, 'src', 'manifest.json'), 'utf8')).version);
  await popup.close();
  await own.close();
});

/** The options page, ready. */
async function optionsPage() {
  const page = await browser.context.newPage();
  await page.goto(browser.extensionUrl('options/options.html'));
  await page.waitForFunction(() => document.body.dataset.ready === 'true');
  return page;
}

const switches = (page, list) =>
  page.evaluate((id) => [...document.querySelectorAll(`#${id} li`)].map((row) => [row.querySelector('.title').textContent, row.querySelector('.switch').getAttribute('aria-checked')]), list);

test('the options page lists the lists with their numbers, and switches one off and on', async () => {
  const page = await optionsPage();
  assert.deepEqual(await switches(page, 'lists'), [['EasyList', 'true'], ['EasyPrivacy', 'true'], ['Stillwater supplement', 'true']]);
  const detail = await page.textContent('#lists li .detail');
  assert.match(detail, new RegExp(`${lists.lists[0].filters.toLocaleString('en-US')} filters`));
  assert.match(await page.textContent('#lists-foot'), new RegExp(`${lists.totals.rules.toLocaleString('en-US')} of the 30,000 rules`));

  await page.click('#lists li:nth-child(2) .switch');
  await until(async () => (await switches(page, 'lists'))[1][1] === 'false', 'the EasyPrivacy switch to turn off');
  assert.deepEqual((await browser.worker.evaluate(() => chrome.declarativeNetRequest.getEnabledRulesets())).sort(), ['easylist', 'stillwater']);
  assert.match(await page.textContent('#lists-foot'), new RegExp(`${(lists.totals.rules - lists.lists[1].rules).toLocaleString('en-US')} of the 30,000 rules`));
  await page.click('#lists li:nth-child(2) .switch');
  await until(async () => (await switches(page, 'lists'))[1][1] === 'true', 'the EasyPrivacy switch to turn on');
  assert.equal((await browser.worker.evaluate(() => chrome.declarativeNetRequest.getEnabledRulesets())).length, 3);
  await page.close();
});

test('the options page lets a site through as typed or pasted, refuses what is not a site, and takes one back', async () => {
  const page = await optionsPage();
  const sites = () => page.evaluate(() => [...document.querySelectorAll('#sites .title')].map((title) => title.textContent));
  assert.deepEqual(await sites(), []);
  assert.equal(await page.textContent('#sites .empty'), 'No site is let through.');

  await page.fill('#site-input', 'not a site');
  await page.press('#site-input', 'Enter');
  assert.equal(await page.textContent('#site-error'), 'That is not a site. Write it as example.com.');
  assert.deepEqual(await sites(), []);

  await page.fill('#site-input', 'https://www.Shop.test/basket?x=1');
  assert.equal(await page.textContent('#site-error'), '', 'the complaint goes when typing begins again');
  await page.press('#site-input', 'Enter');
  await until(async () => (await sites()).length === 1, 'the site to be listed');
  await page.fill('#site-input', 'news.test');
  await page.click('#site-form button');
  await until(async () => (await sites()).length === 2, 'the second site to be listed');
  assert.deepEqual(await sites(), ['news.test', 'shop.test']);
  const rules = await browser.worker.evaluate(() => chrome.declarativeNetRequest.getDynamicRules());
  assert.deepEqual(rules.map((rule) => rule.condition.requestDomains ?? rule.condition.initiatorDomains), [['news.test', 'shop.test'], ['news.test', 'shop.test']]);

  await page.click('#sites li:first-child button');
  await until(async () => (await sites()).length === 1, 'the site to be taken back');
  assert.deepEqual(await sites(), ['shop.test']);
  await browser.ask({ type: 'site:set', site: 'shop.test', allowed: false });
  await page.close();
});

test('the switches keep their settings, and the pause is a rule of its own', async () => {
  const page = await optionsPage();
  assert.deepEqual(await switches(page, 'switches'), [['Hide the slots ads leave', 'true'], ['YouTube', 'true'], ['Count on the icon', 'true'], ['Pause everywhere', 'false']]);
  for (const row of [1, 2, 3, 4]) await page.click(`#switches li:nth-child(${row}) .switch`);
  await until(async () => (await switches(page, 'switches')).map((item) => item[1]).join() === 'false,false,false,true', 'every switch to change');
  const { settings } = await browser.ask({ type: 'overview' });
  assert.deepEqual([settings.cosmetic, settings.youtube, settings.badge, settings.paused], [false, false, false, true]);
  const rules = await browser.worker.evaluate(() => chrome.declarativeNetRequest.getDynamicRules());
  assert.deepEqual(rules.map((rule) => [rule.id, rule.action.type, rule.priority]), [[2, 'allow', 1000]]);
  await page.close();
});

test('a change Chrome refuses is not kept: the rules and the page stay as they were, and the page is told', async () => {
  // Have Chrome refuse the last thing a change does, once.
  await browser.worker.evaluate(() => {
    const real = chrome.action.setBadgeTextColor;
    chrome.action.setBadgeTextColor = () => {
      chrome.action.setBadgeTextColor = real;
      return Promise.reject(new Error('Refused, for the test.'));
    };
  });
  const before = (await browser.ask({ type: 'overview' })).settings;
  const answer = await browser.ask({ type: 'settings:set', patch: { paused: !before.paused } });
  assert.equal(answer.error, 'Refused, for the test.');
  assert.deepEqual((await browser.ask({ type: 'overview' })).settings, before, 'nothing was kept');
  const rules = await browser.worker.evaluate(() => chrome.declarativeNetRequest.getDynamicRules());
  assert.equal(rules.some((rule) => rule.id === 2), before.paused, 'and the pause rule, already made when Chrome refused, was taken back');
  // The next change goes through.
  const again = await browser.ask({ type: 'settings:set', patch: { paused: before.paused } });
  assert.equal(again.error, undefined);
});

test('putting everything back as installed is asked twice, and does it', async () => {
  await browser.ask({ type: 'site:set', site: 'kept.test', allowed: true });
  await browser.ask({ type: 'ruleset:set', id: 'easyprivacy', enabled: false });
  const page = await optionsPage();
  await page.click('#reset');
  assert.equal(await page.textContent('#reset'), 'Press again to put everything back');
  assert.deepEqual((await browser.ask({ type: 'overview' })).settings.allowlist, ['kept.test'], 'once is not enough');
  await page.click('#reset');
  await until(async () => (await switches(page, 'switches')).map((item) => item[1]).join() === 'true,true,true,false', 'the switches to go back');
  const state = await browser.ask({ type: 'overview' });
  assert.deepEqual(state.settings, { allowlist: [], paused: false, cosmetic: true, youtube: true, badge: true, listsOff: [] });
  assert.deepEqual(state.enabled.sort(), ['easylist', 'easyprivacy', 'stillwater']);
  assert.deepEqual(await browser.worker.evaluate(() => chrome.declarativeNetRequest.getDynamicRules()), []);
  await page.close();
});

test('a switch pressed from the keyboard keeps the keyboard, and a change made elsewhere shows on the page', async () => {
  const page = await optionsPage();
  await page.focus('#switches li:nth-child(3) .switch');
  await page.keyboard.press('Space');
  await until(async () => (await switches(page, 'switches'))[2][1] === 'false', 'the switch to turn off');
  assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('aria-label')), 'Count on the icon', 'still on the switch that was pressed');
  await page.keyboard.press('Space');
  await until(async () => (await switches(page, 'switches'))[2][1] === 'true', 'the switch to turn back on');

  // From the popup's side, while the options page is open.
  await browser.ask({ type: 'site:set', site: 'elsewhere.test', allowed: true });
  await until(() => page.evaluate(() => [...document.querySelectorAll('#sites .title')].some((title) => title.textContent === 'elsewhere.test')), 'the site let through elsewhere to be listed');
  // Taking the last site back gives the keyboard to the field.
  await page.focus('#sites li:first-child button');
  await page.keyboard.press('Enter');
  await until(() => page.evaluate(() => document.querySelector('#sites .empty') !== null), 'the list to empty');
  assert.equal(await page.evaluate(() => document.activeElement?.id), 'site-input');
  assert.equal(await page.textContent('#problem'), '');
  await page.close();
});

test('a big page\'s classes are sent in lots, and its slots still hidden', async () => {
  // More classes than one message may carry, and after them all one EasyList hides everywhere.
  const classes = Array.from({ length: 25000 }, (_, index) => `<i class="c${index}"></i>`).join('');
  server.page('big.test', '/', `<!doctype html><body>${classes}<div id="slot" class="ad--banner">ad</div></body>`);
  const { page } = await open(browser.context, server.url('big.test'));
  await until(() => page.evaluate(() => getComputedStyle(document.getElementById('slot')).display === 'none'), 'the slot on the big page to be hidden');
  await page.close();
});

test('the options page says what it cannot do with the build\'s own numbers, and names the lists\' authors', async () => {
  const page = await optionsPage();
  const limits = await page.evaluate(() => [...document.querySelectorAll('#limits li')].map((item) => item.textContent));
  assert.equal(limits.length, 5);
  const popups = lists.lists.reduce((sum, list) => sum + (list.dropped['option:popup'] ?? 0), 0);
  assert.ok(popups > 1000);
  assert.match(limits[1], new RegExp(`${popups.toLocaleString('en-US')} that close pop-up windows`));
  assert.match(await page.textContent('#about-title ~ .note:nth-of-type(2)'), /EasyList authors.*GNU General Public License/s);
  assert.equal(await page.getAttribute('a[href="https://easylist.to/"]', 'rel'), 'noreferrer');
  // Every control can be reached and named.
  const unnamed = await page.evaluate(() => [...document.querySelectorAll('button, input, a')].filter((control) => !(control.textContent.trim() || control.getAttribute('aria-label'))).length);
  assert.equal(unnamed, 0);
  await page.close();
});

test('after all of that, Chromium holds nothing against the extension', async (t) => {
  const held = await complaints(browser);
  if (!held) return t.skip('this Chromium has no extensions page to ask');
  assert.deepEqual(held, { state: 'ENABLED', warnings: [], manifest: [], errors: [] });
});
