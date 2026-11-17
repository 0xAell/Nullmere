#!/usr/bin/env bash
# The realm (realm/), checked end to end: its rules' unit tests, its build
# to WebAssembly, and a play-through of the published module on a real
# SpacetimeDB server through the HTTP API a client uses, each player under
# an identity of their own.
#
#   realm/check.sh                    # with `spacetime` on the PATH: starts a server if none answers
#   SPACETIME="docker exec stdb spacetime" REALM_WASM=/wasm/realm.wasm REALM_SERVER=local \
#       REALM_HOST=http://127.0.0.1:3900 realm/check.sh
#                                     # with the server and its CLI in a container
#
# REALM_HOST is where the server answers (http://127.0.0.1:3000),
# REALM_SERVER what its CLI calls it (REALM_HOST unless the CLI runs
# elsewhere), REALM_DB the database published, afresh each time
# (nullmere-check).
set -euo pipefail

cd "$(dirname "$0")/.."
HOST="${REALM_HOST:-http://127.0.0.1:3000}"
SERVER="${REALM_SERVER:-$HOST}"
DB="${REALM_DB:-nullmere-check}"
SPACETIME="${SPACETIME:-spacetime}"
WASM="${REALM_WASM:-$PWD/realm/target/wasm32-unknown-unknown/release/realm.wasm}"

echo "== The rules' tests"
(cd realm && cargo test --quiet)

echo "== The rules at a thousand players, in release"
(cd realm && cargo test --quiet --release --test scale -- --ignored --nocapture)

echo "== The module, built"
(cd realm && cargo build --quiet --release --target wasm32-unknown-unknown)
ls -l realm/target/wasm32-unknown-unknown/release/realm.wasm

if ! curl -s -o /dev/null -X POST "$HOST/v1/identity"; then
    echo "== Starting SpacetimeDB"
    mkdir -p build
    # shellcheck disable=SC2086
    (nohup $SPACETIME start > build/realm-check-server.log 2>&1 &)
    for _ in $(seq 1 60); do
        curl -s -o /dev/null -X POST "$HOST/v1/identity" && break
        sleep 1
    done
    curl -s -o /dev/null -X POST "$HOST/v1/identity" || { echo "error: SpacetimeDB didn't start; see build/realm-check-server.log" >&2; exit 1; }
fi

echo "== Publishing $DB"
# shellcheck disable=SC2086
$SPACETIME publish --server "$SERVER" --bin-path "$WASM" --yes --delete-data "$DB" | tail -2

echo "== Playing it through"
python3 -I - "$HOST" "$DB" "$SPACETIME" "$SERVER" <<'PY'
import json, sys, urllib.request, urllib.error

host, db, spacetime, server = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
failures = []

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

def someone():
    status, body = post("/v1/identity", "")
    assert status == 200, body
    return json.loads(body)["token"]

def call(token, reducer, *arguments):
    """A reducer called as a client calls it: None if it was done, or the realm's refusal."""
    status, body = post(f"/v1/database/{db}/call/{reducer}", json.dumps(list(arguments)), token)
    return None if status == 200 else body.strip()

def rows(token, query):
    status, body = post(f"/v1/database/{db}/sql", query, token, "text/plain")
    if status != 200:
        return body.strip()
    result = json.loads(body)[0]
    names = [element["name"]["some"] for element in result["schema"]["elements"]]
    return [dict(zip(names, row)) for row in result["rows"]]

def check(what, got, wanted):
    if got == wanted:
        print("  ok  ", what)
    else:
        print("  FAIL", what, "\n        got:   ", str(got)[:300], "\n        wanted:", str(wanted)[:300])
        failures.append(what)

ada, bryn, nobody = someone(), someone(), someone()

realm = rows(ada, "SELECT * FROM realm")
check("the realm opened as it was published", [(r["id"], r["pace"]) for r in realm], [(0, 1)])

check("a player joins under a name", call(ada, "join", "  Ada   of the Lake "), None)
check("and is told why not, in plain words, a second time", call(ada, "join", "Ada again"), "You have already joined the realm.")
check("a name taken is refused, however it is capitalised", call(bryn, "join", "ADA OF THE LAKE"), "Another player has that name.")
check("a name too short is refused", call(bryn, "join", "x"), "A name needs at least 3 letters.")
check("another joins", call(bryn, "join", "Bryn"), None)

players = rows(nobody, "SELECT id, name, online FROM player")
check("everyone may read who plays", sorted((p["id"], p["name"]) for p in players), [(1, "Ada of the Lake"), (2, "Bryn")])
check("neither is here: each asked and went", [p["online"] for p in players], [False, False])
check("how many connections an identity has open is the realm's alone to know", isinstance(rows(ada, "SELECT * FROM presence"), str), True)
check("each player reads themself", [p["name"] for p in rows(ada, "SELECT * FROM me")], ["Ada of the Lake"])
check("and no one else", [p["name"] for p in rows(bryn, "SELECT * FROM me")], ["Bryn"])
check("someone who has not joined reads no one", rows(nobody, "SELECT * FROM me"), [])
private = rows(ada, "SELECT * FROM pace")
check("what is a player's alone is not a client's to read", isinstance(private, str) and "pace" in private, True)
private = rows(ada, "SELECT * FROM account")
check("nor whose identity is whose", isinstance(private, str) and "account" in private, True)
fired = call(ada, "fire", {"scheduled_id": 1, "scheduled_at": {"Time": {"__timestamp_micros_since_unix_epoch__": 0}}, "kind": 1, "subject": 1})
check("only the realm keeps its timers", fired is not None, True)

