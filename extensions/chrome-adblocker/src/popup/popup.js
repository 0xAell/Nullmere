// The popup: what Stillwater is doing on the page in front, and the one
// choice to make about it.

import { ask } from '../shared/ask.js';
import { wording } from '../shared/words.js';

const $ = (id) => document.getElementById(id);

function show(state) {
  const words = wording(state);
  $('lake').dataset.state = words.name;
  $('moon').classList.toggle('new', words.name !== 'still');
  $('moon').setAttribute('aria-pressed', String(words.name === 'still'));
  $('moon').setAttribute('aria-label', words.moon);
  $('moon').disabled = !state.filterable;
  $('count').textContent = words.count;
  $('count').hidden = words.count === '';
  $('count-label').textContent = words.label;
  $('site').textContent = words.site || ' ';
  $('words').textContent = words.words;
  $('act').textContent = words.act;
  $('act').hidden = !words.act;
}

async function main() {
  $('version').textContent = chrome.runtime.getManifest().version;
  // The tab in front; or, for the tests, the one named in the address.
  const named = Number(new URLSearchParams(location.search).get('tab'));
  const tabId = named || (await chrome.tabs.query({ active: true, currentWindow: true }))[0]?.id;
  let state = await ask({ type: 'state', tabId });
  show(state);

  const refresh = async () => {
    state = await ask({ type: 'state', tabId });
    show(state);
  };

  const press = async () => {
    if (!state.filterable) return;
    if (state.paused) await ask({ type: 'settings:set', patch: { paused: false } });
    else await ask({ type: 'site:set', site: state.site, allowed: !state.allowed, tabId });
    await refresh();
  };
  $('moon').addEventListener('click', press);
  $('act').addEventListener('click', press);

  // The count goes on rising while the page loads.
  setInterval(refresh, 1000);
}

main();
