import json, csv, collections, math, re, datetime, pathlib
A=json.load(open('airlines3.json')); APG=json.load(open('airports3.json')); GS=json.load(open('game_stats.json'))
ap={}
for r in csv.DictReader(open('airports_oa.csv', encoding='utf-8')):
    if r['iata_code']: ap[r['iata_code']]=(r['iso_country'], r['continent'], float(r['latitude_deg'] or 0), float(r['longitude_deg'] or 0), (r['municipality'] or r['name']).split(' (')[0].split(',')[0])
# the weekly report's market definitions, region(), market() and seats(): scripts/report/analyze.py's market block in this
# repository, run as analyze.py runs it, from the line starting "REG={}" to the line starting "# ---------- world markets"
# (at the start of a line, since the comment above the block names both markers; scan_markets.py finds it the same way)
_src=(pathlib.Path(__file__).resolve().parent.parent / 'report' / 'analyze.py').read_text()
_m0, _m1 = re.search(r'(?m)^REG=\{\}', _src), re.search(r'(?m)^# ---------- world markets', _src)
if not _m0 or not _m1: raise SystemExit("scripts/report/analyze.py's market block (REG={} to # ---------- world markets) wasn't found")
exec(_src[_m0.start():_m1.start()])
def dist(a,b):
    if a not in ap or b not in ap: return 0
    la1,lo1,la2,lo2=map(math.radians,[ap[a][2],ap[a][3],ap[b][2],ap[b][3]]); h=math.sin((la2-la1)/2)**2+math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2; return 2*6371*math.asin(math.sqrt(h))

def _num(x): return int(re.sub(r'[^0-9]','', x.split('/')[0]) or 0)
cap_top={r[1]:_num(r[2]) for r in GS['transrecpaxcap']['rows'] if r[0]!='Overall'}
pax_top={r[1]:_num(r[2]) for r in GS['transrecpax']['rows'] if r[0]!='Overall'}
WORLD_CAP=12762497
est={}
for a in A:
    est[a['name']]=sum(len(f[4])*seats(f[7]) for f in a['flights'] if f[4])
matched={}
for n2 in cap_top:   # each game name maps to exactly one enterprise: an exact name first, otherwise the closest name that starts with it
    exact=[n for n in est if n.lower()==n2.lower()]
    cands=exact or sorted([n for n in est if n.lower().startswith(n2.lower()) or n2.lower().startswith(n.lower())], key=lambda n: abs(len(n)-len(n2)))
    if cands: matched[cands[0]]=n2
known=sum(cap_top[matched[n]] for n in matched); rest_est=sum(v for n,v in est.items() if n not in matched)
# airlines outside the game's top 20 must stay below its 20th place: cap any estimate above it, then scale the rest to the world total
floor20=min(cap_top.values()); capped={}
for _ in range(5):
    free=sum(v for n,v in est.items() if n not in matched and n not in capped)
    OTHER=(WORLD_CAP-known-sum(capped.values()))/free if free else 1
    newcap={n:floor20*0.98 for n,v in est.items() if n not in matched and n not in capped and v*OTHER>=floor20}
    if not newcap: break
    capped.update(newcap)
FACT={n:(cap_top[matched[n]]/est[n] if n in matched else (capped[n]/est[n] if n in capped else OTHER)) if est[n] else 1 for n in est}
FAM=[(r'^(32N|32Q|31N|32A)$','Airbus A320neo family'),(r'^(318|319|320|321)$','Airbus A320 (classic)'),(r'^(7M7|7M8|7M9|7MX)$','Boeing 737 MAX'),(r'^(73[0-9GHJW])$','Boeing 737 (classic and NG)'),(r'^(CS1|CS3|221|223)$','Airbus A220'),(r'^(E7[0-9]|E9[0-9]|29[0-9]|E75|E90|E95)$','Embraer E-Jets'),(r'^(CR[1-9]|ER[34D]|EM2)$','Regional jets'),(r'^(AT[4-7]|DH[1-4]|DH8|ATR)$','Turboprops'),(r'^(919|C27|SU9)$','C919, ARJ21 and Superjet'),(r'^(75.|76.)$','Boeing 757 and 767'),(r'^(77.|78.|74.)$','Boeing 777, 787 and 747'),(r'^(33.|34.|35.|38.)$','Airbus A330, A350 and A380')]
def fam(t):
    for p,n in FAM:
        if re.match(p,t or ''): return n
    return 'Other'
