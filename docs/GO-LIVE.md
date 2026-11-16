# Going live

Everything Nullmere Online needs is built and rehearsed in CI on every push
that changes the code, the scripts or the news: the realm published to a
SpacetimeDB server and played through, by hand and by its own Swift client, a release signed and notarized with
a throwaway identity, every screen put to Xcode's accessibility audit. What
is left needs what only the maintainer has: a SpacetimeDB sign-in, an Apple
Developer account, a Mac with Apple Intelligence, and ears.

Each step is a checklist. Paste each block into Terminal as it stands, from
the repository's folder (the one block to fill in first is marked **Fill
in**); the line after **Worked when** is what it prints when it did. Steps 1 to 4 stand alone and can be done in any order; step 5
follows 1 and 2. Within a step, the checks come first and change nothing;
the commands marked **Changes things** do: publishing the realm, setting the
release's secrets, pushing a version tag, committing the figures.

Where every step stands, at any time, and the command for each one not yet
done:

```sh
scripts/go-live-status.sh
```

## 1. Publish the realm on maincloud

Needs a GitHub account (SpacetimeDB signs in with it). The realm is one
SpacetimeDB module (`realm/`), its rules and its timers inside it: there is
no steward to keep running beside it, and publishing it is the whole of
raising it. On its first publish to a database it opens itself; published
again, it keeps its rows.

- [ ] Install the SpacetimeDB CLI, once (it says if already there), and put
  it on this Terminal's path (new Terminals find it by themselves):

  ```sh
  command -v spacetime || curl -sSf https://install.spacetimedb.com | sh
  export PATH="$HOME/.local/bin:$PATH"
  spacetime --version
  ```

  **Worked when** it prints its version.

- [ ] Sign in to SpacetimeDB (it opens a GitHub sign-in in the browser), and
  put the token it keeps in the repository's `SPACETIME_TOKEN` secret:

  ```sh
  spacetime login
  spacetime login show --token | awk '{print $NF}' | tail -n 1 | gh secret set SPACETIME_TOKEN
  ```

  **Worked when** `gh secret list` shows `SPACETIME_TOKEN`.

- [ ] **Changes things.** Publish it: run **Publish the realm** from the
  repository's Actions tab with the database named `nullmere`, or here:

  ```sh
  gh workflow run realm.yml -f database=nullmere
  ```

  **Worked when** the run's last line reads `Published https://maincloud.spacetimedb.com/nullmere`.

- [ ] Ask it how it stands, as any client may:

  ```sh
  scripts/go-live-status.sh --expect-realm
  ```

  **Worked when** its line for the realm reads `1. The realm … UP at https://maincloud.spacetimedb.com/nullmere: the realm proper, …`.

Release builds already point at `https://maincloud.spacetimedb.com/nullmere`;
nothing in the app changes. If the name is taken, publish under another and
build the app for it with
`REALM_ADDRESS=https://maincloud.spacetimedb.com/<name> scripts/build-app.sh`.