# The world: its land and its catalogue, there for every client to read.
radius = realm[0]["radius"]
land = rows(nobody, "SELECT * FROM land")
check("the land is kept in chunks of 256 hexes", (len(land) > 100, all(len(chunk["ground"]) in (256, 512) for chunk in land)), (True, True))
check("the catalogue is written out, 19 buildings by 25 levels", len(rows(nobody, "SELECT id FROM blueprint")), 475)

# A city: founded on joining, its owner's to read whole, everyone's to see.
city = rows(ada, "SELECT * FROM my_city")
check("joining founds a city", [(c["name"], c["keep"], c["builders"]) for c in city], [("Ada of the Lake", 1, 1)])
check("everyone sees where cities stand", len(rows(nobody, "SELECT id FROM city")), 2)
check("and what stands on which hex", sorted(p["kind"] for p in rows(nobody, "SELECT * FROM place") if p["kind"] == 1), [1, 1])
buildings = rows(ada, "SELECT * FROM my_buildings")
check("it has a Keep, a Farm and a Sawmill", sorted((b["kind"], b["level"]) for b in buildings), [(1, 1), (2, 1), (3, 1)])
check("another player's buildings are not theirs to read", sorted(b["city"] for b in rows(bryn, "SELECT * FROM my_buildings")) == [c["id"] for c in rows(bryn, "SELECT * FROM my_city")] * 3, True)
for table in ("building", "job", "stock"):
    private = rows(ada, f"SELECT * FROM {table}")
    check(f"the {table} table itself is closed to clients", isinstance(private, str), True)
stock = rows(ada, "SELECT * FROM my_stock")[0]
check("it starts with goods and brings more in each hour", (stock["grain"], stock["timber"], stock["stone"], stock["grain_hourly"], stock["holds"]), (6000, 8000, 6000, 1300, 30000))

# Raising the Keep: paid at once, done by the database's own scheduler.
keep = next(b for b in buildings if b["kind"] == 1)
farm = next(b for b in buildings if b["kind"] == 2)
check("nothing rises above the Keep", call(ada, "upgrade", farm["id"]), "Raise your Keep to level 2 first.")
check("another player can't raise it", call(bryn, "upgrade", keep["id"]), "That is not yours.")
check("the Keep begins to rise", call(ada, "upgrade", keep["id"]), None)
jobs = rows(ada, "SELECT * FROM my_jobs")
check("a job is under way, eight seconds long", [(j["kind"], j["subject"], j["level"], j["ends"] - j["started"]) for j in jobs], [(1, keep["id"], 2, 8)])
check("its cost is paid as it begins", rows(ada, "SELECT * FROM my_stock")[0]["timber"] in range(8000 - 620, 8000 - 620 + 10), True)
check("and nothing else rises above the Keep meanwhile", call(ada, "upgrade", farm["id"]), "Raise your Keep to level 2 first.")
check("and not the same thing twice", call(ada, "upgrade", keep["id"]), "Your Keep is already being built.")
import time
deadline = time.time() + 30
while time.time() < deadline and rows(ada, "SELECT * FROM my_jobs"):
    time.sleep(1)
check("the realm's own timer finishes it", [b["level"] for b in rows(ada, "SELECT * FROM my_buildings") if b["kind"] == 1], [2])
check("and everyone sees the city's Keep at level 2", [c["keep"] for c in rows(nobody, "SELECT * FROM city") if c["name"] == "Ada of the Lake"], [2])
check("now the Farm may follow", call(ada, "upgrade", farm["id"]), None)
check("a second thing must wait for the builder", call(ada, "build", 4), "Your builders are busy. Wait for them to finish.")
check("a building not yet open is refused", call(bryn, "build", 10), "Raise your Keep to level 10 first.")

# A faster realm, for the rest: its owner's alone to set.
check("a player can't set the realm's pace", call(bryn, "set_pace", 60), "Only the realm's owner may do that.")
import subprocess, shlex
owner = subprocess.run(shlex.split(spacetime) + ["call", "--server", server, db, "set_pace", "60"], capture_output=True, text=True)
check("its owner can", owner.returncode, 0)
check("and the catalogue is written out at the new pace", [(b["seconds"]) for b in rows(nobody, "SELECT * FROM blueprint") if b["building"] == 1 and b["level"] == 5], [10])

def until(what, done, seconds=90):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if done():
            return check(what, True, True)
        time.sleep(0.5)
    check(what, False, True)

def mine(token, kind):
    return next((b for b in rows(token, "SELECT * FROM my_buildings") if b["kind"] == kind), None)

# Troops: a Barracks raised, a batch trained on a timer.
check("Bryn raises the Keep", call(bryn, "upgrade", mine(bryn, 1)["id"]), None)
until("to level 2", lambda: mine(bryn, 1)["level"] == 2)
check("builds a Barracks", call(bryn, "build", 7), None)
until("which stands", lambda: (mine(bryn, 7) or {}).get("level") == 1)
barracks = mine(bryn, 7)
check("more than a batch holds is refused", call(bryn, "train", barracks["id"], 1, 51), "At most 50 at once.")
check("a tier not yet open is refused", call(bryn, "train", barracks["id"], 2, 10), "Raise your Barracks to level 5 first.")
check("twenty spearmen go into training", call(bryn, "train", barracks["id"], 1, 20), None)
check("one batch at a time", call(bryn, "train", barracks["id"], 1, 5), "Your Barracks is already training troops.")
until("and stand ready", lambda: [(t["kind"], t["tier"], t["ready"]) for t in rows(bryn, "SELECT * FROM my_troops")] == [(1, 1, 20)])
check("only their owner counts them", rows(ada, "SELECT * FROM my_troops"), [])
check("the troop table itself is closed to clients", isinstance(rows(bryn, "SELECT * FROM troop"), str), True)
check("troops are raised only upward", call(bryn, "promote", barracks["id"], 1, 1, 5), "Troops are raised only to a higher tier.")
check("nor past what the Barracks trains", call(bryn, "promote", barracks["id"], 1, 2, 5), "Raise your Barracks to level 5 first.")

