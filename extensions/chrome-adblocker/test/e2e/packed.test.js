// The zip in dist/ is what people install. Unpacked as they would unpack
// it, it has to be an extension Chromium loads, with nothing held against
// it, that blocks and hides.

import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, before, test } from 'node:test';
import { unzip } from '../../tools/lib/zip.js';
import { zipPath } from '../../tools/package.js';
import { complaints, launch, open, startServer, until } from './harness.js';

let server;
let browser;
let folder;

before(async () => {
  folder = mkdtempSync(join(tmpdir(), 'stillwater-unpacked-'));
  for (const file of unzip(readFileSync(zipPath()))) {
    mkdirSync(dirname(join(folder, file.name)), { recursive: true });
    writeFileSync(join(folder, file.name), file.data);
  }
  server = await startServer();
  browser = await launch(folder);
});

after(async () => {
  await browser?.close();
  await server?.close();
  if (folder) rmSync(folder, { recursive: true, force: true });
});

test('the zip unpacks to an extension of the version it is named for, with its licences beside it', () => {
  const manifest = JSON.parse(readFileSync(join(folder, 'manifest.json'), 'utf8'));
  assert.equal(manifest.manifest_version, 3);
  assert.ok(zipPath().endsWith(`nullmere-stillwater-${manifest.version}.zip`));
  for (const file of ['LICENSE', 'THIRD-PARTY-NOTICES.md', 'licences/GPL-3.0.txt', 'lists.json', 'rules/easylist.json', 'cosmetic/easylist.json', 'popups/easylist.json']) {
    assert.ok(readFileSync(join(folder, file)).length > 0, file);
  }
});

test('Chromium loads it, blocks an ad host, hides a slot, and holds nothing against it', async (t) => {
  const rulesets = await browser.worker.evaluate(() => chrome.declarativeNetRequest.getEnabledRulesets());
  assert.deepEqual(rulesets.sort(), ['easylist', 'easyprivacy', 'stillwater']);

  const { generic } = JSON.parse(readFileSync(join(folder, 'cosmetic', 'easylist.json'), 'utf8'));
  const selector = generic.simple.find((item) => /^\.[a-z][\w-]*$/.test(item));
  server.page('news.test', '/', `<!doctype html><body><script src="${server.url('adnxs.com', '/tag.js')}"></script><div id="slot" class="${selector.slice(1)}">an ad</div></body>`);
  const { page, blocked } = await open(browser.context, server.url('news.test'));
  assert.equal(blocked().length, 1);
  await until(() => page.evaluate(() => getComputedStyle(document.getElementById('slot')).display === 'none'), 'the slot to be hidden');
  await page.close();

  const held = await complaints(browser);
  if (!held) return t.skip('this Chromium has no extensions page to ask');
  assert.deepEqual(held, { state: 'ENABLED', warnings: [], manifest: [], errors: [] });
});
