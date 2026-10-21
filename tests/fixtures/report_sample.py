"""Cuts the weekly report's sample (tests/report_test.py; tests/README.md, "The report sample") to what the report needs,
so it stays small (decision #9: small, dated samples of game data, never keys).

Usage: psql -X -q -At -v at=<moment> -f tests/fixtures/report_sample.sql | python3 tests/fixtures/report_sample.py <out.json.gz>
Run by database/rehearse.sh (REPORT_SAMPLE_DIR) on the rehearsal's copy; the result is the run's report-sample artifact.

What is kept, each in the shape export_for_report() gives it, so the report's scripts read the sample as they read the
real files:
- figures: every airline's cash forecast (without each payment and type, but with its points, lowest point and next
  order), its profit for the last 14 days between captures, and its route profit over 7 days (the best 6 and worst 4
  routes), and since 22 Oct its three biggest competitors with itself and the scans (competition()'s competitors, self
  and scans); Review's cards; hubs first; the growth lists (the first 8 of each). Not the 1- and 3-day route profit, the
  aircraft, the fare changes, the load patterns, the capture board or the group today, which the report doesn't use.
- rules: settings, world rules, aircraft types and cabins as they are; our airlines (and any the legs name), their bases
  and aircraft, every flight leg, and only the rotations, routes and airports those use (not the route research).
- scan: every airline's name and departures a week; the full schedules of our airlines and of the 12 rivals flying most
  at airports we serve, those rivals' flights cut to the ones touching those airports; our bases' airport pages, with
  our airlines and the 10 biggest others at each, and the latest 5 news items.
- site_airlines: the website's airlines (names, codes, colours).
"""
import gzip, json, sys

doc = json.loads(sys.stdin.read())
out_path = sys.argv[1]

# ---------------------------------------------------------------- the figures
F = doc["figures"]
KEEP_FORECAST = ("airline_id", "home_airport", "as_of", "status", "missing", "cash", "cash_at", "profit_per_flight",
                 "flights_per_day", "flight_profit_day", "cushion", "points", "lowest", "can_order_now", "next_order")


def routes_cut(rp):
    if not isinstance(rp, dict):
        return rp
    routes = rp.get("routes") or []
    best, worst = routes[:6], [r for r in routes[-4:] if r not in routes[:6]]
    return dict({k: v for k, v in rp.items() if k != "routes"}, routes=best + worst)


airlines = []
for a in F.get("airlines") or []:
    airlines.append({
        "airline_id": a.get("airline_id"), "code": a.get("code"), "name": a.get("name"),
        "cash_forecast": {k: v for k, v in (a.get("cash_forecast") or {}).items() if k in KEEP_FORECAST},
        "airline_profit": (a.get("airline_profit") or [])[-14:],
        "route_profit": {"7": routes_cut((a.get("route_profit") or {}).get("7"))},
        # the weekly report's three biggest competitors (manual §7), when the figures have them (since 22 Oct)
        **{k: a[k] for k in ("competitors", "self", "scans") if k in a},
    })
G = F.get("growth_signals") or {}
figures = {
    "world_id": F.get("world_id"), "as_of": F.get("as_of"),
    "airline_cards": {k: v for k, v in (F.get("airline_cards") or {}).items() if k not in ("group_today", "group_today_shown")},
    "growth_signals": dict({k: v for k, v in G.items() if not isinstance(v, (list, dict))},
                           **{k: v[:8] for k, v in G.items() if isinstance(v, list)}),
    "hub_progress": F.get("hub_progress"),
    "airlines": airlines,
}

# ---------------------------------------------------------------- the planning library's input
R = doc["rules"]
legs = R.get("flight_legs") or []
named = {l["airline_id"] for l in legs}
ours = {a["id"] for a in R.get("airlines") or [] if a.get("ours")}
keep_al = ours | named
rotations = [r for r in R.get("rotations") or [] if r["id"] in {l.get("rotation_id") for l in legs}]
routes = [r for r in R.get("routes") or [] if r["id"] in {r2["route_id"] for r2 in rotations}]
bases = [b for b in R.get("airline_bases") or [] if b["airline_id"] in keep_al]
aircraft = [a for a in R.get("aircraft") or [] if a["airline_id"] in keep_al]
codes = ({l["origin_code"] for l in legs} | {l["dest_code"] for l in legs} | {r["hub_code"] for r in routes}
         | {r["dest_code"] for r in routes} | {b["airport_code"] for b in bases} | {a["base_code"] for a in aircraft if a.get("base_code")})
rules = dict(R, airlines=[a for a in R.get("airlines") or [] if a["id"] in keep_al], airline_bases=bases, aircraft=aircraft,
             rotations=rotations, routes=routes, airports=[a for a in R.get("airports") or [] if a["code"] in codes])

# ---------------------------------------------------------------- the world scan
S = doc.get("scan") or {}
our_games = {a.get("game_id") for a in rules["airlines"] if a.get("ours") and a.get("game_id") is not None}
served = set()
for a in S.get("airlines") or []:
    if a.get("id") in our_games:
        for f in a.get("flights") or []:
            served.update(f[2:4])
touching = lambda a: [f for f in (a.get("flights") or []) if f[2] in served or f[3] in served]   # noqa: E731
rivals = sorted((a for a in S.get("airlines") or [] if a.get("id") not in our_games),
                key=lambda a: -sum(len(f[4] or "") for f in touching(a)))[:12]
rival_ids = {a["id"] for a in rivals}
scan_airlines = [{"id": a.get("id"), "name": a.get("name"), "n_weekly": a.get("n_weekly"),
                  "flights": (a.get("flights") or []) if a.get("id") in our_games else touching(a) if a.get("id") in rival_ids else []}
                 for a in S.get("airlines") or []]
base_codes = {b["airport_code"] for b in bases if b["airline_id"] in ours}
scan_airports = []
for p in S.get("airports") or []:
    if p.get("code") not in base_codes:
        continue
    st = sorted(p.get("stations") or [], key=lambda s: -(s.get("weekly") or 0))
    keep = [s for s in st if s.get("enterprise_id") in our_games] + [s for s in st if s.get("enterprise_id") not in our_games][:10]
    scan_airports.append(dict(p, stations=[s for s in st if s in keep], news=(p.get("news") or [])[:5]))
scan = {"id": S.get("id"), "taken_at": S.get("taken_at"), "airlines": scan_airlines, "airports": scan_airports}

sample = {"frozen_at": doc["frozen_at"], "made_from": doc["made_from"] + "; cut by tests/fixtures/report_sample.py",
          "figures": figures, "rules": rules, "scan": scan, "site_airlines": doc.get("site_airlines") or []}
text = json.dumps(sample, separators=(",", ":"), ensure_ascii=False)
with open(out_path, "wb") as fh:
    with gzip.GzipFile(fileobj=fh, mode="wb", compresslevel=9, mtime=0) as gz:
        gz.write(text.encode())
print(f"report sample: {len(figures['airlines'])} airlines' figures, {len(rules['flight_legs'])} legs, {len(rules['aircraft'])} aircraft, "
      f"{len(rules['airports'])} airports, scan {scan['id']} ({sum(1 for a in scan_airlines if a['flights'])} schedules, "
      f"{len(scan_airports)} airport pages); {len(text) // 1024} KB before compression")