# A march: out along a way, gathering, and home with the goods.
def unpacked(packed):
    return ((packed >> 16) & 0xFFFF) - 32768, (packed & 0xFFFF) - 32768

def distance(a, b):
    dq, dr = a[0] - b[0], a[1] - b[1]
    return (abs(dq) + abs(dr) + abs(dq + dr)) // 2

home = unpacked(rows(bryn, "SELECT * FROM my_city")[0]["hex"])
sites = sorted(rows(nobody, "SELECT * FROM site"), key=lambda site: distance(unpacked(site["hex"]), home))
check("sites lie scattered over the land", len(sites) > 500, True)
check("nothing is gathered where nothing lies", call(bryn, "send", home[0], home[1], 1, [{"kind": 1, "tier": 1, "count": 5}], 0), "There is nothing to gather there.")
check("more than stand ready can't be sent", call(bryn, "send", *unpacked(sites[0]["hex"]), 1, [{"kind": 1, "tier": 1, "count": 21}], 0), "You have only 20 tier 1 Spearmen ready.")
site, sent = None, "There is no way there over open ground."
for site in sites[:20]:
    sent = call(bryn, "send", *unpacked(site["hex"]), 1, [{"kind": 1, "tier": 1, "count": 20}], 0)
    if sent != "There is no way there over open ground.":
        break
check("an army sets out for the nearest site", sent, None)
before = rows(bryn, "SELECT * FROM my_stock")[0]
marches = rows(nobody, "SELECT * FROM march")
check("everyone sees it on the map", [(m["kind"], m["state"], m["soldiers"], m["target"]) for m in marches], [(1, 1, 20, site["id"])])
route = marches[0]["route"]
check("with the way it takes, from its city to the site", (len(route) >= 16, marches[0]["from"] == rows(bryn, "SELECT * FROM my_city")[0]["hex"], marches[0]["to"] == site["hex"]), (True, True, True))
check("what it is made of is its owner's alone to read", [(q["kind"], q["tier"], q["count"]) for q in rows(bryn, "SELECT * FROM my_squads")], [(1, 1, 20)])
check("and no one else's", rows(ada, "SELECT * FROM my_squads"), [])
check("its soldiers are out of the city", rows(bryn, "SELECT * FROM my_troops"), [])
check("one army at a time at Keep 2", call(bryn, "send", *unpacked(sites[1]["hex"]), 1, [{"kind": 1, "tier": 1, "count": 1}], 0) in ("You have only 0 tier 1 Spearmen ready.", "Your one army is out. Raise your Keep to send more."), True)
until("it reaches the site and works it", lambda: [m["state"] for m in rows(nobody, "SELECT * FROM march")] == [2], 60)
check("the site is its while it works", [s["gatherer"] for s in rows(nobody, "SELECT * FROM site") if s["id"] == site["id"]], [marches[0]["id"]])
# An army may fall on another's gathering there, but not on its own, nor where no one gathers.
check("no army falls on its own", call(bryn, "send", *unpacked(site["hex"]), 8, [{"kind": 1, "tier": 1, "count": 1}], 0), "That is your own army.")
check("nor where no one gathers", call(bryn, "send", *unpacked(sites[1]["hex"]), 8, [{"kind": 1, "tier": 1, "count": 1}], 0), "No army is gathering there.")
check("another's army may be fallen on, by soldiers there are", (call(ada, "send", *unpacked(site["hex"]), 8, [{"kind": 1, "tier": 1, "count": 100000}], 0) or "").startswith("You have only "), True)
until("then turns for home with its load", lambda: [m["state"] for m in rows(nobody, "SELECT * FROM march")] == [3], 60)
good = {1: "grain", 2: "timber", 3: "stone", 4: "moonsalt"}[site["kind"]]
check("carrying what twenty spearmen carry", [h[good] for h in rows(bryn, "SELECT * FROM my_hauls")], [240])
check("which has come off the site", [s["left"] for s in rows(nobody, "SELECT * FROM site") if s["id"] == site["id"]], [site["left"] - 240])
until("and comes home", lambda: rows(nobody, "SELECT * FROM march") == [], 60)
check("its soldiers ready again", [(t["kind"], t["ready"]) for t in rows(bryn, "SELECT * FROM my_troops")], [(1, 20)])
after = rows(bryn, "SELECT * FROM my_stock")[0]
check("and its load in the city's stock", after[good] >= before[good] + 240, True)

