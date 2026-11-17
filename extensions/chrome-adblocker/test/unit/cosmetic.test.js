import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CosmeticIndex, covers, hidingCSS, merged, namesOf } from '../../src/shared/cosmetic-lookup.js';
import { buildCosmetic, keyToken } from '../../tools/lib/cosmetic.js';
import { parseLine } from '../../tools/lib/filters.js';
import { patternSource } from '../../tools/lib/dnr.js';

const build = (lines, hide) => buildCosmetic(lines.map((line) => parseLine(line)), hide);

test('the token a selector cannot match without', () => {
  const tokens = {
    '.ad-box > div': '.ad-box',
    'div#Ad_Top.wide': '#ad_top',
    'div:not(.keep) > .promo': '.promo',
    'a[href*=".ads."]': null,
    '[id^="div-gpt-ad"]': null,
    'div:has(.ad)': null,
    '.a\\:b': null,
    'section.Sponsored-Row': '.sponsored-row',
  };
  for (const [selector, token] of Object.entries(tokens)) assert.equal(keyToken(selector), token, selector);
});

test('generic selectors are sorted into simple, keyed and always', () => {
  const { data, counts } = build(['##.ad-box', '###ad_top', '##.ad-wrap > .inner', '##[id^="div-gpt-ad"]', '##a[href^="https://ads.example/"]', '##.ad-box']);
  assert.deepEqual(data.generic.simple, ['#ad_top', '.ad-box']);
  assert.deepEqual(data.generic.keyed, { '.ad-wrap': ['.ad-wrap > .inner'] });
  assert.deepEqual(data.generic.always, ['[id^="div-gpt-ad"]', 'a[href^="https://ads.example/"]']);
  assert.deepEqual([counts.generic, counts.genericSimple, counts.genericKeyed, counts.genericAlways], [5, 2, 1, 2]);
});

test('selectors for named sites, their exclusions and exceptions', () => {
  const { data } = build(['news.example,blog.example##.promo', 'news.example,~live.news.example##.sidebar-ad', 'google.*###tads', 'shop.example#@#.ad-box', '##.ad-box', '~quiet.example##.banner']);
  assert.deepEqual(data.specific, { 'blog.example': ['.promo'], 'google.*': ['#tads'], 'news.example': ['.promo', '.sidebar-ad'] });
  assert.deepEqual(data.exceptions, { 'live.news.example': ['.sidebar-ad'], 'quiet.example': ['.banner'], 'shop.example': ['.ad-box'] });
  assert.deepEqual(data.generic.simple, ['.ad-box', '.banner']);
});

test('an exception with no site named takes the selector out everywhere', () => {
  const { data } = build(['##.ad-box', '##.sponsor', 'news.example##.sponsor', 'news.example##.promo', 'only.example##.sponsor', '#@#.sponsor']);
  assert.deepEqual(data.generic.simple, ['.ad-box']);
  assert.deepEqual(data.specific, { 'news.example': ['.promo'] });
});

test('the hosts where hiding is off come from the network exceptions', () => {
  const { data } = build(['##.ad'], { elemhide: ['shop.example', 'shop.example'], generichide: ['news.example'] });
  assert.deepEqual([data.noCosmetic, data.noGeneric], [['shop.example'], ['news.example']]);
});

test('the names a host answers to', () => {
  assert.deepEqual(namesOf('www.google.co.uk'), ['www.google.co.uk', 'www.google.co.*', 'www.google.*', 'google.co.uk', 'google.co.*', 'google.*', 'co.uk', 'co.*', 'uk']);
  assert.deepEqual(namesOf('Example.com'), ['example.com', 'example.*', 'com']);
  assert.ok(namesOf('smile.amazon.com.au').includes('amazon.*'));
  // Two labels are a suffix only where they look like one: a name on someone's host is not that name's site.
  assert.equal(namesOf('amazon.shop-host.com').includes('amazon.*'), false);
  assert.equal(namesOf('google.example.io').includes('google.*'), false);
  assert.equal(covers(['example.com'], 'a.b.example.com'), true);
  assert.equal(covers(['b.example.com'], 'example.com'), false);
  assert.equal(covers([], 'example.com'), false);
});

test('a page is given its own selectors and the generic ones that need no token', () => {
  const { data } = build(['##[id^="div-gpt-ad"]', '##.ad-box', 'news.example##.promo', 'google.*###tads', 'news.example#@#[id^="div-gpt-ad"]', 'live.news.example#@#.promo']);
  const index = new CosmeticIndex(data);
  assert.deepEqual(index.selectorsFor('other.example'), ['[id^="div-gpt-ad"]']);
  assert.deepEqual(index.selectorsFor('www.news.example'), ['.promo'], 'its own, and the exception takes the generic one out');
  assert.deepEqual(index.selectorsFor('live.news.example'), []);
  assert.deepEqual(index.selectorsFor('www.google.de').sort(), ['#tads', '[id^="div-gpt-ad"]']);
  assert.deepEqual(index.selectorsFor('www.google.de', { generic: false }), ['#tads']);
});

