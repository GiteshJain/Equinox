"""The planning library's line optimiser gives its saved answer on the Pan Am A350 sample (spec
docs/specs/2026-10-27-long-haul-lines.md §6; manual §4, long haul in 7-day lines). The Scheduling chat's hand-built
sample line of 27 Oct (SFO–LGW, LGW–SEA, SEA–PKX, LGW–LAX, SFO–PVG, PVG–LAX: 12 legs, 17.7 h a day, maintenance 193%,
a counting stop at most every 39.6 h) is the reference; the optimiser's own answer on the same routes was saved when
the command was built, and this check runs the built command on the same input and must find exactly that line.

The input is tests/fixtures/line_a350_2026-10-12.json, a case in the same format as lib/rules/cases/ (laid over
cases/_base.json, as every case is): the 12 Oct test sample's 140 legs at the six airports, the A350-900 with its
14,200 km reach, maintenance_max_gap_h 40. The search is capped by work (chains started plus lines evaluated), never by
seconds, so the answer is the same on every machine. Vitest checks the library's own function against the same answer
on every run of npm test; this check runs the built command end to end, as scripts/README.md tells Claude to run it.

Usage: python3 tests/line_saved_answer_test.py   (after npm run build)
"""
import json, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CASES = ROOT / "lib" / "rules" / "cases"
FIXTURE = ROOT / "tests" / "fixtures" / "line_a350_2026-10-12.json"
CLI = ROOT / "lib" / "rules" / "dist" / "cli.js"
failures = []


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:12]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


def merged(*parts):
    """A case's input, as the Vitest runner lays it: settings and world_rules merge key by key, lists are replaced."""
    out = {}
    for p in parts:
        for k, v in (p or {}).items():
            out[k] = {**out.get(k, {}), **v} if k in ("settings", "world_rules") and isinstance(v, dict) else v
    return out


def compare(got, want, path="best"):
    """Every key the saved answer names must match (numbers to within 1e-9), as the case runner compares."""
    if isinstance(want, (int, float)) and not isinstance(want, bool) and isinstance(got, (int, float)):
        return [] if abs(got - want) <= 1e-9 else [f"{path}: {got!r}, expected {want!r}"]
    if isinstance(want, list):
        if not isinstance(got, list) or len(got) != len(want):
            return [f"{path}: {len(got) if isinstance(got, list) else got!r} item(s), expected {len(want)}"]
        return [m for i, (g, w) in enumerate(zip(got, want)) for m in compare(g, w, f"{path}[{i}]")]
    if isinstance(want, dict):
        if not isinstance(got, dict):
            return [f"{path}: {got!r}, expected an object"]
        return [m for k, w in want.items() for m in compare(got.get(k), w, f"{path}.{k}")]
    return [] if got == want else [f"{path}: {got!r}, expected {want!r}"]


def main():
    base = json.loads((CASES / "_base.json").read_text())["input"]
    doc = json.loads(FIXTURE.read_text())
    case = doc["cases"][0]
    inp = merged(base, doc.get("input"), case.get("input"))
    ask, want = case["ask"], case["answer"]
    legs = want["best"]["legs"]
    step(len(legs) == 12 and want["best"]["score"]["routes"] == 6, "the fixture holds the saved line: 6 routes, 12 legs, each route both ways",
         [f"{len(legs)} legs, {want['best']['score']['routes']} routes"])
    if not CLI.is_file():
        step(False, "the library's command on the same input", ["lib/rules/dist/cli.js is missing: run npm run build first"])
    else:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(inp, f)
            path = f.name
        args = ["node", str(CLI), "optimise-line", path, "--airline", str(ask["airline_id"]), "--type", ask["type"], "--hubs", ",".join(ask["hubs"]),
                "--routes", ",".join(ask["routes"]), "--step", str(ask["step"]), "--work", str(ask["work"]), "--seconds", "0"]
        r = subprocess.run(args, capture_output=True, text=True, timeout=600)
        pathlib.Path(path).unlink(missing_ok=True)
        if r.returncode:
            step(False, "the library's command on the same input", [(r.stderr.strip().splitlines() or ["no output"])[-1]])
        else:
            ans = json.loads(r.stdout)
            b = ans.get("best") or {}
            m = b.get("maintenance") or {}
            problems = compare(ans, want, "answer")
            step(not problems, f"the library's command (node lib/rules/dist/cli.js optimise-line) on {len(inp['flight_legs'])} of the sample's legs gives the saved line: "
                               f"{len(b.get('legs') or [])} legs over {b.get('score', {}).get('routes', '?')} routes from {b.get('start_hub', '?')}, "
                               f"{b.get('block_hours_day', 0):.1f} h a day, maintenance {m.get('pct', '?')}% with a counting stop at most every {m.get('max_gap_h', '?')} h, "
                               f"{b.get('connections_within_target', '?')} of {b.get('connections', '?')} connections within {ans.get('connection_target_h', '?')} h "
                               f"({ans.get('search', {}).get('lines_evaluated', '?')} lines evaluated, {ans.get('search', {}).get('feasible', '?')} feasible; "
                               f"{'search finished' if ans.get('search', {}).get('finished') else 'the work budget ran out, the best found'})", problems)
            # the hand-built sample's figures are sanity targets, not exact answers (spec §1)
            step(b.get("block_hours_day", 0) >= 16 and m.get("pct", 0) >= 100 and (m.get("max_gap_h") or 999) <= 40,
                 "the line is in the hand-built sample's range: at least 16 h a day, maintenance at or above 100%, no stretch over 40 h",
                 [f"{b.get('block_hours_day')} h a day, {m.get('pct')}%, {m.get('max_gap_h')} h"])
    print(f"\n{len(failures)} step(s) failed" if failures else "\nline optimiser against its saved answer: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
