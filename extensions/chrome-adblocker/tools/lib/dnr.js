// Turns parsed network filters (filters.js) into declarativeNetRequest
// rules: the only way a Manifest V3 extension may block requests.
//
// What Chrome's rules can't say is dropped and counted by reason, never
// approximated in a way that would block more than the filter does.

import { hostname } from './filters.js';

const FRAMES = ['main_frame', 'sub_frame'];

/** Every resource type a rule may name. */
export const RESOURCE_TYPES = [
  'main_frame',
  'sub_frame',
  'stylesheet',
  'script',
  'image',
  'font',
  'object',
  'xmlhttprequest',
  'ping',
  'csp_report',
  'media',
  'websocket',
  'webtransport',
  'webbundle',
  'other',
];

/**
 * Priorities. At one priority Chrome lets `allow` win over `block`, which
 * is how an exception filter beats a blocking one. `$important` blocks sit
 * above the exceptions, and the user's own allowlist above everything.
 *
 * `$csp` filters sit below all of them. Chrome leaves out a header rule
 * when an `allow` of its priority or higher matches, which is the only
 * way to say `@@...$csp`; down here that `allow` takes the policy back and
 * is outranked by every blocking rule, so it lets nothing else through.
 */
export const PRIORITY = { csp: 1, normal: 2, important: 3, user: 1000 };

const unique = (list) => [...new Set(list)].sort();

/**
 * Whether a regular expression is one Chrome's RE2 engine is likely to
 * take: no lookaround, backreferences, atomic groups or possessive
 * quantifiers. Chrome also refuses expressions that compile too large,
 * which only Chrome can tell: see test/e2e and lists/rejected.json.
 */
export function regexLooksSupported(source) {
  try {
    new RegExp(source);
  } catch {
    return false;
  }
  let inClass = false;
  for (let i = 0; i < source.length; i++) {
    const c = source[i];
    if (c === '\\') {
      const next = source[i + 1] ?? '';
      // RE2 takes an escaped punctuation mark as itself, and of letters and
      // digits only these: no backreferences, no \u, \c or \k.
      if (/\w/.test(next) && !'dDsSwWbBnrtfvaAzx0'.includes(next)) return false;
      i++;
      continue;
    }
    if (inClass) {
      if (c === ']') inClass = false;
      continue;
    }
    if (c === '[') {
      inClass = true;
      continue;
    }
    if (c === '(' && source[i + 1] === '?' && source[i + 2] !== ':') return false;
    if ('*+?}'.includes(c) && source[i + 1] === '+') return false;
    if (c === '{') {
      const repeat = /^\{(\d+)(?:,(\d*))?\}/.exec(source.slice(i));
      if (repeat && Math.max(Number(repeat[1]), Number(repeat[2] || 0)) > 1000) return false;
    }
  }
  return true;
}

/** The part of a filter that says which URLs it matches. */
function urlPart(filter, rejected) {
  if (filter.regex) {
    if (!regexLooksSupported(filter.pattern)) return { drop: 'regex:unsupported' };
    if (rejected.has(filter.pattern)) return { drop: 'regex:rejected-by-chrome' };
    return { regexFilter: filter.pattern };
  }
  if (!filter.pattern) return {};
  const whole = /^\|\|([^/^*|:?=&]+)\^$/.exec(filter.pattern);
  if (whole && !filter.matchCase && !filter.to) {
    const host = hostname(whole[1]);
    if (host) return { host };
  }
  return { urlFilter: filter.pattern };
}

/** The parts of a rule's condition that do not depend on the URL. */
function baseCondition(filter) {
  const condition = {};
  if (filter.thirdParty !== null) condition.domainType = filter.thirdParty ? 'thirdParty' : 'firstParty';
  if (filter.domains?.include.length) condition.initiatorDomains = unique(filter.domains.include);
  if (filter.domains?.exclude.length) condition.excludedInitiatorDomains = unique(filter.domains.exclude);
  if (filter.to?.include.length) condition.requestDomains = unique(filter.to.include);
  if (filter.to?.exclude.length) condition.excludedRequestDomains = unique(filter.to.exclude);
  if (filter.methods?.length) condition.requestMethods = unique(filter.methods);
  return condition;
}

