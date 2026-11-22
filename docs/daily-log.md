# Nullmere daily log

Short notes that land on main under ael's GitHub identity so the contribution graph reflects real work days. Claude's session commits still carry the game forward; this file is the daily stamp when needed.

## 2026-11-10 (Europe/Belgrade)

The 9th on main brought a new mechanic, the unquiet dead: a field keeps its dead after battle, corpse-lights hang over unburied fields, the fallen rise pale as Barrowkin at the dark of the moon, and companies bury them under barrows whose stone words come from the Mac's own model. Battle fronts now meet with companies pressing in pairs, walls answer with arrows, roads run between holds, and the phone's chart marks unburied fields and barrows (`578eab6` tip, run 895 green). Real on-device Apple model answers on eligible hardware and an iPhone device run remain unverified. Next push: on-device inference evidence, companion iOS sync and reconnection end to end, Rise of Kingdoms and Warpkeep parity gaps, UI declutter. Session stays Opus 5.5 Max. Standing bar unchanged: Rise of Kingdoms or better, live multiplayer, original 3D, minimal UI.

## 2026-11-09 (Europe/Belgrade)

The 8th on main was mostly the black lake at night: lanterns carried through the town's lanes, lanterns and fires lying on the water, holds glowing warm from afar, the strand's waves on the scene's clock, a lake shore sound, and a Dark/Moonlit/Bright night brightness choice fixing the too-dark default view (`60f590b` tip, run 815 green). The Mac now shows the phone's presence and can cancel an on-device model reading. Real on-device Apple model answers and an iPhone run remain unverified. Next push: on-device Foundation Models inference for NPC/commander talk, companion iOS sync and reconnection end to end, then Rise of Kingdoms and Warpkeep parity gaps. Session stays Opus 5.5 Max. Standing bar unchanged: Rise of Kingdoms or better, live multiplayer, original 3D, minimal UI.

## 2026-11-08 (Europe/Belgrade)

Late on the 7th into the 8th, the companion phone app kept gaining real realm management on main: the Ring arena, lantern scouting, realm edicts, prisoners, oaths, the Forge and gear, alliance works and stores, and raising standards from the phone's chart (`9e0f576` tip). CI's live smoke now runs the phone against the same realm as the Mac. Apple on-device model evidence still marked unverified on CI's ineligible runner. Session stays Opus 5.5 Max for polish. Standing bar unchanged: Rise of Kingdoms or better, live multiplayer, original 3D, minimal UI.

## 2026-11-07 (Europe/Belgrade)

Overnight into the 7th on main: keeper view cost scoped to what is theirs, heard view written as parts, road traffic apart from watch paces, frame-time GPU pacing, and a full-realm concurrent-order path (`f376515` tip). CI running on tip. Session stays Opus 5.5 Max for polish. Standing bar unchanged: Rise of Kingdoms or better, live multiplayer, original 3D, minimal UI.

## 2026-11-06 (Europe/Belgrade)

Wayhouse and Lyceum Blender models landed on main (every-work-in-Blender pass), with the round house's roof ring set on its cone. Overnight building wave from late the 5th still moving through CI. Session on Opus 5.5 Max for polish. Standing bar unchanged: Rise of Kingdoms or better, live multiplayer, original 3D, minimal UI.

## 2026-11-05 (Europe/Belgrade)

Blender-authored unit models landed through the day: spearman, archer, lantern-bearer, rider/horse, commanders, mangonel crew, founder and handcart. Two-bone skinning, glTF reader, view-distance land draw, and a SpacetimeDB WebSocket close fix also went to main. World city screenshot `docs/shots/world-city.png` is in the tree. Session on Opus 5.5 Max for polish. Standing bar unchanged: Rise of Kingdoms or better, live multiplayer, original 3D, minimal UI.
## 2026-11-11

- Chill week: the Claude session moved to Haiku 5.5 Low to save usage, with a once-a-day check and at least one commit on main per day.
- Landed Nov 10: commanders counsel the House's dealings (peace, pact, tribute, war), its holds and its Lanterns' scouting; FERRY in the order book; the phone ferries and disbands companies and musters at the highest open tier; parley with envoys through the on-device model; a fix so TRAIN at a named tier musters that tier; run 964's Mac test failures mended.
- Still open: on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

## 2026-11-12

- Chill week continues: Claude session on Haiku 5.5 Low, once-a-day check.
- Latest on main: parley with a prisoner and with a petitioner at the gate through the on-device model, on the Mac and the phone (tip 017c200, landed Nov 11). No new Claude pushes since.
- Still open: on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

