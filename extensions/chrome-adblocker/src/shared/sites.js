// Sites and the list of those the user lets through. No Chrome API here:
// the service worker, the pages and the unit tests all use it.

/** Above every rule a filter list can make (tools/lib/dnr.js: PRIORITY). */
export const USER_PRIORITY = 1000;

/** The dynamic rules Stillwater keeps: one for the sites let through, one for the pause. */
export const RULE = { allowlist: 1, paused: 2 };

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

/** Whether a host is one of the sites let through, or under one. */
export function isAllowed(allowlist, host) {
  const site = siteOf(host);
  if (!site) return false;
  return (allowlist ?? []).some((allowed) => site === allowed || site.endsWith(`.${allowed}`));
}

/** The list with a site added or taken out, in order, each site once. */
export function withSite(allowlist, site, allowed) {
  const rest = (allowlist ?? []).filter((other) => other !== site);
  return (allowed ? [...rest, site] : rest).sort();
}

/**
 * The dynamic rules for the user's own choices: every request of a page
 * of a site let through is allowed, and of every page while paused.
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
  }
  if (paused) {
    rules.push({
      id: RULE.paused,
      priority: USER_PRIORITY,
      action: { type: 'allowAllRequests' },
      condition: { resourceTypes: ['main_frame', 'sub_frame'] },
    });
  }
  return rules;
}

/** A count as the popup shows it: 1,204. */
export function grouped(count) {
  return String(Math.max(0, Math.round(Number(count) || 0))).replace(/\B(?=(\d{3})+$)/g, ',');
}
