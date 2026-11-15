// Sites and the list of those the user lets through. No Chrome API here:
// the service worker, the pages and the unit tests all use it.

/** Above every rule a filter list can make (tools/lib/dnr.js: PRIORITY). */
export const USER_PRIORITY = 1000;

/** The dynamic rules Stillwater keeps: two for the sites let through, one for the pause. */
export const RULE = { allowlist: 1, paused: 2, allowlistRequests: 3 };

/** Every resource type, the page itself included: for a rule meant to match everything. */
const EVERY_TYPE = ['main_frame', 'sub_frame', 'stylesheet', 'script', 'image', 'font', 'object', 'xmlhttprequest', 'ping', 'csp_report', 'media', 'websocket', 'webtransport', 'webbundle', 'other'];

/** The host of a page Stillwater can filter (http or https), or ''. */
export function hostOf(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:' ? parsed.hostname : '';
  } catch {
    return '';
  }
}

/**
 * The site a host is let through as: lower case, without a leading `www.`.
 * Letting `example.com` through lets its subdomains through with it.
 */
export function siteOf(host) {
  return String(host ?? '').toLowerCase().replace(/\.$/, '').replace(/^www\./, '');
}

/**
 * What someone typed or pasted as a site (a host, or a whole address), as
 * a site; '' if it is not one.
 */
export function siteFromInput(text) {
  const typed = String(text ?? '').trim().toLowerCase();
  if (!typed || /\s/.test(typed)) return '';
  let host;
  try {
    host = new URL(/^[a-z][a-z0-9+.-]*:\/\//.test(typed) ? typed : `http://${typed}`).hostname;
  } catch {
    return '';
  }
  const site = siteOf(host);
  return /^(?:[a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(site) ? site : '';
}

/** Whether `site` is `under`, or a subdomain of it. */
const within = (site, under) => site === under || site.endsWith(`.${under}`);

/** The site let through that lets a host through, the widest if several do; '' if none does. */
export function allowedBy(allowlist, host) {
  const site = siteOf(host);
  if (!site) return '';
  return (allowlist ?? []).filter((allowed) => within(site, allowed)).sort((a, b) => a.length - b.length)[0] ?? '';
}

/** Whether a host is one of the sites let through, or under one. */
export function isAllowed(allowlist, host) {
  return allowedBy(allowlist, host) !== '';
}

/**
 * The list with a site let through or stilled again, in order, each site
 * once. Letting a site through drops the sites under it, which it now
 * covers. Stilling one takes out whatever lets it through: asked of
 * `shop.example.com` while `example.com` is let through, it is
 * `example.com` that goes, since nothing less would still it.
 */
export function withSite(allowlist, site, allowed) {
  const list = allowlist ?? [];
  if (!allowed) return list.filter((other) => !within(site, other)).sort();
  return [...list.filter((other) => !within(other, site)), site].sort();
}

/**
 * The dynamic rules for the user's own choices.
 *
 * A site let through gets two rules. The first allows every request of
 * its pages, frames of other sites inside them included. Chrome works out
 * which frames that covers as each navigation finishes, and a request a
 * page makes in its very first instant can be judged before it has: so a
 * second rule allows whatever a document of the site asks for, which
 * needs no such bookkeeping.
 *
 * Paused, one rule allows every request there is.
 *
 * A page already open keeps what it was loaded with until it is reloaded.
 */
export function userRules({ allowlist = [], paused = false } = {}) {
  const rules = [];
  if (allowlist.length) {
    rules.push({
      id: RULE.allowlist,
      priority: USER_PRIORITY,
      action: { type: 'allowAllRequests' },
      condition: { requestDomains: [...allowlist], resourceTypes: ['main_frame'] },
    });
    rules.push({
      id: RULE.allowlistRequests,
      priority: USER_PRIORITY,
      action: { type: 'allow' },
      condition: { initiatorDomains: [...allowlist] },
    });
  }
  if (paused) {
    rules.push({
      id: RULE.paused,
      priority: USER_PRIORITY,
      action: { type: 'allow' },
      condition: { resourceTypes: EVERY_TYPE },
    });
  }
  return rules;
}

/** A count as the popup shows it: 1,204. */
export function grouped(count) {
  return String(Math.max(0, Math.round(Number(count) || 0))).replace(/\B(?=(\d{3})+$)/g, ',');
}