test('tokens seen on a page call for the generic selectors that need them', () => {
  const { data } = build(['##.ad-box', '###Ad_Top', '##.ad-wrap > .inner', '##.ad-wrap .label', 'shop.example#@#.ad-box']);
  const index = new CosmeticIndex(data);
  assert.deepEqual(index.selectorsForTokens('news.example', ['.ad-box', '.unrelated', '#ad_top']), ['.ad-box', '#Ad_Top']);
  assert.deepEqual(index.selectorsForTokens('news.example', ['.AD-WRAP']).sort(), ['.ad-wrap .label', '.ad-wrap > .inner'], 'case is not held against a token');
  assert.deepEqual(index.selectorsForTokens('www.shop.example', ['.ad-box']), []);
  assert.deepEqual(index.selectorsForTokens('news.example', []), []);
});

test('the switches for a host', () => {
  const index = new CosmeticIndex(build(['##.ad'], { elemhide: ['shop.example'], generichide: ['news.example'] }).data);
  assert.deepEqual(index.switches('www.shop.example'), { cosmetic: false, generic: false });
  assert.deepEqual(index.switches('news.example'), { cosmetic: true, generic: false });
  assert.deepEqual(index.switches('other.example'), { cosmetic: true, generic: true });
});

test('the switches for a page by its address', () => {
  const at = (pattern) => [{ source: patternSource(pattern), caseSensitive: false }];
  const index = new CosmeticIndex(build(['##.ad'], { elemhide: [], generichide: [], generichideAt: at('||www.google.*/search?'), elemhideAt: at('|http://localhost:') }).data);
  assert.deepEqual(index.switches('www.google.com', 'https://www.google.com/search?q=boats'), { cosmetic: true, generic: false }, 'the results');
  assert.deepEqual(index.switches('www.google.com', 'https://www.google.com/maps'), { cosmetic: true, generic: true }, 'another part of the site');
  assert.deepEqual(index.switches('www.google.com'), { cosmetic: true, generic: true }, 'with no address, by host alone');
  assert.deepEqual(index.switches('localhost', 'http://localhost:8080/admin'), { cosmetic: false, generic: false });
  assert.deepEqual(index.switches('localhost', 'https://localhost:8080/admin'), { cosmetic: true, generic: true }, 'the anchor holds the scheme to its word');
  // Through the merge of several lists, as the worker reads them.
  const both = new CosmeticIndex(merged([build(['##.a']).data, build(['##.b'], { elemhide: [], generichide: [], generichideAt: at('||news.example/live/') }).data]));
  assert.equal(both.switches('news.example', 'https://news.example/live/now').generic, false);
  assert.equal(both.switches('news.example', 'https://news.example/today').generic, true);
});

test('the style sheet hides in rules of a few selectors each', () => {
  assert.equal(hidingCSS([]), '');
  assert.equal(hidingCSS(['.a', '#b > c']), '.a,#b > c{display:none!important}\n');
  assert.equal(hidingCSS(['.a', '.b', '.c'], 2), '.a,.b{display:none!important}\n.c{display:none!important}\n');
});

test('lists are merged, and one list\'s exception with no site holds against the others', () => {
  const first = build(['##.ad-box', '##.sponsor', 'news.example##.promo', '##.wrap > .sponsor-row']).data;
  const second = build(['##.banner', 'news.example##.sponsor', 'news.example##.extra', '#@#.sponsor', 'shop.example#@#.ad-box'], { elemhide: ['x.example'], generichide: [] }).data;
  assert.deepEqual(second.never, ['.sponsor']);
  const all = merged([first, second]);
  assert.deepEqual(all.generic.simple, ['.ad-box', '.banner']);
  assert.deepEqual(all.generic.keyed, { '.wrap': ['.wrap > .sponsor-row'] });
  assert.deepEqual(all.specific, { 'news.example': ['.promo', '.extra'] });
  assert.deepEqual(all.exceptions, { 'shop.example': ['.ad-box'] });
  assert.deepEqual(all.noCosmetic, ['x.example']);
  const index = new CosmeticIndex(all);
  assert.deepEqual(index.selectorsForTokens('shop.example', ['.ad-box', '.banner']), ['.banner']);
});

test('plans and styles are kept for their sites, taken back by exceptions, and merged', () => {
  const first = build(['news.example##.card:has-text(Sponsored)', 'news.example,shop.*##li:has(> b:has-text(/^Ad$/))', 'live.news.example#@#.card:has-text(Sponsored)', 'news.example##.nav {top: 0 !important}']);
  assert.deepEqual(Object.keys(first.data.procedural), ['news.example', 'shop.*']);
  assert.deepEqual(first.data.procedural['news.example'].map((plan) => plan.raw), ['.card:has-text(Sponsored)', 'li:has(> b:has-text(/^Ad$/))']);
  assert.deepEqual(first.data.styles, { 'news.example': ['.nav{top:0 !important}'] });
  assert.deepEqual([first.counts.procedural, first.counts.styles], [3, 1]);

  const index = new CosmeticIndex(merged([first.data, build(['blog.example##.post:has-text(Promoted)', '#@#li:has(> b:has-text(/^Ad$/))']).data]));
  assert.deepEqual(index.proceduralFor('www.news.example'), [[{ css: '.card' }, { text: 'Sponsored' }]], 'the other list took the second filter back everywhere');
  assert.deepEqual(index.proceduralFor('live.news.example'), [], 'and the site\'s own exception the first');
  assert.deepEqual(index.proceduralFor('blog.example'), [[{ css: '.post' }, { text: 'Promoted' }]]);
  assert.deepEqual(index.proceduralFor('elsewhere.example'), []);
  assert.equal(index.stylesFor('www.news.example'), '.nav{top:0 !important}');
  assert.equal(index.stylesFor('elsewhere.example'), '');
});
