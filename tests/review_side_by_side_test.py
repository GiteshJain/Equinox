"""The new planner's Review side by side with the old Review on the rehearsal's copy (decision #18, build pull request 10,
spec docs/specs/2026-10-14-review.md, "Checks"): the pull request's own new planner (built into web/app/) and the old
planner (web/planner/, its nav button "Review" opening its finance view, renderFinance), both at their live addresses,
signed in as the same test staff user, at the same frozen moment, reading a full local copy of Supabase restored from
last night's backup. Then the plan card's service check run on last night's plan cards, as a finding.

Run by database/rehearse.sh, last (after the Check side by side). Like tests/check_side_by_side_test.py it uses
tests/real_saves_test.py's helpers and request mapping, needs the copy, so it isn't part of tests/run_all.sh, and nothing
goes outside.

1. The moment: the copy's latest capture plus one hour, as tests/captured_figures_test.py takes it, with typed loads and
   day flags entered after it set aside until the test ends.
2. Both planners open at the moment (the old one from a copy of web/ with captured_figures_test.py's hook, so the test can
   set its screen's state and call its own functions; web/planner/ itself is unchanged). Opening them writes nothing.
3. For every airline, its page in both (the old ui.finAl, the new /review/<code>), every board open: the cards (every
   airline's, which one is picked), the group today (each airline's row; the old board's group totals left out, manual §5),
   the profit chart (its bars' tips and labels, the average) and the table of reported days, Cash, next 14 days (the chart's
   words, every payment, the facts, what's safe to order), route profit for the last day, 3 and 7 days (the filters, the
   line under them, both charts, every row, the aircraft and their table, the fare changes), the fare plan, and manual
   entry (the cash boxes as filled in, the nightly log, the loads by hand for today). Then the chart at 14 intervals: when
   no airline has 15 reported days, one is given typed cash for earlier days for the test (taken out after), and its chart
   must show the last 14.
4. Real saves in the new planner, each then in the old planner from the same copy: cash and fixed costs for today, loads
   typed for today, loads pasted from a saved sample of the game's load table (fixtures/load_table_sample.tsv, filled with
   the copy's flights) with the day marked complete, and "+ fare plan" then "remove" on a route that offers it. Each must
   write exactly the old planner's rows (the copy put back after each), logged as planner (with the tab's ID, or save_loads
   for loads, the old planner's own route), and the old planner, opened again after the new one's save, shows the same.
5. A preview address (127.0.0.1) shows Review, and saving cash, typed loads and a fare plan there send no write.
6. At 380 px wide, Review with every board open, an airline's page opened directly, has no sideways scroll and no errors.
   Screenshots of Review, new and old, at 380 and 1280 px go to REVIEW_SCREENS_DIR (the run's review-screens artifact).
7. The plan card's service check (spec part 2): the library's command (node lib/rules/dist/cli.js check-card) on every plan
   card on the copy, with rules_input() as its input; what it flags is listed (a finding, not a failure).
8. Nothing went outside.

A difference fails and names the airline, the board, the row and both values, unless it is a known difference (KNOWN
below, each with its rule), printed with how often it was used and examples. Prints registrations, codes, flight numbers,
counts and the screens' words, never anything else from the rows, since the log is posted on the pull request; never the
local keys or the test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL, SECRET_TABLES and REVIEW_SCREENS_DIR.
Usage: python3 tests/review_side_by_side_test.py
"""
import asyncio, atexit, json, os, re, secrets, shutil, subprocess, sys, tempfile, time
from collections import Counter
from datetime import date, timedelta
from pathlib import Path
from harness import FIX, LIVE_HOST, ROOT, serve, settle
from playwright.async_api import async_playwright
import real_saves_test as rs
from real_saves_test import count_changes, counts, is_planner_user, library, local_env, log_since, make_user, marks, planner_facts, psql, token_for, why
import planner_next_test as pn
from captured_figures_test import HELD, ms, put_back as put_back_loads, set_aside
from home_side_by_side_test import web_copy

SCREENS_DIR = os.environ.get("REVIEW_SCREENS_DIR")
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"
CLI = ROOT / "lib" / "rules" / "dist" / "cli.js"
PAGE_BOARDS = ["Profit", "Cash, next 14 days", "Route profit", "Fare plan", "Manual entry"]
failures = []
started = time.monotonic()
COPY = {}
HELD_BACK = []

KNOWN = {
    "group totals": {
        "rule": "manual §5: each airline is its own business, and §3: the surplus figure is retired. The old group today board opens with "
                "six group totals (cash across the airlines, flight profit, leases, week-end closing and net a day for the group, and the "
                "aircraft on the ground with their leases); the new board keeps each airline's row and leaves the totals out (the spec). "
                "Only those six figures: every airline's row must be the same.",
        "used": 0, "where": []},
    "boards fold": {
        "rule": "the spec asks Review's boards to fold as Check's do (all folded on arrival, Collapse all and Expand all); the old Review's "
                "boards didn't fold. Only the tools line and the fold marks: the boards are compared open.",
        "used": 0, "where": []},
    "safe-to-order order": {
        "rule": "Cash, next 14 days lists each type an airline may buy: the old planner in its code's order (BUY_TYPES), the database by "
                "aircraft type (airline_aircraft_types; tests/captured_figures_test.py compares them as sets). Only the order: the same pills "
                "with the same words.",
        "used": 0, "where": []},
    "routes order": {
        "rule": "the aircraft table lists the routes each aircraft flew: the old Review in the order the database happened to return "
                "the capture's flights (it asked for none), the captured figures (aircraft_profit()) in the order they were flown, as "
                "Check's side by side allows. Only the order within that cell: the same routes.",
        "used": 0, "where": []},
    "rounding at a boundary": {
        "rule": "a figure the old screen rounded from its own floating-point sums and the database works out exactly can land either side "
                "of a rounding boundary (captured_figures_test.py counts float noise at a boundary as no difference). Only a number one "
                "unit apart in its last place shown, with every other word the same.",
        "used": 0, "where": []},
}


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:30]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


def known(name, where):
    KNOWN[name]["used"] += 1
    if len(KNOWN[name]["where"]) < 12:
        KNOWN[name]["where"].append(where)


