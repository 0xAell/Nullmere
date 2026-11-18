// The service worker: keeps Chrome's rules in step with what the user has
// chosen, chooses what each page hides, and answers the popup and the
// options page. It holds nothing that can't be made again: Chrome stops it
// when idle and starts it afresh for the next event.

import { parseLine } from '../lib/filters.js';
import { OWN_FIRST_ID, OWN_MOST_LETTERS, readOwn } from '../lib/own.js';
import { CosmeticIndex, hidingCSS, merged } from '../shared/cosmetic-lookup.js';
import { Popups } from '../shared/popups.js';
import { DEFAULTS, readSettings, writeSettings } from '../shared/settings.js';
import { allowedBy, hostOf, isAllowed, RULE, siteFromInput, siteOf, userRules, withSite } from '../shared/sites.js';

const dnr = chrome.declarativeNetRequest;

const ICONS = {
  on: { 16: '/icons/icon-16.png', 32: '/icons/icon-32.png', 48: '/icons/icon-48.png' },
  off: { 16: '/icons/off-16.png', 32: '/icons/off-32.png', 48: '/icons/off-48.png' },
};

/** What the enabled lists and one's own filters hide, once it has been read; null whenever either changes. */
let index = null;
/** One's own filters as last read, by their text. */
let own = null;
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

/**
 * One's own filters, read as the build reads a list (lib/own.js), each
 * regular expression in them first asked of Chrome, which alone knows
 * which it can use.
 */
async function ownFilters(text) {
  if (own?.text === text) return own.value;
  let value = readOwn(text);
  // Each expression asked of Chrome; one it refuses is read again as its
  // alternatives (tools/lib/dnr.js), which are asked in their turn.
  const refused = new Set();
  const asked = new Set();
  for (let round = 0; round < 4; round++) {
    let more = false;
    for (const rule of value.rules) {
      const regex = rule.condition.regexFilter;
      if (!regex || asked.has(regex)) continue;
      asked.add(regex);
      const { isSupported } = await dnr.isRegexSupported({ regex, isCaseSensitive: Boolean(rule.condition.isUrlFilterCaseSensitive) });
      if (!isSupported) {
        refused.add(regex);
        more = true;
      }
    }
    if (!more) break;
    value = readOwn(text, { rejectedRegex: [...refused] });
  }
  own = { text, value };
  return value;
}

/** Makes Chrome's rules, lists and the badge follow the settings. */
async function apply(settings) {
  const mine = await ownFilters(settings.own);
  const kept = (await dnr.getDynamicRules()).map((rule) => rule.id).filter((id) => id >= OWN_FIRST_ID);
  await dnr.updateDynamicRules({ removeRuleIds: [...Object.values(RULE), ...kept], addRules: [...userRules(settings), ...mine.rules] });
  await applyLists(settings);
  // Chrome counts what it blocked on each tab's page and writes it on the
  // icon. With the badge off the count is still kept (the popup reads it)
  // and only drawn in next to no colour: Chrome refuses a text colour of
  // none at all, so it is given the faintest there is, on no background.
  await dnr.setExtensionActionOptions({ displayActionCountAsBadgeText: true });
  await chrome.action.setBadgeBackgroundColor({ color: settings.badge ? [22, 35, 58, 255] : [0, 0, 0, 0] });
  await chrome.action.setBadgeTextColor({ color: settings.badge ? [228, 234, 242, 255] : [0, 0, 0, 1] });
  await applyYouTube(settings);
  await applyScriptlets(settings);
}

/**
 * Keeps the scriptlets of the lists that are on registered with Chrome,
 * each for the sites its filter names (scriptlets/<list>.json, made by
 * the build), in the page's own world before its first script: never
 * while paused, and never for a site let through. Chrome keeps them
 * registered between sessions; they are brought to the settings in place
 * whenever these change.
 */
async function applyScriptlets(settings) {
  const ours = (id) => id.startsWith('scriptlet-');
  if (settings.paused) return keepRegistered(ours, []);
  const off = new Set(settings.listsOff);
  const through = settings.allowlist.flatMap((site) => [`*://${site}/*`, `*://*.${site}/*`]);
  const plans = await Promise.all(listIds().filter((id) => !off.has(id)).map(async (id) => (await fetch(chrome.runtime.getURL(`scriptlets/${id}.json`))).json()));
  const scripts = plans.flat().map((script) => {
    const excluded = [...(script.excludeMatches ?? []), ...through];
    return { ...script, excludeMatches: excluded, runAt: 'document_start', allFrames: true, world: 'MAIN' };
  });
  await keepRegistered(ours, scripts);
}

