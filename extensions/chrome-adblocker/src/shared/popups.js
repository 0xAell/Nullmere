// Decides whether a tab a page has opened is a pop-up the lists name, from
// the data tools/lib/popups.js builds. No Chrome API is used here, so the
// same code runs in the service worker and under the unit tests.

import { covers, suffixLength } from './cosmetic-lookup.js';
import { patternMatcher } from './patterns.js';

/** The site a host belongs to, as far as can be told without the suffix list: `shop.example.co.uk` is `example.co.uk`. */
export function siteName(host) {
  const name = String(host ?? '').toLowerCase();
  // An address in numbers is its own site.
  if (/^[\d.]+$/.test(name) || name.includes(':')) return name;
  const labels = name.split('.').filter(Boolean);
  return labels.slice(-(suffixLength(labels) + 1)).join('.');
}

/**
 * The most of an address a list's own regular expression is tried on.
 * Patterns are matched in time that grows only with the address
 * (patterns.js), but a regular expression a list writes could take far
 * longer on an address a page builds for it; a few lists write any, and
 * those test the start of an address.
 */
export const LONGEST = 4096;

export class Popups {
  /** `lists`: the pop-up data of each enabled list. An exception in one holds against them all. */
  constructor(lists) {
    this.hosts = new Set();
    this.patterns = [];
    this.exceptions = [];
    const compiled = (entry) => {
      const sites = { on: entry.on && new Set(entry.on), notOn: entry.notOn && new Set(entry.notOn) };
      if (typeof entry.pattern === 'string') return { ...entry, ...sites, test: patternMatcher(entry.pattern, entry.cased) };
      try {
        const expression = new RegExp(entry.re, entry.cased ? '' : 'i');
        return { ...entry, ...sites, test: (url) => expression.test(url.length > LONGEST ? url.slice(0, LONGEST) : url) };
      } catch {
        return null;
      }
    };
    for (const list of lists) {
      for (const host of list.hosts ?? []) this.hosts.add(host);
      this.patterns.push(...(list.patterns ?? []).map(compiled).filter(Boolean));
      this.exceptions.push(...(list.exceptions ?? []).map(compiled).filter(Boolean));
    }
  }

  /** Whether a tab opened to `url` by a page of the host `opener` is one the lists close. */
  closes(url, opener) {
    let host;
    try {
      const address = new URL(url);
      if (address.protocol !== 'http:' && address.protocol !== 'https:') return false;
      host = address.hostname;
    } catch {
      return false;
    }
    const third = siteName(host) !== siteName(opener);
    const applies = (entry) =>
      (entry.third === undefined || entry.third === third) && (!entry.on || covers(entry.on, opener)) && !(entry.notOn && covers(entry.notOn, opener)) && entry.test(url);
    return (covers(this.hosts, host) || this.patterns.some(applies)) && !this.exceptions.some(applies);
  }
}
