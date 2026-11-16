import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { patternMatcher } from '../../src/shared/patterns.js';
import { Popups, siteName } from '../../src/shared/popups.js';
import { parseLine, parseList } from '../../tools/lib/filters.js';
import { buildPopups } from '../../tools/lib/popups.js';

/**
 * The plain reading of a pattern as a regular expression, kept here only
 * to hold the matcher to: it means the same, but can be made to take
 * seconds on an address built for it.
 */
function patternSource(pattern) {
  let rest = pattern;
  let source = '';
  let end = '';
  if (rest.startsWith('||')) {
    source = '^[a-z][a-z0-9+.-]*:\\/\\/(?:[^/?#]*\\.)?';
    rest = rest.slice(2);
  } else if (rest.startsWith('|')) {
    source = '^';
    rest = rest.slice(1);
  }
  if (rest.endsWith('|')) {
    end = '$';
    rest = rest.slice(0, -1);
  }
  for (const c of rest) {
    if (c === '*') source += '.*';
    else if (c === '^') source += '(?:[^\\w.%-]|$)';
    else source += /[\w-]/.test(c) ? c : `\\${c}`;
  }
  return source + end;
}

/** The pop-up data of filter lines, and the matcher over it. */
function popups(...lines) {
  const built = buildPopups(lines.map((line) => parseLine(line)).filter((filter) => filter.popup));
  return { ...built, match: new Popups([built.data]) };
}

test('an Adblock Plus pattern matches the addresses it means', () => {
  const matches = (pattern, url) => patternMatcher(pattern)(url);
  // `||`: the host or any subdomain of it, and nothing that only ends alike.
  assert.equal(matches('||ads.example^', 'https://ads.example/x'), true);
  assert.equal(matches('||ads.example^', 'http://cdn.ads.example:8080/x'), true);
  assert.equal(matches('||ads.example^', 'https://badads.example/x'), false);
  assert.equal(matches('||ads.example^', 'https://ads.example.evil.test/x'), false);
  assert.equal(matches('||ads.example^', 'https://site.test/?u=https://ads.example/'), false);
  // `^`: a separator, or the end of the address.
  assert.equal(matches('/pop.php^', 'https://x.test/pop.php'), true);
  assert.equal(matches('/pop.php^', 'https://x.test/pop.php?zone=1'), true);
  assert.equal(matches('/pop.php^', 'https://x.test/pop.php5'), false);
  // `*`, and the ends of the address.
  assert.equal(matches('/go/*&popunder=', 'https://x.test/go/now?a=1&popunder=1'), true);
  assert.equal(matches('|https://x.test/out|', 'https://x.test/out'), true);
  assert.equal(matches('|https://x.test/out|', 'https://x.test/out/more'), false);
  // Everything else is itself: a dot is not any character.
  assert.equal(matches('/ad.php?zone', 'https://x.test/ad.php?zone=3'), true);
  assert.equal(matches('/ad.php?zone', 'https://x.test/adxphp?zone=3'), false);
});

test('hosts named whole are a set; the rest keep what narrows them; exceptions are kept apart', () => {
  const { data, count, dropped } = popups(
    '||pop.example^$popup',
    '||other.example^$popup',
    '||other.example^$popup',
    '||third.example^$popup,third-party',
    '/ad.php?zone$popup,domain=news.example|~live.news.example',
    '@@||pop.example/account/$popup',
    '/^https?:\\/\\/[a-z]{8}\\.top\\//$popup',
    '||ads.example^$popup,script',
    '$popup',
    '||x.example^$popup,to=y.example',
    '/(unclosed/$popup',
  );
  assert.deepEqual(data.hosts, ['ads.example', 'other.example', 'pop.example']);
  assert.deepEqual(data.patterns, [
    { pattern: '||third.example^', third: true },
    { pattern: '/ad.php?zone', on: ['news.example'], notOn: ['live.news.example'] },
    { re: '^https?:\\/\\/[a-z]{8}\\.top\\/' },
  ]);
  assert.deepEqual(data.exceptions, [{ pattern: '||pop.example/account/' }]);
  assert.equal(count, 8, 'every filter taken is counted, written twice or not');
  assert.deepEqual([...dropped].sort(), [['popup:option', 1], ['popup:regex', 1], ['popup:too-broad', 1]]);
});

test('a tab a page opens is closed where the lists name its address, and nowhere else', () => {
  const { match } = popups(
    '||pop.example^$popup',
    '||third.example^$popup,third-party',
    '/ad.php?zone$popup,domain=news.example|~live.news.example',
    '&popunder=$popup',
    '@@||pop.example/account/$popup',
    '@@||partner.example^$popup,domain=shop.example',
    '||partner.example^$popup',
  );
  const closes = (url, opener = 'site.example') => match.closes(url, opener);
  assert.equal(closes('https://pop.example/'), true);
  assert.equal(closes('http://cdn.pop.example/landing?x=1'), true, 'its subdomains with it');
  assert.equal(closes('https://notpop.example/'), false);
  assert.equal(closes('https://harmless.example/page'), false);
  // An exception for some of a host's addresses.
  assert.equal(closes('https://pop.example/account/login'), false);
  // third-party: of another site than the page that opened it.
  assert.equal(closes('https://third.example/', 'site.example'), true);
  assert.equal(closes('https://third.example/', 'www.third.example'), false);
  // domain=: only from the pages named, and not from one excluded.
  assert.equal(closes('https://x.example/ad.php?zone=1', 'news.example'), true);
  assert.equal(closes('https://x.example/ad.php?zone=1', 'www.news.example'), true);
  assert.equal(closes('https://x.example/ad.php?zone=1', 'live.news.example'), false);
  assert.equal(closes('https://x.example/ad.php?zone=1', 'other.example'), false);
  // A pattern anywhere in the address, whatever its case.
  assert.equal(closes('https://x.example/go?a=1&PopUnder=1'), true);
  // An exception for one site's pages only.
  assert.equal(closes('https://partner.example/', 'shop.example'), false);
  assert.equal(closes('https://partner.example/', 'site.example'), true);
  // Only addresses of the web are judged.
  for (const url of ['about:blank', '', 'chrome://newtab/', 'data:text/html,x', 'not an address']) assert.equal(closes(url), false, url);
});

