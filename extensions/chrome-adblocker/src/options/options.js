// The options page: the lists, the sites let through, the switches, and
// what Stillwater cannot do, said plainly.

import { ask } from '../shared/ask.js';
import { siteFromInput } from '../shared/sites.js';
import { limitWords, listDetail, sourceWords, SWITCHES } from '../shared/words.js';

const $ = (id) => document.getElementById(id);

/** An element with text, classes and attributes. */
function make(tag, { text, className, ...attributes } = {}, children = []) {
  const element = document.createElement(tag);
  if (text !== undefined) element.textContent = text;
  if (className) element.className = className;
  for (const [name, value] of Object.entries(attributes)) element.setAttribute(name, value);
  element.append(...children);
  return element;
}

/** A switch that says its own name and state, and calls `change` with the state asked for. */
function switchFor(name, on, change) {
  const button = make('button', { className: 'switch', type: 'button', role: 'switch', 'aria-checked': String(on), 'aria-label': name }, [make('span', { className: 'moon' })]);
  button.addEventListener('click', () => change(button.getAttribute('aria-checked') !== 'true'));
  return button;
}

function row(title, detail, control) {
  return make('li', {}, [make('div', { className: 'about' }, [make('p', { className: 'title', text: title }), make('p', { className: 'detail', text: detail })]), control]);
}

let overview = null;
const switches = { lists: new Map(), settings: new Map() };

/** Says what went wrong where it will be read, and heard. */
function problem(error) {
  $('problem').textContent = error ? `Stillwater could not do that: ${error.message ?? error}` : '';
}

/** Asks the worker for something that changes what is shown, and shows what came of it. */
async function change(message) {
  try {
    const answer = await ask(message);
    overview = answer.lists ? answer : { ...overview, settings: answer.settings };
    problem(null);
  } catch (error) {
    problem(error);
  }
  show();
}

/** Lays the page out, once. What changes after is changed in place, so a switch just pressed keeps the keyboard. */
function lay() {
  const { lists, version } = overview;
  $('lists').replaceChildren(
    ...lists.lists.map((list) => {
      const control = switchFor(list.title, false, (on) => change({ type: 'ruleset:set', id: list.id, enabled: on }));
      switches.lists.set(list.id, control);
      return row(list.title, listDetail(list), control);
    }),
  );
  $('switches').replaceChildren(
    ...SWITCHES.map(({ key, title, detail }) => {
      const control = switchFor(title, false, (on) => change({ type: 'settings:set', patch: { [key]: on } }));
      switches.settings.set(key, control);
      return row(title, detail, control);
    }),
  );
  $('limits').replaceChildren(...limitWords(lists).map(([lead, rest]) => make('li', {}, [make('strong', { text: lead }), ` ${rest}`])));
  $('about').textContent = `Nullmere Stillwater ${version}.`;
}

function show() {
  const { settings, enabled, lists } = overview;
  for (const [id, control] of switches.lists) control.setAttribute('aria-checked', String(enabled.includes(id)));
  for (const [key, control] of switches.settings) control.setAttribute('aria-checked', String(settings[key]));
  $('lists-foot').textContent = sourceWords(lists, enabled);

  // The sites: laid out afresh only when they have changed.
  const listed = [...$('sites').querySelectorAll('.title')].map((title) => title.textContent);
  if (listed.join('\n') === settings.allowlist.join('\n') && $('sites').children.length) return;
  const sites = settings.allowlist.map((site) => {
    const remove = make('button', { className: 'caps act quiet-act', type: 'button', text: 'Still again', 'aria-label': `Stop letting ${site} through` });
    remove.addEventListener('click', async () => {
      const after = settings.allowlist[settings.allowlist.indexOf(site) + 1];
      await change({ type: 'site:set', site, allowed: false });
      // The keyboard goes to the site that took this one's place, or to the field.
      const next = [...$('sites').querySelectorAll('button')].find((button) => button.getAttribute('aria-label') === `Stop letting ${after} through`);
      (next ?? $('site-input')).focus();
    });
    return make('li', {}, [make('div', { className: 'about' }, [make('p', { className: 'title', text: site })]), remove]);
  });
  $('sites').replaceChildren(...(sites.length ? sites : [make('li', {}, [make('p', { className: 'detail empty', text: 'No site is let through.' })])]));
}

$('site-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const site = siteFromInput($('site-input').value);
  if (!site) {
    $('site-error').textContent = 'That is not a site. Write it as example.com.';
    return;
  }
  $('site-error').textContent = '';
  $('site-input').value = '';
  await change({ type: 'site:set', site, allowed: true });
});

$('site-input').addEventListener('input', () => {
  $('site-error').textContent = '';
});

let armed = 0;
$('reset').addEventListener('click', async () => {
  // Asked twice, a few seconds apart at most: it forgets the sites let through.
  if (Date.now() - armed > 5000) {
    armed = Date.now();
    $('reset').textContent = 'Press again to put everything back';
    setTimeout(() => {
      if (Date.now() - armed >= 5000) $('reset').textContent = 'Put everything back as installed';
    }, 5100);
    return;
  }
  armed = 0;
  $('reset').textContent = 'Put everything back as installed';
  await change({ type: 'reset' });
});

overview = await ask({ type: 'overview' });
lay();
show();
document.body.dataset.ready = 'true';

// A change made elsewhere (the popup, another window) shows here too.
chrome.storage.onChanged.addListener(async () => {
  overview = await ask({ type: 'overview' });
  show();
});