# ---------- reading either Review: the new one draws the old one's markup, so one reader serves both (root: the old
# #view, the new main[data-screen=review])
READ = r"""(sel) => {
  const R = document.querySelector(sel);
  if (!R) return null;
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const cls = e => [...e.classList].sort().join(" ");
  const cell = c => T(c) + [...c.querySelectorAll(".pill")].map(p => "{" + cls(p) + "}").join("")
    + (c.classList.contains("neg") || c.querySelector("b.neg") ? "{neg}" : "") + (c.classList.contains("pos") ? "{pos}" : "");
  const rows = t => [...t.querySelectorAll("tr")].filter(tr => tr.style.display !== "none").map(tr => [...tr.children].map(cell));
  const svg = s => ({ texts: [...s.querySelectorAll("text")].map(T), titles: [...s.querySelectorAll("title")].map(T),
    tips: [...s.querySelectorAll("[data-tip]")].map(e => e.getAttribute("data-tip")), bars: [...s.querySelectorAll("rect.bpos, rect.bneg")].map(r => r.getAttribute("class")) });
  const out = {
    title: T(R.querySelector(".vh h1")) + " | " + T(R.querySelector(".vh p")), tools: T(R.querySelector(".revtools")),
    cards: [...R.querySelectorAll(".fgrid .fcard")].map(c => ({ on: c.classList.contains("on"), head: T(c.querySelector(".fch")),
      big: T(c.querySelector(".fbig")) + (c.querySelector(".fbig.neg") ? "{neg}" : ""), sub: T(c.querySelector(".fsub")),
      dt: [...c.querySelectorAll("dt")].map(T), dd: [...c.querySelectorAll("dd")].map(cell), spark: [...c.querySelectorAll(".spark rect")].map(r => r.getAttribute("class")) })),
    boards: {}, order: [] };
  for (const b of R.querySelectorAll(".board")) {
    const h = b.querySelector(":scope > h3.rh");
    if (!h) continue;
    const first = [...h.childNodes].find(n => n.nodeType === 3 && n.textContent.trim());
    const key = h.dataset.rkey || (first ? first.textContent : T(h)).trim();
    out.order.push(key);
    const inputs = [...b.querySelectorAll("input:not([type=checkbox]), textarea")].map(i => (i.dataset.cash !== undefined ? "cash" : i.dataset.fixed !== undefined ? "fixed"
      : i.dataset.q !== undefined ? "loads" : i.id || i.tagName.toLowerCase()) + "=" + i.value);
    const c = b.cloneNode(true);
    const kpis = [...c.querySelectorAll(".gks .gk")].map(T);
    c.querySelectorAll(".gks").forEach(e => e.remove());
    const safe = [...c.querySelectorAll(".fcsafe .pill")].map(p => cls(p) + "|" + T(p));
    c.querySelectorAll(".fcsafe .pill").forEach(e => e.remove());
    const svgs = [...c.querySelectorAll("svg")].map(svg);
    const tables = [...c.querySelectorAll("table")].map(rows);
    const buttons = [...c.querySelectorAll(".mf")].map(x => (x.classList.contains("on") ? "*" : "") + T(x));
    const h3 = c.querySelector(":scope > h3.rh");
    const head = T(h3);
    c.querySelectorAll("svg, table, input, textarea, .mf, :scope > h3.rh").forEach(e => e.remove());
    out.boards[key] = { head, kpis, safe, svgs, tables, buttons, inputs, rest: T(c), pills: [...c.querySelectorAll(".pill")].map(p => cls(p) + "|" + T(p)) };
  }
  return out;
}"""
OLD_ROOT, NEW_ROOT = "#view", "main[data-screen=review]"
NUM = re.compile(r"\d+(?:\.\d+)?")


def near(a, b):
    """Two words the same but for numbers one unit apart in their last place shown (float noise at a rounding boundary)."""
    if not isinstance(a, str) or not isinstance(b, str):
        return False
    pa, pb = NUM.split(a), NUM.split(b)
    na, nb = NUM.findall(a), NUM.findall(b)
    if pa != pb or len(na) != len(nb):
        return False
    for x, y in zip(na, nb):
        if x == y:
            continue
        dx = len(x.split(".")[1]) if "." in x else 0
        dy = len(y.split(".")[1]) if "." in y else 0
        if dx != dy or abs(float(x) - float(y)) > 10 ** -dx + 1e-9:
            return False
    return True


def same(label, o, n, p):
    """o == n, else (a rounding boundary aside) a problem naming where."""
    if o == n:
        return
    if isinstance(o, list) and isinstance(n, list) and len(o) == len(n):
        for i, (x, y) in enumerate(zip(o, n)):
            same(f"{label}[{i}]", x, y, p)
        return
    if near(o, n):
        known("rounding at a boundary", f"{label}: old {o!r}, new {n!r}"[:240])
        return
    p.append(f"{label}: old {o!r}, new {n!r}"[:900])


def compare_board(al, k, o, n):
    p = []
    if o is None or n is None:
        return [f"{al}: {k}: the {'old' if o is None else 'new'} board isn't there"]
    same(f"{al}: {k}: title", o["head"], n["head"], p)
    if o["kpis"] and not n["kpis"]:
        known("group totals", f"{len(o['kpis'])} figures: " + "; ".join(o["kpis"][:6])[:300])
    elif o["kpis"] != n["kpis"]:
        p.append(f"{al}: {k}: the totals: old {o['kpis']}, new {n['kpis']}")
    if o["safe"] != n["safe"]:
        if sorted(o["safe"]) == sorted(n["safe"]):
            known("safe-to-order order", f"{al}: old {[s.split('|')[1].split(' (')[0] for s in o['safe']]}, new {[s.split('|')[1].split(' (')[0] for s in n['safe']]}")
        else:
            same(f"{al}: {k}: safe to order", o["safe"], n["safe"], p)
    if len(o["svgs"]) != len(n["svgs"]):
        p.append(f"{al}: {k}: old {len(o['svgs'])} charts, new {len(n['svgs'])}")
    for i, (a, b) in enumerate(zip(o["svgs"], n["svgs"])):
        for f in ("texts", "titles", "tips", "bars"):
            same(f"{al}: {k}: chart {i + 1}'s {f}", a[f], b[f], p)
    if len(o["tables"]) != len(n["tables"]):
        p.append(f"{al}: {k}: old {len(o['tables'])} tables, new {len(n['tables'])}")
    for i, (a, b) in enumerate(zip(o["tables"], n["tables"])):
        if len(a) != len(b):
            p.append(f"{al}: {k}: table {i + 1} ({(a or [[]])[0][:3]}): old {len(a)} rows, new {len(b)}")
        # a Routes column holds a set: the same routes in another order are a known difference
        sets = [c for c, h in enumerate((a or [[]])[0]) if h == "Routes" and (b or [[]])[0][c:c + 1] == ["Routes"]]
        for r, (x, y) in enumerate(zip(a, b)):
            if r and x != y and sets and len(x) == len(y) and all(
                    (sorted(x[c].split(", ")) == sorted(y[c].split(", "))) if c in sets else x[c] == y[c] for c in range(len(x))):
                known("routes order", f"{al} {x[0]}: old '{x[sets[0]]}', new '{y[sets[0]]}'")
                continue
            same(f"{al}: {k}: table {i + 1} row {r}", x, y, p)
    same(f"{al}: {k}: buttons", o["buttons"], n["buttons"], p)
    same(f"{al}: {k}: boxes", o["inputs"], n["inputs"], p)
    same(f"{al}: {k}: pills", o["pills"], n["pills"], p)
    # a board's other words, without their spaces: the old markup has spaces between its tags where React has none
    ro, rn = re.sub(r"\s", "", o["rest"]), re.sub(r"\s", "", n["rest"])
    if ro != rn and not near(ro, rn):
        i = next((j for j in range(min(len(ro), len(rn))) if ro[j] != rn[j]), min(len(ro), len(rn)))
        p.append(f"{al}: {k}: its words, from character {i}: old …{ro[max(0, i - 120):i + 260]!r}, new …{rn[max(0, i - 120):i + 260]!r}")
    elif ro != rn:
        known("rounding at a boundary", f"{al}: {k}'s words")
    return p


