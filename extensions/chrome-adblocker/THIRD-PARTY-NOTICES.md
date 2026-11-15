# Third-party notices

Nullmere Stillwater's own code, art and supplement list are part of
Nullmere and are licensed, like the rest of it, under the GNU Affero
General Public License, version 3 only (the `LICENSE` file at the root of
the repository, and of the packaged extension).

It could not block anything without the work of others. That work is
named here, with the terms it is used under.

## EasyList and EasyPrivacy

- **What:** the filter lists EasyList and EasyPrivacy.
- **By:** the EasyList authors (Fanboy, MonztA, Khrin, Yuki2718 and the
  lists' many contributors). <https://easylist.to/>
- **Source:** <https://github.com/easylist/easylist>, at the commit named
  in `lists/sources.json` (and in `lists.json` inside the packaged
  extension).
- **Licence:** the lists are dual licensed under the GNU General Public
  License, version 3 or later, and the Creative Commons
  Attribution-ShareAlike 3.0 Unported licence or later; either may be
  chosen. See <https://easylist.to/pages/licence.html>. Stillwater uses
  them under the **GNU General Public License, version 3 or later**, whose
  text is in `licences/GPL-3.0.txt`. (That licence's section 13 is what
  lets a work under it be combined with one under the Affero licence.)

**Where they are, and how they are changed:**

- `lists/easylist.txt` and `lists/easyprivacy.txt` are the lists
  themselves, assembled by `tools/refresh-lists.js` from the files of the
  repository above exactly as the lists' own templates
  (`easylist.template`, `easyprivacy.template`) set them out. Two comment
  lines saying so are added under each list's first line. Nothing else is
  changed.
- `rules/easylist.json`, `rules/easyprivacy.json`, `cosmetic/easylist.json`,
  `cosmetic/easyprivacy.json`, `popups/easylist.json` and
  `popups/easyprivacy.json` in the built and packaged extension are
  **derived from** those lists by `tools/build.js`: the same filters,
  rewritten in the form Chrome's declarativeNetRequest API and this
  extension's own scripts take. Filters that cannot be expressed are left
  out; the build prints how many, and why. These derived files are
  distributed under the same licence as the lists, the GNU General Public
  License, version 3 or later.

The lists are provided by their authors without warranty of any kind. The
EasyList authors do not endorse Nullmere Stillwater, and any fault in how
their filters are converted or applied is this project's, not theirs.

## Nothing else

The extension ships no other third-party code, fonts, images or sounds.
Its icons and the art of its pages are drawn by its own code
(`tools/make-icons.js`, the pages' own styles). Its tests use
[Playwright](https://playwright.dev/) (Apache License 2.0), which is not
part of the packaged extension.
