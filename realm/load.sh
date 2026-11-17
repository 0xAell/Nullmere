#!/usr/bin/env bash
# The realm under load, on a SpacetimeDB already serving (realm/check.sh
# starts one): the module published afresh as its own database, then a
# hundred players joining at once and asking, each three times a second
# for half a minute, what players ask most (realm/load.py). Its figures
# are printed, LOAD lines, and kept in build/realm-load.json.
#
#   realm/load.sh
#
# REALM_HOST, REALM_SERVER, SPACETIME and REALM_WASM as realm/check.sh
# takes them; REALM_LOAD_DB the database (nullmere-load); LOAD_PLAYERS,
# LOAD_SECONDS and LOAD_WORKERS the run's size (100, 30, 16).
set -euo pipefail

cd "$(dirname "$0")/.."
HOST="${REALM_HOST:-http://127.0.0.1:3000}"
SERVER="${REALM_SERVER:-$HOST}"
DB="${REALM_LOAD_DB:-nullmere-load}"
SPACETIME="${SPACETIME:-spacetime}"
WASM="${REALM_WASM:-$PWD/realm/target/wasm32-unknown-unknown/release/realm.wasm}"

curl -s -o /dev/null -X POST "$HOST/v1/identity" || { echo "error: no SpacetimeDB at $HOST; realm/check.sh starts one" >&2; exit 1; }
[ -f "$WASM" ] || { echo "error: no module at $WASM; realm/check.sh builds it" >&2; exit 1; }

echo "== Publishing $DB"
$SPACETIME publish --server "$SERVER" --bin-path "$WASM" --yes --delete-data "$DB" | tail -2

echo "== The realm under load"
python3 -I realm/load.py "$HOST" "$DB" "${LOAD_PLAYERS:-100}" "${LOAD_SECONDS:-30}" "${LOAD_WORKERS:-16}" build/realm-load.json