# ---------- the two planners
class OldReview(rs.Planner):
    """The old planner (real_saves_test.py's), its clock frozen at the moment before its scripts run, with the hook."""

    def __init__(self, *a, moment, **k):
        super().__init__(*a, **k)
        self.moment = moment

    async def page(self, host=LIVE_HOST):
        self.pg = pg = await self.ctx.new_page()
        await pg.clock.set_fixed_time(self.moment)
        await pg.emulate_media(reduced_motion="reduce")
        pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
        pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
              if m.type == "error" and "Failed to load resource" not in m.text else None)
        pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await pg.goto(f"http://{host}:{self.port}/planner/")
        return pg

    async def ready(self):
        await self.pg.wait_for_function("() => window.__eqOld && window.__eqOld('CAP.at') > 0", timeout=60000)

    async def run(self, js):
        return await self.pg.evaluate("s => window.__eqOld(s)", js)

    async def review(self, airline, days=7):
        """The old Review (its finance view) on an airline's page, route profit over the days given."""
        await self.run(f"Object.assign(ui, {{view: 'finance', modal: null, finAl: {json.dumps(airline)}, rpDays: {int(days)}, rpSig: '', rpSort: 'pwk', rpQ: ''}}); render(); true")
        await settle(self.pg, 250)

    async def reopen(self):
        await self.pg.close()
        await self.page()
        await self.pg.wait_for_function("() => window.__eqDataLoaded === true", timeout=60000)
        await self.ready()


class NewReview(pn.Planner):
    pass


async def new_review(pl, code=None, expand=True):
    """The new Review at an airline's address, once it has read everything; every board open."""
    to = "/review" + (f"/{code}" if code else "")
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", to)
    await pl.pg.wait_for_function("""want => { const m = document.querySelector('main[data-screen=review]');
        return !!m && m.dataset.reviewReady === 'yes' && decodeURIComponent(m.dataset.reviewView || '') === want; }""", arg=to, timeout=90000)
    await settle(pl.pg, 300)
    if expand:
        await pl.pg.click("#rev-expall")
        await settle(pl.pg, 150)


async def new_days(pl, d):
    await pl.pg.click(f"{NEW_ROOT} [data-rpdays='{d}']")
    await settle(pl.pg, 300)
    await pl.pg.wait_for_function("() => (document.querySelector('main[data-screen=review]') || {dataset: {}}).dataset.reviewReady === 'yes'", timeout=60000)
    await settle(pl.pg, 250)


async def refresh(new):
    """The new planner loaded again (signed in already, its clock still frozen): a new tab ID, the copy read as it is now."""
    await new.pg.reload()
    await new.pg.wait_for_function("!!window.__eqPlanner", timeout=60000)
    await new.pg.wait_for_selector("main[data-screen]", timeout=60000)
    await settle(new.pg, 300)


def page_boards(view):
    """A reading's boards keyed as the new Review keys them: the old airline's profit board is titled with its name."""
    out = {}
    for k, v in (view or {}).get("boards", {}).items():
        out[k if k in PAGE_BOARDS or k == "The group today" else "Profit"] = v
    return out


# ---------- 3. every airline's page
async def pages(old, new):
    p, seen = [], []
    first = True
    for a in COPY["airlines"]:
        await old.review(a["name"])
        await new_review(new, a["code"])
        o, n = await old.pg.evaluate(READ, OLD_ROOT), await new.pg.evaluate(READ, NEW_ROOT)
        if o is None or n is None:
            p.append(f"{a['code']}: the {'old' if o is None else 'new'} Review isn't there")
            continue
        if first:
            same("the title", o["title"], n["title"], p)
            if n["tools"] and not o["tools"]:
                known("boards fold", f"the tools line: {n['tools'][:60]}")
            first = False
        if len(o["cards"]) != len(n["cards"]):
            p.append(f"{a['code']}: old {len(o['cards'])} cards, new {len(n['cards'])}")
        for oc, nc in zip(o["cards"], n["cards"]):
            for f in ("on", "head", "big", "sub", "dt", "dd", "spark"):
                same(f"{a['code']}: the card {oc['head'][:20]}: {f}", oc[f], nc[f], p)
        ob, nb = page_boards(o), page_boards(n)
        order_o = [k if k in PAGE_BOARDS or k == "The group today" else "Profit" for k in o["order"]]
        if order_o != n["order"]:
            p.append(f"{a['code']}: the boards: old {order_o}, new {n['order']}")
        for k in (["The group today"] if "The group today" in ob else []) + PAGE_BOARDS:
            p += compare_board(a["code"], k, ob.get(k), nb.get(k))
        # route profit over the last day and 3 days, then back to 7
        for d in (1, 3):
            await old.review(a["name"], d)
            await new_days(new, d)
            o2, n2 = page_boards(await old.pg.evaluate(READ, OLD_ROOT)), page_boards(await new.pg.evaluate(READ, NEW_ROOT))
            p += [x.replace(": Route profit", f": Route profit ({d} day{'s' if d > 1 else ''})") for x in compare_board(a["code"], "Route profit", o2.get("Route profit"), n2.get("Route profit"))]
        await new_days(new, 7)
        rp = nb.get("Route profit") or {"tables": [[]]}
        prof = nb.get("Profit") or {"svgs": [{"bars": []}], "tables": [[]]}
        seen.append(f"{a['code']} ({len((prof['svgs'] or [{'bars': []}])[0]['bars'])} bars, {max(0, len((prof['tables'] or [[]])[0]) - 1)} days, "
                    f"{max(0, len((rp['tables'] or [[]])[0]) - 1)} routes)")
    return "every airline's page equals the old Review's: the cards, the group today, profit, Cash, next 14 days, route profit (last day, 3 and 7 days), the fare plan and manual entry: " + ", ".join(seen), p