Keeping the peace: a player reports a line of chat from the Mac's chat,
and the report waits for you with the line and the three said before and
after it. As the identity that published the realm (the
`SPACETIME_TOKEN`'s, signed in with `spacetime login`):

```sh
spacetime sql --server maincloud nullmere "SELECT * FROM complaint"   # the reports waiting
spacetime call --server maincloud nullmere take_away 42 false         # line 42 of the realm's chat (true: an alliance's)
spacetime call --server maincloud nullmere bar_player 7 24            # player 7 says nothing for 24 hours (0 lifts it)
spacetime call --server maincloud nullmere dismiss_report 3           # report 3 let go
spacetime call --server maincloud nullmere forget_player 7            # player 7 forgotten, on their asking
```

A line taken away stands where it was, its words gone, and its reports
go with it. A player forgotten keeps their city under the name
`Forgotten #7`, their name leaves the roll, the chat, their letters and
what alliances hold of them, and their identity is let go, so they join
anew if they come back; words others wrote of them stay.

## 2. Sign and notarize the release

Needs an Apple Developer account, and the GitHub CLI signed in to this
repository.

- [ ] From Apple, once:
  - the **Developer ID Application** certificate with its private key:
    Keychain Access > My Certificates, the certificate, Export… as
    `DeveloperID.p12`, with a password of your choosing;
  - an **App Store Connect API key**: App Store Connect > Users and Access >
    Integrations > App Store Connect API, Generate API Key (role Developer),
    then Download API Key, `AuthKey_XXXXXXXXXX.p8` (Apple gives it once),
    and the **Issuer ID** shown above the keys.

- [ ] Sign the GitHub CLI in:

  ```sh
  command -v gh || brew install gh
  gh auth login
  ```

- [ ] **Fill in**, then paste: where the two files are, the Issuer ID, and
  the version to release, for the blocks below in this same Terminal:

  ```sh
  P12=~/Downloads/DeveloperID.p12
  KEY=~/Downloads/AuthKey_XXXXXXXXXX.p8
  ISSUER=00000000-0000-0000-0000-000000000000
  VERSION=1.0.0
  ```

  The key's file keeps the name Apple gave it: its id is read from it. The
  version is three numbers, as the app's is.

- [ ] Check the three, setting nothing (it asks for the password the `.p12`
  was exported with):

  ```sh
  DRY_RUN=1 scripts/set-release-secrets.sh "$P12" "$KEY" "$ISSUER"
  ```

  **Worked when** it ends: `Checked. Would set MACOS_CERTIFICATE, MACOS_CERTIFICATE_PASSWORD, APPLE_API_KEY, APPLE_API_KEY_ID and APPLE_API_ISSUER.`

- [ ] **Changes things.** Set the five secrets the release signs and notarizes with:

  ```sh
  scripts/set-release-secrets.sh "$P12" "$KEY" "$ISSUER"
  ```

  **Worked when** it ends: `The five secrets are set. A signed, notarized release is now a tag away:`

- [ ] Check that CI passed on the commit to be released (the release
  workflow checks again, and releases nothing it hasn't):

  ```sh
  gh run list --workflow ci.yml --commit "$(git rev-parse HEAD)" --status success --limit 1
  ```

  **Worked when** it lists a run, its line beginning `completed	success`.
  (None listed: CI hasn't passed on this commit, or hasn't run on it; run
  it with `gh workflow run ci.yml --ref "$(git branch --show-current)"`.)

- [ ] **Changes things.** Tag the version, and follow the Release workflow it starts to its end:

  ```sh
  git tag "v$VERSION" && git push origin "v$VERSION"
  sleep 15 && gh run watch --exit-status "$(gh run list --workflow release.yml --branch "v$VERSION" --limit 1 --json databaseId --jq '.[0].databaseId')"
  ```

  The workflow releases nothing CI hasn't passed whole on the tagged
  commit, and runs its tests again; signs the app with the hardened
  runtime and a secure timestamp, signs, notarizes and staples the disk
  image, checks it as a keeper receives it (`scripts/verify-release.sh`),
  and attaches it with its SHA-256 to a GitHub release. **Worked when** the
  watch ends without an error (`--exit-status` makes a failed run fail it)
  and the release's notes don't say "ad-hoc signed".

- [ ] On any Mac, check the image as downloaded:

  ```sh
  gh release download "v$VERSION" --pattern 'Nullmere-Online-*'
  shasum -a 256 -c "Nullmere-Online-$VERSION.dmg.sha256"
  spctl --assess --type open --context context:primary-signature --verbose "Nullmere-Online-$VERSION.dmg"
  ```

  **Worked when** they print `Nullmere-Online-1.0.0.dmg: OK` and
  `Nullmere-Online-1.0.0.dmg: accepted` with `source=Notarized Developer ID`
  (for version 1.0.0).

## 3. Hear the voices and counsel, and measure, on a real Mac

Needs a Mac with Apple silicon, macOS 26, Xcode 26, and Apple Intelligence
turned on (System Settings > Apple Intelligence & Siri) and its model
downloaded. CI's runners are virtual Macs. CI asks their model for the
voices and for a commander's counsel through the debug app too (the voices
and counsel steps of its build job), and they tell it they aren't
eligible: the debug app, a release build made for the checks
(`CHECKS=1 scripts/build-app.sh`, asked by the Model check workflow), and
the app as it ships, whose launcher shows its requirement screen there.
And their figures are a virtual Mac's, not Apple silicon's own. A keeper's
Mac is the one that counts.

- [ ] One command: Apple's on-device model speaks for every kind of envoy and
  chronicle entry, each line held to the voices' rules (spoken at all,
  short, grave, no numbers but the facts', no talk of games or players);
  then a commander takes counsel through it, as on a keeper's Mac: three
  questions about the realm as their House sees it, answered by looking
  about with the counsel's tools, an order put forward that the realm would
  take, what was said remembered, and an answer stopped as it begins, each
  held to counsel's rules; then the frame, GPU and turn figures CI holds to
  `perf/baseline.json` are taken here and set beside CI's. When all pass,
  all are committed to `perf/mac/`.

  ```sh
  scripts/check-on-mac.sh
  ```

  **Worked when** its summary reads

  ```
    The voices (Apple Intelligence) passed
    Counsel (Apple Intelligence) passed
    The figures (Apple silicon)  passed
  ```

  and it says `Committed. Put it on record: git push`. Counsel reading
  `unverified (the model isn't ready)` means this Mac's model wasn't ready
  to be asked: turn Apple Intelligence on, let its model download, and run
  it again. Each part can be run alone: `scripts/check-voices.sh`,
  `scripts/check-counsel.sh`, `scripts/measure-mac.sh`.

- [ ] **Changes things.** Put them on record:

  ```sh
  git push
  ```

## 4. Listen to it with VoiceOver

CI walks every screen through the accessibility tree VoiceOver reads and
puts each to Xcode's accessibility audit (`scripts/ui-test.sh`, which runs
here too). What no machine can judge is how it sounds. On the Mac from step
3, with VoiceOver on (⌘F5), open the app and check by ear:

- [ ] The launcher: the title is read as "Nullmere Online", then Play,
      News, Settings, Repository and Quit, each with its hint.
- [ ] Settings: each row is read as a menu with its value, and VO-Space
      opens its choices.
- [ ] The front door: the realm's state, the name field and its rule, and
      "Enter the world"; a realm out of reach is said aloud.
- [ ] The world: each watch's turn is said whole; on the map, VO-→ walks
      the keeper's seat, holds and companies, each ringed where it lies;
      VO-U opens the rotor (your companies, enemies in sight, holds);
      a company's actions (VO-⌘-Space) offer its marches and strikes,
      and choosing one is said done.

## 5. The first keepers

With the realm up (step 1) and a release out (step 2), a keeper downloads
the disk image from the release, opens Nullmere Online, presses Play, and
enters under a name of their choosing: no account, no settings, the realm
is the realm. The first twelve take the twelve seats; others wait at the
door for one to open.
