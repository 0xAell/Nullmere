// The stand-ins a filter may have a request given instead of what it asked
// for ($redirect=, $rewrite=abp-resource:), by every name the lists call
// them: uBlock Origin's names and their aliases, and Adblock Plus's. Each is
// a file of the extension's own, in src/redirects/, written for it.

/** A stand-in's file in src/redirects/ by each name a filter may give it. */
export const REDIRECTS = {
  'noop.js': 'noop.js',
  noopjs: 'noop.js',
  'blank-js': 'noop.js',
  'noop.txt': 'noop.txt',
  nooptext: 'noop.txt',
  'blank-text': 'noop.txt',
  'noop.json': 'noop.json',
  noopjson: 'noop.json',
  '1x1.gif': '1x1.gif',
  '1x1-transparent.gif': '1x1.gif',
  '1x1-transparent-gif': '1x1.gif',
  'noop-1s.mp4': 'noop.mp4',
  noopmp4: 'noop.mp4',
  'noopmp4-1s': 'noop.mp4',
  'blank-mp4': 'noop.mp4',
  'chartbeat.js': 'chartbeat.js',
  'googletagmanager_gtm.js': 'googletagmanager_gtm.js',
  'googletagmanager.com/gtm.js': 'googletagmanager_gtm.js',
  'fingerprint2.js': 'fingerprint2.js',
};

/** Where the stand-ins are, as a redirect rule names an extension's file. */
export const REDIRECT_DIRECTORY = '/redirects/';

/**
 * The file a filter's stand-in is, from what `$redirect=` or `$rewrite=`
 * says: none for a name Stillwater has no stand-in for. A redirect's
 * priority among others (`noop.js:10`) is not Chrome's to weigh, and goes.
 */
export function redirectFile(option, value) {
  let name = value.trim();
  if (option === 'rewrite') {
    if (!name.startsWith('abp-resource:')) return null;
    name = name.slice('abp-resource:'.length);
  } else {
    name = name.replace(/:\d+$/, '');
  }
  return Object.hasOwn(REDIRECTS, name) ? REDIRECTS[name] : null;
}
