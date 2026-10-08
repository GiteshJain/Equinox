import json, math, datetime
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
for f in ['manrope-400','manrope-500','manrope-700','unbounded-400','unbounded-500']: font_manager.fontManager.addfont(f'/home/claude/fonts/{f}.ttf')
plt.rcParams.update({'font.family':font_manager.FontProperties(fname='/home/claude/fonts/manrope-500.ttf').get_name(),'font.size':9,'axes.edgecolor':'#C9CDD8','axes.labelcolor':'#3B4566','xtick.color':'#5D6785','ytick.color':'#3B4566','axes.spines.top':False,'axes.spines.right':False,'figure.dpi':200})
R=json.load(open('nl.json')); W=R['world']; G=R['game']['general']; ST=R['game']['stats']
byseats=sorted(R['per'], key=lambda p:-p['seats'])
num=lambda x: int(''.join(ch for ch in x.split('/')[0] if ch.isdigit()) or 0)
NIGHT='#0A1230'; VIOLET='#4B3BA8'; ROSE='#E86A92'; AMBER='#F6B44B'; INK='#0E1630'; GREY='#C9CFDC'
RN={'NA':'North America','MXC':'Mexico & Caribbean','SAM':'South America','EUR':'Europe','CIS':'Russia & CIS','ME':'Middle East','AFR':'Africa','SAS':'South Asia','CHN':'China','NEA':'North-East Asia','SEA':'South-East Asia','OCE':'Oceania','OTH':'Other'}
# --- cover map: every airport sized by weekly departures, on a night map
land=json.load(open('land110.geojson'))
fig=plt.figure(figsize=(8.5,3.9)); ax=fig.add_axes([0,0,1,1]); ax.set_facecolor(NIGHT); fig.patch.set_facecolor(NIGHT)
for ft in land['features']:
    g=ft['geometry']; polys=g['coordinates'] if g['type']=='MultiPolygon' else [g['coordinates']]
    for poly in polys:
        xs=[p[0] for p in poly[0]]; ys=[p[1] for p in poly[0]]; ax.fill(xs,ys,color='#16245A',lw=0)
pts=R['airport_pts']; mx=max(p[2] for p in pts)
ax.scatter([p[1] for p in pts],[p[0] for p in pts],s=[2+60*(p[2]/mx)**0.8 for p in pts],c=AMBER,alpha=.55,lw=0)
ax.scatter([p[1] for p in pts],[p[0] for p in pts],s=[0.6+8*(p[2]/mx)**0.8 for p in pts],c='#FFE8B8',alpha=.9,lw=0)
ax.set_xlim(-170,180); ax.set_ylim(-58,78); ax.axis('off'); plt.savefig('nl_map.png', facecolor=NIGHT); plt.close()
def hbar(items, fname, color=VIOLET, w=7.2, h=3.6, fmt=lambda v:f"{v:,.0f}", label=None):
    fig,ax=plt.subplots(figsize=(w,h)); names=[i[0] for i in items]; vals=[i[1] for i in items]
    ax.barh(range(len(items)), vals, color=color, height=.62)
    for k,v in enumerate(vals): ax.text(v+max(vals)*.01, k, fmt(v), va='center', fontsize=8, color=INK, fontweight='bold')
    ax.set_yticks(range(len(items))); ax.set_yticklabels(names, fontsize=8.4); ax.invert_yaxis(); ax.set_xlim(0,max(vals)*1.15)
    ax.grid(axis='x', color='#ECEEF3', lw=.6); ax.set_axisbelow(True); ax.tick_params(axis='x', labelsize=7.5)
    if label: ax.set_xlabel(label, fontsize=8)
    plt.tight_layout(); plt.savefig(fname); plt.close()
