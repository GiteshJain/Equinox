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

Since 12 Nov (to-do 235, spec §2) the workflow runs the parts side by side, as the jobs in JOBS below, each on its own
restored copy: plan() gives the jobs a run needs and what each does, and gather() reads their results into the one
comment, failing when any job failed or left no result.

Usage:
  python3 database/rehearsal_parts.py --base origin/main   # the paths changed since the merge base, from git (a
                                                            # renamed file counts by both its names)
  python3 database/rehearsal_parts.py < paths.txt          # one path per line
  python3 database/rehearsal_parts.py --all                # every part (the nightly run)
Prints the reasons, one line per path, then `jobs=<JSON>` (the jobs side by side, for the workflow's matrix) and
`parts=<comma list>` (empty when nothing runs) as its last two lines, which the workflow appends to $GITHUB_OUTPUT.
  python3 database/rehearsal_parts.py --gather <folder> '<jobs JSON>' '<parts>' [comment file]
Reads each job's result (<folder>/rehearsal-result-<key>/status and log.txt), prints the comment (or writes it to the
file) and exits 1 if any job failed or left no result.
"""
import fnmatch, json, pathlib, subprocess, sys

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


# The jobs side by side (to-do 235, spec §2), from the times measured on 11 and 12 Nov: each pays about 2 minutes to set
# up and restore its copy, so only the slow parts get their own. The capture replay is about half the database tests
# (4 to 8.3 minutes); briefing_test.sql (1.6 to 3) goes with the briefing; the planner's test and the saves stay one job,
# since the saves import the planner's test module and run after it on the same copy. Each job runs the parts of its
# own that the run needs (none: the job isn't started). With the db part:
#   db_tests  which database tests it runs (rehearse.sh's REHEARSE_DB_TESTS); together they run each test once
#   db_saved  whether it saves the outputs before the changes and writes the figures moved (REHEARSE_DB_SAVED)
# Worked out from the parts a job runs: browser, whether it installs the test browser (only the planner's and the saves'
# tests use one); node, whether it can build the planner and the planning library (they and the briefing need them).
REPLAY = "capture_data_replay_test.sql"
BRIEFING_TEST = "briefing_test.sql"
JOBS = [
    {"key": "planner", "name": "the planner and the saves", "parts": ["types", "planner", "saves"],
     "db_tests": None, "db_saved": False},
    {"key": "replay", "name": "the capture replay", "parts": ["db"],
     "db_tests": f"only:{REPLAY}", "db_saved": False},
    {"key": "briefing", "name": "the briefing, its database test and the map's guide", "parts": ["db", "briefing"],
     "db_tests": f"only:{BRIEFING_TEST}", "db_saved": False},
    {"key": "database", "name": "the other database tests, the descriptions, the reference file and the samples",
     "parts": ["db", "reference", "samples"],
     "db_tests": f"except:{REPLAY},{BRIEFING_TEST}", "db_saved": True},
]


def plan(parts):
    """The jobs a run with these parts needs, in JOBS' order, each with the parts it runs and its settings. The backup
    and restore (with the db part) goes last in the planner's job when that runs, so it dumps the copy after the saves
    as it did when everything ran in one job; otherwise in the database job."""
    run = [j for j in JOBS if any(p in parts for p in j["parts"])]
    backup = None
    if "db" in parts:
        backup = "planner" if any(j["key"] == "planner" for j in run) else "database"
    out = []
    for j in run:
        mine = [p for p in ALL if p in parts and p in j["parts"]]
        out.append({
            "key": j["key"], "name": j["name"], "parts": ",".join(mine),
            "db_tests": j["db_tests"] or "all", "db_saved": "1" if j["db_saved"] else "0",
            "backup": "1" if j["key"] == backup else "0",
            "browser": bool({"planner", "saves"} & set(mine)),
            "node": bool({"planner", "saves", "briefing"} & set(mine)),
        })
    return out


def gather(folder, jobs, parts, limit=60000):
    """The one comment for the pull request from each job's result, and whether every job passed. A job with no result
    (it stopped before writing one, or was never started) counts as failed."""
    folder = pathlib.Path(folder)
    results, ok = [], True
    for j in jobs:
        d = folder / f"rehearsal-result-{j['key']}"
        status = (d / "status").read_text().strip() if (d / "status").exists() else ""
        log = (d / "log.txt").read_text(errors="replace").splitlines() if (d / "log.txt").exists() else []
        log = [l[:300] for l in log if l.strip()]
        if status == "success":
            word, body = "passed", log[-12:]
        elif status:
            ok = False
            fails = [l for l in log if l.startswith("FAIL") or "FAILED" in l][:15]
            word, body = "failed", (fails + ["..."] if fails else []) + log[-40:]
        else:
            ok = False
            word, body = "failed: no result (the job stopped before writing one; see the run's log)", []
        results.append((j, word, body))
    run = parts.split(",") if parts else []
    lines = [f"**Database rehearsal: {'passed' if ok else 'failed'}**", "",
             f"Parts: {', '.join(run) or 'none'}"
             + (f" (not run: {', '.join(p for p in ALL if p not in run)})" if len(run) < len(ALL) else "")
             + f". {len(jobs)} job(s) side by side, each on its own copy.", ""]
    for j, word, body in results:
        lines += [f"**{j['name']}** ({j['parts']}): {word}"]
        if body:
            lines += ["```"] + body + ["```"]
        lines += [""]
    text = "\n".join(lines)
    if len(text) > limit:
        text = text[:limit] + "\n```\n(cut: the rest is in the run's log)\n"
    return text, ok


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
    if len(argv) in (5, 6) and argv[1] == "--gather":
        text, ok = gather(argv[2], json.loads(argv[3]), argv[4])
        if len(argv) == 6:
            pathlib.Path(argv[5]).write_text(text)
        else:
            print(text)
        return 0 if ok else 1
    if len(argv) == 2 and argv[1] == "--all":
        print("the nightly run on main: every part")
        print(f"jobs={json.dumps(plan(ALL), separators=(',', ':'))}")
        print(f"parts={','.join(ALL)}")
        return 0
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
    print(f"jobs={json.dumps(plan(parts), separators=(',', ':'))}")
    print(f"parts={','.join(parts)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
