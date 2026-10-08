import re, json, time, sys, html, urllib.request, datetime
sys.path.insert(0,'/home/claude'); from gfetch import get
KEY=open('/home/claude/.sb_anon').read().strip(); SEC=open('/home/claude/.ingest_secret').read().strip()
def rpc(kind, payload):
    req=urllib.request.Request("https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/ingest_snapshot", data=json.dumps({"p_secret":SEC,"p_kind":kind,"p_payload":payload}).encode(), headers={"apikey":KEY,"Authorization":"Bearer "+KEY,"Content-Type":"application/json"})
    for a in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r: return json.loads(r.read() or b'null')
        except Exception as e:
            if a==2: raise
            time.sleep(3)
def text(s): return re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',s))).strip()
def log(*a):
    print(datetime.datetime.now(datetime.UTC).strftime('%H:%M:%S'), *a, flush=True)
# 1. every enterprise in Gander
import os
PHASE=sys.argv[1]; SNAP=int(sys.argv[2]); A0=int(sys.argv[3]) if len(sys.argv)>3 else 0; A1=int(sys.argv[4]) if len(sys.argv)>4 else 999
ents={int(k):v for k,v in json.load(open('/home/claude/ents.json')).items()} if os.path.exists('/home/claude/ents.json') else {}
for L in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ" if not ents else ""):
    try:
        s=get(f"https://gander.airlinesim.aero/app/info/enterprises?letter={L}")
        for i,n in re.findall(r'href="\./enterprises/(\d+)"[^>]*>\s*([^<]{1,80}?)\s*<', s): ents[int(i)]=html.unescape(n)
    except Exception as e: log("letter", L, "failed", e)
    time.sleep(0.4)
json.dump(ents, open('/home/claude/ents.json','w')); log("enterprises:", len(ents))
snap=SNAP
apid=json.load(open('/home/claude/apid.json')) if os.path.exists('/home/claude/apid.json') else {}
for k,(eid,name) in enumerate(sorted(ents.items())):
    if PHASE!="airlines" or not (A0<=k<A1): continue
    try:
        s=get(f"https://gander.airlinesim.aero/app/info/enterprises/{eid}?tab=3")
    except Exception as e:
        log("schedule failed", eid, name, e); continue
    for aid,code in re.findall(r'href="\.\./airports/(\d+)"[^>]*>\s*([A-Z0-9]{3})\s*<', s): apid[code]=int(aid)
    clean=re.sub(r'<script[\s\S]*?</script>','',s); m=re.search(r'<table[\s\S]*?</table>', clean); table=m.group(0) if m else ""
    fl=[]; frm=to=""
    for row in re.findall(r'<tr[\s\S]*?</tr>', table):
        cells=[text(c) for c in re.findall(r'<t[hd][^>]*>([\s\S]*?)</t[hd]>', row)]; j=" | ".join(cells)
        mf=re.match(r'^from .*\(\s*([A-Z0-9]{3})\s*\)', j); mt=re.match(r'^to .*\(\s*([A-Z0-9]{3})\s*\)', j)
        if mf: frm=mf.group(1); continue
        if mt: to=mt.group(1); continue
        if len(cells)>=4 and re.match(r'^[A-Z0-9]{2,3} \d{1,5}[A-Z]?$', cells[0]):   # two- and three-letter airline codes
            code,no=cells[0].split(" "); days=re.sub(r'[^1-7]','',cells[1] if len(cells)>1 else "")
            fl.append([code,no,frm,to,days,cells[2],cells[3],cells[4] if len(cells)>4 else "",cells[5] if len(cells)>5 else ""])   # last field: operator
    weekly=sum(len(f[4]) for f in fl); aps=len({f[2] for f in fl}|{f[3] for f in fl})
    rpc("airline", {"snapshot_id":snap,"enterprise_id":eid,"name":name,"flights":fl,"n_flights":len(fl),"n_weekly":weekly,"n_airports":aps})
    if k%20==0: log(f"{k+1}/{len(ents)} {name}: {len(fl)} flights")
    time.sleep(0.5)
json.dump(apid, open('/home/claude/apid.json','w'))
log("airport ids learned:", len(apid))
if PHASE=="airlines": sys.exit(0)
# 2. airport pages: our hubs and bases, plus the big rival hubs
AP="JFK ORD DFW LAX SFO SEA DEL BOM HYD BLR CCU MAA CDG AMS BCN MXP MUC LGW MAN EDI PVG PKX SZX KMG XIY KUL LHR SIN DXB DOH AUH IST HKG ICN BKK PEK CAN CTU HND NRT FRA MAD FCO ATL EWR IAD MIA YYZ MEX SYD CGK MNL SGN DUB ZRH VIE CPH".split()
if os.path.exists("/home/claude/top_airports.json"): AP=list(dict.fromkeys(AP+json.load(open("/home/claude/top_airports.json"))))
for code in AP:
    aid=apid.get(code)
    if not aid: log("no id for", code); continue
    try: s=get(f"https://gander.airlinesim.aero/app/info/airports/{aid}")
    except Exception as e: log("airport failed", code, e); continue
    t=text(re.sub(r'<script[\s\S]*?</script>|<style[\s\S]*?</style>','',s))
    def kv(label, nxt):
        m=re.search(re.escape(label)+r'\s+(.*?)\s+'+nxt, t); return m.group(1) if m else None
    info={"size":kv("Airport size","Slots"),"slots_per_5min":kv("Slots (per 5 minutes)","Slot Availability"),"slot_availability":kv("Slot Availability","Min\\."),
          "min_transfer":kv("Min. transfer time","Nighttime"),"night_ban":kv("Nighttime ban","Noise"),"runway":kv("Runway","Airport size"),"country":kv("Country","Continent"),"continent":kv("Continent","Runway")}
    stations=[]
    for row in re.findall(r'<tr>[\s\S]*?</tr>', s):
        m=re.search(r'href="\.\./enterprises/(\d+)">([^<]*)</a>', row); d=re.search(r'([\d,]+)\s*Departures', row)
        if not (m and d): continue
        al=re.search(r'alliances/(\d+)', row); tds=re.findall(r'<td[^>]*>([\s\S]*?)</td>', row)
        il=bool(re.search(r'<(img|span|i)\b', tds[3])) if len(tds)>3 else False
        stations.append({"enterprise_id":int(m.group(1)),"name":html.unescape(m.group(2)).strip(),"weekly":int(d.group(1).replace(',','')),"alliance":int(al.group(1)) if al else None,"interline":il})
    news=[{"at":a,"text":b.strip()} for a,b in re.findall(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) UTC\s+(.*?)(?=\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC|Found a mistake)', t)]
    rpc("airport", {"snapshot_id":snap,"code":code,"airport_id":aid,"info":info,"stations":stations,"news":news})
    time.sleep(0.25)
if PHASE=="airports": rpc("finish", {"snapshot_id":snap,"note":f"full scan: {len(ents)} enterprises, {len(AP)} airports"})
log("DONE snapshot", snap)