/**
 * The resource types of a filter as Chrome wants them. With none named
 * Chrome matches everything but the page itself, as Adblock Plus does. With
 * only exclusions Chrome would match the page too, so the page is excluded
 * by name.
 */
function typesOf(types, notTypes) {
  if (types.length) return { resourceTypes: unique(types) };
  if (notTypes.length) return { excludedResourceTypes: unique([...notTypes, 'main_frame']) };
  return {};
}

/** The kinds of document a `$csp` filter is for: those it names, or both. */
function framesOf(filter) {
  const frames = filter.types.filter((type) => FRAMES.includes(type));
  return frames.length ? unique(frames) : FRAMES;
}

/**
 * A `$csp` filter is for documents, and what it says of them means one
 * thing for a page and another for a frame, where Chrome's conditions
 * mean the same for both. So a filter that says either is read as two.
 *
 * `domain=` names the documents the policy is for. For a frame that is
 * the page it is in, which Chrome calls the request's initiator. For a
 * page it is the page's own host, and to Chrome that is the request's
 * domain: its initiator is whichever page held the link that led there.
 *
 * `third-party` is the document against the page it is in. A frame may
 * be of another site than its page. A page is never of another site than
 * itself, where Chrome would compare it with the page before it (or with
 * nothing, for an address typed): so `~third-party` says nothing of a
 * page, and `third-party` leaves no page for the filter to be for.
 *
 * Returns null where it can't be said (`to=` is taken).
 */
function byDocument(filter) {
  const named = filter.domains && filter.domains.include.length + filter.domains.exclude.length > 0;
  if (filter.csp === undefined || (!named && filter.thirdParty === null)) return [filter];
  const frames = framesOf(filter);
  const filters = [];
  if (frames.includes('main_frame') && filter.thirdParty !== true) {
    if (named && filter.to) return null;
    const page = { ...filter, types: ['main_frame'], thirdParty: null };
    filters.push(named ? { ...page, domains: null, to: filter.domains } : page);
  }
  if (frames.includes('sub_frame')) filters.push({ ...filter, types: ['sub_frame'] });
  return filters;
}

/**
 * What a filter asks for, as one or more { action, priority, types }:
 * an exception for a whole document is its own rule beside the exception
 * for the types named with it.
 */
function actionsOf(filter) {
  const priority = filter.important ? PRIORITY.important : PRIORITY.normal;
  if (filter.csp !== undefined) {
    const types = { resourceTypes: framesOf(filter) };
    if (filter.exception) return [{ action: { type: 'allow' }, priority: PRIORITY.csp, types }];
    if (!filter.csp) return [];
    const header = { header: 'content-security-policy', operation: 'append', value: filter.csp };
    return [{ action: { type: 'modifyHeaders', responseHeaders: [header] }, priority: filter.important ? PRIORITY.important : PRIORITY.csp, types }];
  }
  if (!filter.exception) return [{ action: { type: 'block' }, priority, types: typesOf(filter.types, filter.notTypes) }];

  const actions = [];
  const hides = filter.elemhide || filter.generichide;
  const others = filter.types.filter((type) => type !== 'main_frame');
  if (filter.types.includes('main_frame')) {
    actions.push({ action: { type: 'allowAllRequests' }, priority, types: { resourceTypes: FRAMES } });
  }
  if (others.length) actions.push({ action: { type: 'allow' }, priority, types: { resourceTypes: unique(others) } });
  // An exception that names no type at all lets everything but the page
  // through, unless it is only there to turn element hiding off.
  if (!filter.types.length && !hides) actions.push({ action: { type: 'allow' }, priority, types: typesOf([], filter.notTypes) });
  return actions;
}

/** Drops the hosts another host in the list already covers (`a.example.com` under `example.com`). */
function withoutCovered(hosts) {
  const all = new Set(hosts);
  return [...all]
    .filter((host) => {
      let dot = host.indexOf('.');
      while (dot !== -1) {
        if (all.has(host.slice(dot + 1))) return false;
        dot = host.indexOf('.', dot + 1);
      }
      return true;
    })
    .sort();
}

