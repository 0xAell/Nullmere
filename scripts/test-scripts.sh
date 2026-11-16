#!/usr/bin/env bash
# What the scripts do, not only that they parse: the smoke tests' helper
# puts this Mac's hosted realm and keeper's name back however a test ends;
# check-on-mac.sh measures, says whether the figures passed, commits nothing
# when they didn't, and refuses a Mac that can't run it. Each runs against
# stand-ins, touching nothing real.
#
#   scripts/test-scripts.sh      (run by scripts/check-scripts.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
failures=0
check() {
    if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAILED: $1: got \"$2\", wanted \"$3\"" >&2; failures=$((failures + 1)); fi
}

# smoke-realm.sh: a realm and a name set aside, and put back after a crash.
mkdir -p "$WORK/home/Library/Application Support/Nullmere Online"
REALM="$WORK/home/Library/Application Support/Nullmere Online/hosted-realm.json"
echo '{"the":"keeper'"'"'s realm"}' > "$REALM"
cat > "$WORK/bin/defaults" <<EOF
#!/usr/bin/env bash
# A stand-in for macOS's defaults, keeping one value in a file.
store="$WORK/defaults-\$2-\$3"
case "\$1" in
    read) [ -f "\$store" ] && cat "\$store" || exit 1 ;;
    write) printf '%s' "\$5" > "\$store" ;;
    delete) [ -f "\$store" ] && rm -f "\$store" || exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/defaults"
