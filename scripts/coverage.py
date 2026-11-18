#!/usr/bin/env python3
"""Line coverage of each module, from the JSON `swift test --enable-code-coverage`
leaves (its path is what `swift test --show-codecov-path` prints).

    scripts/coverage.py <codecov.json> [Module=floor ...] [--worst N] [--lines N] [--every Module]
    scripts/coverage.py --self-test

Prints a line per module under Sources/, and fails if any named module's
coverage is under its floor, in percent. With --worst, also lists the N
files with the most lines no test runs, where tests would do most good;
with --lines, the lines themselves of the first N of those; with --every,
every line no test runs in every file of that module, and (COVERFUNCS)
the lines of each of its functions no test called. The lines are
reckoned from each file's segments as llvm-cov reckons its own count, and
a COVERCHECK line says in how many files the two agree.
"""
import json
import sys


def line_counts(segments):
    """Each line llvm-cov counts in a file, with how often it ran, as its
    line coverage reckons it from the file's segments ([line, column,
    count, has count, region entry, gap]): a line counts where a region
    with a count begins on it or one runs across it, and is not where a
    region skipped begins; it ran as often as the most of those."""
    counts = {}
    if not segments:
        return counts
    wrapped = None
    at = 0
    for line in range(segments[0][0], segments[-1][0] + 1):
        starts = []
        while at < len(segments) and segments[at][0] == line:
            starts.append(segments[at])
            at += 1

        def entry(segment):
            gap = len(segment) > 5 and segment[5]
            return segment[3] and len(segment) > 4 and segment[4] and not gap

        entries = [segment for segment in starts if entry(segment)]
        skipped = bool(starts) and not starts[0][3] and len(starts[0]) > 4 and starts[0][4]
        # Any region with a count beginning on it, a gap's too, maps the line.
        counted = any(segment[3] and len(segment) > 4 and segment[4] for segment in starts)
        if (not skipped and ((wrapped is not None and wrapped[3]) or entries)) or counted:
            count = wrapped[2] if wrapped is not None else 0
            for segment in entries:
                count = max(count, segment[2])
            counts[line] = count
        if starts:
            wrapped = starts[-1]
    return counts


def unrun_lines(segments):
    """The lines llvm-cov counts that no test ran."""
    return sorted(line for line, count in line_counts(segments).items() if count == 0)


def never_called(report, module):
    """The functions of a module's files no test called, closures and
    property initialisers among them, each by its file and the lines it
    spans: llvm-cov counts a line of each function apart, so one of these
    on a line that otherwise ran is unrun all the same. A function made
    more than once (a generic one) counts as called where any of it was."""
    called, spans = {}, {}
    for data in report.get("data", []):
        for function in data.get("functions", []):
            regions = function.get("regions", [])
            names = function.get("filenames", [])
            if not regions or not names:
                continue
            first = regions[0]
            path = names[first[5]] if len(first) > 5 and first[5] < len(names) else names[0]
            if "/Sources/" not in path:
                continue
            name = path.split("/Sources/", 1)[1]
            if not name.startswith(module + "/"):
                continue
            key = (name, first[0], first[1])
            called[key] = called.get(key, False) or function.get("count", 0) > 0
            spans[key] = (first[0], first[2])
    found = {}
    for key, ran in called.items():
        if not ran:
            start, end = spans[key]
            found.setdefault(key[0], set()).update(range(start, end + 1))
    return {name: sorted(lines) for name, lines in found.items()}


def ranges(numbers, most=30):
    """1, 2, 3, 7 as "1-3, 7"."""
    spans = []
    for number in numbers:
        if spans and number == spans[-1][1] + 1:
            spans[-1][1] = number
        else:
            spans.append([number, number])
    text = [f"{a}-{b}" if a != b else f"{a}" for a, b in spans[:most]]
    if len(spans) > most:
        text.append(f"and {len(spans) - most} more")
    return ", ".join(text)


