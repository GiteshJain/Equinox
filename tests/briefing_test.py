"""The airline briefing on its saved sample (decision #24; spec docs/specs/2026-10-15-airline-briefing.md).

scripts/briefing/brief.py runs, unchanged, with --inputs on the newest tests/fixtures/briefing_<date>.json.gz: what it
downloads through export_for_report() (the captured figures, the planning library's input, the latest finished scan and
each airline's briefing rows), as the rehearsal's copy of a nightly backup gave them, cut to what the briefing needs
(tests/fixtures/briefing_sample.py; tests/README.md, "The briefing sample"). Nothing reaches the network: the home folder
holds no keys and $EQUINOX_API_URL points nowhere, so a briefing that tried to download would fail. Checks, for every
one of our airlines in the sample:
  - it prints a short briefing (every heading, at most 60 lines) and writes briefing_<code>.json with every section;
  - each section is that airline's, as the sample gives it: the card and cash forecast (airline_cards(),
    cash_forecast()); the fleet (every aircraft in service, its profit aircraft_profit()'s); the routes (each route its
    own: its route profit, loads and growth marks, never another airline's); hubs first; the deliveries, to-dos and fare
    plan exactly as the briefing kind gave them, each plan card with legs checked by the library; the rivals from the
    sample's scan; the capture's state and verdict.
And the cases the sample may not hold: an airline with no deliveries, no finished scan, an airline the scan doesn't hold,
a plan card checked (and one with a wrong service code, which the check names), and an airline that isn't ours.

Usage: python3 tests/briefing_test.py   (after npm run build, for the planning library's command)
"""
import copy, gzip, json, os, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIX = ROOT / "tests" / "fixtures"
BRIEF = ROOT / "scripts" / "briefing" / "brief.py"
CLI = ROOT / "lib" / "rules" / "dist" / "cli.js"
HEADINGS = ("Money", "Fleet (", "Routes (", "Hubs", "Deliveries (", "To-dos (", "Fare plan:", "Competition", "Rivals")
SECTIONS = ("airline", "card", "fleet", "routes", "hubs", "deliveries", "todos", "fare_plan", "rivals", "competition", "capture")
failures = []


def check(ok, name, detail=""):
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok or not detail else "\n      " + str(detail)[:900]), flush=True)
    if not ok:
        failures.append(name)
    return ok


class Runner:
    """Runs brief.py on saved inputs in a folder of its own, with no keys and nowhere to download from."""

    def __init__(self, work):
        self.work = pathlib.Path(work)
        self.home = self.work / "home"
        self.home.mkdir()
        self.n = 0

    def __call__(self, inputs, airline):
        self.n += 1
        folder = self.work / f"run{self.n}"
        folder.mkdir()
        path = folder / "inputs.json"
        path.write_text(json.dumps(inputs))
        env = {k: v for k, v in os.environ.items() if k.lower() not in ("http_proxy", "https_proxy", "all_proxy")}
        env.update(HOME=str(self.home), EQUINOX_API_URL="http://127.0.0.1:9", EQUINOX_RULES_CLI=str(CLI))
        r = subprocess.run([sys.executable, str(BRIEF), str(airline), "--inputs", str(path), "--out", str(folder)],
                           cwd=folder, env=env, capture_output=True, text=True, timeout=600)
        files = list(folder.glob("briefing_*.json"))
        return r, (json.loads(files[0].read_text()) if len(files) == 1 else None)


def ours(rules):
    return sorted((a for a in rules["airlines"] if a.get("ours") and a.get("active") is not False),
                  key=lambda a: (a.get("position") is None, a.get("position") or 0, a["id"]))


def block_lines(lines, heading):
    """How many lines a briefing's block takes, from its heading to the blank line after it."""
    i = next((k for k, x in enumerate(lines) if x.startswith(heading)), None)
    if i is None:
        return 0
    j = next((k for k in range(i, len(lines)) if not lines[k].strip()), len(lines))
    return j - i


def by_airline(rows, aid):
    return next((x for x in rows or [] if x.get("airline_id") == aid), None)