const YOUTUBE = ['youtube.com', 'youtube-nocookie.com'];

/**
 * Keeps the two scripts for YouTube registered only while they are
 * wanted, and never for a YouTube host that is let through: the one in
 * the page's own world (content/youtube-main.js), which has to be there
 * before the page's first script and so can't wait to ask, and the
 * extension's own beside it (content/youtube.js). They are always there
 * together or not at all, so neither is ever left waiting for the other
 * where a page could notice; and with YouTube switched off nothing of
 * the extension runs in YouTube's pages but what hides ad slots.
 */
async function applyYouTube(settings) {
  const ids = ['youtube-main', 'youtube'];
  if (!settings.youtube || settings.paused) return keepRegistered((id) => ids.includes(id), []);
  const where = {
    matches: YOUTUBE.flatMap((host) => [`*://${host}/*`, `*://*.${host}/*`]),
    runAt: 'document_start',
    allFrames: true,
    // A frame with no address of its own inside YouTube has its own copy
    // of what the first script wraps, and is given the scripts too.
    matchOriginAsFallback: true,
  };
  const through = settings.allowlist.filter((site) => YOUTUBE.some((host) => site === host || site.endsWith(`.${host}`)));
  where.excludeMatches = through.flatMap((site) => [`*://${site}/*`, `*://*.${site}/*`]);
  await keepRegistered((id) => ids.includes(id), [
    { ...where, id: 'youtube-main', js: ['content/youtube-main.js'], world: 'MAIN' },
    { ...where, id: 'youtube', js: ['content/youtube.js'], world: 'ISOLATED' },
  ]);
}

/**
 * Makes the registered content scripts whose ids `ours` claims be those
 * wanted, with no moment when one wanted is missing: each already
 * registered is updated in place (Chrome keeps them between sessions, so
 * at a browser's start they are there as its first tabs load), the new are
 * registered, and only those no longer wanted are let go. Each wanted
 * script says every field it sets, an empty list among them, as an update
 * keeps whatever it does not say.
 */
async function keepRegistered(ours, wanted) {
  const registered = new Set((await chrome.scripting.getRegisteredContentScripts()).map((script) => script.id).filter(ours));
  const kept = wanted.filter((script) => registered.has(script.id));
  const fresh = wanted.filter((script) => !registered.has(script.id));
  const gone = [...registered].filter((id) => !wanted.some((script) => script.id === id));
  if (kept.length) await chrome.scripting.updateContentScripts(kept);
  if (fresh.length) await chrome.scripting.registerContentScripts(fresh);
  if (gone.length) await chrome.scripting.unregisterContentScripts({ ids: gone });
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
    await writeSettings(settings);
  } catch (error) {
    await apply(before).catch(() => {});
    throw error;
  }
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

chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  // A tab's own icon is forgotten when it navigates.
  if (change.status === 'loading' || change.url !== undefined) {
    readSettings()
      .then((settings) => paint(tabId, tab.url, settings))
      .catch(() => {});
  }
});

// ---------------------------------------------------------------------------
// Cosmetic filtering: which elements a page hides.

/** The cosmetic data of the lists now enabled and of one's own filters, read once for as long as the worker lives. */
function cosmeticIndex() {
  index ??= (async () => {
    const enabled = await dnr.getEnabledRulesets();
    const lists = await Promise.all(enabled.map(async (id) => (await fetch(chrome.runtime.getURL(`cosmetic/${id}.json`))).json()));
    const mine = await ownFilters((await readSettings()).own);
    const lookup = new CosmeticIndex(merged([...lists, mine.cosmetic]));
    lookup.own = mine.selectors;
    return lookup;
  })().catch((error) => {
    index = null;
    throw error;
  });
  return index;
}

/**
 * Adds a style sheet to the document that asked. As the user's own, so a
 * page's `!important` can't undo it. The selectors of one's own filters,
 * which no Chromium has read before, are each written in a rule of their
 * own: one Chrome can't read loses only itself.
 */