# A new city is at peace: no army may be sent against it yet.
theirs = rows(nobody, "SELECT * FROM city")
check("every city shows until when it is at peace", all(city["shield"] > city["founded"] for city in theirs), True)
adas = unpacked(rows(ada, "SELECT * FROM my_city")[0]["hex"])
refused = call(bryn, "send", adas[0], adas[1], 3, [{"kind": 1, "tier": 1, "count": 1}], 0)
check("an army sent against a new city is refused", (refused or "").startswith("That city is at peace for another "), True)
check("and against one's own", call(bryn, "send", home[0], home[1], 3, [{"kind": 1, "tier": 1, "count": 1}], 0), "That is your own city.")
check("the realm's fame is for all to read, and no one has any before a city is fought", rows(nobody, "SELECT * FROM fame"), [])
check("no alliance's gift waits on one in none", rows(bryn, "SELECT * FROM my_boons"), [])
check("so none is claimed", call(bryn, "claim_boons"), "No gift is waiting on you.")
check("and no one reads the gifts' table itself", isinstance(rows(bryn, "SELECT * FROM boon"), str), True)
cairns = sorted(rows(nobody, "SELECT * FROM cairn"), key=lambda cairn: distance(unpacked(cairn["hex"]), home))
check("cairns stand on the land, for all to read, of levels one to five", len(cairns) > 0 and all(1 <= cairn["level"] <= 5 for cairn in cairns), True)
check("no scouts go where no cairn stands", call(bryn, "send", home[0], home[1], 7, [{"kind": 1, "tier": 1, "count": 1}], 0), "No cairn stands there.")
check("nor to a cairn from a city without a Scout Camp", call(bryn, "send", *unpacked(cairns[0]["hex"]), 7, [{"kind": 1, "tier": 1, "count": 1}], 0), "Raise your Scout Camp to level 1 first.")
check("no cairn's hoard is found yet", rows(bryn, "SELECT * FROM my_finds"), [])
check("and no one reads the finds' table itself", isinstance(rows(bryn, "SELECT * FROM find"), str), True)
check("the alliance's stores' prices are for all to read", sorted((price["item"], price["honour"]) for price in rows(nobody, "SELECT * FROM price")), [(1, 100), (2, 1000), (3, 6000), (4, 5000), (9, 250), (10, 2000)])
check("one in no alliance has no honour", rows(bryn, "SELECT * FROM my_honour"), [])
check("and buys nothing from an alliance's stores", call(bryn, "buy", 1, 1), "You are in no alliance.")
check("and no one reads the honour table itself", isinstance(rows(bryn, "SELECT * FROM honour"), str), True)
check("tomes of war are among the realm's wares, read by commanders", sorted((ware["item"], ware["kind"]) for ware in rows(nobody, "SELECT * FROM ware") if ware["item"] >= 9), [(9, 4), (10, 4)])
check("no tome is read by a commander one does not have", call(bryn, "read_tome", 999, 9, 1), "You have no such commander.")

# A player's first tasks: the first is to raise the Keep, which Ada has done.
tasks = rows(nobody, "SELECT * FROM task")
check("the first tasks are written out for all to read", (len(tasks), sorted(tasks, key=lambda task: task["step"])[0]["words"]), (24, "Raise your Keep to level 2."))
check("some give hastes and tomes besides", [(task["brief_hastes"], task["tomes"]) for task in sorted(tasks, key=lambda task: task["step"])[1:4]], [(2, 0), (3, 0), (0, 1)])
check("a player is on the first", rows(ada, "SELECT * FROM my_progress"), [{"player": rows(ada, "SELECT * FROM me")[0]["id"], "step": 1}])
grain = rows(ada, "SELECT * FROM my_stock")[0]["grain"]
check("a task done is claimed", call(ada, "claim_task"), None)
check("and gives what it promised", (rows(ada, "SELECT * FROM my_stock")[0]["grain"] >= grain + 1000, rows(ada, "SELECT * FROM my_progress")[0]["step"]), (True, 2))
check("the next is not done yet", call(ada, "claim_task"), "Not done yet: Build a Barracks.")
check("no one reads another's progress", isinstance(rows(ada, "SELECT * FROM progress"), str), True)

# A player's other device, their phone beside their Mac: a code asked for
# on one, taken on the other, which plays as them from then on.
check("a code is asked for", call(ada, "offer_link"), None)
link = rows(ada, "SELECT * FROM my_link")
check("and shown to its player alone", (len(link), len(link[0]["letters"]) if link else 0, rows(bryn, "SELECT * FROM my_link"), isinstance(rows(ada, "SELECT * FROM link"), str)), (1, 10, [], True))
phone = someone()
check("another device takes it, however typed", call(phone, "take_link", link[0]["letters"].lower() if link else ""), None)
check("and plays as its player", [p["name"] for p in rows(phone, "SELECT * FROM me")], [p["name"] for p in rows(ada, "SELECT * FROM me")])
check("the code is used up", (call(someone(), "take_link", link[0]["letters"] if link else ""), rows(ada, "SELECT * FROM my_link")), ("No code of yours reads so, or it has been used. Ask your other device for a new one.", []))
check("a device that plays already takes no code", call(bryn, "take_link", "ABCDEFGHJK"), "You have already joined the realm.")

# The day's work: five deeds and three chests, the same for everyone.
duties = rows(nobody, "SELECT * FROM duty")
chests = rows(nobody, "SELECT * FROM chest")
check("the day's deeds and chests are written out for all to read", (len(duties), sum(duty["marks"] for duty in duties), sorted(chest["marks"] for chest in chests)), (5, 100, [40, 70, 100]))
today = rows(ada, "SELECT * FROM my_daily")
check("what a player has begun today is counted", (len(today), today[0]["begun"] >= 1 if today else None), (1, True))
check("a chest not yet earned is refused", call(ada, "open_chest", 3), "That chest opens at 100 marks of the day's work.")
check("and one that is not there", call(ada, "open_chest", 9), "There is no such chest.")
check("no one reads another's day", isinstance(rows(ada, "SELECT * FROM daily"), str), True)

# Favour: its levels for all to read; none earned until a chest is opened.
graces = sorted(rows(nobody, "SELECT * FROM grace"), key=lambda grace: grace["level"])
check("the levels of favour are written out for all to read", (len(graces), graces[0]["points"], graces[-1]["sooner"]), (11, 0, 10))
check("a player has none until they open a chest", (rows(ada, "SELECT * FROM my_favour"), isinstance(rows(ada, "SELECT * FROM favour"), str)), ([], True))

