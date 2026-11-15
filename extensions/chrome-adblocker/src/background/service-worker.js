// The service worker: keeps Chrome's rules in step with what the user has
// chosen, chooses what each page hides, and answers the popup and the
// options page. It holds nothing that can't be made again: Chrome stops it
// when idle and starts it afresh for the next event.

import { CosmeticIndex, hidingCSS, merged } from '../shared/cosmetic-lookup.js';
import { Popups } from '../shared/popups.js';
import { DEFAULTS, readSettings, writeSettings } from '../shared/settings.js';
import { allowedBy, hostOf, isAllowed, RULE, siteFromInput, siteOf, userRules, withSite } from '../shared/sites.js';

const dnr = chrome.declarativeNetRequest;

const ICONS = {
  on: { 16: '/icons/icon-16.png', 32: '/icons/icon-32.png', 48: '/icons/icon-48.png' },
  off: { 16: '/icons/off-16.png', 32: '/icons/off-32.png', 48: '/icons/off-48.png' },
};

/** What the enabled lists hide, once it has been read; null whenever the enabled lists change. */
let index = null;
/** The pop-ups the enabled lists name, likewise. */
let popups = null;

// ---------------------------------------------------------------------------
// The user's choices, put into effect.

/** The ids of the filter lists the extension is built with. */
function listIds() {
  return chrome.runtime.getManifest().declarative_net_request.rule_resources.map((resource) => resource.id);
}

/**
 * Has Chrome enable the lists the user left on and no others. Chrome
 * keeps the enabled set itself, but only until the extension is next
 * updated, when every list in the manifest comes back on.
 */
async function applyLists(settings) {
  const off = new Set(settings.listsOff);
  const enabled = new Set(await dnr.getEnabledRulesets());
  const enableRulesetIds = listIds().filter((id) => !off.has(id) && !enabled.has(id));
  const disableRulesetIds = listIds().filter((id) => off.has(id) && enabled.has(id));
  if (!enableRulesetIds.length && !disableRulesetIds.length) return;
  await dnr.updateEnabledRulesets({ enableRulesetIds, disableRulesetIds });
  index = null;
  popups = null;
}

/** Makes Chrome's rules, lists and the badge follow the settings. */
async function apply(settings) {
  await dnr.updateDynamicRules({ removeRuleIds: Object.values(RULE), addRules: userRules(settings) });
  await applyLists(settings);
  // Chrome counts what it blocked on each tab's page and writes it on the
  // icon. With the badge off the count is still kept (the popup reads it)
  // and only drawn in next to no colour: Chrome refuses a text colour of
  // none at all, so it is given the faintest there is, on no background.
  await dnr.setExtensionActionOptions({ displayActionCountAsBadgeText: true });
  await chrome.action.setBadgeBackgroundColor({ color: settings.badge ? [22, 35, 58, 255] : [0, 0, 0, 0] });
  await chrome.action.setBadgeTextColor({ color: settings.badge ? [228, 234, 242, 255] : [0, 0, 0, 1] });
  await applyYouTube(settings);
}

const YOUTUBE = ['youtube.com', 'youtube-nocookie.com'];

/**
 * Keeps the script that runs in YouTube's own pages (content/youtube-main.js)
 * registered only while it is wanted, and never for a YouTube host that
 * is let through. It has to be there before the page's first script, so
 * it can't wait to ask.
 */
async function applyYouTube(settings) {
  const id = 'youtube-main';
  const registered = await chrome.scripting.getRegisteredContentScripts({ ids: [id] });
  if (registered.length) await chrome.scripting.unregisterContentScripts({ ids: [id] });
  if (!settings.youtube || settings.paused) return;
  const script = {
    id,
    js: ['content/youtube-main.js'],
    matches: YOUTUBE.flatMap((host) => [`*://${host}/*`, `*://*.${host}/*`]),
    runAt: 'document_start',
    world: 'MAIN',
    allFrames: true,
  };
  const through = settings.allowlist.filter((site) => YOUTUBE.some((host) => site === host || site.endsWith(`.${host}`)));
  if (through.length) script.excludeMatches = through.flatMap((site) => [`*://${site}/*`, `*://*.${site}/*`]);
  await chrome.scripting.registerContentScripts([script]);
}

/**
 * Puts settings into effect and keeps them. If Chrome refuses any part,
 * what was in effect before is put back and nothing is kept, so what the
 * pages show is always what Chrome is doing.
 */
