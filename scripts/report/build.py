import json, datetime
from reportlab.lib.pagesizes import letter
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table, TableStyle, Image, PageBreak, KeepTogether, NextPageTemplate)
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
pdfmetrics.registerFont(TTFont('LS','/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf'))
pdfmetrics.registerFont(TTFont('LSB','/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'))
pdfmetrics.registerFont(TTFont('LSI','/usr/share/fonts/truetype/liberation/LiberationSans-Italic.ttf'))
from reportlab.pdfbase.pdfmetrics import registerFontFamily
registerFontFamily('LS', normal='LS', bold='LSB', italic='LSI', boldItalic='LSB')
R=json.load(open('results.json'))
INK=colors.HexColor('#1D1D1F'); MUTED=colors.HexColor('#5B616B'); FAINT=colors.HexColor('#8A9099'); LINE=colors.HexColor('#E3E6EA')
ACC=colors.HexColor('#0B5CAD'); BAND=colors.HexColor('#0F1B2D'); POS=colors.HexColor('#1A7F37'); NEG=colors.HexColor('#C4141C'); SOFT=colors.HexColor('#F4F6F8'); WARN=colors.HexColor('#A35A00')
st={}
def S(name, **kw):
    base=dict(fontName='LS', fontSize=9, leading=12.4, textColor=INK); base.update(kw); st[name]=ParagraphStyle(name, **base); return st[name]
S('body'); S('small', fontSize=7.6, leading=10, textColor=MUTED); S('tiny', fontSize=6.8, leading=8.6, textColor=FAINT)
S('h1', fontName='LSB', fontSize=15, leading=19, spaceAfter=4); S('kicker', fontName='LSB', fontSize=7.6, leading=10, textColor=ACC, spaceAfter=2)
S('h2', fontName='LSB', fontSize=10.5, leading=14, spaceBefore=8, spaceAfter=3); S('lead', fontSize=10, leading=14, textColor=colors.HexColor('#2E333A'))
S('cell', fontSize=7.6, leading=9.6); S('cellb', fontName='LSB', fontSize=7.6, leading=9.6); S('cellm', fontSize=7.6, leading=9.6, textColor=MUTED)
S('cellr', fontSize=7.6, leading=9.6, alignment=2); S('cellrb', fontName='LSB', fontSize=7.6, leading=9.6, alignment=2)
S('bul', fontSize=9, leading=12.4, leftIndent=11, bulletIndent=0, spaceAfter=3)
S('kv', fontName='LSB', fontSize=20, leading=23, textColor=INK); S('kl', fontSize=7.6, leading=9.6, textColor=MUTED); S('kd', fontSize=7.4, leading=9.4, textColor=POS)
S('title', fontName='LSB', fontSize=24, leading=28, textColor=colors.white); S('subtitle', fontSize=10, leading=13, textColor=colors.HexColor('#C9D3E0'))
P=lambda t, s='body': Paragraph(t, st[s])
def bullets(items, s='bul'): return [Paragraph(t, st[s], bulletText='•') for t in items]
def table(rows, widths, head=True, zebra=True, align_right_from=None, bold_last=False):
    data=[[c if not isinstance(c,str) else Paragraph(c, st['cellb' if (head and i==0) else 'cell']) for c in r] for i,r in enumerate(rows)]
    t=Table(data, colWidths=widths, repeatRows=1 if head else 0)
    sty=[('VALIGN',(0,0),(-1,-1),'MIDDLE'),('LINEBELOW',(0,0),(-1,0),0.8,INK) if head else ('LINEBELOW',(0,0),(-1,0),0,colors.white),
         ('LINEBELOW',(0,1),(-1,-1),0.4,LINE),('TOPPADDING',(0,0),(-1,-1),3.2),('BOTTOMPADDING',(0,0),(-1,-1),3.2),('LEFTPADDING',(0,0),(-1,-1),4),('RIGHTPADDING',(0,0),(-1,-1),4)]
    if bold_last: sty+= [('LINEABOVE',(0,-1),(-1,-1),0.8,INK),('BACKGROUND',(0,-1),(-1,-1),SOFT)]
    t.setStyle(TableStyle(sty)); return t
