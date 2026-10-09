import json, math, itertools, urllib.request
S=json.load(open('/home/claude/real_state.json')); D=json.load(open('/home/claude/data.json'))
KEY=open('/home/claude/.sb_anon').read().strip()
MCT=json.loads(urllib.request.urlopen(urllib.request.Request("https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/site_public", data=b"{}", headers={"apikey":KEY,"Authorization":"Bearer "+KEY,"Content-Type":"application/json"}), timeout=60).read())['content']['mct']
off=lambda c: float(D['utc'].get(c,0) or 0); hm=lambda t: int(t.split(':')[0])*60+int(t.split(':')[1])
def km(a,b):
    A,B=D['coords'][a],D['coords'][b]; la1,lo1,la2,lo2=map(math.radians,[A[0],A[1],B[0],B[1]])
    return 2*6371*math.asin(math.sqrt(math.sin((la2-la1)/2)**2+math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2))
# block time as the game computes it (fitted to 468 of our flights on 7 Oct: exact minute on ~93%, never more than 2 min out)
SPEED={'A321':840,'XLR':840,'E195':831,'A320':839,'A350':911}
_DIST={}
for _r in D['routes']+S.get('routesAdded',[]): _DIST[frozenset((_r[1],_r[2]))]=_r[5]
def dist(a,b): return _DIST.get(frozenset((a,b))) or km(a,b)
def block(a,b,ac='A321',add=25):
    d=dist(a,b)
    return round(d/SPEED[ac]*60+add)
legs=[]   # existing group legs in UTC minutes of day
for f in S['freqs']:
    al,h,d=f['routeKey'].split('|')
    if f.get('depHub') and f.get('arrDest'): legs.append(dict(fr=h,to=d,dep=(hm(f['depHub'])-off(h)*60)%1440,arr=(hm(f['arrDest'])-off(d)*60)%1440))
    if f.get('depDest') and f.get('arrHub'): legs.append(dict(fr=d,to=h,dep=(hm(f['depDest'])-off(d)*60)%1440,arr=(hm(f['arrHub'])-off(h)*60)%1440))
def conns(new, H, buf=0):
    m=MCT.get(H,90)+buf; n=0; allL=legs+new
    for i in [l for l in allL if l['to']==H]:
        for o in [l for l in allL if l['fr']==H]:
            if (i in new or o in new) and o['to']!=i['fr'] and m<=(o['dep']-i['arr'])%1440<=480: n+=1
    return n
CURF=S['ref'].get('curfews',{})
def in_curfew(ap, t):
    w=CURF.get(ap)
    if not w: return False
    a,b=[hm(x) for x in w.split('-')]; t=int(t)%1440
    return a<=t<=b if a<=b else (t>=a or t<=b)
def plan(base, dests, start_range=(300,660), step=5, turn=80, mt_per=27.6, mt_h=1.7, min_turn=66, spacing=180, hubs_extra=(), day_only=False, ac='A321'):
    best=None
    for order in itertools.permutations(dests):
        for st in range(start_range[0], start_range[1]+1, step):   # local start time at base
            t=st; new=[]; blk=0; loc=[]
            for d in order:
                b=block(base,d,ac); blk+=2*b
                dU=(t-off(base)*60)%1440; aU=(dU+b)%1440
                new.append(dict(fr=base,to=d,dep=dU,arr=aU)); loc.append((base,d,t%1440,(t+b+(off(d)-off(base))*60)%1440,b))
                t2=t+b+turn; dU2=(t2-off(base)*60)%1440; aU2=(dU2+b)%1440
                new.append(dict(fr=d,to=base,dep=dU2,arr=aU2)); loc.append((d,base,(t2+(off(d)-off(base))*60)%1440,(t2+b)%1440,b))
                t=t2+b+turn
            gap=1440-(t-turn-st)
            if gap<min_turn: continue
            if any(in_curfew(fr,dep) or in_curfew(to,arr) for fr,to,dep,arr,bk in loc): continue   # night bans
            if day_only and any(not (360<=int(dep)%1440<=1439) for fr,to,dep,arr,bk in loc): continue   # no departures between midnight and 06:00
            maint=(gap-min_turn)/(mt_per*len(new)+mt_h*blk/60)
            if maint<1.0: continue
            ok=True
            for nl in new:   # a second daily must sit at least 3 hours from the existing flight
                for l in legs:
                    if l['fr']==nl['fr'] and l['to']==nl['to'] and min((l['dep']-nl['dep'])%1440,(nl['dep']-l['dep'])%1440)<spacing: ok=False
            if not ok: continue
            c=conns(new, base)+sum(conns(new,h) for h in hubs_extra)
            key=(c, maint)
            if best is None or key>best[0]: best=(key, order, st, loc, blk, maint, gap)
    return best
def show(name, base, dests, **kw):
    b=plan(base, dests, **kw)
    if not b: print(name, "-> no feasible plan"); return None
    (c,maint),order,st,loc,blk,_,gap=b
    print(f"{name}: {c} connections | {blk/60:.1f} h a day | maintenance {maint*100:.0f}% | order {order}")
    for fr,to,dep,arr,bk in loc:
        dep=int(round(dep))%1440; arr=int(round(arr))%1440
        print(f"    {fr}-{to} {dep//60:02d}:{dep%60:02d} -> {arr//60:02d}:{arr%60:02d} ({bk//60}:{bk%60:02d})")
    return b
