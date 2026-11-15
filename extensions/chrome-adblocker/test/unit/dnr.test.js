import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PRIORITY, problemsWith, regexLooksSupported, toRules } from '../../tools/lib/dnr.js';
import { parseLine } from '../../tools/lib/filters.js';

/** Rules from filter lines, each checked against Chrome's requirements. */
function rules(lines, options) {
  const result = toRules(lines.map((line) => parseLine(line)), options);
  for (const rule of result.rules) assert.deepEqual(problemsWith(rule), [], JSON.stringify(rule));
  return result;
}

test('filters for whole hosts become one rule, covered hosts left out', () => {
  const { rules: out } = rules(['||ads.example^', '||tracker.example^', '||banner.ads.example^', '||zeta.example^']);
  assert.deepEqual(out, [{ id: 1, action: { type: 'block' }, condition: { requestDomains: ['ads.example', 'tracker.example', 'zeta.example'] } }]);
});

test('hosts are grouped only with filters otherwise alike', () => {
  const { rules: out } = rules(['||a.example^', '||b.example^$third-party', '||c.example^$third-party', '||d.example^$script', '@@||e.example^', '||f.example^$domain=site.example']);
  assert.equal(out.length, 5);
  const third = out.find((rule) => rule.condition.domainType === 'thirdParty');
  assert.deepEqual(third.condition.requestDomains, ['b.example', 'c.example']);
  const allow = out.find((rule) => rule.action.type === 'allow');
  assert.deepEqual(allow.condition, { requestDomains: ['e.example'] });
  assert.deepEqual(out.find((rule) => rule.condition.initiatorDomains).condition, { initiatorDomains: ['site.example'], requestDomains: ['f.example'] });
  assert.deepEqual(out.map((rule) => rule.id), [1, 2, 3, 4, 5]);
});

test('a host with anything after it, or with match-case, stays a pattern', () => {
  const { rules: out } = rules(['||ads.example/banner', '||ads.example^*/x', '||Ads.example^$match-case', '|https://ads.example^']);
  assert.deepEqual(out.map((rule) => rule.condition.urlFilter), ['||ads.example/banner', '||ads.example^*/x', '||Ads.example^', '|https://ads.example^']);
  assert.equal(out[2].condition.isUrlFilterCaseSensitive, true);
  assert.equal(out[0].condition.isUrlFilterCaseSensitive, undefined);
});

test('types: named, excluded (the page excluded with them), and the default', () => {
  const { rules: out } = rules(['/ad.js$script,image', '/ad.$~image,~script', '/ad/banner.']);
  assert.deepEqual(out[0].condition.resourceTypes, ['image', 'script']);
  assert.deepEqual(out[1].condition.excludedResourceTypes, ['image', 'main_frame', 'script']);
  assert.deepEqual(Object.keys(out[2].condition), ['urlFilter']);
});

test('domain= becomes the initiators, included and excluded', () => {
  const { rules: out } = rules(['/ad.js$domain=a.example|b.example|~x.a.example', '/promo.$domain=~b.example']);
  assert.deepEqual(out[0].condition.initiatorDomains, ['a.example', 'b.example']);
  assert.deepEqual(out[0].condition.excludedInitiatorDomains, ['x.a.example']);
  assert.deepEqual(out[1].condition, { excludedInitiatorDomains: ['b.example'], urlFilter: '/promo.' });
});

test('exceptions allow; one for a document allows everything in it', () => {
  const { rules: out } = rules(['@@||site.example/player.js$script', '@@||trusted.example^$document', '@@||mixed.example^$document,script', '@@||paged.example/app/$document']);
  assert.deepEqual(out.find((rule) => rule.condition.urlFilter === '||site.example/player.js').action, { type: 'allow' });
  const whole = out.filter((rule) => rule.action.type === 'allowAllRequests');
  assert.deepEqual(whole.map((rule) => rule.condition), [
    { resourceTypes: ['main_frame', 'sub_frame'], requestDomains: ['mixed.example', 'trusted.example'] },
    { resourceTypes: ['main_frame', 'sub_frame'], urlFilter: '||paged.example/app/' },
  ]);
  const script = out.find((rule) => rule.action.type === 'allow' && rule.condition.requestDomains);
  assert.deepEqual(script.condition, { resourceTypes: ['script'], requestDomains: ['mixed.example'] });
  // Where a whole host is excepted, what its documents ask for is allowed outright too;
  // an exception for some of a host's pages can't be said that way, and is left as it is.
  const asked = out.filter((rule) => rule.action.type === 'allow' && rule.condition.initiatorDomains);
  assert.deepEqual(asked.map((rule) => rule.condition), [{ initiatorDomains: ['mixed.example', 'trusted.example'] }]);
});

test('important blocks outrank exceptions', () => {
  const { rules: out } = rules(['||ads.example^$important', '@@||ads.example^']);
  assert.equal(out.find((rule) => rule.action.type === 'block').priority, PRIORITY.important);
  assert.equal(out.find((rule) => rule.action.type === 'allow').priority, undefined, 'the default priority is left unwritten');
  assert.ok(PRIORITY.user > PRIORITY.important && PRIORITY.important > PRIORITY.normal);
});