# Items: the hastes a chest holds, kept in a satchel until they are used.
wares = sorted(rows(nobody, "SELECT * FROM ware"), key=lambda ware: ware["item"])
check("the items are written out for all to read", [(ware["name"], ware["seconds"], ware["kind"]) for ware in wares], [("Five minutes' haste", 300, 1), ("An hour's haste", 3600, 1), ("Eight hours' haste", 28800, 1), ("Eight hours' peace", 28800, 2), ("Iron", 0, 3), ("Leather", 0, 3), ("Bone", 0, 3), ("Silver", 0, 3), ("Tome of war", 0, 4), ("Great tome of war", 0, 4)])
check("the day's last chest holds a peace", [chest["peaces"] for chest in sorted(chests, key=lambda chest: chest["id"])], [0, 0, 1])
check("and every chest says what hastes it holds", all(chest["brief_hastes"] + chest["hour_hastes"] + chest["long_hastes"] > 0 for chest in chests), True)
check("a satchel begins empty, and is its owner's alone to read", (rows(ada, "SELECT * FROM my_satchel"), isinstance(rows(ada, "SELECT * FROM satchel"), str)), ([], True))
check("a haste a player has not got is refused", call(ada, "use_item", 1, 1), "No such work is under way in your city.")
check("and a thing that is no item", call(ada, "use_item", 99, 1), "There is no such thing to use.")
check("a tome is read by a commander, not used on a work", call(ada, "use_item", 9, 1), "A tome is read by one of your commanders.")
check("a peace is kept on the city, not on a work", call(ada, "use_item", 4, 1), "That keeps your city at peace; it hastens no work.")
check("a material is worked at the Forge, not used", call(ada, "use_item", 5, 1), "That is worked at the Forge into gear.")
# The Forge: what it makes, for all to read; gear its owner's alone.
patterns = rows(nobody, "SELECT * FROM pattern")
check("what the Forge makes is written out for all to read", (len(patterns), sorted(p["name"] for p in patterns if p["grade"] == 1)), (12, ["Iron sword", "Leather boots", "Leather cap", "Leather coat"]))
check("nothing is made without a Forge", call(ada, "forge", 1), "Raise your Forge to level 1 first.")
check("gear is its owner's alone to read", (rows(ada, "SELECT * FROM my_gear"), isinstance(rows(ada, "SELECT * FROM gear"), str)), ([], True))
check("and one a player has not got is refused", call(ada, "use_peace", 4), "You have none of that left.")

# The realm's contests: the Long Hunt, running as the realm opens.
trials = rows(nobody, "SELECT * FROM trial")
prizes = sorted(rows(nobody, "SELECT * FROM prize"), key=lambda prize: prize["place"])
trials = sorted(trials, key=lambda trial: trial["id"])
check("the contests and their prizes are written out for all to read", ([(trial["name"], trial["every"], trial["lasts"], trial["opens"]) for trial in trials], [prize["points"] for prize in prizes if prize["trial"] == 1]), ([("The Long Hunt", 7, 3, 0), ("The Harvest Moon", 7, 3, 2), ("The Call to Arms", 7, 3, 4), ("The Raising", 7, 3, 1), ("The Red Field", 7, 2, 5)], [100, 400, 1000]))
check("a prize not yet earned is refused", call(ada, "claim_prize", 1, 1), "That prize is for 100 points.")
check("and one that is not there", call(ada, "claim_prize", 1, 9), "There is no such prize.")
laurels = rows(nobody, "SELECT * FROM laurel")
check("what the first three places give is written out for all to read", (len(laurels), sorted(laurel["long_hastes"] for laurel in laurels if laurel["trial"] == 1)), (15, [1, 2, 3]))
check("the contests' standings are for all to read", isinstance(rows(nobody, "SELECT * FROM standing"), list), True)
check("no place is claimed before a round is over", call(ada, "claim_place", 3), "No round of that contest is over yet.")
check("no one reads another's tallies", isinstance(rows(ada, "SELECT * FROM tally"), str), True)

