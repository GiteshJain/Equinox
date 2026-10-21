"""The weekly report, step 2 (scripts/README.md): works out the briefing's numbers into results.json.

Reads, from the current folder, what pull.py downloaded:
- rules.json (the planning library's input): our airlines, their game IDs, names and bases (airlines, airline_bases);
  nothing about them is typed in here, and nothing assumes six (#14). Each airline's aircraft, routes, flights, seats
  and block hours a day come from its stored legs through the library's aircraftWeek (node lib/rules/dist/cli.js
  aircraft rules.json), the same figures as the planner's Tails screen;
- figures.json (the captured figures, #19): all the money. Cash, profit a day, flight profit a day, the lowest point in
  the next 14 days and when, the next order, route profit, the growth signals and hubs first, each airline on its own:
  no surplus figure and no group totals (manual §1, §3); and since 22 Oct each airline against its three biggest
  competitors (competition()'s competitors, self and scans; manual §7);
- airlines.json, airports.json, scan.json (the world scan) and airports_oa.csv (OurAirports' public airport list): the
  competition, markets and hubs, as before;
- site_airlines.json (the website's airlines), if there: each airline's colour for the charts.
Then sends the scan's market summaries through ingest_snapshot() (kind markets, report/scan_markets.py beside this
file). --no-send leaves that out (the report test uses it).

Usage, from the working folder: python3 <repository>/scripts/report/analyze.py [--no-send]
The library's command is found beside this file's repository (lib/rules/dist/cli.js, made by npm run build), or at
$EQUINOX_RULES_CLI.
"""
import collections, csv, json, os, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
FIG = json.load(open("figures.json")); RUL = json.load(open("rules.json"))
A = json.load(open("airlines.json")); AP = json.load(open("airports.json"))
SCAN = json.load(open("scan.json")) if os.path.exists("scan.json") else {}
SITE = json.load(open("site_airlines.json")) if os.path.exists("site_airlines.json") else []

# ---------- our airlines, from rules.json: ours and active, in display order
OURS_ROWS = sorted((a for a in RUL["airlines"] if a.get("ours") and a.get("active") is not False),
                   key=lambda a: (a.get("position") is None, a.get("position") or 0, a["id"]))
NAME = {a["id"]: a.get("public_name") or a.get("planner_name") or a.get("game_name") or a.get("iata_code") or f"Airline {a['id']}" for a in OURS_ROWS}
OURS = {a["game_id"]: NAME[a["id"]] for a in OURS_ROWS if a.get("game_id") is not None}      # the scan's airline ID -> our name
BY_GAME = {a["game_id"]: a["id"] for a in OURS_ROWS if a.get("game_id") is not None}
PALETTE = ["#2A8FD8", "#D7263D", "#F1C21B", "#8E1537", "#1C3F8C", "#0F8C8C", "#6B4FA0", "#E07B39", "#3E8E41", "#7A7F87"]


def colour(a, i):
    """The airline's colour from the website's airlines (site_public(), the airlines table), else a palette colour."""
    for s in SITE:
        if s.get("color") and (s.get("key") == a.get("planner_name") or (s.get("code") and s.get("code") == a.get("iata_code"))):
            return s["color"]
    return PALETTE[i % len(PALETTE)]


BASES = sorted((b for b in RUL.get("airline_bases") or [] if b["airline_id"] in NAME),
               key=lambda b: (b.get("position") is None, b.get("position") or 0, b["id"]))

# ---------- airports -> country/region
ap = {}
for r in csv.DictReader(open("airports_oa.csv", encoding="utf-8")):
    if r["iata_code"]:
        ap[r["iata_code"]] = (r["iso_country"], r["continent"], float(r["latitude_deg"] or 0), float(r["longitude_deg"] or 0), r["municipality"] or r["name"])
