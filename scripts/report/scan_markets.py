"""The weekly report's market summaries of world scans, kept for good (design §3.9, §11 choice 2: scan_airline_markets).

analyze.py sends them for the scan pull.py downloaded. This fills any scan, or fills it again after a change to the
market definitions, which are analyze.py's (read from beside this file, as nl_analyze.py reads them):

    python3 scan_markets.py [scan id ...]      no ids: every finished scan whose schedules are still kept (one month)

Run it from the weekly report's working folder: it needs airports_oa.csv there, and ~/.sb_anon and ~/.ingest_secret.
Each scan's summaries replace any it had (ingest_snapshot(), kind markets)."""
import collections, csv, json, pathlib, sys, urllib.request

URL = "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/"


def rpc(fn, body):
    key = open('/home/claude/.sb_anon').read().strip()
    req = urllib.request.Request(URL + fn, data=json.dumps(body).encode(),
                                 headers={"apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read() or b'null')


def send(scan_id, rows):
    """Stores one scan's market summaries, replacing any it had: rows of {enterprise_id, market, weekly_departures,
    city_pairs}, as analyze.py's market_summaries() makes them. Answers {ok, rows}."""
    secret = open('/home/claude/.ingest_secret').read().strip()
    return rpc("ingest_snapshot", {"p_secret": secret, "p_kind": "markets",
                                   "p_payload": {"snapshot_id": int(scan_id), "markets": rows}})


def definitions(airports_csv='airports_oa.csv'):
    """analyze.py's market definitions (region(), market(), seats(), market_summaries()) and the airports they read."""
    g = {"collections": collections, "ap": {}}
    for r in csv.DictReader(open(airports_csv, encoding='utf-8')):
        if r['iata_code']:
            g['ap'][r['iata_code']] = (r['iso_country'], r['continent'], float(r['latitude_deg'] or 0),
                                       float(r['longitude_deg'] or 0), r['municipality'] or r['name'])
    src = (pathlib.Path(__file__).resolve().parent / 'analyze.py').read_text()
    exec(src[src.index('REG={}'):src.index('# ---------- world markets')], g)
    return g


if __name__ == "__main__":
    g = definitions()
    secret = open('/home/claude/.ingest_secret').read().strip()
    ex = lambda kind, arg=None: rpc("export_for_report", {"p_secret": secret, "p_kind": kind, "p_arg": arg})
    ids = sys.argv[1:] or [str(s['id']) for s in ex('snapshots') if s['status'] == 'done']
    for sid in ids:
        airlines = ex('airlines', sid)
        if not airlines or any(a.get('flights') is None for a in airlines):
            print(f"scan {sid}: no schedules kept (archived, or an empty scan): skipped")
            continue
        answer = send(sid, g['market_summaries'](airlines))
        print(f"scan {sid}: {answer.get('rows')} market summaries stored, from {len(airlines)} airlines")