fin=R['fin']; kpi=R['kpi']
AL=['Ryanair','Kingfisher','Pan American','Virgin Atlantic','China Eastern','Malaysia Airlines']
SH={'Ryanair':'Ryanair','Kingfisher':'Kingfisher','Pan American':'Pan Am','Virgin Atlantic':'Virgin','China Eastern':'China Eastern','Malaysia Airlines':'Malaysia'}
tot=lambda key: sum(kpi[a][key] for a in AL)
gcash=sum(fin[a]['cash'] for a in AL); gfix=sum(fin[a]['fixed7'] for a in AL); gsur=sum(fin[a]['surplus'] for a in AL)
glast=sum(fin[a]['last_profit'] for a in AL); gwk=sum(fin[a]['avg_profit_week'] for a in AL)
ourweekly=sum(w for _,_,w in R['our_rank']); world=R['world']['weekly']
def money(x, sign=True): return (f"{x:+.2f}M" if sign else f"{x:.2f}M")
def colored(x, txt=None):
    t=txt or money(x); c='#1A7F37' if x>=0 else '#C4141C'; return f'<font color="{c}">{t}</font>'
# ---------------- page furniture
def on_page(c, doc):
    c.saveState(); w,h=letter
    if doc.page==1:
        c.setFillColor(BAND); c.rect(0, h-1.62*inch, w, 1.62*inch, fill=1, stroke=0)
        c.setFillColor(colors.HexColor('#F1C21B')); c.rect(0.75*inch, h-1.62*inch, 0.6*inch, 0.05*inch, fill=1, stroke=0)
    else:
        c.setFont('LSB', 7.4); c.setFillColor(INK); c.drawString(0.75*inch, h-0.5*inch, 'Equinox Group')
        c.setFont('LS', 7.4); c.setFillColor(FAINT); c.drawString(0.75*inch+52, h-0.5*inch, '·  Weekly briefing  ·  Week 41, 28 Sep – 4 Oct 2026')
        c.setStrokeColor(LINE); c.setLineWidth(0.6); c.line(0.75*inch, h-0.58*inch, w-0.75*inch, h-0.58*inch)
    c.setFont('LS', 7); c.setFillColor(FAINT)
    c.drawString(0.75*inch, 0.45*inch, 'Internal · prepared 5 Oct 2026 from the planner and a full scan of every airline in Gander (5 Oct, 04:53 UTC)')
    c.drawRightString(w-0.75*inch, 0.45*inch, f'{doc.page}')
    c.restoreState()
doc=BaseDocTemplate('/home/claude/report/Equinox_Weekly_Briefing_W41.pdf', pagesize=letter, leftMargin=0.75*inch, rightMargin=0.75*inch, topMargin=0.78*inch, bottomMargin=0.7*inch,
                    title='Equinox Group — Weekly briefing, week 41', author='Equinox planning')
W=letter[0]-1.5*inch
f_first=Frame(0.75*inch, 0.7*inch, W, letter[1]-0.7*inch-1.62*inch-0.18*inch, id='first', leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
f_rest=Frame(0.75*inch, 0.7*inch, W, letter[1]-0.78*inch-0.7*inch, id='rest', leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
class Doc(BaseDocTemplate): pass
doc.addPageTemplates([PageTemplate(id='first', frames=[f_first], onPage=on_page), PageTemplate(id='rest', frames=[f_rest], onPage=on_page)])
story=[]
# ---------------- page 1: executive summary
class Cover:  # title text drawn in the band
    pass
def cover_text(c, doc):
    on_page(c, doc); w,h=letter
    c.setFillColor(colors.white); c.setFont('LSB', 23); c.drawString(0.75*inch, h-0.82*inch, 'Equinox Group — Weekly briefing')
    c.setFont('LS', 10); c.setFillColor(colors.HexColor('#C9D3E0')); c.drawString(0.75*inch, h-1.1*inch, 'Week 41  ·  28 Sep – 4 Oct 2026  ·  First edition: sets the baseline for week-on-week comparison')
    c.setFont('LS', 8.2); c.setFillColor(colors.HexColor('#8FA0B6')); c.drawString(0.75*inch, h-1.33*inch, 'Ryanair  ·  Kingfisher  ·  Pan Am  ·  Virgin  ·  China Eastern  ·  Malaysia')
doc.pageTemplates[0].onPage=cover_text
story.append(P('THE WEEK IN ONE LINE', 'kicker'))
story.append(P('All six airlines made money for the first time and the fleet nearly doubled, from 42 to 82 aircraft. From here, growth is limited by cash, not by demand.', 'lead'))
story.append(Spacer(1,9))
def tile(v, l, d, dc=POS):
    return [Paragraph(v, st['kv']), Spacer(1,1), Paragraph(l, st['kl']), Paragraph(f'<font color="{dc.hexval().replace("0x","#")}">{d}</font>', st['kd'])]
tiles=[tile('82', 'aircraft in service', '+40 this week · 20 more on order'),
       tile(f'+{glast:.1f}M', 'group profit a day, 2–4 Oct', f'week average +{gwk:.1f}M a day'),
       tile(f'{gsur:.1f}M', 'surplus after this week\'s orders', f'cash {gcash:.1f}M against {gfix:.1f}M due in 7 days', WARN),
       tile(f'{ourweekly:,}', 'flights a week across the group', f'{ourweekly/world*100:.1f}% of all flights in Gander')]
tt=Table([tiles], colWidths=[W/4]*4)
tt.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),9),('RIGHTPADDING',(0,0),(-1,-1),6),('TOPPADDING',(0,0),(-1,-1),8),('BOTTOMPADDING',(0,0),(-1,-1),8),
                        ('BACKGROUND',(0,0),(-1,-1),SOFT),('LINEBEFORE',(1,0),(-1,0),0.6,colors.white)]))
