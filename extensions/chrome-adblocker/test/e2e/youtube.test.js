// YouTube, against a stand-in. Chromium is told www.youtube.com is the
// local server (over HTTPS, which is the only way it will ask that host),
// and the server gives pages shaped like YouTube's where it matters: the
// player's response written into the page and fetched again, a player
// element that says when an ad is showing, and a feed with an ad slot.
//
// What this proves is that the extension does what it means to on pages
// of that shape. It can't prove YouTube still has that shape: that is
// checked by hand, and said so in the README.

import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { complaints, launch, open, startServer, until } from './harness.js';

let server;
let browser;
const HOST = 'www.youtube.com';
const RESPONSE = { playabilityStatus: { status: 'OK' }, videoDetails: { videoId: 'abc' }, adPlacements: [{ ad: 1 }], playerAds: [{ ad: 2 }], adSlots: [{ ad: 3 }], adBreakHeartbeatParams: 'x' };

const WATCH = `<!doctype html><title>Watch</title><body>
  <div id="movie_player" class="html5-video-player"><video id="video" src="/media/video.wav" preload="auto"></video></div>
  <div id="player-ads">An ad beside the player</div>
  <div id="contents">
    <ytd-rich-item-renderer id="promoted"><ytd-ad-slot-renderer>Promoted</ytd-ad-slot-renderer></ytd-rich-item-renderer>
    <ytd-rich-item-renderer id="video-tile"><div>A video</div></ytd-rich-item-renderer>
  </div>
  <script>var ytInitialPlayerResponse = ${JSON.stringify(RESPONSE)};</script>
  <script>
    window.report = {
      initial: Object.keys(ytInitialPlayerResponse).sort(),
      parsed: Object.keys(JSON.parse(${JSON.stringify(JSON.stringify(RESPONSE))})).sort(),
      inside: Object.keys(JSON.parse(${JSON.stringify(JSON.stringify({ playerResponse: RESPONSE, other: 1 }))}).playerResponse).sort(),
      unrelated: JSON.parse('{"ads":[1],"adPlacement":2,"list":[{"adPlacements":"deeper down, left alone"}]}'),
      native: Function.prototype.toString.call(JSON.parse).includes('[native code]') && Function.prototype.toString.call(Response.prototype.json).includes('[native code]'),
    };
    fetch('/youtubei/v1/player').then((response) => response.json()).then((json) => { window.report.fetched = Object.keys(json).sort(); });
  </script></body>`;

// The same page, whose first script tries to overhear the extension's two
// scripts and to tell the one in its own world to stop.
const HOSTILE = WATCH.replace(
  '<body>',
  `<body><script>
    window.heard = [];
    document.addEventListener('stillwater:word', (event) => window.heard.push(event.detail));
    window.unanswered = document.dispatchEvent(new CustomEvent('stillwater:word', { detail: 'stillwater:page', cancelable: true }));
    for (const name of ['stillwater:ready', 'stillwater:rest', 'stillwater:page']) document.dispatchEvent(new CustomEvent(name));
    // And puts its own in place of what the extension's script might use after it has started.
    window.reached = [];
    const apply = Reflect.apply;
    Reflect.apply = function (...given) { window.reached.push('Reflect.apply'); return Object.freeze(apply(...given)); };
    const iterate = Array.prototype[Symbol.iterator];
    Array.prototype[Symbol.iterator] = function () { if (this.length === 4 && this[0] === 'adPlacements' && this[3] === 'adBreakHeartbeatParams') { window.reached.push('its list of keys'); this.length = 0; } return iterate.call(this); };
  </script>`,
);

before(async () => {
  server = await startServer({ secure: true });
  server.page(HOST, '/watch', WATCH);
  server.page(HOST, '/hostile', HOSTILE);
  server.page(HOST, '/youtubei/v1/player', JSON.stringify(RESPONSE), { type: 'application/json' });
  server.page('blog.test', '/', `<!doctype html><body><iframe id="embed" src="${server.url(HOST, '/watch')}"></iframe></body>`);
  browser = await launch(undefined, { insecure: true });
});