W={'airlines':len(A),'flying':0,'weekly':0,'seats':0}; per=[]; dep=collections.Counter(); depal=collections.defaultdict(collections.Counter); pairs=collections.defaultdict(collections.Counter); regdep=collections.Counter(); typ=collections.Counter(); famc=collections.Counter()
aps=set(); ctry=set(); mk=collections.defaultdict(collections.Counter); mkf=collections.Counter(); longest=[]
for a in A:
    fl=[f for f in a['flights'] if f[4] and seats(f[7])>0]
    if not fl: continue
    W['flying']+=1; wk=0; st=0; dests=set(); cs=set(); bases=collections.Counter()
    for f in fl:
        n=len(f[4]); s=seats(f[7])*FACT.get(a['name'],1)
        if s==0: continue
        wk+=n; st+=n*s; dests.update([f[2],f[3]]); bases[f[2]]+=n
        for c in (f[2],f[3]):
            if c in ap: cs.add(ap[c][0]); ctry.add(ap[c][0])
        aps.update([f[2],f[3]]); dep[f[2]]+=n; depal[f[2]][a['name']]+=n; pairs[frozenset((f[2],f[3]))][a['name']]+=n
        _,rg=region(f[2]); regdep[rg or 'OTH']+=n; typ[f[7]]+=n; famc[fam(f[7])]+=n
        m=market(f[2],f[3]); mk[m][a['name']]+=n*s
        d=dist(f[2],f[3]); longest.append((d,a['name'],f[2],f[3],f[7]))
    W['weekly']+=wk; W['seats']+=st
    b,bn=bases.most_common(1)[0]
    per.append({'name':a['name'],'weekly':wk,'seats':round(st),'dests':len(dests),'countries':len(cs),'base':b,'base_share':bn/wk,'exact':a['name'] in matched})
per.sort(key=lambda x:-x['weekly'])
W['airports']=len(aps); W['countries']=len(ctry); W['routes']=len(pairs)
airports=[]
for c,n in dep.most_common(20):
    lead,ln=depal[c].most_common(1)[0]; airports.append({'code':c,'city':ap.get(c,('','',0,0,c))[4],'cc':ap.get(c,('',))[0],'weekly':n,'airlines':len(depal[c]),'leader':lead,'lshare':ln/n})
fortress=[{'code':c,'city':ap.get(c,('','',0,0,c))[4],'weekly':n,'leader':depal[c].most_common(1)[0][0],'share':depal[c].most_common(1)[0][1]/n} for c,n in dep.items() if n>=140 and depal[c].most_common(1)[0][1]/n>=0.7]
fortress.sort(key=lambda x:-x['weekly'])
busiest=sorted([{'pair':sorted(p),'weekly':sum(v.values())/2,'airlines':len(v),'top':v.most_common(2)} for p,v in pairs.items()], key=lambda x:-x['weekly'])[:15]
contested=sorted([{'pair':sorted(p),'weekly':sum(v.values())/2,'airlines':len(v),'names':[k for k,_ in v.most_common(6)]} for p,v in pairs.items()], key=lambda x:(-x['airlines'],-x['weekly']))[:10]
seenL=set(); L=[]
for d,al,f,t,ty in sorted(longest, reverse=True):
    k=(al,frozenset((f,t)))
    if k in seenL: continue
    seenL.add(k); L.append({'km':round(d),'airline':al,'from':f,'to':t,'type':ty})
    if len(L)==10: break
