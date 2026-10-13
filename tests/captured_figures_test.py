"""The captured figures side by side with the old planner on the rehearsal's copy (decision #19, build pull request 3,
spec docs/specs/2026-10-12-captured-figures.md §3): every Review and Check figure the old planner works out from the
capture must equal the database functions' (database/migrations/20261012210000_captured_figures.sql) at the same frozen
moment, for every airline.

Run by database/rehearse.sh after the other steps. Like tests/rules_library_test.py it uses tests/real_saves_test.py's
helpers and request mapping, needs the copy, so it isn't part of tests/run_all.sh, and nothing goes outside.

1. The moment: the copy's latest capture (game_capture_raw) plus one hour, to the millisecond. The copy as it stood
   then: the functions read typed loads and day flags only as entered by p_as_of, while the old planner reads every
   one, so those entered after the moment (the real-saves step types one minutes before this test; Gitesh may type
   some after the latest capture) are set aside while the test runs and put back when it ends.
2. The old planner, opened as real_saves_test.py opens it (its live address mapped to a local server, the live Supabase
   address answered by the copy, its Supabase library from npm), its clock frozen at the moment, signed in as a test
   staff user; opening it writes nothing. It is served from a copy of web/ in which one line is added to the planner,
   before its boot: window.__eqOld = s => eval(s), so the test can call the planner's own functions (cashForecast,
   finStats, routeProfit, patterns ...) and run, word for word, the statements its boards are built from
   (groupOverviewHtml's rows, capSignalsHtml's lists, hubProgressHtml's rows, captureBoard's reads, cashForecast's bal
   and fits). The planner in web/planner/ is unchanged.
3. Each function called through the data API as that staff user with p_as_of = the moment: airline_cards,
   growth_signals, hub_progress, capture_status, and for every airline cash_forecast (and with orders: the most of
   each type the old fits() allows today, one more, and two types together), airline_profit, route_profit and
   aircraft_profit for 1, 3 and 7 days, and fare_changes.
4. Compared, for every airline: Review's cards (profit a day, per aircraft, return on fleet, pays back in, funds an
   aircraft every, fleet, flights, load, next order), the group today, profit by day, "Cash, next 14 days" (every point,
   every payment, the lowest point and its payment, every type's price, lease and safe date, and how many today), route
   profit for 1, 3 and 7 days (every route and mark, the average flight), aircraft, fare changes; Check's growth lists,
   the load patterns, main hubs towards 750 and the capture board; can order now. Money to the old planner's rounding
   (a difference only in float noise at a rounding boundary is no difference), counts and dates exactly. Anything that
   differs fails, naming the airline, the figure, both values and the old function it came from.
5. Each function's time on the copy, best of 3, as postgres (must be under 500 ms), after ANALYZE: the copy is
   restored without the planner statistics the live database keeps.

Prints airline names, route codes, registrations, counts and figures, never anything else from the rows, since the log
is posted on the pull request. Never prints the local keys or the test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL and SECRET_TABLES.
Usage: python3 tests/captured_figures_test.py
"""
import asyncio, atexit, datetime, decimal, json, secrets, shutil, sys, tempfile, time
from pathlib import Path
from harness import ROOT, WEB, LIVE_HOST, serve
from playwright.async_api import async_playwright

PLANNER_FILE = WEB / "planner" / "index.html"
HOOK = "  window.__eqOld = s => eval(s);   // added by tests/captured_figures_test.py to the copy it serves\n"
HOOK_BEFORE = "  // ---------- boot ----------\n"
LIMIT_MS = 500
failures = []


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:40]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


# ---------- the old planner's own code, from its file ----------
def planner_copy(dest):
    """A copy of web/ with the hook added to the planner, before its boot. Returns the copy's folder."""
    root = Path(dest) / "web"
    shutil.copytree(WEB, root, ignore=shutil.ignore_patterns("app"))
    page = root / "planner" / "index.html"
    html = page.read_text()
    if html.count(HOOK_BEFORE) != 1:
        raise RuntimeError("the old planner's boot line isn't where the test expects it")
    page.write_text(html.replace(HOOK_BEFORE, HOOK + HOOK_BEFORE, 1))
    return root


def between(src, start, end):
    """The old planner's code between two lines of its file (start excluded), as written."""
    i = src.find(start)
    j = src.find(end, i + len(start)) if i >= 0 else -1
    if i < 0 or j < 0:
        raise RuntimeError(f"not found in the old planner: {start.strip()[:60]} … {end.strip()[:40]}")
    return src[i + len(start):j]


def line_starting(src, start):
    i = src.find(start)
    if i < 0:
        raise RuntimeError(f"not found in the old planner: {start.strip()[:60]}")
    return src[i:src.index("\n", i)]