def check_airline(S, a, r, b):
    aid, code = a["id"], a["iata_code"]
    F, R, B = S["figures"], S["rules"], S["briefings"][str(aid)]
    FA = by_airline(F["airlines"], aid) or {}
    lines = r.stdout.strip().splitlines()
    if not check(r.returncode == 0 and b is not None, f"{code}: the briefing runs on the sample and writes its JSON", (r.stderr or r.stdout)[-900:]):
        return
    missing = [h for h in HEADINGS if not any(l.startswith(h) for l in lines)]
    check(not missing and len(lines) <= 60 and lines[0].startswith(f"{b['airline']['name']} ({code})"),
          f"{code}: it prints a short briefing ({len(lines)} lines, every heading)", f"missing {missing}")
    check(all(k in b for k in SECTIONS) and b["airline"]["id"] == aid and b["as_of"] == F["as_of"],
          f"{code}: every section, for this airline, as of the figures' moment", [k for k in SECTIONS if k not in b])
    # the card and the cash forecast: airline_cards() and cash_forecast(), as they are
    card, fc = by_airline(F["airline_cards"]["airlines"], aid), FA.get("cash_forecast") or {}
    check(b["card"]["card"] == card and b["card"]["cash"]["cash"] == fc.get("cash")
          and (b["card"]["cash"]["lowest"] or {}).get("balance") == (fc.get("lowest") or {}).get("balance"),
          f"{code}: the card and cash forecast are airline_cards()'s and cash_forecast()'s")
    if card and card.get("profit_day") is not None:
        check(f"Profit a day {card['profit_day']:.2f}M" in r.stdout, f"{code}: it prints the card's profit a day ({card['profit_day']:.2f}M)")
    # the fleet: every aircraft in service, each one the airline's, its profit aircraft_profit()'s
    rows = {x["id"]: x for x in R["aircraft"]}
    active = {x["registration"] for x in R["aircraft"] if x["airline_id"] == aid and x["status"] == "active"}
    regs = {x["registration"] for x in b["fleet"]}
    profit = {x["registration"]: x for x in (FA.get("aircraft_profit") or {}).get("7") or []}
    check(active <= regs and all(rows[x["aircraft_id"]]["airline_id"] == aid for x in b["fleet"]),
          f"{code}: the fleet holds its {len(active)} aircraft in service, and only its own", sorted(active ^ regs)[:6])
    check(all((x["profit"] or {}).get("net_day") == (profit.get(x["registration"]) or {}).get("net_day") for x in b["fleet"]),
          f"{code}: each aircraft's profit is aircraft_profit()'s")
    # the routes: each its own, never another airline's (route_profit(), route_loads(), growth_signals())
    rp = {x["route_id"]: x for x in ((FA.get("route_profit") or {}).get("7") or {}).get("routes") or []}
    loads = {x["route_id"]: x for x in (B.get("route_loads") or {}).get("routes") or []}
    rotations = {x["route_id"] for x in R["rotations"] if x["airline_id"] == aid}
    own = set(rp) | set(loads) | rotations
    routes = b["routes"]["routes"]
    foreign = [x["route_id"] for x in routes if x["route_id"] not in own]
    wrong = [x["route_id"] for x in routes if x["route_id"] in rp and (x["profit"] or {}).get("profit_week") != rp[x["route_id"]].get("profit_week")]
    wrong += [x["route_id"] for x in routes if x["route_id"] in loads and (x["load"] or {}).get("average") != loads[x["route_id"]].get("average")]
    check(not foreign and not wrong and own <= {x["route_id"] for x in routes},
          f"{code}: {len(routes)} routes, each the airline's own with its own profit and loads",
          f"not the airline's: {foreign[:8]}; another route's figures: {wrong[:8]}; left out: {sorted(own - {x['route_id'] for x in routes})[:8]}")
    marks = {(x.get("route_id"), k) for k in ("ready_for_another_flight", "raise_fares", "fix_or_reduce") for x in F["growth_signals"].get(k) or []
             if x.get("airline_id") == aid}
    check({(x["route_id"], k) for x in routes for k in x["growth_lists"]} == marks, f"{code}: the growth lists name its routes ({len(marks)} marks)")
    # hubs first, deliveries, to-dos, fare plan and capture, as the sample gives them
    check(b["hubs"] == by_airline(F["hub_progress"]["airlines"], aid), f"{code}: hubs first is hub_progress()'s")
    cards = [c for d in b["deliveries"] for c in d["plan_cards"]]
    check([d["aircraft_id"] for d in b["deliveries"]] == [d["aircraft_id"] for d in B["deliveries"]]
          and all(c.get("check") is not None and "ok" in c["check"] for c in cards if c.get("legs")),
          f"{code}: {len(b['deliveries'])} deliveries as the briefing kind gave them, {len(cards)} plan cards, each with legs checked")
    check(b["todos"] == B["todos"] and b["fare_plan"] == B["fare_plan"], f"{code}: {len(b['todos'])} open to-dos and the fare plan as the briefing kind gave them")
    cs = by_airline(F["capture_status"]["airlines"], aid) or {}
    check((b["capture"] or {}).get("verdict") == cs.get("verdict") and (b["capture"] or {}).get("last_at") == cs.get("last_at"),
          f"{code}: the capture's state and verdict ({cs.get('verdict') or 'not checked'})")
    # the rivals: the sample's scan, every pair the airline flies now
    pairs = {"–".join(sorted((l["origin_code"], l["dest_code"]))) for l in R["flight_legs"] if l["airline_id"] == aid}
    rv = b["rivals"]
    check(rv["scan_id"] == (S["scan"] or {}).get("id") and pairs <= {x["pair"] for x in rv["routes"]},
          f"{code}: rivals from scan {rv['scan_id']} on its {len(pairs)} airport pairs ({sum(1 for x in rv['routes'] if x['rivals_weekly'])} shared)")


