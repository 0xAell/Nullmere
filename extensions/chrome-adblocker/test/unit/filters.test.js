import assert from 'node:assert/strict';
import { test } from 'node:test';
import { hostname, isBalanced, parseLine, parseList, splitSelectors } from '../../tools/lib/filters.js';

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
    '||ads.example^$popup': 'option:popup',
    '||ads.example^$webrtc': 'option:webrtc',
    '||ads.example^$rewrite=abp-resource:blank-js': 'option:rewrite',
    '||ads.example^$redirect=noop.js': 'option:redirect',
    '||ads.example^$removeparam=utm_source': 'option:removeparam',
    '@@||ads.example^$genericblock': 'option:genericblock',
    '||ads.example^$sitekey=abc': 'option:sitekey',
    '||ads.example^$domain=google.*': 'option:domain-entity',
    '||ads.example^$badfilter': 'option:badfilter',
    'реклама.example/баннер': 'pattern:non-ascii',
  };
  for (const [line, reason] of Object.entries(reasons)) {
    assert.deepEqual([parseLine(line).kind, parseLine(line).reason], ['unsupported', reason], line);
  }
  // Excluding a type Chrome can't match loses nothing; naming it beside others drops only it.
  assert.equal(parseLine('||ads.example^$~popup').kind, 'network');
  assert.deepEqual(parseLine('||ads.example^$popup,script').types, ['script']);
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

test('cosmetic filters: :-abp-has becomes :has; what CSS cannot say is refused', () => {
  assert.deepEqual(parseLine('example.com#?#div:-abp-has(> .label)').selectors, ['div:has(> .label)']);
  const reasons = {
    'example.com#?#div:-abp-contains(Sponsored)': 'cosmetic:procedural',
    'example.com##div:has-text(Sponsored)': 'cosmetic:procedural',
    'example.com##div:upward(2)': 'cosmetic:procedural',
    'example.com##+js(aopr, ads)': 'cosmetic:scriptlet',
    'example.com#$#abort-on-property-read ads': 'cosmetic:snippet',
    'example.com#%#window.ads = 1': 'cosmetic:snippet',
    'example.com##.a { display: block }': 'cosmetic:style',
    'example.com##.a { display: block } .b': 'cosmetic:malformed',
    'example.com##div[title="x"': 'cosmetic:malformed',
    'exam ple.com##.a': 'cosmetic:domain',
  };
  for (const [line, reason] of Object.entries(reasons)) {
    assert.deepEqual([parseLine(line).kind, parseLine(line).reason], ['unsupported', reason], line);
  }
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
  const list = parseList(['[Adblock Plus 2.0]', '! Title: test', '||ads.example^', '##.ad', '||pop.example^$popup', '||pop2.example^$popup', 'x.example##+js(nowoif)'].join('\n'));
  assert.equal(list.lines, 5);
  assert.equal(list.network.length, 1);
  assert.equal(list.cosmetic.length, 1);
  assert.deepEqual([...list.dropped], [['option:popup', 2], ['cosmetic:scriptlet', 1]]);
});
