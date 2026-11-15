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

function show() {
  const { settings, enabled, lists, version } = overview;

  $('lists').replaceChildren(
    ...lists.lists.map((list) =>
      row(list.title, listDetail(list), switchFor(list.title, enabled.includes(list.id), async (on) => {
        overview = await ask({ type: 'ruleset:set', id: list.id, enabled: on });
        show();
      })),
    ),
  );
  $('lists-foot').textContent = sourceWords(lists, enabled);

  const sites = settings.allowlist.map((site) => {
    const remove = make('button', { className: 'caps act quiet-act', type: 'button', text: 'Still again', 'aria-label': `Stop letting ${site} through` });
    remove.addEventListener('click', () => change({ type: 'site:set', site, allowed: false }));
    return make('li', {}, [make('div', { className: 'about' }, [make('p', { className: 'title', text: site })]), remove]);
  });
  $('sites').replaceChildren(...(sites.length ? sites : [make('li', {}, [make('p', { className: 'detail empty', text: 'No site is let through.' })])]));

  $('switches').replaceChildren(
    ...SWITCHES.map(({ key, title, detail }) => row(title, detail, switchFor(title, settings[key], (on) => change({ type: 'settings:set', patch: { [key]: on } })))),
  );

  $('limits').replaceChildren(
    ...limitWords(lists).map(([lead, rest]) => make('li', {}, [make('strong', { text: lead }), ` ${rest}`])),
  );
  $('about').textContent = `Nullmere Stillwater ${version}.`;
}

/** Asks the worker for a change to the settings and shows what came of it. */
async function change(message) {
  const answer = await ask(message);
  overview = { ...overview, settings: answer.settings };
  show();
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
  overview = await ask({ type: 'reset' });
  show();
});

overview = await ask({ type: 'overview' });
show();
document.body.dataset.ready = 'true';