test('a filter that would close every tab a page opens is not taken unless it says whose pages it is for', () => {
  const { data, count, dropped } = popups('|*|$popup', '/$popup', '|http$popup', '/^https?:/$popup', '*$popup,third-party', '|http*://*?$popup,domain=tracker.example', '$popup,third-party,domain=tracker.example', '@@|http$popup');
  assert.deepEqual(data.hosts, []);
  assert.deepEqual(data.patterns.map((entry) => entry.on), [['tracker.example'], ['tracker.example']], 'the two that name a site are kept');
  assert.equal(data.exceptions.length, 1, 'an exception may be as wide as it likes');
  assert.equal(count, 3);
  assert.deepEqual([...dropped], [['popup:too-broad', 5]]);
});

test('an address however long is judged by every filter, and quickly', () => {
  const { match } = popups(
    '||pop.example^$popup',
    '&sseq=*&dseq=$popup',
    '||padded.example^$popup,third-party',
    '@@||pop.example/account/$popup',
    '@@||www.google.*/search?q=*&oq=*&aqs=chrome.*&sourceid=chrome&$popup,third-party',
  );
  const padding = (piece, length) => piece.repeat(Math.ceil(length / piece.length)).slice(0, length);
  const began = performance.now();
  // Padding an address does not take it out of a filter's reach.
  assert.equal(match.closes(`https://padded.example/click?${padding('x', 5_000)}`, 'site.example'), true);
  assert.equal(match.closes(`https://other.example/?${padding('&sseq=', 400_000)}&dseq=1`, 'site.example'), true);
  assert.equal(match.closes(`https://other.example/?${padding('&sseq=', 400_000)}`, 'site.example'), false);
  assert.equal(match.closes(`https://pop.example/account/?${padding('a', 400_000)}`, 'site.example'), false, 'an exception holds however long');
  // An address built against an exception with four wildcards, two megabytes of it.
  assert.equal(match.closes(`https://www.google.pop.example/search?${padding('q=&oq=&aqs=chrome.', 2_000_000)}`, 'site.example'), true);
  assert.ok(performance.now() - began < 1_500, `in well under the seconds an expression would take: ${Math.round(performance.now() - began)} ms`);
});

test('the matcher means what the plain reading of every pop-up pattern in EasyList means', () => {
  // Addresses made from each pattern, so most should match, and the same spoilt.
  const list = parseList(readFileSync(new URL('../../lists/easylist.txt', import.meta.url), 'utf8'));
  const patterns = [...new Set(list.popups.filter((filter) => !filter.regex && filter.pattern).map((filter) => filter.pattern))];
  assert.ok(patterns.length > 2_000, 'the real list was read');
  const ordinary = ['https://example.com/', 'http://news.example.org/story/42?a=1&b=2', 'https://cdn.example.net/ad.php?zone=7&id=3#x'];
  let compared = 0;
  let matched = 0;
  for (const pattern of patterns) {
    const made = pattern
      .replace(/^\|\|/, 'https://sub.')
      .replace(/^\|/, '')
      .replace(/\|$/, '')
      .replaceAll('*', 'x/y')
      .replaceAll('^', '/');
    const addresses = [made, made.replaceAll('/', 'a'), `${made}tail`, `https://other.example/?u=${made}`, ...ordinary];
    const reading = new RegExp(patternSource(pattern), 'i');
    const matcher = patternMatcher(pattern);
    for (const url of addresses) {
      assert.equal(matcher(url), reading.test(url), `${pattern} on ${url}`);
      compared++;
      if (reading.test(url)) matched++;
    }
  }
  assert.ok(matched > patterns.length, `enough of them matched to mean something: ${matched} of ${compared}`);
});

test('lists are read together: an exception in one holds against the others', () => {
  const first = buildPopups([parseLine('||pop.example^$popup')]).data;
  const second = buildPopups([parseLine('@@||pop.example^$popup')]).data;
  assert.equal(new Popups([first]).closes('https://pop.example/', 'site.example'), true);
  assert.equal(new Popups([first, second]).closes('https://pop.example/', 'site.example'), false);
  assert.equal(new Popups([]).closes('https://pop.example/', 'site.example'), false);
  // Data with an expression this browser can't read loses that one filter, not the rest.
  const broken = new Popups([{ hosts: ['pop.example'], patterns: [{ re: '(' }, { re: 'popunder' }], exceptions: [] }]);
  assert.equal(broken.closes('https://x.example/popunder', 'site.example'), true);
});

test('the site a host belongs to, for telling a pop-up of the same site from another\'s', () => {
  assert.equal(siteName('www.shop.example.com'), 'example.com');
  assert.equal(siteName('shop.example.co.uk'), 'example.co.uk');
  assert.equal(siteName('example.com'), 'example.com');
  assert.equal(siteName('localhost'), 'localhost');
  assert.equal(siteName('192.168.1.20'), '192.168.1.20');
  assert.equal(siteName(''), '');
});
