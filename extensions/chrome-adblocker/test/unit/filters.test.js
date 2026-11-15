import assert from 'node:assert/strict';
import { test } from 'node:test';
import { hostname, isBalanced, isContained, parseLine, parseList, splitSelectors } from '../../tools/lib/filters.js';

test('comments, headers and blank lines are nothing', () => {
  for (const line of ['', '   ', '! a comment', '[Adblock Plus 2.0]', '# hosts comment']) {
    assert.ok(['blank', 'comment'].includes(parseLine(line).kind), line);
  }
});

test('a blocking filter keeps its pattern and has the default types', () => {
  const filter = parseLine('||Ads.Example.com^');
  assert.equal(filter.kind, 'network');
  assert.equal(filter.exception, false);
  assert.equal(filter.pattern, '||ads.example.com^', 'lower case unless match-case');
  assert.deepEqual([filter.types, filter.notTypes, filter.thirdParty, filter.domains], [[], [], null, null]);
});

test('options: types, their aliases and exclusions', () => {
  assert.deepEqual(parseLine('/banner.$script,image,~stylesheet').types, ['image', 'script']);
  assert.deepEqual(parseLine('/banner.$script,image,~stylesheet').notTypes, ['stylesheet']);
  assert.deepEqual(parseLine('/x.$xhr,frame,css,doc,beacon').types, ['main_frame', 'ping', 'stylesheet', 'sub_frame', 'xmlhttprequest']);
  assert.deepEqual(parseLine('/x.$subdocument,xmlhttprequest').types, ['sub_frame', 'xmlhttprequest']);
});

test('options: party, case, domains, important', () => {
  const filter = parseLine('@@||cdn.example/Ad.js$script,third-party,match-case,domain=a.example|B.example|~x.a.example,important');
  assert.equal(filter.exception, true);
  assert.equal(filter.thirdParty, true);
  assert.equal(filter.matchCase, true);
  assert.equal(filter.pattern, '||cdn.example/Ad.js', 'case kept with match-case');
  assert.deepEqual(filter.domains, { include: ['a.example', 'b.example'], exclude: ['x.a.example'] });
  assert.equal(filter.important, true);
  assert.equal(parseLine('||x.example^$~third-party').thirdParty, false);
  assert.equal(parseLine('||x.example^$1p').thirdParty, false);
  assert.equal(parseLine('||x.example^$3p').thirdParty, true);
});

test('options: to, denyallow and method', () => {
  assert.deepEqual(parseLine('*$script,to=a.example|~b.a.example,domain=site.example').to, { include: ['a.example'], exclude: ['b.a.example'] });
  assert.deepEqual(parseLine('*$script,denyallow=cdn.example,domain=site.example').to, { include: [], exclude: ['cdn.example'] });
  assert.deepEqual(parseLine('||x.example^$method=post|get').methods, ['post', 'get']);
});

test('a filter between slashes is a regular expression, its case kept', () => {
  const filter = parseLine('/^https?:\\/\\/[a-z]{8}\\.example\\/Ad/$script,third-party');
  assert.equal(filter.regex, true);
  assert.equal(filter.pattern, '^https?:\\/\\/[a-z]{8}\\.example\\/Ad');
  assert.deepEqual(filter.types, ['script']);
});

test('csp, and the exceptions that turn hiding off', () => {
  assert.equal(parseLine("||site.example^$csp=script-src 'self' *.cdn.example").csp, "script-src 'self' *.cdn.example");
  assert.equal(parseLine('@@||site.example^$csp').csp, '');
  const hide = parseLine('@@||site.example^$generichide');
  assert.deepEqual([hide.exception, hide.generichide, hide.elemhide], [true, true, false]);
  assert.equal(parseLine('@@||site.example^$elemhide').elemhide, true);
  assert.equal(parseLine('||site.example^$elemhide').kind, 'unsupported', 'only an exception may turn hiding off');
});

