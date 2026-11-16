# Nullmere Stillwater: the design

Stillwater is the ad blocker for Chrome in `extensions/chrome-adblocker/`.
Its core design is settled: the architecture, the rule pipeline, the theme
and interface, the file layout and the test plan below are what is built
and tested. This note gathers them in one place for whoever takes the work
on. The extension's own [README](../extensions/chrome-adblocker/README.md)
is the user's account, with the numbers, the live-web results and the
limits in full. This note lives outside the extension's folder on purpose:
any change under that folder starts the extension's whole workflow.

## What it is held to

- **Manifest V3**, Chrome 121 or later. Chrome does the blocking, from
  rules compiled ahead of time; the extension never sees a request's body.
- **Nothing sent anywhere.** It makes no request of its own: no account,
  no telemetry, no remote code, no "acceptable ads", no list fetched at
  run time. The lists are as new as the version installed.
- **Original work.** Its code, icons and words are its own. EasyList and
  EasyPrivacy are used under their licences (`THIRD-PARTY-NOTICES.md`,
  `licences/`). AGPL-3.0-only, as the repository is.
- **Honest about its limits.** Whatever Manifest V3 cannot do is said in
  the README and the options page. It is never papered over.

## Architecture

Two halves: what is worked out at build time, and what runs in the browser.

**At build time** (`tools/`, Node 20, no dependencies but Playwright for
tests): the lists, pinned at an EasyList commit, become Chrome's static
rules, the cosmetic data, the pop-up data and the procedural plans in
`build/`. See the rule pipeline below.

**In the browser** (`src/`):

| Part | Runs | Does |
|---|---|---|
| `background/service-worker.js` | as Chrome wakes it (a module) | Keeps the three dynamic rules (sites let through, their requests, the pause); chooses what each frame hides and inserts it as the **user's** style (`scripting.insertCSS`, `origin: 'USER'`), so a page's `!important` can't undo it; closes pop-up ads (`webNavigation`); sets the icon (on, or the new-moon "off" icon for a site let through or a pause) and the badge; answers the popup, the options page and the content scripts. It holds nothing it can't rebuild when Chrome stops it, but which tabs pages opened in the last ten seconds. |
| `content/cosmetic.js` | every page and frame, at `document_start` | Tells the worker which classes and ids the page has, so only generic selectors that could match are sent (13,637 of them otherwise); runs the worded ("procedural") filters as short plans: hide the card whose label says *Sponsored*. |
| `content/youtube.js` and `youtube-main.js` | YouTube only, the second in the page's own world (`world: 'MAIN'`), registered only while the YouTube switch is on | Takes the ad lists out of the data YouTube's player reads, skips or runs out an ad that plays anyway, hides promoted tiles. Best effort. |
| `popup/` | the toolbar button | The state of this page, and letting its site through or not. |
| `options/` | a tab of its own | The lists, the sites let through, the switches, the limits, about, and putting everything back. |
| `shared/` | imported by all the above | `settings.js` (one `settings` object in `chrome.storage.local`), `sites.js` (sites from hosts, the dynamic rules), `cosmetic-lookup.js`, `popups.js`, `patterns.js`, `ask.js` (messages), `words.js` (every sentence shown), `theme.css`. |

**Settings** (`shared/settings.js`, `DEFAULTS`): `allowlist` (sites let
through, subdomains included), `paused`, `cosmetic`, `youtube`, `popups`,
`badge`, `listsOff` (rulesets switched off, kept because Chrome forgets
which rulesets were enabled when the extension updates).

**Dynamic rules** (`shared/sites.js`): ids 1 (`allowAllRequests` for the
sites let through), 2 (the pause) and 3 (the sites' own requests), at
priority 1000, above every static rule. They are rewritten whole from the
settings whenever the settings change and whenever the worker starts.

## The rule pipeline

```
lists/ (EasyList, EasyPrivacy at a named commit; stillwater.txt, its own short list)
  -> tools/lib/filters.js     Adblock Plus syntax read into filters
  -> tools/lib/dnr.js         network filters -> declarativeNetRequest rules, one ruleset a list
                              (easylist, easyprivacy, stillwater); whole-host filters merged into
                              requestDomains; every rule checked against Chrome's requirements;
                              the total kept inside the 30,000 static rules Chrome guarantees
  -> tools/lib/cosmetic.js    hiding selectors: for named sites, generic ones keyed by the class
     tools/lib/selectors.js   or id they need, and exceptions
  -> tools/lib/procedural.js  :has-text() and its kind -> short plans the content script runs
  -> tools/lib/popups.js      $popup filters -> a set of hosts and a few hundred expressions
  -> build/rules/, build/cosmetic/, build/popups/, beside a copy of src/
```

`tools/validate.js` asks Chromium itself which regular expressions and
selectors it refuses, and records them in `lists/rejected.json`. The next
build leaves them out. `tools/refresh-lists.js` brings `lists/` up to a new
EasyList commit; the README's numbers are then updated (a unit test says
which). `tools/package.js` makes `dist/nullmere-stillwater-<version>.zip`,
byte for byte the same from the same sources.

