// Pop-ups, in a real Chromium with the small list of test/e2e/lists: a
// tab a page opens to an address the list names as a pop-up is closed,
// however it gets there, and every other tab is left alone.

import assert from 'node:assert/strict';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { build } from '../../tools/build.js';
import { complaints, launch, open, root, startServer, until } from './harness.js';

let server;
let browser;

before(async () => {
  const out = join(root, 'build-test');
  build({ lists: join(root, 'test', 'e2e', 'lists'), out, quiet: true });
  server = await startServer();
  browser = await launch(out);
});

after(async () => {
  await browser?.close();
  await server?.close();
});

/** The addresses of every tab, as the extension sees them. */
const tabs = () => browser.worker.evaluate(async () => (await chrome.tabs.query({})).map((tab) => tab.pendingUrl || tab.url || ''));

/** How many tabs have been opened since the worker was last asked to count them. */
async function counting() {
  await browser.worker.evaluate(() => {
    if (globalThis.madeTabs === undefined) chrome.tabs.onCreated.addListener(() => globalThis.madeTabs++);
    globalThis.madeTabs = 0;
  });
  return () => browser.worker.evaluate(() => globalThis.madeTabs);
}

/**
 * Opens a page of `host` holding `body`, does `act` on it, and says what
 * became of the tab that opened: { closed } or { kept: its address }.
 */
async function opening(host, body, act) {
  server.page(host, '/', `<!doctype html><title>${host}</title><body>${body}</body>`);
  const { page } = await open(browser.context, server.url(host));
  const before = (await tabs()).length;
  const made = await counting();
  await act(page);
  await until(async () => (await made()) >= 1, 'a tab to be opened');
  // Closed, or still there once it has had the time closing takes many times over.
  let closed = false;
  try {
    await until(async () => (await tabs()).length === before, 'the tab to be closed', { timeout: 1500 });
    closed = true;
  } catch {
    closed = false;
  }
  let kept = null;
  if (!closed) {
    const extra = browser.context.pages().filter((other) => other !== page && !other.url().startsWith('chrome-extension://'));
    kept = extra.map((other) => other.url()).at(-1) ?? null;
    for (const other of extra) await other.close();
  }
  await page.close();
  return closed ? { closed } : { kept };
}

const link = (url) => `<a id="go" target="_blank" href="${url}">a link that opens a tab</a>`;
const click = (page) => page.click('#go');

test('a tab opened straight to a pop-up address is closed; one opened to any other is left', async () => {
  assert.deepEqual(await opening('news.test', link(server.url('popup-only.test', '/landing')), click), { closed: true });
  assert.deepEqual(await opening('news.test', link(server.url('cdn.popup-only.test', '/landing')), click), { closed: true }, 'a subdomain with its host');
  assert.deepEqual(await opening('news.test', link(server.url('plain.test', '/article')), click), { kept: server.url('plain.test', '/article') });
});

test('a window opened by script is closed too: straight there, opened empty and sent there, or by way of another page', async () => {
  const target = server.url('popup-only.test', '/landing');
  const button = (script) => `<button id="go" onclick="${script}">open</button>`;
  assert.deepEqual(await opening('news.test', button(`window.open('${target}')`), click), { closed: true });
  assert.deepEqual(await opening('news.test', button(`const made = window.open('about:blank'); setTimeout(() => { made.location = '${target}'; }, 150)`), click), { closed: true }, 'opened empty, then sent there');
  // By way of a page that sends it on once it has loaded.
  server.page('plain.test', '/out', `<!doctype html><body><script>setTimeout(() => { location.href = ${JSON.stringify(target)}; }, 100);</script></body>`);
  assert.deepEqual(await opening('news.test', button(`window.open('${server.url('plain.test', '/out')}')`), click), { closed: true }, 'by way of another page');
});

test('a pop-up filter is for the pages it names, of other sites where it says so, and an exception takes it back', async () => {
  const zoned = server.url('anything.test', '/pop.php?zone=7');
  assert.deepEqual(await opening('news.test', link(zoned), click), { closed: true }, 'domain=news.test, from news.test');
  assert.deepEqual(await opening('other.test', link(zoned), click), { kept: zoned }, 'and not from another site');
  const account = server.url('popup-only.test', '/account/');
  assert.deepEqual(await opening('news.test', link(account), click), { kept: account }, 'an exception for some of a host\'s addresses');
  const third = server.url('popthird.test', '/landing');
  assert.deepEqual(await opening('news.test', link(third), click), { closed: true }, 'third-party, from another site');
  assert.deepEqual(await opening('www.popthird.test', link(third), click), { kept: third }, 'and not from its own');
});

test('nothing is closed for a site let through, with the switch off, or while paused', async () => {
  const target = server.url('popup-only.test', '/landing');
  await browser.ask({ type: 'site:set', site: 'news.test', allowed: true });
  assert.deepEqual(await opening('news.test', link(target), click), { kept: target }, 'the page that opened it is let through');
  await browser.ask({ type: 'site:set', site: 'news.test', allowed: false });

  await browser.ask({ type: 'settings:set', patch: { popups: false } });
  assert.deepEqual(await opening('news.test', link(target), click), { kept: target }, 'the switch is off');
  await browser.ask({ type: 'settings:set', patch: { popups: true } });

  await browser.ask({ type: 'settings:set', patch: { paused: true } });
  assert.deepEqual(await opening('news.test', link(target), click), { kept: target }, 'paused');
  await browser.ask({ type: 'settings:set', patch: { paused: false } });

  assert.deepEqual(await opening('news.test', link(target), click), { closed: true }, 'and closed again after all that');
});

test('a tab the person opens for themselves is theirs, whatever its address', async () => {
  // No page opened it.
  const page = await browser.context.newPage();
  await page.goto(server.url('popup-only.test', '/landing'));
  await page.waitForTimeout(400);
  assert.equal(page.isClosed(), false);
  assert.equal(await page.title(), 'popup-only.test');
  await page.close();

  // One a page opened, in which the person then goes somewhere by the address bar.
  server.page('news.test', '/', `<!doctype html><body>${link(server.url('plain.test', '/article'))}</body>`);
  const { page: opener } = await open(browser.context, server.url('news.test'));
  const [made] = await Promise.all([browser.context.waitForEvent('page'), opener.click('#go')]);
  await made.waitForLoadState();
  await made.goto(server.url('popup-only.test', '/landing'));
  await made.waitForTimeout(400);
  assert.equal(made.isClosed(), false, 'gone to by hand, it is left');
  await made.close();
  await opener.close();
});

test('with a list switched off its pop-ups are no longer closed', async () => {
  const target = server.url('popup-only.test', '/landing');
  await browser.ask({ type: 'ruleset:set', id: 'easylist', enabled: false });
  assert.deepEqual(await opening('news.test', link(target), click), { kept: target });
  await browser.ask({ type: 'ruleset:set', id: 'easylist', enabled: true });
  assert.deepEqual(await opening('news.test', link(target), click), { closed: true });
});

test('after all of that, Chromium holds nothing against the extension', async (t) => {
  const held = await complaints(browser);
  if (!held) return t.skip('this Chromium has no extensions page to ask');
  assert.deepEqual(held, { state: 'ENABLED', warnings: [], manifest: [], errors: [] });
});
