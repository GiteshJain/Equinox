#!/usr/bin/env python3
"""The Database rehearsal's parts by the paths a pull request changes (to-do 233; spec
docs/specs/2026-11-11-faster-checks.md §1): database/rehearsal_parts.py on hand-made lists of changed paths, and every
file the rehearsal's own scripts read in a group, so a change to one of them can never skip the part that reads it.
Since 12 Nov (to-do 235, spec §2) also the jobs side by side: for every mix of parts, each part needed is run by a job
and none is run that isn't, each database test by exactly one job (as rehearse.sh itself picks them), the backup and the
figures by one job, the browser only where a test opens the planner; the last job fails when any job failed or left no
result; and the workflow is wired that way."""
import itertools, json, pathlib, re, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "database"))
from rehearsal_parts import ALL, JOBS, classify, gather, plan  # noqa: E402

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

# --- the jobs side by side (to-do 235) ---
DB_TESTS = sorted(p.name for p in (ROOT / "database/tests").glob("*.sql"))
# rehearse.sh's own test_wanted(), run in bash, so the test checks the shell's choice and not a copy of it
sh = (ROOT / "database/rehearse.sh").read_text()
fn = re.search(r"^test_wanted\(\) \{.*?^\}", sh, re.S | re.M)
if not fn:
    problems.append("rehearse.sh has no test_wanted() function to pick the database tests")


def shell_picks(spec):
    script = fn.group(0) + f'\ndb_tests="{spec}"\nfor t in "$@"; do test_wanted "$t" && echo "$t"; done; true\n'
    out = subprocess.run(["bash", "-c", script, "picks", *DB_TESTS], capture_output=True, text=True, check=True)
    return out.stdout.split()


if fn:
    checked = 0
    for n in range(1, len(ALL) + 1):
        for mix in itertools.combinations(ALL, n):
            mix = list(mix)
            jobs = plan(mix)
            where = f"parts {','.join(mix)}"
            keys = [j["key"] for j in jobs]
            if len(set(keys)) != len(keys):
                problems.append(f"{where}: a job is started twice: {keys}")
            done = set()
            for j in jobs:
                mine = j["parts"].split(",") if j["parts"] else []
                if not mine:
                    problems.append(f"{where}: the {j['key']} job is started with no part to run")
                if not set(mine) <= set(mix):
                    problems.append(f"{where}: the {j['key']} job runs {mine}, more than the run needs")
                done |= set(mine)
                opens = bool({"planner", "saves"} & set(mine))
                if j["browser"] != opens:
                    problems.append(f"{where}: the {j['key']} job's browser is {j['browser']}, but its parts {mine}")
                if not j["node"] and {"planner", "saves", "briefing"} & set(mine):
                    problems.append(f"{where}: the {j['key']} job builds nothing but runs {mine}")
            if done != set(mix):
                problems.append(f"{where}: no job runs {sorted(set(mix) - done)}")
            if {"planner", "saves"} & set(mix):
                together = [j for j in jobs if {"planner", "saves"} & set(j["parts"].split(","))]
                if len(together) != 1:
                    problems.append(f"{where}: the planner's test and the saves must be in one job (the saves import its module)")
            backups = [j["key"] for j in jobs if j["backup"] == "1"]
            saved = [j["key"] for j in jobs if j["db_saved"] == "1" and "db" in j["parts"].split(",")]
            if "db" in mix:
                runs = {}
                for j in jobs:
                    if "db" in j["parts"].split(","):
                        for name in (j["db_tests"].split(":", 1)[1].split(",") if ":" in j["db_tests"] else []):
                            if name not in DB_TESTS:
                                problems.append(f"{j['key']} job names {name}, which isn't in database/tests/")
                        for t in shell_picks(j["db_tests"]):
                            runs.setdefault(t, []).append(j["key"])
                for t in DB_TESTS:
                    if len(runs.get(t, [])) != 1:
                        problems.append(f"{where}: {t} is run by {runs.get(t, []) or 'no job'}, not by exactly one")
                want_backup = "planner" if "planner" in keys else "database"
                if backups != [want_backup]:
                    problems.append(f"{where}: the backup and restore is in {backups or 'no job'}, not the {want_backup} job")
                if saved != ["database"]:
                    problems.append(f"{where}: the outputs before and the figures moved are in {saved or 'no job'}")
            elif backups:
                problems.append(f"{where}: the backup and restore runs without the db part ({backups})")
            checked += 1
    print(f"ok    the jobs side by side: in every one of {checked} mixes of parts, each part run by a job and no other, "
          f"each of the {len(DB_TESTS)} database tests by exactly one job, the backup, the figures and the browser where they belong")

case_jobs = {"a look-only planner change": (["types", "planner", "saves"], ["planner"]),
             "a database change (every part)": (ALL, ["planner", "replay", "briefing", "database"]),
             "the table guide": (["reference"], ["database"]),
             "a capture page sample": (["db"], ["replay", "briefing", "database"])}
for name, (mix, want) in case_jobs.items():
    got = [j["key"] for j in plan(mix)]
    if got != want:
        problems.append(f"jobs for {name}: wanted {want}, got {got}")
    else:
        print(f"ok    jobs for {name}: {', '.join(got)}")

