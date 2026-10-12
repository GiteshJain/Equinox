"""The planning library's optimiser against scripts/planning/plan.py (decision #19, spec §4): on one fixed input, both
find the same best plan: the same order, start, connections and maintenance.

The input is lib/rules/cases/optimiser-planpy.json (laid over cases/_base.json, as every case is): the test sample's
legs at KUL (sample_2026-10-10), shaped as rules_input() answers, with three destinations to plan. Its answer is
plan.py's. This check:
  1. runs plan.py itself, unchanged, on that input: plan.py reads three files and one web address when it starts, so
     here they are answered from the input (its state's frequencies, its route research and site_public()'s minimum
     connection times) and nothing is read or fetched for real;
  2. runs the library's command on the same input (node lib/rules/dist/cli.js optimise ..., built by npm run build);
  3. both must equal the case's answer (maintenance to within 1e-9). Vitest checks the library against the same answer
     on every run of npm test.
plan.py's own numbers are its keyword arguments, set from the input: the turn (the type's min_turn_min plus
turn_margin_min, 80 here), its maintenance figures (the type's maint_per_cycle and maint_per_hour, and ground_keep_min
for the time it keeps at the base), the second-daily gap and the start window.

Usage: python3 tests/rules_planpy_test.py   (after npm run build)
"""
import io, json, pathlib, subprocess, sys, tempfile, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CASES = ROOT / "lib" / "rules" / "cases"
PLAN = ROOT / "scripts" / "planning" / "plan.py"
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


def clock(m):
    m = int(round(m)) % 1440
    return f"{m // 60:02d}:{m % 60:02d}"


def plan_py_inputs(inp):
    """What plan.py reads when it starts, made from a rules_input()-shaped document: its state (frequencies in local
    time, night bans), its route research (UTC offsets, positions, routes) and site_public()'s connection times."""
    airports = {a["code"]: a for a in inp["airports"]}
    names = {a["id"]: a.get("planner_name") or f"Airline {a['id']}" for a in inp["airlines"]}

    def off(code):
        a = airports.get(code) or {}
        v = a.get("utc_offset_override", a.get("utc_offset"))
        v = a.get("utc_offset") if v is None else v
        return float(v or 0)

    freqs = []
    for leg in inp["flight_legs"]:   # one frequency per leg, its outbound half only: plan.py reads both halves the same way
        o, d, dep, blk = leg["origin_code"], leg["dest_code"], leg["dep_utc_min"], leg["block_min"]
        freqs.append({"routeKey": f"{names.get(leg['airline_id'])}|{o}|{d}", "days": "".join(map(str, leg["days_utc"])),
                      "depHub": clock(dep + off(o) * 60), "arrDest": clock(dep + blk + off(d) * 60), "depDest": "", "arrHub": ""})
    curfews = {c: f"{a['night_ban_from']}-{a['night_ban_to']}" for c, a in airports.items() if a.get("night_ban_from") and a.get("night_ban_to")}
    state = {"freqs": freqs, "routesAdded": [], "ref": {"curfews": curfews}}
    data = {"utc": {c: off(c) for c in airports},
            "coords": {c: [a.get("lat"), a.get("lon"), "", ""] for c, a in airports.items()},
            "routes": [[names.get(r["airline_id"]), r["hub_code"], r["dest_code"], "", "", r["distance_km"], "", 3] for r in inp["routes"]]}
    mct = {c: a["mct_min"] for c, a in airports.items() if a.get("mct_min") is not None}
    return state, data, mct


def run_plan_py(state, data, mct, ask, type_row, settings):
    """plan.py, unchanged, with its three files and its one web request answered from memory."""
    files = {"/home/claude/real_state.json": json.dumps(state), "/home/claude/data.json": json.dumps(data), "/home/claude/.sb_anon": "local-test-key"}
    fake_open = lambda path, *a, **k: io.StringIO(files[str(path)])   # noqa: E731 (plan.py only reads these three)
    answer = json.dumps({"content": {"mct": mct}}).encode()

    class Response(io.BytesIO):
        pass

    real = urllib.request.urlopen
    urllib.request.urlopen = lambda *a, **k: Response(answer)
    try:
        ns = {"__name__": "plan_py_under_test", "open": fake_open}
        exec(compile(PLAN.read_text(), str(PLAN), "exec"), ns)
    finally:
        urllib.request.urlopen = real
    a, b = ask["start"].split("-")
    hm = lambda t: int(t[:2]) * 60 + int(t[3:5])   # noqa: E731
    best = ns["plan"](ask["base"], ask["destinations"], start_range=(hm(a), hm(b)), step=ask["step"],
                      turn=type_row["min_turn_min"] + settings["turn_margin_min"], mt_per=type_row["maint_per_cycle"],
                      mt_h=type_row["maint_per_hour"], min_turn=type_row["ground_keep_min"], spacing=settings["second_daily_gap_h"] * 60,
                      hubs_extra=tuple(ask.get("extra_hubs") or ()), ac="A321")
    if best is None:
        return None
    (c, maint), order, st, loc, blk, _, gap = best
    return {"order": list(order), "start_local_min": st, "start_local": clock(st), "connections": c, "maintenance_ratio": maint}


def compare(got, want):
    if got is None or want is None:
        return [] if got is want else [f"one found a plan and the other didn't ({got} / {want})"]
    out = [f"{k}: {got.get(k)!r}, expected {want.get(k)!r}" for k in ("order", "start_local_min", "start_local", "connections") if got.get(k) != want.get(k)]
    if abs(got["maintenance_ratio"] - want["maintenance_ratio"]) > 1e-9:
        out.append(f"maintenance_ratio: {got['maintenance_ratio']!r}, expected {want['maintenance_ratio']!r}")
    return out


def main():
    base = json.loads((CASES / "_base.json").read_text())["input"]
    doc = json.loads((CASES / "optimiser-planpy.json").read_text())
    case = doc["cases"][0]
    inp = merged(base, doc.get("input"), case.get("input"))
    want = case["answer"]["best"]
    ask = case["ask"]
    type_row = next(t for t in inp["aircraft_types"] if t["name"] == ask["type"])
    state, data, mct = plan_py_inputs(inp)

    try:
        got = run_plan_py(state, data, mct, ask, type_row, inp["settings"])
        problems = compare(got, want)
    except Exception as e:
        got, problems = None, [f"{type(e).__name__}: {e}"]
    step(not problems, f"plan.py, unchanged, on {len(inp['flight_legs'])} of the sample's legs at {ask['base']}: best plan "
                       f"{' then '.join((got or {}).get('order') or ['none'])} from {(got or {}).get('start_local', '?')}, "
                       f"{(got or {}).get('connections', '?')} connections, maintenance {round(((got or {}).get('maintenance_ratio') or 0) * 100)}%, "
                       "as the case's answer", problems)

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
            lib = json.loads(r.stdout).get("best")
            problems = compare(lib, want) + compare(lib, got) if got else compare(lib, want)
            step(not problems, f"the library's command (node lib/rules/dist/cli.js optimise) on the same input gives the same plan "
                               f"({json.loads(r.stdout).get('considered')} plans tried, {json.loads(r.stdout).get('feasible')} feasible)", problems)
    print(f"\n{len(failures)} step(s) failed" if failures else "\noptimiser against plan.py: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