def old_js(src):
    """One expression, run inside the old planner's closure, giving every figure as JSON."""
    group = between(src, "function groupOverviewHtml() {\n", '    if (!rows.some(r => r.ops != null)) return "";')
    signals = between(src, "function capSignalsHtml() {\n", "    const k = v => (v >= 0")
    hubs = between(src, "function hubProgressHtml() {\n", '    return `<h4 class="gh">Main hubs')
    capture = between(src, "function captureBoard() {\n", '    let h = `<div class="board"><h3 class="rh">Capture')
    bal = line_starting(src, "const bal = t => cash0 + opsDay")
    fits = line_starting(src, "const fits = (td, n, P, L) =>")
    # fits()'s own left-hand side, point by point: the forecast after n orders at td, each with its own lease
    after = fits.replace("const fits = ", "const after = ", 1).replace(".every(p => p.v - ", ".map(p => ({ t: p.t, v: p.v - ", 1)
    if after.endswith(" >= CUSHION);"):
        after = after[:-len(" >= CUSHION);")] + " }));"
    if after.count("const after = ") != 1 or ".map(p => ({ t: p.t, v: p.v - " not in after or not after.endswith(" }));"):
        raise RuntimeError("the old planner's fits() isn't written the way the test reads it")
    return """(() => {
  const plainRoute = r => ({ key: r.key, n: r.n, profit: r.profit, income: r.income, ppf: r.ppf, margin: r.margin, wk: r.wk, pwk: r.pwk,
    ecoA: r.ecoA, busA: r.busA, cargoA: r.cargoA, fareA: r.fareA, sold: r.sold, ecoN: r.eco.length, soldShare: r.soldShare, sig: r.sigKey, why: r.why });
  const plainTail = t => ({ tail: t.tail, n: t.n, profit: t.profit, day: t.day, ls: t.ls, net: t.net, type: t.type, routes: [...t.routes] });
  const out = { now: Date.now(), today: today(), capAt: CAP.at, capErr: CAP.err, pnl: CAP.pnl.length, airlines: airlines(),
                capHome: Object.keys(CAP_HOME), short: SHORT_TYPE, cushion: CUSHION, cards: {}, fc: {}, fcNext: {}, orderNow: {}, rp: {}, fits: {} };
  for (const al of airlines()) {
    const s = finStats(al);
    out.cards[al] = { profit: s.profit, span: s.span, early: s.early, perAc: s.perAc, rof: s.rof, payback: s.payback, fundEvery: s.fundEvery,
      flying: s.flying, flyVal: s.flyVal, avgPrice: s.avgPrice, flightsNow: s.flightsNow, flightsThen: s.flightsThen, tailsThen: s.tailsThen,
      load7: s.load7, onOrder: s.onOrder, iv: s.iv };
    out.fc[al] = cashForecast(al);
    out.fcNext[al] = fcNext(al).replace(/<[^>]*>/g, "");
    out.orderNow[al] = orderNow(al);
    out.rp[al] = {};
    for (const d of [1, 3, 7]) { const R = routeProfit(al, d);
      out.rp[al][d] = { n: R.n, matched: R.matched, mixed: R.mixed, cost: R.cost, routes: R.routes.map(plainRoute), tails: R.tails.map(plainTail), changes: R.changes }; }
    out.fits[al] = (() => { const fc = cashForecast(al); if (!fc || !fc.safe) return null; const { cash0, t0, opsDay, pay, pts } = fc;
      """ + bal + """
      """ + fits + """
      """ + after + """
      const most = (P, L) => { let n = 0; while (n < 400 && fits(t0, n + 1, P, L)) n++; return n; };
      const line = (P, L) => after(t0, 1, P, L).slice(1);   // the first is the order's own moment, which is also the first point
      return { types: fc.safe.map(x => ({ short: x.short, P: x.P, L: x.L, most: most(x.P, x.L), after: line(x.P, x.L) })),
               pair: fc.safe.length >= 2 ? { a: fc.safe[0].short, b: fc.safe[1].short,
                                             ok: fits(t0, 1, fc.safe[0].P + fc.safe[1].P, fc.safe[0].L + fc.safe[1].L),
                                             after: line(fc.safe[0].P + fc.safe[1].P, fc.safe[0].L + fc.safe[1].L) } : null }; })();
  }
  out.patterns = patterns().map(p => ({ routeKey: p.routeKey, airline: p.airline, n: p.n, full: p.full, b95: p.b95, b85: p.b85, b70: p.b70,
                                       days: p.days.size, flights: p.flights.size, sig: p.sig }));
  out.group = (() => {""" + group + """ return rows; })();
  out.signals = (() => {""" + signals + """ return { add: add.map(r => ({ al: r.al, key: r.key })), raise: raise.map(r => ({ al: r.al, key: r.key })),
      fix: fix.map(r => ({ al: r.al, key: r.key })), lossAc: lossAc.map(t => ({ al: t.al, tail: t.tail })) }; })();
  out.hubs = (() => {""" + hubs + """ return rows; })();
  out.capture = (() => {""" + capture + """ return airlines().filter(a => CAP_HOME[a]).map(al => ({ al,
      kinds: Object.fromEntries(CAP_KINDS.map(([k]) => { const t = run(al, k, d0), y = run(al, k, d1);
        return [k, { today: t ? String(t.captured_at).slice(11, 16) : null, yesterday: y ? String(y.captured_at).slice(11, 16) : null }]; })),
      today: nFl(al, d0), yesterday: nFl(al, d1), missing: CAP_KINDS.filter(([k]) => !run(al, k, d0)).map(k => k[0]) })); })();
  return JSON.stringify(out);
})()"""


# ---------- the old planner's formats ----------
def to_fixed(x, places):
    """JavaScript's Number.prototype.toFixed: the exact value of the double, halves away from zero."""
    q = decimal.Decimal(1).scaleb(-places)
    return str(decimal.Decimal(float(x)).quantize(q, rounding=decimal.ROUND_HALF_UP))


def js_round(x):
    """Math.round: halves up."""
    return int(decimal.Decimal(float(x)).to_integral_value(rounding=decimal.ROUND_HALF_UP)) if x >= 0 else -int(
        decimal.Decimal(-float(x)).to_integral_value(rounding=decimal.ROUND_HALF_DOWN))


def fc_day(ms):
    """fcDay(): Tue, Oct 14 (UTC)."""
    d = datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc)
    return d.strftime("%a, %b ") + str(d.day)


def fc_what(s):
    """fcWhat(): what a payment is, as the forecast names it."""
    import re
    s = s or ""
    if re.search("Week-end closing", s, re.I):
        return "the week-end closing"
    m = re.search(r"Leasing payment for ([A-Z0-9-]+)", s, re.I)
    return "the lease for " + m[1] if m else "a payment"


def ms(iso):
    """A moment from the database (ISO, UTC to the millisecond) in milliseconds since 1970, as JavaScript counts."""
    if iso is None:
        return None
    return int(datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() * 1000 + 0.5)


def num(x):
    return None if x is None else float(x)


