#!/usr/bin/env node
// Visits real pages on the open web, once with the built extension loaded
// and once without, and says what it made of each: requests kept back,
// ad frames left showing, whether the page still loads and runs, and on
// YouTube whether the player's response came through without its ad lists.
//
// It is not a test: the web changes under it, so a page's numbers are
// reported, not judged. It fails only where the extension itself is at
// fault: it did not load, or Chromium holds an error against it.
//
//   node tools/live-check.js [build directory]     needs the open web
//   LIVE_ONLY=YouTube node tools/live-check.js     only the pages so named
//
// The "Ad blocker, on the live web" workflow runs it from a machine that
// can reach the web, and keeps its report.

import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, appendFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { blocksHosts } from './build.js';

const { chromium } = createRequire(import.meta.url)('playwright');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** The pages visited: some that carry many ads, two that carry none, and YouTube. */
export const PAGES = [
  { name: 'The Guardian', url: 'https://www.theguardian.com/international' },
  { name: 'Speedtest', url: 'https://www.speedtest.net/' },
  { name: 'BBC', url: 'https://www.bbc.com/news' },
  { name: 'The Independent', url: 'https://www.independent.co.uk/' },
  { name: 'Stack Overflow', url: 'https://stackoverflow.com/questions/11227809/why-is-processing-a-sorted-array-faster-than-processing-an-unsorted-array' },
  { name: 'IGN', url: 'https://www.ign.com/' },
  { name: 'AccuWeather', url: 'https://www.accuweather.com/' },
  { name: 'Wikipedia (no ads)', url: 'https://en.wikipedia.org/wiki/Lake' },
  { name: 'GitHub (no ads)', url: 'https://github.com/' },
  { name: 'YouTube', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', youtube: true },
];

const AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];
const SETTLE = 6_000;

/** The hosts the built rules block whole, for counting what a page asks of them without the extension. */
function blockedHosts(directory) {
  const hosts = new Set();
  const lists = JSON.parse(readFileSync(join(directory, 'lists.json'), 'utf8')).lists;
  for (const list of lists) {
    for (const rule of JSON.parse(readFileSync(join(directory, 'rules', `${list.id}.json`), 'utf8'))) {
      if (blocksHosts(rule) && !rule.condition.initiatorDomains && !rule.condition.domainType && !rule.condition.resourceTypes) {
        for (const host of rule.condition.requestDomains) hosts.add(host);
      }
    }
  }
  return hosts;
}

function under(hosts, host) {
  for (let at = host; at; at = at.includes('.') ? at.slice(at.indexOf('.') + 1) : '') {
    if (hosts.has(at)) return true;
  }
  return false;
}

/** Chromium with the extension in `directory` loaded, or with none. */
async function start(directory) {
  const profile = mkdtempSync(join(tmpdir(), 'stillwater-live-'));
  const args = ['--headless=new', '--lang=en-GB'];
  if (directory) args.push(`--disable-extensions-except=${directory}`, `--load-extension=${directory}`);
  const context = await chromium.launchPersistentContext(profile, {
    headless: false,
    args,
    viewport: { width: 1366, height: 900 },
    locale: 'en-GB',
  });
  let worker = null;
  if (directory) worker = context.serviceWorkers()[0] ?? (await context.waitForEvent('serviceworker', { timeout: 15_000 }));
  return {
    context,
    worker,
    id: worker ? new URL(worker.url()).host : '',
    async close() {
      await context.close();
      rmSync(profile, { recursive: true, force: true });
    },
  };
}

