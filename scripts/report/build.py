"""The weekly report, step 4 (scripts/README.md): lays out the PDF briefing from results.json, the charts and notes.json.

- Every figure comes from results.json (analyze.py): no figure is typed in here. Money is each airline's own, from the
  database's captured figures; there is no surplus figure and no group row (manual §1, §3).
- The week and the file name come from the figures' date (its ISO week): Equinox_Weekly_Briefing_<year>-W<week>.pdf.
- The week's written text comes from notes.json, which the Saturday review writes (scripts/report/notes.example.json
  shows every part): the week in one line, what matters, decisions, each section's headline and notes, the rivals'
  reads, rivals' moves, risks, opportunities, the plan (done, coming up, watch list). A part with no notes is left out.

Usage, from the working folder: python3 <repository>/scripts/report/build.py [--notes notes.json] [--out ~/report]
Needs the Liberation Sans fonts.
"""
import argparse, datetime, json, os
from xml.sax.saxutils import escape
from reportlab import rl_config
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import registerFontFamily
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, Image, KeepTogether, NextPageTemplate, PageBreak, PageTemplate, Paragraph, Spacer, Table,
                                TableStyle)

rl_config.invariant = 1   # the same input always gives the same file (no build time in it)
ap = argparse.ArgumentParser()
ap.add_argument("--notes", default="notes.json")
ap.add_argument("--out", default=os.path.expanduser("~/report"))
args = ap.parse_args()
pdfmetrics.registerFont(TTFont("LS", "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"))
pdfmetrics.registerFont(TTFont("LSB", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("LSI", "/usr/share/fonts/truetype/liberation/LiberationSans-Italic.ttf"))
registerFontFamily("LS", normal="LS", bold="LSB", italic="LSI", boldItalic="LSB")

R = json.load(open("results.json"))
N = json.load(open(args.notes)) if os.path.exists(args.notes) else {}
AL = R["airlines"]
INK = colors.HexColor("#1D1D1F"); MUTED = colors.HexColor("#5B616B"); FAINT = colors.HexColor("#8A9099"); LINE = colors.HexColor("#E3E6EA")
ACC = colors.HexColor("#0B5CAD"); BAND = colors.HexColor("#0F1B2D"); POS = colors.HexColor("#1A7F37"); NEG = colors.HexColor("#C4141C"); SOFT = colors.HexColor("#F4F6F8")
st = {}


def S(name, **kw):
    base = dict(fontName="LS", fontSize=9, leading=12.4, textColor=INK); base.update(kw); st[name] = ParagraphStyle(name, **base); return st[name]


S("body"); S("small", fontSize=7.6, leading=10, textColor=MUTED); S("tiny", fontSize=6.8, leading=8.6, textColor=FAINT)
S("h1", fontName="LSB", fontSize=15, leading=19, spaceAfter=4); S("kicker", fontName="LSB", fontSize=7.6, leading=10, textColor=ACC, spaceAfter=2)
S("h2", fontName="LSB", fontSize=10.5, leading=14, spaceBefore=8, spaceAfter=3); S("lead", fontSize=10, leading=14, textColor=colors.HexColor("#2E333A"))
S("cell", fontSize=7.6, leading=9.6); S("cellb", fontName="LSB", fontSize=7.6, leading=9.6)
S("bul", fontSize=9, leading=12.4, leftIndent=11, bulletIndent=0, spaceAfter=3)
P = lambda t, s="body": Paragraph(t, st[s])   # noqa: E731
esc = lambda x: escape(str(x))   # noqa: E731 (names and other text from the data)


def bullets(items):
    return [Paragraph(t, st["bul"], bulletText="•") for t in items]


def table(rows, widths, head=True):
    data = [[c if not isinstance(c, str) else Paragraph(c, st["cellb" if (head and i == 0) else "cell"]) for c in r] for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1 if head else 0)
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("LINEBELOW", (0, 0), (-1, 0), 0.8, INK), ("LINEBELOW", (0, 1), (-1, -1), 0.4, LINE),
                           ("TOPPADDING", (0, 0), (-1, -1), 3.2), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.2), ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4)]))
    return t