hbar([(RN.get(k,k),v) for k,v in R['regdep']], 'nl_regions.png', color=VIOLET, h=3.3, label='Weekly departures')
hbar([(p['name'],p['seats']) for p in byseats[:10]], 'nl_league.png', color=NIGHT, h=2.7, label='Seats a week')
lf=[(r[1], min(100, num(r[2])/R['cap_top'][r[1]]*100)) for r in ST['transrecpax'] if r[0]!='Overall' and r[1] in R['cap_top']][:12]
hbar(lf, 'nl_loads.png', color=VIOLET, h=3.6, fmt=lambda v:f"{v:.0f}%", label='Passengers carried as a share of seats offered (load factor)')
hbar([(f"{a['city']} ({a['code']})",a['weekly']) for a in R['airports'][:10]], 'nl_airports.png', color=VIOLET, h=2.7, label='Departures a week')
fam=[x for x in R['fam'] if x[0]!='Other'][:10]; tot=sum(v for _,v in R['fam'])
hbar([(n,v/tot*100) for n,v in fam], 'nl_fleet.png', color=ROSE, h=3.4, fmt=lambda v:f"{v:.0f}%", label='Share of all flights')
hbar(R['exp30'], 'nl_expansion.png', color=AMBER, h=3.2, label='New stations opened, last 30 days')
print('charts ok')
from reportlab.lib.pagesizes import letter
from reportlab.platypus import BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table, TableStyle, Image, PageBreak, NextPageTemplate
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase.pdfmetrics import registerFontFamily
for n,f in [('MR','manrope-400'),('MM','manrope-500'),('MB','manrope-700'),('UN','unbounded-400'),('UM','unbounded-500')]: pdfmetrics.registerFont(TTFont(n,f'/home/claude/fonts/{f}.ttf'))
registerFontFamily('MR', normal='MR', bold='MB', italic='MR', boldItalic='MB')
C=lambda h: colors.HexColor(h); INKc=C(INK); MUT=C('#5D6785'); FAINT=C('#8C94AD'); LINE=C('#E2E5EE'); SOFT=C('#F2F4F8'); NIGHTc=C(NIGHT)
st={}
def S(n, **k):
    b=dict(fontName='MR', fontSize=9.4, leading=13.6, textColor=INKc); b.update(k); st[n]=ParagraphStyle(n, **b)
S('body'); S('small', fontSize=7.8, leading=10.6, textColor=MUT); S('tiny', fontSize=7, leading=9, textColor=FAINT)
S('kick', fontName='MB', fontSize=7.8, leading=10, textColor=C(VIOLET)); S('h1', fontName='UN', fontSize=22, leading=26, spaceAfter=6)
S('h2', fontName='UM', fontSize=12.5, leading=16, spaceBefore=10, spaceAfter=4); S('deck', fontName='MM', fontSize=11.2, leading=16, textColor=C('#3B4566'))
S('cell', fontSize=7.8, leading=10); S('cellb', fontName='MB', fontSize=7.8, leading=10); S('bul', fontSize=9.4, leading=13.6, leftIndent=11, bulletIndent=0, spaceAfter=3)
S('num', fontName='UN', fontSize=22, leading=24); S('numl', fontName='MM', fontSize=8, leading=10.5, textColor=MUT)
P=lambda t,s='body': Paragraph(t, st[s])
bul=lambda items: [Paragraph(t, st['bul'], bulletText='•') for t in items]
def table(rows, widths):
    data=[[Paragraph(str(c), st['cellb' if i==0 else 'cell']) for c in r] for i,r in enumerate(rows)]
    t=Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'MIDDLE'),('LINEBELOW',(0,0),(-1,0),0.8,INKc),('LINEBELOW',(0,1),(-1,-1),0.4,LINE),('TOPPADDING',(0,0),(-1,-1),3),('BOTTOMPADDING',(0,0),(-1,-1),3),('LEFTPADDING',(0,0),(-1,-1),4),('RIGHTPADDING',(0,0),(-1,-1),4)]))
    return t
