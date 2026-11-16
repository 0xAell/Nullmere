// Pop-up filters (`||ads.example^$popup`): not for requests, but for the
// windows and tabs a page opens. Chrome's rules can't say that, so these
// are not rules. They are built into data the service worker reads
// (src/shared/popups.js), and a tab a page opens to an address they name
// is closed.
//
//   hosts        hosts every pop-up to which is closed (`||host^$popup`)
//   patterns     [{ pattern | re, cased?, third?, on?, notOn? }] for the
//                rest: the filter's address pattern as it is written (or a
//                list's own regular expression), and where it says so,
//                whether the pop-up is of another site than its opener
//                (`third`), and the sites whose pages it is for or not for
//   exceptions   the same, for `@@...$popup`

import { patternMatcher } from '../../src/shared/patterns.js';
import { hostname } from './filters.js';

const unique = (list) => [...new Set(list)].sort();

/** Addresses with nothing of an ad about them: a filter that matches them all matches anything. */
const ORDINARY = ['https://example.com/', 'http://news.example.org/story/42', 'https://www.shop.example/basket?item=7#top'];

/** Whether an entry's address test passes every address there is, as far as a few ordinary ones can tell. */
function matchesAnything(entry) {
  const test = typeof entry.pattern === 'string' ? patternMatcher(entry.pattern, entry.cased) : (url) => new RegExp(entry.re, entry.cased ? '' : 'i').test(url);
  return ORDINARY.every(test);
}

/**
 * Builds the pop-up data from parsed filters that are for pop-ups.
 * Returns { data, count, dropped }: `count` filters taken, and a Map of
 * reason to how many could not be.
 */
export function buildPopups(filters) {
  const hosts = new Set();
  const patterns = [];
  const exceptions = [];
  const seen = new Set();
  const dropped = new Map();
  const drop = (reason) => dropped.set(reason, (dropped.get(reason) ?? 0) + 1);
  let count = 0;

  for (const filter of filters) {
    // Nothing a pop-up has: it is an address a page opens, not a request with a method or a host asked of.
    if (filter.to || filter.methods) {
      drop('popup:option');
      continue;
    }
    const conditions = {};
    if (filter.thirdParty !== null) conditions.third = filter.thirdParty;
    if (filter.domains?.include.length) conditions.on = unique(filter.domains.include);
    if (filter.domains?.exclude.length) conditions.notOn = unique(filter.domains.exclude);

    const whole = !filter.regex && !filter.matchCase ? /^\|\|([^/^*|:?=&]+)\^$/.exec(filter.pattern) : null;
    const host = whole ? hostname(whole[1]) : '';
    if (!filter.exception && host && Object.keys(conditions).length === 0) {
      hosts.add(host);
      count++;
      continue;
    }

    let address;
    if (filter.regex) {
      try {
        new RegExp(filter.pattern);
      } catch {
        drop('popup:regex');
        continue;
      }
      address = { re: filter.pattern };
    } else if (!filter.pattern) {
      // With no address at all it has to say whose pages it is for.
      if (!conditions.on) {
        drop('popup:too-broad');
        continue;
      }
      address = { pattern: '' };
    } else {
      address = { pattern: filter.pattern };
    }
    const entry = { ...address, ...conditions };
    if (filter.matchCase) entry.cased = true;
    // One that would close every tab a page opens, whatever the page, is
    // not taken on a list's word: it has to say whose pages it is for.
    if (!filter.exception && !conditions.on && matchesAnything(entry)) {
      drop('popup:too-broad');
      continue;
    }
    const key = JSON.stringify([filter.exception, entry]);
    count++;
    if (seen.has(key)) continue;
    seen.add(key);
    (filter.exception ? exceptions : patterns).push(entry);
  }
  return { data: { hosts: [...hosts].sort(), patterns, exceptions }, count, dropped };
}
