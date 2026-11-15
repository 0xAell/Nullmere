// A build from the small list in test/e2e/lists, one filter for each
// thing the converter and the extension are meant to do, in a real
// Chromium: what each kind of filter blocks, lets through and hides.

import assert from 'node:assert/strict';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { build } from '../../tools/build.js';
import { complaints, launch, open, root, startServer, until } from './harness.js';

let server;
let browser;

before(async () => {
  const out = join(root, 'build-test');
  build({ lists: join(root, 'test', 'e2e', 'lists'), out, quiet: true });
  server = await startServer();
  browser = await launch(out);
});

after(async () => {
  await browser?.close();
  await server?.close();
});

const script = (host, path = '/x.js') => `<script src="${server.url(host, path)}"></script>`;
const image = (host, path = '/x.gif') => `<img src="${server.url(host, path)}">`;

/** Loads a page of `body` on `host` and returns which hosts' requests the extension stopped, and which scripts ran. */
async function visit(host, body, path = '/') {
  server.page(host, path, `<!doctype html><title>${host}</title><body>${body}</body>`);
  const { page, blocked } = await open(browser.context, server.url(host, path));
  const stopped = blocked().map((url) => `${new URL(url).hostname}${new URL(url).pathname}`).sort();
  const ran = (await page.evaluate(() => window.ran)) ?? [];
  return { page, stopped, ran };
}

/** Which of the elements with these ids are hidden. */
const hidden = (page, ids) => page.evaluate((list) => list.filter((id) => getComputedStyle(document.getElementById(id)).display === 'none'), ids);

test('a host is blocked whole, with its subdomains; a path anywhere; an exception lets its one script by', async () => {
  const { page, stopped, ran } = await visit('news.test', [script('ads.test', '/tag.js'), image('img.ads.test'), script('cdn.test', '/banner-ads/x.js'), script('ads.test', '/allowed.js'), script('cdn.test', '/lib.js')].join(''));
  assert.deepEqual(stopped, ['ads.test/tag.js', 'cdn.test/banner-ads/x.js', 'img.ads.test/x.gif']);
  assert.deepEqual(ran, ['ads.test/allowed.js', 'cdn.test/lib.js']);
  await page.close();
});

test('third-party: blocked from another site, not from its own', async () => {
  let { page, stopped } = await visit('news.test', script('third.test'));
  assert.deepEqual(stopped, ['third.test/x.js']);
  await page.close();
  ({ page, stopped } = await visit('third.test', script('third.test') + script('static.third.test')));
  assert.deepEqual(stopped, []);
  await page.close();
});

test('domain= and types: only on the pages named, only the types named', async () => {
  let { page, stopped, ran } = await visit('news.test', script('scripts.test') + image('scripts.test') + script('typed.test') + image('typed.test'));
  assert.deepEqual(stopped, ['scripts.test/x.js', 'typed.test/x.gif']);
  assert.deepEqual(ran, ['typed.test/x.js']);
  await page.close();
  ({ page, stopped } = await visit('other.test', script('scripts.test')));
  assert.deepEqual(stopped, [], 'scripts.test is blocked on news.test alone');
  await page.close();
});

test('important outranks its exception; a regular expression matches; a popup-only filter makes no rule', async () => {
  const { page, stopped, ran } = await visit('news.test', script('important.test') + script('cdn.regex.test', '/ad42.js') + script('cdn.regex.test', '/adx.js') + script('popup-only.test'));
  assert.deepEqual(stopped, ['cdn.regex.test/ad42.js', 'important.test/x.js']);
  assert.deepEqual(ran, ['cdn.regex.test/adx.js', 'popup-only.test/x.js']);
  await page.close();
});

test('csp= adds a policy to the page: its scripts do not run', async () => {
  let { page, ran } = await visit('csp.test', script('csp.test', '/own.js'));
  assert.deepEqual(ran, [], 'script-src none');
  await page.close();
  ({ page, ran } = await visit('plain.test', script('plain.test', '/own.js')));
  assert.deepEqual(ran, ['plain.test/own.js']);
  await page.close();
});

