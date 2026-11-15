// Chooses which elements to hide on a page, from the data tools/build.js
// writes (cosmetic.json). No Chrome API is used here, so the same code
// runs in the service worker and under the unit tests.
//
// The data:
//   generic.always   selectors given to every page
//   generic.simple   selectors that are one class or one id (`.ad-box`)
//   generic.keyed    { token: selectors } that can only match a page that
//                    has the class or id the token names
//   specific         { host or entity: selectors } for named sites
//   exceptions       { host or entity: selectors } not to hide there
//   noGeneric        hosts where the generic selectors are off
//   noCosmetic       hosts where nothing is hidden

/** The hosts and entities a hostname answers to: itself, each parent, and `name.*` forms. */
export function namesOf(host) {
  const labels = host.toLowerCase().split('.').filter(Boolean);
  const names = [];
  for (let start = 0; start < labels.length; start++) {
    const rest = labels.slice(start);
    names.push(rest.join('.'));
    // An entity (`google.*`) stands for a name under any public suffix.
    // Without the suffix list, the last one or two labels are taken as it.
    for (let cut = 1; cut <= 2 && cut < rest.length; cut++) {
      names.push(`${rest.slice(0, rest.length - cut).join('.')}.*`);
    }
  }
  return [...new Set(names)];
}

/** Whether a host, or a parent of it, is in a list of hosts. */
export function covers(list, host) {
  const set = list instanceof Set ? list : new Set(list ?? []);
  if (!set.size) return false;
  const labels = host.toLowerCase().split('.').filter(Boolean);
  for (let start = 0; start < labels.length; start++) {
    if (set.has(labels.slice(start).join('.'))) return true;
  }
  return false;
}

/** One rule hiding every selector. `:is()` forgives a selector Chrome can't read, so one bad selector never loses the rest. */
export function hidingRule(selectors) {
  return selectors.length ? `:is(${selectors.join(',')}){display:none!important}` : '';
}

/** A lookup over the cosmetic data, made once and asked for each page. */
export class CosmeticIndex {
  constructor(data) {
    this.data = data;
    this.noGeneric = new Set(data.noGeneric ?? []);
    this.noCosmetic = new Set(data.noCosmetic ?? []);
    this.byToken = new Map();
    for (const selector of data.generic.simple) this.add(selector.toLowerCase(), selector);
    for (const [token, selectors] of Object.entries(data.generic.keyed)) {
      for (const selector of selectors) this.add(token, selector);
    }
  }

  add(token, selector) {
    const list = this.byToken.get(token);
    if (list) list.push(selector);
    else this.byToken.set(token, [selector]);
  }

  /** What is off on a host's pages. */
  switches(host) {
    const off = covers(this.noCosmetic, host);
    return { cosmetic: !off, generic: !off && !covers(this.noGeneric, host) };
  }

  /** The selectors not to hide on a host. */
  exceptionsFor(host) {
    const out = new Set();
    for (const name of namesOf(host)) {
      for (const selector of this.data.exceptions[name] ?? []) out.add(selector);
    }
    return out;
  }

  /**
   * The selectors to hide as a page of `host` begins: those written for
   * it, and the generic ones that need no token. `generic: false` leaves
   * the generic ones out.
   */
  selectorsFor(host, { generic = true } = {}) {
    const except = this.exceptionsFor(host);
    const out = new Set();
    for (const name of namesOf(host)) {
      for (const selector of this.data.specific[name] ?? []) out.add(selector);
    }
    if (generic) {
      for (const selector of this.data.generic.always) out.add(selector);
    }
    return [...out].filter((selector) => !except.has(selector));
  }

  /**
   * The generic selectors that classes and ids seen on a page call for.
   * Tokens are `.class` or `#id`.
   */
  selectorsForTokens(host, tokens) {
    const except = this.exceptionsFor(host);
    const out = new Set();
    for (const token of tokens) {
      for (const selector of this.byToken.get(String(token).toLowerCase()) ?? []) {
        if (!except.has(selector)) out.add(selector);
      }
    }
    return [...out];
  }
}