# The market definitions. scan_markets.py, gander monthly's nl_analyze.py and the airline briefing run this block as it
# is, from the line starting "REG={}" to the line starting "# ---------- world markets", each found at the start of a
# line since this comment names them too: keep both markers and keep it standalone (it needs only ap and collections).
REG={}
def setr(codes, reg):
    for c in codes.split(): REG[c]=reg
setr("US CA","NA")
setr("MX GT BZ SV HN NI CR PA CU JM HT DO PR BS BB TT AW CW KY TC VG VI AG LC GD VC KN DM MQ GP BQ SX MF BL BM","MXC")
setr("BR AR CL PE CO EC VE BO PY UY GY SR GF FK","SAM")
setr("GB IE FR DE NL BE LU CH AT IT ES PT DK NO SE FI IS PL CZ SK HU SI HR BA RS ME MK AL GR CY MT RO BG EE LV LT TR FO GI AD MC SM LI XK GL","EUR")
setr("RU UA BY MD GE AM AZ KZ UZ KG TJ TM","CIS")
setr("AE QA SA OM BH KW IL JO LB SY IQ IR YE PS","ME")
setr("IN PK BD LK NP MV BT AF","SAS"); setr("CN","CHN"); setr("JP KR KP MN TW HK MO","NEA")
setr("MY SG TH ID PH VN KH LA MM BN TL","SEA"); setr("AU NZ","OCE")
CONT={'AF':'AFR','OC':'OCE','SA':'SAM','EU':'EUR','NA':'MXC','AS':'SEA'}
def region(code):
    a=ap.get(code)
    if not a: return None, None
    return a[0], REG.get(a[0], CONT.get(a[1], 'OTH'))
DOM={'US':'US domestic','CN':'China domestic','IN':'India domestic','JP':'Japan domestic','BR':'Brazil domestic','AU':'Australia domestic','CA':'Canada domestic','ID':'Indonesia domestic','RU':'Russia domestic','MX':'Mexico domestic'}
RN={'NA':'North America','MXC':'Mexico & Caribbean','SAM':'South America','EUR':'Europe','CIS':'Russia & CIS','ME':'Middle East','AFR':'Africa','SAS':'South Asia','CHN':'China','NEA':'NE Asia','SEA':'SE Asia','OCE':'Oceania','OTH':'Other'}
PAIR={frozenset(['NA','EUR']):'Transatlantic',frozenset(['NA','MXC']):'US/Canada–Mexico & Caribbean',frozenset(['NA','SAM']):'North–South America',
 frozenset(['EUR','CHN']):'Europe–East Asia',frozenset(['EUR','NEA']):'Europe–East Asia',frozenset(['EUR','SEA']):'Europe–SE Asia',frozenset(['EUR','SAS']):'Europe–South Asia',
 frozenset(['EUR','ME']):'Europe–Middle East',frozenset(['SAS','ME']):'South Asia–Gulf',frozenset(['CHN','ME']):'East Asia–Gulf',frozenset(['NEA','ME']):'East Asia–Gulf',frozenset(['SEA','ME']):'SE Asia–Gulf',
 frozenset(['CHN','NEA']):'China–NE Asia',frozenset(['CHN','SEA']):'China–SE Asia',frozenset(['NEA','SEA']):'NE Asia–SE Asia',frozenset(['SAS','SEA']):'South Asia–SE Asia',frozenset(['SAS','CHN']):'South Asia–China',
 frozenset(['SAS','NEA']):'South Asia–NE Asia',frozenset(['SEA','OCE']):'Asia–Oceania',frozenset(['CHN','OCE']):'Asia–Oceania',frozenset(['NEA','OCE']):'Asia–Oceania',frozenset(['SAS','OCE']):'Asia–Oceania',
 frozenset(['NA','CHN']):'Transpacific',frozenset(['NA','NEA']):'Transpacific',frozenset(['NA','SEA']):'Transpacific',frozenset(['NA','SAS']):'North America–South Asia',frozenset(['NA','OCE']):'Transpacific',
 frozenset(['EUR','AFR']):'Europe–Africa',frozenset(['EUR','CIS']):'Europe–Russia & CIS',frozenset(['NA','ME']):'North America–Middle East',frozenset(['EUR','MXC']):'Europe–Latin America',frozenset(['EUR','SAM']):'Europe–Latin America'}