# Rallies are an alliance's: one in none can neither call nor join one, and an army goes to one no other way.
check("a rally is called by a member of an alliance", call(ada, "call_rally", adas[0], adas[1], [{"kind": 1, "tier": 1, "count": 1}], 0), "You are in no alliance.")
check("and joined by one", call(ada, "join_rally", 1, [{"kind": 1, "tier": 1, "count": 1}], 0), "You are in no alliance.")
check("an army is not sent to a rally by an order of its own", call(ada, "send", adas[0], adas[1], 6, [{"kind": 1, "tier": 1, "count": 1}], 0), "The realm knows no such order.")
# The Moonspire: a race among alliances, season by season.
seasons = rows(nobody, "SELECT * FROM season")
check("the first season is written out for all to read, begun as the realm opened", ([(season["number"], season["victor"]) for season in seasons], seasons[0]["ends"] > seasons[0]["began"] if seasons else None), ([(1, 0)], True))
check("and every alliance's Moonspire with it", isinstance(rows(nobody, "SELECT * FROM spire"), list), True)
check("one in no alliance has no Moonspire to give toward", call(ada, "give_to_spire", 10, 10, 10, 0), "You are in no alliance.")
check("and what a player has given is theirs alone to read", (rows(ada, "SELECT * FROM my_gift"), isinstance(rows(ada, "SELECT * FROM gift"), str)), ([], True))
check("help is asked of an alliance, and given within one", (call(ada, "ask_help", 1), call(ada, "help", 0)), ("You are in no alliance.", "You are in no alliance."))
check("one in no alliance sees no asking for help, and no one reads the table itself", (rows(ada, "SELECT * FROM my_pleas"), rows(ada, "SELECT * FROM my_helps"), isinstance(rows(ada, "SELECT * FROM plea"), str)), ([], [], True))
check("one in no alliance sees no rallies, and no one reads the table itself", (rows(ada, "SELECT * FROM my_rallies"), rows(ada, "SELECT * FROM my_musters"), isinstance(rows(ada, "SELECT * FROM rally"), str)), ([], [], True))
# An alliance's land: its wardstones, for all to read; raised only by an alliance's officers.
check("every wardstone is for all to read, and there are none yet", rows(nobody, "SELECT * FROM ward"), [])
check("one in no alliance raises none", call(ada, "raise_ward", adas[0] + 3, adas[1]), "You are in no alliance.")
check("nor takes one down", call(ada, "raze_ward", 1), "You are in no alliance.")
# A city moves only to clear ground (or, while an army of its is out, not at all).
check("a city is moved by its owner, never into the lake", call(ada, "move_city", 0, 0) in ("No city can stand there.", "Bring your armies home before your city moves."), True)
# What an alliance learns together: for all to read; given toward only by its members.
check("what alliances have learnt is for all to read, and there is nothing yet", rows(nobody, "SELECT * FROM learning"), [])
check("one in no alliance gives nothing toward it", call(ada, "give_to_learning", 1, 10, 10, 10), "You are in no alliance.")
# Envoys and pacts between alliances: every pact for all to read, an envoy its two alliances' alone.
check("every pact is for all to read, and there are none yet", rows(nobody, "SELECT * FROM pact"), [])
check("one in no alliance sends no envoy", call(ada, "send_envoy", 1, 1, 3), "You are in no alliance.")
check("one in no alliance sees no envoys, and no one reads the table itself", (rows(ada, "SELECT * FROM my_envoys"), isinstance(rows(ada, "SELECT * FROM envoy"), str)), ([], True))
# Prisoners: a player's own to read; none held yet, and no one ransoms or lets go what is not theirs.
check("no one is held yet, and no one reads the table itself", (rows(ada, "SELECT * FROM my_prisoners"), isinstance(rows(ada, "SELECT * FROM prisoner"), str)), ([], True))
check("a commander not held is not ransomed, nor let go", (call(ada, "ransom", 1), call(ada, "release_prisoner", 1)), ("There is no such prisoner of yours.",) * 2)
# Petitions: an alliance's alone to read; one in none petitions nothing.
check("one in no alliance petitions no one", call(ada, "petition_alliance", 10, 0, 0, 0), "You are in no alliance.")
check("one in no alliance sees no petitions, and no one reads the table itself", (rows(ada, "SELECT * FROM my_petitions"), isinstance(rows(ada, "SELECT * FROM petition"), str)), ([], True))
# The titles of the Mere: for all to read; none held, and none bestowed with no season yet won.
check("the titles are for all to read, and none is held", rows(nobody, "SELECT * FROM title"), [])
check("no one bestows a title before a season is won", call(ada, "bestow_title", 1, 2), "Only the Lord of the Mere bestows its titles: the leader of the alliance that won the last season.")
# Letters: a player's own to read; one written, and read by the one it is to.
check("a letter goes to another player", call(ada, "send_letter", 2, "Well met, neighbour."), None)
check("who reads it in their letters, and no one reads the table itself", ([(l["sender"], l["words"], l["read"]) for l in rows(bryn, "SELECT * FROM my_letters")], isinstance(rows(bryn, "SELECT * FROM letter"), str)), ([(1, "Well met, neighbour.", False)], True))
check("an officer's letter to the alliance needs an alliance", call(ada, "send_alliance_letter", "To all."), "You are in no alliance.")
# The gates of the ridge: six, for all to read, held by the Unquiet as the realm opens; stormed only by an alliance's rally.
gates = sorted(rows(nobody, "SELECT * FROM gate"), key=lambda gate: gate["id"])
check("six gates stand in the ridge's passes, held by the Unquiet", [(gate["id"], gate["holder"], gate["fighter"]) for gate in gates], [(n, 0, 0) for n in range(1, 7)])
first_gate = unpacked(gates[0]["hex"]) if gates else (0, 0)
check("one in no alliance calls no rally against a gate", call(ada, "call_rally", first_gate[0], first_gate[1], [{"kind": 1, "tier": 1, "count": 1}], 0), "You are in no alliance.")
check("nor is an army sent against one by an order of its own", call(ada, "send", first_gate[0], first_gate[1], 3, [{"kind": 1, "tier": 1, "count": 1}], 0), "There is no city to attack there.")

# Commanders: one to begin with, more from a Tavern.
captains = rows(bryn, "SELECT * FROM my_commanders")
check("a player begins with one commander, in the city", [(c["level"], c["march"], 1 <= c["way"] <= 6, len(c["name"]) >= 3) for c in captains], [(1, 0, True, True)])
check("another is taken on from a Tavern", call(bryn, "hire"), "Raise your Tavern to level 1 first.")
check("no one reads another's commanders", (rows(ada, "SELECT * FROM my_commanders") != captains, isinstance(rows(bryn, "SELECT * FROM commander"), str)), (True, True))

# Talents, pairs and the city's keeper: points come with levels, so a new commander has none.
captain = captains[0]
check("a commander at level 1 has no points to spend on a talent", call(bryn, "learn_talent", captain["id"], 1), f"{captain['name']} has no points left to spend. They gain one with each level.")
check("and a talent that is not one", call(bryn, "learn_talent", captain["id"], 99), "There is no such talent.")
check("one with none learnt has nothing to forget", call(bryn, "forget_talents", captain["id"]), "That commander has learnt no talents to forget.")
check("a commander goes out beside another, not beside themselves", call(bryn, "pair", captain["id"], captain["id"]), "A commander can't go out beside themselves.")
check("another player's commander is not theirs to teach, pair or set to keep a city", (call(ada, "learn_talent", captain["id"], 1), call(ada, "pair", captain["id"], 0), call(ada, "keep_city", captain["id"])), ("You have no such commander.",) * 3)
check("none learnt and none paired, and no one reads the tables themselves", (rows(bryn, "SELECT * FROM my_skills"), rows(bryn, "SELECT * FROM my_bonds"), isinstance(rows(bryn, "SELECT * FROM skill"), str), isinstance(rows(bryn, "SELECT * FROM bond"), str)), ([], [], True, True))
check("a commander is set to keep the city", (call(bryn, "keep_city", captain["id"]), [k["commander"] for k in rows(bryn, "SELECT * FROM my_keeper")], rows(ada, "SELECT * FROM my_keeper")), (None, [captain["id"]], []))
check("and stood down from it, and no one reads the table itself", (call(bryn, "keep_city", 0), rows(bryn, "SELECT * FROM my_keeper"), isinstance(rows(ada, "SELECT * FROM keeper"), str)), (None, [], True))