async def chart_at_14(old, new):
    """The profit chart shows the last 14 intervals: on an airline with 15 reported days or more, or one given typed cash for
    earlier days for the test (taken out after)."""
    p = []
    have = {}
    for a in COPY["airlines"]:
        have[a["id"]] = int(psql(f"select count(*) from private.fig_cash_days({int(a['id'])}, :'m'::timestamptz)", m=COPY["moment"]).strip())
    a = max(COPY["airlines"], key=lambda x: have[x["id"]])
    added = 0
    if have[a["id"]] < 16:
        first = psql(f"select coalesce(min(day)::text, '') from private.fig_cash_days({int(a['id'])}, :'m'::timestamptz)", m=COPY["moment"]).strip() or COPY["moment"][:10]
        added = 16 - have[a["id"]]
        psql(f"""begin; select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'review_side_by_side_test', true);
            insert into public.cash_entries (world_id, airline_id, day, cash, entered_at)
            select {WORLD}, {int(a['id'])}, :'f'::date - g, 20000000 + g * 150000 * (case when g % 3 = 0 then -1 else 1 end), :'m'::timestamptz - interval '30 days'
              from generate_series(1, {added}) g
            on conflict (airline_id, day) do nothing; commit;""", f=first, m=COPY["moment"])
    try:
        if added:
            await old.reopen()
            await refresh(new)
        await old.review(a["name"])
        await new_review(new, a["code"])
        ob, nb = page_boards(await old.pg.evaluate(READ, OLD_ROOT)), page_boards(await new.pg.evaluate(READ, NEW_ROOT))
        p += compare_board(a["code"], "Profit", ob.get("Profit"), nb.get("Profit"))
        bars = len(((nb.get("Profit") or {}).get("svgs") or [{"bars": []}])[0]["bars"])
        days = max(0, len(((nb.get("Profit") or {}).get("tables") or [[]])[0]) - 1)
        if bars != min(14, days):
            p.append(f"{a['code']}: the chart shows {bars} intervals of {days}, not the last {min(14, days)}")
        if days < 15:
            p.append(f"{a['code']}: only {days} intervals to chart, so the last 14 can't be told from fewer")
    finally:
        if added:
            psql(f"""begin; select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'review_side_by_side_test', true);
                delete from public.cash_entries where airline_id = {int(a['id'])} and entered_at = :'m'::timestamptz - interval '30 days'; commit;""", m=COPY["moment"])
            await old.reopen()
            await refresh(new)
    return (f"the profit chart shows the last 14 intervals, as the old one: {a['code']} with {bars} bars of {days} reported intervals"
            + (f" ({added} earlier days of typed cash given for the test, taken out after)" if added else "")), p


# ---------- 4. saves, in the new planner and then in the old, from the same copy
async def until_quiet(seconds=30):
    """Waits for the change log to grow and then stop growing for 2 s (the old planner saves after 0.3 s, all at once)."""
    end, last, still = time.monotonic() + seconds, -1, 0.0
    while time.monotonic() < end:
        n = int(psql("select coalesce(max(id), 0) from public.change_log").strip())
        if n == last and n > 0:
            still += 0.5
            if still >= 2:
                return
        else:
            still = 0.0
        last = n
        await asyncio.sleep(0.5)


def kinds(rows):
    return Counter((r["table"], r["op"]) for r in rows)


def snapshot(sql_rows):
    """The rows a query gives, as JSON, without their times (each side writes its own)."""
    rows = json.loads(psql(f"select coalesce(json_agg(x), '[]') from ({sql_rows}) x").strip())
    for r in rows:
        for c in ("id", "created_at", "updated_at", "entered_at", "saved_at_ms"):
            r.pop(c, None)
    return rows


def restore(table, key_sql, rows_json):
    """Puts a table's rows for a key back as they were, ids and all (the change log off for the test's own moves)."""
    psql(f"""set equinox.change_log = 'off';
        delete from public.{table} where {key_sql};
        insert into public.{table} overriding system value select * from json_populate_recordset(null::public.{table}, :'rows'::json);""", rows=rows_json)


def raw(table, key_sql):
    return psql(f"select coalesce(json_agg(t), '[]') from public.{table} t where {key_sql}").strip()


async def both(name, old, new, today, tables, act_new, act_old, after_new=None, detail=None):
    """One save in the new planner, the copy put back, then the same in the old: the same rows and kinds of change."""
    problems = []
    before = {t: raw(t, k) for t, k in tables.items()}
    await refresh(new)
    client = await new.pg.evaluate("window.__eqPlanner.client")
    mark = marks()
    await act_new()
    await rs.wait_for(lambda: log_since(mark), lambda got: len(got) >= 1, seconds=30)
    await until_quiet()
    new_log = log_since(mark)
    new_rows = {t: snapshot(f"select * from public.{t} where {k}") for t, k in tables.items()}
    want = detail or client
    problems += [f"a change-log row names {r['actor']} ({r['detail']}), not planner ({'the tab' if want == client else want})" for r in new_log
                 if r["actor"] != "planner" or r["detail"] != want]
    if after_new:
        problems += await after_new()
    for t, k in tables.items():
        restore(t, k, before[t])
    mark2 = marks()
    await old.reopen()
    await act_old()
    await rs.wait_for(lambda: log_since(mark2), lambda got: len(got) >= 1, seconds=30)
    await until_quiet()
    old_log = log_since(mark2)
    old_rows = {t: snapshot(f"select * from public.{t} where {k}") for t, k in tables.items()}
    for t, k in tables.items():
        restore(t, k, before[t])
    if kinds(new_log) != kinds(old_log):
        problems.append(f"the new planner changed {dict(kinds(new_log))}, the old {dict(kinds(old_log))}")
    for t in tables:
        if new_rows[t] != old_rows[t]:
            problems.append(f"{t} after the new planner's save differs from the old's: new {new_rows[t]}, old {old_rows[t]}"[:900])
    if not new_log:
        problems.append("the new planner wrote nothing")
    mark3 = marks()
    await old.reopen()
    await refresh(new)
    await asyncio.sleep(1)
    for t, k in tables.items():
        if json.loads(raw(t, k)) != json.loads(before[t]):
            late = log_since(mark3)
            problems.append(f"{t} changed again after it was put back, with both planners opened again ({dict(kinds(late))}"
                            f"{', by ' + late[0]['actor'] + ' (' + str(late[0]['detail']) + ')' if late else ''}): put back once more")
            restore(t, k, before[t])
    return f"{name}: {dict(kinds(new_log))}, the same rows as the old planner's, logged as planner" + (" (save_loads, the old route)" if detail else " with the tab's ID"), problems


