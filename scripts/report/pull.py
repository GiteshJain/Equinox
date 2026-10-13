"""The weekly report, step 1 (scripts/README.md): downloads what the report reads, into the current folder.

- figures.json: every captured figure for every airline, now (export_for_report kind figures, decision #19): cash, the
  cash forecast's lowest point and next order, profit a day, route profit, growth signals, hubs first;
- rules.json: the planning library's input (kind rules): our airlines, their game IDs and bases, aircraft, every leg;
- airlines.json, airports.json and scan.json: the latest finished world scan (every airline with its schedule, the
  scanned airports, and which scan it is), for competition and markets;
- site_airlines.json: the website's airlines (site_public()), for each airline's colour in the charts.
Needs ~/.sb_anon (the public key) and ~/.ingest_secret.
"""
import json, os, urllib.request

URL = "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/"
KEY = open(os.path.expanduser("~/.sb_anon")).read().strip()
SEC = open(os.path.expanduser("~/.ingest_secret")).read().strip()


def rpc(name, body):
    req = urllib.request.Request(URL + name, data=json.dumps(body).encode(),
                                 headers={"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read())


def ex(kind, arg=None):
    return rpc("export_for_report", {"p_secret": SEC, "p_kind": kind, "p_arg": arg})


snaps = ex("snapshots"); print("snapshots:", [(s["id"], s["status"]) for s in snaps][-5:])
sid = str(max(s["id"] for s in snaps if s["status"] == "done"))
json.dump(ex("airlines", sid), open("airlines.json", "w"))
json.dump(ex("airports", sid), open("airports.json", "w"))
json.dump({"id": int(sid), "taken_at": next(s["taken_at"] for s in snaps if str(s["id"]) == sid)}, open("scan.json", "w"))   # which scan: analyze.py sends its market summaries for it
json.dump(ex("figures", "{}"), open("figures.json", "w"))   # as of now; {"as_of": "<moment>"} for another moment
json.dump(ex("rules", ""), open("rules.json", "w"))
json.dump(rpc("site_public", {}).get("airlines") or [], open("site_airlines.json", "w"))
for f in ("airlines.json", "airports.json", "scan.json", "figures.json", "rules.json", "site_airlines.json"):
    print(f, os.path.getsize(f))