Wd=letter[0]-1.5*inch
def furniture(c, doc):
    c.saveState(); w,h=letter
    if doc.page==1:
        c.setFillColor(NIGHTc); c.rect(0,h-2.05*inch,w,2.05*inch,fill=1,stroke=0)
        c.setFillColor(colors.white); c.setFont('UM',34); c.drawString(0.75*inch,h-1.05*inch,'gander monthly')
        c.setFont('MM',10); c.setFillColor(C('#C9D1EA')); c.drawString(0.75*inch,h-1.38*inch,'Issue 1  ·  October 2026  ·  The story so far  ·  Corrected edition')
        c.setFont('MR',8.5); c.setFillColor(C('#9AA4C4')); c.drawString(0.75*inch,h-1.62*inch,'A monthly look at the AirlineSim Gander world, presented by')
        c.setFont('UM',10); c.setFillColor(colors.white); tw=c.stringWidth('A monthly look at the AirlineSim Gander world, presented by ','MR',8.5); c.drawString(0.75*inch+tw,h-1.62*inch,'equinox.')
        gx=[(0,'#0A1230'),(0.38,'#4B3BA8'),(0.66,'#E86A92'),(1,'#F6B44B')]
        for k in range(200):
            t=k/199; seg=[s for s in zip(gx,gx[1:]) if s[0][0]<=t<=s[1][0]][0]; (t0,c0),(t1,c1)=seg; f=(t-t0)/(t1-t0); a=C(c0); b=C(c1)
            c.setFillColor(colors.Color(a.red+(b.red-a.red)*f, a.green+(b.green-a.green)*f, a.blue+(b.blue-a.blue)*f)); c.rect(0.75*inch+k*(3.2*inch/200), h-1.82*inch, 3.2*inch/200+0.3, 2.2, fill=1, stroke=0)
    else:
        c.setFont('UM',8.5); c.setFillColor(INKc); c.drawString(0.75*inch,h-0.5*inch,'gander monthly')
        c.setFont('MR',7.4); c.setFillColor(FAINT); c.drawString(0.75*inch+82,h-0.5*inch,'Issue 1 · October 2026 · presented by equinox.')
        c.setStrokeColor(LINE); c.setLineWidth(.6); c.line(0.75*inch,h-0.58*inch,w-0.75*inch,h-0.58*inch)
    c.setFont('MR',6.8); c.setFillColor(FAINT); c.drawString(0.75*inch,0.45*inch,'Fan-made and created entirely by AI. Based on public AirlineSim (Gander) data scanned 6 Oct 2026. Not affiliated with AirlineSim or any airline.')
    c.drawRightString(w-0.75*inch,0.45*inch,str(doc.page)); c.restoreState()
doc=BaseDocTemplate('/home/claude/report/Gander_Monthly_Issue1_Oct2026.pdf', pagesize=letter, leftMargin=.75*inch, rightMargin=.75*inch, topMargin=.8*inch, bottomMargin=.7*inch, title='gander monthly — Issue 1, October 2026', author='presented by equinox.')
doc.addPageTemplates([PageTemplate(id='first', frames=[Frame(.75*inch,.7*inch,Wd,letter[1]-.7*inch-2.05*inch-.2*inch,leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0)], onPage=furniture),
                      PageTemplate(id='rest', frames=[Frame(.75*inch,.7*inch,Wd,letter[1]-.8*inch-.7*inch,leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0)], onPage=furniture)])