def market(a,b):
    ca,ra=region(a); cb,rb=region(b)
    if not ra or not rb: return 'Unknown'
    if ca==cb and ca in DOM: return DOM[ca]
    if ra==rb:
        if ra=='NA': return 'US–Canada'
        return 'Intra-'+RN[ra]
    return PAIR.get(frozenset([ra,rb]), f"{RN[ra]}–{RN[rb]}" if ra<rb else f"{RN[rb]}–{RN[ra]}")
SEATS={'32Q':190,'32N':165,'CS3':135,'7M8':172,'7MX':200,'319':135,'738':170,'7M9':180,'321':190,'E90':100,'320':160,'295':130,'73G':135,'DH4':76,'290':106,'752':200,'ER4':50,'E75':78,'CR9':80,'919':160,'339':290,'SU9':95,'AT7':70,'359':310,'CS1':115,'E95':120,'333':290,'75T':240,'CR7':70,'763':230,'7M7':150,'788':250,'C27':90,'DH3':50,'351':350,'733':140,'EM2':30,'789':290,'73J':180,'75W':200,'772':320,'739':180,'343':280,'781':330,'77W':360,'388':500,'744':400,'332':250,'318':110,'734':150,'735':120,'73H':170,'E70':72,'CR2':50,'AT4':48,'DH8':40,'77L':320,'346':330,'342':260,'764':240,'762':200,'M88':150,'M90':155,'717':110,'100':100}
def seats(t):
    if not t or t.endswith('F') or t in ('ATF','ABX','74Y','77X','76X'): return 0
    return SEATS.get(t,150)
def market_summaries(A):   # per airline and market: passenger departures a week and city pairs, as the market table below counts them (kept for good in scan_airline_markets)
    out=collections.defaultdict(lambda:[0,set()])
    for a in A:
        for f in a['flights'] or []:
            n=len(f[4])
            if not n or seats(f[7])==0: continue
            k=(a['id'],market(f[2],f[3])); out[k][0]+=n; out[k][1].add(frozenset((f[2],f[3])))
    return [{"enterprise_id":i,"market":m,"weekly_departures":w,"city_pairs":len(p)} for (i,m),(w,p) in sorted(out.items(), key=lambda kv:kv[0])]
# ---------- world markets (the group's share of each, and who carries it: manual §7, competition for the group and each airline)
mk = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0]))   # market -> airline -> [flights/wk, seats/wk]
pairs = collections.defaultdict(lambda: collections.defaultdict(int))        # undirected pair -> airline -> flights/wk
names = {a["id"]: a["name"] for a in A}
for a in A:
    for f in a["flights"] or []:
        n = len(f[4])
        if not n:
            continue
        m = market(f[2], f[3]); s = seats(f[7])
        if s == 0:
            continue
        mk[m][a["id"]][0] += n; mk[m][a["id"]][1] += n * s
        pairs[frozenset((f[2], f[3]))][a["id"]] += n
label = lambda k: OURS.get(k) or names.get(k) or str(k)   # noqa: E731
mtab = []
for m, d in mk.items():
    tot = sum(v[1] for v in d.values()); totf = sum(v[0] for v in d.values())
    ours = sum(v[1] for k, v in d.items() if k in OURS)
    top = sorted(d.items(), key=lambda kv: -kv[1][1])
    mtab.append({"market": m, "seats": tot, "flights": totf, "our_seats": ours, "our_share": ours / tot if tot else 0,
                 "top": [(label(k), v[1], v[1] / tot, k in OURS) for k, v in top[:6]],
                 "top_rival": next(((label(k), v[1], v[1] / tot) for k, v in top if k not in OURS), None),
                 "ours_by": [(OURS[k], v[1], v[1] / tot) for k, v in top if k in OURS],
                 "rank_ours": next((i + 1 for i, (k, v) in enumerate(top) if k in OURS), None), "n_airlines": len(d)})
