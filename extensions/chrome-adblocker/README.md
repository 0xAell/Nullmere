# Nullmere Stillwater

An ad blocker for Chrome, in Nullmere's own look: a black lake, a full
moon, and nothing moving on the water. It blocks ads and trackers with
[EasyList](https://easylist.to/) and EasyPrivacy, hides the slots they
leave, closes the pop-ups, and keeps out of the way.

<p>
  <img src="docs/popup.png" width="300" alt="The popup: a full moon over a dark lake, its light on the water, and below it the number 27, requests kept from this page, on news.example">
  <img src="docs/popup-let-through.png" width="300" alt="The popup with the site let through: the moon is new, a thin ring, and nothing lies on the water">
</p>

It is a Manifest V3 extension, so Chrome itself does the blocking, from
rules made ahead of time. That has real limits, which are
[set out below](#what-it-cannot-do) rather than glossed over.

## Install

Stillwater is not on the Chrome Web Store. It is loaded from a folder.

1. Download [`dist/nullmere-stillwater-1.0.0.zip`](dist/nullmere-stillwater-1.0.0.zip)
   and unzip it somewhere it can stay (Chrome loads it from there each
   time it starts).
2. Open `chrome://extensions` and turn on **Developer mode** (top right).
3. Press **Load unpacked** and choose the unzipped folder, the one with
   `manifest.json` in it.
4. Pin it: the puzzle-piece button in the toolbar, then the pin beside
   Nullmere Stillwater.

To update, replace the folder's contents with a newer zip's and press the
reload arrow on its card in `chrome://extensions`. It needs Chrome 121 or
later.

To build it yourself instead (Node 20.15 or later, nothing to install):

```sh
cd extensions/chrome-adblocker
npm run build        # writes build/
```

and load `build/` the same way.

## Using it

The toolbar icon shows how many requests Chrome kept from the page in
front. Press it for the popup:

<img src="docs/toolbar.png" width="560" alt="The end of Chromium's toolbar: the address bar's star, then Stillwater's icon, a moon on a dark square, with a count of 3 on it, then the extensions menu, the profile and the browser's menu">


- **The moon is the switch.** Full, with its light on the water:
  Stillwater is filtering this site. Press the moon, or *Let this site
  through*, and the site is reloaded with nothing blocked or hidden on it
  or its subdomains; the moon turns new. Press again to still it.
- **Options** opens a page with the filter lists (each can be switched
  off), the sites let through, and five switches: hiding ad slots,
  closing pop-ups, YouTube, the count on the icon, and a pause for
  everything.

<img src="docs/options.png" width="640" alt="The options page: the three lists with their numbers and switches, two sites let through, and the switches">

## What it does

| | |
|---|---|
| **Blocks requests** | 135,154 filters from EasyList, EasyPrivacy and a short list of Stillwater's own become 12,997 rules for Chrome's `declarativeNetRequest`, inside the 30,000 Chrome guarantees every extension. Filters for whole hosts are merged, so 94,309 hosts are blocked by 184 of those rules. |
| **Gives stand-ins** | 37 filters keep a request back by giving the page something harmless of Stillwater's own in its place, where refusing it outright would leave the page waiting on it: an empty script, text or JSON, a one-pixel image, a second of silent video, or a few lines that answer as Google's tag manager, Chartbeat or fingerprintjs2 would and send nothing. Chrome serves them from the extension; nothing is fetched. |
| **Hides ad slots** | 30,934 selectors. A site's own are applied as its pages begin. The 13,637 generic ones are not thrown at every page: a content script tells the extension which classes and ids a page has, and only the selectors that could match are added. They are added as the user's own style, so a page's `!important` can't undo them. |
| **Follows worded filters** | 283 filters pick an element by the words in it (*hide the card whose label says Sponsored*). No style sheet can; the content script follows them as short plans. |
| **Closes pop-up ads** | 2,977 filters name the addresses of pop-up ads. A tab or window a page opens to one is closed: at once if it is opened straight there, or as it gets there if it is opened empty or by way of another address. A tab you open yourself (a new tab, a bookmark, an address you type) is never touched. |
| **Lets sites through** | Per site, from the popup or the options page, subdomains included. |
| **YouTube** | Takes the ad lists out of the data YouTube's player reads, skips or runs out an ad that plays anyway, and hides promoted tiles. Best effort: see below. |
| **Sends nothing anywhere** | The extension makes no request of its own. No account, no telemetry, no remote code, no "acceptable ads". |

The numbers are those of the lists as they stood on 15 November 2026,
commit [`4f2a9139`](https://github.com/easylist/easylist/commit/4f2a9139d44ec4e71d82ca48f86fc2a717ba603f)
of the EasyList authors' repository. A test holds this file to the build.

## On the live web

The tests above meet stand-ins: the machines Stillwater was written on
cannot reach the web. So the *Ad blocker, on the live web* workflow
loads it on real pages from one of GitHub's machines, each page once
without the extension and once with it (Chromium 153, headless, six
seconds after each page loaded). Its third run, on 16 November 2026:

| Page | Requests | Kept back | Ad-sized frames showing | Letters of text | Page errors |
|---|---|---|---|---|---|
| The Guardian | 584 → 137 | 28 | 0 → 0 | 17,731 → 17,489 | 0 → 19 |
| Speedtest | 3,402 → 36 | 8 | 5 → 0 | 909 → 909 | 0 → 0 |
| BBC News | 102 → 103 | 10 | 1 → 1 | 7,996 → 7,989 | 0 → 0 |
| The Independent | 245 → 80 | 26 | 1 → 0 | 9,730 → 8,774 | 0 → 0 |
| IGN | 570 → 158 | 18 | 2 → 0 | 6,422 → 6,465 | 0 → 0 |
| Wikipedia (no ads) | 45 → 45 | 2 | 0 → 0 | 67,856 → 67,856 | 0 → 0 |
| GitHub (no ads) | 118 → 119 | 5 | 0 → 0 | 3,449 → 3,523 | 0 → 0 |

*Without → with.* What a page asks for falls by as much as the ads it no
longer loads would have asked; what Chrome kept back is the number on
the icon, which matched on every page. The frame left on the BBC is its
consent dialog, there either way. Everything kept back from a site's own
hosts was a filter of EasyPrivacy's written for that address: analytics
beacons, telemetry and cookie syncing. The Guardian's nineteen errors
are all *Failed to fetch*, its own code finding its analytics refused,
and its text reads the same; the Independent's thousand fewer letters
are its ad and recommendation slots, hidden. Chromium held nothing
against the extension.

Some sites turn a headless browser away whatever it carries (Stack
Overflow, AccuWeather, the Daily Mail and Fandom answered 403, CNN an
empty page), and could not be judged. YouTube is one of them: see below.

## What it cannot do

**Chrome applies the rules, not Stillwater.** Under Manifest V3 an
extension can no longer look at each request and decide; it hands Chrome
rules made ahead of time. So:

- **The lists are as new as this version.** EasyList changes many times a
  day; Stillwater's copy changes when someone runs `npm run refresh` and
  ships a new build. An ad host that appeared last week is not blocked
  until then.
- **Some filters have no rule to become** and are left out. The build
  counts them:

  | Left out | How many | Why |
  |---|---|---|
  | Exceptions that take back only a stand-in (`$redirect-rule`) | 1 | They leave the block standing; Chrome's `allow` would take back both. |
  | Scriptlets and procedural filters beyond `:has-text` | 43 | They need a script run in the page (`+js(...)`, `:xpath`, `:-abp-properties`). |
  | Regular expressions Chrome refuses | 15 | Chrome's engine has no lookahead and refuses expressions that compile too large. `tools/validate.js` asks a real Chromium which. |
  | Hiding exceptions for part of a site | 13 | Only an exception for a whole host can be looked up when a page's selectors are chosen. |
  | Others | 7 | Four selectors Chromium can't read, two filters for addresses that are not hosts, and one that would match every request. |

  That is 79 of 135,154 filters, 0.1%. Nothing is approximated in a
  way that blocks more than the filter meant.

**A pop-up is closed, not prevented.** No rule of Chrome's can stop a page
opening a window, so Stillwater closes it as soon as it sees where it is
going: it may show for a moment, and its first request may already have
left. A tab is watched for ten seconds after a page opens it: wherever it
is redirected in that time, and wherever it goes in the two seconds after
it first shows a page, is taken for the page's doing, since Chrome does
not say whether a person pressed something. After that a link you press
in it is yours, and so is anywhere you go by the address bar. A link you
click yourself that opens a new tab to one of these addresses is closed
too, as it is by other blockers using these lists. An ad that takes over the tab
you were in, having moved the page you wanted into a new one, is not
caught.

**YouTube is the hardest, and this part is not verified against YouTube.**
Its ads come from the same hosts as its videos, so no rule can block
them. What Stillwater does there is tested against a stand-in page shaped
like YouTube's where it matters (see `test/e2e/youtube.test.js`). Run on
the live web, YouTube answered GitHub's machines with a refusal (429) or
an empty player, with the extension or without, so even that check never
saw a real watch page. Whether YouTube still has the stand-in's shape
today is unverified. YouTube changes its player often and works against ad
blockers; expect this part to break first, and to need the *YouTube*
switch turned off, or `youtube.com` let through, if YouTube objects. It
does not hide what it does: a page that looks can tell that the functions
it reads its data with have been wrapped. With the switch off, or
YouTube let through, nothing of that part runs in YouTube's pages at all.
A player embedded in a site you have let through is left alone only from
the moment the extension has looked the site up, which is after the
player has read its first data.

**The count is Chrome's.** Chrome counts what it blocked on each tab and
starts afresh as a navigation finishes. A request blocked in a page's very
first instant can be counted before that and lost: in tests here, about
one page load in seven showed a count one or two short. What was blocked
is not in doubt, only the number.

**An ad written into the page itself can only be hidden**, and only where
a list names it. Text ads a site serves from its own address look like the
site's own words to any extension.

**Chrome's own pages, the Web Store and other extensions** are closed to
every extension, this one included.

**Not yet run by a person in Google Chrome.** Everything above was checked
by automated tests in Chromium 153 (Playwright's build, headless, on
Linux), loading the unpacked extension, against stand-ins and on the
live web. The toolbar picture is Chromium's own window, on a virtual
display: the icon pinned and Chrome's count on it, read back as 3
before it was taken (`tools/toolbar.js`). It has not been installed by
hand in Google Chrome on a Mac or Windows machine. The popup and options
pictures here are the real pages, taken in that Chromium.

## Why it asks for what it asks for

When it is loaded Chrome says Stillwater can *read and change all your
data on all websites*, *read your browsing history* and *block content on
any page*. Those are Chrome's words for the permissions below. The second
is Chrome's name for two of them: reading its own count of what it
blocked, and being told when a page opens a tab and where that tab goes.
Stillwater reads the number, judges the pop-up's address, and keeps no
history of either.

| Permission | What it is used for |
|---|---|
| `declarativeNetRequest` | The rules that block requests. |
| `declarativeNetRequestFeedback` | Reading Chrome's count of what it blocked on a tab, for the popup. |
| `storage` | The sites let through and the switches. Kept on this computer. |
| `webNavigation` | Being told when a page opens a tab or window, and where it goes in its first seconds, so a pop-up ad can be closed. |
| `scripting` | Adding the style that hides ad slots to a page, and registering the two YouTube scripts only while their switch is on. |
| Access to all sites | The content script that reports a page's classes and ids and follows the worded filters. It reads class names, ids, and for worded filters the text of the elements a list points at; none of it leaves the browser. |

## How it is put together

```
lists/        EasyList and EasyPrivacy at a named commit, and Stillwater's own short list
tools/        refresh-lists.js, build.js, validate.js, package.js, make-icons.js, shots.js, toolbar.js,
              live-check.js (real pages, from a machine that can reach the web)
  lib/        filters.js (reads the lists)   dnr.js (makes Chrome's rules)
              redirects.js (the stand-ins, by every name the lists give them)
              cosmetic.js, procedural.js, selectors.js (what to hide)
              popups.js (which pop-ups to close)   zip.js, png.js
src/          the extension as written: manifest, service worker, content scripts, pages, icons,
              and redirects/, the stand-ins a request may be given instead
build/        the extension as Chrome loads it: src/ plus rules/, cosmetic/ and popups/ (not kept in git)
dist/         the packed build
test/unit/    the converter, the cosmetic and pop-up data, sites, wording, the zip
test/e2e/     the unpacked extension in Chromium against a stand-in for every host
```

- `tools/lib/filters.js` reads Adblock Plus syntax. `tools/lib/dnr.js`
  turns network filters into rules and checks each against what Chrome
  requires. `tools/lib/cosmetic.js` sorts selectors into those for named
  sites, generic ones keyed by the class or id they need, and exceptions.
- A filter that gives a stand-in (`$redirect=`, `$rewrite=abp-resource:`)
  becomes a rule that sends the request to a file in `src/redirects/`,
  every one written for Stillwater. Chrome ranks such a rule above the
  blocks and below the exceptions. The files are open to the pages they
  are given to only at an address Chrome makes afresh each session, so a
  page can't look for them to tell that Stillwater is there.
- `tools/lib/popups.js` turns pop-up filters into a set of hosts and a few
  hundred expressions; `src/shared/popups.js` judges an address by them.
- `src/background/service-worker.js` keeps three dynamic rules (the sites
  let through, and the pause), chooses what each frame hides, closes the
  pop-ups, and answers the pages. Chrome stops it when idle, so it holds
  nothing it can't make again, but for which tabs pages have opened in
  the last ten seconds.
- The icons are drawn by `tools/make-icons.js` from a few shapes: nothing
  is traced or taken from anywhere.

## Working on it

```sh
npm test             # some 80 unit tests, Node alone
npm run build        # lists/ -> build/
npm run test:e2e     # the unpacked build in Chromium (needs Playwright: npm ci && npx playwright install chromium)
npm run package      # build, then dist/nullmere-stillwater-<version>.zip
npm run refresh      # bring lists/ up to date with the EasyList repository
```

After a refresh: `npm run build && node tools/validate.js && npm run build`
(the middle step asks Chromium which regular expressions and selectors it
refuses and records them in `lists/rejected.json`), then
`npm run test:e2e`, `npm run package`, update the numbers in this file
(`npm test` says which), and commit.

The browser tests start a local server and tell Chromium that every host
name is that server, so pages can ask for real ad hosts and the tests can
see which requests never arrived. Nothing in them goes out to the network.

The **Ad blocker** workflow (`.github/workflows/adblocker.yml`) runs all
of it on every change under this folder, checks that the zip in `dist/`
is exactly a fresh build, and keeps the zip as the run's artifact.

The **Ad blocker, on the live web** workflow
(`.github/workflows/adblocker-live.yml`), run by hand, loads the build in
Chromium on real pages with and without the extension and reports what
it found (`node tools/live-check.js` does the same anywhere the web can
be reached; `LIVE_ONLY=YouTube` narrows it). It fails only if Chromium
holds an error against the extension: the web changes too often to hold
a page's numbers to anything.

## Licences and thanks

Stillwater's own code, art and list are part of Nullmere, under the GNU
Affero General Public License, version 3 only, like the rest of it.

EasyList and EasyPrivacy are the work of the EasyList authors and their
contributors, used under the GNU General Public License, version 3 or
later. The rules, selectors and pop-up addresses in the packed extension
are derived from them and carry the same licence.
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) says exactly what is
taken, from where, and how it is changed. The EasyList authors do not
endorse this extension; faults in how their filters are converted are
this project's.

The way YouTube's player response is pruned follows what the
[uBlock Origin](https://github.com/gorhill/uBlock) project worked out;
no code of theirs is used.
