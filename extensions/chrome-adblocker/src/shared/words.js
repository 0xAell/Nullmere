// The words the popup says. Kept apart from the page so they can be read
// and tested without a browser.

import { grouped } from './sites.js';

/** The words for each state the page in front can be in. */
export function wording(state) {
  if (!state.filterable) {
    return { name: 'none', count: '', label: 'Nothing to keep out', site: '', words: 'This is not a page Stillwater can filter.', act: '', moon: 'Stillwater does not filter this page.' };
  }
  if (state.paused) {
    return { name: 'paused', count: '', label: 'Paused', site: state.site, words: 'Stillwater is paused everywhere.', act: 'Resume', moon: 'Stillwater is paused everywhere. Press to resume.' };
  }
  if (state.allowed) {
    // Named as it is let through, which may be a site above this page's.
    const site = state.through || state.site;
    return { name: 'allowed', count: '', label: 'Let through', site, words: 'Nothing is kept from this site.', act: 'Still this site again', moon: `${site} is let through. Press to filter it again.` };
  }
  return {
    name: 'still',
    count: grouped(state.count),
    label: state.count === 1 ? 'Request kept from this page' : 'Requests kept from this page',
    site: state.site,
    words: 'The water is still.',
    act: 'Let this site through',
    moon: `Stillwater is filtering ${state.site}. Press to let this site through.`,
  };
}

/** The switches on the options page: the setting each one keeps, and what it says. */
export const SWITCHES = [
  { key: 'cosmetic', title: 'Hide the slots ads leave', detail: 'Elements the lists name as ad slots are hidden on the page.' },
  { key: 'popups', title: 'Close pop-up ads', detail: 'A tab or window a page opens to an address the lists name as a pop-up ad is closed.' },
  { key: 'youtube', title: 'YouTube', detail: 'Skip the ads that can be skipped and hide the ones that can be hidden. The part most likely to break: see below.' },
  { key: 'badge', title: 'Count on the icon', detail: 'Show how many requests were kept from the page in front.' },
  { key: 'paused', title: 'Pause everywhere', detail: 'Let everything through on every site until this is switched back.' },
];

/** What a list holds, in a line. */
export function listDetail(list) {
  const parts = [`${grouped(list.filters)} filters`];
  if (list.rules) parts.push(`${grouped(list.rules)} rules for Chrome`);
  if (list.cosmetic) parts.push(`${grouped(list.cosmetic)} selectors to hide`);
  if (list.popups) parts.push(`${grouped(list.popups)} pop-ups to close`);
  return list.filters ? parts.join(' · ') : 'Nothing in it yet.';
}

/** Where the lists came from and how much of Chrome's allowance they use. */
export function sourceWords(lists, enabled) {
  const day = new Date(lists.source.committed).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
  const inUse = lists.lists.filter((list) => enabled.includes(list.id)).reduce((sum, list) => sum + list.rules, 0);
  return `The lists as they stood on ${day} (commit ${lists.source.commit.slice(0, 8)} of the EasyList authors' repository). ${grouped(inUse)} of the ${grouped(lists.limits.guaranteedRules)} rules Chrome guarantees an extension are in use.`;
}

/** How many filters of the lists were left out for reasons that begin with any of `prefixes`. */
function leftOut(lists, ...prefixes) {
  let sum = 0;
  for (const list of lists.lists) {
    for (const [reason, count] of Object.entries(list.dropped)) {
      if (prefixes.some((prefix) => reason.startsWith(prefix))) sum += count;
    }
  }
  return sum;
}

/** What Stillwater cannot do, as [lead, rest] pairs: said on the options page as it is in the README. */
export function limitWords(lists) {
  const scripted = leftOut(lists, 'cosmetic:procedural', 'cosmetic:scriptlet', 'cosmetic:snippet', 'cosmetic:style');
  const others = leftOut(lists, '') - scripted;
  return [
    ['Chrome applies the rules, not Stillwater.', 'Under Manifest V3 an extension can no longer look at each request and decide. It hands Chrome rules made ahead of time, so the lists are as new as this version of Stillwater, not refreshed each day.'],
    ['Some filters have no rule to become.', `Left out of this build: ${grouped(scripted)} that would need a script Stillwater has not written or a page rewritten as it arrives, and ${grouped(others)} more that Chrome's rules can't say or Chrome refuses.`],
    ['A pop-up is closed, not prevented.', 'Chrome\'s rules can\'t stop a page opening a window. Stillwater closes one as soon as it sees where it is going, so it may show for a moment.'],
    ['YouTube is the hardest.', 'Its ads come from the same hosts as its videos, and it changes often. Stillwater hides and skips what it can there; expect that part to break first.'],
    ['An ad written into the page itself can only be hidden,', 'and only where a list names it. Nothing an extension does can tell it from the page\'s own words otherwise.'],
    ['Chrome\'s own pages, the Web Store and other extensions', 'are closed to every extension, this one included.'],
  ];
}