## Theme and interface

The look is Nullmere's night: a black lake, a full moon and nothing moving
on the water.

- **Colours** (`shared/theme.css`, custom properties): night `#040508`,
  with `#070b14` above and `#020306` below; ink `#e4eaf2`; glow `#96b4e1`;
  moon `#e9eef6`; words, quiet and faint as ink at 92, 64 and 42 per cent;
  lines in glow at 20 and 42 per cent; `#f2a399` for a problem only. Dark
  colour scheme only.
- **Type**: the system face at weight 300. The game's spaced capitals
  (`.caps`: 10.5 px, tracking 0.24 em, uppercase, quiet) name things.
  Numbers stand large and alone.
- **Stillness**: a few fixed stars, and nothing that twinkles, pulses or
  slides. A state changes by what stands, not by motion.
- **The moon is the switch.** Full, with its light on the water: this site
  is blocked. New, a thin ring with nothing on the water: this site is let
  through. The toolbar icon follows (`icons/icon-*` and `icons/off-*`, drawn
  from a few shapes by `tools/make-icons.js`, nothing traced).
- **Popup**, top to bottom: the name in capitals; the moon (a button,
  `aria-pressed`, that lets the site through or not); the count of requests
  kept from this page (`aria-live`) and its label; the site; a sentence of
  what is so; an action where one is wanted; Options and the version.
- **Options**, as sections with headings: the lists (each switchable, with
  its size); sites let through (listed, removable, added by name); the
  switches (hiding slots, YouTube, pop-ups, the badge, pause); what it
  cannot do; about; and one button that puts everything back as installed.
- **Words**: every sentence is in `shared/words.js`, plain and short, with
  no jargon (no "DNR", "cosmetic" or "allowlist" shown to the user).
  `test/unit/words.test.js` holds them.
- **Access**: every control is a real button or input with a label; focus
  shows as a glow outline; sections are labelled for screen readers.
  Screenshots of the popup and the options page are in
  `extensions/chrome-adblocker/docs/`, made by `tools/shots.js`.

## File layout

```
extensions/chrome-adblocker/
  lists/         EasyList and EasyPrivacy at a named commit, stillwater.txt, rejected.json
  tools/         refresh-lists.js build.js validate.js package.js make-icons.js shots.js live-check.js
    lib/         filters.js dnr.js cosmetic.js selectors.js procedural.js popups.js zip.js png.js
  src/           manifest.json; background/ content/ popup/ options/ shared/ icons/
  build/         src/ plus rules/, cosmetic/ and popups/, as Chrome loads it (not kept in git)
  dist/          the packed zip (kept, and checked to be exactly a fresh build)
  test/unit/     Node's test runner, no browser
  test/e2e/      the unpacked build in Chromium, through Playwright
  docs/          the README's pictures
```

## Test plan

- **Unit** (`npm test`, some 80 tests, Node alone): the filter reader and
  the converter to Chrome's rules (each rule valid, hosts merged, the
  limits kept), the cosmetic and procedural data, the pop-up data, sites
  and the dynamic rules, the words, the zip, the list refresh, the sources'
  licences, and the README's numbers held to the build.
- **Browser** (`npm run test:e2e`, some 95 tests, Playwright's Chromium):
  the unpacked build, with every host name pointed at a local server, so a
  page may ask for real ad hosts and the test sees which requests never
  arrive. Nothing goes out to the network. Covered: blocking by each
  list, filters of every kind the lists use (51), real page shapes,
  pop-ups closed (and tabs the user opens never touched), the worker
  stopped and started again with nothing lost, the YouTube stand-in, and
  the packed zip loaded as Chrome would.
- **CI**: the *Ad blocker* workflow (`.github/workflows/adblocker.yml`) runs
  the unit tests, the build and the browser tests on every change under the
  extension's folder, checks that `dist/` is exactly a fresh build, and keeps
  the zip as the run's artifact.
- **The live web**: the *Ad blocker, on the live web* workflow, run by hand,
  loads real pages with and without the extension and reports requests,
  what was kept back, ad-sized frames, text and page errors. It fails only
  if Chromium holds an error against the extension. Its third run's table
  is in the README.

## Where it stands, and what is left

Built and tested as above, and seen on the live web from GitHub's machines.
Still unverified: a person using it in Google Chrome itself, and YouTube's
real watch pages, which turned GitHub's machines away. Left for whoever
continues it: a Chrome Web Store listing (it needs the maintainer's
developer account), list refreshes as EasyList moves, and the YouTube part
kept up as YouTube changes.
