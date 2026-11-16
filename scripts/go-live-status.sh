#!/usr/bin/env bash
# Says where each step of going live stands (docs/GO-LIVE.md), and for
# each one not yet done, the one command that does it. Changes nothing.
#
#   scripts/go-live-status.sh                  # the realm proper
#   REALM_ADDRESS=http://127.0.0.1:3000/nullmere scripts/go-live-status.sh
#   scripts/go-live-status.sh --expect-realm   # fails unless the realm answers
#
# The release and its secrets are read with the GitHub CLI (gh) where it is
# signed in; without it, that step says it can't tell.
set -euo pipefail
cd "$(dirname "$0")/.."

ADDRESS="${REALM_ADDRESS:-https://maincloud.spacetimedb.com/nullmere}"
HOST="${ADDRESS%/*}"
DB="${ADDRESS##*/}"
EXPECT_REALM=0
[ "${1:-}" = --expect-realm ] && EXPECT_REALM=1

line() { printf '%-22s %s\n' "$1" "$2"; }
also() { printf '%-22s %s\n' "" "$1"; }
done_steps=0

echo "Nullmere Online, going live: where it stands"
echo

# 1. The realm: its own row and its players, read as any client may.
realm_json=""
players_json=""
token="$(curl -s -m 10 -X POST "$HOST/v1/identity" 2>/dev/null | sed -n 's/.*"token":"\([^"]*\)".*/\1/p' || true)"
sql() {
    curl -s -m 10 -X POST -H "Authorization: Bearer $token" -H "Content-Type: text/plain" --data "$1" \
        "$HOST/v1/database/$DB/sql" 2>/dev/null || true
}
if [ -n "$token" ]; then
    realm_json="$(sql "SELECT * FROM realm")"
    players_json="$(sql "SELECT * FROM player")"
fi
realm="$(REALM="$realm_json" PLAYERS="$players_json" python3 -c '
import json, os
def rows(text):
    result = json.loads(text)[0]
    names = [element["name"]["some"] for element in result["schema"]["elements"]]
    return [dict(zip(names, row)) for row in result["rows"]]
try:
    realm = rows(os.environ["REALM"])[0]
    players = len(rows(os.environ["PLAYERS"]))
    pace = "the realm proper" if realm["pace"] == 1 else "a trial realm at {0} times the pace".format(realm["pace"])
    print("{0}, {1} hexes from the lake to its edge|{2}".format(pace, realm["radius"], players))
except Exception:
    pass
' 2>/dev/null || true)"
players=""
publish="the Publish the realm workflow, from the repository's Actions tab (docs/GO-LIVE.md, step 1)"
if [ -n "$realm" ]; then
    players="${realm##*|}"
    line "1. The realm" "UP at $ADDRESS: ${realm%|*}"
    done_steps=$((done_steps + 1))
elif [ -n "$token" ]; then
    line "1. The realm" "NOT PUBLISHED: SpacetimeDB answers at $HOST, but no realm \"$DB\" stands there"
    also "$publish"
else
    line "1. The realm" "OUT OF REACH: nothing answers at $HOST"
    also "$publish"
fi

# 2. The release: signed and notarized, or not yet.
secrets="MACOS_CERTIFICATE MACOS_CERTIFICATE_PASSWORD APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    # Listing secrets needs admin rights to the repository; without them
    # the secrets can't be told from missing ones.
    readable=1
    have="$(gh secret list 2>/dev/null | awk '{print $1}')" || readable=0
    missing=""
    if [ "$readable" = 1 ]; then
        for secret in $secrets; do
            echo "$have" | grep -qx "$secret" || missing="$missing $secret"
        done
    fi
    release="$(gh release view --json tagName,body --jq '.tagName + "|" + (.body | test("ad-hoc"; "i") | tostring)' 2>/dev/null || true)"
    if [ -n "$release" ] && [ "${release##*|}" = false ]; then
        line "2. The release" "NOTARIZED: ${release%|*}"
        done_steps=$((done_steps + 1))
    elif [ -n "$release" ]; then
        line "2. The release" "AD-HOC SIGNED: ${release%|*} is not notarized"
    else
        line "2. The release" "NONE YET"
    fi
    if [ "$readable" = 0 ]; then
        also "can't read the repository's secrets here (they need admin rights to list)"
    elif [ -n "$missing" ]; then
        also "secrets missing:$missing"
        also "scripts/set-release-secrets.sh DeveloperID.p12 AuthKey_XXXXXXXXXX.p8 <issuer id>"
    elif [ "${release##*|}" != false ]; then
        also "the secrets are all set: git tag v1.0.0 && git push origin v1.0.0"
    fi
else
    line "2. The release" "CAN'T TELL: the GitHub CLI isn't signed in here (gh auth login)"
    also "scripts/set-release-secrets.sh DeveloperID.p12 AuthKey_XXXXXXXXXX.p8 <issuer id>, then tag a version"
fi

# 3. On a real Mac: the figures measured on Apple silicon, on record
# (scripts/check-on-mac.sh). The rebuilt realm's counsel through Apple's
# on-device model has no check on a real Mac yet (docs/GAPS.md).
measured="$(ls perf/mac/*.json 2>/dev/null | tr '\n' ' ' || true)"
if [ -n "$measured" ]; then
    line "3. The figures" "MEASURED: $measured"
    done_steps=$((done_steps + 1))
else
    line "3. The figures" "NOT YET MEASURED"
    also "scripts/check-on-mac.sh  (on a Mac with Apple silicon)"
fi
line "3. Counsel" "NO CHECK YET on a real Mac: the rebuilt realm's counsel through Apple's on-device model (docs/GAPS.md)"

# 4. VoiceOver, listened to: no machine can tell how it sounds.
line "4. VoiceOver" "BY EAR: docs/GO-LIVE.md, step 4 (CI audits every screen and walks the map: scripts/ui-test.sh)"

# 5. The first players.
if [ -n "$players" ] && [ "$players" -gt 0 ]; then
    line "5. Players" "$players player$([ "$players" = 1 ] || echo s) joined"
    done_steps=$((done_steps + 1))
else
    line "5. Players" "NONE YET: they come once the realm is up and a release is out"
fi

echo
echo "$done_steps of the 4 steps a machine can check are done; step 4 is by ear."
if [ "$EXPECT_REALM" = 1 ] && [ -z "$realm" ]; then
    echo "error: the realm at $ADDRESS doesn't answer" >&2
    exit 1
fi