async def saves(old, new, today, out):
    w = COPY["world"]
    # ---- cash and fixed costs for today: the first airline with today's cash, a figure 1.11M more and its fixed costs typed
    log = json.loads(psql("select private.fig_cash_log(:'w'::bigint, :'m'::timestamptz)", w=w, m=COPY["moment"]).strip())
    pick = next((a for a in log["airlines"] if a["today"]["shown_cash"] is not None), (log["airlines"] or [None])[0])
    if pick:
        a = next(x for x in COPY["airlines"] if x["id"] == pick["airline_id"])
        cash = f"{round((pick['today']['shown_cash'] or 10) + 1.11, 2)}"
        fixed = f"{round((pick['today']['shown_fixed'] or 0) + 0.37, 2)}"
        day = log["today"]

        async def act_new():
            await new_review(new, a["code"])
            await new.pg.fill(f"[data-cash={json.dumps(a['code'])}]", cash)
            await new.pg.fill(f"[data-fixed={json.dumps(a['code'])}]", fixed)
            await new.pg.click("#cashsave")

        async def act_old():
            await old.review(a["name"])
            await old.pg.fill(f"[data-cash={json.dumps(a['name'])}]", cash)
            await old.pg.fill(f"[data-fixed={json.dumps(a['name'])}]", fixed)
            await old.pg.click("#cashsave")

        async def shows():
            await old.reopen()
            got = json.loads(await old.run(f"JSON.stringify([(state.cash[{json.dumps(day)}] || {{}})[{json.dumps(a['name'])}], (state.fixed7[{json.dumps(day)}] || {{}})[{json.dumps(a['name'])}]])"))
            return [] if got == [float(cash), float(fixed)] else [f"the old planner, opened again, shows cash and fixed costs {got}, not {cash} and {fixed}"]
        try:
            out.append(await both(f"cash and fixed costs for today ({a['code']}: {cash}M and {fixed}M typed)", old, new, today,
                                  {"cash_entries": f"airline_id = {int(a['id'])} and day = '{day}'"}, act_new, act_old, shows))
        except Exception as e:
            out.append(("cash and fixed costs for today", [why(e)]))
    else:
        out.append(("cash and fixed costs for today", ["no airline on the copy"]))

    # ---- loads typed for today: one more flight of the first airline flying today, at 60%
    day = COPY["moment"][:10]
    flights = json.loads(await old.run(f"JSON.stringify(flightsOn({json.dumps(day)}).map(f => ({{airline: f.airline, no: f.no, from: f.from, to: f.to, tail: f.tail}})))"))
    names = {a["name"]: a for a in COPY["airlines"]}
    fl = next((f for f in flights if f["airline"] in names), None)
    if fl:
        a = names[fl["airline"]]
        cur = json.loads(await old.run(f"JSON.stringify((lfDay({json.dumps(day)}) || {{f: {{}}}}).f)"))
        under = ", ".join(f"{k.split('|')[1]} {v}" for k, v in sorted(((k, v) for k, v in cur.items() if k.startswith(a["name"] + "|") and float(v) < 95), key=lambda x: x[1]))
        typed = (under + ", " if under else "") + f"{fl['no']} 60"
        tables = {"load_entries": f"world_id = {w} and game_date = '{day}'", "load_days": f"world_id = {w} and game_date = '{day}'"}

        async def open_new_loads():
            await new_review(new, a["code"])
            await new.pg.evaluate("document.querySelector('[data-loads-by-hand]').open = true")
            await settle(new.pg, 200)

        async def act_new():
            await open_new_loads()
            await new.pg.fill(f"[data-q={json.dumps((a['code'] or a['name']) + '|x')}]", typed)
            await new.pg.click("#lfsave")

        async def act_old():
            await old.review(a["name"])
            await old.pg.evaluate("document.querySelector('details.gsub [data-det=lfman]').parentElement.open = true")
            await old.pg.fill(f"[data-q={json.dumps(a['name'] + '|x')}]", typed)
            await old.pg.click("#lfsave")

        async def shows():
            await old.reopen()
            got = json.loads(await old.run(f"JSON.stringify((lfDay({json.dumps(day)}) || {{f: {{}}}}).f[{json.dumps(a['name'] + '|' + str(fl['no']))}] ?? null)"))
            return [] if got == 60 else [f"the old planner, opened again, shows flight {fl['no']} at {got}, not 60"]
        try:
            out.append(await both(f"loads typed for {day} ({a['code']} {fl['no']} at 60%, with the {len(under.split(', ')) if under else 0} already under 95%)",
                                  old, new, today, tables, act_new, act_old, shows, detail="save_loads"))
        except Exception as e:
            out.append(("loads typed", [why(e)]))

        # ---- loads pasted from the saved sample, the day marked complete
        mine = [f for f in flights if f["airline"] == a["name"]][:2]
        if len(mine) == 2:
            text = (FIX / "load_table_sample.tsv").read_text()
            for k, v in {"{CODE}": a["code"], "{NO1}": mine[0]["no"], "{NO2}": mine[1]["no"], "{TAIL}": mine[0]["tail"] or "X-TEST",
                         "{FROM1}": mine[0]["from"], "{TO1}": mine[0]["to"], "{FROM2}": mine[1]["from"], "{TO2}": mine[1]["to"],
                         "{DM}": f"{day[8:10]}.{day[5:7]}."}.items():
                text = text.replace(k, str(v))

            async def act_new_paste():
                await open_new_loads()
                await new.pg.evaluate("document.querySelector('details.lfpaste').open = true")
                await new.pg.fill("#lfpaste-in", text)
                await new.pg.click("#lfpaste-read")
                await new.pg.wait_for_selector("[data-paste-preview] #lfpaste-save", timeout=10000)
                await new.pg.click("#lfpaste-save")

            async def act_old_paste():
                await old.review(a["name"])
                await old.pg.evaluate("document.querySelector('details.gsub [data-det=lfman]').parentElement.open = true; document.querySelector('details.lfpaste').open = true")
                await old.pg.fill("#lfpaste-in", text)
                await old.pg.click("#lfpaste-read")
                await old.pg.wait_for_selector("#lfpaste-save", timeout=10000)
                await old.pg.click("#lfpaste-save")

            async def shows_paste():
                await old.reopen()
                d = json.loads(await old.run(f"JSON.stringify(lfDay({json.dumps(day)}) || null)")) or {}
                got = (d.get("done"), (d.get("f") or {}).get(f"{a['name']}|{mine[0]['no']}"), f"{a['name']}|{mine[1]['no']}" in (d.get("f") or {}))
                return [] if got == (True, 81, False) else [f"the old planner, opened again, shows the day {got}, not complete with {mine[0]['no']} at 81% and {mine[1]['no']} cleared"]
            try:
                out.append(await both(f"loads pasted from the saved sample ({a['code']} {mine[0]['no']} at 81%, {mine[1]['no']} full) with {day} marked complete",
                                      old, new, today, tables, act_new_paste, act_old_paste, shows_paste, detail="save_loads"))
            except Exception as e:
                out.append(("loads pasted", [why(e)]))
        else:
            out.append((f"loads pasted: {a['code']} flies fewer than two flights on {day}", []))
    else:
        out.append((f"loads typed and pasted: no flight of ours on {day}", []))

    # ---- + fare plan, then remove, on a route that offers it
    offer = None
    for a in COPY["airlines"]:
        await new_review(new, a["code"])
        key = await new.pg.evaluate("(document.querySelector('[data-fareadd]') || {dataset: {}}).dataset.fareadd || ''")
        if key:
            offer = (a, key)
            break
    if offer:
        a, key = offer
        hub, dest = key.split("-")
        tables = {"fare_plan": f"airline_id = {int(a['id'])}"}
        rk = f"{a['name']}|{hub}|{dest}"

        async def add_new():
            await new_review(new, a["code"])
            await new.pg.click(f"[data-fareadd={json.dumps(key)}]")

        async def add_old():
            await old.review(a["name"])
            await old.pg.click(f"[data-fareadd={json.dumps(rk)}]")

        async def shows_add():
            await old.reopen()
            got = json.loads(await old.run(f"JSON.stringify((state.farePlan || []).filter(p => p.routeKey === {json.dumps(rk)} && p.status === 'planned').map(p => [p.pct, p.cls, p.why]))"))
            return [] if got == [[5, "economy", "sells out"]] else [f"the old planner, opened again, shows the fare plan {got}"]
        try:
            out.append(await both(f"+ fare plan on {a['code']} {hub}–{dest}", old, new, today, tables, add_new, add_old, shows_add))
        except Exception as e:
            out.append(("+ fare plan", [why(e)]))
        # remove: a change planned for the test (as the old planner adds it), dropped in each
        before = raw("fare_plan", tables["fare_plan"])
        try:
            await refresh(new)
            await new_review(new, a["code"])
            await new.pg.click(f"[data-fareadd={json.dumps(key)}]")
            await until_quiet()
            fp = json.loads(psql(f"select coalesce((select json_build_object('id', id, 'key', legacy_key) from public.fare_plan where airline_id = {int(a['id'])} and status = 'planned' order by id desc limit 1)::text, 'null')").strip())
            added = raw("fare_plan", tables["fare_plan"])

            async def drop_new():
                await new_review(new, a["code"])
                await new.pg.click(f"[data-faredel='{int(fp['id'])}']")

            async def drop_old():
                await old.review(a["name"])
                await old.pg.click(f"[data-faredel={json.dumps(fp['key'])}]")

            async def shows_drop():
                await old.reopen()
                got = json.loads(await old.run(f"JSON.stringify(((state.farePlan || []).find(p => p.id === {json.dumps(fp['key'])}) || {{}}).status || null)"))
                return [] if got == "dropped" else [f"the old planner, opened again, shows the change as {got}"]
            label, problems = await both_from(f"remove on {a['code']} {hub}–{dest}", old, new, today, tables, added, drop_new, drop_old, shows_drop)
            out.append((label, problems))
        except Exception as e:
            out.append(("remove", [why(e)]))
        finally:
            try:
                restore("fare_plan", tables["fare_plan"], before)
                await refresh(new)
            except Exception as e:
                out.append(("the fare plan put back", [why(e)]))
    else:
        out.append(("+ fare plan and remove: no route on the copy offers a fare plan (none marked raise fares or add a flight without one planned)", []))
    return out


