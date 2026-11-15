// Builds the data the extension hides elements from (see
// src/shared/cosmetic-lookup.js for how it is read) out of parsed cosmetic
// filters.

const SIMPLE = /^[.#]-?[_a-zA-Z][\w-]*$/;

/**
 * A class or id a selector can't match without: the first one written
 * outside brackets, parentheses and quotes, as `.name` or `#name` in lower
 * case. null if there is none, or the selector uses escapes.
 */
export function keyToken(selector) {
  if (selector.includes('\\')) return null;
  let bare = '';
  let depth = 0;
  let quote = '';
  for (const c of selector) {
    if (quote) {
      if (c === quote) quote = '';
      continue;
    }
    if (c === '"' || c === "'") quote = c;
    else if (c === '(' || c === '[') depth++;
    else if (c === ')' || c === ']') depth--;
    else if (depth === 0) bare += c;
  }
  const found = /[.#]-?[_a-zA-Z][\w-]*/.exec(bare);
  return found ? found[0].toLowerCase() : null;
}

const sorted = (set) => [...set].sort();

function push(map, key, selectors) {
  if (!map.has(key)) map.set(key, new Set());
  for (const selector of selectors) map.get(key).add(selector);
}

function toObject(map) {
  const out = {};
  for (const key of [...map.keys()].sort()) out[key] = sorted(map.get(key));
  return out;
}

/**
 * Builds the cosmetic data from cosmetic filters and from the hosts the
 * network exceptions turn hiding off for (dnr.js: `hide`).
 *
 * Returns { data, counts }.
 */
export function buildCosmetic(filters, hide = { elemhide: [], generichide: [] }) {
  const generic = new Set();
  const neverHide = new Set();
  const specific = new Map();
  const exceptions = new Map();

  for (const filter of filters) {
    const named = [...filter.include, ...filter.entities];
    if (filter.exception) {
      if (named.length) for (const host of named) push(exceptions, host, filter.selectors);
      else for (const selector of filter.selectors) neverHide.add(selector);
      continue;
    }
    if (named.length) for (const host of named) push(specific, host, filter.selectors);
    else for (const selector of filter.selectors) generic.add(selector);
    for (const host of filter.exclude) push(exceptions, host, filter.selectors);
  }

  // An exception with no site named takes the selector out everywhere.
  for (const selector of neverHide) {
    generic.delete(selector);
    for (const selectors of specific.values()) selectors.delete(selector);
  }
  for (const [host, selectors] of specific) {
    if (!selectors.size) specific.delete(host);
  }

  const simple = [];
  const always = [];
  const keyed = new Map();
  for (const selector of sorted(generic)) {
    if (SIMPLE.test(selector)) simple.push(selector);
    else {
      const token = keyToken(selector);
      if (token) push(keyed, token, [selector]);
      else always.push(selector);
    }
  }

  const data = {
    generic: { always, simple, keyed: toObject(keyed) },
    specific: toObject(specific),
    exceptions: toObject(exceptions),
    noGeneric: [...new Set(hide.generichide)].sort(),
    noCosmetic: [...new Set(hide.elemhide)].sort(),
  };
  const count = (object) => Object.values(object).reduce((sum, list) => sum + list.length, 0);
  const counts = {
    generic: generic.size,
    genericAlways: always.length,
    genericSimple: simple.length,
    genericKeyed: count(data.generic.keyed),
    specific: count(data.specific),
    specificHosts: Object.keys(data.specific).length,
    exceptions: count(data.exceptions),
  };
  return { data, counts };
}