class Cmp:
    """Collects every comparison and what differed: the airline, the figure, both values and the old function."""

    def __init__(self):
        self.n, self.problems = 0, []

    def add(self, ok, al, fig, old, new, fn):
        self.n += 1
        if not ok:
            self.problems.append(f"{al}: {fig}: old planner {old}, database {new} ({fn})")

    def exact(self, al, fig, old, new, fn):
        self.add(old == new, al, fig, old, new, fn)

    def money(self, al, fig, old, new, fn, places=2, scale=1):
        """Equal to the old planner's rounding: toFixed(places) of value × scale; float noise at a boundary is equal."""
        old, new = num(old), num(new)
        if old is None or new is None:
            return self.add(old is None and new is None, al, fig, old, new, fn)
        a, b = to_fixed(old * scale, places), to_fixed(new * scale, places)
        self.add(a == b or abs(old - new) * scale < 1e-9 * max(1.0, abs(old * scale)), al, fig, a, b, fn)

    def k(self, al, fig, old, new, fn):
        """Thousands, as kk() and k() show them: the sign, then Math.round(|v| × 1000)."""
        old, new = num(old), num(new)
        if old is None or new is None:
            return self.add(old is None and new is None, al, fig, old, new, fn)
        a = ("+" if old >= 0 else "−") + str(js_round(abs(old) * 1000))
        b = ("+" if new >= 0 else "−") + str(js_round(abs(new) * 1000))
        self.add(a == b or abs(old - new) * 1000 < 1e-9 * max(1.0, abs(old * 1000)), al, fig, a, b, fn)

    def pct(self, al, fig, old, new, fn):
        """A whole percent, Math.round."""
        old, new = num(old), num(new)
        if old is None or new is None:
            return self.add(old is None and new is None, al, fig, old, new, fn)
        self.add(js_round(old) == js_round(new) or abs(old - new) < 1e-9, al, fig, js_round(old), js_round(new), fn)

    def days(self, al, fig, old, new, fn):
        """dd(): under a day, or Math.round days."""
        def dd(n):
            return None if n is None else "under a day" if n < 1 else str(js_round(n))
        self.add(dd(num(old)) == dd(num(new)) or (old is not None and new is not None and abs(float(old) - float(new)) < 1e-9),
                 al, fig, dd(num(old)), dd(num(new)), fn)


def sorted_by(items, key, label):
    """Problems if the database's list isn't in the old planner's order (ties may come either way)."""
    keys = [key(x) for x in items]
    return [] if all(keys[i] >= keys[i + 1] for i in range(len(keys) - 1)) else [f"{label} isn't in the old planner's order"]


