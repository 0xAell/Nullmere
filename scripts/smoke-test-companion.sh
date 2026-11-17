#!/usr/bin/env bash
# Plays Nullmere Companion in the iOS Simulator against a realm served on
# this machine (scripts/serve-realm.sh): a player joins over the realm's
# own HTTP API and asks for a code, as their Mac would; the phone, in the
# Simulator, is launched with the code, which a debug build takes as typed,
# and comes in as them; the realm then finds the code used and the player
# here, and the phone's screen is photographed:
# build/companion-shots/companion-home.png.
#
#   NULLMERE_REALM=http://127.0.0.1:3000/nullmere-ui scripts/smoke-test-companion.sh
#
# The app is built first, by scripts/build-companion.sh.
set -Eeuo pipefail
trap 'echo "error: smoke-test-companion.sh stopped at line $LINENO: $BASH_COMMAND" >&2' ERR
cd "$(dirname "$0")/.."
REALM="${NULLMERE_REALM:-http://127.0.0.1:3000/nullmere-ui}"
APP="build/companion/Nullmere Companion.app"
BUNDLE_ID=online.nullmere.companion
SHOTS=build/companion-shots
mkdir -p "$SHOTS"
[ -d "$APP" ] || { echo "error: no $APP: run scripts/build-companion.sh first" >&2; exit 1; }

# The realm's HTTP API, as a client asks it: realm.py <realm> <command> [args].
realm() {
    python3 -I - "$REALM" "$@" <<'PY'
import json, sys, urllib.error, urllib.parse, urllib.request
parts = urllib.parse.urlsplit(sys.argv[1])
host, db = f"{parts.scheme}://{parts.netloc}", parts.path.strip("/")
command, rest = sys.argv[2], sys.argv[3:]

def post(path, body, token=None, content="application/json"):
    request = urllib.request.Request(host + path, data=body.encode(), method="POST")
    request.add_header("Content-Type", content)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()

def rows(token, query):
    status, body = post(f"/v1/database/{db}/sql", query, token, "text/plain")
    if status != 200:
        raise SystemExit(f"error: {query}: {body.strip()}")
    result = json.loads(body)[0]
    names = [element["name"]["some"] for element in result["schema"]["elements"]]
    return [dict(zip(names, row)) for row in result["rows"]]

if command == "player":
    # A player as their Mac makes them: an identity, a name, a code asked for.
    token = json.loads(post("/v1/identity", "")[1])["token"]
    for reducer, arguments in (("join", ["Ada of the Phone"]), ("offer_link", [])):
        status, body = post(f"/v1/database/{db}/call/{reducer}", json.dumps(arguments), token)
        if status != 200:
            raise SystemExit(f"error: {reducer}: {body.strip()}")
    print(token, rows(token, "SELECT * FROM my_link")[0]["letters"])
elif command == "linked":
    # Whether the phone took the code and the player is here: their code
    # used, and they online while the phone keeps its line to the realm.
    token = rest[0]
    me = rows(token, "SELECT * FROM me")[0]
    print("yes" if not rows(token, "SELECT * FROM my_link") and me["online"] else "no")
PY
}

read -r TOKEN CODE < <(realm player)
[ -n "${CODE:-}" ] || { echo "error: no player joined, or no code was asked for, at $REALM" >&2; exit 1; }
echo "A player, Ada of the Phone, joined $REALM and asked for a code: $CODE"

# An iPhone simulator, the newest iOS's first.
DEVICE="$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if ".iOS-" not in runtime:
        continue
    for device in devices[runtime]:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit
')"
[ -n "$DEVICE" ] || { echo "error: no iPhone simulator is available" >&2; exit 1; }
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl install "$DEVICE" "$APP"
SIMCTL_CHILD_NULLMERE_REALM="$REALM" SIMCTL_CHILD_NULLMERE_LINK_CODE="$CODE" xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
echo "Nullmere Companion launched on the simulator $DEVICE with the code."

linked=no
for _ in $(seq 1 45); do
    sleep 2
    linked="$(realm linked "$TOKEN")"
    [ "$linked" = yes ] && break
done
sleep 3
xcrun simctl io "$DEVICE" screenshot "$SHOTS/companion-home.png" >/dev/null
echo "The phone photographed: $SHOTS/companion-home.png"
if [ "$linked" != yes ]; then
    echo "error: the phone didn't come in as the player: their code unused, or they not here" >&2
    exit 1
fi
echo "The phone came in as Ada of the Phone: the code used, and she is here while it keeps its line."
