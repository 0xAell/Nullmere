// Pop-up filters (`||ads.example^$popup`): not for requests, but for the
// windows and tabs a page opens. Chrome's rules can't say that, so these
// are not rules. They are built into data the service worker reads
// (src/shared/popups.js), and a tab a page opens to an address they name
// is closed.
//
//   hosts        hosts every pop-up to which is closed (`||host^$popup`)
//   patterns     [{ re, cased?, third?, on?, notOn? }] for the rest: an
//                expression for the address, and where the filter says so,
//                whether the pop-up is of another site than its opener
//                (`third`), and the sites whose pages it is for or not for
//   exceptions   the same, for `@@...$popup`

import { hostname } from './filters.js';

const unique = (list) => [...new Set(list)].sort();

/**
 * An Adblock Plus pattern as the source of a regular expression that
 * matches the same addresses: `||` a host or any subdomain of it, `|` an
 * end of the address, `^` a separator (anything but a letter, a digit or
 * `_ - . %`, or the address's end), `*` anything.
 */
export function patternSource(pattern) {
  let rest = pattern;
  let source = '';
  let end = '';
  if (rest.startsWith('||')) {
    source = '^[a-z][a-z0-9+.-]*:\\/\\/(?:[^/?#]*\\.)?';
    rest = rest.slice(2);
  } else if (rest.startsWith('|')) {
    source = '^';
    rest = rest.slice(1);
  }
  if (rest.endsWith('|')) {
    end = '$';
    rest = rest.slice(0, -1);
  }
  for (const c of rest) {
    if (c === '*') source += '.*';
    else if (c === '^') source += '(?:[^\\w.%-]|$)';
    else source += /[\w-]/.test(c) ? c : `\\${c}`;
  }
  return source + end;
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

    let source;
    if (filter.regex) {
      try {
        new RegExp(filter.pattern);
      } catch {
        drop('popup:regex');
        continue;
      }
      source = filter.pattern;
    } else if (!filter.pattern) {
      // With no address at all it has to say whose pages it is for.
      if (!conditions.on) {
        drop('popup:too-broad');
        continue;
      }
      source = '';
    } else {
      source = patternSource(filter.pattern);
    }
    const entry = { re: source, ...conditions };
    if (filter.matchCase) entry.cased = true;
    const key = JSON.stringify([filter.exception, entry]);
    count++;
    if (seen.has(key)) continue;
    seen.add(key);
    (filter.exception ? exceptions : patterns).push(entry);
  }
  return { data: { hosts: [...hosts].sort(), patterns, exceptions }, count, dropped };
}