## 2026-11-13

- Chill week continues: once-a-day check, no new Claude pushes to main since 017c200 (Nov 11).
- Still open: on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

## 2026-11-14

- Full rework started: the Claude session moves to Fable 5.2 xHigh to rebuild weak systems, art, UI and code toward Rise of Kingdoms level, per docs/rework-plan.md.
- No new Claude pushes to main since 017c200 (Nov 11); main CI green.
- Still open: on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

## 2026-11-15

- Rework landed on Nov 14: alliances and chat, first tasks, Academy research and its screen, a second builder, commanders, a richer daytime ground and water, map panning by pointer step, and city-under-attack warnings (tip 390c9ed).
- Main CI is red on the Mac "Build, test and bundle" job (runs 973, 974, 976); the realm, phone and accessibility jobs pass.
- Still open: on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

## 2026-11-16

- Late Nov 15 the top priority became a Nullmere-themed Chrome ad blocker in extensions/chrome-adblocker/. Landed on main: packing and its own CI job, every filter kind checked in Chromium, themed popup and options page, text-matching and restyling filters, YouTube handling, README and art, settings that survive restart and update, an independent code review's fixes, pop-up ad closing, and the packed extension kept in the repo (tip of that work 3dd1e35). The Ad blocker CI job is green on it.
- Also landed: 1ff0d03 "Realm: the day's work" (daily realm rules); its Realm rules run was still in progress at time of writing.
- Still open: the ad blocker is not yet called done; on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

## 2026-11-17

- Claude kept pushing realm work through Nov 16 (tip e79d2ab, ~11:49 PM): contest standings and laurels in the Mac realm panel and commander counsel, meadow swards carried from the land's corners, and Mac CI runs 1079 and 1080 recorded in the plan.
- CI: the Realm rules run on 454929b is green; a CI run on that commit failed, and the run on e79d2ab was still in progress at time of writing.
- Still open: the ad blocker is not yet called done; on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

- Update ~8 PM: Claude kept shipping through Nov 17 (tip 73905cd, ~8:04 PM): ad blocker element picker and own-filter syntax, realm panel/UI wording and frame-staging fixes, NullmereKit coverage floor 93.5, and a Realm rules check that fails unless a publish is live.
- CI: Realm rules green on 37ed62c; the CI run on that commit and the Realm rules run on 73905cd were still in progress at time of writing.


## 2026-11-18

- Late Nov 17 Claude kept to realm performance work (tip d1600a6, ~11:33 PM): the frame's still pieces staged once, worked-out poses kept for every frame, the Mac staging baselines lowered to what Mac run 1140 measured, and a panning frame timed in four passes. Mac run 1140 recorded all jobs green.
- CI: the run on 1587d77 is green; the run on e0dacdc failed before the baselines were re-timed.
- Still open: the ad blocker is not yet called done; on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.


## 2026-11-19

- Just after midnight Claude pushed bf5db75 (lanes and roads drawn whole, not in dashes), faa955c (StageTests count a seat's lanes as the test world has them) and f5f560a (plan: woods and meadow up to a city seen on Metal), tip ~1:03 AM.
- CI: the main CI runs on faa955c and f5f560a finished green; the Realm rules run on bf5db75 failed before the follow-up fix.
- Still open: the ad blocker is not yet called done; on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.


## 2026-11-21

- Development has been paused since Nov 19 at ael's call. Main tip is still cafaf2d (works stand on trodden earth: yards warmed, the sawpit's clearing no longer a pit of soot).
- CI: the CI and Realm rules runs on cafaf2d both finished green.
- Still open: the ad blocker is not yet called done; on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

## 2026-11-22

- Development remains paused since Nov 19 at ael's call. Main tip is 28694d2 (Daily log: Nov 21). Last game commit is still cafaf2d (Works stand on trodden earth: yards warmed, the sawpit no pit of soot); no new Claude pushes since Nov 19.
- CI: the CI and Realm rules runs on cafaf2d both finished green. No CI or Realm rules run on 28694d2.
- Still open: the ad blocker is not yet called done; on-device Apple model answers and the companion app on a real iPhone remain unverified on hardware.

- Update ~11 PM: Development remains paused since Nov 19 at ael's call. Main tip is still a8b1d77 (Carry Warpkeep gameplay and reliability patterns into Nullmere).
- CI: the CI and Realm rules runs on a8b1d77 both finished green.
