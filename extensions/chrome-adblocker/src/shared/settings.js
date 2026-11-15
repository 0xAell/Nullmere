// What the user has chosen, kept in chrome.storage.local. Only the service
// worker writes it (so the rules always follow); the pages read it and ask
// the worker for changes.

export const DEFAULTS = Object.freeze({
  /** Sites let through, as sites.js: siteOf() writes them. */
  allowlist: [],
  /** Everything let through, everywhere, until switched back. */
  paused: false,
  /** Hide the slots ads leave (cosmetic filtering). */
  cosmetic: true,
  /** Handle YouTube's own ads as far as an extension can. */
  youtube: true,
  /** Close the tabs and windows pages open to addresses the lists name as pop-up ads. */
  popups: true,
  /** Show the count of what was kept from a page on the toolbar icon. */
  badge: true,
  /**
   * Filter lists switched off, by ruleset id. Chrome remembers which
   * rulesets are enabled only until the extension is next updated, and
   * then goes back to the manifest's; this is what the user chose.
   */
  listsOff: [],
});

const KEY = 'settings';

export async function readSettings() {
  const stored = (await chrome.storage.local.get(KEY))[KEY] ?? {};
  const settings = { ...DEFAULTS, ...stored };
  for (const key of ['allowlist', 'listsOff']) {
    settings[key] = Array.isArray(settings[key]) ? settings[key].filter((item) => typeof item === 'string') : [];
  }
  return settings;
}

export async function writeSettings(settings) {
  await chrome.storage.local.set({ [KEY]: settings });
}
