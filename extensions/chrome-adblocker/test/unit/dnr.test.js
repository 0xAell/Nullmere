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
  assert.deepEqual(out, [{ id: 1, priority: PRIORITY.normal, action: { type: 'block' }, condition: { requestDomains: ['ads.example', 'tracker.example', 'zeta.example'] } }]);
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

test('a document exception narrowed by anything else is not widened to all its documents ask for', () => {
  const result = rules(['@@||plain.example^$document', '@@||narrow.example^$document,domain=~foo.example', '@@||posted.example^$document,method=post', '@@||third.example^$document,third-party']);
  const asked = result.rules.filter((rule) => rule.action.type === 'allow' && rule.condition.initiatorDomains);
  assert.deepEqual(asked.map((rule) => rule.condition), [{ initiatorDomains: ['plain.example'] }]);
  // And only the plain one turns hiding off for its host: the others except some of its pages' loads, not the host.
  assert.deepEqual(result.hide.elemhide, ['plain.example']);
});

test('important blocks outrank exceptions', () => {
  const { rules: out } = rules(['||ads.example^$important', '@@||ads.example^']);
  assert.equal(out.find((rule) => rule.action.type === 'block').priority, PRIORITY.important);
  assert.equal(out.find((rule) => rule.action.type === 'allow').priority, PRIORITY.exception);
  // Each above the one before: the csp's, the blocks, the stand-ins, the
  // exceptions, the important blocks and stand-ins, the user's own.
  const order = ['csp', 'normal', 'redirect', 'exception', 'important', 'importantRedirect', 'user'].map((name) => PRIORITY[name]);
  assert.deepEqual([...order].sort((a, b) => a - b), order);
  assert.equal(new Set(order).size, order.length);
  // An exception marked important takes back an important block, as allow wins at one priority.
  const { rules: both } = rules(['||ads.example^$important', '@@||ads.example^$important']);
  assert.deepEqual(both.map((rule) => [rule.action.type, rule.priority]).sort(), [['allow', PRIORITY.important], ['block', PRIORITY.important]]);
});

test('a stand-in is given for a request in place of refusing it, above the blocks and below the exceptions', () => {
  const { rules: out, dropped } = rules([
    '||chartbeat.example/js/chartbeat.js$redirect=chartbeat.js,script',
    '||tracker.example^$redirect=noopjs,script',
    '||pixels.example^$image,important,redirect=1x1.gif,domain=shop.example',
    '||video.example/*.mp4$rewrite=abp-resource:blank-mp4,domain=news.example',
    '||tracker.example^',
    '@@||tracker.example^*/kept.js$script',
  ]);
  assert.equal(dropped.size, 0);
  const given = (path) => out.find((rule) => rule.action.redirect?.extensionPath === path);
  const chartbeat = given('/redirects/chartbeat.js');
  assert.deepEqual(chartbeat, {
    id: chartbeat.id,
    priority: PRIORITY.redirect,
    action: { type: 'redirect', redirect: { extensionPath: '/redirects/chartbeat.js' } },
    condition: { urlFilter: '||chartbeat.example/js/chartbeat.js', resourceTypes: ['script'] },
  });
  // A whole host's stand-in is grouped by host as blocks are.
  assert.deepEqual(given('/redirects/noop.js').condition, { requestDomains: ['tracker.example'], resourceTypes: ['script'] });
  const pixel = given('/redirects/1x1.gif');
  assert.equal(pixel.priority, PRIORITY.importantRedirect);
  assert.deepEqual(pixel.condition, { requestDomains: ['pixels.example'], initiatorDomains: ['shop.example'], resourceTypes: ['image'] });
  assert.equal(given('/redirects/noop.mp4').condition.urlFilter, '||video.example/*.mp4');
  // The host's block sits below its stand-in, its exception above.
  const block = out.find((rule) => rule.action.type === 'block');
  const allow = out.find((rule) => rule.action.type === 'allow');
  assert.ok(block.priority < given('/redirects/noop.js').priority && given('/redirects/noop.js').priority < allow.priority);
});

test('csp adds a response header on documents and frames; its exception allows them', () => {
  const { rules: out } = rules(["||site.example^$csp=script-src 'self'", '@@||ok.site.example^$csp', "||frames.example^$csp=worker-src 'none',subdocument"]);
  const added = out.filter((rule) => rule.action.type === 'modifyHeaders');
  assert.deepEqual(added[0].action.responseHeaders, [{ header: 'content-security-policy', operation: 'append', value: "script-src 'self'" }]);
  assert.deepEqual(added.map((rule) => rule.condition.resourceTypes), [['main_frame', 'sub_frame'], ['sub_frame']]);
  const allow = out.find((rule) => rule.action.type === 'allow');
  assert.deepEqual(allow.condition, { resourceTypes: ['main_frame', 'sub_frame'], requestDomains: ['ok.site.example'] });
});

