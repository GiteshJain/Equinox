"""The planning library's optimiser gives plan.py's saved answer (decision #19; spec docs/specs/2026-10-13-callers.md
§1). scripts/planning/plan.py, the optimiser Claude used until build pull request 4, is retired: the library's command
replaces it. Before it went, plan.py was run unchanged on one fixed input and its best plan was saved with that input;
this check runs the command Claude now uses on the same input and must find exactly that plan.

The input is tests/fixtures/optimiser_kul_2026-10-10.json, a case in the same format as lib/rules/cases/ (laid over
cases/_base.json, as every case is): the test sample's 60 legs at KUL (sample_2026-10-10), shaped as rules_input()
answers, with three destinations to plan. It is game data, so it lives with the other dated samples in tests/fixtures/
(decision #9). Its answer is plan.py's: KCH, PQC, then PEN from 06:45 local, 70 connections at KUL, maintenance 289%
(2.889515240886267, to within 1e-9). Vitest checks the library's own function against the same answer on every run of
npm test; this check runs the built command end to end, as scripts/README.md tells Claude to run it.

Usage: python3 tests/optimiser_saved_answer_test.py   (after npm run build)
"""
import json, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CASES = ROOT / "lib" / "rules" / "cases"
FIXTURE = ROOT / "tests" / "fixtures" / "optimiser_kul_2026-10-10.json"
CLI = ROOT / "lib" / "rules" / "dist" / "cli.js"
# plan.py's answer on this input, as it gave it before it was retired (also kept in the fixture, as the case's answer)
PLAN_PY = {"order": ["KCH", "PQC", "PEN"], "start_local": "06:45", "start_local_min": 405, "connections": 70,
           "maintenance_ratio": 2.889515240886267}
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


def compare(got, want):
    if got is None or want is None:
        return [] if got is want else [f"one found a plan and the other didn't ({got} / {want})"]
    out = [f"{k}: {got.get(k)!r}, expected {want.get(k)!r}" for k in ("order", "start_local_min", "start_local", "connections") if got.get(k) != want.get(k)]
    if abs(got["maintenance_ratio"] - want["maintenance_ratio"]) > 1e-9:
        out.append(f"maintenance_ratio: {got['maintenance_ratio']!r}, expected {want['maintenance_ratio']!r}")
    return out


def main():
    base = json.loads((CASES / "_base.json").read_text())["input"]
    doc = json.loads(FIXTURE.read_text())
    case = doc["cases"][0]
    inp = merged(base, doc.get("input"), case.get("input"))
    ask = case["ask"]
    step(not compare(case["answer"]["best"], PLAN_PY), "the fixture still holds plan.py's saved answer (KCH, PQC, PEN from 06:45, 70 connections, maintenance 289%)",
         compare(case["answer"]["best"], PLAN_PY))
    if not CLI.is_file():
        step(False, "the library's command on the same input", ["lib/rules/dist/cli.js is missing: run npm run build first"])
    else:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(inp, f)
            path = f.name
        args = ["node", str(CLI), "optimise", path, ask["base"], ",".join(ask["destinations"]), "--type", ask["type"], "--start", ask["start"], "--step", str(ask["step"])]
        if ask.get("extra_hubs"):
            args += ["--hubs", ",".join(ask["extra_hubs"])]
        r = subprocess.run(args, capture_output=True, text=True, timeout=300)
        pathlib.Path(path).unlink(missing_ok=True)
        if r.returncode:
            step(False, "the library's command on the same input", [(r.stderr.strip().splitlines() or ["no output"])[-1]])
        else:
            ans = json.loads(r.stdout)
            lib = ans.get("best")
            step(not compare(lib, PLAN_PY), f"the library's command (node lib/rules/dist/cli.js optimise) on {len(inp['flight_legs'])} of the sample's legs at "
                                           f"{ask['base']} gives plan.py's saved plan: {' then '.join((lib or {}).get('order') or ['none'])} from "
                                           f"{(lib or {}).get('start_local', '?')}, {(lib or {}).get('connections', '?')} connections, maintenance "
                                           f"{round(((lib or {}).get('maintenance_ratio') or 0) * 100)}% ({ans.get('considered')} plans tried, "
                                           f"{ans.get('feasible')} feasible)", compare(lib, PLAN_PY))
    print(f"\n{len(failures)} step(s) failed" if failures else "\noptimiser against plan.py's saved answer: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