# ---------- the comparison ----------
def compare(old, db, names):
    """old: the old planner's figures (old_js); db: the functions' answers (collect_db); names: airline id → old name."""
    c = Cmp()
    ids = {v: int(k) for k, v in names.items()}
    short = old["short"]
    sh = lambda name: short.get(str(name or "").upper(), name)   # SHORT_TYPE, as the old planner names a type
    cards = {names[str(x["airline_id"])]: x for x in db["cards"]["airlines"]}
    c.exact("all", "airlines with a card, in order", old["airlines"], [names[str(x["airline_id"])] for x in db["cards"]["airlines"]], "airlines()")

    for al in old["airlines"]:
        o, n = old["cards"][al], cards.get(al) or {}
        f = "finStats/renderFinance"
        c.money(al, "card: profit a day", o.get("profit"), n.get("profit_day"), f)
        c.exact(al, "card: profit read over (days)", o.get("span"), n.get("span_days"), f)
        c.exact(al, "card: early read", o.get("early"), n.get("early"), f)
        c.k(al, "card: per aircraft", o.get("perAc"), n.get("per_aircraft_day"), f)
        c.money(al, "card: return on fleet (% a week)", o.get("rof"), n.get("return_on_fleet_pct_week"), f, 1)
        c.days(al, "card: an aircraft pays back in", o.get("payback"), n.get("payback_days"), f)
        c.days(al, "card: funds a new aircraft every", o.get("fundEvery"), n.get("funds_aircraft_every_days"), f)
        c.exact(al, "card: fleet flying", o["flying"], n.get("fleet"), f)
        c.exact(al, "card: fleet added this week", o["flying"] - o["tailsThen"], n.get("fleet_added_this_week"), f)
        c.exact(al, "card: on order", o["onOrder"], n.get("on_order"), f)
        c.exact(al, "card: flights a day", o["flightsNow"], n.get("flights_day"), f)
        c.exact(al, "card: flights added this week", o["flightsNow"] - o["flightsThen"], n.get("flights_added_this_week"), f)
        c.pct(al, "card: average load, 7 days", o.get("load7"), n.get("load_7_days"), f)
        nx = n.get("next_order") or {}
        if nx.get("when") == "needs":
            mine = "needs " + nx.get("missing", "")
        elif nx.get("when") == "now":
            mine = "can order " + " or ".join(sh(t) for t in nx["types"][:2])
        elif nx.get("when") == "later":
            mine = f"{sh(nx['type'])} safe from {fc_day(ms(nx['safe_from']))}"
        else:
            mine = "not in the next 14 days"
        c.exact(al, "card: next order", old["fcNext"][al], mine, "fcNext")
        c.exact(al, "can order now", old["orderNow"][al], [sh(t) for t in n.get("can_order_now") or []], "orderNow")

        # profit by day (Review's chart and table)
        p = db["profit"][al]
        oiv, niv = o.get("iv") or [], p.get("days") or []
        c.exact(al, "profit by day: dates", [x["d"] for x in oiv], [x["date"] for x in niv], "finStats.iv")
        for x, y in zip(oiv, niv):
            d, f = x["d"], "finStats.iv"
            c.money(al, f"profit by day {d}: cash", x["c"], y["cash"], f)
            c.money(al, f"profit by day {d}: change", x["dc"], y["change"], f)
            c.money(al, f"profit by day {d}: order payments", x["cap"] or None, num(y["order_payments"]) or None, f)
            c.money(al, f"profit by day {d}: profit a day", x["profit"], y["profit_day"], f)
            c.exact(al, f"profit by day {d}: days between", x["days"], y["days"], f)
            c.exact(al, f"profit by day {d}: aircraft", x["tails"], y["aircraft"], f)
            c.exact(al, f"profit by day {d}: flights", x["flights"], y["flights"], f)
            c.pct(al, f"profit by day {d}: average load", x.get("load"), y.get("load"), f)
            if x["tails"]:
                c.k(al, f"profit by day {d}: per aircraft", x["profit"] / x["tails"], num(y["profit_day"]) / y["aircraft"] if y["aircraft"] else None, f)
        c.money(al, "profit by day: 7-day average", o.get("profit"), p.get("profit_day"), "finStats")

        # Cash, next 14 days
        compare_forecast(c, al, old["fc"].get(al), db["fc"][al], old["fits"].get(al), db["orders"].get(al), sh)

        # route profit, aircraft and fare changes
        for d in ("1", "3", "7"):
            compare_routes(c, al, d, old["rp"][al][d], db["rp"][al][d], db["ac"][al][d], ids[al])
        compare_fares(c, al, old["rp"][al]["7"]["changes"], db["fares"][al]["changes"])

    # the group today
    rows = {names[str(x["airline_id"])]: x for x in db["cards"]["group_today"]}
    c.exact("all", "the group today: airlines", [r["al"] for r in old["group"]], [names[str(x["airline_id"])] for x in db["cards"]["group_today"]],
            "groupOverviewHtml")
    c.exact("all", "the group today: shown", any(r["ops"] is not None for r in old["group"]), db["cards"]["group_today_shown"], "groupOverviewHtml")
    for r in old["group"]:
        al, n, f = r["al"], rows.get(r["al"]) or {}, "groupOverviewHtml"
        c.money(al, "group today: cash", r["cash"], n.get("cash"), f)
        c.money(al, "group today: flight profit a day", r["ops"], n.get("flight_profit_day"), f)
        c.money(al, "group today: leases a day", r["lease"], n.get("leases_day"), f)
        c.money(al, "group today: week-end closing a day", r["closing"], n.get("closing_day"), f)
        c.money(al, "group today: leases and closing a day", r["lease"] + r["closing"], num(n.get("leases_day", 0)) + num(n.get("closing_day", 0)), f)
        c.money(al, "group today: net a day", r["net"], n.get("net_day"), f)
        c.exact(al, "group today: aircraft on the ground", sorted(r["ground"]), sorted(n.get("on_ground") or []), f)
        c.k(al, "group today: their leases a day", r["groundLease"], n.get("on_ground_lease_day"), f)

    # Check: the growth lists, the load patterns, main hubs, the capture board
    g = db["growth"]
    key = lambda x: names[str(x["airline_id"])] + "|" + x["hub"] + "|" + x["dest"]
    for label, mine, theirs, sort in (("ready for another flight", g["ready_for_another_flight"], old["signals"]["add"], lambda x: num(x["profit_week"])),
                                      ("raise fares", g["raise_fares"], old["signals"]["raise"], lambda x: x["flights"]),
                                      ("fix or reduce", g["fix_or_reduce"], old["signals"]["fix"], lambda x: -num(x["profit_per_flight"]))):
        c.exact("all", f"growth: {label}", sorted(r["key"] for r in theirs), sorted(key(x) for x in mine), "capSignalsHtml")
        for p in sorted_by(mine, sort, f"growth: {label}"):
            c.add(False, "all", p, "sorted", "not sorted", "capSignalsHtml")
    c.exact("all", "growth: aircraft losing money after their lease", sorted(r["al"] + "|" + r["tail"] for r in old["signals"]["lossAc"]),
            sorted(names[str(x["airline_id"])] + "|" + x["registration"] for x in g["aircraft_losing_after_lease"]), "capSignalsHtml")
    pats = {names[str(x["airline_id"])] + "|" + x["hub"] + "|" + x["dest"]: x for x in g["load_patterns"]}
    c.exact("all", "load patterns: routes", sorted(p["routeKey"] for p in old["patterns"]), sorted(pats), "patterns")
    for p in old["patterns"]:
        x, al = pats.get(p["routeKey"]) or {}, p["airline"]
        for a, b in (("n", "departures"), ("full", "full"), ("b95", "under_95"), ("b85", "under_85"), ("b70", "under_70"),
                     ("days", "days"), ("flights", "flights"), ("sig", "mark")):
            c.exact(al, f"load pattern {p['routeKey'].split('|', 1)[1]}: {b}", p[a], x.get(b), "patterns")

    hubs = {names[str(x["airline_id"])]: x for x in db["hubs"]["airlines"]}
    shown = {r["al"] for r in old["hubs"]}
    for r in old["hubs"]:
        al, x, f = r["al"], hubs.get(r["al"]) or {}, "hubProgressHtml"
        c.exact(al, "main hub", r["H"], x.get("main_hub"), f)
        c.exact(al, "main hub: departures a week flying", r["dep"], x.get("departures"), f)
        c.exact(al, "main hub: on plan cards not yet filed", r["add"], x.get("planned"), f)
        c.exact(al, "main hub: percent of the target", js_round(r["dep"] / 7.5), js_round(num(x.get("percent") or 0)), f)
        c.exact(al, "main hub: exempt", False, x.get("exempt"), f)
    for al, x in hubs.items():
        if al not in shown:
            c.add(x.get("exempt") is True or x.get("main_hub") is None, al, "hubs first: not on the old screen, so exempt or without a main hub",
                  "not shown", {"exempt": x.get("exempt"), "main_hub": x.get("main_hub")}, "hubProgressHtml (MAIN_HUB)")

    caps = {names[str(x["airline_id"])]: x for x in db["capture"]["airlines"]}
    c.exact("all", "capture board: airlines", [r["al"] for r in old["capture"]], [names[str(x["airline_id"])] for x in db["capture"]["airlines"]],
            "captureBoard")
    for r in old["capture"]:
        al, x, f = r["al"], caps.get(r["al"]) or {}, "captureBoard"
        for kind, t in r["kinds"].items():
            mine = (x.get("pages") or {}).get(kind) or {}
            c.exact(al, f"capture board: {kind} today", t["today"], (mine.get("today") or "")[11:16] or None, f)
            c.exact(al, f"capture board: {kind} yesterday", t["yesterday"], (mine.get("yesterday") or "")[11:16] or None, f)
        c.exact(al, "capture board: flights today", r["today"] or None, x.get("flights_today") or None, f)
        c.exact(al, "capture board: flights yesterday", r["yesterday"] or None, x.get("flights_yesterday") or None, f)
        c.exact(al, "capture board: missing today", r["missing"], x.get("missing"), f)
    return c


