#!/usr/bin/env bash
# Starts SpacetimeDB on this machine, where nothing answers yet, and
# publishes the realm (realm/) to it under a name, its data fresh, at a
# pace its owner sets: what CI's Mac jobs play the app against, as a
# contributor may on their own Mac.
#
#   scripts/serve-realm.sh                    # the server alone
#   scripts/serve-realm.sh nullmere-ui        # and the realm, as nullmere-ui
#
# SERVER names the server (http://127.0.0.1:3000) and PACE the realm's pace
# (60, sixty times as written). Installs Rust and SpacetimeDB where either
# is missing.
set -euo pipefail
cd "$(dirname "$0")/.."
SERVER="${SERVER:-http://127.0.0.1:3000}"
DATABASE="${1:-}"
PACE="${PACE:-60}"
mkdir -p build

answers() { curl -s -o /dev/null -X POST "$SERVER/v1/identity"; }

command -v rustup >/dev/null || curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
command -v spacetime >/dev/null || curl -sSf https://install.spacetimedb.com | sh -s -- --yes

if ! answers; then
    echo "Starting SpacetimeDB on this machine..."
    (nohup spacetime start > build/spacetime.log 2>&1 &)
    for _ in $(seq 1 90); do
        answers && break
        sleep 1
    done
    if ! answers; then
        echo "error: SpacetimeDB didn't start at $SERVER" >&2
        tail -n 40 build/spacetime.log >&2 || true
        exit 1
    fi
fi
spacetime login show --token >/dev/null 2>&1 || spacetime login --server-issued-login local
[ -n "$DATABASE" ] || exit 0

echo "Building the realm's module..."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
(cd realm && cargo build --release --target wasm32-unknown-unknown 2>&1 | tail -n 3)
spacetime publish --server "$SERVER" --bin-path realm/target/wasm32-unknown-unknown/release/realm.wasm --yes --delete-data "$DATABASE"
spacetime call --server "$SERVER" "$DATABASE" set_pace "$PACE"
echo "The realm stands at $SERVER/$DATABASE."
