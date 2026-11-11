#!/usr/bin/env python3
"""Which parts of the Database rehearsal a pull request needs, from the paths it changes (to-do 233; brief
docs/briefs/2026-11-11-faster-checks.md, option E; spec docs/specs/2026-11-11-faster-checks.md §1).

Each changed path is matched against the groups below. A path in one or more groups starts those groups' parts. A
path in no group but on the outside list starts nothing: it can't change what the rehearsal checks (documents, the
userscripts, the website's pages, the other checks). A path on no list at all starts every part, so a path nobody
thought of costs time, never protection. The pull request needs the union of its paths' parts.

The parts:
  db         the outputs saved before the changes, the database tests, the figures moved, and the backup and restore
  reference  the descriptions (docs/data.md) and the reference file (database/current/functions.sql)
  types      the planner's types generated from the copy, against app/planner/src/db/types.ts
  planner    the planner built and opened on the copy: sign-in, every screen at 1280 and 380 px, its addresses
  saves      every kind of save, through each screen's own controls
  briefing   the airline briefing for every airline and the map's guide, on the copy
  samples    a test sample made from the copy (which ones: the workflow compares the sample files themselves)
Every part needs the copy: the backup restored, with every migration live doesn't have yet applied.

Usage:
  python3 database/rehearsal_parts.py --base origin/main   # the paths changed since the merge base, from git (a
                                                            # renamed file counts by both its names)
  python3 database/rehearsal_parts.py < paths.txt          # one path per line
Prints the reasons, one line per path, then `parts=<comma list>` (empty when nothing runs) as its last line, which the
workflow appends to $GITHUB_OUTPUT.
"""
import fnmatch, subprocess, sys

ALL = ["db", "reference", "types", "planner", "saves", "briefing", "samples"]
PLANNER = ["types", "planner", "saves"]

# (patterns, parts, why). A pattern ending in /** matches everything under that folder; otherwise fnmatch, where *
# also crosses folders.
GROUPS = [
    (["database/**"], ALL,
     "the database, its tests or the rehearsal itself: everything a database change needs"),
    ([".github/workflows/database-rehearsal.yml", "tests/rehearsal_parts_test.py"], ALL,
     "this check itself"),
    (["tests/fixtures/capture_pages_*.json.gz"], ["db"],
     "a capture page sample the database tests read"),
    (["docs/data.md"], ["reference"],
     "the table guide, checked against the copy"),
    (["app/**", "web/_redirects", "web/assets/**", "package.json", "package-lock.json", ".nvmrc",
      "tests/planner_next_test.py", "tests/plan_card_cabins.mjs"], PLANNER,
     "the planner, its addresses, what it loads or its test on the copy"),
    (["lib/**", "package.json", "package-lock.json", ".nvmrc"], PLANNER + ["briefing"],
     "the planning library, which the planner and the briefing both run"),
    (["tests/harness.py", "tests/local_copy.py", "tests/fixtures/sample_*.json.gz",
      "tests/fixtures/schedule_113.expected.json"], PLANNER + ["briefing"],
     "a helper the planner's, the saves' and the briefing's tests on the copy share, or a sample it reads"),
    (["tests/planner_saves_test.py", "tests/planner_flights.mjs", "tests/fixtures/planner_saves.expected.json",
      "tests/fixtures/load_table_sample.tsv"], PLANNER,
     "the saves' test or what it reads (the saves run after the planner's test, whose module they import)"),
    (["scripts/briefing/**", "scripts/report/analyze.py", "tests/briefing_copy_test.py"], ["briefing"],
     "the airline briefing or its test on the copy"),
    (["tests/fixtures/make_sample.sh", "tests/fixtures/sample.sql", "tests/fixtures/report_sample.sql",
      "tests/fixtures/report_sample.py", "tests/fixtures/capture_sample.sql"], ["samples"],
     "how a test sample is made from the copy"),
    (["tests/fixtures/briefing_sample.sql", "tests/fixtures/briefing_sample.py"], ["samples", "briefing"],
     "how the briefing's sample is made from the copy"),
]

# Paths that start no part (when no group above matches them). The map, docs/architecture.md, is here: its guide runs
# every night on main, and on any pull request that starts the briefing.
OUTSIDE = [
    "docs/**", "*.md", "capture/**", "functions/**", "web/**", "scripts/**", "tests/**", ".claude/**",
    ".github/workflows/checks.yml", ".gitignore", "eslint.config.js",
]


def matches(path, pattern):
    if pattern.endswith("/**"):
        return path.startswith(pattern[:-2])
    return fnmatch.fnmatchcase(path, pattern)


def parts_for(path):
    """The parts one path starts, and why."""
    parts, why = set(), []
    for patterns, ps, reason in GROUPS:
        if any(matches(path, p) for p in patterns):
            parts.update(ps)
            why.append(reason)
    if why:
        return parts, "; ".join(why)
    if any(matches(path, p) for p in OUTSIDE):
        return set(), "can't change what the rehearsal checks"
    return set(ALL), "on no list, so everything runs"


def classify(paths):
    """The parts a pull request changing these paths needs, in the rehearsal's order, and a line per path."""
    need, lines = set(), []
    for path in paths:
        path = path.strip()
        if not path:
            continue
        ps, why = parts_for(path)
        need |= ps
        lines.append(f"{path}: {', '.join(p for p in ALL if p in ps) or 'nothing'} ({why})")
    return [p for p in ALL if p in need], lines


def changed_paths(base):
    out = subprocess.run(["git", "diff", "--name-only", "--no-renames", f"{base}...HEAD"], capture_output=True, text=True, check=True)
    return out.stdout.splitlines()


def main(argv):
    if len(argv) == 3 and argv[1] == "--base":
        paths = changed_paths(argv[2])
    elif len(argv) == 1:
        paths = sys.stdin.read().splitlines()
    else:
        print(__doc__.split("Usage:")[1], file=sys.stderr)
        return 2
    parts, lines = classify(paths)
    for line in lines:
        print(line)
    if not lines:
        print("no changed paths")
    print(f"parts={','.join(parts)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