def compare_forecast(c, al, o, n, fits, orders, sh):
    f = "cashForecast"
    if o is None:
        return c.exact(al, "cash forecast: status", "no capture", n.get("status"), f)
    if o.get("missing"):
        c.exact(al, "cash forecast: status", ("missing", o["missing"]), (n.get("status"), n.get("missing")), f)
        c.money(al, "cash forecast: cash at capture", o["cash0"], n.get("cash"), f)
        return c.exact(al, "cash forecast: captured at", o["t0"], ms(n.get("cash_at")), f)
    c.exact(al, "cash forecast: status", "ok", n.get("status"), f)
    if n.get("status") != "ok":
        return
    c.money(al, "cash forecast: cash at capture", o["cash0"], n["cash"], f)
    c.exact(al, "cash forecast: captured at", o["t0"], ms(n["cash_at"]), f)
    c.money(al, "cash forecast: flight profit a day", o["opsDay"], n["flight_profit_day"], f)
    c.k(al, "cash forecast: profit a flight", o["perFlight"], n["profit_per_flight"], f)
    c.money(al, "cash forecast: flights a day", o["fpd"], n["flights_per_day"], f, 0)
    c.money(al, "cash forecast: flights a day (exact)", o["fpd"], n["flights_per_day"], f, 6)
    c.money(al, "cash forecast: payments, next 7 days", o["payWeek"], n["payments_next_7_days"], f)
    c.exact(al, "cash forecast: payments", len(o["pay"]), len(n["payments"]), f)
    for i, (x, y) in enumerate(zip(o["pay"], n["payments"])):
        c.exact(al, f"cash forecast: payment {i + 1} at", x["t"], ms(y["at"]), f)
        c.money(al, f"cash forecast: payment {i + 1} amount", x["m"], y["amount"], f)
        c.exact(al, f"cash forecast: payment {i + 1} is a weekly repeat", bool(x.get("repeat")), y["repeat"], f)
        c.exact(al, f"cash forecast: payment {i + 1} is", fc_what(x["what"]), fc_what(y["what"]), f)
    c.exact(al, "cash forecast: points", len(o["pts"]), len(n["points"]), f)
    for i, (x, y) in enumerate(zip(o["pts"], n["points"])):
        c.exact(al, f"cash forecast: point {i + 1} at", x["t"], ms(y["at"]), f)
        c.money(al, f"cash forecast: point {i + 1} balance", x["v"], y["balance"], f)
    c.exact(al, "cash forecast: lowest point at", o["low"]["t"], ms(n["lowest"]["at"]), f)
    c.money(al, "cash forecast: lowest point", o["low"]["v"], n["lowest"]["balance"], f)
    oc, nc = o.get("cause"), n["lowest"].get("payment")
    c.exact(al, "cash forecast: the payment that makes the lowest point (when, how much)",
            None if not oc else (oc["t"], to_fixed(oc["m"], 2)), None if not nc else (ms(nc["at"]), to_fixed(num(nc["amount"]), 2)), f)
    if oc and nc and fc_what(oc["what"]) != fc_what(nc["what"]):
        # two payments of the same amount at the same moment: either is the old planner's, as the events came
        same = [p for p in n["payments"] if ms(p["at"]) == oc["t"] and to_fixed(num(p["amount"]), 2) == to_fixed(oc["m"], 2)]
        c.add(any(fc_what(p["what"]) == fc_what(oc["what"]) for p in same) and len(same) > 1, al,
              "cash forecast: the payment that makes the lowest point", fc_what(oc["what"]), fc_what(nc["what"]), f)
    types = {sh(t["type"]): t for t in n["types"]}
    # the same types (the old planner lists them in its code's order, the function by type)
    c.exact(al, "cash forecast: types it may buy", sorted(x["short"] for x in o["safe"]), sorted(sh(t["type"]) for t in n["types"]), "cashForecast (BUY_TYPES)")
    for x in o["safe"]:
        t, s = types.get(x["short"]) or {}, x["short"]
        c.money(al, f"cash forecast: {s} price with cabin", x["P"], t.get("price_with_cabin"), f)
        c.money(al, f"cash forecast: {s} lease a week", x["L"], t.get("lease_week"), f)
        c.exact(al, f"cash forecast: {s} lease seen", x["leaseSeen"], t.get("lease_seen"), "leaseM")
        c.exact(al, f"cash forecast: {s} safe day", x.get("d"), t.get("safe_day"), f)
        c.exact(al, f"cash forecast: {s} safe from", x.get("t") if x.get("d") is not None else None, ms(t.get("safe_from")), f)
        if x.get("d") == 0:
            c.exact(al, f"cash forecast: {s} how many today", x.get("n"), t.get("count_today"), f)
    # the orders tested: the forecast after one of each type today, point by point (fits()'s own left-hand side, each
    # order with its own lease from 7 days after it is ordered), the most of each the old fits() allows today and one
    # more, and two types together
    def line(label, theirs, mine):
        mine = mine or []
        c.exact(al, f"{label}: points", len(theirs), len(mine), "cashForecast fits")
        for k, (x, y) in enumerate(zip(theirs, mine)):
            c.exact(al, f"{label}: point {k + 1} at", x["t"], ms(y["at"]), "cashForecast fits")
            c.money(al, f"{label}: point {k + 1} balance after", x["v"], y["balance"], "cashForecast fits")
    for x in (fits or {}).get("types", []):
        got = (orders or {}).get(x["short"]) or {}
        line(f"orders tested: 1 × {x['short']} today", x["after"], got.get("after"))
        if x["most"] > 0:
            c.exact(al, f"orders tested: {x['most']} × {x['short']} today is safe", True, got.get("most"), "cashForecast fits")
        if x["most"] < 400:
            c.exact(al, f"orders tested: {x['most'] + 1} × {x['short']} today isn't safe", False, got.get("one_more"), "cashForecast fits")
    pair = (fits or {}).get("pair")
    if pair:
        got = (orders or {}).get("pair") or {}
        c.exact(al, f"orders tested: {pair['a']} and {pair['b']} together today", pair["ok"], got.get("safe"), "cashForecast fits")
        line(f"orders tested: {pair['a']} and {pair['b']} together today", pair["after"], got.get("after"))