async function hide(sender, selectors, more = '', own = new Set()) {
  const css = hidingCSS(selectors.filter((selector) => !own.has(selector))) + hidingCSS(selectors.filter((selector) => own.has(selector)), 1) + more;
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
  // By host, and by address: the frame's own, and the page's it is in.
  const own = lookup.switches(host, sender?.url);
  const whole = lookup.switches(page, sender?.frameId === 0 ? sender.url : sender?.tab?.url);
  return { active: own.cosmetic && whole.cosmetic, generic: own.generic && whole.generic, lookup };
}

// ---------------------------------------------------------------------------
// Pop-ups. No rule of Chrome's can stop a page opening a tab or a window,
// so one opened to an address the lists name as a pop-up ad is closed: at
// once if it is opened straight to that address, or as it gets there if
// it is opened empty or by way of another address.

/** How long a tab a page opened is watched for where it goes. */
const WATCHED = 10_000;
/** Tabs pages have opened: tab id to { opener: the host of the page that opened it, since, settled, shown: when it first showed a page }. */
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

/** Closes a watched tab if the address it is going to is one the lists name. A failure here closes nothing. */
function judge(tabId, url) {
  return judged(tabId, url).catch(() => {});
}

async function judged(tabId, url) {
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
  opened.set(details.tabId, { opener, since: Date.now(), settled: false, shown: 0 });
  openers.set(details.sourceTabId, { opener, page: source.url, since: Date.now() });
  // The address a page opens a tab to is the page's doing. Wherever the
  // tab goes after that is judged as it arrives, when Chrome says how it
  // came to go there: an address typed into a tab still empty is not.
  await judge(details.tabId, details.url);
});

/** Ways of going somewhere that are the person's own doing, not the page's. */
const BY_HAND = new Set(['typed', 'auto_bookmark', 'generated', 'keyword', 'keyword_generated', 'reload', 'start_page']);

/**
 * How long after an opened tab first shows a page a move it makes is
 * still taken for the page's doing. A page that means to send its tab on
 * does it at once; a person reads before they press a link, and Chrome
 * does not say which of the two it was.
 */
const SENT_ON = 2_000;

chrome.webNavigation.onCommitted.addListener((details) => {
  const tab = opened.get(details.tabId);
  if (details.frameId !== 0 || !tab) return;
  const how = details.transitionQualifiers;
  const byHand = BY_HAND.has(details.transitionType) || how.includes('from_address_bar') || how.includes('forward_back');
  // Once the tab has shown a page for a while, a move is the page's doing
  // only where Chrome says the page made it. A server's redirect belongs
  // to whoever began the navigation, which by then is the person.
  const sentOnByPage = how.includes('client_redirect');
  const lingered = tab.settled && Date.now() - tab.shown > SENT_ON;
  if (byHand || (lingered && !sentOnByPage)) {
    // The person has taken the tab over: it is theirs from here.
    opened.delete(details.tabId);
    return;
  }
  if (hostOf(details.url) && !tab.settled) {
    tab.settled = true;
    tab.shown = Date.now();
  }
  judge(details.tabId, details.url);
});

// A page that opens what was asked for in a new tab and sends its own tab
// to an ad (a "tab-under"): the tab it sends there is put back on the page
// it was showing, so the ad is gone and the person has both: the page they
// were on, and what they asked for in the new tab.

/** How long after a page opens a tab its own tab going to a pop-up address is taken for that. */
const UNDER = 3_000;
/** Tabs whose pages have just opened another: tab id to { opener: the page's host, page: its address, since }. */
const openers = new Map();

chrome.webNavigation.onCommitted.addListener((details) => {
  const source = openers.get(details.tabId);
  if (details.frameId !== 0 || !source) return;
  const how = details.transitionQualifiers;
  if (BY_HAND.has(details.transitionType) || how.includes('from_address_bar') || how.includes('forward_back') || Date.now() - source.since > UNDER) {
    openers.delete(details.tabId);
    return;
  }
  takeBack(details.tabId, details.url, source).catch(() => {});
});

