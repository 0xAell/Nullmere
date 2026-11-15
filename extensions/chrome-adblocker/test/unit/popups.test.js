import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Popups, siteName } from '../../src/shared/popups.js';
import { parseLine } from '../../tools/lib/filters.js';
import { buildPopups, patternSource } from '../../tools/lib/popups.js';

/** The pop-up data of filter lines, and the matcher over it. */
function popups(...lines) {
  const built = buildPopups(lines.map((line) => parseLine(line)).filter((filter) => filter.popup));
  return { ...built, match: new Popups([built.data]) };
}

test('an Adblock Plus pattern becomes an expression for the same addresses', () => {
  const matches = (pattern, url) => new RegExp(patternSource(pattern), 'i').test(url);
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
    { re: patternSource('||third.example^'), third: true },
    { re: patternSource('/ad.php?zone'), on: ['news.example'], notOn: ['live.news.example'] },
    { re: '^https?:\\/\\/[a-z]{8}\\.top\\/' },
  ]);
  assert.deepEqual(data.exceptions, [{ re: patternSource('||pop.example/account/') }]);
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
