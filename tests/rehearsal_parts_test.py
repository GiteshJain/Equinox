#!/usr/bin/env python3
"""The Database rehearsal's parts by the paths a pull request changes (to-do 233; spec
docs/specs/2026-11-11-faster-checks.md §1): database/rehearsal_parts.py on hand-made lists of changed paths, and every
file the rehearsal's own scripts read in a group, so a change to one of them can never skip the part that reads it."""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "database"))
from rehearsal_parts import ALL, classify  # noqa: E402

PLANNER_ONLY = ["types", "planner", "saves"]
problems = []


def case(name, paths, want):
    got, lines = classify(paths)
    if got != want:
        problems.append(f"{name}: wanted {want or 'nothing'}, got {got or 'nothing'}\n      " + "\n      ".join(lines))
    else:
        print(f"ok    {name}: {', '.join(got) or 'nothing'}")


case("a look-only planner change (the stylesheet and a screen)",
     ["app/planner/src/ui/styles.css", "app/planner/src/screens/home/Home.tsx"], PLANNER_ONLY)
case("a new migration", ["database/migrations/20261112000000_x.sql"], ALL)
case("a database test only", ["database/tests/jobs_test.sql"], ALL)
case("the rehearsal's script", ["database/rehearse.sh"], ALL)
case("the database's reference file", ["database/current/functions.sql"], ALL)
case("documents only", ["docs/briefs/2026-11-11-faster-checks.md", "docs/operating-manual.md", "README.md",
                         "docs/map/planner.md", "tests/README.md"], [])
case("the map alone (its guide runs every night on main)", ["docs/architecture.md"], [])
case("a path on no list", ["somewhere/new_file.txt"], ALL)
case("a new file at the top", ["tsconfig.json"], ALL)
case("a mix: a planner screen and the briefing",
     ["app/planner/src/screens/today/Today.tsx", "scripts/briefing/brief.py"], PLANNER_ONLY + ["briefing"])
case("a mix: documents, a userscript and a planner screen",
     ["docs/architecture.md", "capture/capture_all.user.js", "app/planner/src/App.tsx"], PLANNER_ONLY)
case("a mix: a planner screen and a migration", ["app/planner/src/App.tsx", "database/migrations/x.sql"], ALL)
case("the planning library", ["lib/rules/src/card.ts"], PLANNER_ONLY + ["briefing"])
case("the package lock", ["package-lock.json"], PLANNER_ONLY + ["briefing"])
case("the planner's addresses", ["web/_redirects"], PLANNER_ONLY)
case("what the planner loads from the website", ["web/assets/logos.js"], PLANNER_ONLY)
case("a website page", ["web/index.html"], [])
case("the userscripts and the other checks", ["capture/capture_all.user.js", "tests/capture_market_test.mjs",
                                              "tests/run_all.sh", ".github/workflows/checks.yml"], [])
case("the saves' recorded answers (the saves always run after the planner's test)",
     ["tests/fixtures/planner_saves.expected.json"], PLANNER_ONLY)
case("the planner's test on the copy (the saves' test imports it)", ["tests/planner_next_test.py"], PLANNER_ONLY)
case("the table guide", ["docs/data.md"], ["reference"])
case("a capture page sample the database tests read", ["tests/fixtures/capture_pages_2026-11-09.json.gz"], ["db"])
case("how the test sample is made", ["tests/fixtures/sample.sql"], ["samples"])
case("how the briefing's sample is made", ["tests/fixtures/briefing_sample.py"], ["briefing", "samples"])
case("the briefing's script", ["scripts/report/analyze.py"], ["briefing"])
case("this check's workflow", [".github/workflows/database-rehearsal.yml"], ALL)
case("this test", ["tests/rehearsal_parts_test.py"], ALL)
case("no paths", [], [])

# Every file under tests/ that the rehearsal's scripts name must start at least one part, so that changing it runs
# whatever reads it. Names are found as `tests/<file>`, `"tests" / "<file>"` and `FIX / "<file>"`.
readers = ["database/rehearse.sh", "tests/planner_next_test.py", "tests/planner_saves_test.py",
           "tests/briefing_copy_test.py", "tests/local_copy.py", "tests/harness.py"]
named = set()
for r in readers:
    text = (ROOT / r).read_text()
    named |= {"tests/" + m.rstrip(".") for m in re.findall(r"(?<![/\w])tests/([A-Za-z0-9_./*-]+)", text)}
    named |= {"tests/" + m for m in re.findall(r'"tests" / "([^"]+)"', text)}
    named |= {"tests/fixtures/" + m for m in re.findall(r'FIX / "([^"]+)"', text)}
    named |= {"tests/fixtures/" + m for m in re.findall(r'FIX\.glob\("([^"]+)"\)', text)}
# what they name that isn't a file the rehearsal reads: documents, other checks, folders, and old tests in comments
skip = {"tests/README.md", "tests/run_all.sh", "tests/fixtures"}
for f in sorted(named - skip):
    if not (ROOT / f).exists() and "*" not in f:
        continue   # named in a comment only (an old test, gone)
    got, _ = classify([f])
    if not got:
        problems.append(f"{f} is read by the rehearsal but starts no part: add it to a group in database/rehearsal_parts.py")
print(f"ok    every file the rehearsal's scripts read starts a part ({len(named - skip)} names checked)"
      if not any("starts no part" in p for p in problems) else "")

if problems:
    print("FAIL  " + "\nFAIL  ".join(problems))
    sys.exit(1)
print("rehearsal parts: all passed")
