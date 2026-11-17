// One's own filters in a real Chromium, written on the options page as a
// person would: they block, hide and let through as a list's lines do;
// each line not taken says why; a selector Chrome can't read hides
// nothing and harms no other; and they outlast the browser being closed.

import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { complaints, launch, open, startServer, until } from './harness.js';

// adnxs.com is a host EasyList blocks; the rest are the user's own.
const OWN = [
  '! Mine',
  '||ownads.test^',
  'ownpage.test##.promo',
  '##.own-generic-slot',
  '@@||adnxs.com^$domain=ownpage.test',
  'ownpage.test##+js(set, a, false)',
  'ownpage.test##div:::nothing',
  '*$image',
].join('\n');

let server;
let profile;

before(async () => {
  server = await startServer();
  profile = mkdtempSync(join(tmpdir(), 'stillwater-own-'));
  for (const host of ['ownpage.test', 'otherpage.test']) {
    server.page(
      host,
      '/',
      `<!doctype html><title>${host}</title><body>
      <div id="promo" class="promo">a promotion</div>
      <div id="slot" class="own-generic-slot">an ad</div>
      <p id="words">The page's own words.</p>
      <script src="${server.url('ownads.test', '/tag.js')}"></script>
      <script src="${server.url('adnxs.com', '/ttj.js')}"></script>
      </body>`,
    );
  }
});

after(async () => {
  await server?.close();
  rmSync(profile, { recursive: true, force: true });
});

/** What a page kept back and hid. */
async function seen(browser, host) {
  const { page, blocked } = await open(browser.context, server.url(host));
  const hidden = async () => page.evaluate(() => ['promo', 'slot', 'words'].filter((id) => getComputedStyle(document.getElementById(id)).display === 'none'));
  // The generic slot is hidden once the content script has told its classes.
  await until(async () => (await hidden()).includes('slot'), `the generic slot on ${host} to be hidden`);
  const result = { blocked: blocked().map((url) => new URL(url).hostname).sort(), hidden: await hidden() };
  await page.close();
  return result;
}

test('filters written on the options page block, hide and let through, and say what they could not take', async () => {
  const browser = await launch(undefined, { profile });
  try {
    const options = await browser.context.newPage();
    await options.goto(browser.extensionUrl('options/options.html'));
    await options.waitForSelector('body[data-ready="true"]');
    assert.equal(await options.textContent('#own-said'), 'None yet.');
    await options.fill('#own-input', OWN);
    await options.click('#own-save');
    await until(async () => (await options.textContent('#own-said')).includes('in use'), 'the filters to be kept');
    assert.equal(await options.textContent('#own-said'), '4 filters in use: 2 rules for Chrome, 2 selectors to hide. 3 lines do nothing; why is below.');
    const notes = await options.$$eval('#own-refused li', (items) => items.map((item) => item.textContent));
    assert.deepEqual(notes, [
      "Line 6, ownpage.test##+js(set, a, false): Chrome runs only the extension's own scripts, so a scriptlet of your own can't be run.",
      "Line 7, ownpage.test##div:::nothing: This browser can't read the selector div:::nothing, so it hides nothing.",
      'Line 8, *$image: It would match far too much: every request of its kind.',
    ]);
    // Kept as written, and in Chrome's rules beside the worker's own.
    const { settings } = await browser.ask({ type: 'overview' });
    assert.equal(settings.own, OWN);
    const dynamic = await browser.worker.evaluate(async () => (await chrome.declarativeNetRequest.getDynamicRules()).map((rule) => rule.id).sort((a, b) => a - b));
    assert.deepEqual(dynamic, [1000, 1001]);
    await options.close();

    // On the page they name: the host blocked, EasyList's host let through, both slots hidden.
    assert.deepEqual(await seen(browser, 'ownpage.test'), { blocked: ['ownads.test'], hidden: ['promo', 'slot'] });
    // Elsewhere: EasyList's host blocked as ever, only the generic slot hidden.
    assert.deepEqual(await seen(browser, 'otherpage.test'), { blocked: ['adnxs.com', 'ownads.test'], hidden: ['slot'] });

    const found = await complaints(browser);
    if (found) assert.deepEqual([found.warnings, found.manifest, found.errors], [[], [], []]);
  } finally {
    await browser.close();
  }
});

