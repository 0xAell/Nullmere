#!/usr/bin/env node
// Builds the extension as Chrome loads it: src/ copied as it is, and beside
// it the rules and cosmetic data made from the filter lists in lists/.
//
//   node tools/build.js                          lists/ -> build/
//   node tools/build.js --lists <dir> --out <dir>
//
// The same lists always build the same files, byte for byte.

import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildCosmetic } from './lib/cosmetic.js';
import { problemsWith, toRules } from './lib/dnr.js';
import { parseList, splitSelectors } from './lib/filters.js';
import { buildPopups } from './lib/popups.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** Chrome's limits that a build is held to (declarativeNetRequest, Chrome 121 and later). */
export const LIMITS = {
  /** Static rules Chrome guarantees an extension, whatever else is installed. */
  guaranteedRules: 30_000,
  /** Regular-expression rules across all enabled static rulesets. */
  regexRules: 1_000,
};

/** The extension's own list, built beside those lists/sources.json names. */
const OWN = { id: 'stillwater', title: 'Stillwater supplement', file: 'stillwater.txt', homepage: 'https://github.com/ael-dev3/Nullmere/tree/main/extensions/chrome-adblocker' };

const count = (map) => Object.fromEntries([...map].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])));

/** Whether a rule blocks every request to the hosts it names. */
export function blocksHosts(rule) {
  const { condition } = rule;
  return rule.action.type === 'block' && Boolean(condition.requestDomains) && !condition.urlFilter && !condition.regexFilter;
}

/**
 * Builds into `out` from the lists in `lists`. Returns what was built:
 * { lists: [{ id, title, filters, rules, regexRules, cosmetic, dropped }], totals }.
 */