story.append(tt); story.append(Spacer(1,10))
story.append(P('What matters this week', 'h2'))
story+=bullets([
 '<b>India is ours, Mumbai is not.</b> Kingfisher is the only airline flying domestic routes in India (49,500 seats a week) and has 73% of Delhi\'s departures. But at Mumbai it is fourth (8%), behind Etihad, Emirates and Qatar, and Gulf airlines hold 89% of South Asia–Gulf traffic.',
 '<b>Malaysia is second at its own hub.</b> Singapore Airlines operates 315 departures a week at KUL against our 196, and 630 a week on KUL–Singapore against our 14. Malaysia leads South Asia–SE Asia (48%), where Singapore Airlines is weak.',
 '<b>Europe: we are the challenger at every base.</b> Ryanair is second at CDG (19%) and Amsterdam (17%). Virgin is second at Gatwick behind easyJet (385 departures a week against 224). KLM has just signed an interline with Singapore Airlines.',
 '<b>China: Air China sets the terms.</b> It flies 58% of China\'s domestic seats and is China Eastern\'s main rival on our routes. China Eastern leads Shanghai Pudong (50%) and Daxing (38%), but Tianjin Airlines opened 15 new stations from Daxing on 5 Oct.',
 '<b>US: Pan Am owns JFK but not the market.</b> It has 27% of JFK departures, more than anyone, but only 8% of transatlantic seats (third) and 2.6% of US domestic. Emirates opened New York on 4 Oct.',
])
story.append(P('Decisions for you', 'h2'))
dec=[['Decision', 'Recommendation', 'When'],
     ['Ryanair\'s two double-daily routes', 'Keep both. Amsterdam–Copenhagen was full on 3 and 4 Oct after a weak 2 Oct; CDG–Munich has been full since 1 Oct. Review again in a week.', 'Today'],
     ['Pan Am–British Caledonian interline', 'Cancel as planned. British Caledonian is a direct rival: 1,010 departures a week at Heathrow, 42 at JFK, and still opening stations.', '10 Oct'],
     ['A321 cabin conversion (26 aircraft, about 5.2M)', 'Stage it by airline surplus: China Eastern, Virgin and Pan Am first. Kingfisher waits until its surplus is clearly above 1M.', '11 Oct'],
     ['Next aircraft orders', 'Nothing affordable today. Pan Am reaches about 7M, enough to open Dallas with 2–3 aircraft, in roughly 5 days at its current profit.', 'Watch nightly']]
story.append(table(dec, [1.75*inch, 4.25*inch, 0.95*inch]))
story.append(NextPageTemplate('rest')); story.append(PageBreak())
# ---------------- page 2: performance
story.append(P('PERFORMANCE', 'kicker'))
story.append(P('Every airline is now profitable day to day. Kingfisher has gone from short of cash to a small cushion, and Malaysia\'s week was dragged down by refits.', 'h1'))
rows=[['Airline','Aircraft','On order','Routes','Flights a day','Seats a day','Profit a day, 2–4 Oct','Week average','Cash','Fixed, next 7 days','Surplus']]
for a in AL:
    k=kpi[a]; f=fin[a]
    rows.append([f'<b>{SH[a]}</b>', str(k['aircraft']), str(k['on_order']), str(k['routes']), str(k['flights_day']), f"{k['seats_day']:,}",
                 colored(f['last_profit']), colored(f['avg_profit_week']), f"{f['cash']:.2f}M", f"{f['fixed7']:.2f}M", colored(f['surplus'], f"{f['surplus']:.2f}M")])
rows.append(['<b>Group</b>', f"<b>{tot('aircraft')}</b>", f"<b>{tot('on_order')}</b>", f"<b>{tot('routes')}</b>", f"<b>{tot('flights_day')}</b>", f"<b>{tot('seats_day'):,}</b>",
             f"<b>{colored(glast)}</b>", f"<b>{colored(gwk)}</b>", f"<b>{gcash:.2f}M</b>", f"<b>{gfix:.2f}M</b>", f"<b>{gsur:.2f}M</b>"])