async function save(settings) {
  const before = await readSettings();
  try {
    await apply(settings);
  } catch (error) {
    await apply(before).catch(() => {});
    throw error;
  }
  await writeSettings(settings);
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

let woken = null;

/**
 * Puts the settings into effect once each time Chrome starts the extension
 * anew: installed, updated, the browser started, or switched off and on
 * again. Chrome forgets the badge's colours and the tabs' icons at every
 * one of those and tells the worker of only some of them. It empties
 * storage.session at all of them, so a mark kept there says whether this
 * has been done since.
 */
function wake() {
  woken ??= inTurn(async () => {
    const { awake } = await chrome.storage.session.get('awake');
    if (awake) return;
    const settings = await readSettings();
    await apply(settings);
    await paintAll(settings);
    await chrome.storage.session.set({ awake: true });
  }).catch(() => {
    woken = null;
  });
  return woken;
}

chrome.runtime.onInstalled.addListener(wake);
chrome.runtime.onStartup.addListener(wake);
wake();

chrome.tabs.onUpdated.addListener(async (tabId, change, tab) => {
  // A tab's own icon is forgotten when it navigates.
  if (change.status === 'loading' || change.url !== undefined) await paint(tabId, tab.url, await readSettings());
});

// ---------------------------------------------------------------------------
// Cosmetic filtering: which elements a page hides.

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
async function hide(sender, selectors, more = '') {
  const css = hidingCSS(selectors) + more;
  if (!css || !sender.tab) return;
  const target = { tabId: sender.tab.id };
  if (sender.documentId) target.documentIds = [sender.documentId];
  else target.frameIds = [sender.frameId ?? 0];
  try {
    await chrome.scripting.insertCSS({ target, css, origin: 'USER' });
  } catch {
    // The document went away before its answer came.
  }
}

/**
 * The host of the page a frame is in: as the frame's own script gave it,
 * or failing that the tab's. The tab's alone would be wrong for a page
 * Chrome loads ahead of a visit, which is in the tab of the page before it.
 */
function pageOf(top, sender) {
  return (typeof top === 'string' && top) || hostOf(sender.tab?.url);
}

/** What cosmetic filtering does for a frame of `host` in a page of `top`. */
async function cosmeticFor(host, top, sender) {
  const settings = await readSettings();
  const page = pageOf(top, sender) || host;
  if (settings.paused || !settings.cosmetic || isAllowed(settings.allowlist, page)) return { active: false, generic: false };
  const lookup = await cosmeticIndex();
  const own = lookup.switches(host);
  const whole = lookup.switches(page);
  return { active: own.cosmetic && whole.cosmetic, generic: own.generic && whole.generic, lookup };
}

// ---------------------------------------------------------------------------
// Pop-ups. No rule of Chrome's can stop a page opening a tab or a window,
// so one opened to an address the lists name as a pop-up ad is closed: at
// once if it is opened straight to that address, or as it gets there if
// it is opened empty or by way of another address.

/** How long a tab a page opened is watched for where it goes. */
const WATCHED = 10_000;
/** Tabs pages have opened: tab id to { opener: the host of the page that opened it, since, settled }. */
const opened = new Map();

/** The pop-up filters of the lists now enabled, read once for as long as the worker lives. */
function popupIndex() {
  popups ??= (async () => {
    const enabled = await dnr.getEnabledRulesets();
    return new Popups(await Promise.all(enabled.map(async (id) => (await fetch(chrome.runtime.getURL(`popups/${id}.json`))).json())));
  })().catch((error) => {
    popups = null;
    throw error;
  });
  return popups;
}

/** Closes a watched tab if the address it is going to is one the lists name. */
async function judge(tabId, url) {
  const tab = opened.get(tabId);
  if (!tab) return;
  if (Date.now() - tab.since > WATCHED) {
    opened.delete(tabId);
    return;
  }
  const settings = await readSettings();
  if (settings.paused || !settings.popups || isAllowed(settings.allowlist, tab.opener)) return;
  if (!(await popupIndex()).closes(url, tab.opener)) return;
  opened.delete(tabId);
  try {
    await chrome.tabs.remove(tabId);
  } catch {
    // It closed by itself meanwhile.
  }
}

chrome.webNavigation.onCreatedNavigationTarget.addListener(async (details) => {
  let source = null;
  try {
    source = await chrome.tabs.get(details.sourceTabId);
  } catch {
    // The tab that opened it has gone.
  }
  const opener = hostOf(source?.url);
  if (!opener) return;
  opened.set(details.tabId, { opener, since: Date.now(), settled: false });
  await judge(details.tabId, details.url);
});

chrome.webNavigation.onBeforeNavigate.addListener((details) => {
  // Until the tab has shown a page of its own, wherever it sets out for is the page's doing.
  if (details.frameId === 0 && opened.get(details.tabId)?.settled === false) judge(details.tabId, details.url);
});

/** Ways of going somewhere that are the person's own doing, not the page's. */
const BY_HAND = new Set(['typed', 'auto_bookmark', 'generated', 'keyword', 'keyword_generated', 'reload', 'start_page']);

chrome.webNavigation.onCommitted.addListener((details) => {
  const tab = opened.get(details.tabId);
  if (details.frameId !== 0 || !tab) return;
  if (BY_HAND.has(details.transitionType) || details.transitionQualifiers.some((how) => how === 'from_address_bar' || how === 'forward_back')) {
    // The person has taken the tab over: it is theirs from here.
    opened.delete(details.tabId);
    return;
  }
  if (hostOf(details.url)) tab.settled = true;
  judge(details.tabId, details.url);
});

chrome.tabs.onRemoved.addListener((tabId) => {
  opened.delete(tabId);
});

// ---------------------------------------------------------------------------
// Messages. Content scripts may only ask what to hide; the rest is for the
// extension's own pages.

const fromPage = {
  /** A document has begun: hide what is written for its site, and say whether to go on looking. */
  async 'cosmetic:start'({ host, top }, sender) {
    const { active, generic, lookup } = await cosmeticFor(String(host), top, sender);
    if (!active) return { active: false, generic: false };
    await hide(sender, lookup.selectorsFor(String(host), { generic }), lookup.stylesFor(String(host)));
    return { active, generic, procedural: lookup.proceduralFor(String(host)) };
  },

  /** A YouTube frame asks whether to get its ads over with. */
  async 'youtube:start'({ top }, sender) {
    const settings = await readSettings();
    const through = isAllowed(settings.allowlist, pageOf(top, sender)) || isAllowed(settings.allowlist, hostOf(sender.url));
    return { active: settings.youtube && !settings.paused && !through };
  },

  /** Classes and ids a document has: hide what the generic filters say of them. */
  async 'cosmetic:tokens'({ host, top, tokens }, sender) {
    if (!Array.isArray(tokens) || tokens.length > 20_000) return {};
    const { generic, lookup } = await cosmeticFor(String(host), top, sender);
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
  // The site that lets this page through may be one above it.
  const through = allowedBy(settings.allowlist, host);
  return {
    host,
    site: siteOf(host),
    through,
    filterable: host !== '',
    allowed: through !== '',
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

  /** Asked in turn, so it is never answered from the middle of a change. */
  async overview() {
    return inTurn(() => overview());
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

  /** Changes the switches: paused, cosmetic, popups, youtube, badge. */
  async 'settings:set'({ patch }) {
    const settings = await inTurn(async () => {
      const kept = await readSettings();
      for (const key of ['paused', 'cosmetic', 'popups', 'youtube', 'badge']) {
        if (typeof patch?.[key] === 'boolean') kept[key] = patch[key];
      }
      await save(kept);
      return kept;
    });
    return { settings };
  },

  /** Turns a filter list on or off. */
  async 'ruleset:set'({ id, enabled }) {
    if (!listIds().includes(id)) return { error: 'There is no such list.' };
    return inTurn(async () => {
      const kept = await readSettings();
      kept.listsOff = listIds().filter((list) => (list === id ? !enabled : kept.listsOff.includes(list)));
      await save(kept);
      return overview();
    });
  },

  /** Back to how Stillwater was installed. */
  async reset() {
    return inTurn(async () => {
      await save({ ...DEFAULTS, allowlist: [], listsOff: [] });
      return overview();
    });
  },
};

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id) return false;
  const own = typeof sender.url === 'string' && sender.url.startsWith(chrome.runtime.getURL(''));
  const handler = (own ? fromExtension[message?.type] : undefined) ?? fromPage[message?.type];
  if (!handler) return false;
  // Not before the settings are in effect: a page asking in the first
  // moment after a start would be told of lists Chrome had just put back.
  wake()
    .then(() => handler(message, sender))
    .then(respond, (error) => respond({ error: String(error?.message ?? error) }));
  return true;
});