test('what Chrome cannot express is refused with its reason', () => {
  const reasons = {
    '||ads.example^$webrtc': 'option:webrtc',
    '||ads.example^$rewrite=abp-resource:blank-js': 'option:rewrite',
    '||ads.example^$redirect=noop.js': 'option:redirect',
    '||ads.example^$removeparam=utm_source': 'option:removeparam',
    '@@||ads.example^$genericblock': 'option:genericblock',
    '||ads.example^$sitekey=abc': 'option:sitekey',
    '||ads.example^$domain=google.*': 'option:domain-entity',
    // Leaving an excluded entity out would block on sites the filter spares.
    '||ads.example^$domain=news.example|~google.*': 'option:domain-entity',
    '||ads.example^$badfilter': 'option:badfilter',
    'реклама.example/баннер': 'pattern:non-ascii',
  };
  for (const [line, reason] of Object.entries(reasons)) {
    assert.deepEqual([parseLine(line).kind, parseLine(line).reason], ['unsupported', reason], line);
  }
  // Excluding a type Chrome can't match loses nothing; naming it beside others drops only it.
  assert.equal(parseLine('||ads.example^$~webrtc').kind, 'network');
  assert.deepEqual(parseLine('||ads.example^$webrtc,script').types, ['script']);
});

test('a filter for pop-ups is kept apart from those for requests', () => {
  // Alone, it matches no request and must make no rule.
  const alone = parseLine('||ads.example^$popup,third-party,domain=news.example');
  assert.deepEqual([alone.kind, alone.popup, alone.pattern, alone.thirdParty, alone.domains], ['popup', true, '||ads.example^', true, { include: ['news.example'], exclude: [] }]);
  assert.deepEqual([parseLine('@@||ok.example^$popup').kind, parseLine('@@||ok.example^$popup').exception], ['popup', true]);
  // Beside a type of request, it is both.
  const both = parseLine('||ads.example^$document,popup');
  assert.deepEqual([both.kind, both.popup, both.types], ['network', true, ['main_frame']]);
  assert.deepEqual([parseLine('||ads.example^$~popup').kind, parseLine('||ads.example^$~popup').popup], ['network', false]);
});

test('patterns are tidied: wildcards at the ends, ||*, and hosts outside ASCII', () => {
  assert.equal(parseLine('*/ads/*').pattern, '/ads/');
  assert.equal(parseLine('||*/adframe.').pattern, '/adframe.');
  assert.equal(parseLine('a**b').pattern, 'a*b');
  assert.equal(parseLine('||bücher.example^').pattern, '||xn--bcher-kva.example^');
  assert.equal(parseLine('$script,domain=site.example').pattern, '');
  assert.equal(parseLine('||').kind, 'unsupported');
});

test('a dollar inside a pattern is not an options mark unless options follow it', () => {
  assert.equal(parseLine('/ads$/').regex, true);
  assert.equal(parseLine('||x.example/a$b/c').pattern, '||x.example/a$b/c');
});

test('cosmetic filters: generic, for named sites, exceptions, entities', () => {
  assert.deepEqual(parseLine('##.ad-banner'), { kind: 'cosmetic', exception: false, selectors: ['.ad-banner'], include: [], exclude: [], entities: [], raw: '##.ad-banner' });
  const named = parseLine('Example.com,~shop.example.com,google.*##.promo, #sponsored > div');
  assert.deepEqual(named.include, ['example.com']);
  assert.deepEqual(named.exclude, ['shop.example.com']);
  assert.deepEqual(named.entities, ['google.*']);
  assert.deepEqual(named.selectors, ['.promo', '#sponsored > div']);
  assert.equal(parseLine('example.com#@#.ad-banner').exception, true);
  assert.equal(parseLine('#@#.ad-banner').exception, true);
});

test('cosmetic filters: :-abp-has becomes :has; what neither CSS nor a plan can say is refused', () => {
  assert.deepEqual(parseLine('example.com#?#div:-abp-has(> .label)').selectors, ['div:has(> .label)']);
  const reasons = {
    'example.com##div:upward(2)': 'cosmetic:procedural',
    'example.com##div:xpath(//a)': 'cosmetic:procedural',
    'example.com#?#div:-abp-properties(width: 300px)': 'cosmetic:procedural',
    'example.com##div:has-text(Sponsored):upward(1)': 'cosmetic:procedural',
    '##div:has-text(Sponsored)': 'cosmetic:procedural',
    'example.com##+js(aopr, ads)': 'cosmetic:scriptlet',
    'example.com#$#abort-on-property-read ads': 'cosmetic:snippet',
    'example.com#%#window.ads = 1': 'cosmetic:snippet',
    'example.com##.a { display: block } .b': 'cosmetic:malformed',
    'example.com##.a { background: url(https://x.example/) }': 'cosmetic:malformed',
    '##.a { display: block }': 'cosmetic:style',
    'example.com##div[title="x"': 'cosmetic:malformed',
    'exam ple.com##.a': 'cosmetic:domain',
  };
  for (const [line, reason] of Object.entries(reasons)) {
    assert.deepEqual([parseLine(line).kind, parseLine(line).reason], ['unsupported', reason], line);
  }
});