# ---------------- formats: money in millions of AS$, as the figures give it
def money(x):
    return "—" if x is None else f"{x:.2f}M"


def signed(x):
    if x is None:
        return "—"
    return f'<font color="{"#1A7F37" if x >= 0 else "#C4141C"}">{x:+.2f}M</font>'


def moment(ts):
    return datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00")) if ts else None


def day(ts):
    m = moment(ts)
    return f"{m.day} {m:%b}" if m else "—"


def next_order(no):
    """The next order as the cash forecast gives it (manual §3): now, a type from a day, not within 14 days, or what is
    missing."""
    w = (no or {}).get("when")
    if w == "now":
        return "Now: " + ", ".join(no.get("types") or [])
    if w == "later":
        return f"{no.get('type')} from {day(no.get('safe_from'))}"
    if w == "not within 14 days":
        return "Not within 14 days"
    if w == "needs":
        return "Needs " + (no.get("missing") or "a capture")
    return "—"


def pct(x, digits=0):
    return "—" if x is None else f"{x:.{digits}f}%"


def num(x, digits=0):
    return "—" if x is None else f"{x:,.{digits}f}"


def note(*keys):
    v = N
    for k in keys:
        v = v.get(k) if isinstance(v, dict) else None
    return v or None


def by_airline(notes_map, a):
    """A note kept per airline in notes.json: keyed by the airline's code or its name."""
    return (notes_map or {}).get(a.get("code")) or (notes_map or {}).get(a["name"])


# ---------------- the week, from the figures' date
AS_OF = moment(R["as_of"])
D = AS_OF.date()
ISO = D.isocalendar()
MONDAY = D - datetime.timedelta(days=D.weekday())
RANGE = f"{D.day} {D:%b %Y}" if MONDAY == D else (f"{MONDAY.day} {MONDAY:%b} – {D.day} {D:%b %Y}" if MONDAY.month != D.month else f"{MONDAY.day} – {D.day} {D:%b %Y}")
WEEK = f"Week {ISO.week}, {RANGE}"
SCAN = moment((R.get("scan") or {}).get("taken_at"))
os.makedirs(args.out, exist_ok=True)
OUT = os.path.join(args.out, f"Equinox_Weekly_Briefing_{ISO.year}-W{ISO.week:02d}.pdf")


def on_page(c, doc):
    c.saveState(); w, h = letter
    if doc.page == 1:
        c.setFillColor(BAND); c.rect(0, h - 1.62 * inch, w, 1.62 * inch, fill=1, stroke=0)
        c.setFillColor(colors.HexColor("#F1C21B")); c.rect(0.75 * inch, h - 1.62 * inch, 0.6 * inch, 0.05 * inch, fill=1, stroke=0)
    else:
        c.setFont("LSB", 7.4); c.setFillColor(INK); c.drawString(0.75 * inch, h - 0.5 * inch, "equinox.")
        c.setFont("LS", 7.4); c.setFillColor(FAINT); c.drawString(0.75 * inch + 34, h - 0.5 * inch, f"·  Weekly briefing  ·  {WEEK}")
        c.setStrokeColor(LINE); c.setLineWidth(0.6); c.line(0.75 * inch, h - 0.58 * inch, w - 0.75 * inch, h - 0.58 * inch)
    c.setFont("LS", 7); c.setFillColor(FAINT)
    c.drawString(0.75 * inch, 0.45 * inch, f"Internal · the database's figures as of {D.day} {D:%b %Y}, {AS_OF:%H:%M} UTC"
                 + (f" · world scan of {SCAN.day} {SCAN:%b}, {SCAN:%H:%M} UTC" if SCAN else ""))
    c.drawRightString(w - 0.75 * inch, 0.45 * inch, f"{doc.page}")
    c.restoreState()


