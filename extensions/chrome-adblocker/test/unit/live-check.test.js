// The live check's report is read by people who cannot see the pages: its
// words must say what was found, not what was not looked at.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { youtubeWords } from '../../tools/live-check.js';

// As the live check found YouTube's watch page on 17 November 2026 (run 4).
const page = (youtube) => ({ name: 'YouTube', title: 'Rick Astley - Never Gonna Give You Up - YouTube', youtube });
const without = page({ response: true, playable: 'OK', adKeys: ['adPlacements', 'adBreakHeartbeatParams'], written: true, adShowing: false, player: true, video: true, playing: false, fetched: false, fetchedAdKeys: [] });
const withIt = page({ response: true, playable: 'OK', adKeys: [], written: true, adShowing: false, player: true, video: true, playing: true, seconds: 12.5, fetched: true, fetchedAdKeys: ['adPlacements'] });

test('the YouTube summary says what each run found in the page', () => {
  const words = youtubeWords(withIt, without);
  assert.match(words, /without the extension: the player's response came through \(OK\), with its ad lists: adPlacements, adBreakHeartbeatParams; an ad did not show in fifteen seconds; video present, not playing; the player fetched no data/);
  assert.match(words, /with it: the player's response came through \(OK\), with no ad lists in it; an ad did not show in fifteen seconds; video playing, 12.5 seconds in; the player fetched its data, which came with ad lists \(adPlacements\)/);
  assert.doesNotMatch(words, /player absent/);
});

test('a page with no player response is said to have none, and one not reached is said not to load', () => {
  const embed = { name: 'YouTube, embedded', title: 'YouTube', youtube: { response: false, written: false, adShowing: false, player: true, video: true, playing: false, fetched: false, fetchedAdKeys: [] } };
  assert.match(youtubeWords(embed, embed), /no player response was found on the page \(nor in the page as sent; player present\)/);
  assert.equal(youtubeWords({ name: 'YouTube' }, without), 'YouTube: the page did not load in one of the two runs.');
});