def compare_routes(c, al, d, o, n, ac, airline_id):
    f = f"routeProfit({d} day{'s' if d != '1' else ''})"
    c.exact(al, f"route profit {d}d: flights", o["n"], n["flights"], f)
    c.exact(al, f"route profit {d}d: matched to loads", o["matched"], n["matched"], f)
    c.exact(al, f"route profit {d}d: couldn't be told apart", o["mixed"], n["mixed"], f)
    mine = {al + "|" + r["hub"] + "|" + r["dest"]: r for r in n["routes"]}
    c.exact(al, f"route profit {d}d: routes", sorted(r["key"] for r in o["routes"]), sorted(mine), f)
    for r in o["routes"]:
        x, rt = mine.get(r["key"]) or {}, r["key"].split("|", 1)[1]
        c.exact(al, f"route {rt} {d}d: flights", r["n"], x.get("flights"), f)
        c.k(al, f"route {rt} {d}d: profit a flight", r["ppf"], x.get("profit_per_flight"), f)
        c.pct(al, f"route {rt} {d}d: margin", None if r["margin"] is None else r["margin"] * 100,
              None if x.get("margin") is None else num(x["margin"]) * 100, f)
        c.exact(al, f"route {rt} {d}d: flights a week", r["wk"], x.get("flights_week"), f)
        if r["wk"]:
            c.money(al, f"route {rt} {d}d: a week", r["pwk"], x.get("profit_week"), f)
        c.pct(al, f"route {rt} {d}d: economy", r["ecoA"], x.get("economy"), f)
        c.pct(al, f"route {rt} {d}d: business", r["busA"], x.get("business"), f)
        c.pct(al, f"route {rt} {d}d: cargo", r["cargoA"], x.get("cargo"), f)
        c.exact(al, f"route {rt} {d}d: sold out", (r["sold"], r["ecoN"]), (x.get("sold_out"), x.get("with_loads")), f)
        c.add((r["fareA"] is None and x.get("economy_fare") is None) or (r["fareA"] is not None and x.get("economy_fare") is not None
              and js_round(r["fareA"]) == js_round(num(x["economy_fare"]))), al, f"route {rt} {d}d: economy fare", r["fareA"], x.get("economy_fare"), f)
        c.exact(al, f"route {rt} {d}d: mark", r["sig"], x.get("mark"), f)
        c.exact(al, f"route {rt} {d}d: why", r["why"], x.get("why"), f)
    for p in sorted_by(n["routes"], lambda x: (num(x["profit_week"]), num(x["profit_per_flight"])), f"route profit {d}d"):
        c.add(False, al, p, "sorted", "not sorted", f)
    avg = n.get("average_flight") or {}
    for a, b in (("pax", "passengers"), ("cargo", "cargo"), ("fuel", "fuel"), ("handling", "handling"), ("onboard", "onboard"),
                 ("landing", "landing"), ("atc", "air_traffic"), ("maintenance", "maintenance")):
        c.money(al, f"route profit {d}d: average flight {b} (thousands)", o["cost"][a] if o["n"] else None,
                None if avg.get(b) is None else num(avg[b]) * 1000, f, 1)
    # the aircraft
    mine = {t["registration"]: t for t in ac["aircraft"]}
    f = f"routeProfit({d}) aircraft (R.tails)"
    c.exact(al, f"aircraft {d}d: registrations", sorted(t["tail"] for t in o["tails"]), sorted(mine), f)
    for t in o["tails"]:
        x, reg = mine.get(t["tail"]) or {}, t["tail"]
        c.exact(al, f"aircraft {reg} {d}d: flights", t["n"], x.get("flights"), f)
        c.k(al, f"aircraft {reg} {d}d: flight profit a day", t["day"], x.get("flight_profit_day"), f)
        c.k(al, f"aircraft {reg} {d}d: lease a day", t["ls"], x.get("lease_day"), f)
        c.k(al, f"aircraft {reg} {d}d: after lease", t["net"], x.get("net_day"), f)
        c.exact(al, f"aircraft {reg} {d}d: type", t["type"], x.get("type"), f)
        c.exact(al, f"aircraft {reg} {d}d: routes", sorted(t["routes"]), sorted(x.get("routes") or []), f)
    for p in sorted_by(ac["aircraft"], lambda x: num(x["net_day"] if x["net_day"] is not None else x["flight_profit_day"]), f"aircraft {d}d"):
        c.add(False, al, p, "sorted", "not sorted", f)


def compare_fares(c, al, o, n):
    f = "routeProfit (R.changes)"
    mine = {(x["origin"] + "–" + x["dest"], x["date"]): x for x in n}
    c.exact(al, "fare changes", sorted((x["route"], x["date"]) for x in o), sorted(mine), f)
    for x in o:
        y = mine.get((x["route"], x["date"])) or {}
        c.exact(al, f"fare change {x['route']} {x['date']}: fare", (js_round(x["from"]), js_round(x["to"])),
                (js_round(num(y.get("fare_before") or 0)), js_round(num(y.get("fare_after") or 0))), f)
        c.pct(al, f"fare change {x['route']} {x['date']}: load before", x.get("before"), y.get("economy_before"), f)
        c.pct(al, f"fare change {x['route']} {x['date']}: load after", x.get("after"), y.get("economy_after"), f)


