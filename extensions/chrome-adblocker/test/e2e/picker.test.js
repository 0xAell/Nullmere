// The element picker in a real Chromium: started from the popup, it lets
// a person point at something on the page and keep a filter that hides
// it, for that site, as one of their own; Escape keeps nothing; and only
// the tab it was started in can keep anything.

import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { launch, open, startServer, tabIdOf, until } from './harness.js';

let server;
let browser;

const PAGE = `<!doctype html><title>pick</title><body style="margin:0;font:16px sans-serif">
  <div id="column">
    <div id="banner" class="offer-tile big" style="height:120px;background:#c33">Buy now</div>
    <div class="offer-tile" id="second" style="height:60px;background:#933">Also an ad</div>
    <p id="words" style="height:60px">The page's own words.</p>
  </div></body>`;

before(async () => {
  server = await startServer();
  server.page('www.pick.test', '/', PAGE);
  server.page('www.pick.test', '/other', PAGE);
  browser = await launch();
});

after(async () => {
  await browser?.close();
  await server?.close();
});

const shown = (page, id) => page.evaluate((which) => getComputedStyle(document.getElementById(which)).display !== 'none', id);

/** The middle of an element on the page, in the page's own coordinates. */
async function middle(page, id) {
  const box = await page.locator(`#${id}`).boundingBox();
  return [box.x + box.width / 2, box.y + box.height / 2];
}

test('the popup offers the picker on a page Stillwater filters, and not on one let through', async () => {
  const { page } = await open(browser.context, server.url('www.pick.test'));
  const tabId = await tabIdOf(browser.worker, page);
  const popup = await browser.context.newPage();
  await popup.goto(browser.extensionUrl(`popup/popup.html?tab=${tabId}`));
  await until(async () => (await popup.isVisible('#pick')) && (await popup.textContent('#pick')) === 'Hide an element', 'the picker to be offered');
  await browser.ask({ type: 'site:set', site: 'pick.test', allowed: true });
  await until(async () => !(await popup.isVisible('#pick')), 'the picker not to be offered on a site let through');
  await browser.ask({ type: 'site:set', site: 'pick.test', allowed: false });
  await popup.close();
  await page.close();
});

test('pointing, clicking and Hide it keeps a filter for the site and hides what it names at once and after', async () => {
  const { page } = await open(browser.context, server.url('www.pick.test'));
  const tabId = await tabIdOf(browser.worker, page);
  await browser.ask({ type: 'picker:start', tabId });
  await page.waitForSelector('[data-stillwater-picker]', { state: 'attached' });

  // Pointed at, the banner is outlined; clicked, it is chosen, and the page's own click never comes.
  await page.evaluate(() => document.getElementById('banner').addEventListener('click', () => (window.clicked = true)));
  await page.mouse.move(...(await middle(page, 'banner')));
  await page.mouse.click(...(await middle(page, 'banner')));
  assert.equal(await page.evaluate(() => window.clicked), undefined, 'the page did not get the click');
  const ways = await page.locator('[data-stillwater-picker] label').allTextContents();
  assert.deepEqual(ways, ['#banner1 on this page', 'div.offer-tile.big1 on this page', '.offer-tile2 on this page', '#column > div:nth-of-type(1)1 on this page']);

  // Wider chooses what holds it, and back again by clicking.
  await page.locator('[data-stillwater-picker] button.wider').click();
  assert.deepEqual(await page.locator('[data-stillwater-picker] label code').allTextContents(), ['#column', 'div:nth-of-type(1)']);
  await page.locator('[data-stillwater-picker] button.cancel').click();
  assert.equal(await page.locator('[data-stillwater-picker]').count(), 0, 'Cancel takes the picker away');

  // Again, and kept: the third way, which names both sponsor boxes.
  await browser.ask({ type: 'picker:start', tabId });
  await page.waitForSelector('[data-stillwater-picker]', { state: 'attached' });
  await page.mouse.move(...(await middle(page, 'banner')));
  await page.mouse.click(...(await middle(page, 'banner')));
  await page.locator('[data-stillwater-picker] label').nth(2).click();
  await page.locator('[data-stillwater-picker] button.go').click();
  await until(async () => (await page.locator('[data-stillwater-picker]').count()) === 0, 'the picker to be done');
  await until(async () => !(await shown(page, 'banner')) && !(await shown(page, 'second')), 'both boxes to be hidden at once');
  assert.ok(await shown(page, 'words'), 'the page\'s words stay');
  const { settings, own } = await browser.ask({ type: 'overview' });
  assert.equal(settings.own, 'pick.test##.offer-tile', 'kept for the site, www. and all');
  assert.equal(own.taken, 1);
  await page.close();

  // Another page of the site hides them by the filter kept.
  const again = await open(browser.context, server.url('www.pick.test', '/other'));
  await until(async () => !(await shown(again.page, 'banner')), 'the filter kept to hide them on another page');
  assert.ok(await shown(again.page, 'words'));
  await again.page.close();
  await browser.ask({ type: 'own:set', text: '' });
});

test('Escape keeps nothing, and a tab the picker was not started in can keep nothing', async () => {
  const { page } = await open(browser.context, server.url('www.pick.test'));
  const tabId = await tabIdOf(browser.worker, page);
  await browser.ask({ type: 'picker:start', tabId });
  await page.waitForSelector('[data-stillwater-picker]', { state: 'attached' });
  await page.mouse.click(...(await middle(page, 'banner')));
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('[data-stillwater-picker]').count(), 0);
  assert.equal((await browser.ask({ type: 'overview' })).settings.own, '');

  // Put into another tab other than from the popup, it can keep nothing, and says so.
  const other = await open(browser.context, server.url('www.pick.test', '/other'));
  const otherId = await tabIdOf(browser.worker, other.page);
  await browser.worker.evaluate((id) => chrome.scripting.executeScript({ target: { tabId: id }, files: ['content/picker.js'] }), otherId);
  await other.page.waitForSelector('[data-stillwater-picker]', { state: 'attached' });
  await other.page.mouse.move(...(await middle(other.page, 'banner')));
  await other.page.mouse.click(...(await middle(other.page, 'banner')));
  await other.page.locator('[data-stillwater-picker] button.go').click();
  await until(async () => (await other.page.locator('[data-stillwater-picker] .said').textContent()) === "Start the picker from Stillwater's popup.", 'the refusal to be said');
  assert.equal((await browser.ask({ type: 'overview' })).settings.own, '');
  assert.ok(await shown(other.page, 'banner'));
  await other.page.close();
  await page.close();
});