test('cosmetic filters that pick an element by its words become plans', () => {
  const plan = (line) => parseLine(line).procedural?.[0];
  assert.deepEqual(plan('example.com##.card:has-text(Sponsored)'), { raw: '.card:has-text(Sponsored)', steps: [{ css: '.card' }, { text: 'Sponsored' }] });
  assert.deepEqual(plan('example.com#?#.card:-abp-contains(Sponsored)').steps, [{ css: '.card' }, { text: 'Sponsored' }]);
  assert.deepEqual(plan('example.com##.card:has-text("Sponsored post")').steps, [{ css: '.card' }, { text: 'Sponsored post' }]);
  assert.deepEqual(plan('example.com##.card:has-text(/^Ad(vert)?$/i)').steps, [{ css: '.card' }, { re: '^Ad(vert)?$', flags: 'i' }]);
  assert.deepEqual(plan('example.*##a[role="button"]:has(p:has-text(Sponsored))').steps, [{ css: 'a[role="button"]' }, { has: [{ css: 'p' }, { text: 'Sponsored' }] }]);
  assert.deepEqual(plan('example.com##.heading:has-text(Partners) + ul').steps, [{ css: '.heading' }, { text: 'Partners' }, { css: ' + ul' }]);
  assert.deepEqual(plan('example.com##li:has(.logo[src*="id=1"]):has(> .name:has-text(Shop)):not(.own)').steps, [
    { css: 'li:has(.logo[src*="id=1"])' },
    { has: [{ css: '> .name' }, { text: 'Shop' }] },
    { css: ':not(.own)' },
  ]);
  // Where the words are looked for in whatever is under, or beside, what was found.
  assert.deepEqual(plan('example.com##.feed :has-text(Sponsored)').steps, [{ css: '.feed *' }, { text: 'Sponsored' }]);
  assert.deepEqual(plan('example.com##.holder > center > :has-text(Advert)').steps, [{ css: '.holder > center > *' }, { text: 'Advert' }]);
  assert.deepEqual(plan('example.com##.holder >:has-text(Advert)').steps, [{ css: '.holder > *' }, { text: 'Advert' }]);
  assert.deepEqual(plan('example.com##.a:has-text(One) :has-text(Two)').steps, [{ css: '.a' }, { text: 'One' }, { css: ' *' }, { text: 'Two' }]);
  assert.deepEqual(plan('example.com##.a:has-text(One) + :has-text(Two)').steps, [{ css: '.a' }, { text: 'One' }, { css: ' + *' }, { text: 'Two' }]);
  assert.deepEqual(plan('example.com##.feed :has(> b:has-text(Ad))').steps, [{ css: '.feed *' }, { has: [{ css: '> b' }, { text: 'Ad' }] }]);
  assert.deepEqual(plan('example.com##.wide\\ :has-text(Ad)').steps, [{ css: '.wide\\ ' }, { text: 'Ad' }], 'an escaped space is the end of a name');
  // Flags that make an expression remember where it stopped are left off: it is asked of one element after another.
  assert.deepEqual(plan('example.com##.card:has-text(/ad/gi)').steps, [{ css: '.card' }, { re: 'ad', flags: 'i' }]);
  assert.deepEqual(plan('example.com##.card:has-text(/ad/y)').steps, [{ css: '.card' }, { re: 'ad', flags: '' }]);
  assert.equal(parseLine('example.com##.card:has-text(/(unclosed/)').kind, 'unsupported', 'an expression that does not compile');
  assert.equal(parseLine('example.com##:has-text(Sponsored)').kind, 'unsupported', 'nothing to find before narrowing');
  const taken = parseLine('example.com#@#.card:has-text(Sponsored)');
  assert.deepEqual([taken.exception, taken.procedural[0].raw], [true, '.card:has-text(Sponsored)']);
});