mtab.sort(key=lambda x: -x["seats"])
# ---------- our bases at their airports (each airline's own departures against the biggest rivals there)
hubtab = []
for b in BASES:
    a = next((x for x in AP if x["code"] == b["airport_code"]), None)
    if not a:
        continue
    gid = next((g for g, i in BY_GAME.items() if i == b["airline_id"]), None)
    st = sorted([s for s in a["stations"] or [] if (s.get("weekly") or 0) > 0], key=lambda s: -s["weekly"]); tot = sum(s["weekly"] for s in st)
    me = next((s for s in st if s["enterprise_id"] == gid), None)
    hubtab.append({"hub": b["airport_code"], "role": b.get("role"), "main": bool(b.get("is_main")), "airline_id": b["airline_id"], "airline": NAME[b["airline_id"]],
                   "ours": me["weekly"] if me else 0, "total": tot, "share": (me["weekly"] / tot if me and tot else 0),
                   "rank": next((i + 1 for i, s in enumerate(st) if s["enterprise_id"] == gid), None),
                   "rivals": [(s["name"], s["weekly"]) for s in st if s["enterprise_id"] not in OURS][:4], "info": a.get("info"), "news": a.get("news")})
# ---------- head-to-head routes
h2h = []
for p, d in pairs.items():
    o = {k: v for k, v in d.items() if k in OURS}
    if not o:
        continue
    c = {k: v for k, v in d.items() if k not in OURS}
    if not c:
        continue
    a1, a2 = sorted(p)
    h2h.append({"pair": f"{a1}–{a2}", "ours": [(OURS[k], v) for k, v in o.items()], "ours_w": sum(o.values()),
                "comp": sorted([(names.get(k, str(k)), v) for k, v in c.items()], key=lambda x: -x[1]), "comp_w": sum(c.values())})
h2h.sort(key=lambda x: -x["comp_w"])
ourpairs = sum(1 for p, d in pairs.items() if any(k in OURS for k in d)); contested = len(h2h)
# rivals per our airline: competitor flights on its airport pairs
riv = collections.defaultdict(lambda: collections.Counter())
for p, d in pairs.items():
    for k in d:
        if k in OURS:
            for c, v in d.items():
                if c not in OURS:
                    riv[OURS[k]][names.get(c, str(c))] += v
# ---------- world ranking, each airline on its own
rank = sorted([(label(a["id"]), a["n_weekly"] or 0, a["id"] in OURS) for a in A], key=lambda x: -x[1])


# ---------- each airline's network, from its stored legs through the planning library (aircraftWeek)
def rules_cli():
    for p in [os.environ.get("EQUINOX_RULES_CLI"), HERE.parent.parent / "lib" / "rules" / "dist" / "cli.js", pathlib.Path("lib/rules/dist/cli.js")]:
        if p and pathlib.Path(p).is_file():
            return str(p)
    sys.exit("the planning library's command isn't built: run npm ci && npm run build in the repository (or set EQUINOX_RULES_CLI)")


r = subprocess.run(["node", rules_cli(), "aircraft", "rules.json"], capture_output=True, text=True, timeout=600)
if r.returncode:
    sys.exit("the planning library's command failed: " + (r.stderr.strip().splitlines() or ["no output"])[-1])
WEEKS = json.loads(r.stdout)
types = {t["id"]: t for t in RUL.get("aircraft_types") or []}
cabins = {c["id"]: c for c in RUL.get("cabin_configs") or []}
fleet = {a["id"]: a for a in RUL.get("aircraft") or []}


def seats_of(ac):
    c = cabins.get(ac.get("cabin_config_id")) if ac else None
    if c and c.get("seats"):
        return c["seats"]
    t = types.get(ac.get("aircraft_type_id")) if ac else None
    return (t or {}).get("seats_max") or 0