/**
 * Converts network filters to declarativeNetRequest rules.
 *
 * Filters that match whole hosts (`||ads.example^`) and are otherwise
 * alike become one rule with every host in `requestDomains`: tens of
 * thousands of filters in a few rules, which is what keeps a real list
 * inside Chrome's limit on rules.
 *
 * Returns
 *   rules      the rules, numbered from options.firstId
 *   hide       { elemhide, generichide }: hosts whose pages cosmetic
 *              filtering (or its generic part) is off for
 *   dropped    Map of reason to how many filters could not be converted
 */
export function toRules(filters, options = {}) {
  const rejected = new Set(options.rejectedRegex ?? []);
  const dropped = new Map();
  const drop = (reason) => dropped.set(reason, (dropped.get(reason) ?? 0) + 1);
  const grouped = new Map();
  const single = [];
  const hide = { elemhide: new Set(), generichide: new Set() };
  // Hosts whose every page is excepted, by the priority of the exception.
  const excepted = new Map();

  const each = [];
  for (const filter of filters) {
    const read = byDocument(filter);
    if (read) each.push(...read);
    else drop('csp:domain-and-to');
  }

  for (const filter of each) {
    const url = urlPart(filter, rejected);
    if (url.drop) {
      drop(url.drop);
      continue;
    }
    const base = baseCondition(filter);

    if (filter.exception && (filter.elemhide || filter.generichide)) {
      // Only a filter for a whole host, or for named pages' domains, can
      // be looked up when a page's selectors are chosen.
      const hosts = url.host ? [url.host] : !filter.pattern && base.initiatorDomains ? base.initiatorDomains : [];
      if (!hosts.length) drop('hide-exception:pattern');
      for (const host of hosts) {
        if (filter.elemhide) hide.elemhide.add(host);
        if (filter.generichide) hide.generichide.add(host);
      }
    }
    // A host whose every page is excepted, with nothing else said of it.
    const wholeHost = url.host && Object.keys(base).length === 0;
    // An exception for a whole document (`@@||site^$document`) lets through
    // what the page asks for and leaves its elements alone as well.
    const documentException = filter.exception && filter.csp === undefined && filter.types.includes('main_frame');
    if (documentException && wholeHost) hide.elemhide.add(url.host);

    const actions = actionsOf(filter);
    if (!actions.length) {
      if (!filter.elemhide && !filter.generichide) drop('nothing-to-do');
      continue;
    }
    const narrowed = url.host || url.urlFilter || url.regexFilter || base.initiatorDomains || base.requestDomains;
    if (!narrowed) {
      drop('too-broad');
      continue;
    }
    for (const { action, priority, types } of actions) {
      const rule = { action, condition: { ...base, ...types } };
      if (priority !== 1) rule.priority = priority;
      if (action.type === 'allowAllRequests' && wholeHost) {
        if (!excepted.has(priority)) excepted.set(priority, []);
        excepted.get(priority).push(url.host);
      }
      if (url.host) {
        const key = JSON.stringify(rule);
        if (!grouped.has(key)) grouped.set(key, { rule, hosts: [] });
        grouped.get(key).hosts.push(url.host);
        continue;
      }
      if (url.urlFilter) rule.condition.urlFilter = url.urlFilter;
      if (url.regexFilter) rule.condition.regexFilter = url.regexFilter;
      if (filter.matchCase && (url.urlFilter || url.regexFilter)) rule.condition.isUrlFilterCaseSensitive = true;
      single.push(rule);
    }
  }

  const rules = [];
  let id = options.firstId ?? 1;
  for (const key of [...grouped.keys()].sort()) {
    const { rule, hosts } = grouped.get(key);
    rule.condition.requestDomains = withoutCovered(hosts);
    rules.push({ id: id++, ...rule });
  }
  // Chrome works out which frames an allowAllRequests rule covers as each
  // navigation finishes, and a request a page makes in its first instant
  // can be judged before it has (seen in this extension's own tests). So
  // where a whole host is excepted, whatever its documents ask for is
  // allowed by a rule that needs no such bookkeeping as well.
  for (const priority of [...excepted.keys()].sort((a, b) => a - b)) {
    rules.push({ id: id++, action: { type: 'allow' }, condition: { initiatorDomains: withoutCovered(excepted.get(priority)) }, priority });
  }
  // Filters written twice (a list repeats some across its sections) are one rule.
  const seen = new Set();
  for (const rule of single) {
    const key = JSON.stringify(rule);
    if (seen.has(key)) continue;
    seen.add(key);
    rules.push({ id: id++, ...rule });
  }
  return { rules, hide: { elemhide: [...hide.elemhide].sort(), generichide: [...hide.generichide].sort() }, dropped };
}