# rehearse.sh refuses a test list it can't follow before it restores anything, so a renamed test can't leave a job
# running nothing
for spec, says in [("only:no_such_test.sql", "isn't in database/tests/"), ("some", "must be all, only:")]:
    r = subprocess.run(["bash", "database/rehearse.sh", tempfile.gettempdir()], cwd=ROOT, capture_output=True, text=True,
                       env={"PATH": "/usr/bin:/bin", "REHEARSE_DB_TESTS": spec}, timeout=60)
    if r.returncode != 1 or says not in r.stdout:
        problems.append(f"rehearse.sh with REHEARSE_DB_TESTS={spec} should stop with '{says}', got {r.returncode}: {r.stdout[-200:]}")
    else:
        print(f"ok    rehearse.sh refuses REHEARSE_DB_TESTS={spec} before restoring anything")

# the last job: passes only when every job passed; a failed job or one with no result fails the whole check
with tempfile.TemporaryDirectory() as d:
    jobs = plan(ALL)

    def result(key, status, log):
        f = pathlib.Path(d) / f"rehearsal-result-{key}"
        f.mkdir(exist_ok=True)
        (f / "status").write_text(status + "\n")
        (f / "log.txt").write_text(log)

    for j in jobs:
        result(j["key"], "success", f"== job: {j['name']}\nok    something\n")
    text, ok = gather(d, jobs, ",".join(ALL))
    if not ok or "Database rehearsal: passed" not in text or any(j["name"] not in text for j in jobs):
        problems.append("gather: every job passed, but the result isn't a pass naming every job")
    cli = subprocess.run([sys.executable, str(ROOT / "database/rehearsal_parts.py"), "--gather", d, json.dumps(jobs), ",".join(ALL)],
                         capture_output=True, text=True)
    if cli.returncode != 0:
        problems.append("gather: the command fails although every job passed")
    result("replay", "failure", "== job: the capture replay\nFAIL  capture_data_replay_test.sql\n" + "ok    filler\n" * 80)
    text, ok = gather(d, jobs, ",".join(ALL))
    if ok or "Database rehearsal: failed" not in text or "FAIL  capture_data_replay_test.sql" not in text:
        problems.append("gather: a failed job didn't fail the result, or its FAIL line isn't in the comment")
    cli = subprocess.run([sys.executable, str(ROOT / "database/rehearsal_parts.py"), "--gather", d, json.dumps(jobs), ",".join(ALL)],
                         capture_output=True, text=True)
    if cli.returncode != 1:
        problems.append(f"gather: the command exits {cli.returncode} with a failed job, not 1")
    result("replay", "success", "ok\n")
    for f in (pathlib.Path(d) / "rehearsal-result-briefing").iterdir():
        f.unlink()
    text, ok = gather(d, jobs, ",".join(ALL))
    if ok or "no result" not in text:
        problems.append("gather: a job that left no result didn't fail the result")
    result("briefing", "cancelled", "")
    _, ok = gather(d, jobs, ",".join(ALL))
    if ok:
        problems.append("gather: a cancelled job didn't fail the result")
    text, _ = gather(d, plan(["types", "planner", "saves"]), "types,planner,saves")
    if "not run: db, reference, briefing, samples" not in text:
        problems.append("gather: the comment doesn't say which parts weren't run")
    big = "x" * 300 + "\n"
    result("planner", "failure", ("FAIL  " + big) * 200)
    text, _ = gather(d, jobs, ",".join(ALL), limit=5000)
    if len(text) > 5200 or "cut" not in text:
        problems.append("gather: a long comment isn't cut to the limit")
if not any(p.startswith("gather") for p in problems):
    print("ok    the last job: passes when every job passed; a failed, cancelled or silent job fails it; says what wasn't run")

# the workflow runs the jobs as planned, and its last job decides and comments
wf = (ROOT / ".github/workflows/database-rehearsal.yml").read_text()
for needle, why in [
    ("include: ${{ fromJSON(needs.parts.outputs.jobs) }}", "the jobs come from rehearsal_parts.py"),
    ("fail-fast: false", "a red job doesn't stop the others"),
    ("REHEARSE_PARTS: ${{ matrix.parts }}", "each job runs its own parts"),
    ("REHEARSE_DB_TESTS: ${{ matrix.db_tests }}", "each job runs its own database tests"),
    ("REHEARSE_DB_SAVED: ${{ matrix.db_saved }}", "one job saves the outputs before"),
    ("REHEARSE_BACKUP: ${{ matrix.backup }}", "one job runs the backup and restore"),
    ("if: matrix.browser", "only a job whose tests open the planner installs the browser"),
    ("needs: [parts, rehearse]", "the last job waits for every job"),
    ("!cancelled()", "the last job runs when a job failed"),
    ("--gather", "the last job gathers the results"),
    ('if [ "$REHEARSE_RESULT" != success ]; then rc=1; fi', "the last job fails when the jobs did, whatever the files say"),
    ("gh pr comment", "one comment"),
]:
    if needle not in wf:
        problems.append(f"the workflow lacks {needle!r} ({why})")
if wf.count("gh pr comment") != 1:
    problems.append("the workflow should post exactly one comment")
if not any(p.startswith("the workflow") for p in problems):
    print("ok    the workflow: the jobs from the plan, side by side, one last job that fails on any red and posts one comment")

if problems:
    print("FAIL  " + "\nFAIL  ".join(problems))
    sys.exit(1)
print("rehearsal parts: all passed")
