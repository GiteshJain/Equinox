"""The airline briefing (decision #24): the whole background for one airline in one step, before scheduling (manual §4).

    python3 scripts/briefing/brief.py <airline> [--as-of <moment>] [--out <folder>]

<airline> is its IATA code (KF), its planner name (Kingfisher), its game name or its id. It prints a short briefing,
about one screen, and writes the full JSON beside it as briefing_<code>.json (in --out, else the current folder).

It only gathers. Each figure comes from its one home (#19), downloaded through export_for_report():
- kind figures (as of --as-of, now by default): the airline's card and cash forecast (airline_cards(),
  cash_forecast()), aircraft and route profit over 7 days (aircraft_profit(), route_profit()), the growth lists and load
  patterns (growth_signals()), hubs first (hub_progress()) and the capture's state with #21's verdict (capture_status());
- kind rules: the planning library's input, which the library's command reads (node lib/rules/dist/cli.js): each
  aircraft's legs a week, block hours a day, maintenance and issues (aircraft), and each plan card's check (check-card,
  service codes included, and since 21 Oct its cabin against the one its routes call for: the card's config_id, and the
  fare level of each route it flies: --fares with the briefing's fare_ladder);
- kind briefing: the airline's deliveries (aircraft on order or arrived, not yet filed) with their plan cards and legs,
  its open to-dos and the group's, its fare plan (fare_plan_status()), each route's fare level (fare_ladder()'s, since
  21 Oct), competition analysis (competition()'s scans, group line, threats and top 20 openings, since 21 Oct: the
  evening proposal's ranked list, manual §3; since 22 Oct a 1-star opening on the E195-E2 says "or the E190-E2 if thin")
  and its loads by route over 7 days (route_loads());
- kinds snapshots and airlines: the latest finished world scan by the moment, for the rivals on the routes it flies and
  at the airports it serves, counted as the weekly report counts them (scripts/report/analyze.py's passenger-flight rule).

Needs ~/.sb_anon (the public key) and ~/.ingest_secret, never committed (scripts/README.md), and the library built
(npm ci && npm run build; or $EQUINOX_RULES_CLI). $EQUINOX_API_URL points it at another copy of the database (the
rehearsal's). --inputs <file> reads saved inputs instead of the database (the checks' sample, tests/briefing_test.py).
"""
import argparse, collections, datetime, json, os, pathlib, re, subprocess, sys, tempfile, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
LIVE = "https://ulecwsyedvwcxgdzmhoq.supabase.co"
SECTIONS = ("airline", "card", "fleet", "routes", "hubs", "deliveries", "todos", "fare_plan", "rivals", "competition", "capture")
GROWTH_LISTS = ("ready_for_another_flight", "raise_fares", "fix_or_reduce")


class Refused(Exception):
    """A plain message for the person running it (an unknown airline, a missing key or build)."""