# ---------- the database's answers ----------
def collect_db(call, ids, moment, old):
    """Every function's answer at the moment. call(fn, args) gives a function's answer (JSON); ids: old name → airline id."""
    db = {"cards": call("airline_cards", {"p_as_of": moment}), "growth": call("growth_signals", {"p_as_of": moment}),
          "hubs": call("hub_progress", {"p_as_of": moment}), "capture": call("capture_status", {"p_as_of": moment}),
          "fc": {}, "profit": {}, "rp": {}, "ac": {}, "fares": {}, "orders": {}}
    inverse = {v: k for k, v in old["short"].items()}
    for al, i in ids.items():
        db["fc"][al] = call("cash_forecast", {"p_airline_id": i, "p_as_of": moment})
        db["profit"][al] = call("airline_profit", {"p_airline_id": i, "p_as_of": moment})
        db["rp"][al] = {d: call("route_profit", {"p_airline_id": i, "p_days": int(d), "p_as_of": moment}) for d in ("1", "3", "7")}
        db["ac"][al] = {d: call("aircraft_profit", {"p_airline_id": i, "p_days": int(d), "p_as_of": moment}) for d in ("1", "3", "7")}
        db["fares"][al] = call("fare_changes", {"p_airline_id": i, "p_as_of": moment})
        fits = (old.get("fits") or {}).get(al)
        if fits:
            o = db["orders"][al] = {}
            tested = lambda orders: call("cash_forecast", {"p_airline_id": i, "p_orders": orders, "p_as_of": moment}).get("orders_tested") or {}
            for x in fits["types"]:
                name = inverse.get(x["short"], x["short"])
                one = tested([{"type": name, "count": 1}])
                o[x["short"]] = {"one": one.get("safe"), "after": one.get("points"),
                                 "most": tested([{"type": name, "count": x["most"]}]).get("safe") if x["most"] > 1 else one.get("safe") if x["most"] == 1 else None,
                                 "one_more": tested([{"type": name, "count": x["most"] + 1}]).get("safe") if x["most"] != 0 else one.get("safe")}
            if fits.get("pair"):
                pair = tested([{"type": inverse.get(fits["pair"]["a"], fits["pair"]["a"]), "count": 1},
                               {"type": inverse.get(fits["pair"]["b"], fits["pair"]["b"]), "count": 1}])
                o["pair"] = {"safe": pair.get("safe"), "after": pair.get("points")}
    return db


TIMED = [("cash_forecast", "select public.cash_forecast({a}, '[]'::jsonb, {m})"),
         ("airline_cards", "select public.airline_cards(null, {m})"),
         ("airline_profit", "select public.airline_profit({a}, {m})"),
         ("route_profit", "select public.route_profit({a}, 7, {m})"),
         ("aircraft_profit", "select public.aircraft_profit({a}, 7, {m})"),
         ("growth_signals", "select public.growth_signals(null, {m})"),
         ("hub_progress", "select public.hub_progress(null, {m})"),
         ("capture_status", "select public.capture_status(null, {m})"),
         ("fare_changes", "select public.fare_changes({a}, {m})")]


HELD = ("load_entries", "load_days")


def set_aside(psql, moment):
    """Takes the typed loads and day flags entered after the moment out of the copy, as {table: rows as JSON}, to be put
    back. The change log is off for these test-only moves (honoured for postgres only)."""
    return {t: psql(f"set equinox.change_log = 'off';\nwith d as (delete from public.{t} where entered_at > :'m'::timestamptz returning *) "
                    "select coalesce(json_agg(d), '[]') from d", m=moment).strip() for t in HELD}


def put_back(psql, held):
    for t, rows in held.items():
        if json.loads(rows or "[]"):
            psql(f"set equinox.change_log = 'off';\ninsert into public.{t} select * from json_populate_recordset(null::public.{t}, :'rows'::json)",
                 rows=rows)


def timings(psql, airline_id, moment):
    """Each function's time on the copy, best of 3, as postgres, for the airline with the most flights (ms). The copy is
    analyzed first: restored from a backup it has none of the planner statistics the live database keeps."""
    psql("analyze")
    out = {}
    for name, sql in TIMED:
        q = sql.format(a=int(airline_id), m="'" + moment + "'::timestamptz")
        res = psql(f"""do $t$ declare t0 timestamptz; best numeric := null; x jsonb;
                       begin for i in 1..3 loop t0 := clock_timestamp(); {q.replace('select ', 'x := ', 1)};
                         best := least(coalesce(best, 1e9), extract(epoch from clock_timestamp() - t0) * 1000); end loop;
                         raise notice 'ms %', round(best); end $t$;""", notices=True)
        out[name] = int(res.rsplit("ms ", 1)[-1].split()[0])
    return out


