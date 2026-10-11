import json, csv, collections, math, datetime, os
A=json.load(open('airlines.json')); AP=json.load(open('airports.json')); P=json.load(open('planner.json'))
S=P['state']; LOADS=P['loads']
OURS={112:'Ryanair',113:'Kingfisher',114:'Pan Am',203:'Virgin',208:'China Eastern',210:'Malaysia'}
PL_NAME={'Ryanair':'Ryanair','Kingfisher':'Kingfisher','Pan American':'Pan Am','Virgin Atlantic':'Virgin','China Eastern':'China Eastern','Malaysia Airlines':'Malaysia'}
# ---------- airports -> country/region
ap={}
for r in csv.DictReader(open('airports_oa.csv', encoding='utf-8')):
    if r['iata_code']: ap[r['iata_code']]=(r['iso_country'], r['continent'], float(r['latitude_deg'] or 0), float(r['longitude_deg'] or 0), r['municipality'] or r['name'])
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
# ---------- world markets
mk=collections.defaultdict(lambda: collections.defaultdict(lambda:[0,0]))   # market -> airline -> [flights/wk, seats/wk]
pairs=collections.defaultdict(lambda: collections.defaultdict(int))        # undirected pair -> airline -> flights/wk
names={a['id']:a['name'] for a in A}
for a in A:
    for f in a['flights']:
        n=len(f[4]);
        if not n: continue
        m=market(f[2],f[3]); s=seats(f[7])
        if s==0: continue
        mk[m][a['id']][0]+=n; mk[m][a['id']][1]+=n*s
        pairs[frozenset((f[2],f[3]))][a['id']]+=n
mtab=[]
for m,d in mk.items():
    tot=sum(v[1] for v in d.values()); totf=sum(v[0] for v in d.values())
    ours=sum(v[1] for k,v in d.items() if k in OURS)
    top=sorted(d.items(), key=lambda kv:-kv[1][1])
    mtab.append({"market":m,"seats":tot,"flights":totf,"our_seats":ours,"our_share":ours/tot if tot else 0,
                 "top":[(names[k] if k not in OURS else OURS[k], v[1], v[1]/tot) for k,v in top[:6]],
                 "ours_by":[(OURS[k], v[1], v[1]/tot) for k,v in top if k in OURS],
                 "rank_ours":next((i+1 for i,(k,v) in enumerate(top) if k in OURS), None), "n_airlines":len(d)})
mtab.sort(key=lambda x:-x['seats'])
# ---------- hubs
HUBS={'JFK':114,'ORD':114,'DEL':113,'BOM':113,'CDG':112,'AMS':112,'LGW':203,'MAN':203,'EDI':203,'PVG':208,'XIY':208,'KMG':208,'PKX':208,'KUL':210}
hubtab=[]
for h,our in HUBS.items():
    a=next((x for x in AP if x['code']==h), None)
    if not a: continue
    st=sorted([s for s in a['stations'] if s['weekly']>0], key=lambda s:-s['weekly']); tot=sum(s['weekly'] for s in st)
    me=next((s for s in st if s['enterprise_id']==our), None); grp=sum(s['weekly'] for s in st if s['enterprise_id'] in OURS)
    hubtab.append({"hub":h,"airline":OURS[our],"ours":me['weekly'] if me else 0,"group":grp,"total":tot,"share":(me['weekly']/tot if me and tot else 0),
                   "rank":next((i+1 for i,s in enumerate(st) if s['enterprise_id']==our),None),"rivals":[(s['name'],s['weekly']) for s in st if s['enterprise_id'] not in OURS][:4],
                   "info":a['info'], "news":a['news']})
# ---------- head-to-head routes
h2h=[]
for p,d in pairs.items():
    o={k:v for k,v in d.items() if k in OURS}
    if not o: continue
    c={k:v for k,v in d.items() if k not in OURS}
    if not c: continue
    a1,a2=sorted(p)
    h2h.append({"pair":f"{a1}–{a2}","ours":[(OURS[k],v) for k,v in o.items()],"ours_w":sum(o.values()),"comp":sorted([(names[k],v) for k,v in c.items()], key=lambda x:-x[1]),"comp_w":sum(c.values())})
h2h.sort(key=lambda x:-x['comp_w'])
ourpairs=sum(1 for p,d in pairs.items() if any(k in OURS for k in d)); contested=len(h2h)
# rivals per our airline: competitor flights on our pairs
riv=collections.defaultdict(lambda: collections.Counter())
for p,d in pairs.items():
    for k in d:
        if k in OURS:
            for c,v in d.items():
                if c not in OURS: riv[OURS[k]][names[c]]+=v