def self_test():
    # [line, column, count, has count, region entry, gap], as llvm-cov
    # exports them; each case worked through as llvm-cov's own line
    # coverage reckons it (LineCoverageStats in CoverageMapping.cpp).
    # A region run four times, and a closure in it on line 2 never run:
    # the line still ran, by the region about it.
    closure = [[1, 1, 4, True, True], [2, 10, 0, True, True], [2, 20, 4, True, False], [3, 1, 0, False, False]]
    assert line_counts(closure) == {1: 4, 2: 4, 3: 4}, line_counts(closure)
    # A region never run from line 3 to its brace on line 5, inside one run
    # twice: line 3 ran by the region about it, 4 and 5 did not.
    unrun = [[1, 1, 2, True, True], [3, 1, 0, True, True], [5, 2, 2, True, False], [7, 1, 0, False, False]]
    assert unrun_lines(unrun) == [4, 5], unrun_lines(unrun)
    assert line_counts(unrun)[3] == 2, "a line where a region ending at it began runs as that region did"
    # A region skipped (no count) maps nothing, nor what follows it uncounted.
    skipped = [[1, 1, 2, True, True], [2, 1, 0, False, True], [4, 1, 2, True, False], [5, 1, 0, False, False]]
    assert line_counts(skipped) == {1: 2, 5: 2}, line_counts(skipped)
    # A gap region beginning on a line with its own count maps it, at the
    # count about it.
    gap = [[1, 1, 1, True, True], [2, 1, 0, True, True, True], [3, 1, 0, False, False]]
    assert line_counts(gap) == {1: 1, 2: 1, 3: 0}, line_counts(gap)
    assert line_counts([]) == {}
    # Functions never called: a closure on line 9 alone, one from 12 to 14;
    # one called, and a generic one called in one of its two makings.
    root = "/w/Sources/"
    def function(count, start, end, column=1):
        return {"count": count, "filenames": [root + "Kit/View.swift"], "regions": [[start, column, end, 2, count, 0, 0, 0]]}
    report = {"data": [{"functions": [function(0, 9, 9, 30), function(0, 12, 14), function(3, 20, 25), function(0, 30, 31), function(2, 30, 31),
                                      {"count": 0, "filenames": [root + "Other/A.swift"], "regions": [[1, 1, 2, 2, 0, 0, 0, 0]]}]}]}
    assert never_called(report, "Kit") == {"Kit/View.swift": [9, 12, 13, 14]}, never_called(report, "Kit")
    assert ranges([1, 2, 3, 7, 9, 10]) == "1-3, 7, 9-10"
    assert ranges(list(range(0, 100, 2)), most=2) == "0, 2, and 48 more"
    print("coverage self-test passed")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) == 2 and argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    if len(argv) < 2:
        print(__doc__)
        return 2
    try:
        with open(argv[1]) as handle:
            report = json.load(handle)
    except OSError as error:
        print(f"COVERAGE not measured: {error}. (A failed test run leaves no coverage.)")
        return 1
    floors = {}
    worst = 0
    args = argv[2:]
    if "--worst" in args:
        at = args.index("--worst")
        worst = int(args[at + 1])
        del args[at:at + 2]
    every = None
    if "--every" in args:
        at = args.index("--every")
        every = args[at + 1]
        del args[at:at + 2]
    shown = 0
    if "--lines" in args:
        at = args.index("--lines")
        shown = int(args[at + 1])
        del args[at:at + 2]
    for arg in args:
        name, _, floor = arg.partition("=")
        floors[name] = float(floor)
    covered, counted = {}, {}
    files = []
    for data in report.get("data", []):
        for entry in data.get("files", []):
            path = entry.get("filename", "")
            if "/Sources/" not in path or "/.build/" in path:
                continue
            module = path.split("/Sources/", 1)[1].split("/", 1)[0]
            lines = entry.get("summary", {}).get("lines", {})
            covered[module] = covered.get(module, 0) + lines.get("covered", 0)
            counted[module] = counted.get(module, 0) + lines.get("count", 0)
            files.append((lines.get("count", 0) - lines.get("covered", 0), lines.get("count", 0), path.split("/Sources/", 1)[1],
                          entry.get("segments", [])))
    failed = False
    for module in sorted(counted):
        if counted[module] == 0:
            continue
        percent = 100.0 * covered[module] / counted[module]
        floor = floors.get(module)
        note = ""
        if floor is not None:
            note = f" (floor {floor:g}%)"
            if percent < floor:
                note += " BELOW"
                failed = True
        print(f"COVERAGE {module} {percent:.2f}% of {counted[module]} lines{note}")
    ranked = sorted(files, key=lambda file: (file[0], file[1], file[2]), reverse=True)
    for missed, count, name, _ in ranked[:worst]:
        print(f"COVERFILE {name} {count - missed}/{count} lines, {missed} unrun")
    for missed, _, name, segments in ranked[:shown]:
        if missed and not (every and name.startswith(every + "/")):
            print(f"COVERLINES {name}: {ranges(unrun_lines(segments))}")
    if every:
        for missed, _, name, segments in ranked:
            if missed and name.startswith(every + "/"):
                print(f"COVERLINES {name}: {ranges(unrun_lines(segments), most=10_000)}")
    if every:
        for name, lines in sorted(never_called(report, every).items()):
            print(f"COVERFUNCS {name}: {ranges(lines, most=10_000)}")
    # Whether the lines reckoned here are llvm-cov's own: its count of each
    # file's unrun lines beside the count of those reckoned.
    differ = [(name, missed, len(unrun_lines(segments))) for missed, _, name, segments in ranked if missed != len(unrun_lines(segments))]
    print(f"COVERCHECK the unrun lines reckoned agree with llvm-cov's count in {len(ranked) - len(differ)} of {len(ranked)} files"
          + "".join(f"; {name} {mine} beside {theirs}" for name, theirs, mine in differ[:8]))
    for module in floors:
        if module not in counted:
            print(f"COVERAGE {module}: no lines measured")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
