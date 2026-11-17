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
  // Sites a scriptlet is for: what the page reads of what it fixes, with
  // the extension and without ("probe", run in the page's own world).
  { name: 'USA Today', url: 'https://www.usatoday.com/', probe: () => `admiral: ${typeof window.admiral === 'function' ? `a function of ${window.admiral.length} arguments` : typeof window.admiral}; gnt.x.adm: ${JSON.stringify(window.gnt?.x?.adm) ?? 'undefined'}` },
  { name: 'TechCrunch', url: 'https://techcrunch.com/', probe: () => `admiral: ${typeof window.admiral}; Admiral's scripts: ${[...document.scripts].filter((script) => /admiral|getadmiral/i.test(script.src + script.textContent.slice(0, 2000))).length}` },
  { name: 'Wikipedia (no ads)', url: 'https://en.wikipedia.org/wiki/Lake' },
  { name: 'GitHub (no ads)', url: 'https://github.com/' },
  { name: 'YouTube', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', youtube: true },
  // Two of the most watched music videos, where an advertiser's ad before the video is likeliest.
  { name: 'YouTube, a music video', url: 'https://www.youtube.com/watch?v=kJQP7kiw5Fk', youtube: true },
  { name: 'YouTube, another music video', url: 'https://www.youtube.com/watch?v=JGwWNGJdvx8', youtube: true },
  { name: 'YouTube, embedded', url: 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=1&mute=1', youtube: true },
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

/**
 * The browser: Playwright's Chromium, or with STILLWATER_CHROME=1 Google
 * Chrome as installed (its codecs those of the Chrome people use, which
 * Chromium lacks), handed the extension over the DevTools protocol, as it
 * takes none named on its command line. LIVE_HEADED=1 shows its windows,
 * on whatever display there is (a virtual one on a runner), not headless.
 */
export const inChrome = process.env.STILLWATER_CHROME === '1';
const headed = process.env.LIVE_HEADED === '1';

/** The browser with the extension in `directory` loaded, or with none. */
async function start(directory) {
  const profile = mkdtempSync(join(tmpdir(), 'stillwater-live-'));
  // Videos may start without a click, as on a page a person has pressed play on: the same with the extension and without.
  const args = [...(headed ? [] : ['--headless=new']), '--lang=en-GB', '--autoplay-policy=no-user-gesture-required'];
  if (directory && inChrome) args.push('--enable-unsafe-extension-debugging');
  else if (directory) args.push(`--disable-extensions-except=${directory}`, `--load-extension=${directory}`);
  const context = await chromium.launchPersistentContext(profile, {
    headless: false,
    channel: inChrome ? 'chrome' : undefined,
    ignoreDefaultArgs: inChrome ? ['--disable-extensions'] : undefined,
    args,
    viewport: { width: 1366, height: 900 },
    locale: 'en-GB',
  });
  let worker = null;
  if (directory) {
    const handed = inChrome ? (await (await context.browser().newBrowserCDPSession()).send('Extensions.loadUnpacked', { path: directory })).id : null;
    const ours = (candidate) => !handed || new URL(candidate.url()).host === handed;
    worker = context.serviceWorkers().find(ours) ?? (await context.waitForEvent('serviceworker', { predicate: ours, timeout: 15_000 }));
  }
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
  const seen = { requests: 0, toBlockedHosts: 0, blocked: 0, blockedHosts: new Map(), blockedFirstParty: [], errors: 0, said: [] };
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
      const address = new URL(request.url());
      const host = address.hostname;
      seen.blockedHosts.set(host, (seen.blockedHosts.get(host) ?? 0) + 1);
      // What was kept back from the site's own hosts: where a filter might have taken too much.
      const site = new URL(page.url).hostname.split('.').slice(-2).join('.');
      if (host === site || host.endsWith(`.${site}`)) {
        if (seen.blockedFirstParty.length < 5) seen.blockedFirstParty.push(`${host}${address.pathname}`.slice(0, 120));
      }
    } catch {
      // As above.
    }
  });
  if (page.youtube) {
    tab.on('response', (response) => {
      if (!response.url().includes('/youtubei/v1/player')) return;
      response
        .json()
        .then((json) => {
          seen.fetchedAdKeys = AD_KEYS.filter((key) => key in json);
          seen.fetched = true;
        })
        .catch(() => {});
    });
  }
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
    // Frames big enough to be ad slots, as they show on the page now, and where each is from.
    const shown = await tab.evaluate(() =>
      [...document.querySelectorAll('iframe')]
        .filter((frame) => {
          const box = frame.getBoundingClientRect();
          const style = getComputedStyle(frame);
          return box.width * box.height >= 10_000 && style.display !== 'none' && style.visibility !== 'hidden';
        })
        .map((frame) => {
          try {
            return frame.src ? new URL(frame.src).hostname || frame.src.slice(0, 20) : '(no address)';
          } catch {
            return '(no address)';
          }
        }),
    );
    result.frames = shown.length;
    result.frameHosts = shown;
    result.words = await tab.evaluate(() => (document.body?.innerText ?? '').length);
    // The page's lines of text, to say which a page lost with the extension.
    result.lines = await tab.evaluate(() => [...new Set((document.body?.innerText ?? '').split('\n').map((line) => line.trim()).filter((line) => line.length >= 4 && line.length <= 90))].slice(0, 800));
    if (page.probe) result.probe = await tab.evaluate(page.probe).catch((error) => `(${String(error.message ?? error).slice(0, 60)})`);
    if (page.youtube) {
      result.youtube = await youtube(tab);
      // What YouTube sent when the player asked for its data, as it came over the wire:
      // the extension changes what the page reads, not what is sent.
      result.youtube.fetched = Boolean(seen.fetched);
      result.youtube.fetchedAdKeys = seen.fetchedAdKeys ?? [];
    }
    if (browser.worker) {
      const tabId = await browser.worker.evaluate(async (url) => (await chrome.tabs.query({})).find((one) => one.url === url)?.id, tab.url());
      result.badge = tabId ? Number(await browser.worker.evaluate((id) => chrome.action.getBadgeText({ tabId: id }), tabId)) || 0 : null;
    }
  } catch (error) {
    result.failed = String(error.message ?? error).split('\n')[0].slice(0, 160);
  }
  Object.assign(result, { requests: seen.requests, toBlockedHosts: seen.toBlockedHosts, blocked: seen.blocked, errors: seen.errors, said: seen.said, ownKeptBack: seen.blockedFirstParty });
  result.topBlocked = [...seen.blockedHosts].sort((a, b) => b[1] - a[1]).slice(0, 6).map(([host, count]) => `${host} ${count}`);
  await Promise.race([tab.close(), new Promise((done) => setTimeout(done, 5_000))]);
  // As it goes, so that a run cut short still says what it saw.
  const { lines, ...said } = result;
  console.error(`${browser.worker ? 'with' : 'without'}  ${JSON.stringify(said)}`);
  return result;
}