per=R['per']; top=per[0]; mostdest=max(per,key=lambda p:p['dests']); mostc=max(per,key=lambda p:p['countries'])
fmtk=lambda v: f"{v/1e6:.1f}M" if v>=1e6 else f"{v/1e3:.0f}k"
na_eu=(dict(R['regdep']).get('NA',0)+dict(R['regdep']).get('EUR',0))/W['weekly']
s=[]
s.append(P('THE STATE OF THE GANDER SKIES','kick'))
s.append(P(f"{G['accounts']} players run {G['enterprises']} airlines. {W['flying']} of them fly {G['flights']:,} flights a week with {G['aircraft']:,} aircraft, between {W['airports']:,} airports in {W['countries']} countries. Here's who leads, where the traffic is, and who has moved fastest since the world opened in mid-August.",'deck'))
s.append(Spacer(1,8)); s.append(Image('nl_map.png', width=Wd, height=Wd*3.9/8.5)); s.append(P('Every airport served in Gander, sized by weekly departures.','tiny'))
s.append(Spacer(1,8))
tiles=[[P(f"{G['flights']:,}",'num'),P(f"{G['pax_cap']/1e6:.1f}M",'num'),P(f"{G['aircraft']:,}",'num'),P(f"{W['routes']:,}",'num')],[P('flights a week','numl'),P('seats a week','numl'),P('aircraft in service','numl'),P('routes flown','numl')]]
t=Table(tiles, colWidths=[Wd/4]*4); t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,-1),SOFT),('LEFTPADDING',(0,0),(-1,-1),10),('TOPPADDING',(0,0),(-1,0),9),('BOTTOMPADDING',(0,1),(-1,1),9),('LINEBEFORE',(1,0),(-1,-1),1,colors.white)])); s.append(t)
s.append(P('In this issue','h2'))
s+=bul(['<b>At a glance:</b> the world in numbers, and where the flying happens.','<b>The league table:</b> the 20 biggest airlines, and how full they fly.','<b>Airports:</b> the busiest, and the fortress hubs.','<b>Markets:</b> who leads the 14 biggest markets.','<b>Routes:</b> the busiest, the longest and the most contested.','<b>Fleets:</b> what the world flies.','<b>On the move:</b> expansions, new airlines and partnerships.'])
s.append(P('Figures from the game\'s own statistics and a full scan of every airline\'s schedule.','tiny'))
s.append(NextPageTemplate('rest')); s.append(PageBreak())
s.append(P('AT A GLANCE','kick')); s.append(P(f"North America and Europe carry {na_eu*100:.0f}% of the world's flying.",'h1'))
s.append(P(f"Of {G['enterprises']} airlines registered in Gander, {W['flying']} are flying passengers. Together they operate {G['flights']:,} flights and {G['pax_cap']/1e6:.2f} million seats a week on {W['routes']:,} routes: {G['economy']/G['pax_cap']*100:.1f}% of seats are economy, {G['business']/G['pax_cap']*100:.1f}% business and {G['first']/G['pax_cap']*100:.1f}% first.",'body'))
s.append(Spacer(1,6)); s.append(Image('nl_regions.png', width=Wd, height=Wd*3.3/7.2))
rd=dict(R['regdep'])
s+=bul([f"<b>North America ({rd.get('NA',0):,}) and Europe ({rd.get('EUR',0):,})</b> are neck and neck for the most departures a week.",f"<b>China is third</b> with {rd.get('CHN',0):,}, ahead of North-East Asia ({rd.get('NEA',0):,}) and Oceania ({rd.get('OCE',0):,}).",f"<b>South Asia is the quietest region</b> at {rd.get('SAS',0):,} departures a week, and Russia and the CIS the second quietest ({rd.get('CIS',0):,}). Both leave plenty of room to grow."])
s.append(PageBreak())
top=byseats[0]
s.append(P('THE LEAGUE TABLE','kick')); s.append(P(f"{top['name']} is the biggest airline in Gander, with {top['seats']:,} seats a week.",'h1'))
s.append(Image('nl_league.png', width=Wd, height=Wd*2.7/7.2))
paxw={r[1]:num(r[2]) for r in ST['transrecpax'] if r[0]!='Overall'}
def pax_of(n):
    for k,v in paxw.items():
        if k.lower()==n.lower() or n.lower().startswith(k.lower()): return v
rows=[['#','Airline','Seats a week','Passengers a week','Load factor','Flights a week','Destinations','Countries']]
for i,p in enumerate(byseats[:20]):
    px=pax_of(p['name']) if p['exact'] else None
    rows.append([str(i+1),p['name'],f"{p['seats']:,}",f"{px:,}" if px else '—',f"{min(100,px/p['seats']*100):.0f}%" if px else '—',f"{p['weekly']:,}",str(p['dests']),str(p['countries'])])
