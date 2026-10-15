"""The market definitions load where the weekly report's are used (spec docs/specs/2026-10-15-small-fixes.md §2).

scripts/report/scan_markets.py and gander monthly's scripts/newsletter/nl_analyze.py run scripts/report/analyze.py's
market block (region(), market(), seats(), market_summaries()). From 13 Oct neither could: they cut the block at the
first "REG={}" and "# ---------- world markets" in the file, which the comment above the block had come to name, so the
cut was the comment and wouldn't run. Both now find the markers at the start of a line, as analyze.py's block stands.

On the saved samples in tests/fixtures/ (the newest report_<date>.json.gz: its world scan's airlines and airports, and
report_airports_oa.csv), with nothing reaching the network:
  1. scan_markets.py: its definitions() loads, and its market summaries for the scan's airlines are exactly what
     analyze.py's own block gives, one row per airline and market with departures a week and city pairs.
  2. nl_analyze.py runs as gander monthly runs it, in a working folder of its inputs with no analyze.py in it (it reads the
     repository's): the scan as airlines3.json and airports3.json, the airport list, and game_stats.json made here from
     the scan (the game's own statistics pages aren't among the samples: its top-20 lists are the scan's 20 largest
     airlines by seats a week). Its markets are analyze.py's market() names, with their seats a week from the scan.

Usage: python3 tests/market_definitions_test.py
"""
import collections, csv, gzip, json, pathlib, re, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIX = ROOT / "tests" / "fixtures"
REPORT = ROOT / "scripts" / "report"
NEWSLETTER = ROOT / "scripts" / "newsletter"
failures = []


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:12]):
        print("      " + str(p), flush=True)
    if not ok:
        failures.append(name)


def airports(path):
    ap = {}
    for r in csv.DictReader(open(path, encoding="utf-8")):
        if r["iata_code"]:
            ap[r["iata_code"]] = (r["iso_country"], r["continent"], float(r["latitude_deg"] or 0),
                                  float(r["longitude_deg"] or 0), r["municipality"] or r["name"])
    return ap


def reference(csv_path):
    """analyze.py's market block, cut at its markers at the start of a line, with the airports it reads."""
    src = (REPORT / "analyze.py").read_text()
    start, end = re.search(r"(?m)^REG=\{\}", src), re.search(r"(?m)^# ---------- world markets", src)
    assert start and end, "analyze.py's market block wasn't found"
    g = {"collections": collections, "ap": airports(csv_path)}
    exec(src[start.start():end.start()], g)
    return g


def main():
    samples = sorted(FIX.glob("report_*.json.gz"))
    step(bool(samples), "the report sample is in tests/fixtures/ (report_<date>.json.gz)")
    if not samples:
        return 1
    scan = json.load(gzip.open(samples[-1]))["scan"]
    csv_path = FIX / "report_airports_oa.csv"
    A, AP = scan["airlines"], scan["airports"]
    flying = [a for a in A if a.get("flights")]
    print(f"sample {samples[-1].name}: scan {scan.get('id')}, {len(A)} airlines ({len(flying)} with schedules), {len(AP)} airports", flush=True)
    ref = reference(csv_path)
    want = ref["market_summaries"](A)

    # 1. scan_markets.py
    sys.path.insert(0, str(REPORT))
    try:
        import scan_markets
        g = scan_markets.definitions(str(csv_path))
        got = g["market_summaries"](A)
        err = None
    except Exception as e:   # the bug: the cut was the comment, which doesn't run
        got, err = None, f"{type(e).__name__}: {e}"
    step(err is None, "scan_markets.py loads analyze.py's market definitions", [err])
    if got is not None:
        step(got == want and len(want) > 0,
             f"scan_markets.py's market summaries are analyze.py's: {len(got)} rows, {len({r['enterprise_id'] for r in got})} airlines, {len({r['market'] for r in got})} markets",
             [f"{len(got)} rows against {len(want)}"] + [r for r in got if r not in want][:5])
        known = sum(r["weekly_departures"] for r in got if r["market"] != "Unknown")
        total = sum(r["weekly_departures"] for r in got)
        step(total > 0 and known / total > 0.9, f"they name a market for {known} of {total} departures a week",
             [f"{total - known} departures a week in Unknown"])

    # 2. nl_analyze.py, as gander monthly runs it
    work = pathlib.Path(tempfile.mkdtemp(prefix="nl-test-"))
    (work / "airlines3.json").write_text(json.dumps(A))
    (work / "airports3.json").write_text(json.dumps(AP))
    (work / "airports_oa.csv").write_text(csv_path.read_text(encoding="utf-8"), encoding="utf-8")
    seats = ref["seats"]
    size = sorted(((sum(len(f[4]) * seats(f[7]) for f in a["flights"] if f[4]), a["name"]) for a in flying), reverse=True)[:20]
    rows = [[str(i + 1), name, f"{n:,} / week"] for i, (n, name) in enumerate(size)]
    (work / "game_stats.json").write_text(json.dumps({"transrecpaxcap": {"rows": [["Overall", "", ""]] + rows},
                                                       "transrecpax": {"rows": [["Overall", "", ""]] + rows}}))
    r = subprocess.run([sys.executable, str(NEWSLETTER / "nl_analyze.py")], cwd=work, capture_output=True, text=True, timeout=300)
    step(r.returncode == 0 and not (work / "analyze.py").exists(),
         "nl_analyze.py runs on the sample in a working folder without analyze.py (it reads the repository's)",
         (r.stderr.strip().splitlines() or ["no error output"])[-6:])
    if r.returncode == 0:
        nl = json.loads((work / "nl.json").read_text())
        names = {ref["market"](f[2], f[3]) for a in flying for f in a["flights"] if f[4] and seats(f[7]) > 0}
        mk = nl.get("markets") or []
        step(bool(mk) and all(m["market"] in names and m["market"] != "Unknown" for m in mk),
             f"its markets are analyze.py's market() names: {len(mk)} markets, led by {mk[0]['market'] if mk else 'none'}",
             [m["market"] for m in mk if m["market"] not in names][:5])
        step(len(nl.get("per") or []) == len([a for a in flying if any(f[4] and seats(f[7]) > 0 for f in a["flights"])]),
             f"it counts every airline of the sample that flies passengers ({len(nl.get('per') or [])})")

    print()
    print("market definitions: " + ("all checks passed" if not failures else f"{len(failures)} check(s) failed"), flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