/** On a YouTube watch page: what the player was told, and whether an ad showed. */
export async function youtube(tab) {
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
  // Press play, muted, as a person would; then fifteen seconds of the
  // player, looking for an ad showing in it and for the video going on.
  await tab
    .evaluate(() => {
      const player = document.getElementById('movie_player');
      player?.mute?.();
      const video = document.querySelector('#movie_player video');
      if (video) video.muted = true;
      player?.playVideo?.();
    })
    .catch(() => {});
  let adShowing = false;
  for (let i = 0; i < 30; i++) {
    adShowing ||= await tab.evaluate(() => Boolean(document.querySelector('#movie_player.ad-showing, #movie_player.ad-interrupting'))).catch(() => false);
    await tab.waitForTimeout(500);
  }
  const player = await tab.evaluate(() => {
    const element = document.getElementById('movie_player');
    const video = document.querySelector('#movie_player video');
    const own = element?.getCurrentTime?.();
    return {
      player: Boolean(element),
      video: Boolean(video),
      playing: video ? !video.paused && !element.classList.contains('ad-showing') : false,
      // How far into the video itself the player says it is: an ad's time is not counted.
      seconds: typeof own === 'number' ? Math.round(own * 10) / 10 : null,
    };
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
/**
 * For each page with a twentieth less text with the extension than without,
 * the lines it had without and not with: an ad's words, or the page's own.
 */
export function lostWords(withExtension, without) {
  const lines = [];
  for (const one of withExtension) {
    const other = without.find((page) => page.name === one.name);
    if (!other?.lines || !one.lines || !(one.words < other.words * 0.95)) continue;
    const kept = new Set(one.lines);
    const lost = other.lines.filter((line) => !kept.has(line));
    lines.push(`- ${one.name}, ${other.words - one.words} fewer letters; ${lost.length} lines not seen with it${lost.length ? `: ${lost.slice(0, 15).map((line) => `"${line.replaceAll('"', "'")}"`).join(', ')}${lost.length > 15 ? ', ...' : ''}` : ''}`);
  }
  return lines.length ? `Pages with a twentieth less text with the extension, and the lines they had without it:\n\n${lines.join('\n')}` : 'No page had a twentieth less text with the extension.';
}

function errorWords(withExtension, without) {
  const lines = [];
  for (const [index, one] of withExtension.entries()) {
    const other = without[index];
    if (one.errors <= other.errors) continue;
    lines.push(`- ${one.name} ("${one.title ?? ''}" with, "${other.title ?? ''}" without): ${one.said.map((words) => `\`${words.replaceAll('`', "'")}\``).join('; ')}`);
  }
  return lines.length ? `Pages that threw more errors with the extension than without:\n\n${lines.join('\n')}` : 'No page threw more errors with the extension than without it.';
}

/** What the YouTube page was told and did, without the extension and with it, in words. */
export function youtubeWords(one, other) {
  if (!one?.youtube || !other?.youtube) return `${one?.name ?? 'YouTube'}: the page did not load in one of the two runs.`;
  const video = (run) => (run.video ? (run.playing ? `playing${run.seconds !== null && run.seconds !== undefined ? `, ${run.seconds} seconds in` : ''}` : 'present, not playing') : 'absent');
  const say = (run) =>
    run.response
      ? `the player's response came through (${run.playable ?? 'no status'}), with ${run.adKeys.length ? `its ad lists: ${run.adKeys.join(', ')}` : 'no ad lists in it'}; an ad ${run.adShowing ? 'showed' : 'did not show'} in fifteen seconds; video ${video(run)}`
      : `no player response was found on the page (${run.written ? 'though the page as sent had one' : 'nor in the page as sent'}; player ${run.player ? 'present' : 'absent'}); an ad ${run.adShowing ? 'showed' : 'did not show'} in fifteen seconds; video ${video(run)}`;
  const wire = (run) => (run.fetched ? `the player fetched its data, which came ${run.fetchedAdKeys.length ? `with ad lists (${run.fetchedAdKeys.join(', ')})` : 'with no ad lists'}` : 'the player fetched no data');
  // What was found is in each run's `youtube`; the page's own title beside it.
  return `${one.name}, without the extension: ${say(other.youtube)}; ${wire(other.youtube)}; titled "${other.title ?? ''}".\n\n${one.name}, with it: ${say(one.youtube)}; ${wire(one.youtube)}; titled "${one.title ?? ''}".`;
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
    `${inChrome ? 'Google Chrome' : 'Chromium'} ${version || '(version not reported)'}, ${headed ? 'its windows shown on a virtual display' : 'headless'}, ${process.env.GITHUB_ACTIONS ? 'from a GitHub runner' : 'from the machine it was run on'}. Each page was loaded once without the extension and once with it, and given ${SETTLE / 1000} seconds after loading.`,
    '',
    table(withExtension, without),
    '',
    errorWords(withExtension, without),
    '',
    lostWords(withExtension, without),
    '',
    ...withExtension.flatMap((one, index) => (one.youtube !== undefined || PAGES.find((page) => page.name === one.name)?.youtube ? [youtubeWords(one, without[index]), ''] : [])),
    '',
    `What the pages a scriptlet is for read of what it fixes, without and with the extension: ${withExtension.filter((one) => one.probe !== undefined).map((one, index) => `${one.name}: ${without.find((other) => other.name === one.name)?.probe ?? '(not reached)'} → ${one.probe}`).join('; ') || 'none reached'}.`,
    '',
    `Most kept back, by host: ${withExtension.filter((one) => one.topBlocked.length).map((one) => `${one.name}: ${one.topBlocked.join(', ')}`).join('; ') || 'nothing'}.`,
    '',
    `Ad-sized frames still showing with the extension, by where they are from: ${withExtension.filter((one) => one.frames).map((one) => `${one.name}: ${one.frameHosts.join(', ')}`).join('; ') || 'none'}.`,
    '',
    `Kept back from a site's own hosts (where a filter might take too much): ${withExtension.filter((one) => one.ownKeptBack.length).map((one) => `${one.name}: ${one.ownKeptBack.map((url) => `\`${url}\``).join(', ')}`).join('; ') || 'nothing'}.`,
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