/** Puts a tab its page sent to a pop-up address back on that page. A failure here changes nothing. */
async function takeBack(tabId, url, source) {
  const settings = await readSettings();
  if (settings.paused || !settings.popups || isAllowed(settings.allowlist, source.opener)) return;
  if (!(await popupIndex()).closes(url, source.opener)) return;
  openers.delete(tabId);
  await chrome.tabs.update(tabId, { url: source.page });
}

chrome.tabs.onRemoved.addListener((tabId) => {
  opened.delete(tabId);
  openers.delete(tabId);
});

// ---------------------------------------------------------------------------
// Messages. Content scripts may only ask what to hide; the rest is for the
// extension's own pages.

const fromPage = {
  /** A document has begun: hide what is written for its site, and say whether to go on looking. */
  async 'cosmetic:start'({ host, top }, sender) {
    const { active, generic, lookup } = await cosmeticFor(String(host), top, sender);
    if (!active) return { active: false, generic: false };
    await hide(sender, lookup.selectorsFor(String(host), { generic }), lookup.stylesFor(String(host)), lookup.own);
    return { active, generic, procedural: lookup.proceduralFor(String(host)) };
  },

  /** A YouTube frame asks whether to get its ads over with. */
  async 'youtube:start'({ top }, sender) {
    const settings = await readSettings();
    const through = isAllowed(settings.allowlist, pageOf(top, sender)) || isAllowed(settings.allowlist, hostOf(sender.url));
    return { active: settings.youtube && !settings.paused && !through };
  },

  /**
   * The picker, started from the popup in this tab, keeps what was picked
   * as one of your own filters for the site the page is on (by the
   * frame's own address, never the page's word), and hides it at once.
   * Only a plain selector, and only from the tab the picker was started
   * in, once.
   */
  async 'picker:hide'({ selector }, sender) {
    const { picking } = await chrome.storage.session.get('picking');
    if (!sender.tab || sender.tab.id !== picking) return { error: 'Start the picker from Stillwater\'s popup.' };
    const site = siteOf(hostOf(sender.url));
    if (!site || typeof selector !== 'string' || !selector || selector.length > 500) return { error: 'There is nothing to keep.' };
    const line = `${site}##${selector}`;
    const filter = parseLine(line);
    if (filter.kind !== 'cosmetic' || filter.exception || filter.procedural || filter.styles || filter.selectors.length !== 1 || filter.selectors[0] !== selector) {
      return { error: 'That is not a selector Stillwater can keep.' };
    }
    await chrome.storage.session.remove('picking');
    await inTurn(async () => {
      const kept = await readSettings();
      kept.own = kept.own === '' || kept.own.endsWith('\n') ? `${kept.own}${line}` : `${kept.own}\n${line}`;
      await save(kept);
      index = null;
    });
    await hide(sender, [selector], '', new Set([selector]));
    return { line };
  },

  /** Classes and ids a document has: hide what the generic filters say of them. */
  async 'cosmetic:tokens'({ host, top, tokens }, sender) {
    if (!Array.isArray(tokens) || tokens.length > 20_000) return {};
    const { generic, lookup } = await cosmeticFor(String(host), top, sender);
    if (generic) await hide(sender, lookup.selectorsForTokens(String(host), tokens), '', lookup.own);
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
  const mine = await ownFilters(settings.own);
  return {
    settings,
    enabled,
    available,
    lists,
    version: chrome.runtime.getManifest().version,
    own: { taken: mine.taken, rules: mine.rules.length, hidden: mine.selectors.size, refused: mine.refused },
  };
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

  /** Puts the picker into the page in a tab, to choose something there to hide. */
  async 'picker:start'({ tabId }) {
    if (!Number.isInteger(tabId)) return { error: 'There is no page to pick from.' };
    await chrome.storage.session.set({ picking: tabId });
    await chrome.scripting.executeScript({ target: { tabId }, files: ['content/picker.js'] });
    return { started: true };
  },

  /** Keeps one's own filters, and puts them into effect. */
  async 'own:set'({ text }) {
    if (typeof text !== 'string') return { error: 'There are no filters to keep.' };
    if (text.length > OWN_MOST_LETTERS) return { error: `That is more than ${OWN_MOST_LETTERS.toLocaleString('en-US')} letters of filters.` };
    return inTurn(async () => {
      const kept = await readSettings();
      kept.own = text;
      await save(kept);
      index = null;
      return overview();
    });
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
      index = null;
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