def cover(c, doc):
    on_page(c, doc); w, h = letter
    c.setFillColor(colors.white); c.setFont("LSB", 23); c.drawString(0.75 * inch, h - 0.82 * inch, "equinox. — Weekly briefing")
    c.setFont("LS", 10); c.setFillColor(colors.HexColor("#C9D3E0")); c.drawString(0.75 * inch, h - 1.1 * inch, f"{WEEK}  ·  figures as of {AS_OF:%H:%M} UTC on {D.day} {D:%b}")
    c.setFont("LS", 8.2); c.setFillColor(colors.HexColor("#8FA0B6")); c.drawString(0.75 * inch, h - 1.33 * inch, "  ·  ".join(a["name"] for a in AL))


doc = BaseDocTemplate(OUT, pagesize=letter, leftMargin=0.75 * inch, rightMargin=0.75 * inch, topMargin=0.78 * inch, bottomMargin=0.7 * inch,
                      title=f"equinox. — Weekly briefing, week {ISO.week} {ISO.year}", author="equinox. planning")
W = letter[0] - 1.5 * inch
f_first = Frame(0.75 * inch, 0.7 * inch, W, letter[1] - 0.7 * inch - 1.62 * inch - 0.18 * inch, id="first", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
f_rest = Frame(0.75 * inch, 0.7 * inch, W, letter[1] - 0.78 * inch - 0.7 * inch, id="rest", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
doc.addPageTemplates([PageTemplate(id="first", frames=[f_first], onPage=cover), PageTemplate(id="rest", frames=[f_rest], onPage=on_page)])
story = []


def section(kicker, key, default_title):
    story.append(P(kicker, "kicker"))
    story.append(P(note(key, "title") or default_title, "h1"))


def image(name, ratio_w, ratio_h):
    if os.path.exists(name):
        story.append(Image(name, width=W, height=W * ratio_h / ratio_w))


# ---------------- page 1: the week in one line, what matters, decisions (all from the notes), and the money at a glance
if note("week_line"):
    story += [P("THE WEEK IN ONE LINE", "kicker"), P(N["week_line"], "lead"), Spacer(1, 9)]
if note("what_matters"):
    story += [P("What matters this week", "h2")] + bullets(N["what_matters"])
if note("decisions"):
    story.append(P("Decisions for you", "h2"))
    story.append(table([["Decision", "Recommendation", "When"]] + [[d.get("decision", ""), d.get("recommendation", ""), d.get("when", "")] for d in N["decisions"]],
                       [1.75 * inch, 4.25 * inch, 0.95 * inch]))

# ---------------- performance: each airline's money (the captured figures)
story.append(P("Each airline's money", "h2" if story else "h1"))
fin = [["Airline", "Cash", "Profit a day", "Flight profit a day", "Lowest in 14 days", "When", "Next order"]]
for a in AL:
    f = a["finance"]; low = f.get("lowest") or {}
    fin.append([f"<b>{esc(a['name'])}</b>", money(f["cash"]), signed(f["profit_day"]), signed(f["flight_profit_day"]),
                money(low.get("balance")), day(low.get("at")), esc(next_order(f["next_order"]))])
story.append(table(fin, [1.12 * inch, 0.62 * inch, 0.7 * inch, 0.78 * inch, 0.8 * inch, 0.5 * inch, 2.48 * inch]))
cush = sorted({a["finance"]["cushion"] for a in AL if a["finance"].get("cushion") is not None})
story.append(P("Money in millions of AS$, from the database's captured figures, each airline on its own. Cash: the latest captured balance. "
               "Profit a day: the change in cash over the last 7 days of captures, with order payments added back. Flight profit a day: "
               "profit a flight in the latest day's bank statement × planned flights a day. Lowest in 14 days: the cash forecast's lowest "
               "point after every scheduled payment; an order is safe when "
               + (" or ".join(f"{c:.2f}M" for c in cush) if cush else "the order cushion") + " stays in hand at the lowest point after it"
               + "".join(f"; {esc(a['name'])}: {esc(a['finance']['missing'])}" for a in AL if a["finance"].get("status") != "ok" and a["finance"].get("missing")) + ".", "tiny"))
story.append(NextPageTemplate("rest")); story.append(PageBreak())

section("PERFORMANCE", "performance", "Each airline's profit, and its cash over the next 14 days.")
image("c_profit.png", 7.2, 0.5 + 0.42 * max(1, len(AL)))
story.append(Spacer(1, 4)); image("c_cash.png", 7.2, 2.9)
story.append(P("Each line starts at the airline's latest captured cash and follows the forecast: flight profit day by day, less every "
               "scheduled lease payment and week-end closing. A dot marks the lowest point; the dashed line is the order cushion.", "tiny"))
if note("performance", "notes"):
    story += [P("What sits behind the numbers", "h2")] + bullets(N["performance"]["notes"])
story.append(PageBreak())

# ---------------- network and operations: each airline's legs through the planning library, route profit, growth
section("NETWORK AND OPERATIONS", "network", "Each airline's network, and where its routes say to grow.")
ops = [["Airline", "Aircraft", "On order", "Routes", "Flights a day", "Seats a day", "Block hours a day", "Hours per aircraft", "Fleet"]]
for a in AL:
    o = a["ops"]
    ops.append([f"<b>{esc(a['name'])}</b>", str(o["aircraft"]), str(o["on_order"]), str(o["routes"]), num(o["flights_day"]), num(o["seats_day"]),
                num(o["block_hours_day"]), num(o["block_hours_per_aircraft"], 1), esc(" · ".join(f"{v} {k}" for k, v in sorted(o["types"].items(), key=lambda kv: -kv[1])))])
story.append(table(ops, [1.05 * inch, 0.52 * inch, 0.5 * inch, 0.5 * inch, 0.55 * inch, 0.6 * inch, 0.62 * inch, 0.62 * inch, 1.99 * inch]))
story.append(P("From each airline's flight legs as stored, through the planning library (the Tails screen's figures): legs flown a week ÷ 7, "
               "seats from each aircraft's cabin, block hours from the game's times.", "tiny"))
rp = [["Airline", "Route", "Flights", "Profit a week", "Profit a flight", "Economy load", "Read"]]
for a in AL:
    for kind, rows in (("best", a["routes"]["best"]), ("weak", a["routes"]["weak"])):
        for x in rows:
            rp.append([esc(a["name"]), f"{esc(x['hub'])}–{esc(x['dest'])}", str(x.get("flights") or 0), signed(x.get("profit_week")), signed(x.get("profit_per_flight")),
                       pct(x.get("economy")), esc(x.get("mark") or "") + (f": {esc(x['why'])}" if x.get("why") else "")])
if len(rp) > 1:
    days = next((a["routes"]["days"] for a in AL if a["routes"].get("days")), 7)
    story += [P(f"Route profit, last {days} days: each airline's best and weakest routes", "h2"), table(rp, [0.95 * inch, 0.75 * inch, 0.5 * inch, 0.7 * inch, 0.7 * inch, 0.6 * inch, 2.75 * inch])]
G = R.get("growth") or {}
for key, title in (("ready_for_another_flight", "Ready for another flight"), ("raise_fares", "Raise fares"), ("fix_or_reduce", "Fix or reduce")):
    if G.get(key):
        story.append(P(f"Growth signals: {title.lower()} (last {G.get('days') or 7} days)", "h2"))
        story.append(table([["Airline", "Route", "Flights", "Profit a week", "Economy load", "Why"]] + [
            [esc(x["airline"]), f"{esc(x.get('hub'))}–{esc(x.get('dest'))}", str(x.get("flights") or 0), signed(x.get("profit_week")), pct(x.get("economy")), esc(x.get("why") or "")]
            for x in G[key]], [0.95 * inch, 0.75 * inch, 0.5 * inch, 0.7 * inch, 0.6 * inch, 3.45 * inch]))
if G.get("aircraft_losing_after_lease"):
    story.append(P("Growth signals: aircraft losing money after their lease", "h2"))
    story.append(table([["Airline", "Aircraft", "Type", "Net a day"]] + [[esc(x["airline"]), esc(x.get("registration")), esc(x.get("type")), signed(x.get("net_day"))]
                                                                        for x in G["aircraft_losing_after_lease"]], [1.2 * inch, 1.2 * inch, 1.6 * inch, 2.95 * inch]))
hf = [["Airline", "Main hub", "Departures a week", "On plan cards", "Towards", "Contested bases"]]
for a in AL:
    h = a["hubs_first"]
    if not h.get("main_hub"):
        continue
    hf.append([esc(a["name"]), esc(h["main_hub"]), str(h.get("departures") or 0), str(h.get("planned") or 0),
               "exempt" if h.get("exempt") else f"{h.get('target') or 0:,.0f} ({pct(h.get('percent'))})",
               esc(", ".join(f"{b['code']} ({b['top_rival']['name']} {b['top_rival']['weekly']}/wk)" if b.get("top_rival") else b["code"] for b in h["bases"] if b.get("contested")) or "none")])
if len(hf) > 1:
    story += [P("Hubs first: each main hub towards its target (manual §3)", "h2"), table(hf, [1.0 * inch, 0.6 * inch, 0.8 * inch, 0.75 * inch, 0.95 * inch, 2.85 * inch])]
if os.path.exists("c_fleet.png"):
    story += [Spacer(1, 6), Image("c_fleet.png", width=3.4 * inch, height=3.4 * inch * (0.5 + 0.36 * max(1, len(AL))) / 3.4, hAlign="LEFT")]
if note("network", "notes"):
    story += [P("Operations notes", "h2")] + bullets(N["network"]["notes"])
story.append(PageBreak())

# ---------------- competition: markets (the world scan; the group's share and each airline's, manual §7)
section("COMPETITION — MARKETS", "markets", "Where our airlines fly against the biggest rivals.")
fly = [m for m in R["mtab"] if m["our_seats"] > 0 and m["market"] != "Unknown"]
image("c_markets.png", 7.2, 0.6 + 0.25 * max(1, min(14, len(fly))))
mk = [["Market", "Seats a week", "Our share", "Our rank", "Leader", "Who carries our share"]]
for m in fly[:12]:
    lead = m["top"][0]
    mk.append([f"<b>{esc(m['market'])}</b>", f"{m['seats']:,}", pct(m["our_share"] * 100, 1), f"{m['rank_ours']} of {m['n_airlines']}",
               f"{esc(lead[0])} {lead[2] * 100:.0f}%", esc(", ".join(f"{a} {s * 100:.1f}%" for a, _, s in m["ours_by"]))])
story.append(table(mk, [1.65 * inch, 0.8 * inch, 0.62 * inch, 0.62 * inch, 1.45 * inch, 1.81 * inch]))
story.append(P("Seats estimated from each flight's aircraft type in the world scan. Markets group airports by region; domestic markets are "
               "shown separately for the largest countries.", "tiny"))
gaps = [m for m in R["mtab"] if m["market"] != "Unknown" and m["our_share"] < 0.05][:8]
if gaps:
    why = note("markets", "why") or {}
    head = ["Market", "Seats a week", "Leader", "Our position"] + (["Why it matters"] if why else [])
    rows = [[f"<b>{esc(m['market'])}</b>", f"{m['seats']:,}", esc(", ".join(f"{n} {s * 100:.0f}%" for n, _, s, o in m["top"][:2] if not o)),
             (f"{m['our_share'] * 100:.1f}% ({m['rank_ours']} of {m['n_airlines']})" if m["our_seats"] else "not flown")] + ([why.get(m["market"], "")] if why else [])
            for m in gaps]
    story += [P("The biggest markets we barely touch", "h2"), table([head] + rows, [1.3 * inch, 0.8 * inch, 1.7 * inch, 1.0 * inch, 2.15 * inch] if why else [1.8 * inch, 1.0 * inch, 2.6 * inch, 1.55 * inch])]
if note("markets", "notes"):
    story += bullets(N["markets"]["notes"])
story.append(PageBreak())

# ---------------- competition: our bases and the rivals on our routes
section("COMPETITION — HUBS AND RIVALS", "hubs", "Our bases, and who we meet on our own routes.")
image("c_hubs.png", 7.2, 0.6 + 0.25 * max(1, len(R["hubtab"])))
story.append(P("Weekly departures by airline from each airport's public page in the world scan.", "tiny"))
reads = note("rivals") or {}
rr = [["Our airline", "Main rivals on our routes (their flights a week on the same airport pairs)"] + (["Read"] if reads else [])]
for a in AL:
    rr.append([f"<b>{esc(a['name'])}</b>", esc(", ".join(f"{n} {v}" for n, v in (R["rivals"].get(a["name"]) or [])[:5]) or "none")] + ([by_airline(reads, a) or ""] if reads else []))
story += [P("Who we meet on our own routes", "h2"), table(rr, [0.95 * inch, 3.15 * inch, 2.85 * inch] if reads else [1.2 * inch, 5.75 * inch])]
if R.get("ourpairs"):
    story.append(P(f"{R['contested']} of our {R['ourpairs']} airport pairs ({R['contested'] / R['ourpairs'] * 100:.0f}%) have a competitor on them. The rest we fly alone.", "small"))
if note("hubs", "notes"):
    story += bullets(N["hubs"]["notes"])
story.append(PageBreak())


# ---------------- competition: each airline against its three biggest competitors (manual §7; competition() in the figures)
def growth(x):
    """The change against the week-before scan, as a table cell: +120 (+4.5%)."""
    if x.get("change") is None:
        return "—"
    c, p = x["change"], x.get("change_pct")
    colour = "#1A7F37" if c > 0 else "#C4141C" if c < 0 else "#5B616B"
    return f'<font color="{colour}">{c:+,}' + (f" ({p:+.1f}%)" if p is not None else "") + "</font>"


def grew(x):
    """The change in words: grew 18%, shrank 4%, held steady; None when there is nothing to compare."""
    c, p = x.get("change"), x.get("change_pct")
    if c is None:
        return None
    if c == 0:
        return "held steady"
    if p is None:
        return f"went from none to {x.get('weekly') or 0:,} departures a week"
    size = f"{abs(p):.1f}" if abs(p) < 1 else f"{abs(p):.0f}"
    return ("grew " if c > 0 else "shrank ") + size + "%"


def against_words(a, cp):
    """One line: "Pan Am grew 18% this week; American, its biggest rival on its pairs, grew 42%." """
    me, top = cp["self"], (cp["top"] or [None])[0]
    latest, before = moment(cp.get("latest")), moment(cp.get("week_before"))
    # "this week" when the scans are about a week apart (the week-before scan is at least 6 days older); else its date
    when = "this week" if latest and before and 6 <= (latest - before).days <= 8 else (f"since {day(cp['week_before'])}" if before else None)
    mine = grew(me) if when else None
    head = (f"{esc(a['name'])} {mine} {when}" if mine else f"{esc(a['name'])}: not in the scan of {day(cp['week_before'])} to compare" if before
            else f"{esc(a['name'])}: no earlier scan to compare its growth")
    if not top:
        return head + "; no outside airline flies its city pairs."
    rival = grew(top) if when else None
    if rival:
        return f"{head}; {esc(top['name'])}, its biggest rival on its pairs, {rival}."
    if before:
        return f"{head}; {esc(top['name'])}, its biggest rival on its pairs, wasn't in the scan of {day(cp['week_before'])}."
    return f"{head}; {esc(top['name'])} is its biggest rival on its pairs."


def fleet_cell(x):
    """A competitor's fleet as a table cell (since 23 Oct): 99 (44 on order), +6 on order this week."""
    f = x.get("fleet")
    if not f or f.get("overall") is None:
        return "not read"
    out = f"{f['overall']:,} ({f.get('on_order') or 0:,} on order)"
    c = f.get("on_order_change")
    if c:
        colour = "#C4141C" if c > 0 else "#1A7F37"
        out += f'<br/><font color="{colour}">{c:+,} on order</font>'
    return out


section("COMPETITION — AGAINST OUR RIVALS", "competitors", "Each airline against its three biggest competitors.")
CP = next((a["competitors"] for a in AL if a.get("competitors")), None)
story.append(P("For each airline, the three outside airlines with the most departures a week on its own city pairs in the "
               + (f"world scan of {day(CP['latest'])}" if CP else "latest world scan") + ", our airline first. Departures a week count "
               "each flight's days both ways, passenger flights only; freighters and our own airlines are no one's rivals here. Growth is "
               + (f"against the scan of {day(CP['week_before'])}" if CP and CP.get("week_before") else "against the scan a week before")
               + ". Fleet: each rival's aircraft and aircraft on order from its overview page in the same scan, with the change in "
               "aircraft on order over the week. From competition() in the database's figures.", "small"))
for a in AL:
    cp = a.get("competitors")
    part = [P(f"{esc(a['name'])}: against its three biggest competitors", "h2")]
    if not cp:
        part.append(P("No world scan to compare yet.", "body"))
    else:
        me = cp["self"]
        fl = cp.get("fleets")   # each rival's fleet, since 23 Oct (none in older figures)
        rows = [["Airline", "Departures a week on its city pairs", "Of its city pairs", "Departures a week, all", "Airports", "Growth over the week"]
                + (["Fleet"] if fl else []),
                [f"<b>{esc(a['name'])}</b>", f"<b>{num(me.get('on_pairs'))}</b>",
                 f"{num(me.get('pairs'))} of {num(me.get('pairs_flown'))}", num(me.get("weekly")), num(me.get("airports")), growth(me)] + (["—"] if fl else [])]
        for x in cp["top"]:
            rows.append([esc(x.get("name")), num(x.get("on_pairs")), num(x.get("pairs")), num(x.get("weekly")), num(x.get("airports")),
                         growth(x) if x.get("weekly_before") is not None or not cp.get("week_before") else "not in that scan"] + ([fleet_cell(x)] if fl else []))
        widths = ([1.55 * inch, 0.95 * inch, 0.7 * inch, 0.95 * inch, 0.6 * inch, 1.1 * inch, 1.1 * inch] if fl
                  else [1.9 * inch, 1.05 * inch, 0.8 * inch, 1.05 * inch, 0.65 * inch, 1.55 * inch])
        part += [table(rows, widths), Spacer(1, 2), P(against_words(a, cp), "body")]
    story.append(KeepTogether(part))
story.append(PageBreak())

# ---------------- competition: rivals' moves (notes) and where each airline ranks (the scan)
section("COMPETITION — MOVES THIS WEEK", "moves", "What rivals did this week, and where each of our airlines ranks.")
if note("moves"):
    story.append(table([["Date", "Airline", "Move", "Why it matters to us"]] + [[m.get("date", ""), m.get("airline", ""), m.get("move", ""), m.get("why", "")] for m in N["moves"]],
                       [0.78 * inch, 1.05 * inch, 1.75 * inch, 3.37 * inch]))
story.append(P("Where we rank", "h2"))
top = [["Rank", "Airline", "Flights a week"]] + [[str(i + 1), esc(n), f"{w:,}"] for i, (n, w, o) in enumerate(R["rank"][:8])]
mine = [["Rank", "Our airline", "Flights a week"]] + [[str(r), esc(n), f"{w:,}"] for r, n, w in R["our_rank"]]
tw = Table([[table(top, [0.45 * inch, 1.75 * inch, 0.9 * inch]), table(mine, [0.45 * inch, 1.75 * inch, 0.9 * inch])]], colWidths=[W / 2] * 2)
tw.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0)]))
story.append(tw)
story.append(P(f"Out of {R['world']['flying']} airlines flying in Gander ({R['world']['airlines']} registered), by departures a week in the world scan.", "small"))