test('csp= with domain= is for that site\'s own pages and the frames in them, not for where its links lead', async () => {
  // The site's own page, come to with no page before it.
  let { page, ran } = await visit('cspsite.test', `${script('cspsite.test', '/own.js')}<a id="out" href="${server.url('elsewhere.test', '/landing')}">out</a><iframe src="${server.url('framed.test', '/embed')}"></iframe>`);
  assert.deepEqual(ran, [], 'the policy is on the site\'s own page');
  // A frame in it, of another site.
  server.page('framed.test', '/embed', `<!doctype html><body>${script('framed.test', '/in-frame.js')}</body>`);
  await page.reload();
  await page.waitForTimeout(300);
  assert.equal(server.reached('framed.test', '/in-frame.js'), false, 'and on a frame in it');
  // Where one of its links leads has no policy put on it.
  server.page('elsewhere.test', '/landing', `<!doctype html><body>${script('elsewhere.test', '/own.js')}</body>`);
  await Promise.all([page.waitForURL('**/landing'), page.click('#out')]);
  await until(() => page.evaluate(() => window.ran?.length === 1), 'the script of the page the link led to, to run');
  await page.close();
  // The same frame in another site's page has none either.
  server.forget();
  ({ page, ran } = await visit('plain.test', `<iframe src="${server.url('framed.test', '/embed')}"></iframe>`));
  await until(() => server.reached('framed.test', '/in-frame.js'), 'the frame\'s script to be asked for in a page the filter does not name');
  await page.close();
});

test('a csp exception takes the policy back, and lets nothing through that another filter blocks', async () => {
  let { page, ran } = await visit('csp.test', script('csp.test', '/own.js'), '/ok/');
  assert.deepEqual(ran, ['csp.test/own.js'], 'no policy on the pages the exception names');
  await page.close();
  let stopped;
  ({ page, stopped } = await visit('news.test', `<iframe src="${server.url('barred.test', '/embed')}"></iframe>`));
  assert.deepEqual(stopped, ['barred.test/embed'], 'the frame is still blocked: its exception was only for a policy');
  await page.close();
});

test('a document exception lets everything through on its pages, frames included, and hides nothing there', async () => {
  server.page('trusted.test', '/frame', `<!doctype html><body>${script('ads.test', '/in-frame.js')}</body>`);
  const { page, stopped, ran } = await visit('trusted.test', `${script('ads.test', '/tag.js')}<iframe src="/frame"></iframe><div id="banner" class="ad-banner">ad</div>`);
  assert.deepEqual(stopped, []);
  assert.deepEqual(ran, ['ads.test/tag.js']);
  await until(() => server.reached('ads.test', '/in-frame.js'), 'the frame\'s ad script to be asked for');
  // Nothing is to happen to the slot: give it the time hiding takes elsewhere, then look.
  await page.waitForTimeout(700);
  assert.deepEqual(await hidden(page, ['banner']), []);
  await page.close();
});

const SLOTS = `
  <div id="banner" class="ad-banner">ad</div>
  <div id="ad_top">ad</div>
  <div class="ad-wrap"><div id="inner" class="inner">ad</div></div>
  <div id="slot" data-ad-slot="1">ad</div>
  <div id="mixed" class="Mixed-Case-Ad">ad</div>
  <div id="story" class="sponsored-story">ad</div>
  <div id="rail" class="promo-rail">ad</div>
  <div id="entity" class="entity-ad">ad</div>
  <div id="pixel" class="tracking-pixel">ad</div>
  <section id="labelled"><span class="ad-label">Advertisement</span></section>
  <section id="unlabelled"><p>Words</p></section>
  <div id="never" class="never-hidden">kept</div>
  <article id="content" class="story">The news itself.</article>`;