after(async () => {
  await browser?.close();
  await server?.close();
});

const report = async (page) => {
  await page.waitForFunction(() => window.report?.fetched);
  return page.evaluate(() => window.report);
};
const KEPT = ['playabilityStatus', 'videoDetails'];
const ALL = Object.keys(RESPONSE).sort();

test('the player is never told of an ad: the lists are gone from its response, however the page reads it', async () => {
  const { page } = await open(browser.context, server.url(HOST, '/watch'));
  const seen = await report(page);
  assert.deepEqual(seen.initial, KEPT, 'the response written into the page');
  assert.deepEqual(seen.parsed, KEPT, 'one parsed from text');
  assert.deepEqual(seen.inside, KEPT, 'one carried inside another object');
  assert.deepEqual(seen.fetched, KEPT, 'one fetched and read as JSON');
  assert.deepEqual(seen.unrelated, { ads: [1], adPlacement: 2, list: [{ adPlacements: 'deeper down, left alone' }] }, 'nothing else is touched');
  assert.equal(seen.native, true, 'and the page\'s own functions still say what they are');
  await page.close();
});

test('EasyList\'s own YouTube filters hide a promoted tile, the supplement a slot beside the player, and a video is left', async () => {
  const { page } = await open(browser.context, server.url(HOST, '/watch'));
  await until(() => page.evaluate(() => getComputedStyle(document.getElementById('promoted')).display === 'none'), 'the promoted tile to be hidden');
  await until(() => page.evaluate(() => getComputedStyle(document.getElementById('player-ads')).display === 'none'), 'the slot beside the player to be hidden');
  assert.notEqual(await page.evaluate(() => getComputedStyle(document.getElementById('video-tile')).display), 'none');
  await page.close();
});

test('an ad that plays all the same is skipped by its button, or run out to its end with the sound off', async () => {
  const { page } = await open(browser.context, server.url(HOST, '/watch'));
  await page.waitForFunction(() => Number.isFinite(document.getElementById('video').duration));
  assert.deepEqual(await page.evaluate(() => [document.getElementById('video').currentTime, document.getElementById('video').muted]), [0, false], 'left alone while no ad shows');

  // An ad with no button: run out, muted; and the sound given back after.
  await page.evaluate(() => document.getElementById('movie_player').classList.add('ad-showing'));
  await until(() => page.evaluate(() => document.getElementById('video').currentTime >= document.getElementById('video').duration - 0.1), 'the ad to be run out');
  assert.equal(await page.evaluate(() => document.getElementById('video').muted), true);
  await page.evaluate(() => document.getElementById('movie_player').classList.remove('ad-showing'));
  await until(() => page.evaluate(() => document.getElementById('video').muted === false), 'the sound to come back');

  // An ad with a Skip button: pressed.
  await page.evaluate(() => {
    window.skipped = 0;
    const player = document.getElementById('movie_player');
    player.insertAdjacentHTML('beforeend', '<button class="ytp-skip-ad-button">Skip</button>');
    player.querySelector('button').addEventListener('click', () => {
      window.skipped++;
      player.classList.remove('ad-interrupting');
    });
    player.classList.add('ad-interrupting');
  });
  await until(() => page.evaluate(() => window.skipped >= 1), 'the Skip button to be pressed');
  await page.close();
});

test('with the YouTube switch off, or YouTube let through, the page is left as it is', async () => {
  const untouched = async () => {
    const { page } = await open(browser.context, server.url(HOST, '/watch'));
    const seen = await report(page);
    await page.evaluate(() => document.getElementById('movie_player').classList.add('ad-showing'));
    await page.waitForTimeout(500);
    const video = await page.evaluate(() => [document.getElementById('video').currentTime, document.getElementById('video').muted]);
    await page.close();
    return { seen, video };
  };

  await browser.ask({ type: 'settings:set', patch: { youtube: false } });
  let { seen, video } = await untouched();
  assert.deepEqual([seen.initial, seen.parsed, seen.fetched], [ALL, ALL, ALL]);
  assert.deepEqual(video, [0, false]);
  await browser.ask({ type: 'settings:set', patch: { youtube: true } });

  await browser.ask({ type: 'site:set', site: 'youtube.com', allowed: true });
  ({ seen, video } = await untouched());
  assert.deepEqual([seen.initial, seen.parsed, seen.fetched], [ALL, ALL, ALL]);
  assert.deepEqual(video, [0, false]);
  await browser.ask({ type: 'site:set', site: 'youtube.com', allowed: false });

  const { page } = await open(browser.context, server.url(HOST, '/watch'));
  assert.deepEqual((await report(page)).initial, KEPT, 'and at work again once switched back');
  await page.close();
});