# ---------------------------------------------------------------- downloading (export_for_report)
def rpc(name, body):
    base = (os.environ.get("EQUINOX_API_URL") or LIVE).rstrip("/")
    try:
        key = open(os.path.expanduser("~/.sb_anon")).read().strip()
    except OSError:
        raise Refused("no ~/.sb_anon: put the public Supabase key there (scripts/README.md)")
    req = urllib.request.Request(base + "/rest/v1/rpc/" + name, data=json.dumps(body).encode(),
                                 headers={"apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read() or b"null")


def export(kind, arg=None):
    try:
        secret = open(os.path.expanduser("~/.ingest_secret")).read().strip()
    except OSError:
        raise Refused("no ~/.ingest_secret: put the ingest secret there (scripts/README.md)")
    return rpc("export_for_report", {"p_secret": secret, "p_kind": kind, "p_arg": arg})


def pull(ident, as_of):
    """Everything the briefing reads, for one airline, as one document (the shape --inputs reads)."""
    rules = export("rules", "")
    airline = find_airline(rules, ident)
    at = {"as_of": as_of} if as_of else {}
    snaps = export("snapshots") or []
    done = [s for s in snaps if s.get("status") == "done" and (not as_of or moment(s.get("taken_at")) <= moment(as_of))]
    scan = None
    if done:
        s = max(done, key=lambda x: x["id"])
        scan = {"id": s["id"], "taken_at": s.get("taken_at"), "airlines": export("airlines", str(s["id"]))}
    return {"as_of": as_of, "rules": rules, "figures": export("figures", json.dumps(at)), "scan": scan,
            "briefing": export("briefing", json.dumps(dict(at, airline=airline["id"])))}


# ---------------------------------------------------------------- small helpers
def moment(ts):
    """A moment from the database's text (UTC when it names no zone, as a date does)."""
    if not ts:
        return None
    m = datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    return m if m.tzinfo else m.replace(tzinfo=datetime.timezone.utc)


def when(ts, clock=True):
    m = moment(ts)
    if not m:
        return "—"
    m = m.astimezone(datetime.timezone.utc)
    return f"{m.day} {m:%b}" + (f" {m:%H:%M} UTC" if clock else "")


def money(x):
    return "—" if x is None else f"{x:.2f}M"


def signed(x):
    return "—" if x is None else f"{x:+.2f}M"


def pct(x):
    return "—" if x is None else f"{x:.0f}%"


def name_of(a):
    return a.get("public_name") or a.get("planner_name") or a.get("game_name") or a.get("iata_code") or f"Airline {a['id']}"


def ours(rules):
    return sorted((a for a in rules.get("airlines") or [] if a.get("ours") and a.get("active") is not False),
                  key=lambda a: (a.get("position") is None, a.get("position") or 0, a["id"]))


def find_airline(rules, ident):
    """One of our active airlines, by id, IATA code, planner name, public name or game name (any case)."""
    want = str(ident).strip().lower()
    for a in ours(rules):
        if want in {str(a["id"]), *(str(a.get(k)).lower() for k in ("iata_code", "planner_name", "public_name", "game_name") if a.get(k))}:
            return a
    raise Refused(f"{ident} isn't one of our airlines: " + ", ".join(f"{a.get('iata_code')} ({name_of(a)})" for a in ours(rules)))


def rules_cli():
    for p in [os.environ.get("EQUINOX_RULES_CLI"), REPO / "lib" / "rules" / "dist" / "cli.js"]:
        if p and pathlib.Path(p).is_file():
            return str(p)
    raise Refused("the planning library's command isn't built: run npm ci && npm run build in the repository (or set EQUINOX_RULES_CLI)")


def library(*args):
    """The planning library's command (lib/rules/src/cli.ts), answering in JSON; raises with its error."""
    r = subprocess.run(["node", rules_cli(), *map(str, args)], capture_output=True, text=True, timeout=600)
    if r.returncode:
        raise RuntimeError((r.stderr.strip().splitlines() or ["the library's command failed"])[-1])
    return json.loads(r.stdout)


def passenger_seats():
    """The weekly report's rule for a passenger flight (scripts/report/analyze.py's market block, run as it stands, as
    scan_markets.py runs it): seats(type) is 0 for a freighter. The block's markers are found at the start of a line,
    since the comment above the block names them too."""
    src = (REPO / "scripts" / "report" / "analyze.py").read_text()
    start, end = re.search(r"(?m)^REG=\{\}", src), re.search(r"(?m)^# ---------- world markets", src)
    if not start or not end:
        raise Refused("scripts/report/analyze.py's market block (REG={} to # ---------- world markets) wasn't found")
    g = {"collections": collections, "ap": {}}
    exec(src[start.start():end.start()], g)
    return g["seats"]


# ---------------------------------------------------------------- gathering
def gather(inp, ident, workdir):
    R, F = inp["rules"], inp["figures"]
    a = find_airline(R, ident)
    aid = a["id"]
    B = inp.get("briefing") or (inp.get("briefings") or {}).get(str(aid))
    if not B or (B.get("airline") or {}).get("id") != aid:
        raise Refused(f"the inputs hold no briefing rows for {a.get('iata_code')} (export_for_report kind briefing)")
    rules_path = pathlib.Path(workdir) / "rules.json"
    rules_path.write_text(json.dumps(R))

    # its hubs and focus cities; never a station (since 22 Oct, manual §2: no base; its routes count like any other)
    bases = sorted((b for b in R.get("airline_bases") or [] if b["airline_id"] == aid and b.get("role") != "station"),
                   key=lambda b: (b.get("position") is None, b.get("position") or 0, b["id"]))
    FA = next((x for x in F.get("airlines") or [] if x.get("airline_id") == aid), {})
    out = {"airline": {"id": aid, "code": a.get("iata_code"), "name": name_of(a), "planner_name": a.get("planner_name"),
                       "game_id": a.get("game_id"), "main_hub": next((b["airport_code"] for b in bases if b.get("is_main")), None),
                       "bases": [{"code": b["airport_code"], "role": b.get("role"), "main": bool(b.get("is_main"))} for b in bases]},
           "as_of": F.get("as_of"),
           "sources": {"figures_as_of": F.get("as_of"), "briefing_as_of": B.get("as_of"),
                       "rules": "the tables as they are now (rules_input())",
                       "deliveries_and_todos": "the tables as they are now",
                       "scan": None}}

    # ---- the card and cash (airline_cards(), cash_forecast())
    card = next((c for c in (F.get("airline_cards") or {}).get("airlines") or [] if c.get("airline_id") == aid), None)
    fc = FA.get("cash_forecast") or {}
    low = fc.get("lowest") or {}
    out["card"] = {
        "card": card,
        "cash": {"status": fc.get("status") or "no capture", "missing": fc.get("missing"), "cash": fc.get("cash"), "cash_at": fc.get("cash_at"),
                 "flight_profit_day": fc.get("flight_profit_day"), "cushion": fc.get("cushion"),
                 "lowest": {"balance": low.get("balance"), "at": low.get("at"), "payment": (low.get("payment") or {}).get("what")} if low else None,
                 "can_order_now": fc.get("can_order_now"), "next_order": fc.get("next_order")}}

    # ---- the fleet (the library's aircraft, aircraft_profit())
    cabins = {c["id"]: c for c in R.get("cabin_configs") or []}
    rows = {x["id"]: x for x in R.get("aircraft") or []}
    profit = {x.get("registration"): x for x in ((FA.get("aircraft_profit") or {}).get("7") or [])}
    fleet = []
    for w in library("aircraft", rules_path):
        if w.get("airline_id") != aid:
            continue
        row = rows.get(w["aircraft_id"]) or {}
        issues = [f"{n} {what}" for n, what in ((w.get("turns_short"), "short turn(s)"), (w.get("turns_tight"), "tight turn(s)"),
                                                (w.get("position_breaks"), "position break(s)"), (w.get("overlaps"), "overlap(s)"),
                                                (w.get("estimated_legs"), "leg(s) on an estimated block")) if n]
        if w.get("maintenance_level") in ("bad", "warn"):
            issues.insert(0, f"maintenance {w.get('maintenance_pct')}% ({w.get('maintenance_level')})")
        p = profit.get(w.get("registration")) or {}
        fleet.append({"aircraft_id": w["aircraft_id"], "registration": w.get("registration"), "type": w.get("type"), "base": w.get("base_code"),
                      "cabin": (cabins.get(row.get("cabin_config_id")) or {}).get("code"), "status": w.get("status"),
                      "legs_week": w.get("legs_week"), "block_hours_day": w.get("block_hours_day"), "routes": w.get("routes"),
                      "maintenance_pct": w.get("maintenance_pct"), "maintenance_level": w.get("maintenance_level"), "issues": issues,
                      "profit": {k: p.get(k) for k in ("flights", "flight_profit_day", "lease_day", "net_day")} if p else None})
    out["fleet"] = fleet

    # ---- the routes (route_loads(), route_profit(), growth_signals())
    rp = (FA.get("route_profit") or {}).get("7") or {}
    loads = {r["route_id"]: r for r in (B.get("route_loads") or {}).get("routes") or []}
    G = F.get("growth_signals") or {}
    lists = collections.defaultdict(list)
    for k in GROWTH_LISTS:
        for x in G.get(k) or []:
            if x.get("airline_id") == aid:
                lists[x.get("route_id")].append(k)
    pattern = {x.get("route_id"): x for x in G.get("load_patterns") or [] if x.get("airline_id") == aid}
    rot_routes = {r["route_id"] for r in R.get("rotations") or [] if r.get("airline_id") == aid}
    route_rows = {r["id"]: r for r in R.get("routes") or []}
    ids = list(dict.fromkeys([x.get("route_id") for x in rp.get("routes") or []] + list(loads) + sorted(rot_routes)))
    routes = []
    for rid in ids:
        if rid is None:
            continue
        p = next((x for x in rp.get("routes") or [] if x.get("route_id") == rid), None)
        L, pt, rr = loads.get(rid), pattern.get(rid), route_rows.get(rid) or {}
        src = p or L or pt or {}
        routes.append({"route_id": rid, "hub": src.get("hub") or rr.get("hub_code"), "dest": src.get("dest") or rr.get("dest_code"),
                       "load": {k: L.get(k) for k in ("average", "departures", "days", "full", "under_95", "under_85", "under_70")} if L else None,
                       "profit": {k: p.get(k) for k in ("flights", "flights_week", "profit", "profit_week", "profit_per_flight", "economy", "economy_fare", "sold_out_share")} if p else None,
                       "mark": p.get("mark") if p else None, "why": p.get("why") if p else None,
                       "growth_lists": lists.get(rid, []),
                       "pattern": {"mark": pt.get("mark"), "why": pt.get("why")} if pt else None})
    out["routes"] = {"days": rp.get("days"), "since": rp.get("since"), "loads_from": (B.get("route_loads") or {}).get("from"),
                     "loads_to": (B.get("route_loads") or {}).get("to"), "routes": routes}

    # ---- the hubs (hub_progress())
    out["hubs"] = next((h for h in (F.get("hub_progress") or {}).get("airlines") or [] if h.get("airline_id") == aid), None)

    # ---- deliveries and plan cards (the briefing kind; the library's check-card), each card with the fare level of each
    # route it flies (since 21 Oct: the briefing's fare_ladder, fare_ladder()'s levels; none in inputs made before it)
    fares_args = []
    if isinstance(B.get("fare_ladder"), dict) and isinstance(B["fare_ladder"].get("routes"), list):
        ladder_path = pathlib.Path(workdir) / "fare_ladder.json"
        ladder_path.write_text(json.dumps(B["fare_ladder"]))
        fares_args = ["--fares", ladder_path]
    deliveries = []
    for d in B.get("deliveries") or []:
        cards = []
        for c in d.get("plan_cards") or []:
            check = None
            if c.get("legs"):
                card_path = pathlib.Path(workdir) / f"card_{c['id']}.json"
                # the card's cabin (config_id, since 21 Oct) is checked against the one its routes call for
                card_path.write_text(json.dumps({"aircraft": d["aircraft_id"], "config_id": c.get("config_id"), "legs": c["legs"]}))
                try:
                    check = library("check-card", rules_path, card_path, *fares_args)
                except RuntimeError as e:
                    check = {"ok": False, "error": str(e), "problems": [str(e)]}
            cards.append(dict(c, check=check))
        deliveries.append(dict(d, plan_cards=cards))
    out["deliveries"] = deliveries

    # ---- to-dos, the fare plan (the briefing kind)
    out["todos"] = B.get("todos") or []
    out["fare_plan"] = B.get("fare_plan") or {}

    # ---- competition analysis (the briefing kind's competition: competition()'s scans, group line, threats and top 20
    # openings, since 21 Oct; none in inputs made before it)
    C = B.get("competition")
    out["competition"] = C if isinstance(C, dict) else {"note": "not in these inputs (a briefing made before 21 Oct)", "scans": None, "group": None,
                                                        "threats": [], "openings": [], "openings_count": None, "openings_allowed": None,
                                                        "openings_left_out": None}

    # ---- the rivals on its routes and at its airports (the latest world scan)
    out["rivals"] = rivals(inp.get("scan"), a, R, F.get("as_of"))
    out["sources"]["scan"] = {k: out["rivals"].get(k) for k in ("scan_id", "taken_at", "age_days")}

    # ---- the capture (capture_status(), with #21's verdict)
    cs = next((c for c in (F.get("capture_status") or {}).get("airlines") or [] if c.get("airline_id") == aid), None)
    out["capture"] = ({k: cs.get(k) for k in ("last_at", "verdict", "verdict_words", "verdict_at", "verdict_day", "status", "missing",
                                               "flights_today", "flights_yesterday")} if cs else None)
    return out


def rivals(scan, a, R, as_of):
    """Who else flies the airline's routes and serves its airports, from the latest finished world scan: departures a week
    (each flight's days), passenger flights only, as the weekly report counts them. Its routes and airports are those it
    flies now (its legs) and those the scan saw it fly."""
    aid = a["id"]
    legs = [l for l in R.get("flight_legs") or [] if l.get("airline_id") == aid]
    pairs_now = {frozenset((l["origin_code"], l["dest_code"])) for l in legs}
    airports_now = {c for p in pairs_now for c in p} | {b["airport_code"] for b in R.get("airline_bases") or [] if b["airline_id"] == aid}
    if not scan:
        return {"scan_id": None, "taken_at": None, "age_days": None, "in_scan": False, "note": "no finished world scan",
                "routes": [], "airports": []}
    taken, now = moment(scan.get("taken_at")), moment(as_of) or datetime.datetime.now(datetime.timezone.utc)
    group = {x.get("game_id"): name_of(x) for x in ours(R) if x.get("game_id") is not None and x["id"] != aid}
    me = a.get("game_id")
    seats = passenger_seats()
    by_pair = collections.defaultdict(collections.Counter)   # pair -> airline (scan id) -> departures a week
    by_dep = collections.defaultdict(collections.Counter)    # airport -> airline -> departures a week from it
    names, in_scan, pairs_scan = {}, False, set()
    for x in scan.get("airlines") or []:
        names[x["id"]] = x.get("name") or str(x["id"])
        in_scan = in_scan or x["id"] == me
        for f in x.get("flights") or []:
            n = len(f[4] or "")
            if not n or seats(f[7]) == 0:
                continue
            p = frozenset((f[2], f[3]))
            by_pair[p][x["id"]] += n
            by_dep[f[2]][x["id"]] += n
            if x["id"] == me:
                pairs_scan.add(p)
    label = lambda k: group.get(k) or names.get(k, str(k))   # noqa: E731
    routes = []
    for p in pairs_now | pairs_scan:
        d = by_pair.get(p) or {}
        rv = sorted(((label(k), v) for k, v in d.items() if k != me and k not in group), key=lambda kv: (-kv[1], kv[0]))
        routes.append({"pair": "–".join(sorted(p)), "flies_now": p in pairs_now, "ours_weekly": d.get(me, 0),
                       "group": sorted(((label(k), v) for k, v in d.items() if k in group), key=lambda kv: (-kv[1], kv[0])),
                       "rivals": rv, "rivals_weekly": sum(v for _, v in rv)})
    routes.sort(key=lambda r: (-r["rivals_weekly"], r["pair"]))
    airports = []
    for c in sorted(airports_now | {x for p in pairs_scan for x in p}):
        d = by_dep.get(c) or {}
        rv = sorted(((label(k), v) for k, v in d.items() if k != me and k not in group), key=lambda kv: (-kv[1], kv[0]))
        airports.append({"code": c, "ours_weekly": d.get(me, 0), "group_weekly": sum(v for k, v in d.items() if k in group),
                         "rivals_weekly": sum(v for _, v in rv), "top_rivals": rv[:5]})
    airports.sort(key=lambda r: (-r["rivals_weekly"], r["code"]))
    return {"scan_id": scan.get("id"), "taken_at": scan.get("taken_at"),
            "age_days": round((now - taken).total_seconds() / 86400, 1) if taken else None,
            "in_scan": in_scan, "note": None if in_scan else "the airline isn't in this scan (new since it was taken, or not scanned)",
            "routes": routes, "airports": airports}


# ---------------------------------------------------------------- printing (about one screen)
def next_order(no):
    no = no or {}
    w = no.get("when")
    if w == "now":
        return "now (" + ", ".join(no.get("types") or []) + ")"
    if w == "later":
        return f"{no.get('type')} from {when(no.get('safe_from'), False)}"
    if w == "needs":
        return "needs " + (no.get("missing") or "a capture")
    return w or "—"


def fare_words(fares):
    """Each route's fare level on a card, in one line: "HUB–AAA economy +10%, business +5%; HUB–NBN launch +0% of the
    default price" (the library's cardFares, through check-card --fares)."""
    if not fares:
        return ""
    def one(f):
        if f.get("flown"):
            return f"{f['route']} " + ", ".join(f"{c['cabin']} {level_pct(c['level'])}" for c in f.get("cabins") or [])
        return f"{f['route']} launch {level_pct(f.get('launch_pct'))}"
    return "; ".join(one(f) for f in fares) + " of the default price"


def level_pct(level):
    """A level against the default price, as the game takes it: 110 → +10%, 85 → −15%."""
    if level is None:
        return "?"
    d = round(float(level) - 100, 1)
    return ("−" if d < 0 else "+") + f"{abs(d):g}%"


def competition_line(C):
    """Competition's heading line: the scans, the threats and the openings ("Competition (scan 17 Oct against 6 Oct): 2
    threat(s), 419 opening(s), 120 allowed under hubs first, top 3 (20 in the JSON):")."""
    if C.get("note"):
        return "Competition: " + C["note"]
    sc = C.get("scans") or {}
    latest, before = (sc.get("latest") or {}).get("taken_at"), (sc.get("week_before") or {}).get("taken_at")
    scans = "no world scan" if not latest else f"scan {when(latest, False)}" + (f" against {when(before, False)}" if before else ", the only one")
    n, ok = C.get("openings_count") or 0, C.get("openings_allowed") or 0
    return (f"Competition ({scans}): {len(C.get('threats') or [])} threat(s), {n} opening(s), {ok} allowed under hubs first"
            + (f", top {min(3, len(C.get('openings') or []))} (20 in the JSON):" if C.get("openings") else ""))


def render(b):
    A, L = b["airline"], []
    put = L.append
    put(f"{A['name']} ({A['code']}) · briefing as of {when(b['as_of'])}")
    cap = b.get("capture")
    if cap:
        verdict = ", ".join(x for x in (cap.get("verdict"), cap.get("verdict_words")) if x) or "not checked"
        put(f"Capture: last {when(cap.get('last_at'))} · {verdict} · today {cap.get('status')}")
    else:
        put("Capture: none for this airline")

    c, cash = (b["card"].get("card") or {}), b["card"]["cash"]
    put("")
    put("Money")
    put(f"  Profit a day {money(c.get('profit_day'))} over {c.get('span_days') or '—'} days" + (" (early read)" if c.get("early") else "")
        + f" · per aircraft {money(c.get('per_aircraft_day'))} · cash {money(cash.get('cash'))} ({when(cash.get('cash_at'))})")
    low = cash.get("lowest") or {}
    put(f"  Lowest in 14 days {money(low.get('balance'))} on {when(low.get('at'), False)}" + (f" ({low['payment']})" if low.get("payment") else "")
        + f" · next order: {next_order(c.get('next_order') or cash.get('next_order'))}")
    put(f"  Fleet {c.get('fleet', '—')} · on order {c.get('on_order', '—')} · {c.get('flights_day', '—')} flights a day · load 7 days {pct(c.get('load_7_days'))}")

    fl = b["fleet"]
    put("")
    put(f"Fleet ({len(fl)} flying or in service)")
    flagged = [x for x in fl if x["issues"] or ((x.get("profit") or {}).get("net_day") or 0) < 0]
    for x in sorted(flagged, key=lambda x: ((x.get("profit") or {}).get("net_day") or 0))[:6]:
        p = x.get("profit") or {}
        what = " ".join(str(v) for v in (x["registration"], x["type"], x.get("cabin")) if v)
        level = f" ({x['maintenance_level']})" if x.get("maintenance_level") in ("bad", "warn") else ""
        rest = [i for i in x["issues"] if not i.startswith("maintenance ")]
        put(f"  {what} at {x['base']}: {x['legs_week']} legs a week, {x['block_hours_day'] or 0:.1f} h a day, "
            f"maintenance {x.get('maintenance_pct') or '—'}%{level}, net {signed(p.get('net_day'))} a day" + (" · " + "; ".join(rest) if rest else ""))
    if not flagged:
        put("  no issues, none losing money after its lease")
    elif len(flagged) > 6:
        put(f"  … {len(flagged) - 6} more with issues in the JSON")

    R = b["routes"]["routes"]
    marks = collections.Counter(r["mark"] or "no captured flights" for r in R)
    put("")
    put(f"Routes ({len(R)}): " + (", ".join(f"{k} {v}" for k, v in marks.most_common()) or "none flown yet"))
    priced = [r for r in R if r.get("profit")]
    show = sorted(priced, key=lambda r: -(r["profit"].get("profit_week") or 0))[:3]
    show += [r for r in sorted(priced, key=lambda r: (r["profit"].get("profit_week") or 0))[:2] if r not in show]
    for r in show:
        ld = r.get("load") or {}
        put(f"  {r['hub']}–{r['dest']}: load {pct(ld.get('average'))} · {money(r['profit'].get('profit_week'))} a week · {r['mark']}"
            + (f": {r['why']}" if r.get("why") else ""))

    h = b.get("hubs")
    put("")
    if h:
        if h.get("exempt"):
            put("Hubs: exempt from hubs first" + (f" (main hub {h['main_hub']})" if h.get("main_hub") else ""))
        else:
            put(f"Hubs: {h.get('main_hub') or 'no main hub'} {h.get('departures')} of {h.get('target')} departures a week "
                f"({pct(h.get('percent'))}), {h.get('planned') or 0} more on plan cards")
        bs = h.get("bases") or []
        for s in bs[:5]:
            tr = s.get("top_rival") or {}
            put(f"  {s.get('code')} ({s.get('role')}): " + ("contested" if s.get("contested") else "not contested")
                + (f", busiest rival {tr.get('name')} {tr.get('weekly')} a week" if tr else ""))
        if len(bs) > 5:
            put(f"  … {len(bs) - 5} more bases in the JSON")
    else:
        put("Hubs: none in hub_progress()")

    D = b["deliveries"]
    put("")
    put(f"Deliveries ({len(D)})" + ("" if D else ": none on order or waiting"))
    for d in D:
        st = "arrived, not yet flying" if d.get("arrived") else f"on order, arrives {when(d.get('delivery_at'))}"
        what = " ".join(x for x in (d.get("registration") or f"aircraft {d['aircraft_id']}", d.get("type"), d.get("order_cabin") or d.get("cabin")) if x)
        put(f"  {what} at {d.get('order_base_code') or d.get('base_code') or '—'}: {st}" + ("" if d["plan_cards"] else " · no plan card yet"))
        for pc in d["plan_cards"]:
            ck = pc.get("check")
            res = "no legs" if ck is None else "check ok" if ck.get("ok") else f"{len(ck.get('problems') or [])} problem(s): {(ck.get('problems') or ['?'])[0]}"
            fw = fare_words((ck or {}).get("fares"))
            put(f"    card \"{pc.get('title') or pc['id']}\", {len(pc.get('legs') or [])} legs: {res}" + (f" · fares: {fw}" if fw else ""))

    T = b["todos"]
    put("")
    put(f"To-dos ({len(T)} open)" + ("" if T else ": none"))
    for t in sorted(T, key=lambda t: bool(t.get("group")))[:4]:   # the airline's own first, then the group's
        put(f"  {t.get('title')}" + (" (group)" if t.get("group") else "") + (f", due {when(t.get('due_on'), False)}" if t.get("due_on") else ""))
    if len(T) > 4:
        put(f"  … {len(T) - 4} more in the JSON")

    P = (b["fare_plan"] or {}).get("plan") or []
    seen = [p for p in P if p.get("applied")]
    put("")
    put(f"Fare plan: {len(P)} change(s) planned, {len(seen)} seen in the captures")
    for p in P[:3]:
        ch = p.get("change_pct")
        put(f"  {p.get('hub')}–{p.get('dest')} {p.get('cabin_class')} " + ("—" if ch is None else f"{float(ch):+g}%") + ": "
            + (f"seen {when(p.get('seen_on'), False)}" if p.get("applied") else "not seen yet"))

    # competition: the heading with the counts, the threats in one line, the top 3 openings in one (the top 20 in the JSON)
    C = b.get("competition") or {}
    put("")
    put(competition_line(C))
    T = C.get("threats") or []
    if T:
        put("  threats: " + "; ".join(f"{t.get('words')} ({when(t.get('on'), False)})" for t in T[:2])
            + (f"; +{len(T) - 2} more in the JSON" if len(T) > 2 else "") + f" · fares paused until {when(T[0].get('until'), False)}")
    if C.get("openings"):
        put("  top: " + "; ".join(f"{o.get('rank')}. {o.get('route')} {o.get('stars') or '?'}★ {o.get('distance_km') or '?'} km, rivals "
                                  f"{o.get('rivals_weekly')} a week, {(o.get('variant') or {}).get('type') or '—'}"
                                  + (f" {o['variant_note']}" if o.get("variant_note") else "")
                                  + (" (November trunk)" if o.get("trunk") else "")
                                  + ("" if o.get("allowed") else " (not yet: hubs first)") for o in C["openings"][:3]))

    V = b["rivals"]
    put("")
    if not V.get("scan_id"):
        put("Rivals: no finished world scan")
    else:
        shared = [r for r in V["routes"] if r["rivals_weekly"]]
        put(f"Rivals (scan {V['scan_id']}, {when(V['taken_at'], False)}, {V['age_days']} days old): {len(shared)} of {len(V['routes'])} routes shared"
            + ("" if V.get("in_scan") else " · " + V["note"]))
        for r in shared[:3]:
            put(f"  {r['pair']}: ours {r['ours_weekly']} a week; " + ", ".join(f"{n} {w}" for n, w in r["rivals"][:3]))
        for ap in [x for x in V["airports"] if x["rivals_weekly"]][:2]:
            put(f"  at {ap['code']}: ours {ap['ours_weekly']} departures a week; " + ", ".join(f"{n} {w}" for n, w in ap["top_rivals"][:3]))
    return "\n".join(L)


# ---------------------------------------------------------------- the command
def main(argv=None):
    ap = argparse.ArgumentParser(description="The airline briefing (decision #24): one airline's whole background before scheduling.")
    ap.add_argument("airline", help="IATA code, planner name, game name or id")
    ap.add_argument("--as-of", help="a moment (UTC, ISO), now when left out")
    ap.add_argument("--out", default=".", help="the folder for briefing_<code>.json (the current folder by default)")
    ap.add_argument("--inputs", help="saved inputs instead of the database (the checks' sample)")
    args = ap.parse_args(argv)
    try:
        if args.inputs:
            inp = json.loads(pathlib.Path(args.inputs).read_text())
        else:
            inp = pull(args.airline, args.as_of)
        with tempfile.TemporaryDirectory() as work:
            b = gather(inp, args.airline, work)
    except Refused as e:
        print("brief.py: " + str(e), file=sys.stderr)
        return 2
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"briefing_{b['airline']['code'] or b['airline']['id']}.json"
    path.write_text(json.dumps(b, indent=1, ensure_ascii=False, default=str))
    print(render(b))
    print(f"\nFull briefing: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