const ALL = ['banner', 'ad_top', 'inner', 'slot', 'mixed', 'story', 'rail', 'entity', 'pixel', 'labelled', 'unlabelled', 'never', 'content'];
const GENERIC = ['banner', 'ad_top', 'inner', 'slot', 'mixed', 'pixel'];

test('generic and site filters hide their slots; the rest of the page is left alone', async () => {
  const { page } = await visit('news.test', SLOTS);
  await until(async () => (await hidden(page, ALL)).length >= 9, 'the slots to be hidden');
  assert.deepEqual(await hidden(page, ALL), [...GENERIC.slice(0, 5), 'story', 'rail', 'pixel', 'labelled']);
  await page.close();
});

test('a site\'s filters are not another site\'s; an excluded subdomain and a site\'s exception are honoured', async () => {
  let { page } = await visit('other.test', SLOTS);
  await until(async () => (await hidden(page, ALL)).length >= GENERIC.length, 'the generic slots to be hidden');
  assert.deepEqual(await hidden(page, ALL), GENERIC);
  await page.close();

  ({ page } = await visit('live.news.test', SLOTS));
  await until(async () => (await hidden(page, ALL)).length >= 8, 'the slots to be hidden');
  assert.deepEqual(await hidden(page, ALL), [...GENERIC.slice(0, 5), 'story', 'pixel', 'labelled'], 'all of news.test\'s but the promo rail');
  await page.close();

  ({ page } = await visit('www.shop.test', SLOTS));
  await until(async () => (await hidden(page, ALL)).length >= GENERIC.length - 1, 'the slots to be hidden');
  assert.deepEqual(await hidden(page, ALL), GENERIC.filter((id) => id !== 'banner'), 'shop.test keeps its .ad-banner');
  await page.close();
});

test('an entity filter is for the name under any suffix', async () => {
  for (const host of ['entity.test', 'www.entity.co.uk']) {
    const { page } = await visit(host, SLOTS);
    await until(async () => (await hidden(page, ['entity'])).length === 1, `the entity slot on ${host}`);
    await page.close();
  }
});

test('generichide leaves a site its generic slots; elemhide leaves it everything', async () => {
  server.page('quiet.test', '/', `<!doctype html><body>${SLOTS}</body>`);
  server.page('nohide.test', '/', `<!doctype html><body>${SLOTS}</body>`);
  for (const host of ['quiet.test', 'nohide.test']) {
    const { page } = await open(browser.context, server.url(host));
    // Nothing is to happen: give it the time the others take, then look.
    await page.waitForTimeout(700);
    assert.deepEqual(await hidden(page, ALL), [], host);
    await page.close();
  }
});

test('slots added after the page loads are hidden as they come', async () => {
  const { page } = await visit('other.test', '<main id="main"><p>Words</p></main>');
  await page.evaluate(() => {
    document.getElementById('main').insertAdjacentHTML('beforeend', '<div id="late" class="ad-banner">ad</div><div class="ad-wrap"><p id="late-inner" class="inner">ad</p></div>');
    document.querySelector('#main p').id = 'ad_top';
  });
  await until(async () => (await hidden(page, ['late', 'late-inner', 'ad_top'])).length === 3, 'the late slots to be hidden');
  await page.close();
});

test('a page\'s own !important cannot bring a slot back', async () => {
  const { page } = await visit('other.test', '<style>.ad-banner { display: block !important }</style><div id="stubborn" class="ad-banner" style="display: block !important">ad</div>');
  await until(async () => (await hidden(page, ['stubborn'])).length === 1, 'the stubborn slot to be hidden');
  await page.close();
});

test('frames are filtered too: another site\'s, and one with no address of its own', async () => {
  server.page('frames.test', '/inner', `<!doctype html><body><div id="banner" class="ad-banner">ad</div><p id="content">kept</p></body>`);
  const { page } = await visit('news.test', `<iframe id="cross" src="${server.url('frames.test', '/inner')}"></iframe><iframe id="blank" srcdoc='<div id="banner" class="ad-banner">ad</div><p id="content">kept</p>'></iframe>`);
  for (const name of ['cross', 'blank']) {
    const frame = await (await page.$(`#${name}`)).contentFrame();
    await until(() => frame.evaluate(() => getComputedStyle(document.getElementById('banner')).display === 'none'), `the slot in the ${name} frame to be hidden`);
    assert.equal(await frame.evaluate(() => getComputedStyle(document.getElementById('content')).display), 'block');
  }
  await page.close();
});

