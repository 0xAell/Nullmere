// What the browser tests share: a Chromium with the extension loaded
// unpacked, and a local server that stands in for every site, ad host and
// tracker (Chromium is told to find every name at 127.0.0.1), recording
// which requests reached it.

import { execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { createServer as createSecureServer } from 'node:https';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Playwright from this package's own node_modules, or one installed for
// the whole machine (NODE_PATH), which `import` alone would not find.
const { chromium } = createRequire(import.meta.url)('playwright');

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

const GIF = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64');

/** A WAV file of so many seconds of silence: something for a <video> to have a length. */
function silence(seconds) {
  const rate = 8000;
  const samples = rate * seconds;
  const wav = Buffer.alloc(44 + samples, 128);
  wav.write('RIFF', 0, 'latin1');
  wav.writeUInt32LE(36 + samples, 4);
  wav.write('WAVEfmt ', 8, 'latin1');
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20); // PCM
  wav.writeUInt16LE(1, 22); // one channel
  wav.writeUInt32LE(rate, 24);
  wav.writeUInt32LE(rate, 28);
  wav.writeUInt16LE(1, 32);
  wav.writeUInt16LE(8, 34); // bits a sample
  wav.write('data', 36, 'latin1');
  wav.writeUInt32LE(samples, 40);
  return wav;
}

let made = null;

/**
 * A certificate signed by no one, made with openssl for the life of the
 * tests: some hosts (YouTube's among them) Chromium will only ask over
 * HTTPS, so their stand-in has to speak it. Chromium is told not to mind.
 */
function certificate() {
  if (made) return made;
  const directory = mkdtempSync(join(tmpdir(), 'stillwater-cert-'));
  try {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=stillwater.test', '-keyout', join(directory, 'key.pem'), '-out', join(directory, 'cert.pem')], { stdio: 'ignore' });
    made = { key: readFileSync(join(directory, 'key.pem')), cert: readFileSync(join(directory, 'cert.pem')) };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
  return made;
}

/**
 * Starts the stand-in server. `hits` lists `host/path` of every request
 * that arrived. A page is given with page(host, path, html); anything else
 * is answered by its extension: a script that records itself in
 * `window.ran`, a one-pixel image, an empty style sheet, a small document.
 */
export async function startServer({ secure = false } = {}) {
  const hits = [];
  const pages = new Map();
  const create = secure ? (handler) => createSecureServer(certificate(), handler) : createServer;
  const server = create((request, response) => {
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
    else if (pathname.endsWith('.wav')) {
      // In ranges, as a player asks for media it means to seek in.
      const sound = silence(4);
      const range = /^bytes=(\d+)-(\d*)$/.exec(request.headers.range ?? '');
      if (!range) return send('audio/wav', sound, { 'accept-ranges': 'bytes' });
      const from = Number(range[1]);
      const to = range[2] ? Math.min(Number(range[2]), sound.length - 1) : sound.length - 1;
      response.writeHead(206, { 'content-type': 'audio/wav', 'accept-ranges': 'bytes', 'content-range': `bytes ${from}-${to}/${sound.length}`, 'content-length': to - from + 1 });
      response.end(sound.subarray(from, to + 1));
    }
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
    url: (host, path = '/') => `${secure ? 'https' : 'http'}://${host}:${port}${path}`,
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
export async function launch(directory = join(root, 'build'), { insecure = false, scale = undefined } = {}) {
  const profile = mkdtempSync(join(tmpdir(), 'stillwater-'));
  const context = await chromium.launchPersistentContext(profile, {
    // The new headless mode is the one that loads extensions; Playwright's
    // own headless shell does not.
    headless: false,
    executablePath: process.env.CHROMIUM_PATH || undefined,
    deviceScaleFactor: scale,
    args: [
      '--headless=new',
      `--disable-extensions-except=${directory}`,
      `--load-extension=${directory}`,
      // Every name is the stand-in server, asked directly: nothing here
      // goes out to the network, whatever proxy the machine is set to use.
      '--host-resolver-rules=MAP * 127.0.0.1',
      '--no-proxy-server',
      '--disable-features=HttpsUpgrades,HttpsFirstBalancedModeAutoEnable',
      // For the stand-in of a host Chromium will only ask over HTTPS.
      ...(insecure ? ['--ignore-certificate-errors'] : []),
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

/**
 * Markup that asks for these addresses a moment after the page has begun,
 * as images. For tests that read Chrome's count of what was blocked:
 * Chrome starts a tab's count afresh as it finishes with a navigation, and
 * a request blocked in the page's very first instant can be counted
 * before that and lost (seen here in about one load in seven). What is
 * blocked is not in doubt, only that count.
 */
export function later(urls) {
  return `<script>setTimeout(() => { for (const url of ${JSON.stringify(urls)}) document.body.appendChild(new Image()).src = url; }, 80);</script>`;
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
