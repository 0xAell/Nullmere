// What the browser tests share: a Chromium with the extension loaded
// unpacked, and a local server that stands in for every site, ad host and
// tracker (Chromium is told to find every name at 127.0.0.1), recording
// which requests reached it.

import { createServer } from 'node:http';
import { mkdtempSync, rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Playwright from this package's own node_modules, or one installed for
// the whole machine (NODE_PATH), which `import` alone would not find.
const { chromium } = createRequire(import.meta.url)('playwright');

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

const GIF = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64');

/**
 * Starts the stand-in server. `hits` lists `host/path` of every request
 * that arrived. A page is given with page(host, path, html); anything else
 * is answered by its extension: a script that records itself in
 * `window.ran`, a one-pixel image, an empty style sheet, a small document.
 */
export async function startServer() {
  const hits = [];
  const pages = new Map();
  const server = createServer((request, response) => {
    const host = (request.headers.host ?? '').replace(/:\d+$/, '');
    const { pathname } = new URL(request.url, 'http://local');
    hits.push(`${host}${pathname}`);
    const page = pages.get(`${host}${pathname}`);
    const send = (type, body, headers = {}) => {
      response.writeHead(200, { 'content-type': type, 'cache-control': 'no-store', 'access-control-allow-origin': '*', ...headers });
      response.end(body);
    };
    if (page) send(page.type, page.body, page.headers);
    else if (pathname.endsWith('.js')) send('application/javascript', `(window.ran ??= []).push(${JSON.stringify(`${host}${pathname}`)});`);
    else if (/\.(gif|png|jpg|jpeg|webp)$/.test(pathname)) send('image/gif', GIF);
    else if (pathname.endsWith('.css')) send('text/css', '');
    else if (pathname.endsWith('.json')) send('application/json', '{}');
    else send('text/html', `<!doctype html><title>${host}</title><body><p>${host}${pathname}</p></body>`);
  });
  await new Promise((done) => server.listen(0, '127.0.0.1', done));
  const { port } = server.address();
  return {
    port,
    hits,
    /** The address of a path on a host, as the browser is to ask for it. */
    url: (host, path = '/') => `http://${host}:${port}${path}`,
    page(host, path, body, { type = 'text/html', headers = {} } = {}) {
      pages.set(`${host}${path}`, { type, body, headers });
    },
    reached: (host, path = '') => hits.some((hit) => hit.startsWith(`${host}${path}`)),
    forget() {
      hits.length = 0;
    },
    close: () => new Promise((done) => server.close(done)),
  };
}

/**
 * Starts Chromium with the extension in `directory` loaded unpacked.
 * Returns { context, worker, id, extensionUrl, ask, close }: `worker` is
 * the extension's service worker, `ask` sends it a message as one of the
 * extension's own pages would.
 */
export async function launch(directory = join(root, 'build')) {
  const profile = mkdtempSync(join(tmpdir(), 'stillwater-'));
  const context = await chromium.launchPersistentContext(profile, {
    // The new headless mode is the one that loads extensions; Playwright's
    // own headless shell does not.
    headless: false,
    executablePath: process.env.CHROMIUM_PATH || undefined,
    args: [
      '--headless=new',
      `--disable-extensions-except=${directory}`,
      `--load-extension=${directory}`,
      // Every name is the stand-in server.
      '--host-resolver-rules=MAP * 127.0.0.1',
      '--disable-features=HttpsUpgrades,HttpsFirstBalancedModeAutoEnable',
    ],
  });
  const worker = context.serviceWorkers()[0] ?? (await context.waitForEvent('serviceworker'));
  const id = new URL(worker.url()).host;
  const extensionUrl = (path) => `chrome-extension://${id}/${path}`;

  // A page of the extension's own to send messages from.
  const desk = await context.newPage();
  await desk.goto(extensionUrl('options/options.html'));
  const ask = (message) => desk.evaluate((sent) => chrome.runtime.sendMessage(sent), message);

  return {
    context,
    worker,
    id,
    extensionUrl,
    ask,
    async close() {
      await context.close();
      rmSync(profile, { recursive: true, force: true });
    },
  };
}

/** Opens a page and waits for it to load, noting every request that failed and why. */
export async function open(context, url) {
  const page = await context.newPage();
  const failed = [];
  page.on('requestfailed', (request) => failed.push({ url: request.url(), error: request.failure()?.errorText ?? '' }));
  await page.goto(url, { waitUntil: 'load' });
  return { page, failed, blocked: () => failed.filter((failure) => failure.error === 'net::ERR_BLOCKED_BY_CLIENT').map((failure) => failure.url) };
}

/** The id of the tab a page is in, as the extension knows it. */
export async function tabIdOf(worker, page) {
  return worker.evaluate(async (url) => (await chrome.tabs.query({})).find((tab) => tab.url === url)?.id, page.url());
}

/** Waits until `check` returns something true, or fails with `what`. */
export async function until(check, what, { timeout = 8000, every = 100 } = {}) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() > deadline) throw new Error(`Timed out waiting for ${what}`);
    await new Promise((done) => setTimeout(done, every));
  }
}
