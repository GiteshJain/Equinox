"""The weekly report, end to end on a small dated sample (decision #19; spec docs/specs/2026-10-13-callers.md §2).

scripts/report/analyze.py, charts.py and build.py run, unchanged, in a working folder made from the newest
tests/fixtures/report_<date>.json.gz: the captured figures and the planning library's input as export_for_report() gave
them on the rehearsal's copy of a nightly backup, cut to what the report needs, with a small piece of the world scan
(tests/fixtures/report_sample.py makes it; tests/README.md, "The report sample"), OurAirports' public airport list cut to
the sample's airports (fixtures/report_airports_oa.csv) and scripts/report/notes.example.json as the week's notes. The
folder also holds the old planner document as an earlier pull.py left it (planner.json, from the 10 Oct test sample), so
a report that still read its money there would show other figures and fail. Nothing reaches the network: analyze.py
runs with --no-send and a home folder with no keys in it. Checks:
  - the PDF is made, named for the figures' ISO week;
  - its text has no "surplus" (manual §3: never use the surplus figure);
  - in the finance table, each airline's cash, profit a day, lowest point in 14 days and next order equal the sample's
    figures (cash_forecast() and airline_cards(), formatted as the report prints money: millions to two decimals);
  - the airlines listed are exactly the sample's (rules_input()'s airlines, ours and active, in display order): the
    cover's list, and the finance table's rows, with no other airline and no group row;
  - each airline against its three biggest competitors (manual §7; spec docs/specs/2026-10-21-report-three-competitors.md
    §2): for each airline its part, its own row first with the figures' numbers, its three rivals in order, and the one
    line of words; "No world scan to compare yet." where the figures have none. A sample made before 22 Oct has no
    competitors in its figures: the test's copy gets a small synthetic block (synthetic_competitors(), never the dated
    fixture), one airline left without it, covering growth, a fall, held steady, a rival new since the week-before scan,
    no rival on its pairs and no earlier scan.
  - since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §5) each airline's rival fares on its contested pairs:
    each way our economy fare against the cheapest rival's and our passenger share this week against last, from the latest
    market read; "not read" for a direction the read missed; a line saying there's no read yet before the first, and that
    there's no contested pair; nothing for an airline whose figures predate them. The sample predates the market pages, so
    the test's copy gets a small synthetic block (synthetic_contested(), never the dated fixture): with a read, before the
    first read and with no contested pair, the other airlines without the key.
The PDF is kept in $REPORT_TEST_OUT when it is set (the checks keep it as the run's weekly-report artifact).

Usage: python3 tests/report_test.py   (after npm run build, for the planning library's command)
"""
import datetime, gzip, json, os, pathlib, re, shutil, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIX = ROOT / "tests" / "fixtures"
REPORT = ROOT / "scripts" / "report"
CLI = ROOT / "lib" / "rules" / "dist" / "cli.js"
failures = []


def check(ok, name, detail=""):
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok or not detail else "\n      " + str(detail)[:1500]), flush=True)
    if not ok:
        failures.append(name)


def money(x):
    return "—" if x is None else f"{x:.2f}M"


def signed(x):
    return "—" if x is None else f"{x:+.2f}M"


def day(ts):
    if not ts:
        return "—"
    m = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    return f"{m.day} {m:%b}"


def next_order(no):
    w = (no or {}).get("when")
    return {"now": lambda: "Now: " + ", ".join(no.get("types") or []),
            "later": lambda: f"{no.get('type')} from {day(no.get('safe_from'))}",
            "not within 14 days": lambda: "Not within 14 days",
            "needs": lambda: "Needs " + (no.get("missing") or "a capture")}.get(w, lambda: "—")()


def flat(s):
    return re.sub(r"\s+", " ", s).strip()


