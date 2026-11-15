#!/usr/bin/env node
// Asks a real Chromium about what only Chromium can tell: whether it takes
// each regular expression the lists' filters use (its RE2 engine refuses
// some syntax, and any expression that compiles too large), and whether it
// can read each selector. What it refuses is written to lists/rejected.json,
// which the build leaves out. Run after a refresh, with a build made:
//
//   npm run build && node tools/validate.js && npm run build
//
// The browser tests fail if rejected.json is out of date.

import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { splitSelectors } from './lib/filters.js';
import { isProcedural } from './lib/procedural.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** Every regular expression and selector a build's files hold. */
export function candidates(build = join(root, 'build')) {
  const lists = JSON.parse(readFileSync(join(build, 'lists.json'), 'utf8')).lists;
  const regex = new Map();
  const selectors = new Set();
  for (const { id } of lists) {
    for (const rule of JSON.parse(readFileSync(join(build, 'rules', `${id}.json`), 'utf8'))) {
      if (rule.condition.regexFilter !== undefined) regex.set(rule.condition.regexFilter, rule.condition.isUrlFilterCaseSensitive === true);
    }
    const data = JSON.parse(readFileSync(join(build, 'cosmetic', `${id}.json`), 'utf8'));
    for (const selector of [...data.generic.always, ...data.generic.simple]) selectors.add(selector);
    for (const group of [data.generic.keyed, data.specific, data.exceptions]) {
      // (An exception may name a worded filter, which is not a selector at all.)
      for (const list of Object.values(group)) for (const selector of list) if (!isProcedural(selector)) selectors.add(selector);
    }
    // What a restyling rule restyles is a selector too, or a list of them.
    for (const list of Object.values(data.styles)) {
      for (const rule of list) for (const selector of splitSelectors(rule.slice(0, rule.indexOf('{')))) selectors.add(selector);
    }
  }
  return { regex: [...regex].map(([source, isCaseSensitive]) => ({ source, isCaseSensitive })), selectors: [...selectors] };
}

/**
 * What a Chromium with the extension loaded refuses of a build:
 * { regex: [sources], selectors: [selectors] }. `browser` is what
 * test/e2e/harness.js: launch() returns.
 */
export async function refusedBy(browser, build = join(root, 'build')) {
  const { regex, selectors } = candidates(build);
  const badRegex = await browser.worker.evaluate(async (list) => {
    const bad = [];
    for (const { source, isCaseSensitive } of list) {
      const answer = await chrome.declarativeNetRequest.isRegexSupported({ regex: source, isCaseSensitive });
      if (!answer.isSupported) bad.push(source);
    }
    return bad;
  }, regex);
  const page = await browser.context.newPage();
  await page.goto(browser.extensionUrl('options/options.html'));
  const badSelectors = await page.evaluate((list) => list.filter((selector) => !CSS.supports(`selector(${selector})`)), selectors);
  await page.close();
  return { regex: badRegex.sort(), selectors: badSelectors.sort(), asked: { regex: regex.length, selectors: selectors.length } };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { launch } = await import('../test/e2e/harness.js');
  const browser = await launch();
  try {
    const refused = await refusedBy(browser);
    const file = join(root, 'lists', 'rejected.json');
    const before = JSON.parse(readFileSync(file, 'utf8'));
    const all = { regex: [...new Set([...before.regex, ...refused.regex])].sort(), selectors: [...new Set([...before.selectors, ...refused.selectors])].sort() };
    writeFileSync(file, `${JSON.stringify(all, null, 2)}\n`);
    console.log(`Chromium was asked about ${refused.asked.regex} regular expressions and ${refused.asked.selectors} selectors.`);
    console.log(`It refused ${refused.regex.length} and ${refused.selectors.length}; lists/rejected.json now names ${all.regex.length} and ${all.selectors.length}.`);
    for (const source of refused.regex) console.log(`  regex    ${source}`);
    for (const selector of refused.selectors.slice(0, 40)) console.log(`  selector ${selector}`);
  } finally {
    await browser.close();
  }
}
