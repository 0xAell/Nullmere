// Takes docs/toolbar.png: Stillwater's icon and its count on Chromium's own
// toolbar, as a person sees them, not a drawing. The browser is started
// with a window, on a virtual display (Xvfb), the extension pinned beside
// the address bar, and a page opened whose ads the test list keeps back;
// the whole screen is then taken (ImageMagick's import) and the toolbar's
// end cut from it.
//
//   node tools/toolbar.js
//
// Needs Xvfb and ImageMagick, as on GitHub's Ubuntu runners.

import { execFileSync, spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { later, startServer, until } from '../test/e2e/harness.js';
import { build } from './build.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = createRequire(import.meta.url)('playwright');

// The window, at twice the pixels, as on a Mac's screen.
const [width, height, scale] = [1280, 800, 2];
const display = `:${90 + Math.floor(Math.random() * 9)}`;
const out = join(root, 'build-test');
build({ lists: join(root, 'test', 'e2e', 'lists'), out, quiet: true });

const screen = spawn('Xvfb', [display, '-screen', '0', `${width * scale}x${height * scale}x24`, '-nolisten', 'tcp'], { stdio: 'ignore' });
const profile = mkdtempSync(join(tmpdir(), 'stillwater-toolbar-'));
const server = await startServer();
const options = {
  headless: false,
  viewport: null,
  env: { ...process.env, DISPLAY: display },
  args: [
    `--disable-extensions-except=${out}`,
    `--load-extension=${out}`,
    '--host-resolver-rules=MAP * 127.0.0.1',
    '--no-proxy-server',
    '--no-first-run',
    '--window-position=0,0',
    `--window-size=${width},${height}`,
    `--force-device-scale-factor=${scale}`,
  ],
};
try {
  await new Promise((done) => setTimeout(done, 800));
  // Once to learn the extension's id, which Chromium makes from where it
  // was loaded from; then again with it pinned, as a person would pin it.
  let context = await chromium.launchPersistentContext(profile, options);
  const worker = context.serviceWorkers()[0] ?? (await context.waitForEvent('serviceworker'));
  const id = new URL(worker.url()).host;
  await context.close();
  const preferences = join(profile, 'Default', 'Preferences');
  const kept = JSON.parse(readFileSync(preferences, 'utf8'));
  kept.extensions = { ...kept.extensions, pinned_extensions: [id] };
  writeFileSync(preferences, JSON.stringify(kept));

  context = await chromium.launchPersistentContext(profile, options);
  const ads = ['/a.gif', '/b.gif', '/c.js'].map((path) => server.url('ads.test', path));
  server.page('news.test', '/', `<!doctype html><title>The Lake Gazette</title><body style="font:16px sans-serif;margin:40px"><h1>The Lake Gazette</h1><p>Morning on the water.</p>${later(ads)}</body>`);
  const page = context.pages()[0] ?? (await context.newPage());
  await page.goto(server.url('news.test', '/'));
  const sw = context.serviceWorkers()[0] ?? (await context.waitForEvent('serviceworker'));
  // Until Chrome's count on the icon is the three requests kept back.
  await until(() => sw.evaluate(async () => {
    const [tab] = await chrome.tabs.query({ active: true });
    return (await chrome.action.getBadgeText({ tabId: tab.id })) === '3';
  }), 'the count of three on the icon');
  await new Promise((done) => setTimeout(done, 500));
  const whole = join(profile, 'screen.png');
  execFileSync('import', ['-display', display, '-window', 'root', whole]);
  // The toolbar's end: the address bar's star, the icon and its count, the
  // extensions menu, the profile and Chromium's own menu.
  execFileSync('convert', [whole, '-crop', `${700 * scale}x${100 * scale}+${580 * scale}+0`, '+repage', '-strip', join(root, 'docs', 'toolbar.png')]);
  await context.close();
  console.log('docs/toolbar.png');
} finally {
  await server.close();
  screen.kill();
  rmSync(profile, { recursive: true, force: true });
}