test('nothing is hidden on a site let through, with hiding switched off, or from a list switched off', async () => {
  server.page('news.test', '/', `<!doctype html><body>${SLOTS}</body>`);
  const look = async () => {
    const { page } = await open(browser.context, server.url('news.test'));
    await page.waitForTimeout(700);
    const result = await hidden(page, ALL);
    await page.close();
    return result;
  };

  await browser.ask({ type: 'site:set', site: 'news.test', allowed: true });
  assert.deepEqual(await look(), []);
  await browser.ask({ type: 'site:set', site: 'news.test', allowed: false });

  await browser.ask({ type: 'settings:set', patch: { cosmetic: false } });
  assert.deepEqual(await look(), []);
  await browser.ask({ type: 'settings:set', patch: { cosmetic: true } });

  const off = await browser.ask({ type: 'ruleset:set', id: 'easyprivacy', enabled: false });
  assert.deepEqual(off.enabled.sort(), ['easylist', 'stillwater']);
  assert.deepEqual(await look(), [...GENERIC.slice(0, 5), 'story', 'rail', 'labelled'], 'the tracker list\'s pixel is no longer hidden');
  const { page, stopped } = await visit('other.test', script('tracker.test'));
  assert.deepEqual(stopped, [], 'nor its host blocked');
  await page.close();
  await browser.ask({ type: 'ruleset:set', id: 'easyprivacy', enabled: true });
  assert.deepEqual(await look(), [...GENERIC.slice(0, 5), 'story', 'rail', 'pixel', 'labelled']);
});

const WORDS = `
  <div class="page" id="page" style="padding-top: 90px">
    <div id="card-ad" class="card"><span>Sponsored</span> A thing to buy.</div>
    <div id="card" class="card">A story.</div>
    <ul><li id="li-ad"><span class="label">Advert</span> Buy it.</li><li id="li-deep"><p><span class="label">Ad</span></p> Not a child.</li><li id="li">A link.</li></ul>
    <h2 id="heading" class="heading">Our partners</h2><ul id="partners"><li>One</li></ul><ul id="after">kept</ul>
    <div id="row-ad" class="row">Promoted <div id="media-ad" class="media">ad</div></div>
    <div id="row-own" class="row own">Promoted <div id="media-own" class="media">own</div></div>
    <div id="feed" class="feed"><div id="feed-ad">Paid post</div><div id="feed-story">A story.</div></div>
  </div>`;
const WORD_IDS = ['card-ad', 'card', 'li-ad', 'li-deep', 'li', 'heading', 'partners', 'after', 'row-ad', 'media-ad', 'row-own', 'media-own', 'feed', 'feed-ad', 'feed-story'];

test('filters that pick an element by its words hide it: plain, by expression, inside :has, and going on to a sibling or child', async () => {
  const { page } = await visit('words.test', WORDS);
  await until(async () => (await hidden(page, WORD_IDS)).length >= 5, 'the worded slots to be hidden');
  // The last is found among a feed's children: the feed itself, which holds the words too, is left.
  assert.deepEqual(await hidden(page, WORD_IDS), ['card-ad', 'li-ad', 'partners', 'media-ad', 'feed-ad']);

  // Words that arrive later are found too.
  await page.evaluate(() => {
    document.getElementById('card').insertAdjacentHTML('afterend', '<div id="late" class="card">Sponsored again</div>');
    document.getElementById('li').insertAdjacentHTML('afterbegin', '<span class="label">ad</span>');
  });
  await until(async () => (await hidden(page, ['late', 'li'])).length === 2, 'the late worded slots to be hidden');
  await page.close();
});

