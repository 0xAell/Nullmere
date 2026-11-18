<p align="center">
  <img src="Packaging/AppIcon.png" width="128" height="128" alt="Nullmere Online app icon: a full moon above a black lake, mirrored in the water">
</p>

<h1 align="center">Nullmere Online</h1>

<p align="center">
  A persistent strategy MMO for the Mac, on a still black lake under the moon.<br>
  <a href="https://github.com/ael-dev3/Nullmere/releases/tag/trailer"><b>Watch the trailer</b></a>
</p>

<p align="center">
  <a href="https://github.com/ael-dev3/Nullmere/releases/tag/trailer"><img src="docs/images/seat-at-night.jpg" width="820" alt="A House's seat at night: a walled keep with lit windows and pink-roofed towers, its town and fields about it"></a>
</p>

Nullmere Online is one world shared by everyone who plays it, kept in real
time on a SpacetimeDB server: a continent ringed about a great dead lake,
still as black glass under the moon, parted from the richer lake country by
a ridge with six passes. Each player founds a city on it beside those who
arrived with them, raises its buildings on timers, trains troops in four
kinds and five tiers, and sends armies under commanders to gather from the
land, clear the barrows of the Unquiet and find the cairns the old folk
left, or to fall on other players' cities and armies. Alliances help each
other build, rally against barrows, cities and the gates of the ridge,
share learning and stores, and race to raise their Moonspire first in each
season of twenty-eight days; the season's victor names the Lord of the Mere.

It is a native Mac app for Apple silicon: SwiftUI and AppKit, every frame
drawn with Metal, every model made for this game alone, its score written as
it plays on recorded orchestral instruments, nearly all its cues recorded
sounds as well, and its night, its towns and the roar of its battles sounded
in code. A player's commanders take counsel with them through Apple's
on-device model, grounded on what the realm holds.
Website: [nullmere.online](https://nullmere.online).

## The trailer

A minute and fifty-nine seconds of the game's own world at night, drawn by its
own renderers and scored by its own synthesiser, with nothing of the
interface over it: [the trailer](https://github.com/ael-dev3/Nullmere/releases/tag/trailer)
(1920 by 1080 at sixty frames a second, [MP4](https://github.com/ael-dev3/Nullmere/releases/download/trailer/nullmere-trailer.mp4)).

<p align="center">
  <img src="docs/images/battle.jpg" width="49%" alt="A battle at night: riders in a House's pink charge between lines of spears and bows">
  <img src="docs/images/eaten-moon.jpg" width="49%" alt="The moon being eaten, red at its edge, mirrored whole in the still black lake">
</p>

## Build and run

You need a Mac with Apple silicon on macOS 26 Tahoe or later, with Apple
Intelligence turned on and its model downloaded (System Settings), and
Xcode 26 or later to build. Commanders take counsel through Apple's
[Foundation Models](https://developer.apple.com/documentation/foundationmodels)
framework, so the game runs only where that model does.

```sh
git clone https://github.com/ael-dev3/Nullmere.git
cd Nullmere
scripts/serve-realm.sh nullmere   # SpacetimeDB on this Mac, with the realm published to it
make play                         # the launcher; its Play enters that realm
```

That builds the game and opens its launcher; press Play, choose the name
you'll go by, and found your city. To
build the app itself:

```sh
make app
open "build/Nullmere Online.app"
```

The public realm on SpacetimeDB's maincloud is not raised yet, so for now a
realm of your own is the way in.
[DEVELOPING.md](docs/DEVELOPING.md) covers
Xcode, the tests, releases and the previews;
[REALM.md](docs/REALM.md) raising a realm on a SpacetimeDB server.

## Where it stands

Nullmere Online is in active development, being rebuilt in the open. An
audit on 14 November measured it against Rise of Kingdoms and found it
turn-based where it should be persistent, its world too dark and plain, its
interface mostly text, and no live realm; [rework-plan.md](docs/rework-plan.md)
has the audit and the plan, with a status table saying what is done, what is
unverified and what has not been started.

The launcher's Play opens the rebuilt realm (`realm/`): one persistent world
in real time, every rule inside the SpacetimeDB module. Cities and their
buildings on timers, troops trained and raised a tier, armies that march,
gather and fight, in the field as well as at barrows and cities, the
Unquiet's barrows, cairns for scouts to find, kill points and rankings,
research, commanders with talents, skills, tomes and gear from the Forge,
alliances with chat, help, rallies, gifts, honour, stores, territory,
learning and carts of goods between allies, crates of goods kept safe from
plunder, the day's work and favour, contests, the Moonspire and the gates
of the ridge, envoys, prisoners, petitions and letters, and its chat kept at
peace by reports its owner reads. CI plays it through on a real SpacetimeDB
server whenever it changes, holds its rules to a budget at a thousand
players, and builds, tests and bundles the Mac app and opens it on that
realm through Play. The public realm on maincloud is not raised yet; until
it is, a realm of your own (above) is the way in. Going live takes steps
that need the maintainer's own accounts, each a checklist in
[GO-LIVE.md](docs/GO-LIVE.md).

The turn-based game the app used to open has been deleted, its rules, its
phone companion and its realm with it; the land the world is drawn on
stands apart from it (`Sources/NullmereLand`, [core-split.md](docs/core-split.md)),
and the trailer is drawn from the rebuilt realm's world. The phone is to be
rebuilt on the rebuilt realm.

## Also in this repository

[Nullmere Stillwater](extensions/chrome-adblocker/) is an ad blocker for
Chrome in Nullmere's look: the lake, the moon, and nothing moving on the
water. It blocks ads and trackers with EasyList and EasyPrivacy under
Manifest V3, hides the slots they leave, and says plainly what Manifest V3
keeps it from doing. Its README has the install steps.

## Documentation

| Document | What it covers |
| --- | --- |
| [Playing](docs/PLAYING.md) | The launcher, the realm and every rule of the game |
| [The realm](docs/REALM.md) | How the server works, and raising a realm |
| [Developing](docs/DEVELOPING.md) | Building, testing, releasing, the previews, the trailer and the code's layout |
| [Design](docs/DESIGN.md) | How the lake and the world look, and the direction |
| [Gaps](docs/GAPS.md) | Nullmere Online against Rise of Kingdoms, and what lies beyond it |
| [Going live](docs/GO-LIVE.md) | The maintainer's checklist for the public realm and release |
| [From Warpkeep](docs/warpkeep-carryover.md) | What Nullmere kept from its halted predecessor |
| [The audit](docs/audit/findings.md) | The consistency audit of October 2026 and what became of it |

## License

- Nullmere Online, its code, art, sound and documentation alike, is licensed
  under the [GNU Affero General Public License, version 3 only](LICENSE)
  (AGPL-3.0-only). Whoever runs a modified realm or client for others over a
  network must offer them its source.
- The score's instruments, and the horn, the clarinet, the bells, the harp,
  the drums, the anvil, the wood, the gong, the tambourine, the cabasa, the
  steel, the slapstick, the brick, the rubbed drum, the bowed cymbal and the
  plucked double bass many cues are sounded on, are notes and sounds of the
  [VS Chamber Orchestra: Community Edition](https://github.com/sgossner/VSCO-2-CE),
  recorded by Sam Gossner and Simon Dalzell and given to the public domain
  (CC0 1.0); as `Art/sound/make.py` makes them into the game they are under
  the AGPL with the rest of it.
- The names Nullmere Online and Nullmere identify the official project.
  Neither licence grants rights to them.