def ops_of(airline_id):
    mine = [w for w in WEEKS if w["airline_id"] == airline_id]
    active = [a for a in fleet.values() if a["airline_id"] == airline_id and a.get("status") == "active"]
    flying = [w for w in mine if w["legs_week"]]
    block_day = sum(w["block_min_week"] for w in mine) / 60 / 7
    return {"aircraft": len(active), "flying": len(flying),
            "on_order": sum(1 for a in fleet.values() if a["airline_id"] == airline_id and a.get("status") in ("on_order", "delivered")),
            "routes": len({rid for w in mine for rid in w.get("route_ids") or []}),
            "flights_day": sum(w["legs_week"] for w in mine) / 7,
            "seats_day": sum(w["legs_week"] * seats_of(fleet.get(w["aircraft_id"])) for w in mine) / 7,
            "block_hours_day": block_day, "block_hours_per_aircraft": block_day / len(flying) if flying else None,
            "types": dict(collections.Counter((types.get(a.get("aircraft_type_id")) or {}).get("name") or "unknown" for a in active))}


# ---------- each airline's money, from the captured figures (manual §3: the cash forecast; no surplus, no group totals)
FA = {a["airline_id"]: a for a in FIG.get("airlines") or []}
CARDS = {c["airline_id"]: c for c in (FIG.get("airline_cards") or {}).get("airlines") or []}
HUBP = {h["airline_id"]: h for h in (FIG.get("hub_progress") or {}).get("airlines") or []}


def finance_of(airline_id):
    f = FA.get(airline_id) or {}; c = CARDS.get(airline_id) or {}; fc = f.get("cash_forecast") or {}
    low = fc.get("lowest") or {}
    return {"status": fc.get("status") or "no capture", "missing": fc.get("missing"),
            "cash": fc.get("cash"), "cash_at": fc.get("cash_at"),
            "profit_day": c.get("profit_day"), "profit_span_days": c.get("span_days"), "early": c.get("early"),
            "per_aircraft_day": c.get("per_aircraft_day"), "load_7_days": c.get("load_7_days"),
            "flight_profit_day": fc.get("flight_profit_day"),
            "lowest": {"balance": low.get("balance"), "at": low.get("at"), "payment": (low.get("payment") or {}).get("what")} if low else None,
            "cushion": fc.get("cushion"),
            "next_order": c.get("next_order") or fc.get("next_order") or {"when": "needs", "missing": "a capture"},
            "points": fc.get("points") or [],
            "profit_days": [{"date": d.get("date"), "profit_day": d.get("profit_day"), "days": d.get("days")} for d in (f.get("airline_profit") or [])][-7:]}


def routes_of(airline_id):
    rp = ((FA.get(airline_id) or {}).get("route_profit") or {}).get("7") or {}
    routes = rp.get("routes") or []
    keep = ("hub", "dest", "flights", "profit_week", "profit_per_flight", "economy", "mark", "why")
    best = [{k: x.get(k) for k in keep} for x in routes[:3]]
    weak = sorted((x for x in routes if x not in routes[:3]), key=lambda x: (x.get("profit_per_flight") is None, x.get("profit_per_flight") or 0))[:2]
    return {"days": rp.get("days"), "since": rp.get("since"), "flights": rp.get("flights"), "best": best, "weak": [{k: x.get(k) for k in keep} for x in weak]}


def competitors_of(airline_id):
    """The airline against its three biggest competitors (manual §7), as competition() gives them in figures.json (since
    22 Oct): the three rivals with the most departures a week on its city pairs in the latest scan, and the airline itself,
    each with its network and the change against the week-before scan. None when the figures have no world scan to
    compare (or predate them): the report says so."""
    f = FA.get(airline_id) or {}
    scans = f.get("scans") or {}
    if "competitors" not in f or not scans.get("latest"):
        return None
    keep = ("rank", "airline_id", "name", "on_pairs", "pairs", "weekly", "airports", "weekly_before", "change", "change_pct")
    return {"latest": scans["latest"].get("taken_at"), "week_before": (scans.get("week_before") or {}).get("taken_at"),
            "self": {k: (f.get("self") or {}).get(k) for k in keep[3:] + ("pairs_flown",)},
            "top": [{k: c.get(k) for k in keep} for c in (f.get("competitors") or [])[:3]]}