story.append(table(rows, [0.82*inch,0.5*inch,0.5*inch,0.48*inch,0.55*inch,0.62*inch,0.72*inch,0.66*inch,0.55*inch,0.62*inch,0.58*inch], bold_last=True))
story.append(P('Profit a day = change in cash plus aircraft order payments (orders are investments); cabin refits are counted as losses. Surplus = cash minus fixed costs due in the next 7 days, minus orders placed since the last cash report.', 'tiny'))
story.append(Spacer(1,6)); story.append(Image('c_profit.png', width=W, height=W*2.7/7.2))
story.append(P('What sits behind the numbers', 'h2'))
story+=bullets([
 '<b>The early-week losses were payment days and refits, not weak trading.</b> Malaysia booked 1.2M of cabin refits on 2 Oct (six A321s moved to Leisure Plus after a plan-card error) and Virgin 0.2M (G-AADI). Without them, Malaysia averaged about +0.3M a day.',
 '<b>Pan Am and Ryanair are the cash engines,</b> each earning over 1M a day at the latest reading. They were the only two that could order, and both did: an A321XLR (N015AW) for JFK–Gatwick, and an E195 (EI-ABL).',
 '<b>Fixed costs rose to 24.0M a week</b> as the new aircraft start paying leases. That is why surplus, not profit, is the binding constraint on growth for the next two weeks.',
])
story.append(PageBreak())
# ---------------- page 3: network & operations
story.append(P('NETWORK AND OPERATIONS', 'kicker'))
story.append(P('Forty aircraft entered service in seven days. The network is filling well, with soft spots concentrated on routes opened this week.', 'h1'))
left=[Image('c_fleet.png', width=3.3*inch, height=3.3*inch*2.3/3.5)]
ops=[['Airline','Aircraft by type'],
     ['Ryanair','9 A321neo · 11 E195'],['Kingfisher','6 A321neo · 1 A320neo · 3 A321XLR · 2 A350'],['Pan Am','5 A321neo · 8 A321XLR · 1 A350'],
     ['Virgin','9 A321neo · 3 E195'],['China Eastern','9 A321neo · 3 E195'],['Malaysia','9 A321neo · 3 E195']]
right=[table(ops, [1.0*inch, 2.4*inch]), Spacer(1,4), P(f"The group flies about <b>{tot('flights_day')} flights</b> and <b>{tot('seats_day'):,} seats</b> a day on <b>{tot('routes')} routes</b>, roughly {tot('block_day'):,} flying hours a day.", 'small')]
two=Table([[left, right]], colWidths=[3.4*inch, W-3.4*inch]); two.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),0),('RIGHTPADDING',(0,0),(-1,-1),6)]))
story.append(two)
story.append(P('Loads: where the network is soft', 'h2'))
lrows=[['Route','Airline','Loads this week','Read'],
 ['Delhi–JFK (A350)','Kingfisher','40–80%, climbing','Business sells out; economy is the gap. Parked until the 2 Nov review.'],
 ['Delhi–Amsterdam','Kingfisher','55–68%','The weakest of the XLR routes to Europe; watch.'],
 ['Amsterdam–Copenhagen (2nd daily)','Ryanair','15–47% on 2 Oct; full 3–4 Oct','Recovered; keep both flights for now.'],
 ['Chongqing, Hyderabad, Xi\'an','Malaysia','26–61%','New this week and ramping; Chennai went from 26% to 82% in five days.'],
 ['Toulouse, Copenhagen, Oslo, Brussels','Virgin','65–83%','New on 1–2 Oct and ramping.'],
 ['Qingdao (return)','China Eastern','51–73%','The only soft China Eastern flight.'],
 ['JFK–Toronto','Pan Am','48% to 92%','Improving fast; still on a 90% price test.']]
