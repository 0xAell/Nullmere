# Splitting NullmereCore (plan 3.4, step B, last part)

NullmereCore holds the turn-based game's rules (37,089 lines in 153 files
on 16 November) and, beside them, the land the kept code still draws:
hexes, the map, terrain and the kinds of things that stand on it. The old
rules go; the land moves to a module of its own. This is the map of that
split, read from the source (no compiler here), for whoever does it.

## What the kept code needs

Kept: NullmereWorld, NullmereModels, NullmereLiveStage, NullmereLive,
NullmereSound, NullmereTrailer, LauncherCore, LauncherKit,
NullmereLauncher and NullmereKit (the window, the rebuilt realm's
screens, the Metal world, the audio engine).

**Whole (4 files, 359 lines):** Hex.swift (`Hex`, `HexLayout`),
PlainCases.swift, Varint.swift (WorldMap's encoding), StoreMarks.swift
(Style.swift's marks of the stores; it names `Resource`).

**In part (24 files, about 1,100 lines of code needed of 6,300):**

| File | Needed | Its old-rule ties, to cut |
| --- | --- | --- |
| WorldMap.swift | `Tile` (terrain, feature, relief); `WorldMap`'s layout, inits, subscripts, `set(_:_:)` and `set(index:)`, `contains`, `index(of:)`, `hex(at:)`, `hexes`, `neighbors(of:)`, `==`, Codable helpers; `Terrain.code`, `Feature.code` | `Tile.yield` (Stock), `unexplored` (Fog), `known(by:from:)` (Explored, RealmState), `set(index:)` touches `RealmState.mapPage`, the caches (LieOfTheLand.swift, which itself is clean), `steps` (`Terrain.moveCost`) |
| Terrain.swift | `Terrain`, `Feature` | `yield` (Stock) |
| Hold.swift | `Hold` with `Project` (and its `progress`), `Training`, `level(_:)`, `maximumWard` | `wounded` (Infirmary's `Wounded`, which nothing kept reads), `House`, `Bits`, the view's extensions |
| Buildings.swift | `BuildingKind`, `maxLevel`, `buildWatches(toLevel:)` | `cost` (Stock), `effect` (GearQuality, GameState) |
| Units.swift | `UnitKind` | `cost`, the `Unit` struct |
| Heritages, Wilds, Resources, Shrines, Omens, Commanders (`Skill`, `Archetype`), Finds (`Find.Kind`), Crests (`Crest`, `Tincture`, `Charge`), AllianceMarks (`AllianceMark.Kind`), Petitions (`Petition.Plea`) | the kind enums | their GameState extensions, Stock, Bonus, Unit |
| Burials.swift | `FieldOfDead`; `GameState.unquietAt` 6000, `unquietPerLevel` 4000 (CorpseLights) | the rest |
| Moonford.swift, Calm.swift, Lyceum.swift, Expeditions.swift | `lunarMonth` 30, `Calm.deepest` 10, `Lyceum.questions` 5, `ExpeditionStage.count` 12 | the rest: move the constants |
| WorldGenerator.swift | the `Lake` enum (NullmereSound's score, Ambience, RealmSound) | the generator: only the trailer reaches it, through GameState |
| Fields.swift, Infirmary.swift, LieOfTheLand.swift | `Fighter` (only `handToHand`), `Wounded` (only `Hold.wounded`), WorldMap's caches | |

**Old only (125 files, 30,430 lines):** everything else: GameState,
Realm, RealmParts, Rules, Commands, RivalMind, Pathfinding, Fog,
Explored, Watch, Progress, SHA256, the envoys, stewards, war, diplomacy
and economy. Random.swift is used by no kept source, only HexTests.

## What must change first

- **The trailer plays the old game.** `NullmereTrailer/TrailerWorld.swift`
  makes a `GameState` and plays 72 watches; Actors.swift and Trailer.swift
  read its houses, holds, seats, sites, holy sites and lairs. The trailer
  needs a world of its own (a generated map and holds set out by hand, or
  the rebuilt realm's sample) before NullmereCore can go; while it plays
  the old game, nearly all of NullmereCore stays.
- **Kept modules' APIs only tests call:** `TileTexture.bytes(for: GameState)`,
  `Fronts.handToHand(in: GameState)`, `CorpseLights.kindled(FieldOfDead)`,
  `Weather.of(OmenKind)`, `FuryLook.of(Skill)`, `markHue`/`markLights`,
  `crestBoards`. Delete them, or move them to tests, and Fields, Burials
  (but its two constants), Omens, Commanders, AllianceMarks, Crests and
  Petitions become old only.
- **Test fixtures built from GameState:** 21 of NullmereWorldTests' 28
  files, 5 of NullmereModelsTests', and NullmereKitTests' FrameHarness,
  WorldMetalView, WorldPerformance, WorldRender and NullmereKitTests.swift.
  They need a world built without the rules: a WorldMap from the land's
  generator (moved with the land) or from the rebuilt realm's sample
  (`LiveSample`, `LiveWindow`), and holds and companies set out by the test.
- **Voices and counsel of the old game:** Voices.swift, VoiceCheck.swift
  and NullmereCounsel use GameState throughout; only NullmereLauncherApp's
  debug reports (`NULLMERE_VOICES_REPORT`, `NULLMERE_COUNSEL_REPORT` via
  `CounselCheck`) reach them. The rebuilt realm's counsel
  (`LiveCounselSession`) and the launcher's model gate call Foundation
  Models directly. They go with the old rules, and scripts/check-voices.sh
  with them; check-counsel.sh moves to the rebuilt realm's counsel.

## The trailer's world, without the old game

TrailerWorld plays twelve stewards for 72 watches and then dresses three
holds by hand (a seat raised whole, a Moonspire at its third stage, a
hold walled in stone). Two ways off the old rules:

- **The rebuilt realm's own world (preferred).** The realm's rules run
  here (`cargo test` in realm/): a small Rust test or binary opens a realm,
  joins a dozen players beside each other, plays their cities up for a
  while at the realm's pace, and writes the rows a client would read
  (land chunks, cities, buildings, sites, barrows) to a JSON file kept
  with the trailer (`realm/tests/trailer_rows.rs` does so: twelve players
  joined together, their Keeps from 25 down to 3, the land within 26
  hexes of the one in their midst; `NULLMERE_TRAILER_ROWS=<file> cargo test
  --test trailer_rows` writes them, about 12 KB). TrailerWorld reads it through `LiveWorld` and
  `LiveWindow`, which already turn those rows into the renderer's map and
  holds, and dresses its three holds as now. The trailer then shows the
  game as it is, not the one deleted.
  The Swift side, mapped: `LiveWorld(snapshot:)` takes the JSON's rows
  (`JSONValue` decodes them) with no session; `LiveWindow(world:centre:
  radius: 26)` gives `map` (`WorldMap`), `holds(in:colours:at:)`
  (`HoldSight`s, each city's levels from its Keep), `sites`, `barrows`,
  `cairns` and `local(_:)`; the relief as `LiveSession.land()` makes it.
  The trailer reads the old game through `world.state` in about 25 places
  (Actors.swift: `houses`, `heritage(of:)` 5 each, `map`, `holds`;
  Trailer.swift: `houses`, `heritage`, `sitesInLand`, `lairsStanding`,
  `holySites`; the tests: `map`, `holds`, `player`). `TrailerWorld` keeps
  `map`, `holds`, `colour(of:)` and `heritage(of:)` (nil: the rebuilt realm
  has no heritages yet) and the sites' and lairs' places itself, and
  `state` goes; holy sites have no rows in the rebuilt realm, so the shot
  that shows them shows the Moonspire's seat instead. The Trailer workflow
  renders stills to compare. Begun on the branch `trailer-world` (not
  pushed to main; a copy as `claude/trailer-world` on GitHub, whose push
  ran the workflows on unfinished work: a `claude/` branch runs them all,
  so push there only what is done): the world read from the rows, the actors and frames
  moved off `world.state`. What it still needs: the trailer's shots stand
  about the lake at the map's middle (`Relief.centre(of: Hex(0, 0))`), so
  the rows must set the twelve cities about the lake country's shore
  (City and Place rows put down by the test, not where joining founds
  them) and the window be centred on the lake, as the old world was; and
  the trailer's tests and TrailerRenderTests moved off `world.state`
  (`world.map`, `world.holds`, `world.tiles`).
- A snapshot of the world the old game made, written once by a Mac test
  and kept as a file: no Swift runs here to write it, so it would need a
  CI step to bring the file back, and it keeps the old game's look.

## Order

1. The trailer's world without GameState (its pictures compared before
   and after in the Trailer workflow's stills). Done on 16 November
   (`6c602b2`): the realm test sets the twelve cities about the lake's
   shore, nine to eleven hexes from its middle, and TrailerWorld reads
   them in a window of 26 about the lake. Built and tested on Linux
   (Realm rules run 80) and on the Mac (CI run 1043, wholly green); rendered whole by the Trailer workflow's run 16
   (14 shots, 7,140 frames, 119 s) and published as the "trailer"
   pre-release's film and stills sheet, as that workflow does on every
   push to the trailer. **Not yet looked at by eye**: the stills sheet
   (`releases/download/trailer/nullmere-trailer-stills.jpg`) is the thing
   to look at, shot by shot, against the last one drawn from the old
   world.
2. A land module (`NullmereLand`): the whole and in-part files above,
   trimmed; kept modules import it instead of NullmereCore. Begun with
   the three whole files that are the land's own (Hex, PlainCases,
   Varint, their members the rules used made public), NullmereCore
   depending on it and passing it on (`@_exported`), so nothing else
   changes yet; the in-part files follow a few at a time. Green on
   Linux (Realm rules run 81). Next, WorldMap, Terrain and LieOfTheLand:
   their old-rule members stay behind as NullmereCore extensions
   (`Tile.yield`, `Terrain.yield`, `Feature.yield` on Stock; `unexplored`
   on GameState.unknown; `known(by:from:)` on Explored), `RealmState.mapPage`
   becomes a constant of the land's (`WorldMap.page`, the rules' taken
   from it), and the twenty-odd members the rules reach that are internal
   now (`steps`, `neighbours`, `lie`, `claims`, `nearest`, `deep`,
   `reliefOf`, `groundOf`, `apart`, `set(index:)`, `forEachIndex`, the
   encoders `ground(of:)`, `relief(of:)`, `tiles(...)`) take `package`
   access, which the package's tools (5.9) give: seen by the rules, not
   beyond the package. Done (`531f8c3`, with `a7b10ae`: a claimant's and
   the caches' initialisers, which the rules call, take package access
   too); built on Linux, the rules' and the kept modules' tests with it
   (Realm rules run 84). Then the city and what it is made of: Resource
   and Stock, BuildingKind, UnitKind (the kinds alone; the Unit in the
   field stays with the rules), Wounded and Hold. What of them is the
   rules' stays as NullmereCore extensions in LandRules.swift: a work's
   effect at its next level (it reads the House's studies and gear), a
   company's tiers (Unit's tier tables), a hold's training watches, and
   a stock as a line says it; House, Temperament and the told-alike
   views stay in House.swift.
3. Test fixtures rebuilt on it, a few files at a time, each step green.
4. Voices, VoiceCheck, NullmereCounsel and the debug reports deleted.
5. NullmereCore and NullmereCoreTests deleted; coverage floors and
   perf/baseline.json (realm.watch.*, calibration's home) follow:
   `CalibrationTests` lives in NullmereCoreTests and must move first.
