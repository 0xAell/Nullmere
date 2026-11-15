// What the user chose has to outlast the worker, the browser and the
// extension being switched off: Chrome stops the worker when it is idle,
// forgets the badge's colours whenever it starts the extension anew, and
// tells the worker of only some of those starts.

import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { complaints, launch, open, root, startServer, until } from './harness.js';

const AD = 'adnxs.com';
const BADGE = { shown: [22, 35, 58, 255], unseen: [0, 0, 0, 0] };

let server;
let profile;

before(async () => {
  server = await startServer();
  profile = mkdtempSync(join(tmpdir(), 'stillwater-kept-'));
  for (const site of ['shop.test', 'other.test']) {
    server.page(site, '/', `<!doctype html><title>${site}</title><body><script src="${server.url(AD, '/tag.js')}"></script></body>`);
  }
});

after(async () => {
  await server?.close();
  rmSync(profile, { recursive: true, force: true });
});

/** How many of a site's ad requests Chromium kept from it. */
async function keptFrom(browser, site) {
  const { page, blocked } = await open(browser.context, server.url(site));
  const count = blocked().length;
  await page.close();
  return count;
}

/** What Chrome holds for the extension, asked of whichever worker is running now. */
async function held(worker) {
  return worker.evaluate(async () => ({
    background: await chrome.action.getBadgeBackgroundColor({}),
    dynamic: (await chrome.declarativeNetRequest.getDynamicRules()).map((rule) => rule.id).sort(),
    lists: (await chrome.declarativeNetRequest.getEnabledRulesets()).sort(),
    scripts: (await chrome.scripting.getRegisteredContentScripts()).map((script) => script.id),
    settings: (await chrome.storage.local.get('settings')).settings,
  }));
}

test('closed and started again, the browser has the sites let through, the switches and the lists as they were left', async () => {
  let browser = await launch(undefined, { profile });
  try {
    await browser.ask({ type: 'site:set', site: 'shop.test', allowed: true });
    await browser.ask({ type: 'settings:set', patch: { badge: false, youtube: false } });
    await browser.ask({ type: 'ruleset:set', id: 'easyprivacy', enabled: false });
    assert.equal(await keptFrom(browser, 'shop.test'), 0);
    assert.equal(await keptFrom(browser, 'other.test'), 1);
  } finally {
    await browser.close();
  }

  browser = await launch(undefined, { profile });
  try {
    // The worker answers nothing until the start's own work is done, so
    // what it says first is already what was left.
    const { settings, enabled } = await browser.ask({ type: 'overview' });
    assert.deepEqual(settings.allowlist, ['shop.test']);
    assert.equal(settings.badge, false);
    assert.equal(settings.youtube, false);
    assert.deepEqual(settings.listsOff, ['easyprivacy']);
    assert.deepEqual([...enabled].sort(), ['easylist', 'stillwater'], 'the list switched off is off when the options page first asks');
    const now = await held(browser.worker);
    assert.deepEqual(now.background, BADGE.unseen, 'the badge is unseen again, as it was left');
    assert.deepEqual(now.dynamic, [1, 3], 'the two rules that let a site through');
    assert.deepEqual(now.lists, ['easylist', 'stillwater'], 'the list switched off is still off');
    assert.deepEqual(now.scripts, [], 'the YouTube scripts are not registered while their switch is off');
    assert.equal(await keptFrom(browser, 'shop.test'), 0, 'the site let through still is');
    assert.equal(await keptFrom(browser, 'other.test'), 1, 'and another site is still filtered');

    const found = await complaints(browser);
    if (found) assert.deepEqual([found.warnings, found.manifest, found.errors], [[], [], []]);
  } finally {
    await browser.close();
  }
});

test('switched off and on again in chrome://extensions, the extension is as it was', async (t) => {
  const browser = await launch();
  try {
    await browser.ask({ type: 'site:set', site: 'shop.test', allowed: true });
    assert.deepEqual((await held(browser.worker)).background, BADGE.shown);

    const cards = await browser.context.newPage();
    await cards.goto('chrome://extensions/');
    if (!(await cards.evaluate(() => typeof chrome.management?.setEnabled === 'function'))) {
      t.skip('this Chromium does not let its extensions page switch an extension off');
      return;
    }
    const setEnabled = (enabled) => cards.evaluate(([id, on]) => new Promise((done) => chrome.management.setEnabled(id, on, done)), [browser.id, enabled]);
    await setEnabled(false);
    assert.equal(await keptFrom(browser, 'other.test'), 0, 'off, nothing is blocked');
    const started = browser.context.waitForEvent('serviceworker');
    await setEnabled(true);
    const worker = await started;

    // Chrome told the worker of nothing (no install, no browser start):
    // it has to see for itself that it was started anew.
    const now = await until(async () => {
      const state = await held(worker).catch(() => null);
      return state && state.background.join() === BADGE.shown.join() ? state : null;
    }, 'the badge to have its colours again');
    assert.deepEqual(now.dynamic, [1, 3]);
    assert.deepEqual(now.scripts.sort(), ['youtube', 'youtube-main']);
    assert.equal(await keptFrom(browser, 'shop.test'), 0, 'the site let through still is');
    assert.equal(await keptFrom(browser, 'other.test'), 1, 'and another site is filtered again');
    await cards.close();
  } finally {
    await browser.close();
  }
});

test('a worker Chrome has stopped comes back knowing what to hide and what was chosen', async () => {
  const browser = await launch();
  try {
    // A class EasyList hides wherever it is found, taken from the build.
    const { generic } = JSON.parse(readFileSync(join(root, 'build', 'cosmetic', 'easylist.json'), 'utf8'));
    const selector = generic.simple.find((item) => /^\.[a-z][\w-]*$/.test(item));
    assert.ok(selector, 'the built list has a plain class to hide');
    server.page('slots.test', '/', `<!doctype html><body><div id="slot" class="${selector.slice(1)}">an ad</div><p>words</p></body>`);
    await browser.ask({ type: 'site:set', site: 'shop.test', allowed: true });

    // Stop the worker as Chrome does when it has been idle.
    const desk = await browser.context.newPage();
    await desk.goto(browser.extensionUrl('options/options.html'));
    const protocol = await browser.context.newCDPSession(desk);
    const statuses = [];
    protocol.on('ServiceWorker.workerVersionUpdated', (event) => statuses.push(...event.versions.map((version) => version.runningStatus)));
    await protocol.send('ServiceWorker.enable');
    await until(() => statuses.includes('running'), 'the worker to be seen running');
    await protocol.send('ServiceWorker.stopAllWorkers');
    await until(() => statuses.at(-1) === 'stopped', 'the worker to stop');
    await desk.close();

    // The next page's content script wakes it; nothing it needs was in its memory.
    const { page } = await open(browser.context, server.url('slots.test'));
    await until(() => page.evaluate(() => getComputedStyle(document.getElementById('slot')).display === 'none'), 'the slot to be hidden by a worker started afresh');
    await page.close();
    assert.equal(await keptFrom(browser, 'shop.test'), 0);
    assert.equal(await keptFrom(browser, 'other.test'), 1);
  } finally {
    await browser.close();
  }
});