test('restyling filters become CSS rules for the sites they name, and only plain declarations', () => {
  assert.deepEqual(parseLine('example.com##.nav.sticky {top:0px;}').styles, ['.nav.sticky{top:0px}']);
  assert.deepEqual(parseLine('example.com###wrap > [id][style*="height"] { height: 100% !important; margin : 0 }').styles, ['#wrap > [id][style*="height"]{height:100% !important;margin:0}']);
  assert.deepEqual(parseLine('example.com##.a { display: block }').selectors, []);
  for (const bad of ['example.com##.a { color: red; background: URL(x) }', 'example.com##.a { }', 'example.com##.a { @import "x" }', 'example.com##.a { content: "\\61" }']) {
    assert.equal(parseLine(bad).kind, 'unsupported', bad);
  }
});

test('a selector that would not stay inside its rule is refused', () => {
  // Each selector is written into `a, b, c {display: none}` for every page it is for.
  const refused = [
    '##@import url(https://x.example/a.css);a',
    'example.com##.a, @import "x";b',
    'example.com##.a;.b',
    'example.com##.a\\',
    'example.com##.a /* note',
    'example.com##.a */ .b',
    'example.com##.a}',
    'example.com##a[href="x]',
    'example.com##.a)',
  ];
  for (const line of refused) assert.deepEqual([parseLine(line).kind, parseLine(line).reason], ['unsupported', 'cosmetic:malformed'], line);
  // What only looks like one of those is kept: inside quotes, or escaped.
  const kept = ['example.com##div[style="width:300px;height:250px"]', 'example.com##a[href*=";ad="]', 'example.com##.a\\;b', 'example.com##.w-1\\/2', "example.com##a[title='}']"];
  assert.deepEqual(parseLine(kept[0]).selectors, ['div[style="width:300px;height:250px"]']);
  assert.deepEqual(parseLine(kept[1]).selectors, ['a[href*=";ad="]']);
  assert.deepEqual(parseLine(kept[2]).selectors, ['.a\\;b']);
  assert.deepEqual(parseLine(kept[3]).selectors, ['.w-1\\/2']);
  assert.equal(parseLine(kept[4]).kind, 'unsupported', 'a brace is refused even in quotes: nothing in the lists needs one');
  assert.equal(isContained('.a, .b'), true);
  assert.equal(isContained(''), false);
  // A restyling filter's selector is held to the same.
  assert.equal(parseLine('example.com##.a;.b { top: 0 }').kind, 'unsupported');
  assert.equal(parseLine('example.com##@media x { top: 0 }').kind, 'unsupported');
});

test('selector lists split at top-level commas only', () => {
  assert.deepEqual(splitSelectors('.a, .b'), ['.a', '.b']);
  assert.deepEqual(splitSelectors('div:is(.a, .b), [title="x, y"]'), ['div:is(.a, .b)', '[title="x, y"]']);
  assert.equal(isBalanced('a[href*="("]'), true);
  assert.equal(isBalanced('a:not(.b'), false);
  assert.equal(isBalanced('a[b'), false);
});

test('hostnames', () => {
  assert.equal(hostname('Example.COM'), 'example.com');
  assert.equal(hostname('bücher.example'), 'xn--bcher-kva.example');
  assert.equal(hostname('a_b.example.com'), 'a_b.example.com');
  for (const bad of ['', 'exa mple.com', 'example.com/', '.example.com', 'example..com', '-a.example']) {
    assert.equal(hostname(bad), '', bad);
  }
});

test('a list is read whole, and what was dropped is counted by reason', () => {
  const list = parseList(['[Adblock Plus 2.0]', '! Title: test', '||ads.example^', '##.ad', '||pop.example^$popup', '||pop2.example^$popup,document', 'x.example##+js(nowoif)', '||rtc.example^$webrtc'].join('\n'));
  assert.equal(list.lines, 6);
  assert.equal(list.network.length, 2, 'the plain filter, and the one that is for documents as well as pop-ups');
  assert.equal(list.cosmetic.length, 1);
  assert.deepEqual(list.popups.map((filter) => filter.pattern), ['||pop.example^', '||pop2.example^']);
  assert.deepEqual([...list.dropped], [['cosmetic:scriptlet', 1], ['option:webrtc', 1]]);
});
