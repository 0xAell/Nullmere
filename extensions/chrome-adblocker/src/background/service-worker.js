// The service worker: keeps Chrome's rules in step with what the user has
// chosen, chooses what each page hides, and answers the popup and the
// options page. It holds nothing that can't be made again: Chrome stops it
// when idle and starts it afresh for the next event.

import { CosmeticIndex, hidingCSS, merged } from '../shared/cosmetic-lookup.js';
import { DEFAULTS, readSettings, writeSettings } from '../shared/settings.js';
import { hostOf, isAllowed, RULE, siteFromInput, siteOf, userRules, withSite } from '../shared/sites.js';

const dnr = chrome.declarativeNetRequest;

const ICONS = {
  on: { 16: '/icons/icon-16.png', 32: '/icons/icon-32.png', 48: '/icons/icon-48.png' },
  off: { 16: '/icons/off-16.png', 32: '/icons/off-32.png', 48: '/icons/off-48.png' },
};

// ---------------------------------------------------------------------------
// The user's choices, put into effect.

/** Makes Chrome's dynamic rules and the badge follow the settings. */
async function apply(settings) {
  await dnr.updateDynamicRules({ removeRuleIds: Object.values(RULE), addRules: userRules(settings) });
  // Chrome counts what it blocked on each tab's page and writes it on the
  // icon. With the badge off the count is still kept (the popup reads it)
  // and only drawn in next to no colour: Chrome refuses a text colour of
  // none at all, so it is given the faintest there is, on no background.
  await dnr.setExtensionActionOptions({ displayActionCountAsBadgeText: true });
  await chrome.action.setBadgeBackgroundColor({ color: settings.badge ? [22, 35, 58, 255] : [0, 0, 0, 0] });
  await chrome.action.setBadgeTextColor({ color: settings.badge ? [228, 234, 242, 255] : [0, 0, 0, 1] });
}

async function save(settings) {
  await writeSettings(settings);
  await apply(settings);
  await paintAll(settings);
}

let last = Promise.resolve();

/**
 * Runs changes to the settings one after another. Each reads what is
 * kept, changes it and writes it back; two at once (two switches pressed
 * in a breath) would each write over the other's change.
 */
function inTurn(change) {
  const mine = last.then(change, change);
  last = mine.catch(() => {});
  return mine;
}

/** The toolbar icon of a tab: the new moon where its site is let through. */
async function paint(tabId, url, settings) {
  const host = hostOf(url);
  const off = settings.paused || (host !== '' && isAllowed(settings.allowlist, host));
  try {
    await chrome.action.setIcon({ tabId, path: off ? ICONS.off : ICONS.on });
  } catch {
    // The tab closed meanwhile.
  }
}

async function paintAll(settings) {
  const tabs = await chrome.tabs.query({});
  await Promise.all(tabs.map((tab) => paint(tab.id, tab.url, settings)));
}

chrome.runtime.onInstalled.addListener(async () => {
  const settings = await readSettings();
  await apply(settings);
  await paintAll(settings);
});

chrome.runtime.onStartup.addListener(async () => {
  const settings = await readSettings();
  await apply(settings);
});

chrome.tabs.onUpdated.addListener(async (tabId, change, tab) => {
  // A tab's own icon is forgotten when it navigates.
  if (change.status === 'loading' || change.url !== undefined) await paint(tabId, tab.url, await readSettings());
});

// ---------------------------------------------------------------------------
// Cosmetic filtering: which elements a page hides.

let index = null;

/** The cosmetic data of the lists now enabled, read once for as long as the worker lives. */
function cosmeticIndex() {
  index ??= (async () => {
    const enabled = await dnr.getEnabledRulesets();
    const lists = await Promise.all(enabled.map(async (id) => (await fetch(chrome.runtime.getURL(`cosmetic/${id}.json`))).json()));
    return new CosmeticIndex(merged(lists));
  })().catch((error) => {
    index = null;
    throw error;
  });
  return index;
}

/** Adds a style sheet to the document that asked. As the user's own, so a page's `!important` can't undo it. */
async function hide(sender, selectors) {
  if (!selectors.length || !sender.tab) return;
  const target = { tabId: sender.tab.id };
  if (sender.documentId) target.documentIds = [sender.documentId];
  else target.frameIds = [sender.frameId ?? 0];
  try {
    await chrome.scripting.insertCSS({ target, css: hidingCSS(selectors), origin: 'USER' });
  } catch {
    // The document went away before its answer came.
  }
}

/** What cosmetic filtering does for a frame of `host` in a tab showing `tabUrl`. */
async function cosmeticFor(host, tabUrl) {
  const settings = await readSettings();
  const page = hostOf(tabUrl) || host;
  if (settings.paused || !settings.cosmetic || isAllowed(settings.allowlist, page)) return { active: false, generic: false };
  const lookup = await cosmeticIndex();
  const own = lookup.switches(host);
  const top = lookup.switches(page);
  return { active: own.cosmetic && top.cosmetic, generic: own.generic && top.generic, lookup };
}