story.append(table(lrows, [1.85*inch, 0.85*inch, 1.35*inch, 2.9*inch]))
story.append(P('Everything else reported 95% or fuller on every day of the week. The nightly report only lists flights under 95%.', 'tiny'))
story.append(P('Operations notes', 'h2'))
story+=bullets([
 '<b>Planning:</b> every aircraft is now planned together after it lands, one airline at a time, with at least 10 flying hours a day. Thirteen aircraft went through that process this week, averaging about 12 hours.',
 '<b>Cabins:</b> seven refits to Leisure Plus (1.4M, booked as a loss). A new 195-seat A321 Leisure cabin (Lie-Flat business) replaces the 172-seat one for new aircraft, and 26 existing A321s are due to convert from 11 Oct.',
 '<b>Lost time:</b> eleven delivered aircraft sat idle for one to two days before scheduling, and the 3 Oct report had to be recovered. The leases hadn\'t started yet, so the cost was revenue only, but same-day scheduling is worth protecting.',
 '<b>Network fixes:</b> Phnom Penh\'s old airport (PNH) is closed in the game. All routes now point to Techo International (KTI).',
])
story.append(PageBreak())
# ---------------- page 4: markets
story.append(P('COMPETITION — MARKETS', 'kicker'))
story.append(P('We lead four markets outright, all built around South Asia. Everywhere else we are a challenger with under 10%.', 'h1'))
story.append(Image('c_markets.png', width=W, height=W*4.1/7.2))
M={m['market']:m for m in R['mtab']}
mk=[['Market','Seats a week','Our share','Our rank','Leader','Who carries our share']]
for name in ['India domestic','North America–South Asia','Europe–South Asia','South Asia–SE Asia','China–SE Asia','Transatlantic','Intra-Europe','China–NE Asia','China domestic','Intra-SE Asia','US domestic','South Asia–Gulf']:
    m=M[name]; lead=m['top'][0]
    mk.append([f'<b>{name}</b>', f"{m['seats']:,}", f"{m['our_share']*100:.1f}%", f"{m['rank_ours']} of {m['n_airlines']}", f"{lead[0]} {lead[2]*100:.0f}%", ', '.join(f"{a} {s*100:.1f}%" for a,_,s in m['ours_by'])])
story.append(table(mk, [1.65*inch,0.8*inch,0.62*inch,0.62*inch,1.45*inch,1.81*inch]))
story.append(P('Seats estimated from each flight\'s aircraft type. Markets group airports by region; domestic markets are shown separately for the largest countries.', 'tiny'))
story.append(PageBreak())
story.append(P('COMPETITION — MARKETS', 'kicker'))
story.append(P('Where the growth is: the biggest markets we barely touch, and the ones our own plan will open next.', 'h1'))
big=[['Market','Seats a week','Leader','Our position','Why it matters'],
 ['Intra-Europe', f"{M['Intra-Europe']['seats']:,}", 'Interflug 11%, Lufthansa 9%', '9.3% (9th of 20)', 'The largest market in the game and fragmented: no one holds more than 11%. Ryanair and Virgin can keep taking share route by route.'],
 ['US domestic', f"{M['US domestic']['seats']:,}", 'US Airways 31%', '2.6% (11th of 13)', 'Second largest. Pan Am is a JFK airline today; Dallas and LAX are where a domestic network would come from.'],
 ['China domestic', f"{M['China domestic']['seats']:,}", 'Air China 58%', '5.3% (5th of 6)', 'Concentrated. China Eastern grows best where Air China is thin: Daxing, Xi\'an, Kunming and regional cities.'],
 ['Japan domestic', f"{M['Japan domestic']['seats']:,}", 'ANA 66%', 'not flown', 'Reached through our new ANA interline. China Eastern\'s Haneda flight feeds it.'],
 ['Australia domestic', f"{M['Australia domestic']['seats']:,}", 'Qantas 59%', 'not flown', 'Feed for Malaysia\'s future Oceania routes, through an interline partner.'],
 ['Intra-SE Asia', f"{M['Intra-SE Asia']['seats']:,}", 'Singapore Airlines 39%', '6.6% (4th of 5)', 'Malaysia\'s home market, with Singapore Airlines and VietJet (32%) ahead.'],
 ['Indonesia domestic', f"{M['Indonesia domestic']['seats']:,}", 'Garuda 100%', 'via Garuda', 'Our interline partner since 2 Oct; Jakarta, Bali and Semarang feed into it.'],
 ['Asia–Oceania', f"{M['Asia–Oceania']['seats']:,}", 'Qantas 38%, Virgin Australia 33%', 'not flown', 'Malaysia\'s long-haul trigger is met (39 cities). Singapore Airlines has only 7% here.'],
 ['Europe–SE Asia', f"{M['Europe–SE Asia']['seats']:,}", 'Singapore Airlines 53%', 'not flown', 'Small today. KLM and Singapore Airlines have just signed an interline to grow it through Amsterdam.'],
 ['Transpacific', f"{M['Transpacific']['seats']:,}", 'EVA Air 50%, Cathay 41%', 'not flown', 'Pan Am\'s role. Only two airlines fly it.']]