const DOMAIN = /^(?:[a-z0-9_-]+\.)*[a-z0-9-]+$/;
const CONDITION_KEYS = new Set([
  'urlFilter',
  'regexFilter',
  'isUrlFilterCaseSensitive',
  'initiatorDomains',
  'excludedInitiatorDomains',
  'requestDomains',
  'excludedRequestDomains',
  'resourceTypes',
  'excludedResourceTypes',
  'requestMethods',
  'domainType',
]);

/**
 * What is wrong with a rule by Chrome's own requirements, as a list of
 * plain words; empty if nothing is. The tests hold every rule built from
 * the real lists to this.
 */
export function problemsWith(rule) {
  const problems = [];
  const { condition = {}, action = {} } = rule;
  if (!Number.isInteger(rule.id) || rule.id < 1) problems.push('id is not a positive whole number');
  if (rule.priority !== undefined && (!Number.isInteger(rule.priority) || rule.priority < 1)) problems.push('priority is not a positive whole number');
  if (!['block', 'allow', 'allowAllRequests', 'modifyHeaders'].includes(action.type)) problems.push(`action ${action.type} is not one this extension makes`);
  for (const key of Object.keys(condition)) {
    if (!CONDITION_KEYS.has(key)) problems.push(`condition has an unknown key ${key}`);
  }
  if (condition.urlFilter !== undefined && condition.regexFilter !== undefined) problems.push('both urlFilter and regexFilter');
  if (condition.urlFilter !== undefined) {
    if (!condition.urlFilter) problems.push('urlFilter is empty');
    if (/[^\x21-\x7e]/.test(condition.urlFilter)) problems.push('urlFilter is not printable ASCII');
    if (condition.urlFilter.startsWith('||*')) problems.push('urlFilter starts with ||*');
  }
  if (condition.regexFilter !== undefined && !condition.regexFilter) problems.push('regexFilter is empty');
  for (const key of ['initiatorDomains', 'excludedInitiatorDomains', 'requestDomains', 'excludedRequestDomains']) {
    const list = condition[key];
    if (list === undefined) continue;
    if (!Array.isArray(list) || !list.length) problems.push(`${key} is empty`);
    else if (list.some((domain) => !DOMAIN.test(domain))) problems.push(`${key} has something that is not a lower-case host`);
  }
  for (const key of ['resourceTypes', 'excludedResourceTypes']) {
    const list = condition[key];
    if (list === undefined) continue;
    if (!Array.isArray(list) || !list.length) problems.push(`${key} is empty`);
    else if (list.some((type) => !RESOURCE_TYPES.includes(type))) problems.push(`${key} names an unknown type`);
  }
  if (condition.resourceTypes && condition.excludedResourceTypes) problems.push('both resourceTypes and excludedResourceTypes');
  if (condition.domainType !== undefined && !['firstParty', 'thirdParty'].includes(condition.domainType)) problems.push('domainType is unknown');
  if (action.type === 'allowAllRequests') {
    const types = condition.resourceTypes ?? [];
    if (!types.length || types.some((type) => !FRAMES.includes(type))) problems.push('allowAllRequests must name only main_frame and sub_frame');
  }
  if (action.type === 'modifyHeaders') {
    const headers = action.responseHeaders ?? [];
    if (!headers.length || headers.some((header) => !header.header || !header.operation)) problems.push('modifyHeaders has no well-formed header');
  }
  const narrowed = condition.urlFilter || condition.regexFilter || condition.requestDomains || condition.initiatorDomains;
  if (!narrowed) problems.push('matches every request');
  return problems;
}