# ---------- world ranking
rank=sorted([(a['name'] if a['id'] not in OURS else OURS[a['id']], a['n_weekly'] or 0, a['id'] in OURS) for a in A], key=lambda x:-x[1])
# ---------- our planner KPIs
AL=['Ryanair','Kingfisher','Pan American','Virgin Atlantic','China Eastern','Malaysia Airlines']
cfg={c['code']:c for c in S['ref']['configs']}
routes={}
D=json.load(open('/home/claude/data.json'))
for r in D['routes']: routes[f"{r[0]}|{r[1]}|{r[2]}"]=r
for r in S.get('routesAdded',[]): routes[f"{r[0]}|{r[1]}|{r[2]}"]=r
kpi={}
for al in AL:
    tl=[t for t in S['tails'] if t['airline']==al]; fr=[f for f in S['freqs'] if f['routeKey'].split('|')[0]==al]
    legs=sum(2*len(f.get('days','1234567')) for f in fr)/7
    seatsd=sum(2*len(f.get('days','1234567'))*(cfg.get(next((t['config'] for t in tl if t['id']==f['tail']),''),{}).get('seats',0)) for f in fr)/7
    blk=0
    for f in fr:
        r=routes.get(f['routeKey']); km=r[5] if r else 1500
        blk+=2*len(f.get('days','1234567'))*(km/846+0.45)
    kpi[al]={"aircraft":len(tl),"routes":len({f['routeKey'] for f in fr}),"flights_day":round(legs),"seats_day":round(seatsd),"block_day":round(blk/7),"types":dict(collections.Counter(t['type'] for t in tl)),
             "on_order":sum(1 for d in S['deliveries'] if d['airline']==al and d['reg'] not in {t['id'] for t in S['tails']})}
# finance
cash=S.get('cash',{}); fx=S.get('fixed7',{}); capex=S.get('capex',[])
dates=sorted(cash)
fin={}
for al in AL:
    pts=[(d, cash[d].get(al)) for d in dates if cash[d].get(al) is not None]
    prof=[]
    for (d0,c0),(d1,c1) in zip(pts,pts[1:]):
        days=(datetime.date.fromisoformat(d1)-datetime.date.fromisoformat(d0)).days or 1
        add=sum(x['amountM'] for x in capex if x['airline']==al and x.get('kind')!='loss' and d0 < x['date'] <= d1)
        prof.append((d1, (c1-c0+add)/days, days))
    lastd=max((d for d in fx if fx[d].get(al) is not None), default=None)
    spent=sum(x['amountM'] for x in capex if x['airline']==al and pts and x['date']>pts[-1][0])
    fin[al]={"series":pts,"profit":prof,"cash":pts[-1][1] if pts else None,"fixed7":fx[lastd][al] if lastd else None,
             "surplus":(pts[-1][1]-fx[lastd][al]-spent) if pts and lastd else None,
             "avg_profit_week":(sum(p*dd for _,p,dd in prof[-6:])/sum(dd for _,_,dd in prof[-6:])) if prof else None,
             "last_profit":prof[-1][1] if prof else None}
# loads: share of reported departures under 95% in the last 7 complete days
ld={}
for mon,days in LOADS.items():
    if isinstance(days, dict): ld.update({d:v for d,v in days.items() if isinstance(v, dict)})
lastdays=sorted([d for d,v in ld.items() if v.get('done')])[-7:]
weak=collections.defaultdict(list)
for d in lastdays:
    for k,v in ld[d].get('f',{}).items():
        al,no=k.split('|',1); weak[al].append((d,no,v))
json.dump({"mtab":mtab,"hubtab":hubtab,"h2h":h2h[:60],"ourpairs":ourpairs,"contested":contested,"rivals":{k:v.most_common(8) for k,v in riv.items()},
           "rank":rank[:30],"our_rank":[(i+1,n,w) for i,(n,w,o) in enumerate(rank) if o],"kpi":kpi,"fin":fin,"lastdays":lastdays,
           "weak":{k:v for k,v in weak.items()},"world":{"airlines":len(A),"flying":sum(1 for a in A if a['n_weekly']),"weekly":sum(a['n_weekly'] or 0 for a in A)}},
          open('results.json','w'), default=str)
print("markets:", len(mtab), "| our markets:", sum(1 for m in mtab if m['our_seats']>0), "| our pairs:", ourpairs, "contested:", contested)
for m in mtab[:40]:
    if m['our_seats']>0: print(f"{m['market']:34s} seats/wk {m['seats']:>9,} ours {m['our_share']*100:5.1f}% rank {m['rank_ours']} of {m['n_airlines']} | top: " + ", ".join(f"{n} {s*100:.0f}%" for n,_,s in m['top'][:4]))
print("unknown share:", next((m['seats'] for m in mtab if m['market']=='Unknown'),0))
print("our world rank:", [(r, n, w) for r,n,w in json.load(open('results.json'))['our_rank']])
# the scan's market summaries, kept for good (scan_airline_markets): sent for the scan pull.py downloaded (scan.json)
if os.path.exists('scan.json'):
    try:
        import scan_markets
        print("market summaries for scan", json.load(open('scan.json'))['id'], ":", scan_markets.send(json.load(open('scan.json'))['id'], market_summaries(A)))
    except Exception as e:
        print("market summaries NOT sent:", e, "(run scan_markets.py <scan id> later)")
