#!/usr/bin/env node
// Takes the pictures in docs/: the popup over a page with ads kept from
// it, the popup with the site let through, and the options page. They are
// the real pages of a fresh build in Chromium, not drawings.
//
//   node tools/shots.js

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { later, launch, open, startServer, tabIdOf, until } from '../test/e2e/harness.js';
import { build } from './build.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'docs');

build({ quiet: true });
const server = await startServer();
const browser = await launch(join(root, 'build'), { scale: 2 });
try {
  // A page asking for twenty-seven hosts the real lists block.
  const rules = JSON.parse(readFileSync(join(root, 'build', 'rules', 'easylist.json'), 'utf8'));
  const hosts = rules.find((rule) => rule.action.type === 'block' && rule.condition.requestDomains?.length > 1000 && !rule.condition.resourceTypes).condition.requestDomains;
  const step = Math.floor(hosts.length / 27);
  const asked = Array.from({ length: 27 }, (_, index) => server.url(hosts[index * step], '/pixel.gif'));
  server.page('news.example', '/', `<!doctype html><title>News</title><body>${later(asked)}</body>`);
  const { page } = await open(browser.context, server.url('news.example'));
  const tabId = await tabIdOf(browser.worker, page);
  await until(async () => (await browser.ask({ type: 'state', tabId })).count === asked.length, 'the count');

  const popup = await browser.context.newPage();
  const shoot = async (name) => {
    await popup.goto(browser.extensionUrl(`popup/popup.html?tab=${tabId}`));
    await popup.waitForFunction(() => document.getElementById('lake').dataset.state !== 'loading');
    // As tall as the popup is, the way Chrome shows it.
    const height = await popup.evaluate(() => document.getElementById('lake').getBoundingClientRect().height);
    await popup.setViewportSize({ width: 340, height: Math.ceil(height) });
    await popup.waitForTimeout(700);
    await popup.screenshot({ path: join(out, `${name}.png`) });
    console.log(`docs/${name}.png`);
  };
  await popup.setViewportSize({ width: 340, height: 480 });
  await shoot('popup');
  await browser.ask({ type: 'site:set', site: 'news.example', allowed: true });
  await shoot('popup-let-through');

  await browser.ask({ type: 'site:set', site: 'journal.example', allowed: true });
  const options = await browser.context.newPage();
  await options.setViewportSize({ width: 900, height: 1180 });
  await options.goto(browser.extensionUrl('options/options.html'));
  await options.waitForFunction(() => document.body.dataset.ready === 'true');
  await options.waitForTimeout(500);
  // The top of the page: the lists, the sites let through, the switches.
  await options.setViewportSize({ width: 900, height: 1180 });
  await options.screenshot({ path: join(out, 'options.png') });
  console.log('docs/options.png');
  console.log(`Chromium ${browser.context.browser()?.version() ?? ''}`);
} finally {
  await browser.close();
  await server.close();
}