async def both_from(name, old, new, today, tables, start_json, act_new, act_old, after_new):
    """As both(), from a given state of the tables (the rows as JSON), put back before each side."""
    for t, k in tables.items():
        restore(t, k, start_json)
    return await both(name, old, new, today, tables, act_new, act_old, after_new)


# ---------- 5. a preview, 6. a phone and the screenshots
async def preview(p, port, env, facts, staff, moment, seen):
    pv = NewReview(p, port, env, facts)
    seen.append(pv)
    problems, clicked = [], []
    try:
        await pv.open(host="127.0.0.1", moment=moment)
        await pv.pg.emulate_media(reduced_motion="reduce")
        await pv.sign_in(*staff)
        n0, mark = counts(), marks()
        await new_review(pv, COPY["airlines"][0]["code"])
        code = COPY["airlines"][0]["code"]
        if await pv.pg.evaluate("s => !!document.querySelector(s)", f"[data-cash={json.dumps(code)}]"):
            await pv.pg.fill(f"[data-cash={json.dumps(code)}]", "99.99")
            await pv.pg.click("#cashsave")
            clicked.append("cash")
            await settle(pv.pg, 600)
        await pv.pg.evaluate("document.querySelector('[data-loads-by-hand]').open = true")
        box = await pv.pg.evaluate("(document.querySelector('[data-q]') || {dataset: {}}).dataset.q || ''")
        if box:
            await pv.pg.fill(f"[data-q={json.dumps(box)}]", "1 50")
            await pv.pg.click("#lfsave")
            clicked.append("typed loads")
            await settle(pv.pg, 600)
        if await pv.pg.evaluate("!!document.querySelector('[data-fareadd]')"):
            await pv.pg.click("[data-fareadd]")
            clicked.append("+ fare plan")
            await settle(pv.pg, 600)
        state = await pv.pg.evaluate("(document.querySelector('[data-save-state]') || {}).textContent")
        if state != "preview · not saved":
            problems.append(f"the header says {state!r}, not \"preview · not saved\"")
        for fn in ("planner_save", "save_loads"):
            if fn in pv.rpcs:
                problems.append(f"the preview sent {fn}() to the copy")
        if log_since(mark):
            problems.append("the tables changed")
        problems += count_changes(n0, counts()) + pv.errors
    finally:
        await pv.close()
    return (f"a preview address (127.0.0.1) shows Review, and {', '.join(clicked) or 'nothing'} there send no write "
            f"(it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})"), problems