s.append(table(rows,[0.3*inch,1.75*inch,0.95*inch,1.05*inch,0.75*inch,0.85*inch,0.75*inch,0.6*inch]))
s.append(P(f"Seats and passengers are the game's own weekly figures. Most destinations: <b>{mostdest['name']}</b> ({mostdest['dests']}). Most countries: <b>{mostc['name']}</b> ({mostc['countries']}).",'small'))
s.append(PageBreak())
s.append(P('TRAFFIC AND CARGO','kick')); s.append(P('How full the biggest airlines fly, and who carries the freight.','h1'))
s.append(Image('nl_loads.png', width=Wd, height=Wd*3.6/7.2))
cg=[r for r in ST['transreccargo'] if r[0]!='Overall'][:10]; cc={r[1]:num(r[2]) for r in ST['transreccargocap'] if r[0]!='Overall'}
s.append(P('The cargo league','h2'))
s.append(table([['#','Airline','Freight a week (CU)','Cargo capacity a week (CU)','Load factor']]+[[r[0],r[1],f"{num(r[2]):,}",f"{cc[r[1]]:,}" if r[1] in cc else '—',f"{num(r[2])/cc[r[1]]*100:.0f}%" if cc.get(r[1]) else '—'] for r in cg],[0.3*inch,2.4*inch,1.5*inch,1.7*inch,1.1*inch]))
s.append(P(f"Gander offers {G['cargo_cap']:,} cargo units of capacity a week.",'small'))
s.append(PageBreak())
A=R['airports']
s.append(P('AIRPORTS','kick')); s.append(P(f"{A[0]['city']} is the world's busiest airport, and almost entirely one airline's.",'h1'))
s.append(Image('nl_airports.png', width=Wd, height=Wd*2.7/7.2))
st_rows=[r for r in ST['apoffices'] if r[0]!='Overall'][:10]; cn_rows=[r for r in ST['aptravels'] if r[0]!='Overall'][:10]
s.append(P('Most airlines, most connections','h2'))
t2=[['#','Airport','Airlines','#','Airport','Connections']]+[[a[0],a[1],a[2].split('/')[0].strip(),b[0],b[1],b[2].split('/')[0].strip()] for a,b in zip(st_rows,cn_rows)]
s.append(table(t2,[0.3*inch,1.9*inch,0.8*inch,0.3*inch,1.9*inch,1.0*inch]))
s.append(P('The fortress hubs','h2')); s.append(P('Busy airports where one airline flies at least 70% of all departures.','small'))
s.append(table([['Airport','Departures a week','Airline','Its share']]+[[f"{f['city']} ({f['code']})",f"{f['weekly']:,}",f['leader'],f"{f['share']*100:.0f}%"] for f in R['fortress']],[2.4*inch,1.3*inch,2.3*inch,1.0*inch]))
s.append(PageBreak())
M=R['markets']; mono=[m for m in M if m['lshare']>=0.95]
s.append(P('MARKETS','kick')); s.append(P(f"{M[0]['market']} is the biggest market, and the most open: no airline holds more than {M[0]['lshare']*100:.0f}%.",'h1'))
s.append(table([['Market','Seats a week','Airlines','Leader','Runner-up']]+[[m['market'],fmtk(m['seats']),str(m['airlines']),f"{m['leader']} {m['lshare']*100:.0f}%",f"{m['second']} {m['sshare']*100:.0f}%" if m['second']!='—' else '—'] for m in M],[1.75*inch,0.9*inch,0.65*inch,1.9*inch,1.8*inch]))
s.append(Spacer(1,6))
s+=bul([f"<b>Concentrated:</b> {', '.join(m['market'] for m in M if m['lshare']>=0.6)} each have one airline with 60% or more.",f"<b>Wide open:</b> {', '.join(m['market'] for m in M if m['lshare']<0.32)} have no airline above about a third.",(f"<b>Single-airline markets:</b> {', '.join(m['market']+' ('+m['leader']+')' for m in mono)}." if mono else "No big market is flown by a single airline.")])
s.append(P('Markets group airports by region, with the largest countries\' domestic flying shown on its own. Seats are estimated from each flight\'s aircraft type.','tiny'))
s.append(PageBreak())
B=R['busiest']; Cn=R['contested']; L=R['longest']
s.append(P('ROUTES','kick')); s.append(P(f"{B[0]['pair'][0]}–{B[0]['pair'][1]} is the busiest route in the world, at {B[0]['weekly']:.0f} flights a week each way.",'h1'))
s.append(P('The busiest','h2')); s.append(table([['Route','Flights a week, each way','Airlines','Main operators']]+[[f"{b['pair'][0]}–{b['pair'][1]}",f"{b['weekly']:.0f}",str(b['airlines']),', '.join(n for n,_ in b['top'])] for b in B[:10]],[1.2*inch,1.5*inch,0.7*inch,3.6*inch]))
s.append(P('The most contested','h2')); s.append(table([['Route','Airlines','Who flies it']]+[[f"{c['pair'][0]}–{c['pair'][1]}",str(c['airlines']),', '.join(c['names'])] for c in Cn[:6]],[1.2*inch,0.7*inch,5.1*inch]))
s.append(P('The longest','h2')); s.append(table([['Route','Distance','Airline','Aircraft']]+[[f"{l['from']}–{l['to']}",f"{l['km']:,} km",l['airline'],l['type']] for l in L[:8]],[1.2*inch,1.0*inch,3.2*inch,1.6*inch]))
s.append(PageBreak())
fam=[x for x in R['fam'] if x[0]!='Other']; tot=sum(v for _,v in R['fam']); nb=sum(v for n,v in R['fam'] if any(k in n for k in ['A320','737','A220']))
s.append(P('FLEETS','kick')); s.append(P(f"The Airbus A320neo family flies {fam[0][1]/tot*100:.0f}% of all flights in Gander.",'h1'))
s.append(Image('nl_fleet.png', width=Wd, height=Wd*3.4/7.2))
s+=bul([f"<b>Narrowbodies rule:</b> the A320 and 737 families and the A220 together fly about {nb/tot*100:.0f}% of all flights.",f"<b>The 737 MAX is the runner-up</b> at {dict(R['fam']).get('Boeing 737 MAX',0)/tot*100:.0f}%, ahead of the classic A320 ({dict(R['fam']).get('Airbus A320 (classic)',0)/tot*100:.0f}%) and the E-Jets ({dict(R['fam']).get('Embraer E-Jets',0)/tot*100:.0f}%).",f"<b>Widebodies</b> fly a small share of flights but most of the longest routes; the longest of all, {L[0]['from']}–{L[0]['to']}, is {L[0]['km']:,} km."])
s.append(PageBreak())
s.append(P('ON THE MOVE','kick')); s.append(P(f"{R['exp30'][0][0]} opened the most new stations in the last 30 days.",'h1'))
s.append(P(f"In the 30 days to 6 October, airlines opened {R['opened30']:,} new stations at the world's 127 busiest airports, and signed {len(R['il30'])} new interline agreements.",'body'))
s.append(Image('nl_expansion.png', width=Wd, height=Wd*3.2/7.2))
s.append(P('New airlines','h2')); s.append(table([['Date','Airline','Founded in']]+[[f[0][:10],f[1],f[2]] for f in R['founded']],[1.0*inch,3.4*inch,2.6*inch]))
s.append(P('Stations closed','h2')); s.append(table([['Date','Airline','Station']]+[[c[0][:10],c[1],c[2]] for c in R['closed'][:6]],[1.0*inch,3.4*inch,2.6*inch]))
s.append(P('Latest partnerships','h2')); s.append(P(', '.join(f"{a} and {b}" for _,a,b in R['il30'][:12])+'.','body'))
s.append(PageBreak())
ce=[r for r in ST['contenterprises'] if r[0]!='Overall']; co=[r for r in ST['countryenterprises'] if r[0]!='Overall'][:10]
s.append(P('WHERE AIRLINES ARE BASED','kick')); s.append(P(f"{ce[0][1]} and {ce[1][1]} are home to the most airlines.",'h1'))
s.append(table([['Continent','Airlines']]+[[r[1],r[2].split('/')[0].strip()] for r in ce],[3.5*inch,1.2*inch]))
s.append(P('By country','h2')); s.append(table([['#','Country','Airlines']]+[[r[0],r[1],r[2].split('/')[0].strip()] for r in co],[0.3*inch,3.2*inch,1.2*inch]))
s.append(PageBreak())
s.append(P('ABOUT THIS NEWSLETTER','kick')); s.append(P('How it\'s made','h1'))
s+=bul([f"<b>Data:</b> every airline's public schedule in AirlineSim's Gander world ({W['airlines']} airlines), plus the public pages of the 127 busiest airports, scanned on 6 October 2026. News covers {R['news_from'][:10]} to 5 October.",'<b>Seats and passengers</b> are the game\'s own figures for the 20 largest airlines. For the others, seats are estimated from each flight\'s aircraft type and scaled so the world total matches the game\'s.','<b>Markets</b> group airports by region; domestic flying in the largest countries is shown separately.','<b>Station counts</b> come from airport pages, so they cover the 127 busiest airports rather than every airport in the world.',
 '<b>Next issue:</b> early November, with the first month-on-month comparison: who grew, who shrank, and who arrived.'])
s.append(Spacer(1,10))
s.append(P('The small print','h2')); s.append(P('gander monthly is presented by equinox. It is researched, written and designed entirely by AI, from public game data. It is a fan-made, non-commercial newsletter and is not affiliated with AirlineSim or with any real airline. Airline names belong to their owners and are used only to identify airlines as they appear in the game.','body'))
s.append(Spacer(1,10)); s.append(P('Feel free to share it with other players.','deck'))
doc.build(s); print('pdf ok')