export function build({ lists = join(root, 'lists'), out = join(root, 'build'), quiet = false } = {}) {
  const sources = JSON.parse(readFileSync(join(lists, 'sources.json'), 'utf8'));
  const rejected = existsSync(join(lists, 'rejected.json')) ? JSON.parse(readFileSync(join(lists, 'rejected.json'), 'utf8')) : { regex: [], selectors: [] };
  const rejectedSelectors = new Set(rejected.selectors);

  rmSync(out, { recursive: true, force: true });
  mkdirSync(join(out, 'rules'), { recursive: true });
  mkdirSync(join(out, 'cosmetic'), { recursive: true });
  mkdirSync(join(out, 'popups'), { recursive: true });
  cpSync(join(root, 'src'), out, { recursive: true });
  for (const file of ['THIRD-PARTY-NOTICES.md', 'licences']) {
    if (existsSync(join(root, file))) cpSync(join(root, file), join(out, file), { recursive: true });
  }
  // Nullmere's own licence, from the root of the repository.
  const licence = join(root, '..', '..', 'LICENSE');
  if (existsSync(licence)) cpSync(licence, join(out, 'LICENSE'));

  const built = [];
  for (const list of [...sources.lists, OWN]) {
    const parsed = parseList(readFileSync(join(lists, list.file), 'utf8'));
    const { rules, hide, dropped } = toRules(parsed.network, { rejectedRegex: rejected.regex });
    for (const rule of rules) {
      const problems = problemsWith(rule);
      if (problems.length) throw new Error(`${list.id}: rule ${rule.id} is not one Chrome takes (${problems.join('; ')}): ${JSON.stringify(rule)}`);
      // A stand-in a rule gives is one the build holds.
      const path = rule.action.redirect?.extensionPath;
      if (path && !existsSync(join(out, path))) throw new Error(`${list.id}: rule ${rule.id} gives ${path}, which the build has not got`);
    }
    for (const [reason, n] of parsed.dropped) dropped.set(reason, (dropped.get(reason) ?? 0) + n);

    let refused = 0;
    for (const filter of parsed.cosmetic) {
      const kept = filter.selectors.filter((selector) => !rejectedSelectors.has(selector));
      refused += filter.selectors.length - kept.length;
      filter.selectors = kept;
      if (filter.styles) {
        const styles = filter.styles.filter((rule) => !splitSelectors(rule.slice(0, rule.indexOf('{'))).some((selector) => rejectedSelectors.has(selector)));
        refused += filter.styles.length - styles.length;
        filter.styles = styles.length ? styles : undefined;
      }
    }
    if (refused) dropped.set('cosmetic:rejected-by-chrome', refused);
    const cosmetic = buildCosmetic(parsed.cosmetic.filter((filter) => filter.selectors.length || filter.procedural || filter.styles), hide);

    const popups = buildPopups(parsed.popups);
    for (const [reason, n] of popups.dropped) dropped.set(reason, (dropped.get(reason) ?? 0) + n);

    // One rule to a line: a rule can be found, and a refresh compared.
    writeFileSync(join(out, 'rules', `${list.id}.json`), `[\n${rules.map((rule) => JSON.stringify(rule)).join(',\n')}\n]\n`);
    writeFileSync(join(out, 'cosmetic', `${list.id}.json`), `${JSON.stringify(cosmetic.data)}\n`);
    writeFileSync(join(out, 'popups', `${list.id}.json`), `${JSON.stringify(popups.data)}\n`);
    built.push({
      id: list.id,
      title: list.title,
      homepage: list.homepage,
      filters: parsed.lines,
      rules: rules.length,
      regexRules: rules.filter((rule) => rule.condition.regexFilter !== undefined).length,
      // Hosts blocked whole: not those an exception or a policy names.
      hosts: rules.reduce((sum, rule) => sum + (blocksHosts(rule) ? rule.condition.requestDomains.length : 0), 0),
      cosmetic: cosmetic.counts.generic + cosmetic.counts.specific + cosmetic.counts.procedural + cosmetic.counts.styles,
      procedural: cosmetic.counts.procedural,
      popups: popups.count,
      standIns: parsed.network.filter((filter) => filter.redirect).length,
      dropped: count(dropped),
    });
  }

  const totals = {
    filters: built.reduce((sum, list) => sum + list.filters, 0),
    rules: built.reduce((sum, list) => sum + list.rules, 0),
    regexRules: built.reduce((sum, list) => sum + list.regexRules, 0),
    cosmetic: built.reduce((sum, list) => sum + list.cosmetic, 0),
    popups: built.reduce((sum, list) => sum + list.popups, 0),
    standIns: built.reduce((sum, list) => sum + list.standIns, 0),
  };
  if (totals.regexRules > LIMITS.regexRules) throw new Error(`${totals.regexRules} regular-expression rules: Chrome takes ${LIMITS.regexRules}`);

  const manifest = JSON.parse(readFileSync(join(out, 'manifest.json'), 'utf8'));
  const declared = (manifest.declarative_net_request?.rule_resources ?? []).map((resource) => resource.path).sort();
  const made = built.map((list) => `rules/${list.id}.json`).sort();
  if (JSON.stringify(declared) !== JSON.stringify(made)) throw new Error(`manifest.json declares ${declared.join(', ')} but the lists build ${made.join(', ')}`);

  const summary = {
    source: { repository: sources.repository, commit: sources.commit, committed: sources.committed, licence: sources.licence },
    limits: LIMITS,
    totals,
    lists: built,
  };
  writeFileSync(join(out, 'lists.json'), `${JSON.stringify(summary, null, 2)}\n`);

  if (!quiet) {
    for (const list of built) {
      console.log(`${list.title}: ${list.filters} filters -> ${list.rules} rules (${list.hosts} hosts, ${list.regexRules} regular expressions), ${list.cosmetic} selectors, ${list.popups} pop-up filters`);
      for (const [reason, n] of Object.entries(list.dropped)) console.log(`    not converted: ${n} ${reason}`);
    }
    console.log(`In all ${totals.rules} rules of the ${LIMITS.guaranteedRules} Chrome guarantees, ${totals.regexRules} regular expressions of ${LIMITS.regexRules}.`);
    if (totals.rules > LIMITS.guaranteedRules) console.log('More rules than Chrome guarantees: some rulesets may not be enabled where other extensions have used the shared allowance.');
    console.log(`Built ${out}`);
  }
  return summary;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const argument = (name, otherwise) => {
    const at = process.argv.indexOf(name);
    return at === -1 ? otherwise : resolve(process.argv[at + 1]);
  };
  build({ lists: argument('--lists', join(root, 'lists')), out: argument('--out', join(root, 'build')) });
}