PATH="$WORK/bin:$PATH" defaults write NullmereLauncher keeper.name.hosted -string "Ama"
set +e
HOME="$WORK/home" PATH="$WORK/bin:$PATH" bash -c "
    set -euo pipefail
    . scripts/smoke-realm.sh
    set_aside_realm NullmereLauncher '$WORK/identity'
    [ ! -e \"\$REALM_FILE\" ] || exit 3
    echo '{\"a\":\"test realm\"}' > \"\$REALM_FILE\"
    defaults write NullmereLauncher keeper.name.hosted -string 'Smoke'
    exit 7
"
crashed=$?
set -e
check "the smoke test ended as it crashed" "$crashed" "7"
check "this Mac's realm is put back" "$(cat "$REALM")" '{"the":"keeper'"'"'s realm"}'
check "the keeper's name is put back" "$(PATH="$WORK/bin:$PATH" defaults read NullmereLauncher keeper.name.hosted)" "Ama"
check "no backup is left behind" "$([ -e "$REALM.smoke-backup" ] && echo left || echo none)" "none"

# check-on-mac.sh: in a stand-in repository, with a stand-in measure and a
# stand-in Mac.
MAC="$WORK/mac"
mkdir -p "$MAC/scripts" "$WORK/macbin"
cp scripts/check-on-mac.sh "$MAC/scripts/"
printf '#!/usr/bin/env bash\necho ran >> "%s/measure-mac.ran"\nexit "${MEASURE_MAC_STATUS:-0}"\n' "$WORK" > "$MAC/scripts/measure-mac.sh"
printf '#!/usr/bin/env bash\necho "status"\n' > "$MAC/scripts/go-live-status.sh"
printf '#!/usr/bin/env bash\ncase "$1" in -s) echo Darwin ;; -m) echo "${MAC_ARCH:-arm64}" ;; *) echo Darwin ;; esac\n' > "$WORK/macbin/uname"
printf '#!/usr/bin/env bash\necho 26.0\n' > "$WORK/macbin/sw_vers"
printf '#!/usr/bin/env bash\nprintf "Xcode 26.0\\nBuild version 17A1\\n"\n' > "$WORK/macbin/xcodebuild"
printf '#!/usr/bin/env bash\ncase "$2" in hw.model) echo Mac16,1 ;; *) echo "Apple M4" ;; esac\n' > "$WORK/macbin/sysctl"
chmod +x "$MAC"/scripts/*.sh "$WORK"/macbin/*
mac_run() {
    rm -f "$WORK"/*.ran
    set +e
    PATH="$WORK/macbin:$PATH" "$@" > "$WORK/mac.out" 2>&1
    echo $? > "$WORK/mac.status"
    set -e
}
measured() { [ -f "$WORK/measure-mac.ran" ] && echo measured || echo "not measured"; }
mac_run env MEASURE_MAC_STATUS=1 "$MAC/scripts/check-on-mac.sh" --no-commit
check "check-on-mac.sh fails when the figures do" "$(cat "$WORK/mac.status")" "1"
check "and says so" "$(grep -cE '^  The figures \(Apple silicon\) *failed$' "$WORK/mac.out")" "1"
check "and commits nothing" "$(grep -c "nothing was committed" "$WORK/mac.out")" "1"
mac_run "$MAC/scripts/check-on-mac.sh" --no-commit
check "check-on-mac.sh passes when the figures do" "$(cat "$WORK/mac.status")" "0"
check "having measured" "$(measured)" "measured"
check "and says so" "$(grep -cE '^  The figures \(Apple silicon\) *passed$' "$WORK/mac.out")" "1"
mac_run env MAC_ARCH=x86_64 "$MAC/scripts/check-on-mac.sh" --no-commit
check "check-on-mac.sh refuses a Mac without Apple silicon" "$(cat "$WORK/mac.status")" "1"
check "before measuring" "$(measured)" "not measured"

# push-ci-shots.sh: two jobs of one run keep their screenshots in its
# folder, another run's at the same moment, against a bare repository
# standing in for GitHub's: none forced away, the branch begun if it isn't.
git init -q --bare "$WORK/shots.git"
mkdir -p "$WORK/mac" "$WORK/phone" "$WORK/next" "$WORK/none"
echo mac > "$WORK/mac/game-world.png"
echo "1.5 Tests.slowest" > "$WORK/mac/test-times.txt"
echo '{"marks.cpu.p50": 1.2}' > "$WORK/mac/perf.json"
echo "PERF-CHECK marks.cpu.p50 within" > "$WORK/mac/perf-check.log"
echo moving > "$WORK/mac/world-battle-motion.gif"
echo world > "$WORK/mac/world.json.gz"
echo phone > "$WORK/phone/companion-house.png"
echo next > "$WORK/next/game-world.png"
shots() { CI_SHOTS_URL="file://$WORK/shots.git" RUN="$1" SHA="$2" scripts/push-ci-shots.sh "$3" >/dev/null 2>"$WORK/shots-$1-$(basename "$3").err"; }
on_branch() { git --git-dir="$WORK/shots.git" show "ci-shots:$1" 2>/dev/null || echo missing; }
shots 746 abc "$WORK/mac"
check "push-ci-shots.sh begins the branch with the run's screenshots" "$(on_branch 746/game-world.png)" "mac"
check "and each test's time beside them" "$(on_branch 746/test-times.txt)" "1.5 Tests.slowest"
check "and the frame times' figures and verdict" "$(on_branch 746/perf.json) $(on_branch 746/perf-check.log)" '{"marks.cpu.p50": 1.2} PERF-CHECK marks.cpu.p50 within'
check "and its moving pictures" "$(on_branch 746/world-battle-motion.gif)" "moving"
check "and the world the preview draws" "$(on_branch 746/world.json.gz)" "world"
check "and the run's commit" "$(on_branch 746/COMMIT)" "abc"
shots 746 abc "$WORK/phone" & phone_job=$!
shots 747 def "$WORK/next" & next_run=$!
wait "$phone_job"; phone_status=$?
wait "$next_run"; next_status=$?
check "two pushes at once both keep theirs" "$phone_status $next_status" "0 0"
check "the other job's screenshot joins the run's folder" "$(on_branch 746/companion-house.png)" "phone"
check "the first job's is still there" "$(on_branch 746/game-world.png)" "mac"
check "the next run's in a folder of its own" "$(on_branch 747/game-world.png)" "next"
check "each a commit of its own, none forced away" "$(git --git-dir="$WORK/shots.git" rev-list --count ci-shots)" "3"
check "a job with no screenshots keeps nothing" "$(CI_SHOTS_URL="file://$WORK/shots.git" RUN=748 SHA=ghi scripts/push-ci-shots.sh "$WORK/none")" "No screenshots to keep."

[ "$failures" = 0 ] && echo "The scripts do what they say."
exit "$failures"