G = FIG.get("growth_signals") or {}
growth = {k: [dict({kk: x.get(kk) for kk in ("hub", "dest", "flights", "profit_week", "profit_per_flight", "economy", "mark", "why", "registration", "type", "net_day")},
                   airline=NAME.get(x.get("airline_id"), str(x.get("airline_id")))) for x in (G.get(k) or [])[:6]]
          for k in ("ready_for_another_flight", "raise_fares", "fix_or_reduce", "aircraft_losing_after_lease")}
growth["days"] = G.get("days")

airlines = []
for i, a in enumerate(OURS_ROWS):
    hp = HUBP.get(a["id"]) or {}
    airlines.append({"id": a["id"], "game_id": a.get("game_id"), "code": a.get("iata_code"), "name": NAME[a["id"]], "color": colour(a, i),
                     "bases": [b["airport_code"] for b in BASES if b["airline_id"] == a["id"]],
                     "main_hub": next((b["airport_code"] for b in BASES if b["airline_id"] == a["id"] and b.get("is_main")), None),
                     "ops": ops_of(a["id"]), "finance": finance_of(a["id"]), "routes": routes_of(a["id"]), "competitors": competitors_of(a["id"]),
                     "hubs_first": {k: hp.get(k) for k in ("main_hub", "departures", "planned", "target", "percent", "exempt")} | {
                         "bases": [{"code": b.get("code"), "role": b.get("role"), "contested": b.get("contested"),
                                    "top_rival": b.get("top_rival"), "contested_routes": len(b.get("contested_routes") or [])} for b in hp.get("bases") or []]}})
json.dump({"as_of": FIG.get("as_of"), "scan": {"id": SCAN.get("id"), "taken_at": SCAN.get("taken_at")},
           "airlines": airlines, "growth": growth,
           "mtab": mtab, "hubtab": hubtab, "h2h": h2h[:60], "ourpairs": ourpairs, "contested": contested,
           "rivals": {k: v.most_common(8) for k, v in riv.items()},
           "rank": rank[:30], "our_rank": [(i + 1, n, w) for i, (n, w, o) in enumerate(rank) if o],
           "world": {"airlines": len(A), "flying": sum(1 for a in A if a["n_weekly"]), "weekly": sum(a["n_weekly"] or 0 for a in A)}},
          open("results.json", "w"), default=str)
print("airlines:", ", ".join(a["name"] for a in airlines), "| figures as of", FIG.get("as_of"))
print("markets:", len(mtab), "| our markets:", sum(1 for m in mtab if m["our_seats"] > 0), "| our pairs:", ourpairs, "contested:", contested)
for m in mtab[:40]:
    if m["our_seats"] > 0:
        print(f"{m['market']:34s} seats/wk {m['seats']:>9,} ours {m['our_share'] * 100:5.1f}% rank {m['rank_ours']} of {m['n_airlines']} | top: " + ", ".join(f"{n} {s * 100:.0f}%" for n, _, s, _o in m["top"][:4]))
print("unknown share:", next((m["seats"] for m in mtab if m["market"] == "Unknown"), 0))
# the scan's market summaries, kept for good (scan_airline_markets): sent for the scan pull.py downloaded (scan.json)
if SCAN.get("id") and "--no-send" not in sys.argv:
    try:
        sys.path.insert(0, str(HERE))
        import scan_markets
        print("market summaries for scan", SCAN["id"], ":", scan_markets.send(SCAN["id"], market_summaries(A)))
    except Exception as e:
        print("market summaries NOT sent:", e, "(run scan_markets.py <scan id> later)")
