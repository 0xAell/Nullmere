#!/usr/bin/env python3
"""Measures the realm under load: many players asking it at once.

    realm/load.py <server> <database> [players] [seconds] [workers] [figures.json]

First `players` (100) players join at once over `workers` (16)
connections, each under an identity the server makes for them, and
each finds their Keep. Then for `seconds` (30) every connection asks,
player after player, what players ask most: their Keep raised a level
(done once, then refused while it rises), a Barracks built (refused
until the Keep allows it), and a look at their own city. Each ask is
timed from asking to answer.

For each kind of ask it prints how many were asked, how many were done,
refused or failed, and the median, 95th and 99th hundredths and the
slowest of their times; and for the half minute, how many were answered
a second. The same go to `figures.json` (build/realm-load.json). A
refusal is an answer, the realm deciding; a failure is no answer, or the
server's error. More than one ask in a hundred failing fails the run.

Server and players share one machine here, a CI runner, and every ask
is a fresh HTTP request: these are the realm's own times, as a player
on the same network would see them, not across the world.
"""
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

arguments = sys.argv[1:]
if len(arguments) < 2:
    sys.exit(__doc__)
host, db = arguments[0].rstrip("/"), arguments[1]
players = int(arguments[2]) if len(arguments) > 2 else 100
seconds = float(arguments[3]) if len(arguments) > 3 else 30
workers = int(arguments[4]) if len(arguments) > 4 else 16
out = arguments[5] if len(arguments) > 5 else "build/realm-load.json"

# The realm lets 120 join a minute, and each player ask 40 things in ten
# seconds (realm/src/rules/entry.rs): a run asks within both.
assert players <= 120, "the realm lets no more than 120 join in a minute"

lock = threading.Lock()
timings = {}


def post(path, body, token=None, content="application/json"):
    """Asks the server; the answer's status and body, or None for no answer."""
    request = urllib.request.Request(host + path, data=body.encode(), method="POST")
    request.add_header("Content-Type", content)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()
    except (urllib.error.URLError, OSError):
        return None, ""


def timed(kind, path, body, token=None, content="application/json"):
    """Asks, and keeps how long the answer took and what it was."""
    began = time.perf_counter()
    status, text = post(path, body, token, content)
    took = (time.perf_counter() - began) * 1000
    outcome = "done" if status == 200 else "refused" if status in (400, 530) else "failed"
    with lock:
        timings.setdefault(kind, []).append((took, outcome))
    return status, text


def figures(entries):
    times = sorted(took for took, _ in entries)

    def at(share):
        return round(times[min(len(times) - 1, int(len(times) * share))], 2) if times else None

    counts = {outcome: sum(1 for _, o in entries if o == outcome) for outcome in ("done", "refused", "failed")}
    return {"asked": len(entries), **counts, "p50": at(0.5), "p95": at(0.95), "p99": at(0.99), "slowest": round(times[-1], 2) if times else None}


# Joining: an identity each, a name each, and each one's Keep found.
stamp = format(int(time.time()) % 46656, "x")


def arrive(index):
    status, body = timed("identity", "/v1/identity", "")
    if status != 200:
        return None
    token = json.loads(body)["token"]
    status, _ = timed("join", f"/v1/database/{db}/call/join", json.dumps([f"Load {stamp}{index}"]), token)
    if status != 200:
        return None
    status, body = timed("look", f"/v1/database/{db}/sql", "SELECT * FROM my_buildings", token, "text/plain")
    if status != 200:
        return None
    result = json.loads(body)[0]
    names = [element["name"]["some"] for element in result["schema"]["elements"]]
    keep = next((row for row in (dict(zip(names, row)) for row in result["rows"]) if row["kind"] == 1), None)
    return (token, keep["id"]) if keep else None


began = time.perf_counter()
with ThreadPoolExecutor(max_workers=workers) as pool:
    arrived = [player for player in pool.map(arrive, range(players)) if player]
joined = time.perf_counter() - began
print(f"LOAD {len(arrived)} of {players} players joined in {joined:.1f} s over {workers} connections")
if not arrived:
    sys.exit("No one could join.")

# The steady half minute: each connection takes players in turn, each
# asking one of the three, in turn too, so every player asks at the same
# rate: three times a second, within the realm's forty in ten seconds,
# the asks spread evenly over the half minute.
RATE = 3
turn = 0
turn_lock = threading.Lock()
asks = [
    ("raise", lambda token, keep: (f"/v1/database/{db}/call/upgrade", json.dumps([keep]), token, "application/json")),
    ("build", lambda token, keep: (f"/v1/database/{db}/call/build", json.dumps([7]), token, "application/json")),
    ("city", lambda token, keep: (f"/v1/database/{db}/sql", "SELECT * FROM my_city", token, "text/plain")),
]


def ask_until_done(_):
    global turn
    while time.perf_counter() < deadline:
        with turn_lock:
            mine = turn
            turn += 1
        due = steady_began + mine / (RATE * len(arrived))
        if due >= deadline:
            return
        wait = due - time.perf_counter()
        if wait > 0:
            time.sleep(wait)
        token, keep = arrived[mine % len(arrived)]
        kind, make = asks[(mine // len(arrived)) % len(asks)]
        path, body, token, content = make(token, keep)
        timed(kind, path, body, token, content)


steady_began = time.perf_counter()
deadline = steady_began + seconds
with ThreadPoolExecutor(max_workers=workers) as pool:
    list(pool.map(ask_until_done, range(workers)))
steady = time.perf_counter() - steady_began
answered = sum(len(timings.get(kind, [])) for kind, _ in asks)

report = {"players": len(arrived), "workers": workers, "each_a_second": RATE, "seconds": round(steady, 1), "per_second": round(answered / steady, 1),
          "joined_seconds": round(joined, 1), "asks": {kind: figures(entries) for kind, entries in sorted(timings.items())}}
for kind, line in report["asks"].items():
    print(f"LOAD {kind}: {line['asked']} asked, {line['done']} done, {line['refused']} refused, {line['failed']} failed; "
          f"p50 {line['p50']} ms, p95 {line['p95']} ms, p99 {line['p99']} ms, slowest {line['slowest']} ms")
print(f"LOAD {answered} asks answered in {steady:.1f} s by {len(arrived)} players, each asking {RATE} a second: {report['per_second']} a second")
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
with open(out, "w") as file:
    json.dump(report, file, indent=1)

failed = sum(line["failed"] for line in report["asks"].values())
total = sum(line["asked"] for line in report["asks"].values())
if failed * 100 > total:
    sys.exit(f"{failed} of {total} asks had no answer, or the server's error")