# ---------- the rehearsal ----------
async def main():
    from real_saves_test import (Planner, count_changes, counts, http, is_planner_user, library, local_env, log_since, make_user, marks,
                                 planner_facts, token_for, why)
    import real_saves_test as rs

    def psql(sql, notices=False, **var):
        if not notices:
            return rs.psql(sql, **var)
        import subprocess
        r = subprocess.run(["psql", rs.DB, "-X", "-At", "-q", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True, timeout=300)
        if r.returncode:
            raise RuntimeError("psql: " + (r.stderr.strip().splitlines() or ["failed"])[0][:200])
        return r.stderr

    class FrozenPlanner(Planner):
        def __init__(self, *a, moment, **k):
            super().__init__(*a, **k)
            self.moment = moment

        async def page(self, host=LIVE_HOST):
            self.pg = pg = await self.ctx.new_page()
            await pg.clock.set_fixed_time(self.moment)
            pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
            pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
                  if m.type == "error" and "Failed to load resource" not in m.text else None)
            pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
            await pg.goto(f"http://{host}:{self.port}/planner/")
            return pg

    facts = planner_facts()
    if not facts:
        step(False, "the old planner names its Supabase address, public key and library", ["not found in web/planner/index.html"])
        sys.exit(1)
    try:
        env = local_env()
        lib_js = library(facts["lib_version"])
        src = PLANNER_FILE.read_text()
        js = old_js(src)
    except Exception as e:
        step(False, "set up: the copy's address, the old planner's Supabase library and its code", [why(e)])
        sys.exit(1)

    # ---------- 1. the moment, and our airlines as the old planner names them
    moment = psql("select to_char((max(captured_at) + interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') from public.game_capture_raw").strip()
    rows = json.loads(psql("""select coalesce(json_agg(json_build_object('id', a.id, 'name', a.planner_name, 'main', b.airport_code, 'home', a.home_airport_code)
                                order by a.position), '[]') from public.airlines a join public.groups g on g.id = a.group_id and g.kind = 'ours'
                              left join public.airline_bases b on b.airline_id = a.id and b.is_main
                             where a.active and a.world_id = (select id from public.worlds where is_default)""").strip())
    ids = {r["name"]: r["id"] for r in rows}
    names = {str(r["id"]): r["name"] for r in rows}
    print(f"the moment: {moment} (the copy's latest capture plus one hour); our airlines: "
          + ", ".join(f"{r['name']} (main base {r['main'] or 'none'}, home {r['home']})" for r in rows), flush=True)

    # the copy as it stood at the moment: typed loads and day flags entered later are set aside until the test ends
    try:
        held = set_aside(psql, moment)
        atexit.register(lambda: put_back(psql, held))
        problems = []
    except Exception as e:
        held, problems = {}, [why(e)]
    step(not problems, "the copy as it stood at the moment: typed loads and day flags entered after it set aside until the test ends ("
         + ", ".join(f"{t}: {len(json.loads(held.get(t) or '[]'))}" for t in HELD) + ")", problems)
    if problems:
        sys.exit(1)

    tag = secrets.token_hex(4)
    staff = (f"captured-figures-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        token = token_for(env, *staff)
        problems = [] if is_planner_user(env, token) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    # ---------- 2. the old planner at the moment
    work = Path(tempfile.mkdtemp(prefix="captured-figures-"))
    old = None
    try:
        root = planner_copy(work)
        with serve(root) as port:
            async with async_playwright() as p:
                pl = FrozenPlanner(p, port, env, facts, lib_js, moment=moment)
                try:
                    n0, mark = counts(), marks()
                    await pl.open()
                    await pl.sign_in(*staff)
                    await pl.pg.wait_for_function("() => window.__eqOld && window.__eqOld('CAP.at') > 0", timeout=60000)
                    old = json.loads(await pl.pg.evaluate("s => window.__eqOld(s)", js))
                    problems = list(pl.errors)
                    if log_since(mark):
                        problems.append("opening the old planner changed the tables")
                    problems += count_changes(n0, counts())
                    if abs(old["now"] - ms(moment)) > 1000:
                        problems.append("the old planner's clock isn't frozen at the moment")
                    if old["capErr"]:
                        problems.append("the old planner couldn't read the capture: " + old["capErr"][:120])
                except Exception as e:
                    problems = [why(e)] + pl.errors[:3]
                step(not problems and old is not None, f"the old planner opened as real_saves_test.py opens it (with the hook), signed in as test staff, "
                     f"its clock frozen at {moment}; opening it wrote nothing; its figures read for {len((old or {}).get('airlines', []))} airlines", problems)
                await pl.close()
                outside = sorted(set(pl.outside))
                step(not outside and pl.copy > 0, f"nothing went outside ({pl.copy} requests answered by the copy, {pl.local} from the local server)",
                     (["reached: " + ", ".join(outside)] if outside else []) + ([] if pl.copy else ["the old planner never reached the copy"]))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if old is None:
        sys.exit(1)

    # ---------- 3. the functions, as staff through the data API
    calls = [0]

    def call(fn, args):
        calls[0] += 1
        code, body = http(env, "POST", f"/rest/v1/rpc/{fn}", args, token=token)
        if code != 200:
            raise RuntimeError(f"{fn} answered {code}: {body[:200].decode(errors='replace')}")
        return json.loads(body)

    try:
        db = collect_db(call, ids, moment, old)
        problems = []
    except Exception as e:
        db, problems = None, [why(e)]
    step(db is not None, f"every function called as staff through the data API at the moment ({calls[0]} calls)", problems)
    if db is None:
        sys.exit(1)

    # ---------- 4. side by side
    c = compare(old, db, names)
    by_fn = {}
    for p in c.problems:
        by_fn.setdefault(p.rsplit("(", 1)[-1].rstrip(")"), []).append(p)
    step(not c.problems, f"every Review and Check figure equals the old planner's for every airline ({c.n} comparisons over "
         f"{len(old['airlines'])} airlines: cards, the group today, profit by day, cash forecast, route profit for 1, 3 and 7 days, "
         f"aircraft, fare changes, growth lists, load patterns, main hubs, the capture board, can order now)",
         [f"{len(v)} from {k}: " + "; ".join(v[:3]) for k, v in sorted(by_fn.items())] + c.problems[:20])
    info = {al: (len(db["rp"][al]["7"]["routes"]), db["rp"][al]["7"]["flights"], db["fc"][al].get("status")) for al in ids}
    print("      " + "; ".join(f"{al}: {r} routes and {f} flights over 7 days, forecast {s}" for al, (r, f, s) in info.items()), flush=True)

    # ---------- 5. each function's time
    busiest = max(ids, key=lambda al: db["rp"][al]["7"]["flights"])
    try:
        t = timings(psql, ids[busiest], moment)
        slow = [f"{k} {v} ms" for k, v in t.items() if v >= LIMIT_MS]
        step(not slow, f"each function's time on the copy, best of 3 ({busiest} for the per-airline ones): "
             + ", ".join(f"{k} {v} ms" for k, v in t.items()) + f" (each under {LIMIT_MS} ms)", ["too slow: " + ", ".join(slow)])
    except Exception as e:
        step(False, "each function's time on the copy", [why(e)])

    print(f"\n{len(failures)} captured-figures step(s) failed" if failures else "\ncaptured figures on the copy: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