# ---------------- risks, opportunities, plan and progress: the Saturday review's notes
# the flagged order books (competition()'s order_flags, since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §5): rivals
# with aircraft on order of a quarter of their fleet or more, or on order with no flights yet, from the database's figures
FLAGS = R.get("order_flags")
if note("risks", "rows") or FLAGS:
    story.append(PageBreak()); section("RISKS", "risks", "The risks this week.")
if note("risks", "rows"):
    story.append(table([["Risk", "Likelihood", "Impact", "Owner", "What we do about it"]] + [[x.get("risk", ""), x.get("likelihood", ""), x.get("impact", ""), x.get("owner", ""), x.get("action", "")]
                                                                                           for x in N["risks"]["rows"]], [2.35 * inch, 0.65 * inch, 0.55 * inch, 0.75 * inch, 2.65 * inch]))
if FLAGS:
    def book(x):
        if x.get("kind") == "starting":
            return f"{x['on_order']:,} on order, no flights yet" + (f" ({x['fleet']:,} aircraft)" if x.get("fleet") else "")
        return f"{x['on_order']:,} on order, {x['share']:.1f}% of {x['fleet']:,} aircraft"

    def week(x):
        c = x.get("on_order_change")
        return "—" if c is None else ("no change" if c == 0 else f"{c:+,} on order")

    story.append(P("Rivals' order books", "h2"))
    story.append(table([["Rival", "Order book", "This week", "Meets our airlines"]]
                       + [[esc(x.get("name")), book(x), week(x), ", ".join(esc(m) for m in x["meets"]) if x.get("meets") else "none"] for x in FLAGS],
                       [2.0 * inch, 2.45 * inch, 1.0 * inch, 1.5 * inch]))
    story.append(P("From each rival's overview page in the latest world scan: aircraft on order of a quarter of its fleet or more (and at least 5), "
                   "or aircraft on order with no flights yet. Meets: it flies one of that airline's city pairs or from one of its bases.", "small"))
