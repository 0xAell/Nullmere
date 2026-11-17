// Scriptlets in a real Chromium: each kind the lists use, run in a page of
// the site its filter names, in the page's own world before its first
// script; and not where a filter excepts a site, nor on a site let
// through, nor while Stillwater is paused.

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
  // The worker registers them as it puts the settings into effect.
  await until(() => browser.worker.evaluate(async () => (await chrome.scripting.getRegisteredContentScripts()).some((script) => script.id.startsWith('scriptlet-'))), 'the scriptlets to be registered');
});

after(async () => {
  await browser?.close();
  await server?.close();
});

/** A page of the site that tries everything the scriptlets stop, and writes down how it went in `window.results`. */
function trial(host) {
  server.page(host, '/caller.js', 'try { decodeURI("a"); results.external = "ran"; } catch { results.external = "stopped"; }', { type: 'application/javascript' });
  server.page(
    host,
    '/',
    `<!doctype html><title>${host}</title><body>
    <script>
      window.results = { trackedAtStart: localStorage.getItem('tracked'), cookieAtStart: document.cookie };
      window.adBlockerDetected = true;
      results.detected = window.adBlockerDetected;
      window.wall = { config: { enabled: true } };
      results.wall = window.wall.config.enabled;
      window.sparedValue = 5;
      results.spared = window.sparedValue;
      results.chosen = localStorage.getItem('chosen');
      results.consent = document.cookie.includes('consent=accept');
      localStorage.setItem('tracked', 'yes');
      document.cookie = '_trackme=1; path=/';
      document.addEventListener('ping', function trackPing() { results.tracked = true; });
      document.addEventListener('ping', function other() { results.other = true; });
      document.dispatchEvent(new Event('ping'));
    </script>
    <script>/* admiral */ try { document.createElement('div'); results.admiral = 'ran'; } catch { results.admiral = 'stopped'; }</script>
    <script>try { document.createElement('div'); results.plain = 'ran'; } catch { results.plain = 'stopped'; }</script>
    <script>try { decodeURI('a'); results.inline = 'ran'; } catch { results.inline = 'stopped'; }</script>
    <script src="/caller.js"></script>
    <script>results.wall = "v4ac1eiZr0";</script>
    <script>
      results.removed = ![...document.scripts].some((script) => script.textContent.includes('"v4ac1e' + 'iZr0"'));
      fetch('/beacon/1').then((response) => response.text()).then((text) => { results.beacon = text; });
      const request = new XMLHttpRequest();
      request.open('GET', '/telemetry/1');
      request.onload = () => { results.telemetry = [request.status, request.responseText]; };
      request.send();
      fetch('/allowed.json').then((response) => response.text()).then((text) => { results.allowed = text; });
    </script>
    </body>`,
  );
}

async function visit(host) {
  trial(host);
  const { page } = await open(browser.context, server.url(host, '/'));
  await until(() => page.evaluate(() => window.results?.beacon !== undefined && window.results?.allowed !== undefined && window.results?.external !== undefined), `the page on ${host} to finish`);
  if (await page.evaluate(() => window.results.telemetry === undefined && window.results.beacon === '')) {
    await until(() => page.evaluate(() => window.results.telemetry !== undefined), 'the request to telemetry to be answered');
  }
  const results = await page.evaluate(() => window.results);
  return { page, results };
}

test('each scriptlet does what its filter asks, in the page of the site it names', async () => {
  server.forget();
  const { page, results } = await visit('scripted.test');
  // set: a value the page can't change, even one it makes later.
  assert.equal(results.detected, false);
  assert.equal(results.spared, 1);
  // abort-current-script: the script that holds the needle is stopped, another not.
  assert.equal(results.admiral, 'stopped');
  assert.equal(results.plain, 'ran');
  // abort-on-stack-trace: an inline script is stopped reaching for it, a file's is not.
  assert.equal(results.inline, 'stopped');
  assert.equal(results.external, 'ran');
  // remove-node-text: the script is gone before it runs (the earlier value stands).
  assert.equal(results.wall, false, 'the set value, not the removed script\'s');
  assert.equal(results.removed, true);
  // set-local-storage-item and set-cookie, before the page's first script.
  assert.equal(results.chosen, 'true');
  assert.equal(results.consent, true);
  // no-fetch-if and no-xhr-if: answered, empty, and never sent.
  assert.equal(results.beacon, '');
  assert.deepEqual(results.telemetry, [200, '']);
  assert.ok(!server.reached('scripted.test', '/beacon') && !server.reached('scripted.test', '/telemetry'));
  assert.equal(results.allowed, '{}', 'another fetch goes out as ever');
  // addEventListener-defuser: the listener that holds the needle is never added.
  assert.equal(results.tracked, undefined);
  assert.equal(results.other, true);
  // What the page left for next time: the item and the cookie are taken on the next visit.
  await page.close();
  const again = await visit('scripted.test');
  assert.equal(again.results.trackedAtStart, null, 'set-local-storage-item took it away');
  assert.ok(!again.results.cookieAtStart.includes('_trackme'), `cookie-remover took it away: ${again.results.cookieAtStart}`);
  await again.page.close();
});

test('a site the filter excepts, a site let through, and a pause are left alone', async () => {
  // Excepted by the filter itself: the rest still run.
  const quiet = await visit('quiet.scripted.test');
  assert.equal(quiet.results.spared, 5);
  assert.equal(quiet.results.detected, false);
  await quiet.page.close();

  await browser.ask({ type: 'site:set', site: 'scripted.test', allowed: true });
  server.forget();
  const through = await visit('scripted.test');
  assert.deepEqual([through.results.detected, through.results.admiral, through.results.inline, through.results.tracked], [true, 'ran', 'ran', true]);
  assert.equal(through.results.wall, 'v4ac1eiZr0', 'the script that would have been taken out ran');
  assert.ok(server.reached('scripted.test', '/beacon/1'), 'the beacon went out');
  await through.page.close();
  await browser.ask({ type: 'site:set', site: 'scripted.test', allowed: false });

  await browser.ask({ type: 'settings:set', patch: { paused: true } });
  const paused = await visit('scripted.test');
  assert.equal(paused.results.detected, true);
  assert.equal(paused.results.inline, 'ran');
  await paused.page.close();
  await browser.ask({ type: 'settings:set', patch: { paused: false } });

  // And back on, they run again.
  const back = await visit('scripted.test');
  assert.equal(back.results.detected, false);
  await back.page.close();
});

test('Chromium holds nothing against the scriptlets', async (t) => {
  const held = await complaints(browser);
  if (!held) return t.skip('this Chromium has no extensions page to ask');
  assert.deepEqual(held, { state: 'ENABLED', warnings: [], manifest: [], errors: [] });
});
