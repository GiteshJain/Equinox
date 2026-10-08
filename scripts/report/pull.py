import json, urllib.request
KEY=open('/home/claude/.sb_anon').read().strip(); SEC=open('/home/claude/.ingest_secret').read().strip()
def ex(kind, arg=None):
    req=urllib.request.Request("https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/export_for_report", data=json.dumps({"p_secret":SEC,"p_kind":kind,"p_arg":arg}).encode(), headers={"apikey":KEY,"Authorization":"Bearer "+KEY,"Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=120) as r: return json.loads(r.read())
snaps=ex('snapshots'); print("snapshots:", snaps)
sid=str(max(s['id'] for s in snaps if s['status']=='done'))
json.dump(ex('airlines', sid), open('airlines.json','w')); json.dump(ex('airports', sid), open('airports.json','w')); json.dump(ex('planner'), open('planner.json','w'))
import os
for f in ('airlines.json','airports.json','planner.json'): print(f, os.path.getsize(f))
