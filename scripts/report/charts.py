import json, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
for f in ['/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf','/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf']: font_manager.fontManager.addfont(f)
plt.rcParams.update({'font.family':'Liberation Sans','font.size':8.5,'axes.edgecolor':'#C9CDD3','axes.labelcolor':'#3A3F47','xtick.color':'#5B616B','ytick.color':'#5B616B','axes.spines.top':False,'axes.spines.right':False,'axes.titleweight':'bold','axes.titlesize':9.5,'axes.titlecolor':'#1D1D1F','figure.dpi':200})
R=json.load(open('results.json'))
LV={'Ryanair':'#F1C21B','Kingfisher':'#D7263D','Pan American':'#2A8FD8','Virgin Atlantic':'#8E1537','China Eastern':'#1C3F8C','Malaysia Airlines':'#0F8C8C'}
SHORT={'Ryanair':'Ryanair','Kingfisher':'Kingfisher','Pan American':'Pan Am','Virgin Atlantic':'Virgin','China Eastern':'China Eastern','Malaysia Airlines':'Malaysia'}
INK='#1D1D1F'; ACC='#0B5CAD'; GREY='#B8BEC7'
# 1. profit per day: week average vs latest (2-4 Oct)
fin=R['fin']; als=list(fin)
fig,ax=plt.subplots(figsize=(7.2,2.7))
y=range(len(als)); wk=[fin[a]['avg_profit_week'] for a in als]; lt=[fin[a]['last_profit'] for a in als]
ax.barh([i+0.18 for i in y], wk, height=0.34, color=GREY, label='Average this week')
ax.barh([i-0.18 for i in y], lt, height=0.34, color=[LV[a] for a in als], label='Latest, 2–4 Oct')
for i,(w,l) in enumerate(zip(wk,lt)):
    ax.text(l+0.02, i-0.18, f"+{l:.2f}M", va='center', fontsize=7.5, color=INK)
    ax.text(max(w,0)+0.02, i+0.18, f"{w:+.2f}M", va='center', fontsize=7, color='#5B616B')
ax.set_yticks(list(y)); ax.set_yticklabels([SHORT[a] for a in als]); ax.invert_yaxis()
ax.axvline(0, color='#8A9099', lw=0.8); ax.set_xlabel('Profit per day (AS$ millions)'); ax.set_xlim(min(0,min(wk))-0.05, max(lt)*1.25)
from matplotlib.patches import Patch
ax.legend(handles=[Patch(color='#3A3F47',label='Latest, 2–4 Oct (airline colour)'),Patch(color=GREY,label='Average this week')], frameon=False, fontsize=7.5, loc='lower right'); ax.grid(axis='x', color='#ECEEF1', lw=0.6); ax.set_axisbelow(True)
plt.tight_layout(); plt.savefig('c_profit.png'); plt.close()
# 2. fleet growth
pts=[('20 Sep',0),('22 Sep',14),('24 Sep',17),('26 Sep',27),('28 Sep',42),('29 Sep',59),('1 Oct',68),('2 Oct',71),('4 Oct',82)]
fig,ax=plt.subplots(figsize=(3.5,2.3))
ax.plot([p[0] for p in pts],[p[1] for p in pts], color=ACC, lw=2, marker='o', ms=3)
ax.fill_between(range(len(pts)),[p[1] for p in pts], color=ACC, alpha=0.08)
ax.text(len(pts)-1, 85, '82', ha='center', fontsize=9, fontweight='bold', color=INK)
ax.set_title('Aircraft in service', loc='left'); ax.set_ylim(0,105); ax.tick_params(axis='x', labelsize=6.5, rotation=0)
ax.set_xticks(range(len(pts))); ax.set_xticklabels([p[0] if i%2==0 or i==len(pts)-1 else '' for i,p in enumerate(pts)])
ax.grid(axis='y', color='#ECEEF1', lw=0.6); ax.set_axisbelow(True)
plt.tight_layout(); plt.savefig('c_fleet.png'); plt.close()
# 3. markets: our share vs the leader's
keep=['India domestic','North America–South Asia','Europe–South Asia','South Asia–SE Asia','China–SE Asia','China–NE Asia','Intra-Europe','Transatlantic','Intra-SE Asia','US/Canada–Mexico & Caribbean','China domestic','NE Asia–SE Asia','US domestic','South Asia–Gulf']
M={m['market']:m for m in R['mtab']}
rows=[M[k] for k in keep if k in M]
fig,ax=plt.subplots(figsize=(7.2,4.1))
for i,m in enumerate(rows):
    lead_name,_,lead=m['top'][0]; ours=m['our_share']
    leader_is_us = lead_name in ('Ryanair','Kingfisher','Pan Am','Virgin','China Eastern','Malaysia')
    other=next(((n,s) for n,_,s in m['top'] if n not in ('Ryanair','Kingfisher','Pan Am','Virgin','China Eastern','Malaysia')), ('no rival',0))
    ax.barh(i+0.2, other[1]*100, height=0.32, color=GREY)
    ax.barh(i-0.2, ours*100, height=0.32, color=ACC)
    ax.text(ours*100+1, i-0.2, f"{ours*100:.0f}%", va='center', fontsize=7, color=INK, fontweight='bold')
    ax.text(other[1]*100+1, i+0.2, (f"{other[0]} {other[1]*100:.0f}%" if other[1] else 'no rival'), va='center', fontsize=6.6, color='#5B616B')
ax.set_yticks(range(len(rows))); ax.set_yticklabels([f"{m['market']}  ({m['seats']/1000:,.0f}k seats/wk)" for m in rows], fontsize=7.2); ax.invert_yaxis()
ax.set_xlim(0,128); ax.set_xlabel('Share of weekly seats (%)'); ax.grid(axis='x', color='#ECEEF1', lw=0.6); ax.set_axisbelow(True)
from matplotlib.patches import Patch
ax.legend(handles=[Patch(color=ACC,label='Equinox group'),Patch(color=GREY,label='Biggest rival')], frameon=False, fontsize=7.2, loc='lower right')
plt.tight_layout(); plt.savefig('c_markets.png'); plt.close()
# 4. hubs: our airline's share of departures vs the biggest rival
H=R['hubtab']
fig,ax=plt.subplots(figsize=(7.2,3.7))
for i,h in enumerate(H):
    our=h['share']*100; rv=h['rivals'][0] if h['rivals'] else ['—',0]; rvs=rv[1]/h['total']*100 if h['total'] else 0
    ax.barh(i+0.18, rvs, height=0.34, color=GREY); ax.barh(i-0.18, our, height=0.34, color=LV[{'Pan Am':'Pan American','Kingfisher':'Kingfisher','Ryanair':'Ryanair','Virgin':'Virgin Atlantic','China Eastern':'China Eastern','Malaysia':'Malaysia Airlines'}[h['airline']]])
    ax.text(our+0.8, i-0.18, f"{our:.0f}% ({h['ours']}/wk)", va='center', fontsize=6.8, color=INK, fontweight='bold')
    ax.text(rvs+0.8, i+0.18, f"{rv[0]} {rvs:.0f}%", va='center', fontsize=6.4, color='#5B616B')
ax.set_yticks(range(len(H))); ax.set_yticklabels([f"{h['hub']} · {h['airline']}" for h in H], fontsize=7.2); ax.invert_yaxis()
ax.set_xlim(0,95); ax.set_xlabel('Share of weekly departures at the airport (%)'); ax.grid(axis='x', color='#ECEEF1', lw=0.6); ax.set_axisbelow(True)
plt.tight_layout(); plt.savefig('c_hubs.png'); plt.close()
print('charts ok')
