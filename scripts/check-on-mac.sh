#!/usr/bin/env bash
# What going live asks of a real Mac, in one command: the frame, GPU and
# other figures CI holds the game to, measured on Apple silicon beside CI's
# (scripts/measure-mac.sh). The figures are kept in perf/mac/ and, when
# they pass, committed, so they are on record. (The rebuilt realm's counsel
# through Apple's on-device model has no check on a real Mac yet:
# docs/GAPS.md.)
# Needs a Mac with Apple silicon, macOS 26 and Xcode 26.
#
#   scripts/check-on-mac.sh             # check, measure, commit
#   scripts/check-on-mac.sh --no-commit # check, measure; leave perf/mac/ to commit
set -euo pipefail
cd "$(dirname "$0")/.."

commit=1
case "${1:-}" in
    "") ;;
    --no-commit) commit=0 ;;
    *) echo "usage: scripts/check-on-mac.sh [--no-commit]" >&2; exit 2 ;;
esac

# What this Mac must be, before the long part.
fail() { echo "error: $*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail "this runs on a Mac"
[ "$(uname -m)" = arm64 ] || fail "this needs a Mac with Apple silicon"
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 26 ] || fail "this needs macOS 26 or later (this is $(sw_vers -productVersion))"
xcodebuild -version >/dev/null 2>&1 || fail "this needs Xcode 26: install it, then run: sudo xcode-select -s /Applications/Xcode.app"
echo "This Mac: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple silicon'), macOS $(sw_vers -productVersion), $(xcodebuild -version | head -n 1)"
echo

figures=failed
echo "== The figures"
if scripts/measure-mac.sh; then figures=passed; fi

echo
echo "== Summary"
printf '  %-28s %s\n' "The figures (Apple silicon)" "$figures"
if [ "$figures" != passed ]; then
    echo
    echo "error: the figures didn't pass; nothing was committed. See build/mac-perf.log." >&2
    exit 1
fi

if [ "$commit" = 1 ]; then
    git add perf/mac
    if git diff --cached --quiet -- perf/mac; then
        echo "Nothing new to commit in perf/mac/."
    else
        git commit -m "Measure the game on $(sysctl -n hw.model)" -- perf/mac
        echo "Committed. Put it on record: git push"
    fi
else
    echo "Kept in perf/mac/; commit and push it to put it on record."
fi
echo
scripts/go-live-status.sh