def main():
    samples = sorted(FIX.glob("briefing_*.json.gz"))
    if not check(bool(samples), "the briefing sample is in tests/fixtures/ (briefing_<date>.json.gz)"):
        sys.exit(1)
    if not check(CLI.is_file(), "the planning library is built (npm run build: lib/rules/dist/cli.js)"):
        sys.exit(1)
    S = json.load(gzip.open(samples[-1]))
    airlines = ours(S["rules"])
    print(f"sample {samples[-1].name}: figures as of {S['figures']['as_of']}, {len(airlines)} airlines, scan {(S['scan'] or {}).get('id')}", flush=True)
    with tempfile.TemporaryDirectory() as work:
        run = Runner(work)
        for a in airlines:
            r, b = run(S, a["iata_code"])
            check_airline(S, a, r, b)

        # an airline with no deliveries (the sample's, or the first airline's taken out)
        a = next((x for x in airlines if not S["briefings"][str(x["id"])]["deliveries"]), None)
        T = S
        if a is None:
            a, T = airlines[0], copy.deepcopy(S)
            T["briefings"][str(a["id"])]["deliveries"] = []
        r, b = run(T, a["iata_code"])
        check(r.returncode == 0 and b["deliveries"] == [] and "Deliveries (0): none on order or waiting" in r.stdout,
              f"no deliveries ({a['iata_code']}): an empty list, and the briefing says so", r.stderr[-600:])

        # no finished scan
        a = airlines[0]
        T = dict(S, scan=None)
        r, b = run(T, a["iata_code"])
        check(r.returncode == 0 and b["rivals"]["scan_id"] is None and b["rivals"]["routes"] == [] and "Rivals: no finished world scan" in r.stdout,
              f"no scan ({a['iata_code']}): no rivals, and the briefing says so", r.stderr[-600:])

        # an airline the scan doesn't hold (new since it was taken)
        if S["scan"]:
            T = copy.deepcopy(S)
            T["scan"]["airlines"] = [x for x in T["scan"]["airlines"] if x["id"] != a.get("game_id")]
            r, b = run(T, a["iata_code"])
            pairs = {"–".join(sorted((l["origin_code"], l["dest_code"]))) for l in S["rules"]["flight_legs"] if l["airline_id"] == a["id"]}
            check(r.returncode == 0 and b["rivals"]["in_scan"] is False and all(x["ours_weekly"] == 0 for x in b["rivals"]["routes"])
                  and pairs <= {x["pair"] for x in b["rivals"]["routes"]} and "isn't in this scan" in r.stdout,
                  f"not in the scan ({a['iata_code']}): its routes now, with the rivals on them, and the briefing says so", r.stderr[-600:])

        # a plan card checked by the library: an aircraft in service's own legs as a card, then a wrong service code
        R = S["rules"]
        pick = None
        for x in airlines:
            ac = next((c for c in R["aircraft"] if c["airline_id"] == x["id"] and c["status"] == "active"
                       and any(l["aircraft_id"] == c["id"] for l in R["flight_legs"])), None)
            if ac:
                pick = (x, ac)
                break
        if check(pick is not None, "the sample has an aircraft flying, for the plan card's check"):
            x, ac = pick
            legs = [{"position": i + 1, "flight_no": l["flight_no"], "origin_code": l["origin_code"], "dest_code": l["dest_code"],
                     "days_utc": l["days_utc"], "dep_utc_min": l["dep_utc_min"], "block_min": l["block_min"], "service_code": None}
                    for i, l in enumerate(sorted((l for l in R["flight_legs"] if l["aircraft_id"] == ac["id"]), key=lambda l: (l["rotation_id"], l["leg_no"])))]
            T = copy.deepcopy(S)
            T["briefings"][str(x["id"])]["deliveries"] = [{"aircraft_id": ac["id"], "registration": ac["registration"], "status": "delivered",
                                                           "type": "test", "arrived": True, "plan_cards": [{"id": -1, "title": "its own legs", "legs": legs}]}]
            r, b = run(T, x["iata_code"])
            ck = (b or {"deliveries": [{"plan_cards": [{}]}]})["deliveries"][0]["plan_cards"][0].get("check") or {}
            check(r.returncode == 0 and isinstance(ck.get("problems"), list) and len(ck.get("legs") or []) == len(legs)
                  and "service" in ck and f'card "its own legs", {len(legs)} legs:' in r.stdout,
                  f"a plan card ({ac['registration']}'s {len(legs)} legs) is checked by the library, service codes included",
                  (r.stderr or str(ck))[-600:])
            # each route's fare level (since 21 Oct; spec docs/specs/2026-10-21-frequencies-and-fares.md §2), per direction
            # since 26 Oct (spec docs/specs/2026-10-26-fare-ladder-per-direction.md §3): with the briefing's fare_ladder, the
            # check's fares and the card's line; the first leg's route on the ladder at 110 out (from its hub) and 105 back,
            # each leg at its own direction's level, the rest not on it (launch)
            first = legs[0]
            hub, dest = sorted((first["origin_code"], first["dest_code"]))
            T["briefings"][str(x["id"])]["fare_ladder"] = {"week_of": "2026-10-17", "settings": {"launch_pct": 100}, "routes": [
                {"route_id": None, "hub": hub, "dest": dest, "direction": "out", "from": hub, "to": dest, "cabin": "economy", "level": 110, "new_level": 115, "planned": False},
                {"route_id": None, "hub": hub, "dest": dest, "direction": "back", "from": dest, "to": hub, "cabin": "economy", "level": 105, "new_level": 105, "planned": False}]}
            r, b = run(T, x["iata_code"])
            ck = (b or {"deliveries": [{"plan_cards": [{}]}]})["deliveries"][0]["plan_cards"][0].get("check") or {}
            fares = ck.get("fares") or []
            ways = {(L["origin_code"], L["dest_code"]) for L in legs}
            want = lambda f: (("economy +10% of the default price" if f.get("from") == hub else "economy +5% of the default price")
                              if {f.get("from"), f.get("to")} == {hub, dest} else "launch (+0% of the default price)")
            first_words = "economy +10%" if first["origin_code"] == hub else "economy +5%"
            check(r.returncode == 0 and len(fares) == len(ways) and fares[0].get("route") == f"{hub}–{dest}"
                  and fares[0].get("from") == first["origin_code"] and all(f.get("words") == want(f) for f in fares)
                  and f"· fares: {first['origin_code']} → {first['dest_code']} {first_words}" in r.stdout,
                  f"a plan card's fare levels: each of its {len(ways)} directions once, the one on the ladder at its own direction's level "
                  "(economy +10% out, +5% back), the others at launch, on the card's line", (r.stderr or str(fares))[-600:])
            del T["briefings"][str(x["id"])]["fare_ladder"]
            for L in legs:
                L["service_code"] = "S9"
            T["briefings"][str(x["id"])]["deliveries"][0]["plan_cards"][0]["legs"] = legs
            r, b = run(T, x["iata_code"])
            ck = (b or {"deliveries": [{"plan_cards": [{}]}]})["deliveries"][0]["plan_cards"][0].get("check") or {}
            check(r.returncode == 0 and ck.get("ok") is False and any("S9" in p for p in ck.get("problems") or []),
                  "a card with a wrong service code (S9) fails its check, naming the code", (ck.get("problems") or r.stderr)[:3])

        # competition analysis (since 21 Oct; spec docs/specs/2026-10-21-competition-analysis.md §4): the briefing kind's
        # competition, its threats and top openings printed under its heading; a sample made before it says so
        a = airlines[0]
        T = copy.deepcopy(S)
        had = "competition" in T["briefings"][str(a["id"])]
        T["briefings"][str(a["id"])].pop("competition", None)
        r, b = run(T, a["iata_code"])
        check(r.returncode == 0 and b["competition"].get("note") and "Competition: not in these inputs" in r.stdout,
              f"competition ({a['iata_code']}): a briefing made before 21 Oct has none, and says so" + (" (the sample has it)" if had else ""), r.stderr[-600:])
        opening = lambda k, route, stars, rivals, allowed: {"rank": k, "route": route, "stars": stars, "distance_km": 1000 + k, "rivals_weekly": rivals,  # noqa: E731
                                                            "variant": {"type": "E195-E2"}, "allowed": allowed}
        T["briefings"][str(a["id"])]["competition"] = {
            "scans": {"latest": {"id": 2, "taken_at": "2026-10-17T19:00:00.000Z"}, "week_before": {"id": 1, "taken_at": "2026-10-06T21:00:00.000Z"}},
            "group": {"ours": 4016, "world": 97960, "share": 4.1},
            "threats": [{"words": "Air China started on PVG–CAN, 14 a week", "on": "2026-10-17T19:00:00.000Z", "until": "2026-10-24T19:00:00.000Z"}],
            "openings": [opening(k, f"AAA–B{k:02d}", 5, 30 - k, k < 6) for k in range(1, 8)], "openings_count": 7, "openings_allowed": 5, "openings_left_out": 0}
        r, b = run(T, a["iata_code"])
        lines = r.stdout.splitlines()
        check(r.returncode == 0 and b["competition"]["openings_count"] == 7 and len(b["competition"]["openings"]) == 7 and len(lines) <= 62
              and "Competition (scan 17 Oct against 6 Oct): 1 threat(s), 7 opening(s), 5 allowed under hubs first, top 3 (20 in the JSON):" in r.stdout
              and "  threats: Air China started on PVG–CAN, 14 a week (17 Oct) · fares paused until 24 Oct" in r.stdout
              and "  top: 1. AAA–B01 5★ 1001 km, rivals 29 a week, E195-E2; 2. AAA–B02" in r.stdout and "AAA–B04" not in r.stdout
              and block_lines(lines, "Competition") == 3,
              f"competition ({a['iata_code']}): the scans, the threats in a line and the top 3 openings under its heading, the rest in the JSON", r.stdout[-900:])
        # in November (manual §4) a trunk is marked in the top line
        T["briefings"][str(a["id"])]["competition"]["openings"][0]["trunk"] = True
        r, b = run(T, a["iata_code"])
        check(r.returncode == 0 and "  top: 1. AAA–B01 5★ 1001 km, rivals 29 a week, E195-E2 (November trunk); 2. AAA–B02" in r.stdout
              and "E195-E2 (November trunk); 3." not in r.stdout,
              f"competition ({a['iata_code']}): a November trunk is marked in the top line, the others not", r.stdout[-900:])

        # an airline that isn't ours
        r, b = run(S, "ZZ")
        check(r.returncode == 2 and b is None and "isn't one of our airlines" in r.stderr, "an airline that isn't ours is refused, listing ours", r.stderr[-300:])
    print(f"{'all passed' if not failures else str(len(failures)) + ' failed'}", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