async def phone(p, port, env, facts, staff, moment, seen):
    ph = NewReview(p, port, env, facts, width=380, height=800)
    seen.append(ph)
    problems = []
    scroll = "Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth"
    try:
        await ph.open(moment=moment)
        await ph.pg.emulate_media(reduced_motion="reduce")
        await ph.sign_in(*staff)
        for a in COPY["airlines"][:2]:
            await new_review(ph, a["code"])
            await ph.pg.evaluate("document.querySelectorAll('main[data-screen=review] details').forEach(d => { d.open = true; })")
            await settle(ph.pg, 300)
            if (over := await ph.pg.evaluate(scroll)) > 0:
                wide = await ph.pg.evaluate("""() => [...document.querySelectorAll('main[data-screen=review] *')].filter(e => e.getBoundingClientRect().right > window.innerWidth + 1
                    && !e.closest('.tblwrap, .tscroll')).slice(0, 4).map(e => e.tagName + '.' + [...e.classList].join('.'))""")
                problems.append(f"Review/{a['code']}, every board open, scrolls sideways by {over} px at 380 px wide (too wide: {wide})")
        problems += ph.errors
    finally:
        await ph.close()
    return "at 380 px wide Review, every board and its folds open, has no sideways scroll and no errors; the cards stack and wide tables scroll in their own box", problems


async def screenshots(old, new):
    if not SCREENS_DIR:
        return
    Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    a = COPY["airlines"][0]
    for width, height in ((1280, 900), (380, 800)):
        await old.pg.set_viewport_size({"width": width, "height": height})
        await new.pg.set_viewport_size({"width": width, "height": height})
        await old.review(a["name"])
        await settle(old.pg, 400)
        await old.pg.screenshot(path=str(Path(SCREENS_DIR) / f"old-review-{width}.png"), full_page=True, timeout=90000)
        await new_review(new, a["code"])
        await settle(new.pg, 400)
        await new.pg.screenshot(path=str(Path(SCREENS_DIR) / f"review-{width}.png"), full_page=True, timeout=90000)
    await old.pg.set_viewport_size({"width": 1440, "height": 1000})
    await new.pg.set_viewport_size({"width": 1280, "height": 900})