# What an Academy studies.
studies = rows(nobody, "SELECT * FROM study")
check("the studies are written out for all to read", (len(studies), sorted(s["name"] for s in studies if s["level"] == 1)[:3]), (150, ["Archery", "Building", "Drill"]))
check("each says what opens it: Tillage begins the works, Drill the arms", sorted((s["name"], s["after_topic"], s["after_level"]) for s in studies if s["level"] == 1 and s["name"] in ("Tillage", "Drill", "Forestry", "Horsemanship")), [("Drill", 0, 0), ("Forestry", 1, 1), ("Horsemanship", 8, 2), ("Tillage", 0, 0)])
check("nothing is studied without an Academy", call(ada, "learn", 1), "Raise your Academy to level 1 first.")
check("what a city has learnt is its owner's alone", (rows(ada, "SELECT * FROM my_lore"), isinstance(rows(ada, "SELECT * FROM lore"), str)), ([], True))

# What players say to one another, and alliances.
check("a player speaks to the realm", call(ada, "say", False, "  Good   morning, all. "), None)
check("and everyone reads it, tidied, under their name", [(s["name"], s["words"]) for s in rows(nobody, "SELECT * FROM realm_chat")], [("Ada of the Lake", "Good morning, all.")])
check("one thing at a time", call(ada, "say", False, "And again"), "Wait a moment before you say more.")
check("nothing is not said", call(bryn, "say", False, "   "), "Say something first.")
check("no alliance, no alliance's chat", call(bryn, "say", True, "Hello?"), "You are in no alliance.")
# Keeping the peace: a line reported and kept for the owner, who takes it
# away; a player barred from speaking, and the bar lifted.
def as_owner(*command):
    return subprocess.run(shlex.split(spacetime) + list(command[:1]) + ["--server", server, db] + [str(part) for part in command[1:]], capture_output=True, text=True)
said_line = rows(nobody, "SELECT * FROM realm_chat")[0]["id"]
check("a player reports a line", call(bryn, "report_line", said_line, False), None)
check("once", call(bryn, "report_line", said_line, False), "You have reported that line already.")
check("never their own words", call(ada, "report_line", said_line, False), "Those are your own words.")
check("nor a line that isn't there", call(bryn, "report_line", 999, False), "There is no such line to report.")
check("reports are closed to players", isinstance(rows(bryn, "SELECT * FROM complaint"), str), True)
check("the owner reads it, with the line", "Good morning, all." in as_owner("sql", "SELECT * FROM complaint").stdout, True)
check("only the owner takes a line away", call(bryn, "take_away", said_line, False), "Only the realm's owner may do that.")
check("the owner does", as_owner("call", "take_away", said_line, "false").returncode, 0)
check("and it stands where it was, its words gone", [(s["name"], s["words"]) for s in rows(nobody, "SELECT * FROM realm_chat") if s["id"] == said_line], [("Ada of the Lake", "")])
check("its report let go", "Good morning, all." in as_owner("sql", "SELECT * FROM complaint").stdout, False)
ada_id = rows(ada, "SELECT * FROM me")[0]["id"]
check("only the owner bars a player", call(bryn, "bar_player", ada_id, 1), "Only the realm's owner may do that.")
check("the owner bars one for an hour", as_owner("call", "bar_player", ada_id, 1).returncode, 0)
check("who may not speak", (call(ada, "say", False, "Hello again") or "").startswith("You may not speak for another "), True)
check("until the bar is lifted", as_owner("call", "bar_player", ada_id, 0).returncode, 0)
time.sleep(2)  # a moment after her last words, as anyone waits between sayings
check("and they speak again", call(ada, "say", False, "Hello again"), None)
check("an alliance is founded from an Embassy", call(bryn, "found_alliance", "Keepers of the Mere", "MERE"), "Raise your Embassy to level 1 first.")
check("there is none to join yet", call(bryn, "join_alliance", 1), "There is no such alliance.")
check("nor to leave", call(bryn, "leave_alliance"), "You are in no alliance.")
check("the alliance tables are read by all, and empty", (rows(nobody, "SELECT * FROM alliance"), rows(nobody, "SELECT * FROM member")), ([], []))
check("an alliance's chat is closed to clients, but for its members' view", (isinstance(rows(bryn, "SELECT * FROM alliance_chat"), str), rows(bryn, "SELECT * FROM my_alliance_chat")), (True, []))
check("as is who has asked to join", (isinstance(rows(bryn, "SELECT * FROM applicant"), str), rows(bryn, "SELECT * FROM my_applicants")), (True, []))