if note("opportunities", "rows"):
    story.append(PageBreak()); section("OPPORTUNITIES", "opportunities", "The opportunities this week.")
    story.append(table([["#", "Opportunity", "Size", "Where we are", "Next move"]] + [[str(i + 1), x.get("opportunity", ""), x.get("size", ""), x.get("where", ""), x.get("next", "")]
                                                                                    for i, x in enumerate(N["opportunities"]["rows"])], [0.25 * inch, 1.55 * inch, 1.1 * inch, 1.2 * inch, 2.85 * inch]))
plan = note("plan") or {}
if any(plan.get(k) for k in ("done", "rotation", "coming_up", "watch")):
    story.append(PageBreak()); section("PLAN AND PROGRESS", "plan", "Our plan, and how it went this week.")
    if plan.get("done"):
        story += [P("What we did this week", "h2")] + bullets(plan["done"])
    if plan.get("rotation"):
        story += [P("Growth rotation", "h2"), table([["Airline", "Moves made this week", "Next move"]] + [[x.get("airline", ""), x.get("moves", ""), x.get("next", "")] for x in plan["rotation"]],
                                                     [1.0 * inch, 3.65 * inch, 2.3 * inch])]
    if plan.get("coming_up"):
        story += [P("Coming up", "h2"), table([["When", "What"]] + [[x.get("when", ""), x.get("what", "")] for x in plan["coming_up"]], [0.95 * inch, 6.0 * inch])]
    if plan.get("watch"):
        story += [P("Watch list", "h2")] + bullets(plan["watch"])
story.append(Spacer(1, 6))
story.append(P("Method: competitor data comes from the world scan" + (f" of {SCAN.day} {SCAN:%b} ({SCAN:%H:%M} UTC)" if SCAN else "")
               + f", {R['world']['airlines']} airlines. Each airline's money comes from the database's captured figures as of {D.day} {D:%b}, {AS_OF:%H:%M} UTC, "
               "and its network from its stored flight legs through the planning library." + (" " + N["method"] if note("method") else ""), "tiny"))
doc.build(story)
print("built", OUT)