def synthetic_competitors(F):
    """A small made-up block of competition()'s competitors, self and scans for a sample made before they were in the
    figures (22 Oct): the test's copy only. Each airline gets one case in turn, the last none at all; answers the words
    the report must print for each, by airline id."""
    as_of = datetime.datetime.fromisoformat(F["as_of"].replace("Z", "+00:00"))
    latest = (as_of - datetime.timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    before_m = as_of - datetime.timedelta(days=7, hours=3)
    before = before_m.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    scans = {"latest": {"id": 902, "taken_at": latest}, "week_before": {"id": 901, "taken_at": before}, "previous": {"id": 901, "taken_at": before}}

    def one(rank, name, on_pairs, pairs, weekly, airports, weekly_before, fleet=None):
        change = None if weekly_before is None else weekly - weekly_before
        pct = None if not weekly_before else round(100.0 * change / weekly_before, 1)
        return {"rank": rank, "airline_id": 9000 + rank, "name": name, "on_pairs": on_pairs, "pairs": pairs, "weekly": weekly,
                "airports": airports, "weekly_before": weekly_before, "change": change, "change_pct": pct, "fleet": fleet}

    def fl(overall, on_order, change):   # a rival's fleet as competition() gives it (since 23 Oct)
        return {"overall": overall, "on_order": on_order, "avg_age_years": 2.1, "types_count": 1,
                "types": [{"type": "Test Type", "overall": overall, "on_order": on_order, "avg_age_years": 2.1}],
                "overall_before": None if change is None else overall, "on_order_before": None if change is None else on_order - change,
                "overall_change": None if change is None else 0, "on_order_change": change}

    def me(on_pairs, pairs, flown, weekly, airports, weekly_before):
        x = one(0, "", on_pairs, pairs, weekly, airports, weekly_before)
        return {k: v for k, v in x.items() if k not in ("rank", "airline_id", "name")} | {"pairs_flown": flown}

    rivals = [one(1, "Test Rival Atlas", 1420, 12, 1420, 160, 1000, fl(99, 44, 6)), one(2, "Test Rival Borealis", 300, 4, 2600, 95, 2700, fl(40, 0, 0)),
              one(3, "Test Rival Cirrus", 120, 2, 400, 30, 400)]
    # each one's connecting departures on the airline's pairs (since 23 Oct), beside direct and never added to it
    for r, (n, pairs, via) in zip(rivals, [(14, 3, [{"via": "KEF", "weekly": 10}, {"via": "OSL", "weekly": 4}]), (0, 0, []), (5, 1, [{"via": "DUB", "weekly": 5}])]):
        r.update(connecting_weekly=n, connecting_pairs=pairs, connecting_via=via)
    when = f"{before_m.day} {before_m:%b}"
    cases = [  # (self, competitors, scans, the words for an airline named N)
        (me(236, 18, 20, 236, 21, 200), rivals, scans, lambda n: f"{n} grew 18% this week; Test Rival Atlas, its biggest rival on its pairs, grew 42%."),
        (me(95, 9, 9, 95, 10, 100), [one(1, "Test Rival Nova", 70, 3, 300, 40, None)] + rivals[1:], scans,
         lambda n: f"{n} shrank 5% this week; Test Rival Nova, its biggest rival on its pairs, wasn't in the scan of {when}."),
        (me(50, 4, 4, 50, 5, 40), [], scans, lambda n: f"{n} grew 25% this week; no outside airline flies its city pairs."),
        (me(80, 6, 6, 80, 7, None), [dict(r, weekly_before=None, change=None, change_pct=None) for r in rivals],
         dict(scans, week_before=None, previous=None), lambda n: f"{n}: no earlier scan to compare its growth; Test Rival Atlas is its biggest rival on its pairs."),
        (me(120, 10, 11, 140, 12, 140), rivals[1:], scans,
         lambda n: f"{n} held steady this week; Test Rival Borealis, its biggest rival on its pairs, shrank 4%."),
    ]
    want = {}
    airlines = F.get("airlines") or []
    for i, a in enumerate(airlines[:-1] if len(airlines) > 1 else airlines):
        self_, comps, sc, words = cases[i % len(cases)]
        a.update(competitors=[dict(c) for c in comps], self=dict(self_, airline_id=a["airline_id"], code=a.get("code"), name=a.get("name")), scans=sc)
        want[a["airline_id"]] = words
    # the world's flagged order books (since 23 Oct), the same in every airline's figures, marked for each: Atlas meets the
    # first airline, the starting airline none
    for i, a in enumerate(airlines):
        a["order_flags"] = [
            {"airline_id": 9001, "name": "Test Rival Atlas", "kind": "orders", "fleet": 99, "on_order": 44, "share": 44.4, "weekly": 1420,
             "on_order_change": 6, "fleet_change": 0, "on_pairs": i == 0, "at_bases": False, "meets": i == 0, "words": ""},
            {"airline_id": 9009, "name": "Test Starter Air", "kind": "starting", "fleet": 0, "on_order": 12, "share": None, "weekly": 0,
             "on_order_change": None, "fleet_change": None, "on_pairs": False, "at_bases": False, "meets": False, "words": ""}]
    return want


def synthetic_contested(F):
    """A small made-up block of competition()'s contested and market_run (since 30 Oct) for a sample made before them: the
    test's copy only. The first airline has a read and two contested pairs (one read both ways, one not read); the second
    contested pairs but no read yet; the third a read and no contested pair; the rest none (as older figures). Answers what
    each airline's part must say, by airline id."""
    airlines = F.get("airlines") or []
    run = {"id": 7, "started_at": "2026-10-30T21:00:00.000Z", "finished_at": "2026-10-30T21:12:00.000Z"}
    way = lambda f, t, ours, rival, eco, vs, share, before: {"direction": "out", "from": f, "to": t, "read_at": "2026-10-30T21:05:00.000Z", "week": "2026-44",   # noqa: E731
                                                          "ours_eco": ours, "cheapest_rival": {"airline_id": 9101, "code": "TR", "name": rival, "eco": eco},
                                                          "vs_cheapest_pct": vs, "share": share, "share_before": before, "change": None}
    want = {}
    if len(airlines) > 0:
        airlines[0].update(market_run=run, contested=[
            {"pair": "TQA-TQB", "route_id": 1, "hub": "TQA", "dest": "TQB", "ours": 14, "rival_id": 9101, "rival": "Test Rival Atlas", "rival_weekly": 21,
             "market": {"out": way("TQA", "TQB", 102, "Test Rival Atlas", 115, -11.3, 30, 32), "back": way("TQB", "TQA", 125, "Test Rival Borealis", 120, 4.2, 45.5, None)}},
            {"pair": "TQA-TQC", "route_id": 2, "hub": "TQA", "dest": "TQC", "ours": 7, "rival_id": 9102, "rival": "Test Rival Borealis", "rival_weekly": 7,
             "market": None}])
        want[airlines[0]["airline_id"]] = ["rival fares on its contested pairs", "TQA to TQB 102 AS$ Test Rival Atlas 115 AS$ -11% 30.0% (32.0%)",
                                           "TQB to TQA 125 AS$ Test Rival Borealis 120 AS$ +4% 45.5% (—)", "TQA to TQC not read — — —",
                                           "TQC to TQA not read — — —", "From the game's Market Analysis pages read on 30 Oct"]
    if len(airlines) > 1:
        airlines[1].update(market_run=None, contested=[{"pair": "TQA-TQD", "route_id": 3, "hub": "TQA", "dest": "TQD", "ours": 7, "rival_id": 9101,
                                                        "rival": "Test Rival Atlas", "rival_weekly": 14, "market": None}])
        want[airlines[1]["airline_id"]] = ["rival fares on its contested pairs", "No market read yet: the capture reads the market pages once a week."]
    if len(airlines) > 2:
        airlines[2].update(market_run=run, contested=[])
        want[airlines[2]["airline_id"]] = ["rival fares on its contested pairs", "No contested pair: no rival has as many departures a week as ours"]
    return want


def run(step, args, cwd, env):
    r = subprocess.run([sys.executable, *args], cwd=cwd, env=env, capture_output=True, text=True, timeout=600)
    check(r.returncode == 0, f"{step} runs", (r.stderr or r.stdout).strip()[-1200:])
    return r.returncode == 0


def main():
    samples = sorted(FIX.glob("report_*.json.gz"))
    if not samples:
        check(False, "the report sample is in tests/fixtures/ (report_<date>.json.gz)")
        sys.exit(1)
    S = json.load(gzip.open(samples[-1]))
    F, R, scan = S["figures"], S["rules"], S["scan"]
    # competition()'s competitors are in the figures since 22 Oct; an older sample gets a synthetic block in this copy
    synthetic = not any("competitors" in a for a in F.get("airlines") or [])
    words = synthetic_competitors(F) if synthetic else {}
    # competition()'s contested pairs with the market pages' fares are in the figures since 30 Oct; an older sample gets a
    # synthetic block in this copy, with and without a read
    synthetic_market = not any("contested" in a for a in F.get("airlines") or [])
    market_words = synthetic_contested(F) if synthetic_market else {}
    ours = sorted((a for a in R["airlines"] if a.get("ours") and a.get("active") is not False),
                  key=lambda a: (a.get("position") is None, a.get("position") or 0, a["id"]))
    names = [a.get("public_name") or a.get("planner_name") or a.get("game_name") for a in ours]
    others = [a.get("public_name") or a.get("planner_name") or a.get("game_name") for a in R["airlines"] if a not in ours]
    print(f"sample {samples[-1].name}: figures as of {F['as_of']}, {len(names)} airlines ({', '.join(names)}), scan {scan.get('id')}", flush=True)
    if not CLI.is_file():
        check(False, "the planning library's command is built (lib/rules/dist/cli.js)", "run npm ci && npm run build first")
        sys.exit(1)

    work = pathlib.Path(tempfile.mkdtemp(prefix="report-test-"))
    try:
        files = {"figures.json": F, "rules.json": R, "airlines.json": scan["airlines"], "airports.json": scan["airports"],
                 "scan.json": {"id": scan.get("id"), "taken_at": scan.get("taken_at")}, "site_airlines.json": S.get("site_airlines") or []}
        for name, doc in files.items():
            (work / name).write_text(json.dumps(doc))
        shutil.copy(FIX / "report_airports_oa.csv", work / "airports_oa.csv")
        shutil.copy(REPORT / "notes.example.json", work / "notes.json")
        old = json.load(gzip.open(FIX / "sample_2026-10-10.json.gz"))   # the old planner document, as pull.py fetched it before
        (work / "planner.json").write_text(json.dumps({"state": old["planner_state"], "loads": {}}))
        home = work / "home"; home.mkdir()   # no ~/.sb_anon or ~/.ingest_secret here: nothing can reach the database
        env = dict(os.environ, HOME=str(home), EQUINOX_RULES_CLI=str(CLI), MPLCONFIGDIR=str(work / "mpl"))
        ok = (run("analyze.py (--no-send)", [str(REPORT / "analyze.py"), "--no-send"], work, env)
              and run("charts.py", [str(REPORT / "charts.py")], work, env)
              and run("build.py", [str(REPORT / "build.py"), "--notes", "notes.json", "--out", str(work / "out")], work, env))
        if not ok:
            sys.exit(1)
        d = datetime.datetime.fromisoformat(F["as_of"].replace("Z", "+00:00")).date().isocalendar()
        pdf = work / "out" / f"Equinox_Weekly_Briefing_{d.year}-W{d.week:02d}.pdf"
        check(pdf.is_file() and pdf.stat().st_size > 20000, f"the PDF is made: {pdf.name}", f"out holds {[p.name for p in (work / 'out').iterdir()]}")
        if not pdf.is_file():
            sys.exit(1)
        if os.environ.get("REPORT_TEST_OUT"):
            os.makedirs(os.environ["REPORT_TEST_OUT"], exist_ok=True)
            shutil.copy(pdf, os.environ["REPORT_TEST_OUT"])
        from pypdf import PdfReader
        pages = [flat(p.extract_text() or "") for p in PdfReader(str(pdf)).pages]
        text = " ".join(pages)
        print(f"      {len(pages)} pages, {len(text):,} characters of text", flush=True)
        check("surplus" not in text.lower(), "its text has no \"surplus\"", [m.group(0) for m in re.finditer(r".{40}surplus.{40}", text, re.I)][:3])
        check(" · ".join(names) in pages[0], "the cover lists exactly the sample's airlines, in order", pages[0][:400])

        # the finance table: from its header to the note under it
        i = text.find("Lowest in 14 days When Next order"); j = text.find("Money in millions of AS$", i)
        check(i >= 0 and j > i, "the finance table is there (Airline, Cash, Profit a day, Flight profit a day, Lowest in 14 days, When, Next order)")
        if i < 0 or j < 0:
            sys.exit(1)
        table = text[i + len("Lowest in 14 days When Next order"):j]
        fa = {a["airline_id"]: a for a in F["airlines"]}
        cards = {c["airline_id"]: c for c in F["airline_cards"]["airlines"]}
        pos, rows = 0, []
        for a, name in zip(ours, names):
            k = table.find(name, pos)
            rows.append((a, name, k))
            pos = k + 1 if k >= 0 else pos
        found = [name for _, name, k in rows if k >= 0]
        check(found == names and table.strip().startswith(names[0]) if names else not table.strip(),
              f"the finance table's rows are the sample's airlines, in order ({len(names)})", f"found {found} in: {table[:600]}")
        stray = [n for n in others + ["Group", "Total", "All airlines"] if n and re.search(r"\b" + re.escape(n) + r"\b", table)]
        check(not stray, "the finance table has no other airline and no group row", f"also lists {stray}")
        for n, (a, name, k) in enumerate(rows):
            if k < 0:
                continue
            seg = table[k:rows[n + 1][2] if n + 1 < len(rows) and rows[n + 1][2] > k else len(table)]
            fc = (fa.get(a["id"]) or {}).get("cash_forecast") or {}
            card = cards.get(a["id"]) or {}
            want = {"cash": money(fc.get("cash")), "profit a day": signed(card.get("profit_day")),
                    "lowest point": money((fc.get("lowest") or {}).get("balance")), "next order": next_order(card.get("next_order") or fc.get("next_order"))}
            # the row's cells in order: cash, profit a day, flight profit a day, lowest point, when ("11 Oct" or "—"), next order
            t = seg[len(name):].split()
            when = 1 if t[4:5] == ["—"] else 2
            got = {"cash": " ".join(t[0:1]), "profit a day": " ".join(t[1:2]), "lowest point": " ".join(t[3:4]), "next order": " ".join(t[4 + when:])}
            bad = [f"{k}: the PDF shows {got[k]!r}, the sample's figures say {want[k]!r}" for k in want if got[k] != want[k]]
            check(not bad, f"{name}: cash {want['cash']}, profit a day {want['profit a day']}, lowest point {want['lowest point']}, "
                           f"next order {want['next order']!r}, as the sample's figures", "; ".join(bad))

        # each airline against its three biggest competitors: its part, its row first, its rivals in order, the words
        k0 = text.find("COMPETITION — AGAINST OUR RIVALS")
        k1 = text.find("COMPETITION — MOVES THIS WEEK", k0)
        check(k0 >= 0 and k1 > k0, "the section \"Each airline against its three biggest competitors\" is there, before the week's moves")
        part_text = text[k0:k1] if k0 >= 0 and k1 > k0 else ""
        heads = [(a, name, part_text.find(f"{name}: against its three biggest competitors")) for a, name in zip(ours, names)]
        check([h for _, _, h in heads] == sorted(h for _, _, h in heads) and all(h >= 0 for _, _, h in heads),
              f"the section has a part for each airline, in order ({len(names)})", [(n, h) for _, n, h in heads])

        def cell(x):
            if x.get("change") is None:
                return "—"
            return f"{x['change']:+,}" + (f" ({x['change_pct']:+.1f}%)" if x.get("change_pct") is not None else "")

        def n0(v):
            return "—" if v is None else f"{v:,.0f}"

        for n, (a, name, h) in enumerate(heads):
            if h < 0:
                continue
            seg = part_text[h:next((h2 for _, _, h2 in heads[n + 1:] if h2 > h), len(part_text))]
            f = fa.get(a["id"]) or {}
            if "competitors" not in f or not (f.get("scans") or {}).get("latest"):
                check("No world scan to compare yet." in seg, f"{name}: \"No world scan to compare yet.\"", seg[:300])
                continue
            me = f["self"]
            fleets = any("fleet" in c for c in f["competitors"])   # since 23 Oct each rival's fleet, a column of its own
            conns = any("connecting_weekly" in c for c in f["competitors"])   # since 23 Oct each rival's connecting departures, beside direct

            def conn(c):
                n = c.get("connecting_weekly")
                if n is None:
                    return " —"
                via = ", ".join(v["via"] for v in c.get("connecting_via") or [] if v.get("via"))
                return f" {n:,}" + (f" via {via}" if n and via else "")

            def fleet(c):
                x = c.get("fleet")
                if not x or x.get("overall") is None:
                    return " not read"
                ch = x.get("on_order_change")
                return f" {x['overall']:,} ({x.get('on_order') or 0:,} on order)" + (f" {ch:+,} on order" if ch else "")
            row = (f"{name} {n0(me['on_pairs'])}" + (" —" if conns else "")
                   + f" {n0(me['pairs'])} of {n0(me['pairs_flown'])} {n0(me['weekly'])} {n0(me['airports'])} {cell(me)}" + (" —" if fleets else ""))
            rows = [row] + [f"{c['name']} {n0(c['on_pairs'])}" + (conn(c) if conns else "") + f" {n0(c['pairs'])} {n0(c['weekly'])} {n0(c['airports'])} "
                            + (cell(c) if c.get("weekly_before") is not None or not f["scans"].get("week_before") else "not in that scan")
                            + (fleet(c) if fleets else "")
                            for c in f["competitors"]]
            at = [seg.find(r) for r in rows]
            check(all(i >= 0 for i in at) and at == sorted(at),
                  f"{name}: its own row first, then its {len(rows) - 1} competitor(s), with the figures' numbers", f"want {rows} in: {seg[:700]}")
            if a["id"] in words:
                check(words[a["id"]](name) in seg, f"{name}: the line {words[a['id']](name)!r}", seg[-400:])
            if conns:
                check("Connecting a week (not added)" in seg, f"{name}: the connecting column is headed as never added to direct", seg[:300])
        # since 30 Oct: each airline's rival fares on its contested pairs, with and without a market read
        for a, name, h in heads:
            if h < 0:
                continue
            f = fa.get(a["id"]) or {}
            nxt = min([h2 for _, _, h2 in heads if h2 > h] + [len(part_text)])
            seg = part_text[h:nxt]
            if a["id"] in market_words:
                for w in market_words[a["id"]]:
                    check(w in seg, f"{name}: rival fares on its contested pairs show {w!r}", seg[-900:])
            elif "contested" not in f:
                check("rival fares on its contested pairs" not in seg, f"{name}: no rival fares part from figures that predate them", seg[-300:])
            else:   # a real sample: each contested pair's route is listed
                for c in f["contested"] if f.get("market_run") else []:
                    check(f"{c['hub']}–{c['dest']}" in seg, f"{name}: its contested pair {c['hub']}–{c['dest']} is listed", seg[-600:])
        # the rivals' order books in the risks (since 23 Oct): each flagged rival once, with whom it meets
        flags = {x["airline_id"]: x for a in F.get("airlines") or [] for x in a.get("order_flags") or []}
        if flags:
            k = text.find("Rivals' order books")
            seg = text[k:k + 1500] if k >= 0 else ""
            check(k > text.find("RISKS") >= 0, "the risks list the rivals' order books", text[text.find("RISKS"):][:300])
            first = (ours[0].get("iata_code") or names[0]) if ours else ""
            for x in sorted(flags.values(), key=lambda x: (-(x["share"] if x["share"] is not None else float("inf")), -x["on_order"])):
                meets = [(fa.get(a["id"]) or {}).get("code") or name for a, name in zip(ours, names)
                         if any(y["airline_id"] == x["airline_id"] and y.get("meets") for y in (fa.get(a["id"]) or {}).get("order_flags") or [])]
                book = (f"{x['on_order']:,} on order, no flights yet" if x["kind"] == "starting"
                        else f"{x['on_order']:,} on order, {x['share']:.1f}% of {x['fleet']:,} aircraft")
                wk = "—" if x.get("on_order_change") is None else ("no change" if x["on_order_change"] == 0 else f"{x['on_order_change']:+,} on order")
                want = f"{x['name']} {book} {wk} {', '.join(meets) if meets else 'none'}"
                check(want in seg, f"the order books: {want!r}", seg[:500])
        if synthetic:
            print("      (the sample predates competition()'s competitors in the figures: the test's copy has a synthetic block)", flush=True)
        if synthetic_market:
            print("      (the sample predates the market pages' contested pairs in the figures: the test's copy has a synthetic block)", flush=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(f"\n{len(failures)} report check(s) failed" if failures else "\nweekly report: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