# The Unquiet: a barrow cleared, its report read, the wounded healed.
barrows = sorted(rows(nobody, "SELECT * FROM barrow"), key=lambda barrow: distance(unpacked(barrow["hex"]), home))
check("barrows of the Unquiet stand over the land", len(barrows) > 300, True)
check("a player begins with all their energy and nothing cleared", [(h["energy"], h["most"], h["cleared"]) for h in rows(bryn, "SELECT * FROM my_hunt")], [(1000, 1000, 0)])
strong = next(barrow for barrow in barrows if barrow["level"] >= 3)
check("a barrow too strong is refused", call(bryn, "send", *unpacked(strong["hex"]), 2, [{"kind": 1, "tier": 1, "count": 20}], 0), f"Clear a level {strong['level'] - 1} barrow first.")
check("fifty more spearmen go into training", call(bryn, "train", barracks["id"], 1, 50), None)
until("and stand ready", lambda: [(t["kind"], t["ready"]) for t in rows(bryn, "SELECT * FROM my_troops")] == [(1, 70)])
# Slower from here, so that the fight lasts long enough to be seen.
slower = subprocess.run(shlex.split(spacetime) + ["call", "--server", server, db, "set_pace", "5"], capture_output=True, text=True)
check("the realm's owner slows it", slower.returncode, 0)
barrow, sent = None, "There is no way there over open ground."
for barrow in [barrow for barrow in barrows if barrow["level"] == 1][:20]:
    sent = call(bryn, "send", *unpacked(barrow["hex"]), 2, [{"kind": 1, "tier": 1, "count": 70}], captains[0]["id"])
    if sent != "There is no way there over open ground.":
        break
check("an army sets out against the nearest weak barrow", sent, None)
check("which takes fifty energy", [950 <= h["energy"] < 1000 for h in rows(bryn, "SELECT * FROM my_hunt")], [True])
until("it reaches the barrow and fights", lambda: [m["state"] for m in rows(nobody, "SELECT * FROM march")] == [4], 180)
hunting = rows(nobody, "SELECT * FROM march")[0]
check("under the commander who was asked to lead it", (hunting["leader"], [c["march"] for c in rows(bryn, "SELECT * FROM my_commanders")]), (captains[0]["id"], [hunting["id"]]))
check("the barrow is its while it fights", [b["fighter"] for b in rows(nobody, "SELECT * FROM barrow") if b["id"] == barrow["id"]], [hunting["id"]])
check("and it can't be called away", call(bryn, "recall", hunting["id"]), "That army is fighting. Wait for the fight to end.")
until("the fight ends and it turns for home", lambda: [m["state"] for m in rows(nobody, "SELECT * FROM march")] == [3], 60)
told = rows(bryn, "SELECT * FROM my_reports")
check("its player is told how it went", [(r["won"], r["foe"], r["fought"], r["stood"], r["fell"], r["dead"], r["read"]) for r in told], [(True, 1, 70, 25, 25, 0, False)])
# As much of the barrow's 800 grain and 800 timber as those still standing carry, twelve each,
# and more by the leader's bonus: a gleaner (way 6) carries five hundredths and one more a level,
# and this commander is still at level 1. The way is chosen by the realm's seed, so it is read.
carries = 5 + 1 if captains[0]["way"] == 6 else 0
carried = min(800, (70 - told[0]["wounded"]) * 12 * (100 + carries) // 100 // 2)
told_words = f"Your army cleared a level 1 barrow of the Unquiet. Of your 70 soldiers, {told[0]['wounded']} {'was' if told[0]['wounded'] == 1 else 'were'} wounded. It is bringing home {carried} grain and {carried} timber. It found 1 "
check("in plain words, with what it found for the Forge", (told[0]["words"].startswith(told_words), told[0]["words"].endswith(" for the Forge.")), (True, True))
check("which is in its player's satchel", sum(s["count"] for s in rows(bryn, "SELECT * FROM my_satchel") if 5 <= s["item"] <= 8), 1)
check("and it carries the spoils", [(h["grain"], h["timber"]) for h in rows(bryn, "SELECT * FROM my_hauls")], [(carried, carried)])
check("and no one else is", rows(ada, "SELECT * FROM my_reports"), [])
check("the report table itself is closed to clients", isinstance(rows(bryn, "SELECT * FROM report"), str), True)
check("the barrow is gone", [b for b in rows(nobody, "SELECT * FROM barrow") if b["id"] == barrow["id"]], [])
check("another stands somewhere", len(rows(nobody, "SELECT * FROM barrow")), len(barrows))
check("and the player has cleared the first level", [h["cleared"] for h in rows(bryn, "SELECT * FROM my_hunt")], [1])
check("the report is marked read", (call(bryn, "read_report", told[0]["id"]), [r["read"] for r in rows(bryn, "SELECT * FROM my_reports")]), (None, [True]))
check("another player can't read it", call(ada, "read_report", told[0]["id"]), "There is no such report.")
until("the army comes home", lambda: rows(nobody, "SELECT * FROM march") == [], 180)
check("its commander with it, having seen the Unquiet fall", [(c["march"], c["seen"]) for c in rows(bryn, "SELECT * FROM my_commanders")], [(0, 25)])
wounded = told[0]["wounded"]
check("with its wounded", [(t["ready"], t["wounded"]) for t in rows(bryn, "SELECT * FROM my_troops")], [(70 - wounded, wounded)])
check("more than lie wounded can't be healed", call(bryn, "heal", 1, 1, wounded + 1), f"You have only {wounded} wounded tier 1 Spearmen.")
if wounded:
    check("the wounded are healed for goods", call(bryn, "heal", 1, 1, wounded), None)
    until("and stand ready again", lambda: [(t["ready"], t["wounded"]) for t in rows(bryn, "SELECT * FROM my_troops")] == [(70, 0)], 60)
check("the report is thrown away", (call(bryn, "forget_report", told[0]["id"]), rows(bryn, "SELECT * FROM my_reports")), (None, []))

if failures:
    print(f"{len(failures)} of the realm's checks failed")
    sys.exit(1)
print("The realm plays through.")
PY