story.append(table(big, [1.15*inch,0.8*inch,1.45*inch,0.95*inch,2.6*inch]))
story.append(PageBreak())
# ---------------- page 6: hubs and rivals
story.append(P('COMPETITION — HUBS AND RIVALS', 'kicker'))
story.append(P('We are the biggest airline at four of our fourteen bases. At KUL, Gatwick, CDG and Amsterdam a single rival out-flies us.', 'h1'))
story.append(Image('c_hubs.png', width=W, height=W*3.7/7.2))
story.append(P('Weekly departures by airline from each airport\'s public page, 5 Oct. Slot availability is 93% or better everywhere, so no base is close to capacity.', 'tiny'))
story.append(P('Who we meet on our own routes', 'h2'))
rv=R['rivals']; order=['Ryanair','Virgin','Pan Am','China Eastern','Malaysia','Kingfisher']
rrows=[['Our airline','Main rivals on our routes (their flights a week on the same airport pairs)','Read']]
reads={'Ryanair':'Fighting the home carriers at both bases. Air France and KLM fly far more on most of our trunks.',
       'Virgin':'easyJet is on almost every Gatwick route. Etihad opened Manchester on 4 Oct.',
       'Pan Am':'United dominates O\'Hare and the Denver and Chicago trunks. Air Canada owns JFK–Toronto.',
       'China Eastern':'Air China on Beijing–Shanghai (140 a week against our 28) and in Xi\'an and Kunming.',
       'Malaysia':'Singapore Airlines is the rival, overwhelmingly on KUL–Singapore. Elsewhere Malaysia is mostly alone.',
       'Kingfisher':'Almost uncontested: only Emirates (Delhi–Dubai) overlaps.'}
for a in order: rrows.append([f'<b>{a}</b>', ', '.join(f"{n} {v}" for n,v in rv.get(a,[])[:5]), reads[a]])
story.append(table(rrows, [0.95*inch, 3.15*inch, 2.85*inch]))
story.append(P(f"{R['contested']} of our {R['ourpairs']} airport pairs ({R['contested']/R['ourpairs']*100:.0f}%) have a competitor on them. The rest we fly alone.", 'small'))
story.append(PageBreak())
# ---------------- page 7: rival moves + world ranking
story.append(P('COMPETITION — MOVES THIS WEEK', 'kicker'))
story.append(P('Rivals are moving into our airports: Emirates to JFK, Etihad to Manchester, Asiana to KUL, and Tianjin Airlines across Daxing.', 'h1'))
mv=[['Date','Airline','Move','Why it matters to us'],
 ['4 Oct','Emirates','Opened New York (JFK)','Competes with Pan Am at JFK and offers India–US connections via Dubai, against Kingfisher\'s Delhi–JFK. We declined its interline request.'],
 ['4 Oct','Etihad','Opened Manchester','A Gulf carrier at Virgin\'s second hub, pulling UK–Asia traffic through Abu Dhabi.'],
 ['4 Oct','Asiana','Opened Kuala Lumpur','A Korean carrier at Malaysia\'s hub. Watch for more North Asian entries.'],
 ['5 Oct','Tianjin Airlines','15 new stations from Daxing (Korea, Taiwan, NE China)','A fast-growing rival at China Eastern\'s newest base.'],
 ['30 Sep–1 Oct','Korean Air, Shandong','Opened Shanghai Pudong; Shandong also Xi\'an and Kunming','More competition at three of China Eastern\'s four bases.'],
 ['28 Sep','KLM + Singapore Airlines','Interline signed','Europe–SE Asia through Amsterdam: a future rival to Malaysia\'s long-haul plan.'],
 ['1–4 Oct','KLM','Opened Atlanta, Rome, London Stansted','KLM is expanding from Ryanair\'s Amsterdam base.'],
 ['30 Sep','Air France','Opened Moscow, St Petersburg, Kyiv, Sofia, Munich; interlines with ANA','The CDG home carrier is pushing east and into Asia.'],
 ['28–30 Sep','Copa, Avianca','Opened JFK and O\'Hare; Avianca–United interline','Latin American carriers arriving at Pan Am\'s bases.'],
 ['27 Sep–4 Oct','British Caledonian','Opened Budapest, Prague, Athens, Cairo, Orlando, Leeds','Expanding fast from Heathrow, and still Pan Am\'s interline partner until 10 Oct.']]