# ---------- 7. the plan card's service check, as a finding
def service_finding():
    """The library's command on every plan card on the copy: what its service check flags (a finding, never a failure)."""
    if not CLI.is_file():
        return "the plan card's service check: lib/rules/dist/cli.js isn't built", ["run npm run build first"]
    work = Path(tempfile.mkdtemp(prefix="service-check-"))
    try:
        rules = work / "rules.json"
        rules.write_text(psql("select private.rules_input_doc(null, 'all')").strip())
        cards = json.loads(psql(f"""select coalesce(json_agg(c order by c.id), '[]') from (
            select pc.id, al.iata_code as airline, a.registration, a.status, t.name as type,
                   (select json_agg(json_build_object('flight_no', l.flight_no, 'origin_code', l.origin_code, 'dest_code', l.dest_code,
                                                      'days_utc', l.days_utc, 'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min, 'service_code', l.service_code)
                                    order by l.position, l.id)
                      from public.plan_card_legs l where l.plan_card_id = pc.id) as legs
              from public.plan_cards pc join public.airlines al on al.id = pc.airline_id
              left join public.aircraft a on a.id = pc.aircraft_id left join public.aircraft_types t on t.id = a.aircraft_type_id
             where pc.world_id = {WORLD}) c""").strip())
        lines, flagged, legs_n, flagged_legs, skipped = [], 0, 0, 0, []
        for c in cards:
            legs = [l for l in (c["legs"] or []) if l["dep_utc_min"] is not None]
            if not legs:
                skipped.append(f"card {c['id']} ({c['registration']}): no timed legs")
                continue
            card = {"aircraft": c["registration"], "legs": legs}
            path = work / f"card_{c['id']}.json"
            path.write_text(json.dumps(card))
            r = subprocess.run(["node", str(CLI), "check-card", str(rules), str(path)], capture_output=True, text=True, timeout=60)
            if r.returncode:
                # an aircraft not in the input (an order): by its type and airline instead
                card = {"type": c["type"], "airline": c["airline"], "legs": legs}
                path.write_text(json.dumps(card))
                r = subprocess.run(["node", str(CLI), "check-card", str(rules), str(path)], capture_output=True, text=True, timeout=60)
            if r.returncode:
                skipped.append(f"card {c['id']} ({c['registration']}): {(r.stderr.strip().splitlines() or ['refused'])[-1][:120]}")
                continue
            ans = json.loads(r.stdout)
            svc = ans.get("service") or {}
            legs_n += len(svc.get("legs") or [])
            issues = svc.get("issues") or []
            if issues:
                flagged += 1
                flagged_legs += len(issues)
                lines.append(f"{c['airline']} {c['registration']}: " + "; ".join(
                    f"{i.get('flight_no') or ''} {i['from']}–{i['to']} {i.get('given') or 'no code'} → {i['wanted']} ({i['km']} km)" for i in issues))
        print(f"ok    finding: the plan card's service check (node lib/rules/dist/cli.js check-card) on the copy's {len(cards)} plan cards: "
              f"{flagged} card(s) with {flagged_legs} of {legs_n} legs flagged" + (f"; {len(skipped)} not checked" if skipped else ""), flush=True)
        for x in lines[:60]:
            print("      " + x, flush=True)
        for x in skipped[:10]:
            print("      not checked: " + x, flush=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ---------- what the copy holds
def read_copy():
    # the airlines the captured figures cover, by the name the old planner knows them by (its planner name)
    airlines = json.loads(psql(f"""select coalesce(json_agg(json_build_object('id', x.airline_id, 'code', x.iata_code,
              'name', coalesce(a.planner_name, a.public_name, a.game_name)) order by x.ord), '[]')
              from private.fig_airlines({WORLD}) x join public.airlines a on a.id = x.airline_id""").strip())
    COPY.update(airlines=airlines, world=int(psql(f"select {WORLD}").strip()))
    return airlines


async def main():
    facts, nfacts = planner_facts(), pn.planner_facts()
    if not facts or not nfacts:
        step(False, "both planners name their Supabase address and public key", ["not found in web/planner/index.html or app/planner/src/data/config.ts"])
        sys.exit(1)
    if not pn.PAGE.is_file():
        step(False, "the new planner is built", ["web/app/index.html is missing: run npm ci && npm run build first"])
        sys.exit(1)
    try:
        env = local_env()
        lib_js = library(facts["lib_version"])
    except Exception as e:
        step(False, "set up: the copy's address and the old planner's Supabase library", [why(e)])
        sys.exit(1)

    moment = psql("select to_char((max(captured_at) + interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') from public.game_capture_raw").strip()
    today = moment[:10]
    COPY["moment"] = moment
    try:
        held = set_aside(psql, moment)
        atexit.register(lambda: HELD_BACK or put_back_loads(psql, held))
        airlines = read_copy()
        problems = [] if airlines else ["the copy has none of our airlines"]
    except Exception as e:
        held, airlines, problems = {}, [], [why(e)]
    aside = [f"{r.get('airline_id', '')} {r.get('game_date')} {r.get('flight_no', 'day')}" for t in HELD for r in json.loads(held.get(t) or "[]")]
    step(not problems, f"the moment: {moment} (the copy's latest capture plus one hour); typed loads and day flags entered after it set aside until the test "
         "ends (" + ", ".join(f"{t}: {len(json.loads(held.get(t) or '[]'))}" for t in HELD) + (f": {'; '.join(aside[:6])}" if aside else "")
         + f"); the copy: {len(airlines)} of our airlines", problems)
    if problems:
        sys.exit(1)

    tag = secrets.token_hex(4)
    staff = (f"review-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="review-side-by-side-"))
    seen = []
    try:
        root = web_copy(work)
        with serve(root) as port:
            async with async_playwright() as p:
                old = OldReview(p, port, env, facts, lib_js, moment=moment)
                new = NewReview(p, port, env, nfacts, width=1280, height=900)
                seen += [old, new]
                try:
                    n0, mark = counts(), marks()
                    await old.open()
                    await old.sign_in(*staff)
                    await old.ready()
                    await new.open(moment=moment)
                    await new.pg.emulate_media(reduced_motion="reduce")
                    await new.sign_in(*staff)
                    await new_review(new, expand=False)
                    problems = list(old.errors) + list(new.errors)
                    if log_since(mark):
                        problems.append("opening the planners changed the tables")
                    problems += count_changes(n0, counts())
                    if abs(await new.pg.evaluate("Date.now()") - ms(moment)) > 1000:
                        problems.append("the new planner's clock isn't frozen at the moment")
                    if await new.pg.evaluate("!!document.querySelector('main[data-screen=review] [data-not-built]')"):
                        problems.append("Review is still a placeholder")
                    folded = await new.pg.evaluate("[...document.querySelectorAll('main[data-screen=review] .board')].every(b => b.classList.contains('rcol'))")
                    if not folded:
                        problems.append("the new Review's boards aren't all folded on arrival")
                except Exception as e:
                    problems = [why(e)] + old.errors[:3] + new.errors[:3]
                step(not problems, "both planners opened at the moment, signed in as test staff, the new one on Review with its boards folded; opening them wrote nothing", problems)
                if problems:
                    sys.exit(1)

                for check in (pages, chart_at_14):
                    t = time.monotonic()
                    try:
                        label, problems = await check(old, new)
                    except Exception as e:
                        label, problems = check.__name__, [why(e)]
                    step(not problems, label + f" ({time.monotonic() - t:.0f} s)", problems + new.errors[:3] + old.errors[:3])
                try:
                    await screenshots(old, new)
                except Exception as e:
                    print(f"      the screenshots: {why(e)}", flush=True)
                for k, v in KNOWN.items():
                    where = f" (e.g. {'; '.join(v['where'][:4])})" if v["where"] else ""
                    print(f"      known difference \"{k}\": used {v['used']} time(s){where}. {v['rule']}"[:1800], flush=True)

                done = []
                try:
                    await saves(old, new, today, done)
                except Exception as e:
                    done.append(("saving cash, loads and the fare plan in the new Review", [why(e)]))
                for label, problems in done:
                    step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                await old.close()
                await new.close()

                for check in (preview, phone):
                    try:
                        label, problems = await check(p, port, env, nfacts, staff, moment, seen)
                    except Exception as e:
                        label, problems = check.__name__, [why(e)]
                    step(not problems, label, problems)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    try:
        service_finding()
    except Exception as e:
        print(f"ok    finding: the plan card's service check couldn't run ({why(e)})", flush=True)

    if any(json.loads(held.get(t) or "[]") for t in HELD):
        problems = []
        try:
            put_back_loads(psql, held)
        except Exception as e:
            # name the rows the test left where a set-aside row goes back
            clash = psql("""select coalesce(json_agg(e), '[]') from public.load_entries e join json_populate_recordset(null::public.load_entries, :'h'::json) h
                              using (airline_id, game_date, flight_no)""", h=held.get("load_entries") or "[]").strip()
            problems = [why(e), f"in the way: {clash[:600]}"]
        HELD_BACK.append(True)
        step(not problems, "the typed loads and day flags set aside at the start put back as they were", problems)

    outside = sorted({h for x in seen for h in x.outside})
    stopped = ", ".join(sorted({h for x in seen for h in x.stopped})) or "nothing"
    step(not outside, f"nothing went outside ({sum(x.copy for x in seen)} requests answered by the copy, {sum(x.local for x in seen)} "
                      f"from the local server; stopped: {stopped})", ["reached: " + ", ".join(outside)] if outside else [])
    print(f"\n{len(failures)} Review side-by-side step(s) failed" if failures else "\nReview side by side: all passed", flush=True)
    print(f"      the Review side by side took {time.monotonic() - started:.0f} s", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
