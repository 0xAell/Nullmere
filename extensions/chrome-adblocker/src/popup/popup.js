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
  // Picking something to hide, on a page Stillwater is filtering.
  $('pick').hidden = !state.filterable || state.allowed || state.paused;
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
    try {
      if (state.paused) await ask({ type: 'settings:set', patch: { paused: false } });
      else await ask({ type: 'site:set', site: state.site, allowed: !state.allowed, tabId });
      await refresh();
    } catch (error) {
      $('words').textContent = `Stillwater could not do that: ${error.message ?? error}`;
    }
  };
  $('moon').addEventListener('click', press);
  $('act').addEventListener('click', press);

  // The picker, put into the page; the popup gets out of its way.
  $('pick').addEventListener('click', async () => {
    try {
      const answer = await ask({ type: 'picker:start', tabId });
      if (answer?.error) throw new Error(answer.error);
      window.close();
    } catch (error) {
      $('words').textContent = `Stillwater could not do that: ${error.message ?? error}`;
    }
  });

  // The options page, in the tab it already has if it is open.
  $('options').addEventListener('click', (event) => {
    event.preventDefault();
    chrome.runtime.openOptionsPage();
  });

  // The count goes on rising while the page loads.
  setInterval(() => refresh().catch(() => {}), 1000);
}

main();