story.append(table(mv, [0.78*inch,1.05*inch,1.75*inch,3.37*inch]))
story.append(P('Where we rank', 'h2'))
rk=R['rank']; ours={n:(r,w) for r,n,w in R['our_rank']}
top=[['Rank','Airline','Flights a week']]+[[str(i+1), n, f"{w:,}"] for i,(n,w,o) in enumerate(rk[:8])]
mine=[['Rank','Our airline','Flights a week']]+[[str(r), n, f"{w:,}"] for r,n,w in R['our_rank']]
tw=Table([[table(top,[0.45*inch,1.75*inch,0.9*inch]), table(mine,[0.45*inch,1.75*inch,0.9*inch])]], colWidths=[W/2]*2)
tw.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),0)]))
story.append(tw)
story.append(P(f"Out of {R['world']['flying']} airlines flying in Gander ({R['world']['airlines']} registered). Together the group would rank about 3rd by weekly flights ({ourweekly:,}), behind Air China and US Airways.", 'small'))
story.append(PageBreak())
# ---------------- page 8: risks
story.append(P('RISKS', 'kicker'))
story.append(P('The biggest risk is self-inflicted: running cash too thin while the new leases start. The biggest outside threat is Singapore Airlines at KUL.', 'h1'))
rk=[['Risk','Likelihood','Impact','Owner','What we do about it'],
 ['<b>Cash cover thins as leases start.</b> Group surplus is 5.7M against 24.0M of fixed costs due in 7 days; Kingfisher has 0.4M.','Medium','High','All','Order only when surplus covers the price; cash and fixed costs nightly; stage the 5.2M cabin conversion by airline.'],
 ['<b>Singapore Airlines at KUL.</b> 315 departures a week against our 196, 39% of SE Asia\'s internal market, and a new interline with KLM.','High','High','Malaysia','Grow where it is thin: South Asia (we lead with 48%), China\'s secondary cities, the night bank. Use the Garuda interline.'],
 ['<b>Gulf carriers in India.</b> They lead Mumbai and hold 89% of South Asia–Gulf. Emirates is now at JFK.','Medium','High','Kingfisher','Open Mumbai as a banked hub before they grow further; keep declining Gulf interlines.'],
 ['<b>Air China\'s weight in China.</b> 58% of domestic seats; 140 against 28 flights a week on Beijing–Shanghai. Tianjin Airlines is growing at Daxing.','Medium','Medium','China Eastern','Avoid head-on trunk wars; build Daxing, Xi\'an and Kunming and the regional cities.'],
 ['<b>London squeeze.</b> easyJet leads Gatwick; British Caledonian dominates Heathrow and is expanding; Etihad is now at Manchester.','Medium','Medium','Virgin','Compete on connections (banks plus the Pan Am JFK–Gatwick feed); end the British Caledonian interline.'],
 ['<b>Kingfisher long-haul drag.</b> Delhi–JFK at 40–80%, Delhi–Amsterdam at 55–68%.','Medium','Medium','Kingfisher','Parked until 2 Nov to judge with a bigger network; then a business-heavier cabin or a split.'],
 ['<b>Execution slips.</b> Idle days on delivered aircraft, a missed report, and deploy credits (about 465 of 1,000 used since 29 Sep).','Medium','Low','Planning','Schedule arrivals the same day; batch planner changes into fewer deploys.']]
story.append(table(rk, [2.35*inch,0.65*inch,0.55*inch,0.75*inch,2.65*inch]))
story.append(PageBreak())
# ---------------- page 9: opportunities
story.append(P('OPPORTUNITIES', 'kicker'))
story.append(P('Our best returns are in markets nobody else serves well: India, South Asia to SE Asia, and the China–SE Asia corridor.', 'h1'))
op=[['#','Opportunity','Size','Where we are','Next move'],
 ['1','<b>India domestic</b>, flown only by Kingfisher', f"{M['India domestic']['seats']:,} seats a week", '100%', 'Every Kingfisher aircraft adds uncontested capacity. Still unflown 4★ cities: Patna, Bhubaneswar, Guwahati, Thiruvananthapuram. Then Mumbai as the second hub.'],
 ['2','<b>China–SE Asia</b>, a corridor we can lead', f"{M['China–SE Asia']['seats']:,}", '17%, 4th (leader Air China 27%)', 'Malaysia\'s China secondary cities (Hangzhou now; Xiamen, Changsha, Wuhan next) could make the group the leader.'],
 ['3','<b>Defend our two South Asia leads</b>', f"{M['South Asia–SE Asia']['seats']+M['Europe–South Asia']['seats']:,}", '48% and 52%, 1st', 'Malaysia\'s India routes are ramping. Kingfisher\'s Europe XLRs need loads; Turkish Airlines holds 35% of Europe–South Asia.'],
 ['4','<b>Transatlantic</b>', f"{M['Transatlantic']['seats']:,}", '8%, 3rd (Icelandair 31%)', 'N015AW on JFK–Gatwick from about 6 Oct, timed into Virgin\'s banks. More Europe from JFK as Pan Am\'s money allows.'],
 ['5','<b>Asia–Oceania</b> for Malaysia', f"{M['Asia–Oceania']['seats']:,}", 'not flown', 'The long-haul trigger is met. First XLRs to Perth, Darwin and Sydney when Malaysia\'s surplus allows.'],
 ['6','<b>Interline feed already signed</b>', 'Garuda: 292k · ANA: 617k domestic seats', 'live from 2 Oct', 'Time Jakarta, Bali and Haneda flights into the partners\' banks (Jakarta already is).'],
 ['7','<b>Daxing</b>, China Eastern\'s new base', '93 departures a week at the airport', '38%, 1st', 'Three new 5★ routes opened with B-0165. Add more before Tianjin Airlines fills the gaps.'],
 ['8','<b>Intra-Europe\'s fragmentation</b>', f"{M['Intra-Europe']['seats']:,}", '9.3%, 9th', 'No airline holds more than 11%. Each Ryanair and Virgin aircraft can win share route by route.']]