test('closed and started again, the browser has one\'s own filters as they were left, and they can be taken away', async () => {
  let browser = await launch(undefined, { profile });
  try {
    assert.equal((await browser.ask({ type: 'overview' })).settings.own, OWN);
    assert.deepEqual(await seen(browser, 'ownpage.test'), { blocked: ['ownads.test'], hidden: ['promo', 'slot'] });
    // Taken away, nothing of them is left.
    const after = await browser.ask({ type: 'own:set', text: '' });
    assert.equal(after.own.taken, 0);
    const dynamic = await browser.worker.evaluate(async () => (await chrome.declarativeNetRequest.getDynamicRules()).map((rule) => rule.id));
    assert.deepEqual(dynamic, []);
    const { page, blocked } = await open(browser.context, server.url('ownpage.test'));
    await page.waitForTimeout(700);
    assert.deepEqual(blocked().map((url) => new URL(url).hostname), ['adnxs.com']);
    assert.deepEqual(await page.evaluate(() => ['promo', 'slot'].filter((id) => getComputedStyle(document.getElementById(id)).display === 'none')), []);
    await page.close();
  } finally {
    await browser.close();
  }
});

test('an expression Chrome refuses whole is kept as its alternatives, and a :has() in a :has() is followed', async () => {
  // EasyList's own, which Chrome refuses whole as compiling too large, each ending alone it takes;
  // with a port allowed, as the stand-in server has one.
  const endings = 'club|bid|biz|xyz|site|pro|info|online|icu|monster|buzz|website|re|casa|top|one|space|network|live|systems|ml|world|life|co';
  const lines = [`/^https?:\\/\\/.*\\.(${endings})(:\\d+)?\\/.*/$script,domain=ownpage.test`, 'ownpage.test##article:has(header:has(.ct-sponsored))'];
  server.page(
    'ownpage.test',
    '/split',
    `<!doctype html><title>split</title><body>
    <article id="paid"><header><span class="ct-sponsored">Sponsored</span></header><p>An offer</p></article>
    <article id="story"><header><span>News</span></header><p>The page's own words.</p></article>
    <script src="${server.url('cdn.ads.xyz', '/tag.js')}"></script>
    <script src="${server.url('cdn.ads.example', '/tag.js')}"></script>
    </body>`,
  );
  const browser = await launch();
  try {
    const answer = await browser.ask({ type: 'own:set', text: lines.join('\n') });
    assert.equal(answer.own.taken, 2);
    assert.deepEqual(answer.own.refused, []);
    const dynamic = await browser.worker.evaluate(async () => (await chrome.declarativeNetRequest.getDynamicRules()).map((rule) => rule.condition.regexFilter).filter(Boolean));
    assert.equal(dynamic.length, endings.split('|').length, 'a rule for each ending');
    assert.ok(dynamic.includes('^https?:\\/\\/.*\\.xyz(:\\d+)?\\/.*'), JSON.stringify(dynamic.slice(0, 3)));
    const { page, blocked } = await open(browser.context, server.url('ownpage.test', '/split'));
    const hidden = () => page.evaluate(() => ['paid', 'story'].filter((id) => getComputedStyle(document.getElementById(id)).display === 'none'));
    await until(async () => (await hidden()).includes('paid'), 'the sponsored article to be hidden');
    assert.deepEqual(await hidden(), ['paid'], "the page's own article stays");
    assert.deepEqual(blocked().map((url) => new URL(url).hostname), ['cdn.ads.xyz'], 'the .xyz script kept back, the other let through');
    await page.close();
  } finally {
    await browser.close();
  }
});

test('more than the worker keeps is refused, and nothing changes', async () => {
  const browser = await launch();
  try {
    const answer = await browser.ask({ type: 'own:set', text: 'x'.repeat(200_001) });
    assert.match(answer.error, /more than 200,000 letters/);
    assert.equal((await browser.ask({ type: 'overview' })).settings.own, '');
  } finally {
    await browser.close();
  }
});