markets=[]
for m,d in mk.items():
    tot=sum(d.values())
    if tot<150000 or m=='Unknown': continue
    lead,lv=d.most_common(1)[0]; second=d.most_common(2)[1] if len(d)>1 else ('—',0)
    markets.append({'market':m,'seats':tot,'airlines':len(d),'leader':lead,'lshare':lv/tot,'second':second[0],'sshare':second[1]/tot})
markets.sort(key=lambda x:-x['seats'])
# news since the world opened, and the last 30 days
news=[]; seen=set()
for a in APG:
    for n in a['news']:
        k=n['at']+n['text']
        if k not in seen: seen.add(k); news.append(n)
cut=(datetime.datetime(2026,10,6)-datetime.timedelta(days=30)).strftime('%Y-%m-%d')
op=collections.Counter(); op30=collections.Counter(); il=[]; founded=[]; closed=[]
for n in news:
    t=n['text']; m=re.match(r'^(.*?) has opened a new station at (.*?) ?\.$', t)
    if m: op[m.group(1)]+=1; op30[m.group(1)]+= n['at']>=cut; continue
    m=re.match(r'^(.*?) and (.*?) have signed a new interlining agreement', t)
    if m: il.append((n['at'],m.group(1),m.group(2))); continue
    m=re.match(r'^(.*?) has been founded in (.*?) ?\.$', t)
    if m: founded.append((n['at'],m.group(1),m.group(2))); continue
    m=re.match(r'^(.*?) have shut down their station at (.*?) ?\.$', t)
    if m: closed.append((n['at'],m.group(1),m.group(2)))
il.sort(reverse=True); founded.sort(reverse=True); closed.sort(reverse=True)
R={'fact':FACT,'pax_top':pax_top,'cap_top':cap_top,'capped':list(capped),'game':{'general':GS.get('general'),'stats':{k:v['rows'] for k,v in GS.items() if isinstance(v,dict) and 'rows' in v},'factor_other':OTHER},'world':W,'per':per,'regdep':regdep.most_common(),'airports':airports,'fortress':fortress[:10],'busiest':busiest,'contested':contested,'longest':L,'markets':markets[:14],
   'fam':famc.most_common(),'types':typ.most_common(12),'news_n':len(news),'opened':sum(op.values()),'opened30':sum(op30.values()),'exp30':op30.most_common(10),'exp_all':op.most_common(10),
   'il':il,'il30':[x for x in il if x[0]>=cut],'founded':founded,'closed':closed,'news_from':min(n['at'] for n in news),'airport_pts':[(ap[c][2],ap[c][3],n) for c,n in dep.items() if c in ap]}
json.dump(R, open('nl.json','w'), default=list)
print(json.dumps({k:R[k] for k in ['world','news_n','opened','opened30','news_from']}))
print("top10:", [(p['name'],p['weekly'],p['dests'],p['countries'],p['base']) for p in per[:10]])
print("regions:", R['regdep'])
print("airports:", [(x['code'],x['weekly'],x['leader'],round(x['lshare'],2)) for x in airports[:10]])
print("fortress:", [(x['code'],x['leader'],round(x['share'],2),x['weekly']) for x in R['fortress']])
print("markets:", [(m['market'],m['seats'],m['airlines'],m['leader'],round(m['lshare'],2)) for m in R['markets']])
print("busiest:", [(b['pair'],b['weekly'],b['airlines']) for b in busiest[:6]]); print("contested:", [(c['pair'],c['airlines']) for c in contested[:5]])
print("longest:", [(l['km'],l['airline'],l['from'],l['to']) for l in L[:5]])
print("fam:", R['fam'][:8]); print("exp30:", R['exp30']); print("il30:", len(R['il30']), R['il30'][:6]); print("founded:", founded[:6]); print("closed:", closed[:6])
