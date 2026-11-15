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
  /** Show the count of what was kept from a page on the toolbar icon. */
  badge: true,
});

const KEY = 'settings';

export async function readSettings() {
  const stored = (await chrome.storage.local.get(KEY))[KEY] ?? {};
  const settings = { ...DEFAULTS, ...stored };
  settings.allowlist = Array.isArray(settings.allowlist) ? settings.allowlist.filter((site) => typeof site === 'string') : [];
  return settings;
}

export async function writeSettings(settings) {
  await chrome.storage.local.set({ [KEY]: settings });
}