story.append(table(op, [0.25*inch,1.55*inch,1.1*inch,1.2*inch,2.85*inch]))
story.append(PageBreak())
# ---------------- page 10: plan and progress
story.append(P('PLAN AND PROGRESS', 'kicker'))
story.append(P('The delivery wave is on schedule and growth is following the rotation. The new planning routine is working.', 'h1'))
story.append(P('What we did this week', 'h2'))
story+=bullets([
 '<b>Fleet:</b> 40 aircraft into service (42 to 82). Eighteen more of the wave arrive by 9 Oct, plus EI-ABL and N015AW.',
 '<b>Network:</b> a new China Eastern base at Daxing. Malaysia\'s route list now covers every Singapore Airlines destination outside the US, after adding nine routes (Brussels, Copenhagen, Rome, Madrid, Zurich, Nagoya, Christchurch, Johannesburg, Cape Town).',
 '<b>Partners:</b> interlines signed with Garuda (Malaysia–Indonesia) and ANA (China Eastern–Japan). Emirates declined. British Caledonian to be cancelled 10 Oct. No Philippine partner exists yet.',
 '<b>Decisions:</b> Delhi–JFK parked for a month; Asia and Oceania to southern Africa assigned to Malaysia; at least 10 flying hours a day for every aircraft unless there is a stated reason; plans built after arrival, one airline at a time.',
 '<b>Tools:</b> the planner was redesigned. Cabins, competitor scanning and this report are now part of the weekly routine.',
])
story.append(P('Growth rotation', 'h2'))
gr=[['Airline','Moves made this week','Next move'],
 ['Ryanair','Big market (Amsterdam routes), then frequency (EI-ABI: Barcelona, Valencia, Lisbon)','Smaller feeder: EI-ABL (E195) arriving 5 Oct'],
 ['Kingfisher','Feeder (Indore, Varanasi, Bhopal), then big market (VT-AAM: Pune, Kochi, Ahmedabad)','Frequency, when its surplus allows'],
 ['Pan Am','Big market (O\'Hare); ordered N015AW for JFK–Gatwick (big market, off-rotation)','Frequency on the full JFK routes; Dallas when it has money for 2–3 aircraft'],
 ['Virgin','Frequency (G-AAEC, G-AADN), then big market (G-AADO: Cairo plus short-hop second dailies)','Frequency'],
 ['China Eastern','Frequency (B-0220), then big market (B-0164, B-0165 opening Daxing)','Frequency'],
 ['Malaysia','Feeder (9M-AAR), big market (9M-AAH: Jakarta, Hangzhou), frequency (9M-AAI)','Smaller feeder']]
story.append(table(gr, [1.0*inch, 3.65*inch, 2.3*inch]))
story.append(P('Coming up', 'h2'))
cu=[['When','What'],
 ['5 Oct','G-AADP, 9M-AAJ, B-0166 (08:53 UTC) · EI-ABL (15:02) · N015AW (21:01) · review Ryanair\'s double-dailies'],
 ['6–9 Oct','The rest of the wave: three aircraft a day for Virgin, China Eastern and Malaysia, ending with G-AADU, 9M-AAO and B-0171 on 9 Oct'],
 ['8 Oct','A321neo frequency orders for Virgin, China Eastern and Malaysia, if surplus allows (likely to slip)'],
 ['10 Oct','Cancel the Pan Am–British Caledonian interline'],
 ['11 Oct','Start converting the 26 A321s to the 195-seat cabin, staged by surplus'],
 ['29 Oct · 2 Nov','Holdings decision (Serbia first) · Kingfisher Delhi–JFK review']]
story.append(table(cu, [0.95*inch, 6.0*inch]))
story.append(P('Watch list', 'h2'))
story+=bullets(['Kingfisher\'s surplus (0.40M) and Delhi–JFK economy loads.','Malaysia\'s new China and India routes filling, and any Singapore Airlines response at KUL.','Tianjin Airlines at Daxing and Air China\'s next moves.','Emirates at JFK; Etihad at Manchester.','Pan Am\'s path to about 7M for Dallas.'])
story.append(Spacer(1,6))
story.append(P('Method: competitor data comes from a full scan of all 161 airlines and 57 airport pages in Gander on 5 Oct (04:53 UTC), the baseline for next week\'s comparison. Our figures come from the planner, the nightly cash and load reports, and the game\'s schedules.', 'tiny'))
doc.build(story)
print('built')