test('a csp exception takes the policy back and lets nothing through that a filter blocks', () => {
  // Chrome leaves a header rule out when an allow of its priority or higher matches, and
  // lets a block of higher priority win over an allow: so the exception sits with the
  // policies, under every block.
  const { rules: out } = rules(["||frames.example^$csp=script-src 'none'", '@@||frames.example/ok/$csp,subdocument', '||frames.example^$subdocument', '||loud.example^$csp=x,important']);
  const policy = out.find((rule) => rule.action.type === 'modifyHeaders' && rule.condition.requestDomains.includes('frames.example'));
  const exception = out.find((rule) => rule.action.type === 'allow');
  const block = out.find((rule) => rule.action.type === 'block');
  assert.deepEqual(exception.condition, { resourceTypes: ['sub_frame'], urlFilter: '||frames.example/ok/' });
  assert.equal(policy.priority ?? 1, PRIORITY.csp);
  assert.equal(exception.priority ?? 1, PRIORITY.csp);
  assert.ok(block.priority > (exception.priority ?? 1), 'the block outranks the csp exception');
  // An important policy is out of an exception's reach.
  assert.equal(out.find((rule) => rule.condition.requestDomains?.includes('loud.example')).priority, PRIORITY.important);
});

test('csp with domain= is for those sites\' own pages, and for frames in them', () => {
  // The page's own host is the request's domain to Chrome; its initiator would be
  // whichever page held the link that led there.
  const { rules: out } = rules(["$csp=worker-src 'none',domain=a.example|b.example|~x.a.example", "||cdn.example^$csp=script-src 'self',domain=c.example,subdocument", '@@$csp,domain=a.example']);
  const added = out.filter((rule) => rule.action.type === 'modifyHeaders');
  assert.deepEqual(added.map((rule) => rule.condition), [
    { resourceTypes: ['sub_frame'], initiatorDomains: ['c.example'], requestDomains: ['cdn.example'] },
    { resourceTypes: ['main_frame'], requestDomains: ['a.example', 'b.example'], excludedRequestDomains: ['x.a.example'] },
    { resourceTypes: ['sub_frame'], initiatorDomains: ['a.example', 'b.example'], excludedInitiatorDomains: ['x.a.example'] },
  ]);
  const taken = out.filter((rule) => rule.action.type === 'allow');
  assert.deepEqual(taken.map((rule) => rule.condition), [
    { resourceTypes: ['main_frame'], requestDomains: ['a.example'] },
    { resourceTypes: ['sub_frame'], initiatorDomains: ['a.example'] },
  ]);
  // With to= as well there is no way to say it.
  const result = rules(["$csp=x,domain=a.example,to=b.example"]);
  assert.deepEqual([result.rules.length, [...result.dropped]], [0, [['csp:domain-and-to', 1]]]);
});

test('csp with third-party is for frames of another site, and says nothing of a page', () => {
  // A page is never of another site than itself. Chrome would compare it with the page
  // before it, or with nothing for an address typed, and call that another site.
  const first = rules(["$csp=script-src 'self',domain=a.example,~third-party"]).rules;
  assert.deepEqual(first.map((rule) => rule.condition), [
    { resourceTypes: ['main_frame'], requestDomains: ['a.example'] },
    { resourceTypes: ['sub_frame'], domainType: 'firstParty', initiatorDomains: ['a.example'] },
  ]);
  const third = rules(["$csp=script-src 'self',domain=a.example,third-party", "||b.example^$csp=worker-src 'none',third-party"]).rules;
  assert.deepEqual(third.map((rule) => rule.condition), [
    { resourceTypes: ['sub_frame'], domainType: 'thirdParty', requestDomains: ['b.example'] },
    { resourceTypes: ['sub_frame'], domainType: 'thirdParty', initiatorDomains: ['a.example'] },
  ], 'no rule for a page at all');
  // One for pages alone and of other sites has nothing left to say, and is counted as left out.
  const nothing = rules(["||d.example^$csp=worker-src 'none',document,third-party"]);
  assert.deepEqual([nothing.rules.length, [...nothing.dropped]], [0, [['csp:third-party-page', 1]]]);
  // Without either, a filter is one rule for both kinds of document, as before.
  assert.deepEqual(rules(["||c.example^$csp=worker-src 'none'"]).rules.map((rule) => rule.condition), [{ resourceTypes: ['main_frame', 'sub_frame'], requestDomains: ['c.example'] }]);
});

test('exceptions that only turn hiding off make no rule, and name their hosts', () => {
  const result = rules(['@@||news.example^$generichide', '@@||shop.example^$elemhide', '@@||both.example^$elemhide,generichide', '@@$generichide,domain=by-domain.example', '@@||path.example/page$generichide', '@@||doc.example^$generichide,document']);
  // The last excepts its whole document as well, and with it all hiding there, as Adblock Plus does.
  assert.deepEqual(result.hide, { elemhide: ['both.example', 'doc.example', 'shop.example'], generichide: ['both.example', 'by-domain.example', 'doc.example', 'news.example'] });
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
    [{ id: 1, action: { type: 'redirect', redirect: { url: 'https://elsewhere.example/' } }, condition: { urlFilter: '/a/' } }, 'action redirect'],
    [{ id: 1, action: { type: 'redirect', redirect: { extensionPath: '/redirects/../manifest.json' } }, condition: { urlFilter: '/a/' } }, 'action redirect'],
  ];
  for (const [rule, words] of cases) {
    assert.ok(problemsWith(rule).some((problem) => problem.includes(words)), `${words}: ${problemsWith(rule)}`);
  }
});
