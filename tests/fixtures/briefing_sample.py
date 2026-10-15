"""Cuts the airline briefing's sample (tests/briefing_test.py; tests/README.md, "The briefing sample") to what the briefing
needs, so it stays small (decision #9: small, dated samples of game data, never keys).

Usage: psql -X -q -At -v at=<moment> -f tests/fixtures/briefing_sample.sql | python3 tests/fixtures/briefing_sample.py <out.json.gz>
Run by database/rehearse.sh (BRIEFING_SAMPLE_DIR) on the rehearsal's copy; the result is the run's briefing-sample
artifact.

What is kept, each in the shape export_for_report() gives it, so scripts/briefing/brief.py reads the sample (--inputs)
as it reads the database:
- figures: Review's cards; each airline's cash forecast (without its payments, points and types), its route profit and
  aircraft profit over 7 days (every route and aircraft); the growth lists and load patterns; hubs first; the capture
  board. Not the 1- and 3-day profit, the profit by day or the fare changes, which the briefing doesn't read.
- rules: settings, world rules, aircraft types, cabins and service profiles as they are; our airlines (and any the legs
  name), their bases and aircraft, every flight leg, and only the rotations, routes and airports those use, plus the
  routes and airports the plan cards' legs use (for the cards' check).
- scan: every airline's name and departures a week; our airlines' full schedules, and the other airlines' flights that
  leave an airport any of ours serves (all the briefing's rivals count).
- briefings: each airline's briefing rows (kind briefing) as they are.
"""
import gzip, json, sys

doc = json.loads(sys.stdin.read())
out_path = sys.argv[1]

# ---------------------------------------------------------------- the figures
F = doc["figures"]
KEEP_FORECAST = ("airline_id", "home_airport", "as_of", "status", "missing", "cash", "cash_at", "profit_per_flight",
                 "flights_per_day", "flight_profit_day", "cushion", "lowest", "can_order_now", "next_order")
airlines = [{"airline_id": a.get("airline_id"), "code": a.get("code"), "name": a.get("name"),
             "cash_forecast": {k: v for k, v in (a.get("cash_forecast") or {}).items() if k in KEEP_FORECAST},
             "route_profit": {"7": (a.get("route_profit") or {}).get("7")},
             "aircraft_profit": {"7": (a.get("aircraft_profit") or {}).get("7")}}
            for a in F.get("airlines") or []]
figures = {"world_id": F.get("world_id"), "as_of": F.get("as_of"),
           "airline_cards": {k: v for k, v in (F.get("airline_cards") or {}).items() if k not in ("group_today", "group_today_shown")},
           "growth_signals": F.get("growth_signals"), "hub_progress": F.get("hub_progress"),
           "capture_status": F.get("capture_status"), "airlines": airlines}

# ---------------------------------------------------------------- the planning library's input
R = doc["rules"]
B = doc.get("briefings") or {}
card_legs = [l for b in B.values() for d in b.get("deliveries") or [] for c in d.get("plan_cards") or [] for l in c.get("legs") or []]
card_pairs = {frozenset((l["origin_code"], l["dest_code"])) for l in card_legs}
legs = R.get("flight_legs") or []
ours = {a["id"] for a in R.get("airlines") or [] if a.get("ours")}
keep_al = ours | {l["airline_id"] for l in legs}
rotations = [r for r in R.get("rotations") or [] if r["id"] in {l.get("rotation_id") for l in legs}]
used = {r["route_id"] for r in rotations}
routes = [r for r in R.get("routes") or [] if r["id"] in used or (r["airline_id"] in ours and frozenset((r["hub_code"], r["dest_code"])) in card_pairs)]
bases = [b for b in R.get("airline_bases") or [] if b["airline_id"] in keep_al]
aircraft = [a for a in R.get("aircraft") or [] if a["airline_id"] in keep_al]
codes = ({l["origin_code"] for l in legs} | {l["dest_code"] for l in legs} | {r["hub_code"] for r in routes} | {r["dest_code"] for r in routes}
         | {b["airport_code"] for b in bases} | {a["base_code"] for a in aircraft if a.get("base_code")}
         | {l["origin_code"] for l in card_legs} | {l["dest_code"] for l in card_legs})
rules = dict(R, airlines=[a for a in R.get("airlines") or [] if a["id"] in keep_al], airline_bases=bases, aircraft=aircraft,
             rotations=rotations, routes=routes, airports=[a for a in R.get("airports") or [] if a["code"] in codes])

# ---------------------------------------------------------------- the world scan
S = doc.get("scan") or None
scan = None
if S:
    our_games = {a.get("game_id") for a in rules["airlines"] if a.get("ours") and a.get("game_id") is not None}
    served = set(codes)
    for a in S.get("airlines") or []:
        if a.get("id") in our_games:
            for f in a.get("flights") or []:
                served.update(f[2:4])
    scan = {"id": S.get("id"), "taken_at": S.get("taken_at"),
            "airlines": [{"id": a.get("id"), "name": a.get("name"), "n_weekly": a.get("n_weekly"),
                          "flights": (a.get("flights") or []) if a.get("id") in our_games
                          else [f for f in a.get("flights") or [] if f[2] in served]}
                         for a in S.get("airlines") or []]}

sample = {"frozen_at": doc["frozen_at"], "made_from": doc["made_from"] + "; cut by tests/fixtures/briefing_sample.py",
          "as_of": doc["frozen_at"], "figures": figures, "rules": rules, "scan": scan, "briefings": B}
text = json.dumps(sample, separators=(",", ":"), ensure_ascii=False)
with open(out_path, "wb") as fh:
    with gzip.GzipFile(fileobj=fh, mode="wb", compresslevel=9, mtime=0) as gz:
        gz.write(text.encode())
print(f"briefing sample: {len(airlines)} airlines' figures and briefing rows "
      f"({sum(len(b.get('deliveries') or []) for b in B.values())} deliveries, {sum(len(b.get('todos') or []) for b in B.values())} to-dos), "
      f"{len(rules['flight_legs'])} legs, {len(rules['aircraft'])} aircraft, {len(rules['airports'])} airports, "
      f"scan {scan and scan['id']} ({sum(len(a['flights']) for a in (scan or {}).get('airlines') or [])} flights); {len(text) // 1024} KB before compression")