// ---------------------------------------------------------------------------
// Messages. Content scripts may only ask what to hide; the rest is for the
// extension's own pages.

const fromPage = {
  /** A document has begun: hide what is written for its site, and say whether to go on looking. */
  async 'cosmetic:start'({ host }, sender) {
    const { active, generic, lookup } = await cosmeticFor(String(host), sender.tab?.url);
    if (!active) return { active: false, generic: false };
    await hide(sender, lookup.selectorsFor(String(host), { generic }));
    return { active, generic };
  },

  /** Classes and ids a document has: hide what the generic filters say of them. */
  async 'cosmetic:tokens'({ host, tokens }, sender) {
    if (!Array.isArray(tokens) || tokens.length > 20_000) return {};
    const { generic, lookup } = await cosmeticFor(String(host), sender.tab?.url);
    if (generic) await hide(sender, lookup.selectorsForTokens(String(host), tokens));
    return {};
  },
};

/** The state of a tab, for the popup. */
async function stateOf(tabId) {
  const settings = await readSettings();
  let tab = null;
  try {
    tab = await chrome.tabs.get(tabId);
  } catch {
    // No such tab.
  }
  const host = hostOf(tab?.url);
  let count = 0;
  if (host) {
    try {
      count = Number(await chrome.action.getBadgeText({ tabId })) || 0;
    } catch {
      count = 0;
    }
  }
  return {
    host,
    site: siteOf(host),
    filterable: host !== '',
    allowed: host !== '' && isAllowed(settings.allowlist, host),
    paused: settings.paused,
    count,
  };
}

/** Everything the options page shows. */
async function overview() {
  const [settings, enabled, available, lists] = await Promise.all([
    readSettings(),
    dnr.getEnabledRulesets(),
    dnr.getAvailableStaticRuleCount(),
    fetch(chrome.runtime.getURL('lists.json')).then((response) => response.json()),
  ]);
  return { settings, enabled, available, lists, version: chrome.runtime.getManifest().version };
}

const fromExtension = {
  async state({ tabId }) {
    return stateOf(tabId);
  },

  async overview() {
    return overview();
  },

  /** Lets a site through, or stops letting it; reloads the tab that asked, so the choice shows. */
  async 'site:set'({ site, allowed, tabId }) {
    const clean = siteFromInput(site);
    if (!clean) return { error: 'That is not a site.' };
    const settings = await inTurn(async () => {
      const kept = await readSettings();
      kept.allowlist = withSite(kept.allowlist, clean, Boolean(allowed));
      await save(kept);
      return kept;
    });
    if (Number.isInteger(tabId)) {
      try {
        await chrome.tabs.reload(tabId);
      } catch {
        // The tab closed meanwhile.
      }
    }
    return { settings };
  },

  /** Changes the switches: paused, cosmetic, youtube, badge. */
  async 'settings:set'({ patch }) {
    const settings = await inTurn(async () => {
      const kept = await readSettings();
      for (const key of ['paused', 'cosmetic', 'youtube', 'badge']) {
        if (typeof patch?.[key] === 'boolean') kept[key] = patch[key];
      }
      await save(kept);
      return kept;
    });
    return { settings };
  },

  /** Turns a filter list on or off. Chrome remembers which are on. */
  async 'ruleset:set'({ id, enabled }) {
    const known = chrome.runtime.getManifest().declarative_net_request.rule_resources.map((resource) => resource.id);
    if (!known.includes(id)) return { error: 'There is no such list.' };
    return inTurn(async () => {
      await dnr.updateEnabledRulesets(enabled ? { enableRulesetIds: [id] } : { disableRulesetIds: [id] });
      index = null;
      return overview();
    });
  },

  /** Back to how Stillwater was installed. */
  async reset() {
    const known = chrome.runtime.getManifest().declarative_net_request.rule_resources;
    return inTurn(async () => {
      await dnr.updateEnabledRulesets({
        enableRulesetIds: known.filter((resource) => resource.enabled).map((resource) => resource.id),
        disableRulesetIds: known.filter((resource) => !resource.enabled).map((resource) => resource.id),
      });
      index = null;
      await save({ ...DEFAULTS, allowlist: [] });
      return overview();
    });
  },
};

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id) return false;
  const own = typeof sender.url === 'string' && sender.url.startsWith(chrome.runtime.getURL(''));
  const handler = (own ? fromExtension[message?.type] : undefined) ?? fromPage[message?.type];
  if (!handler) return false;
  handler(message, sender).then(respond, (error) => respond({ error: String(error?.message ?? error) }));
  return true;
});
