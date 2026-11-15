# Nullmere Stillwater

An ad blocker for Chrome, in Nullmere's own look: a black lake, a full
moon, and nothing moving on the water. It blocks ads and trackers with
[EasyList](https://easylist.to/) and EasyPrivacy, hides the slots they
leave, and keeps out of the way.

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

- **The moon is the switch.** Full, with its light on the water:
  Stillwater is filtering this site. Press the moon, or *Let this site
  through*, and the site is reloaded with nothing blocked or hidden on it
  or its subdomains; the moon turns new. Press again to still it.
- **Options** opens a page with the filter lists (each can be switched
  off), the sites let through, and four switches: hiding ad slots,
  YouTube, the count on the icon, and a pause for everything.

<img src="docs/options.png" width="640" alt="The options page: the three lists with their numbers and switches, two sites let through, and the switches">

## What it does

| | |
|---|---|
| **Blocks requests** | 135,154 filters from EasyList, EasyPrivacy and a short list of Stillwater's own become 12,973 rules for Chrome's `declarativeNetRequest`, inside the 30,000 Chrome guarantees every extension. Filters for whole hosts are merged, so 94,503 hosts are blocked by 341 of those rules. |
| **Hides ad slots** | 30,934 selectors. A site's own are applied as its pages begin. The 13,637 generic ones are not thrown at every page: a content script tells the extension which classes and ids a page has, and only the selectors that could match are added. They are added as the user's own style, so a page's `!important` can't undo them. |
| **Follows worded filters** | 283 filters pick an element by the words in it (*hide the card whose label says Sponsored*). No style sheet can; the content script follows them as short plans. |
| **Lets sites through** | Per site, from the popup or the options page, subdomains included. |
| **YouTube** | Takes the ad lists out of the data YouTube's player reads, skips or runs out an ad that plays anyway, and hides promoted tiles. Best effort: see below. |
| **Sends nothing anywhere** | The extension makes no request of its own. No account, no telemetry, no remote code, no "acceptable ads". |

The numbers are those of the lists as they stood on 15 November 2026,
commit [`4f2a9139`](https://github.com/easylist/easylist/commit/4f2a9139d44ec4e71d82ca48f86fc2a717ba603f)
of the EasyList authors' repository. A test holds this file to the build.

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
  | Pop-up filters (`$popup`) | 2,969 | Chrome's rules can't close a window a page opens. |
  | Redirects and rewrites (`$redirect`, `$rewrite`) | 38 | They swap a request for a harmless stand-in; these rules can only block or allow. |
  | Scriptlets and procedural filters beyond `:has-text` | 43 | They need a script run in the page (`+js(...)`, `:xpath`, `:-abp-properties`). |
  | Regular expressions Chrome refuses | 15 | Chrome's engine has no lookahead and refuses expressions that compile too large. `tools/validate.js` asks a real Chromium which. |
  | Hiding exceptions for part of a site | 13 | Only an exception for a whole host can be looked up when a page's selectors are chosen. |
  | Others | 7 | Four selectors Chromium can't read, two filters for addresses that are not hosts, and one that would match every request. |

  That is 3,085 of 135,154 filters, 2.3%. Nothing is approximated in a
  way that blocks more than the filter meant.

**YouTube is the hardest, and this part is not verified against YouTube.**
Its ads come from the same hosts as its videos, so no rule can block
them. What Stillwater does there is tested against a stand-in page shaped
like YouTube's where it matters (see `test/e2e/youtube.test.js`), from a
machine that could not reach YouTube. Whether YouTube still has that shape
today is unverified. YouTube changes its player often and works against ad
blockers; expect this part to break first, and to need the *YouTube*
switch turned off, or `youtube.com` let through, if YouTube objects.

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
Linux), loading the unpacked extension. It has not been installed by hand
in Google Chrome on a Mac or Windows machine, and the toolbar icon and
badge have not been looked at on a real toolbar. The popup and options
pictures here are the real pages, taken in that Chromium.

## Why it asks for what it asks for

| Permission | What it is used for |
|---|---|
| `declarativeNetRequest` | The rules that block requests. |
| `declarativeNetRequestFeedback` | Reading Chrome's count of what it blocked on a tab, for the popup. |
| `storage` | The sites let through and the switches. Kept on this computer. |
| `scripting` | Adding the style that hides ad slots to a page, and registering the YouTube script only while its switch is on. |
| Access to all sites | The content script that reports a page's classes and ids and follows the worded filters. It reads class names, ids, and for worded filters the text of the elements a list points at; none of it leaves the browser. |

## How it is put together

```
lists/        EasyList and EasyPrivacy at a named commit, and Stillwater's own short list
tools/        refresh-lists.js, build.js, validate.js, package.js, make-icons.js, shots.js
  lib/        filters.js (reads the lists)   dnr.js (makes Chrome's rules)
              cosmetic.js, procedural.js (what to hide)   zip.js, png.js
src/          the extension as written: manifest, service worker, content scripts, pages, icons
build/        the extension as Chrome loads it: src/ plus rules/ and cosmetic/ (not kept in git)
dist/         the packed build
test/unit/    the converter, the cosmetic data, sites, wording, the zip
test/e2e/     the unpacked extension in Chromium against a stand-in for every host
```

- `tools/lib/filters.js` reads Adblock Plus syntax. `tools/lib/dnr.js`
  turns network filters into rules and checks each against what Chrome
  requires. `tools/lib/cosmetic.js` sorts selectors into those for named
  sites, generic ones keyed by the class or id they need, and exceptions.
- `src/background/service-worker.js` keeps three dynamic rules (the sites
  let through, and the pause), chooses what each frame hides, and answers
  the pages. It holds nothing that can't be made again, since Chrome stops
  it when idle.
- The icons are drawn by `tools/make-icons.js` from a few shapes: nothing
  is traced or taken from anywhere.

## Working on it

```sh
npm test             # 60-odd unit tests, Node alone
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

## Licences and thanks

Stillwater's own code, art and list are part of Nullmere, under the GNU
Affero General Public License, version 3 only, like the rest of it.

EasyList and EasyPrivacy are the work of the EasyList authors and their
contributors, used under the GNU General Public License, version 3 or
later. The rules and selectors in the packed extension are derived from
them and carry the same licence.
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) says exactly what is
taken, from where, and how it is changed. The EasyList authors do not
endorse this extension; faults in how their filters are converted are
this project's.

The way YouTube's player response is pruned follows what the
[uBlock Origin](https://github.com/gorhill/uBlock) project worked out;
no code of theirs is used.