test('a restyling filter restyles what is left, over the page\'s own style', async () => {
  const { page } = await visit('words.test', WORDS);
  await until(() => page.evaluate(() => getComputedStyle(document.getElementById('page')).paddingTop === '0px'), 'the page\'s padding to be taken away');
  await page.close();
  const other = await visit('other.test', WORDS);
  await other.page.waitForTimeout(500);
  assert.equal(await other.page.evaluate(() => getComputedStyle(document.getElementById('page')).paddingTop), '90px', 'only on the site named');
  assert.deepEqual(await hidden(other.page, WORD_IDS), []);
  await other.page.close();
});

test('an exception takes a worded filter back for its site', async () => {
  const { page } = await visit('quiet.words.test', WORDS);
  await until(async () => (await hidden(page, WORD_IDS)).length >= 4, 'the other worded slots to be hidden');
  assert.deepEqual(await hidden(page, WORD_IDS), ['li-ad', 'partners', 'media-ad', 'feed-ad']);
  await page.close();
});

test('a form whose fields are named for the DOM\'s own properties is read and hidden like anything else', async () => {
  // A form answers to its fields' names before its own properties: `form.style` is then a field.
  const fields = ['style', 'id', 'classList', 'className', 'nodeType', 'querySelectorAll', 'matches', 'getAttribute', 'textContent', 'nextElementSibling'].map((name) => `<input name="${name}">`).join('');
  const { page } = await visit(
    'words.test',
    `<form id="form-generic" class="ad-banner">${fields}</form>
     <form id="form-worded" class="card">${fields}Sponsored</form>
     <div class="heading">Our partners</div><form id="form-sibling">${fields}</form><ul id="list-after">kept</ul>
     <div id="card-after" class="card">Sponsored too</div>`,
  );
  const ids = ['form-generic', 'form-worded', 'form-sibling', 'list-after', 'card-after'];
  await until(async () => (await hidden(page, ids)).length >= 3, 'the forms to be hidden');
  // The sibling filter is for a list after the heading; the form between them is passed over and the list is not its next sibling.
  assert.deepEqual(await hidden(page, ids), ['form-generic', 'form-worded', 'card-after'], 'and the plans after the form\'s go on working');
  await page.close();
});

test('a page whose images are named for the document\'s own properties is read and hidden like any other', async () => {
  // The document answers to the names of images in it before its own properties: `document.querySelectorAll` is then an image.
  const images = ['querySelectorAll', 'querySelector', 'documentElement', 'readyState', 'addEventListener', 'body'].map((name) => `<img name="${name}" alt="">`).join('');
  const { page } = await visit('words.test', `${images}<div id="generic" class="ad-banner">ad</div><div id="worded" class="card">Sponsored</div><div id="kept" class="card">A story.</div>`);
  assert.equal(await page.evaluate(() => typeof document.querySelectorAll), 'object', 'the page itself can no longer ask its document');
  await until(async () => (await page.evaluate(() => ['generic', 'worded'].filter((id) => getComputedStyle(document.getElementById(id)).display === 'none').length)) === 2, 'both slots to be hidden');
  assert.equal(await page.evaluate(() => getComputedStyle(document.getElementById('kept')).display), 'block');
  // And what comes later is still seen.
  await page.evaluate(() => document.getElementById('kept').insertAdjacentHTML('afterend', '<div id="late" class="card">Sponsored later</div><div id="late-generic" class="ad-banner">ad</div>'));
  await until(async () => (await page.evaluate(() => ['late', 'late-generic'].filter((id) => getComputedStyle(document.getElementById(id)).display === 'none').length)) === 2, 'the later slots to be hidden');
  await page.close();
});

test('after all of that, Chromium holds nothing against the extension', async (t) => {
  const held = await complaints(browser);
  if (!held) return t.skip('this Chromium has no extensions page to ask');
  assert.deepEqual(held, { state: 'ENABLED', warnings: [], manifest: [], errors: [] });
});
