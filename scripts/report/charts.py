"""The weekly report, step 3 (scripts/README.md): draws the charts from results.json, in the current folder.
Every name and colour comes from results.json (our airlines from rules.json, colours from the website's airlines); no
airline is named here. Makes c_profit.png, c_cash.png, c_fleet.png, c_markets.png and c_hubs.png.
Needs the Liberation Sans fonts."""
import datetime, json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.patches import Patch
for f in ["/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
    font_manager.fontManager.addfont(f)
plt.rcParams.update({"font.family": "Liberation Sans", "font.size": 8.5, "axes.edgecolor": "#C9CDD3", "axes.labelcolor": "#3A3F47", "xtick.color": "#5B616B",
                     "ytick.color": "#5B616B", "axes.spines.top": False, "axes.spines.right": False, "axes.titleweight": "bold", "axes.titlesize": 9.5,
                     "axes.titlecolor": "#1D1D1F", "figure.dpi": 200})
R = json.load(open("results.json"))
AL = R["airlines"]
COL = {a["name"]: a["color"] for a in AL}
INK = "#1D1D1F"; ACC = "#0B5CAD"; GREY = "#B8BEC7"; MUTED = "#5B616B"
n = lambda x: x if isinstance(x, (int, float)) else 0   # noqa: E731 (a missing figure draws as nothing)


def save(name):
    plt.tight_layout(); plt.savefig(name, metadata={"Software": None}); plt.close()


# 1. profit a day: the last 7 days of reported cash, and today's flight profit a day (each airline on its own)
fig, ax = plt.subplots(figsize=(7.2, 0.5 + 0.42 * max(1, len(AL))))
y = range(len(AL)); pd = [a["finance"]["profit_day"] for a in AL]; fp = [a["finance"]["flight_profit_day"] for a in AL]
ax.barh([i + 0.18 for i in y], [n(v) for v in fp], height=0.34, color=GREY)
ax.barh([i - 0.18 for i in y], [n(v) for v in pd], height=0.34, color=[a["color"] for a in AL])
span = max([abs(n(v)) for v in pd + fp] + [0.1])
for i, (p, f) in enumerate(zip(pd, fp)):
    ax.text(max(n(p), 0) + span * 0.02, i - 0.18, "no figure" if p is None else f"{p:+.2f}M", va="center", fontsize=7.5, color=INK)
    ax.text(max(n(f), 0) + span * 0.02, i + 0.18, "no figure" if f is None else f"{f:+.2f}M", va="center", fontsize=7, color=MUTED)
ax.set_yticks(list(y)); ax.set_yticklabels([a["name"] for a in AL]); ax.invert_yaxis()
ax.axvline(0, color="#8A9099", lw=0.8); ax.set_xlabel("AS$ millions a day")
ax.set_xlim(min([0] + [n(v) for v in pd + fp]) - span * 0.1, span * 1.3)
ax.legend(handles=[Patch(color="#3A3F47", label="Profit a day, last 7 days (airline colour)"), Patch(color=GREY, label="Flight profit a day, latest statement")],
          frameon=False, fontsize=7.5, loc="upper center", bbox_to_anchor=(0.5, -0.32 if len(AL) < 4 else -0.16), ncol=2)
ax.grid(axis="x", color="#ECEEF1", lw=0.6); ax.set_axisbelow(True)
save("c_profit.png")

# 2. cash over the next 14 days, each airline's forecast, with the order cushion
fig, ax = plt.subplots(figsize=(7.2, 2.9))
t0 = None
for a in AL:
    pts = [(datetime.datetime.fromisoformat(p["at"].replace("Z", "+00:00")), p["balance"]) for p in a["finance"]["points"] if p.get("balance") is not None]
    if not pts:
        continue
    t0 = t0 or pts[0][0]
    ax.plot([(t - pts[0][0]).total_seconds() / 86400 for t, _ in pts], [v for _, v in pts], color=a["color"], lw=1.6, label=a["name"])
    low = a["finance"]["lowest"] or {}
    if low.get("at") and low.get("balance") is not None:
        lt = datetime.datetime.fromisoformat(low["at"].replace("Z", "+00:00"))
        ax.plot([(lt - pts[0][0]).total_seconds() / 86400], [low["balance"]], "o", ms=3.5, color=a["color"])
cushions = {a["finance"]["cushion"] for a in AL if a["finance"].get("cushion") is not None}
for c in cushions:
    ax.axhline(c, color=MUTED, lw=0.8, ls="--")
    ax.text(14, c, " cushion", va="bottom", ha="right", fontsize=6.8, color=MUTED)
ax.set_xlim(0, 14); ax.set_xlabel("Days after each airline's latest capture"); ax.set_ylabel("Cash, AS$ millions")
ax.legend(frameon=False, fontsize=7, ncol=3, loc="upper left"); ax.grid(axis="y", color="#ECEEF1", lw=0.6); ax.set_axisbelow(True)
save("c_cash.png")

# 3. fleet: aircraft in service and on order, by airline
fig, ax = plt.subplots(figsize=(3.4, 0.5 + 0.36 * max(1, len(AL))))
ax.barh(range(len(AL)), [a["ops"]["aircraft"] for a in AL], height=0.55, color=[a["color"] for a in AL])
ax.barh(range(len(AL)), [a["ops"]["on_order"] for a in AL], left=[a["ops"]["aircraft"] for a in AL], height=0.55, color=GREY)
for i, a in enumerate(AL):
    ax.text(a["ops"]["aircraft"] + a["ops"]["on_order"] + 0.4, i, f"{a['ops']['aircraft']}" + (f" + {a['ops']['on_order']}" if a["ops"]["on_order"] else ""), va="center", fontsize=7, color=INK)
ax.set_yticks(range(len(AL))); ax.set_yticklabels([a["name"] for a in AL], fontsize=7.2); ax.invert_yaxis()
ax.set_title("Aircraft in service, and on order (grey)", loc="left")
ax.set_xlim(0, max([a["ops"]["aircraft"] + a["ops"]["on_order"] for a in AL] + [1]) * 1.25); ax.grid(axis="x", color="#ECEEF1", lw=0.6); ax.set_axisbelow(True)
save("c_fleet.png")

# 4. markets: the group's share against the biggest rival's, in the biggest markets we fly
rows = [m for m in R["mtab"] if m["our_seats"] > 0 and m["market"] != "Unknown"][:14]
fig, ax = plt.subplots(figsize=(7.2, 0.6 + 0.25 * max(1, len(rows))))
for i, m in enumerate(rows):
    other = m.get("top_rival") or ["no rival", 0, 0]
    ax.barh(i + 0.2, other[2] * 100, height=0.32, color=GREY)
    ax.barh(i - 0.2, m["our_share"] * 100, height=0.32, color=ACC)
    ax.text(m["our_share"] * 100 + 1, i - 0.2, f"{m['our_share'] * 100:.0f}%", va="center", fontsize=7, color=INK, fontweight="bold")
    ax.text(other[2] * 100 + 1, i + 0.2, f"{other[0]} {other[2] * 100:.0f}%" if other[2] else "no rival", va="center", fontsize=6.6, color=MUTED)
ax.set_yticks(range(len(rows))); ax.set_yticklabels([f"{m['market']}  ({m['seats'] / 1000:,.0f}k seats/wk)" for m in rows], fontsize=7.2); ax.invert_yaxis()
ax.set_xlim(0, 128); ax.set_xlabel("Share of weekly seats (%)"); ax.grid(axis="x", color="#ECEEF1", lw=0.6); ax.set_axisbelow(True)
ax.legend(handles=[Patch(color=ACC, label="Our airlines together"), Patch(color=GREY, label="Biggest rival")], frameon=False, fontsize=7.2,
          loc="upper center", bbox_to_anchor=(0.5, -0.1 if len(rows) > 6 else -0.25), ncol=2)
save("c_markets.png")

# 5. bases: our airline's share of departures against the biggest rival's
H = R["hubtab"]
fig, ax = plt.subplots(figsize=(7.2, 0.6 + 0.25 * max(1, len(H))))
for i, h in enumerate(H):
    our = h["share"] * 100; rv = h["rivals"][0] if h["rivals"] else ["—", 0]; rvs = rv[1] / h["total"] * 100 if h["total"] else 0
    ax.barh(i + 0.18, rvs, height=0.34, color=GREY); ax.barh(i - 0.18, our, height=0.34, color=COL.get(h["airline"], ACC))
    ax.text(our + 0.8, i - 0.18, f"{our:.0f}% ({h['ours']}/wk)", va="center", fontsize=6.8, color=INK, fontweight="bold")
    ax.text(rvs + 0.8, i + 0.18, f"{rv[0]} {rvs:.0f}%", va="center", fontsize=6.4, color=MUTED)
ax.set_yticks(range(len(H))); ax.set_yticklabels([f"{h['hub']} · {h['airline']}" for h in H], fontsize=7.2); ax.invert_yaxis()
ax.set_xlim(0, 100); ax.set_xlabel("Share of weekly departures at the airport (%)"); ax.grid(axis="x", color="#ECEEF1", lw=0.6); ax.set_axisbelow(True)
save("c_hubs.png")
print("charts ok")
