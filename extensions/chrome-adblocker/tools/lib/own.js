// The user's own filters, written on the options page in the lists' own
// syntax, read exactly as the build reads a list: the same parser, the
// same rules for Chrome, the same data for what pages hide. The service
// worker runs this (the build ships tools/lib/ as lib/), so a filter of
// one's own does what the same line in EasyList would.
//
// Each line not taken is said with why, by its line number.

import { buildCosmetic } from './cosmetic.js';
import { problemsWith, toRules } from './dnr.js';
import { parseLine } from './filters.js';

/** The dynamic rules of one's own filters are numbered from here, clear of the few the worker keeps (sites.js: RULE). */
export const OWN_FIRST_ID = 1000;

/** At most so many rules from one's own filters: Chrome keeps 30,000 dynamic rules, and some are the worker's. */
export const OWN_MOST_RULES = 5000;

/** At most so many letters of one's own filters kept. */
export const OWN_MOST_LETTERS = 200_000;

/** Why a filter of one's own is not taken, in words, from the reason the parser or the converter gave. */
export function whyNot(reason) {
  const said = String(reason ?? '');
  if (said === 'own:scriptlet') return "Chrome runs only the extension's own scripts, so a scriptlet of your own can't be run.";
  if (said === 'own:popup') return "Pop-up filters of your own aren't followed; the lists' are.";
  if (said === 'own:too-many') return `More than ${OWN_MOST_RULES.toLocaleString('en-US')} rules of your own: the rest are left out.`;
  if (said.startsWith('regex:')) return "Chrome can't use this regular expression.";
  if (said === 'too-broad') return 'It would match far too much: every request of its kind.';
  if (said === 'nothing-to-do') return 'It asks for nothing to be done.';
  if (said === 'cosmetic:style') return 'A filter that restyles must name its sites.';
  if (said === 'cosmetic:procedural') return "This way of picking an element isn't followed.";
  if (said.startsWith('cosmetic:scriptlet') || said === 'cosmetic:snippet') return "Chrome runs only the extension's own scripts, so this can't be run.";
  if (said === 'cosmetic:domain' || said.startsWith('option:domain')) return 'One of the sites it names is not a site Chrome can match.';
  if (said.startsWith('option:')) return `Chrome's rules can't say its option ${said.slice('option:'.length).replace(/-unknown$/, '')}.`;
  if (said.startsWith('csp:') || said.startsWith('hide-exception:')) return "Chrome's rules can't say it.";
  return "It can't be read as a filter.";
}

/**
 * Reads one's own filters. `rejectedRegex` is the regular expressions
 * Chrome has said it can't use (the worker asks it). Returns
 *   rules      the rules for Chrome, numbered from OWN_FIRST_ID
 *   cosmetic   what pages hide, as cosmetic-lookup.js reads a list
 *   selectors  every selector the filters hide, to be written apart
 *   taken      how many lines are in use
 *   refused    [{ line, text, why }] for each line not taken
 */
export function readOwn(text, { rejectedRegex = [] } = {}) {
  const network = [];
  const cosmetic = [];
  const refused = [];
  const lines = String(text ?? '').split(/\r?\n/);
  const refuse = (index, reason) => refused.push({ line: index + 1, text: lines[index].trim(), why: whyNot(reason) });

  lines.forEach((line, index) => {
    const filter = parseLine(line);
    if (filter.kind === 'blank' || filter.kind === 'comment') return;
    if (filter.kind === 'scriptlet') return refuse(index, 'own:scriptlet');
    if (filter.kind === 'popup') return refuse(index, 'own:popup');
    if (filter.kind === 'unsupported') return refuse(index, filter.reason);
    if (filter.kind === 'cosmetic') {
      if (filter.selectors.length || filter.procedural || filter.styles) cosmetic.push(filter);
      else refuse(index, 'cosmetic:malformed');
      return;
    }
    // A network filter alone first, so a line Chrome's rules can't say is
    // named by its own number; those that can are made into rules together.
    const alone = toRules([filter], { rejectedRegex });
    const why = [...alone.dropped.keys()][0];
    if (why) return refuse(index, why);
    if (alone.rules.some((rule) => problemsWith(rule).length)) return refuse(index, 'malformed');
    network.push(filter);
  });

  const { rules, hide } = toRules(network, { rejectedRegex, firstId: OWN_FIRST_ID });
  if (rules.length > OWN_MOST_RULES) {
    refused.push({ line: 0, text: '', why: whyNot('own:too-many') });
    rules.length = OWN_MOST_RULES;
  }
  const data = buildCosmetic(cosmetic, hide).data;
  const selectors = new Set([
    ...data.generic.always,
    ...data.generic.simple,
    ...Object.values(data.generic.keyed).flat(),
    ...Object.values(data.specific).flat(),
  ]);
  refused.sort((a, b) => a.line - b.line);
  return { rules, cosmetic: data, selectors, taken: network.length + cosmetic.length, refused };
}