test('the page can neither overhear the extension\'s two scripts nor tell the one in its world to stop', async () => {
  const { page } = await open(browser.context, server.url(HOST, '/hostile'));
  const seen = await report(page);
  assert.deepEqual([seen.initial, seen.parsed, seen.fetched], [KEPT, KEPT, KEPT], 'the ad lists are still taken out');
  assert.deepEqual(await page.evaluate(() => window.heard), ['stillwater:page'], 'it hears only what it said itself');
  assert.equal(await page.evaluate(() => window.unanswered), true, 'and nothing answers it');
  assert.deepEqual(await page.evaluate(() => window.reached), [], 'what it put in place of the browser\'s own was never used');
  await page.close();
});

test('a response the page has made unchangeable is given back as a copy without its ad lists', async () => {
  server.page(HOST, '/frozen', `<!doctype html><body><script>
    var ytInitialPlayerResponse = Object.freeze(${JSON.stringify(RESPONSE)});
    window.report = { initial: Object.keys(ytInitialPlayerResponse).sort(), fetched: [] };
  </script></body>`);
  const { page } = await open(browser.context, server.url(HOST, '/frozen'));
  assert.deepEqual(await page.evaluate(() => window.report.initial), KEPT);
  await page.close();
});

test('with the YouTube switch off nothing of the extension answers a page that calls for it', async () => {
  await browser.ask({ type: 'settings:set', patch: { youtube: false } });
  const { page } = await open(browser.context, server.url(HOST, '/hostile'));
  const seen = await report(page);
  assert.deepEqual([seen.initial, seen.fetched], [ALL, ALL], 'the page is as YouTube sent it');
  assert.equal(await page.evaluate(() => window.unanswered), true, 'its call goes unanswered');
  await page.waitForTimeout(300);
  assert.deepEqual(await page.evaluate(() => window.heard), ['stillwater:page'], 'and nothing is said back, then or later');
  assert.deepEqual(await browser.worker.evaluate(async () => (await chrome.scripting.getRegisteredContentScripts()).map((script) => script.id)), [], 'neither script is registered');
  await page.close();
  await browser.ask({ type: 'settings:set', patch: { youtube: true } });
  assert.deepEqual(await browser.worker.evaluate(async () => (await chrome.scripting.getRegisteredContentScripts()).map((script) => script.id).sort()), ['youtube', 'youtube-main']);
});

test('a player embedded in another site is handled there too, and left alone where that site is let through', async () => {
  let { page } = await open(browser.context, server.url('blog.test'));
  let frame = await (await page.$('#embed')).contentFrame();
  await frame.waitForFunction(() => window.report?.fetched);
  assert.deepEqual(await frame.evaluate(() => window.report.fetched), KEPT);
  await page.close();

  await browser.ask({ type: 'site:set', site: 'blog.test', allowed: true });
  ({ page } = await open(browser.context, server.url('blog.test')));
  frame = await (await page.$('#embed')).contentFrame();
  await frame.waitForFunction(() => window.report?.fetched);
  assert.deepEqual(await frame.evaluate(() => window.report.fetched), ALL, 'what arrives after the frame has asked is left alone');
  await browser.ask({ type: 'site:set', site: 'blog.test', allowed: false });
  await page.close();
});

test('after all of that, Chromium holds nothing against the extension', async (t) => {
  const held = await complaints(browser);
  if (!held) return t.skip('this Chromium has no extensions page to ask');
  assert.deepEqual(held, { state: 'ENABLED', warnings: [], manifest: [], errors: [] });
});