test('csp adds a response header on documents and frames; its exception allows them', () => {
  const { rules: out } = rules(["||site.example^$csp=script-src 'self'", '@@||ok.site.example^$csp', "||frames.example^$csp=worker-src 'none',subdocument"]);
  const added = out.filter((rule) => rule.action.type === 'modifyHeaders');
  assert.deepEqual(added[0].action.responseHeaders, [{ header: 'content-security-policy', operation: 'append', value: "script-src 'self'" }]);
  assert.deepEqual(added.map((rule) => rule.condition.resourceTypes), [['main_frame', 'sub_frame'], ['sub_frame']]);
  const allow = out.find((rule) => rule.action.type === 'allow');
  assert.deepEqual(allow.condition, { resourceTypes: ['main_frame', 'sub_frame'], requestDomains: ['ok.site.example'] });
});

test('exceptions that only turn hiding off make no rule, and name their hosts', () => {
  const result = rules(['@@||news.example^$generichide', '@@||shop.example^$elemhide', '@@||both.example^$elemhide,generichide', '@@$generichide,domain=by-domain.example', '@@||path.example/page$generichide', '@@||doc.example^$generichide,document']);
  assert.deepEqual(result.hide, { elemhide: ['both.example', 'shop.example'], generichide: ['both.example', 'by-domain.example', 'doc.example', 'news.example'] });
  assert.deepEqual(result.rules.map((rule) => [rule.action.type, rule.condition.requestDomains ?? rule.condition.initiatorDomains]), [['allowAllRequests', ['doc.example']], ['allow', ['doc.example']]]);
  assert.deepEqual([...result.dropped], [['hide-exception:pattern', 1]]);
});

test('regular expressions: kept when RE2 can take them, dropped when not or when Chrome refused them', () => {
  const result = rules(['/^https?:\\/\\/ads\\d+\\.example\\//$script', '/ads(?=banner)/', '/(ad)\\1/', '/a{2000}/', '/refused\\.example/'], { rejectedRegex: ['refused\\.example'] });
  assert.deepEqual(result.rules.map((rule) => rule.condition.regexFilter), ['^https?:\\/\\/ads\\d+\\.example\\/']);
  assert.deepEqual(Object.fromEntries(result.dropped), { 'regex:unsupported': 3, 'regex:rejected-by-chrome': 1 });
  for (const good of ['^ads?[0-9]+\\.', 'a|b', '[(?=]x', 'a\\+b', '\\bads\\b', '(?:ad|banner)s?']) assert.equal(regexLooksSupported(good), true, good);
  for (const bad of ['(?<!x)ad', '(?<name>ad)', 'a++', '\\u0041', '(', '\\_ad', '\\k<x>']) assert.equal(regexLooksSupported(bad), false, bad);
});

test('a filter that would match every request is dropped; one narrowed by its pages is kept', () => {
  const result = rules(['$third-party', '$script,domain=site.example', '||ads.example^$csp=']);
  assert.deepEqual(result.rules.map((rule) => rule.condition), [{ initiatorDomains: ['site.example'], resourceTypes: ['script'] }]);
  assert.deepEqual(Object.fromEntries(result.dropped), { 'too-broad': 1, 'nothing-to-do': 1 });
});

test('the same filter written twice is one rule; rules are numbered from firstId', () => {
  const { rules: out } = rules(['/ads/banner.', '/ads/banner.', '||x.example^', '||x.example^'], { firstId: 100 });
  assert.deepEqual(out.map((rule) => rule.id), [100, 101]);
  assert.deepEqual(out[0].condition.requestDomains, ['x.example']);
});

test('to= narrows the hosts requested and keeps a host pattern beside it', () => {
  const { rules: out } = rules(['||cdn.example^$to=a.cdn.example|~b.cdn.example', '*$script,denyallow=ok.example,domain=site.example']);
  assert.deepEqual(out[0].condition, { requestDomains: ['a.cdn.example'], excludedRequestDomains: ['b.cdn.example'], urlFilter: '||cdn.example^' });
  assert.deepEqual(out[1].condition, { initiatorDomains: ['site.example'], excludedRequestDomains: ['ok.example'], resourceTypes: ['script'] });
});

test('problemsWith names what Chrome would refuse', () => {
  const ok = { id: 1, action: { type: 'block' }, condition: { urlFilter: '/ads/' } };
  assert.deepEqual(problemsWith(ok), []);
  const cases = [
    [{ ...ok, id: 0 }, 'id'],
    [{ ...ok, condition: {} }, 'every request'],
    [{ ...ok, condition: { urlFilter: '/ads/', regexFilter: 'ads' } }, 'both urlFilter'],
    [{ ...ok, condition: { urlFilter: '||*ads' } }, '||*'],
    [{ ...ok, condition: { urlFilter: '/реклама/' } }, 'ASCII'],
    [{ ...ok, condition: { urlFilter: '/a/', resourceTypes: ['script'], excludedResourceTypes: ['image'] } }, 'both resourceTypes'],
    [{ ...ok, condition: { urlFilter: '/a/', resourceTypes: ['scripts'] } }, 'unknown type'],
    [{ ...ok, condition: { requestDomains: ['Example.com'] } }, 'lower-case host'],
    [{ ...ok, condition: { requestDomains: [] } }, 'empty'],
    [{ id: 1, action: { type: 'allowAllRequests' }, condition: { urlFilter: '/a/', resourceTypes: ['script'] } }, 'allowAllRequests'],
    [{ id: 1, action: { type: 'modifyHeaders' }, condition: { urlFilter: '/a/' } }, 'modifyHeaders'],
    [{ id: 1, action: { type: 'redirect' }, condition: { urlFilter: '/a/' } }, 'action redirect'],
  ];
  for (const [rule, words] of cases) {
    assert.ok(problemsWith(rule).some((problem) => problem.includes(words)), `${words}: ${problemsWith(rule)}`);
  }
});
