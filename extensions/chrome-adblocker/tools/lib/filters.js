// Reads filter lists written in Adblock Plus syntax (the syntax EasyList and
// EasyPrivacy use) into plain objects. Nothing here knows about Chrome: the
// conversion to declarativeNetRequest rules is in dnr.js, and the cosmetic
// data is built in cosmetic.js.

import { domainToASCII } from 'node:url';

// A cosmetic filter: optional domains, a separator, a selector. The domain
// part can't hold the characters a network pattern would (as in ABP itself).
const COSMETIC = /^([^/|@"!]*?)(#@?[?$%]?#)(.+)$/;

// The options at the end of a network filter: `$script,domain=example.com`.
const OPTIONS = /\$(~?[\w-]+(?:=[^,]*)?(?:,~?[\w-]+(?:=[^,]*)?)*)$/;

// Request types a filter may name, and the declarativeNetRequest type each
// one means.
const TYPES = {
  script: 'script',
  image: 'image',
  stylesheet: 'stylesheet',
  css: 'stylesheet',
  object: 'object',
  'object-subrequest': 'object',
  xmlhttprequest: 'xmlhttprequest',
  xhr: 'xmlhttprequest',
  subdocument: 'sub_frame',
  frame: 'sub_frame',
  ping: 'ping',
  beacon: 'ping',
  websocket: 'websocket',
  font: 'font',
  media: 'media',
  other: 'other',
  document: 'main_frame',
  doc: 'main_frame',
};

// Types Chrome's declarativeNetRequest has no way to match. A filter that
// names only these is dropped; one that excludes them loses nothing.
const UNMATCHABLE_TYPES = new Set(['popup', 'webrtc']);

// Procedural operators (uBlock Origin's and AdGuard's) that plain CSS can't
// express. `:-abp-has()` is not here: it is rewritten to `:has()`.
const PROCEDURAL = /:(?:has-text|contains|-abp-contains|-abp-properties|matches-css(?:-before|-after)?|matches-attr|matches-path|matches-media|matches-prop|min-text-length|upward|xpath|remove|remove-attr|remove-class|style|watch-attr|others|shadow|spath|nth-ancestor|if|if-not)\(/;

/** A hostname in lower case ASCII (punycode), or '' if it is not one. */
export function hostname(text) {
  const lower = text.trim().toLowerCase();
  if (!lower) return '';
  const ascii = /^[\x00-\x7f]*$/.test(lower) ? lower : domainToASCII(lower);
  return /^(?:[a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(ascii) ? ascii : '';
}

/**
 * A list of domains as `domain=` and cosmetic filters write them: included,
 * excluded (`~`), and entities (`example.*`), which Chrome can't match in a
 * network rule but the cosmetic lookup can.
 */
function domainList(text, separator) {
  const list = { include: [], exclude: [], entities: [], bad: [] };
  for (const part of text.split(separator)) {
    const item = part.trim();
    if (!item) continue;
    const negated = item.startsWith('~');
    const name = negated ? item.slice(1) : item;
    if (name.endsWith('.*')) {
      const stem = hostname(name.slice(0, -2));
      if (!stem) list.bad.push(item);
      else (negated ? list.exclude : list.entities).push(`${stem}.*`);
      continue;
    }
    const host = hostname(name);
    if (!host) list.bad.push(item);
    else (negated ? list.exclude : list.include).push(host);
  }
  return list;
}

/** Whether brackets, parentheses and quotes are balanced: a selector that is not could break out of the rule it is put in. */
export function isBalanced(selector) {
  const closers = { ')': '(', ']': '[' };
  const open = [];
  let quote = '';
  for (let i = 0; i < selector.length; i++) {
    const c = selector[i];
    if (c === '\\') {
      i++;
      continue;
    }
    if (quote) {
      if (c === quote) quote = '';
      continue;
    }
    if (c === '"' || c === "'") quote = c;
    else if (c === '(' || c === '[') open.push(c);
    else if (c === ')' || c === ']') {
      if (open.pop() !== closers[c]) return false;
    }
  }
  return !quote && open.length === 0;
}

/** Splits a selector list at its top-level commas. */
export function splitSelectors(text) {
  const parts = [];
  let depth = 0;
  let quote = '';
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '\\') {
      i++;
      continue;
    }
    if (quote) {
      if (c === quote) quote = '';
      continue;
    }
    if (c === '"' || c === "'") quote = c;
    else if (c === '(' || c === '[') depth++;
    else if (c === ')' || c === ']') depth--;
    else if (c === ',' && depth === 0) {
      parts.push(text.slice(start, i).trim());
      start = i + 1;
    }
  }
  parts.push(text.slice(start).trim());
  return parts.filter(Boolean);
}

/**
 * Reads a cosmetic filter. Returns
 *   { kind: 'cosmetic', exception, selectors, include, exclude, entities }
 * or { kind: 'unsupported', reason }.
 */
function cosmetic(domains, separator, body) {
  const unsupported = (reason) => ({ kind: 'unsupported', reason: `cosmetic:${reason}` });
  if (separator.includes('$') || separator.includes('%')) return unsupported('snippet');
  let selector = body.trim();
  if (selector.startsWith('+js(') || selector.startsWith('^')) return unsupported('scriptlet');
  if (separator.includes('?') || selector.includes(':-abp-')) {
    selector = selector.replaceAll(':-abp-has(', ':has(');
    if (selector.includes(':-abp-')) return unsupported('procedural');
  }
  if (PROCEDURAL.test(selector)) return unsupported('procedural');
  // `selector {declarations}` is Adblock Plus's way to restyle an element.
  if (/\{[^{}]*\}\s*$/.test(selector)) return unsupported('style');
  if (/[{}]|\/\*/.test(selector) || !isBalanced(selector)) return unsupported('malformed');
  const list = domainList(domains, ',');
  if (list.bad.length) return unsupported('domain');
  const selectors = splitSelectors(selector);
  if (!selectors.length) return unsupported('malformed');
  return {
    kind: 'cosmetic',
    exception: separator.includes('@'),
    selectors,
    include: list.include,
    exclude: list.exclude,
    entities: list.entities,
  };
}

/**
 * Reads a network filter. Returns { kind: 'network', ... } with
 *   exception    `@@`: lets requests through
 *   pattern      the URL pattern, lower case unless matchCase; '' matches all
 *   regex        the pattern is a regular expression
 *   types        declarativeNetRequest types named; empty means the default
 *   notTypes     types excluded with `~`
 *   thirdParty   true, false, or null for either
 *   domains      { include, exclude } of the pages it applies on, or null
 *   to           { include, exclude } of the hosts requested, or null
 *   csp          a Content-Security-Policy to add (or '' in an exception)
 *   elemhide, generichide   an exception that turns cosmetic filtering off
 *   important    outranks exceptions
 * or { kind: 'unsupported', reason }.
 */
function network(text) {
  const unsupported = (reason) => ({ kind: 'unsupported', reason });
  let rest = text;
  const filter = {
    kind: 'network',
    exception: false,
    pattern: '',
    regex: false,
    matchCase: false,
    types: [],
    notTypes: [],
    thirdParty: null,
    domains: null,
    to: null,
    methods: null,
    csp: undefined,
    elemhide: false,
    generichide: false,
    important: false,
  };
  if (rest.startsWith('@@')) {
    filter.exception = true;
    rest = rest.slice(2);
  }

  let options = [];
  const found = OPTIONS.exec(rest);
  if (found) {
    options = found[1].split(',');
    rest = rest.slice(0, found.index);
  }

  const types = new Set();
  const notTypes = new Set();
  let unmatchable = '';
  for (const option of options) {
    const negated = option.startsWith('~');
    const [name, ...valueParts] = (negated ? option.slice(1) : option).split('=');
    const value = valueParts.join('=');
    const key = name.toLowerCase();
    if (key in TYPES) {
      (negated ? notTypes : types).add(TYPES[key]);
    } else if (UNMATCHABLE_TYPES.has(key)) {
      if (!negated) unmatchable = key;
    } else if (key === 'third-party' || key === '3p') {
      filter.thirdParty = !negated;
    } else if (key === 'first-party' || key === '1p') {
      filter.thirdParty = negated;
    } else if (key === 'match-case') {
      filter.matchCase = !negated;
    } else if (key === 'domain' || key === 'from') {
      if (value.startsWith('/')) return unsupported('option:domain-regex');
      const list = domainList(value, '|');
      if (list.bad.length) return unsupported('option:domain');
      // Chrome can't match an entity (`google.*`) as an initiator. Dropping
      // one from the included domains only narrows where the filter applies.
      if (!list.include.length && list.entities.length) return unsupported('option:domain-entity');
      if (list.include.length || list.exclude.length) filter.domains = { include: list.include, exclude: list.exclude };
    } else if (key === 'to' || key === 'denyallow') {
      const list = domainList(value, '|');
      if (list.bad.length || list.entities.length) return unsupported(`option:${key}`);
      if (key === 'denyallow') filter.to = { include: [], exclude: list.include };
      else filter.to = { include: list.include, exclude: list.exclude };
    } else if (key === 'method') {
      const methods = value.toLowerCase().split('|').filter(Boolean);
      if (methods.some((method) => method.startsWith('~'))) return unsupported('option:method');
      filter.methods = methods;
    } else if (key === 'csp') {
      if (negated) return unsupported('option:csp');
      filter.csp = value;
    } else if (key === 'elemhide' || key === 'ehide') {
      filter.elemhide = true;
    } else if (key === 'generichide' || key === 'ghide') {
      filter.generichide = true;
    } else if (key === 'important') {
      filter.important = true;
    } else {
      return unsupported(`option:${key}`);
    }
  }
  if ((filter.elemhide || filter.generichide) && !filter.exception) return unsupported('option:hide-in-block');
  if (unmatchable && types.size === 0 && filter.csp === undefined && !filter.elemhide && !filter.generichide) {
    return unsupported(`option:${unmatchable}`);
  }
  filter.types = [...types].sort();
  filter.notTypes = [...notTypes].sort();

  if (rest.length > 1 && rest.startsWith('/') && rest.endsWith('/')) {
    filter.regex = true;
    filter.pattern = rest.slice(1, -1);
    return filter;
  }

  // Leading and trailing wildcards say nothing; `||*` is `*` to Chrome.
  let pattern = rest.replace(/\*+/g, '*');
  if (pattern.startsWith('||*')) pattern = pattern.slice(2);
  pattern = pattern.replace(/^\*+/, '').replace(/\*+$/, '');
  if (/^\|\|?$/.test(pattern) || pattern === '|' || pattern === '^') return unsupported('pattern:empty-anchor');
  if (!filter.matchCase) pattern = pattern.toLowerCase();
  if (/[^\x21-\x7e]/.test(pattern)) {
    // Only a host can be written another way (punycode); anything else
    // outside printable ASCII can't be given to Chrome.
    const host = /^(\|\|)([^/^*|]+)(.*)$/.exec(pattern);
    const ascii = host ? hostname(host[2]) : '';
    if (!ascii || /[^\x21-\x7e]/.test(host[3])) return unsupported('pattern:non-ascii');
    pattern = host[1] + ascii + host[3];
  }
  filter.pattern = pattern;
  return filter;
}

/**
 * Reads one line of a filter list:
 *   { kind: 'blank' | 'comment' }
 *   { kind: 'network', ... }      see network()
 *   { kind: 'cosmetic', ... }     see cosmetic()
 *   { kind: 'unsupported', reason }
 */
export function parseLine(line) {
  const text = line.trim();
  if (!text) return { kind: 'blank' };
  if (text.startsWith('!') || (text.startsWith('[') && text.endsWith(']'))) return { kind: 'comment' };
  // A hosts-file comment.
  if (/^#(?:\s|$)/.test(text)) return { kind: 'comment' };
  const hidden = COSMETIC.exec(text);
  const parsed = hidden ? cosmetic(hidden[1], hidden[2], hidden[3]) : network(text);
  parsed.raw = text;
  return parsed;
}

/** Reads a whole list, keeping only what can be used, and counting the rest by reason. */
export function parseList(text) {
  const network = [];
  const cosmetic = [];
  const dropped = new Map();
  let lines = 0;
  for (const line of text.split(/\r?\n/)) {
    const parsed = parseLine(line);
    if (parsed.kind === 'blank' || parsed.kind === 'comment') continue;
    lines++;
    if (parsed.kind === 'network') network.push(parsed);
    else if (parsed.kind === 'cosmetic') cosmetic.push(parsed);
    else dropped.set(parsed.reason, (dropped.get(parsed.reason) ?? 0) + 1);
  }
  return { network, cosmetic, dropped, lines };
}