/** What a page came to: whether it loaded, what it asked for, what was kept back, what it shows. */
async function visit(browser, page, hosts) {
  const tab = await browser.context.newPage();
  const seen = { requests: 0, toBlockedHosts: 0, blocked: 0, blockedHosts: new Map(), errors: 0, said: [] };
  tab.on('request', (request) => {
    seen.requests++;
    try {
      if (under(hosts, new URL(request.url()).hostname)) seen.toBlockedHosts++;
    } catch {
      // Not an address with a host.
    }
  });
  tab.on('requestfailed', (request) => {
    if (request.failure()?.errorText !== 'net::ERR_BLOCKED_BY_CLIENT') return;
    seen.blocked++;
    try {
      const host = new URL(request.url()).hostname;
      seen.blockedHosts.set(host, (seen.blockedHosts.get(host) ?? 0) + 1);
    } catch {
      // As above.
    }
  });
  tab.on('pageerror', (error) => {
    seen.errors++;
    if (seen.said.length < 4) seen.said.push(String(error.message ?? error).split('\n')[0].slice(0, 140));
  });
  const result = { name: page.name, url: page.url };
  try {
    const response = await tab.goto(page.url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
    result.status = response?.status() ?? 0;
    await tab.waitForLoadState('load', { timeout: 20_000 }).catch(() => {});
    await tab.waitForTimeout(SETTLE);
    result.title = (await tab.title()).slice(0, 80);
    // Frames big enough to be ad slots, as they show on the page now.
    result.frames = await tab.evaluate(() =>
      [...document.querySelectorAll('iframe')].filter((frame) => {
        const box = frame.getBoundingClientRect();
        const style = getComputedStyle(frame);
        return box.width * box.height >= 10_000 && style.display !== 'none' && style.visibility !== 'hidden';
      }).length,
    );
    result.words = await tab.evaluate(() => (document.body?.innerText ?? '').length);
    if (page.youtube) result.youtube = await youtube(tab);
    if (browser.worker) {
      const tabId = await browser.worker.evaluate(async (url) => (await chrome.tabs.query({})).find((one) => one.url === url)?.id, tab.url());
      result.badge = tabId ? Number(await browser.worker.evaluate((id) => chrome.action.getBadgeText({ tabId: id }), tabId)) || 0 : null;
    }
  } catch (error) {
    result.failed = String(error.message ?? error).split('\n')[0].slice(0, 160);
  }
  Object.assign(result, { requests: seen.requests, toBlockedHosts: seen.toBlockedHosts, blocked: seen.blocked, errors: seen.errors, said: seen.said });
  result.topBlocked = [...seen.blockedHosts].sort((a, b) => b[1] - a[1]).slice(0, 6).map(([host, count]) => `${host} ${count}`);
  await Promise.race([tab.close(), new Promise((done) => setTimeout(done, 5_000))]);
  // As it goes, so that a run cut short still says what it saw.
  console.error(`${browser.worker ? 'with' : 'without'}  ${JSON.stringify(result)}`);
  return result;
}

/** On a YouTube watch page: what the player was told, and whether an ad showed. */
async function youtube(tab) {
  await tab.waitForFunction(() => window.ytInitialPlayerResponse || document.querySelector('#movie_player'), null, { timeout: 15_000 }).catch(() => {});
  const told = await tab.evaluate((keys) => {
    const response = window.ytInitialPlayerResponse;
    // Whether the page as sent carried a player response at all: a page that
    // asks to be signed in, or for consent, carries none.
    const written = [...document.scripts].some((script) => script.text.includes('ytInitialPlayerResponse'));
    if (!response || typeof response !== 'object') return { response: false, written };
    return {
      response: true,
      playable: response.playabilityStatus?.status ?? null,
      adKeys: keys.filter((key) => key in response),
      title: response.videoDetails?.title ?? null,
      written,
    };
  }, AD_KEYS);
  // Ten seconds of the player, looking for an ad showing in it.
  let adShowing = false;
  for (let i = 0; i < 20 && !adShowing; i++) {
    adShowing = await tab.evaluate(() => Boolean(document.querySelector('#movie_player.ad-showing, #movie_player.ad-interrupting')));
    if (!adShowing) await tab.waitForTimeout(500);
  }
  const player = await tab.evaluate(() => {
    const video = document.querySelector('#movie_player video');
    return { player: Boolean(document.querySelector('#movie_player')), video: Boolean(video), playing: video ? video.currentTime > 0 || !video.paused : false };
  });
  return { ...told, adShowing, ...player };
}

/** What Chromium holds against the extension, from its extensions page; null where it can't be asked. */
async function complaints(browser) {
  const tab = await browser.context.newPage();
  try {
    await tab.goto('chrome://extensions/');
    const info = await tab.evaluate((id) => (chrome.developerPrivate?.getExtensionInfo ? new Promise((done) => chrome.developerPrivate.getExtensionInfo(id, done)) : null), browser.id);
    if (!info) return null;
    const words = (list) => (list ?? []).map((item) => item.message ?? String(item));
    return { state: info.state, warnings: words(info.installWarnings), manifest: words(info.manifestErrors), errors: words(info.runtimeErrors) };
  } catch {
    return null;
  } finally {
    await tab.close();
  }
}

function table(withExtension, without) {
  const rows = [
    '| Page | Loaded with / without | Letters of text with / without | Requests with / without | To hosts the lists block, without | Kept back | Count on the icon | Ad-sized frames with / without | Page errors with / without |',
    '|---|---|---|---|---|---|---|---|---|',
  ];
  for (const [index, one] of withExtension.entries()) {
    const other = without[index];
    const loaded = (visit) => (visit.failed ? `no (${visit.failed})` : `${visit.status}`);
    rows.push(`| ${one.name} | ${loaded(one)} / ${loaded(other)} | ${one.words ?? '-'} / ${other.words ?? '-'} | ${one.requests} / ${other.requests} | ${other.toBlockedHosts} | ${one.blocked} | ${one.badge ?? '-'} | ${one.frames ?? '-'} / ${other.frames ?? '-'} | ${one.errors} / ${other.errors} |`);
  }
  return rows.join('\n');
}

/** Where a page threw more errors with the extension than without: what they said, and its title both ways. */
function errorWords(withExtension, without) {
  const lines = [];
  for (const [index, one] of withExtension.entries()) {
    const other = without[index];
    if (one.errors <= other.errors) continue;
    lines.push(`- ${one.name} ("${one.title ?? ''}" with, "${other.title ?? ''}" without): ${one.said.map((words) => `\`${words.replaceAll('`', "'")}\``).join('; ')}`);
  }
  return lines.length ? `Pages that threw more errors with the extension than without:\n\n${lines.join('\n')}` : 'No page threw more errors with the extension than without it.';
}

function youtubeWords(one, other) {
  if (!one.youtube || !other.youtube) return 'YouTube: the watch page did not load in one of the two runs.';
  const say = (run) =>
    run.response
      ? `the player's response came through (${run.playable ?? 'no status'}), with ${run.adKeys.length ? `its ad lists: ${run.adKeys.join(', ')}` : 'no ad lists in it'}; an ad ${run.adShowing ? 'showed' : 'did not show'} in ten seconds; video ${run.video ? (run.playing ? 'playing' : 'present, not playing') : 'absent'}`
      : `no player response was found on the page (${run.written ? 'though the page as sent had one' : 'nor in the page as sent'}; player ${run.player ? 'present' : 'absent'})`;
  return `YouTube, without the extension: ${say(other)}; titled "${other.title ?? ''}".\n\nYouTube, with it: ${say(one)}; titled "${one.title ?? ''}".`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const directory = resolve(process.argv[2] ?? join(root, 'build'));
  if (!existsSync(join(directory, 'manifest.json'))) {
    console.error(`${directory} has no manifest.json. Run: npm run build`);
    process.exit(1);
  }
  // LIVE_ONLY=YouTube,CNN visits only the pages whose names begin so.
  const only = (process.env.LIVE_ONLY ?? '').split(',').map((name) => name.trim().toLowerCase()).filter(Boolean);
  const pages = only.length ? PAGES.filter((page) => only.some((name) => page.name.toLowerCase().startsWith(name))) : PAGES;
  const hosts = blockedHosts(directory);
  const withExtension = [];
  const without = [];
  let held = null;
  let version = '';

  const plain = await start(null);
  try {
    version = plain.context.browser()?.version() ?? '';
    for (const page of pages) without.push(await visit(plain, page, hosts));
  } finally {
    await plain.close();
  }
  const loaded = await start(directory);
  try {
    for (const page of pages) withExtension.push(await visit(loaded, page, hosts));
    held = await complaints(loaded);
  } finally {
    await loaded.close();
  }

  const day = new Date().toISOString().slice(0, 10);
  const report = [
    `## Stillwater on the live web, ${day}`,
    '',
    `Chromium ${version || '(version not reported)'}, headless, ${process.env.GITHUB_ACTIONS ? 'from a GitHub runner' : 'from the machine it was run on'}. Each page was loaded once without the extension and once with it, and given ${SETTLE / 1000} seconds after loading.`,
    '',
    table(withExtension, without),
    '',
    errorWords(withExtension, without),
    '',
    youtubeWords(withExtension.find((one) => one.youtube) ?? {}, without.find((one) => one.youtube) ?? {}),
    '',
    `Most kept back, by host: ${withExtension.filter((one) => one.topBlocked.length).map((one) => `${one.name}: ${one.topBlocked.join(', ')}`).join('; ') || 'nothing'}.`,
    '',
    `What Chromium holds against the extension: ${held ? JSON.stringify(held) : 'not asked (no extensions page)'}.`,
  ].join('\n');
  console.log(report);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${report}\n`);
  writeFileSync(join(root, 'live-report.json'), `${JSON.stringify({ day, version, withExtension, without, held }, null, 2)}\n`);

  const faults = !held ? [] : [...held.warnings, ...held.manifest, ...held.errors];
  if (held && held.state !== 'ENABLED') faults.push(`state ${held.state}`);
  if (faults.length) {
    console.error(`The extension is at fault:\n  ${faults.join('\n  ')}`);
    process.exit(1);
  }
}
