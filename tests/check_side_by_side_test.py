"""The new planner's Check side by side with the old Check on the rehearsal's copy (decision #18, build pull request 9,
spec docs/specs/2026-10-13-check.md, "Checks"): the pull request's own new planner (built into web/app/) and the old
planner (web/planner/, its nav button "Check" opening its review view), both at their live addresses, signed in as the
same test staff user, at the same frozen moment, reading a full local copy of Supabase restored from last night's backup.

Run by database/rehearse.sh, last (after the Hubs side by side). Like tests/tails_side_by_side_test.py it uses
tests/real_saves_test.py's helpers and request mapping, needs the copy, so it isn't part of tests/run_all.sh, and nothing
goes outside. /api/game-schedule is answered by the test, from the saved sample Tails' test uses
(tests/fixtures/schedule_113.expected.json, the function's answer for a saved game page) and from each airline's own
flights as the old planner lists them, with differences put in.

1. The moment: the copy's latest capture plus one hour, as tests/captured_figures_test.py takes it, with typed loads and
   day flags entered after it set aside until the test ends.
2. Both planners open at the moment (the old one from a copy of web/ with captured_figures_test.py's hook, so the test can
   set its screen's state and call its own functions; web/planner/ itself is unchanged). Opening them writes nothing.
3. The boards fold as the old ones do: all folded on arrival, Expand all, a board's title, Collapse all.
4. Every board equals the old one's: Capture, Growth, Aircraft checks and Cabins (every table row, pill, bar and line of
   words), and the daily load report on each of the last 7 days (the ‹ button), its summary and every airline's flights.
5. The game check, the game answering: Kingfisher's saved sample for the airline whose game ID it is; one airline its own
   flights with a time changed, days changed, a flight taken out, one valid only from a date and a round trip on one of
   its routes (one it doesn't fly yet, where it has one); one airline "502"; the rest their own flights exactly. Each airline's line and its
   pop-up equal the old ones. Then fix one, fix all and add a flight in the new planner, the copy put back, and the same
   in the old planner: both must write the same rows (the legs, the rotation and its legs) and the same kinds of change.
6. Mark checked, Refitted to, Keep as is and Show again, and logging an order, through the new Check's own buttons: each
   writes only its rows, logged as planner with the tab's ID, and the old planner, opened again, shows the same.
7. A preview address (127.0.0.1) shows Check, and Mark checked, Keep as is and logging an order there send no write.
8. At 380 px wide, every board open and a game check's pop-up, nothing scrolls sideways and there are no errors.
   Screenshots of Check, new and old, at 380 and 1280 px go to CHECK_SCREENS_DIR (the run's check-screens artifact).
9. Nothing went outside.

A difference fails and names the board, the row and both values, unless it is a known difference (KNOWN below, each with
its rule), printed with how often it was used and examples. Prints registrations, codes, flight numbers, counts and the
screens' words, never anything else from the rows, since the log is posted on the pull request; never the local keys or
the test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL, SECRET_TABLES and CHECK_SCREENS_DIR.
Usage: python3 tests/check_side_by_side_test.py
"""
import asyncio, atexit, json, os, re, secrets, shutil, sys, tempfile, time
from collections import Counter
from datetime import date, timedelta
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from harness import FIX, LIVE_HOST, serve, settle
from playwright.async_api import async_playwright
import real_saves_test as rs
from real_saves_test import count_changes, counts, is_planner_user, library, local_env, log_since, make_user, marks, planner_facts, psql, token_for, why
import planner_next_test as pn
from captured_figures_test import HELD, ms, put_back as put_back_loads, set_aside
from home_side_by_side_test import web_copy

SCREENS_DIR = os.environ.get("CHECK_SCREENS_DIR")
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"
BOARDS = ["Capture", "Growth", "Aircraft checks", "Cabins", "Game check", "Daily load report"]
REPORT_DAYS = 7
failures = []
started = time.monotonic()
COPY = {}

KNOWN = {
    "suggested size": {
        "rule": "the old next move named a suggested aircraft size after each route (suggestSize, bigSize, feedSize: by stars, distance and "
                "Ryanair, a rule in the old planner's code with no home in the database), and so did the last column (Add) of its routes ready "
                "from the load reports. The spec asks to say so rather than copy such a rule into the screen, so the new options name the "
                "route and its stars only. Only the size words (the old .sz) and that column.",
        "used": 0, "where": []},
    "order queue families": {
        "rule": "the old order queues had three families typed into its code (A320 family, A350, E195; Ryanair without the A350); the new "
                "columns are the families our airlines may have (airline_aircraft_types), in name order, and \"not in fleet\" where an airline may "
                "not. Only a column one has and the other hasn't: the columns both have must be the same.",
        "used": 0, "where": []},
    "regions": {
        "rule": "the old hub readiness named the region of each city from a list of countries by region typed into its code (REGION_OF), "
                "which isn't in the database; the new table counts the cities by country (airports.country_code), as Hubs does (build "
                "pull request 8). Only the last column and its heading: the cities flying and with planned must be the same.",
        "used": 0, "where": []},
    "minimum connection time": {
        "rule": "manual §4: each airport's minimum connection time (world_airports.mct_min). The old planner feeds no bank at a base with no "
                "figure; the library uses 90 minutes there (#19 spec §5, as tests/rules_library_test.py allows). Only hub readiness rows at a "
                "base with no mct_min.",
        "used": 0, "where": []},
    "order on a tie": {
        "rule": "aircraft whose one-week checks come up the same day: the old list kept them in its list of tails' order (only in the "
                "adapter's extra), the library in the aircraft's order, as Home's test allows. Only the order within one day's row.",
        "used": 0, "where": []},
    "load pill order": {
        "rule": "a check's load-pattern pills: the old Check listed them in the order its load window met the routes (day by day back from "
                "two days ahead, skipping days not reported); the new one orders them by the schedule's departures over the same days. "
                "Only the order: the same pills with the same words.",
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


# ---------- reading either Check: the new one draws the old one's markup, so one reader serves both (root: the old #view,
# the new main[data-screen=check])
READ = r"""(sel) => {
  const R = document.querySelector(sel);
  if (!R) return null;
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const cls = e => [...e.classList].sort().join(" ");
  const cell = c => T(c) + [...c.querySelectorAll(".pill")].map(p => "{" + cls(p) + "}").join("");
  const rows = t => [...t.querySelectorAll("tr")].map(tr => [...tr.children].map(cell));
  const out = { title: T(R.querySelector(".vh h1")) + " | " + T(R.querySelector(".vh p")), tools: T(R.querySelector(".revtools")), boards: {}, order: [] };
  for (const b of R.querySelectorAll(".board")) {
    const h = b.querySelector(":scope > h3.rh");
    if (!h || !h.dataset.rkey) continue;
    out.order.push(h.dataset.rkey);
    const c = b.cloneNode(true);
    const sizes = [...c.querySelectorAll(".sz")].map(T);
    c.querySelectorAll(".sz").forEach(e => e.remove());
    const tables = [...c.querySelectorAll("table")].map(rows);
    const bars = [...c.querySelectorAll(".hpbar i")].map(i => i.style.width);
    const cards = [...c.querySelectorAll(".ck")].map(k => ({ head: T(k.querySelector(".ckh")), pills: [...k.querySelectorAll(".ckb .pill")].map(p => cls(p) + "|" + T(p)),
      note: T(k.querySelector(".note")) }));
    const qcards = [...c.querySelectorAll(".qcard")].map(q => ({ head: T(q.querySelector(".qh > .dim")), logo: !!q.querySelector(".qh > img.alogo"),
      name: q.querySelector(".qh > img.alogo") ? "" : T(q.querySelector(".qh > b")), summary: T(q.querySelector(".qfl > summary")),
      flights: [...q.querySelectorAll(".qlist > span")].map(s => (s.classList.contains("dim") ? "~" : "") + T(s) + (s.querySelector(".capl.low") ? "{low}" : "")) }));
    const lines = [...c.querySelectorAll(".gc")].map(g => ({ text: T(g), pills: [...g.querySelectorAll(".pill")].map(cls), buttons: [...g.querySelectorAll("button")].map(T) }));
    c.querySelectorAll("table, .ck, .qcard, .gc").forEach(e => e.remove());
    out.boards[h.dataset.rkey] = { head: T(h), folded: b.classList.contains("rcol"), sizes, tables, bars, cards, qcards, lines, rest: T(c),
      pills: [...c.querySelectorAll(".pill")].map(p => cls(p) + "|" + T(p)) };
  }
  return out;
}"""
READ_MODAL = r"""() => {
  const m = document.querySelector(".modal");
  if (!m) return null;
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const cls = e => [...e.classList].sort().join(" ");
  const cell = c => T(c) + [...c.querySelectorAll(".pill")].map(p => "{" + cls(p) + "}").join("");
  const t = m.querySelector(".mbody table");
  return { head: T(m.querySelector(".mhead > div")), table: t ? [...t.querySelectorAll("tr")].map(tr => [...tr.children].map(cell)) : null,
    imp: T(m.querySelector(".imp > b")),
    cands: [...m.querySelectorAll(".impr")].map(r => ({ text: T(r.querySelector(":scope > span")), opts: [...r.querySelectorAll("select option")].map(T),
      button: T(r.querySelector("button")) })),
    empty: T(m.querySelector(".mbody .empty")), foot: [...m.querySelectorAll(".mfoot button")].map(T) };
}"""
OLD_ROOT, NEW_ROOT = "#view", "main[data-screen=check]"


# ---------- the two planners
async def answer_game(r, answers):
    """/api/game-schedule?u=<the airline's game link>: the answer set for its game ID, else the game's 502."""
    u = parse_qs(urlsplit(r.request.url).query).get("u", [""])[0]
    m = re.search(r"enterprises/(\d+)", u) or re.match(r"^(\d+)$", u)
    body = (answers or {}).get(m[1]) if m else None
    if body is None:
        await r.fulfill(status=502, body=json.dumps({"error": "The game answered 502."}), content_type="application/json")
    else:
        await r.fulfill(body=json.dumps(body), content_type="application/json")


class OldCheck(rs.Planner):
    """The old planner (real_saves_test.py's), its clock frozen at the moment before its scripts run, with the hook."""

    def __init__(self, *a, moment, **k):
        super().__init__(*a, **k)
        self.moment = moment
        self.answers = {}

    async def page(self, host=LIVE_HOST):
        self.pg = pg = await self.ctx.new_page()
        await pg.clock.set_fixed_time(self.moment)
        await pg.emulate_media(reduced_motion="reduce")
        pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
        pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
              if m.type == "error" and "Failed to load resource" not in m.text else None)
        pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await pg.route("**/api/game-schedule*", lambda r: answer_game(r, self.answers))
        await pg.goto(f"http://{host}:{self.port}/planner/")
        return pg

    async def ready(self):
        await self.pg.wait_for_function("() => window.__eqOld && window.__eqOld('CAP.at') > 0", timeout=60000)

    async def run(self, js):
        return await self.pg.evaluate("s => window.__eqOld(s)", js)

    async def check(self, expand=True):
        """The old Check (its review view), every board open."""
        await self.run("Object.assign(ui, {view: 'review', modal: null}); render(); true")
        await settle(self.pg, 200)
        if expand:
            await self.pg.click("#rev-expall")
            await settle(self.pg, 150)

    async def reopen(self):
        await self.pg.close()
        await self.page()
        await self.pg.wait_for_function("() => window.__eqDataLoaded === true", timeout=60000)
        await self.ready()

    async def game(self):
        await self.pg.click("#gcheck")
        await self.pg.wait_for_function("() => window.__eqOld('!gameCheck.running && !!gameCheck.at')", timeout=60000)
        await settle(self.pg, 150)


class NewCheck(pn.Planner):
    """The new planner (planner_next_test.py's), with /api/game-schedule answered by the test."""

    answers = None

    async def open(self, *a, **k):
        pg = await super().open(*a, **k)
        await pg.route("**/api/game-schedule*", lambda r: answer_game(r, self.answers))
        return pg


async def new_check(pl, day=None, expand=True):
    """The new Check at its address, once it has read everything; every board open."""
    to = "/check" + (f"?day={day}" if day else "")
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", to)
    await pl.pg.wait_for_function("""want => { const m = document.querySelector('main[data-screen=check]');
        return !!m && m.dataset.checkReady === 'yes' && decodeURIComponent(m.dataset.checkView || '') === want; }""", arg=to, timeout=90000)
    await pl.pg.wait_for_function("() => !!window.EQ_LOGOS", timeout=20000)
    await settle(pl.pg, 300)
    if expand:
        await pl.pg.click("#rev-expall")
        await settle(pl.pg, 150)


async def new_game(pl):
    await pl.pg.click("#gcheck")
    await pl.pg.wait_for_function("() => /Last checked/.test((document.querySelector('[data-board=\"Game check\"] .toolbar .count') || {}).textContent || '')", timeout=60000)
    await settle(pl.pg, 200)


async def refresh(new):
    """The new planner loaded again (signed in already, its clock still frozen), so it reads the copy as it is now."""
    await new.pg.reload()
    await new.pg.wait_for_function("!!window.__eqPlanner", timeout=60000)
    await new.pg.wait_for_selector("main[data-screen]", timeout=60000)
    await settle(new.pg, 300)


# ---------- 3. folding
FOLDS = """(sel) => [...document.querySelectorAll(sel + ' .board')].filter(b => b.querySelector(':scope > h3.rch')).map(b => (b.classList.contains('rcol') ? '-' : '+') + b.querySelector(':scope > h3').dataset.rkey)"""


async def folding(old, new):
    p, seen = [], []
    await old.check(expand=False)
    await new_check(new, expand=False)
    for what, act in (("on arrival", None), ("after Expand all", "#rev-expall"), ("after a click on Cabins' title", "h3.rch[data-rkey=Cabins]"),
                      ("after Collapse all", "#rev-colall"), ("after Expand all again", "#rev-expall")):
        if act:
            await old.pg.click(f"{OLD_ROOT} {act}" if act.startswith("h3") else act)
            await new.pg.click(f"{NEW_ROOT} {act}" if act.startswith("h3") else act)
            await settle(old.pg, 150)
            await settle(new.pg, 150)
        o, n = await old.pg.evaluate(FOLDS, OLD_ROOT), await new.pg.evaluate(FOLDS, NEW_ROOT)
        seen.append(f"{what}: {' '.join(n)}")
        if o != n:
            p.append(f"{what}: old {o}, new {n}")
    return "the boards fold as the old ones: " + "; ".join(seen[:3]) + " …", p


# ---------- 4. the boards
def compare_tables(k, ot, nt):
    p = []
    if len(ot) != len(nt):
        return [f"{k}: old {len(ot)} tables, new {len(nt)}: old heads {[t[0] if t else [] for t in ot]}, new {[t[0] if t else [] for t in nt]}"]
    for a, b in zip(ot, nt):
        if a == b:
            continue
        head = a[0] if a else []
        if head[:3] == ["Hub", "Bank", "Cities flying"]:
            skip = COPY.get("no_mct", set())
            ra = [r for r in a[1:] if r[0] not in skip]
            rb = [r for r in b[1:] if r[0] not in skip]
            if len(ra) != len(a) - 1 or len(rb) != len(b) - 1:
                known("minimum connection time", f"hub readiness at {sorted({r[0] for r in a[1:] + b[1:] if r[0] in skip})}")
            if [r[:4] for r in ra] != [r[:4] for r in rb]:
                p.append(f"{k} hub readiness: old {[r[:4] for r in ra][:8]}, new {[r[:4] for r in rb][:8]}"[:900])
            elif [r[4:] for r in ra] != [r[4:] for r in rb] or head[4:] != (b[0] if b else [])[4:]:
                known("regions", f"{len(ra)} rows, e.g. old {ra[0][4] if ra else ''!r}, new {rb[0][4] if rb else ''!r}")
            continue
        if head[:2] == ["Due", "Aircraft"]:
            if len(a) == len(b) and all(x[0] == y[0] and sorted(x[1].split(", ")) == sorted(y[1].split(", ")) for x, y in zip(a, b)):
                known("order on a tie", f"checks coming up: {[x for x, y in zip(a, b) if x != y][:2]}")
                continue
        if head and head[-1] == "Add" and (b[0] if b else []) == head[:-1]:
            known("suggested size", f"{k}: the Add column of {len(a) - 1} routes ready, e.g. {[r[-1] for r in a[1:4]]}")
            a = [r[:-1] for r in a]
            if a == b:
                continue
        nh = b[0] if b else []
        if head[:1] == ["Airline"] and nh[:1] == ["Airline"] and head != nh and len(a) == len(b) and set(head[1:]) & set(nh[1:]) \
                and all("<th" not in c for c in head) and k == "Growth" and any("on order" in c or "empty" in c or "not in fleet" in c for r in a[1:] for c in r):
            both = [c for c in head[1:] if c in nh]
            pick = lambda t, h: [[r[0]] + [r[h.index(c)] for c in both] for r in t[1:]]
            if pick(a, head) == pick(b, nh):
                known("order queue families", f"old {head[1:]}, new {nh[1:]}")
                continue
            p.append(f"{k} order queues: old {pick(a, head)[:6]}, new {pick(b, nh)[:6]}"[:900])
            continue
        if len(a) != len(b):
            p.append(f"{k} table {head}: old {len(a)} rows, new {len(b)}")
        for x, y in zip(a, b):
            if x != y:
                p.append(f"{k} table {head[:3]}: old {x}, new {y}"[:900])
                break
    return p


def compare_board(k, o, n):
    if o is None or n is None:
        return [f"{k}: the {'old' if o is None else 'new'} board isn't there"]
    p = []
    for f in ("head", "folded", "bars", "rest", "pills", "lines"):
        if o[f] != n[f]:
            p.append(f"{k}: {f}: old {o[f]!r}, new {n[f]!r}"[:1200])
    if o["sizes"] and not n["sizes"]:
        known("suggested size", f"{k}: {len(o['sizes'])} options, e.g. {o['sizes'][:4]}")
    elif o["sizes"] != n["sizes"]:
        p.append(f"{k}: sizes: old {o['sizes']}, new {n['sizes']}")
    p += compare_tables(k, o["tables"], n["tables"])
    if len(o["cards"]) != len(n["cards"]):
        p.append(f"{k}: old {len(o['cards'])} checks due, new {len(n['cards'])}: old {[c['head'][:40] for c in o['cards']]}, new {[c['head'][:40] for c in n['cards']]}")
    for a, b in zip(o["cards"], n["cards"]):
        if a["head"] != b["head"] or a["note"] != b["note"]:
            p.append(f"{k}: the check: old {a['head']!r}, new {b['head']!r}"[:900])
        if a["pills"] != b["pills"]:
            if sorted(a["pills"]) == sorted(b["pills"]):
                known("load pill order", f"{a['head'][:12]}: old {a['pills']}, new {b['pills']}"[:300])
            else:
                p.append(f"{k}: {a['head'][:12]}'s pills: old {a['pills']}, new {b['pills']}"[:900])
    if o["qcards"] != n["qcards"]:
        if len(o["qcards"]) != len(n["qcards"]):
            p.append(f"{k}: old {len(o['qcards'])} airlines, new {len(n['qcards'])}")
        for a, b in zip(o["qcards"], n["qcards"]):
            for f in ("head", "logo", "name", "summary"):
                if a[f] != b[f]:
                    p.append(f"{k}: an airline's {f}: old {a[f]!r}, new {b[f]!r}")
            if a["flights"] != b["flights"]:
                diff = [(x, y) for x, y in zip(a["flights"], b["flights"]) if x != y][:3]
                p.append(f"{k}: {a['name'] or a['head'][:20]}'s flights: old {len(a['flights'])}, new {len(b['flights'])}; e.g. {diff}"[:900])
    return p


async def boards(old, new):
    await old.check()
    await new_check(new)
    o, n = await old.pg.evaluate(READ, OLD_ROOT), await new.pg.evaluate(READ, NEW_ROOT)
    p = []
    if o["title"] != n["title"] or o["tools"] != n["tools"]:
        p.append(f"the title and tools: old {o['title']!r} {o['tools']!r}, new {n['title']!r} {n['tools']!r}")
    if o["order"] != n["order"] or n["order"] != BOARDS:
        p.append(f"the boards: old {o['order']}, new {n['order']}")
    for k in BOARDS[:4]:
        p += compare_board(k, o["boards"].get(k), n["boards"].get(k))
    nb = n["boards"]
    g = nb.get("Growth") or {"tables": []}
    label = (f"every board equals the old Check's: Capture ({max(0, len((nb.get('Capture') or {'tables': [[]]})['tables'][0]) - 1)} airlines), Growth "
             f"({len(g['bars'])} main hubs, {len(g['tables'])} tables: the next move, the growth lists, the order queues, hub readiness), Aircraft checks "
             f"({len((nb.get('Aircraft checks') or {'cards': []})['cards'])} due), Cabins ({max(0, sum(len(t) - 1 for t in (nb.get('Cabins') or {'tables': []})['tables']))} rows)")
    return label, p, n


async def report_days(old, new):
    """The daily load report on each of the last REPORT_DAYS days, moved by the ‹ button in both."""
    p, days = [], []
    await old.check()
    await new_check(new)
    day = await new.pg.evaluate("document.querySelector('main[data-screen=check]').dataset.day")
    first = await old.run("ui.lfDate")
    if first != day:
        p.append(f"the report opens on {first} in the old planner, {day} in the new")
        await old.run(f"ui.lfDate = {json.dumps(day)}; render(); true")
        await settle(old.pg, 150)
    for i in range(REPORT_DAYS):
        if i:
            want = (date.fromisoformat(day) - timedelta(days=1)).isoformat()
            await old.pg.click(f"{OLD_ROOT} [data-lfday='-1']")
            await new.pg.click(f"{NEW_ROOT} [data-lfday='-1']")
            await settle(old.pg, 150)
            await new.pg.wait_for_function("""want => { const m = document.querySelector('main[data-screen=check]');
                return !!m && m.dataset.day === want && m.dataset.checkReady === 'yes'; }""", arg=want, timeout=60000)
            await settle(new.pg, 200)
            day = want
            if (got := await old.run("ui.lfDate")) != day:
                p.append(f"the old planner moved to {got}, the new to {day}")
        o = (await old.pg.evaluate(READ, OLD_ROOT))["boards"].get("Daily load report")
        n = (await new.pg.evaluate(READ, NEW_ROOT))["boards"].get("Daily load report")
        days.append(f"{day} ({sum(len(q['flights']) for q in (n or {'qcards': []})['qcards'])} departures)")
        p += [f"{day}: {x}" for x in compare_board("Daily load report", o, n)]
    path = await new.pg.evaluate("location.pathname + location.search")
    if f"day={day}" not in path:
        p.append(f"the report's day isn't in the address ({path})")
    return f"the daily load report equals the old one on each of the last {REPORT_DAYS} days: " + ", ".join(days), p


# ---------- 5. the game check
def shift(hhmm, m):
    if not hhmm:
        return hhmm
    h, mm = (int(x) for x in hhmm.split(":"))
    t = (h * 60 + mm + m) % 1440
    return f"{t // 60:02d}:{t % 60:02d}"


def game_answers(planner, links):
    """The game's answer for each airline with a link: {game id: answer}, the tweaks made to one airline, and the airline whose
    answer is a 502. planner: {airline: {number: [entries]}} as the old plannerFlights gives them."""
    sample = json.loads((FIX / "schedule_113.expected.json").read_text())
    ids = {al: (re.search(r"enterprises/(\d+)", l or "") or [None, None])[1] for al, l in links.items() if l}
    out, tweak, err = {}, None, None
    order = [a for a in COPY["airlines"] if a["name"] in ids]
    plain = [a for a in order if ids[a["name"]] != sample.get("id")]
    if plain:
        err = plain[-1]
    for a in order:
        al, gid = a["name"], ids[a["name"]]
        if gid == sample.get("id"):
            out[gid] = sample
            continue
        if err and a["id"] == err["id"]:
            continue
        flights = []
        for no, entries in sorted((planner.get(al) or {}).items(), key=lambda x: int(x[0]) if x[0].isdigit() else 0):
            for e in entries:
                flights.append({"code": a["code"] or "XX", "no": str(no), "from": e["from"], "to": e["to"], "days": e["days"], "dep": e["dep"], "arr": e["arr"], "type": "32N", "valid": ""})
        if tweak is None and a["id"] in COPY["unflown"]:
            single = [no for no, e in sorted((planner.get(al) or {}).items(), key=lambda x: int(x[0]) if x[0].isdigit() else 0) if len(e) == 1 and e[0]["dep"] and e[0]["arr"]]
            if len(single) >= 4:
                t0, t1, t2, t3 = single[:4]
                for f in flights:
                    if f["no"] == t0:
                        f["dep"], f["arr"] = shift(f["dep"], 10), shift(f["arr"], 10)
                    elif f["no"] == t1:   # one day fewer (the last), or another day when it flies one
                        f["days"] = f["days"][:-1] if len(f["days"]) > 1 else ("2" if f["days"] == "1" else "1")
                flights = [f for f in flights if f["no"] != t2]
                v = next(f for f in flights if f["no"] == t3)
                flights.append(dict(v, dep=shift(v["dep"], 60), arr=shift(v["arr"], 60), days="6", valid="from 20.10."))
                r = COPY["unflown"][a["id"]]
                top = max(int(n) for n in (planner.get(al) or {}) if n.isdigit())
                n1 = top + 101 + (top + 101) % 2   # an even number, its return one above
                arr = shift("10:00", 120 + r["od"] - r["oh"])
                back = shift(arr, 90)
                flights += [{"code": a["code"] or "XX", "no": str(n1), "from": r["hub"], "to": r["dest"], "days": "1234567", "dep": "10:00", "arr": arr, "type": "32N", "valid": ""},
                            {"code": a["code"] or "XX", "no": str(n1 + 1), "from": r["dest"], "to": r["hub"], "days": "1234567", "dep": back, "arr": shift(back, 120 + r["oh"] - r["od"]),
                             "type": "32N", "valid": ""}]
                tweak = {"airline": a, "time": t0, "days": t1, "gone": t2, "valid": t3, "pair": (str(n1), str(n1 + 1)), "route": r}
        out[gid] = {"id": gid, "airline": al, "flights": flights}
    return out, tweak, err


async def game_check(old, new):
    """Runs the check in both and compares each airline's line and its pop-up."""
    p = []
    await old.check()
    await old.game()
    await new_check(new)
    await new_game(new)
    o, n = await old.pg.evaluate(READ, OLD_ROOT), await new.pg.evaluate(READ, NEW_ROOT)
    p += compare_board("Game check", o["boards"].get("Game check"), n["boards"].get("Game check"))
    modals = 0
    for a in COPY["airlines"]:
        if not await old.pg.evaluate("s => !!document.querySelector(s)", f"[data-gcopen={json.dumps(a['name'])}]"):
            if await new.pg.evaluate("s => !!document.querySelector(s)", f"[data-gcopen={json.dumps(a['code'] or '')}]"):
                p.append(f"{a['code']}: the new line offers a review, the old doesn't")
            continue
        await old.pg.click(f"[data-gcopen={json.dumps(a['name'])}]")
        await new.pg.click(f"[data-gcopen={json.dumps(a['code'] or '')}]")
        await old.pg.wait_for_selector(".modal", timeout=10000)
        await new.pg.wait_for_selector("[data-gc-modal] .modal", timeout=10000)
        await settle(old.pg, 100)
        mo, mn = await old.pg.evaluate(READ_MODAL), await new.pg.evaluate(READ_MODAL)
        modals += 1
        for f in ("head", "table", "imp", "cands", "empty", "foot"):
            if (mo or {}).get(f) != (mn or {}).get(f):
                p.append(f"{a['code']}'s pop-up: {f}: old {(mo or {}).get(f)!r}, new {(mn or {}).get(f)!r}"[:1200])
        await old.pg.click(".modal .mx")
        await new.pg.click(".modal .mx")
        await settle(old.pg, 100)
        await settle(new.pg, 100)
    lines = (n["boards"].get("Game check") or {"lines": []})["lines"]
    return (f"the game check equals the old one: {len(lines)} airlines' lines ("
            + "; ".join(x["text"][:70] for x in lines) + f") and {modals} pop-ups with their differences and flights to add"), p


def legs_of(airline_id):
    return json.loads(psql(f"""select coalesce(json_agg(to_jsonb(l) - 'updated_at' order by l.id), '[]') from public.flight_legs l
                               where l.airline_id = {int(airline_id)}""").strip())


def fleet_of(airline_id):
    return json.loads(psql(f"""select coalesce(json_agg(to_jsonb(a) - 'updated_at' order by a.id), '[]') from public.aircraft a
                               where a.airline_id = {int(airline_id)}""").strip())


def restore_fleet(snap):
    psql("""begin;
      select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'check_side_by_side_test', true);
      update public.aircraft x set status = s.status, base_code = s.base_code, cabin_config_id = s.cabin_config_id, extra = s.extra, retired_on = s.retired_on,
             checked_on = s.checked_on, schedule_changed_on = s.schedule_changed_on, maintenance_note = s.maintenance_note
        from jsonb_populate_recordset(null::public.aircraft, :'a'::jsonb) s where x.id = s.id
         and (x.status, x.base_code, x.cabin_config_id, x.extra, x.retired_on, x.checked_on, x.schedule_changed_on, x.maintenance_note)
             is distinct from (s.status, s.base_code, s.cabin_config_id, s.extra, s.retired_on, s.checked_on, s.schedule_changed_on, s.maintenance_note);
      commit;""", a=json.dumps(snap))


def restore_legs(snap):
    psql("""begin;
      select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'check_side_by_side_test', true);
      update public.flight_legs x set dep_utc_min = s.dep_utc_min, block_min = s.block_min, days_utc = s.days_utc, flight_no = s.flight_no, aircraft_id = s.aircraft_id
        from jsonb_populate_recordset(null::public.flight_legs, :'l'::jsonb) s where x.id = s.id
         and (x.dep_utc_min, x.block_min, x.days_utc, x.flight_no, x.aircraft_id) is distinct from (s.dep_utc_min, s.block_min, s.days_utc, s.flight_no, s.aircraft_id);
      commit;""", l=json.dumps(snap))


def max_ids():
    return json.loads(psql("""select json_build_object('rotations', coalesce((select max(id) from public.rotations), 0),
        'flight_legs', coalesce((select max(id) from public.flight_legs), 0), 'routes', coalesce((select max(id) from public.routes), 0),
        'aircraft', coalesce((select max(id) from public.aircraft), 0))""").strip())


def made_since(ids):
    drop = ("id", "created_at", "updated_at")
    d = json.loads(psql(f"""select json_build_object(
        'rotations', (select coalesce(jsonb_agg(to_jsonb(r) order by r.id), '[]') from public.rotations r where r.id > {int(ids['rotations'])}),
        'legs', (select coalesce(jsonb_agg(to_jsonb(l) order by l.rotation_id, l.leg_no), '[]') from public.flight_legs l where l.id > {int(ids['flight_legs'])}),
        'routes', (select coalesce(jsonb_agg(to_jsonb(r) order by r.id), '[]') from public.routes r where r.id > {int(ids['routes'])}))""").strip())
    for r in d["rotations"]:
        r["legacy_key"] = (r.get("legacy_key") or "")[:-3]
    for k in d:
        d[k] = [{c: v for c, v in r.items() if c not in drop + ("rotation_id", "route_id" if k == "routes" else "")} for r in d[k]]
    return d


def drop_since(ids):
    psql(f"""begin;
      select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'check_side_by_side_test', true);
      delete from public.flight_legs where id > {int(ids['flight_legs'])} or rotation_id > {int(ids['rotations'])};
      delete from public.rotations where id > {int(ids['rotations'])};
      delete from public.routes where id > {int(ids['routes'])};
      commit;""")


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


async def game_saves(old, new, tw):
    """Fix one, fix all and add a flight: the new planner first, the copy put back, then the old planner the same way; both
    must write the same rows."""
    out = []
    a = tw["airline"]
    for what in ("fix one", "fix all", "add a flight"):
        problems = []
        snap, fleet = legs_of(a["id"]), fleet_of(a["id"])
        # the new planner
        await refresh(new)
        await new_check(new)
        await new_game(new)
        client = await new.pg.evaluate("window.__eqPlanner.client")
        ids, mark = max_ids(), marks()
        code = a["code"] or ""
        if what == "fix all":
            await new.pg.click(f"[data-board='Game check'] [data-gcfixall={json.dumps(code)}]")
        else:
            await new.pg.click(f"[data-gcopen={json.dumps(code)}]")
            await new.pg.wait_for_selector("[data-gc-modal] .modal", timeout=10000)
            if what == "fix one":
                k = await new.pg.evaluate("no => [...document.querySelectorAll('.modal table tr')].slice(1).findIndex(tr => (tr.children[0] || {}).textContent.trim() === no)", tw["time"])
                await new.pg.click(f"[data-gcfix={json.dumps(code + '|' + str(k))}]")
            else:
                k = await new.pg.evaluate("no => [...document.querySelectorAll('.modal .impr')].findIndex(r => r.querySelector('b').textContent.trim() === no)", tw["pair"][0])
                await new.pg.click(f"[data-imp={json.dumps(code + '|' + str(k))}]")
        await rs.wait_for(lambda: log_since(mark), lambda got: len(got) >= 1, seconds=60)
        await until_quiet()
        await new.pg.wait_for_function("() => /^(saved)$/.test((document.querySelector('[data-save-state]') || {}).textContent || '')", timeout=30000)
        new_log = log_since(mark)
        n_legs, n_made, n_fleet = legs_of(a["id"]), made_since(ids), fleet_of(a["id"])
        problems += [f"a change-log row names {r['actor']} ({r['detail']}), not planner (the tab's ID)" for r in new_log if r["actor"] != "planner" or r["detail"] != client]
        drop_since(ids)
        restore_legs(snap)
        restore_fleet(fleet)
        # the old planner, on the copy as it was
        await old.reopen()
        await old.check()
        await old.game()
        ids2, mark2 = max_ids(), marks()
        if what == "fix all":
            await old.pg.click(f"{OLD_ROOT} [data-gcfixall={json.dumps(a['name'])}]")
        else:
            await old.pg.click(f"[data-gcopen={json.dumps(a['name'])}]")
            await old.pg.wait_for_selector(".modal", timeout=10000)
            if what == "fix one":
                k = await old.pg.evaluate("no => [...document.querySelectorAll('.modal table tr')].slice(1).findIndex(tr => (tr.children[0] || {}).textContent.trim() === no)", tw["time"])
                await old.pg.click(f"[data-gcfix={json.dumps(a['name'] + '|' + str(k))}]")
            else:
                k = await old.pg.evaluate("no => [...document.querySelectorAll('.modal .impr')].findIndex(r => r.querySelector('b').textContent.trim() === no)", tw["pair"][0])
                await old.pg.click(f"[data-imp={json.dumps(a['name'] + '|' + str(k))}]")
        await rs.wait_for(lambda: log_since(mark2), lambda got: len(got) >= 1, seconds=60)
        await until_quiet()
        old_log = log_since(mark2)
        o_legs, o_made, o_fleet = legs_of(a["id"]), made_since(ids2), fleet_of(a["id"])
        drop_since(ids2)
        restore_legs(snap)
        restore_fleet(fleet)
        if n_fleet != o_fleet:
            diff = [(x["registration"], {c: (x[c], y.get(c)) for c in x if x[c] != y.get(c)}) for x, y in zip(n_fleet, o_fleet) if x != y][:4]
            problems.append(f"the aircraft after the new planner's {what} differ from the old's: (aircraft, column: new, old) {diff}"[:900])
        changed = [x["id"] for x, y in zip(n_legs, snap) if x != y]
        if n_legs != o_legs:
            diff = [(x["id"], {c: (x[c], y.get(c)) for c in x if x[c] != y.get(c)}) for x, y in zip(n_legs, o_legs) if x != y][:4]
            problems.append(f"the legs after the new planner's {what} differ from the old's: (leg, column: new, old) {diff}"[:900])
        if n_made != o_made:
            problems.append(f"the rows added: new {n_made}, old {o_made}"[:900])
        nk, ok_ = kinds(new_log), kinds(old_log)
        if nk != ok_:
            problems.append(f"the new {what} changed {dict(nk)}, the old {dict(ok_)}")
        if what != "add a flight" and not changed:
            problems.append("the new planner changed no leg")
        if what == "add a flight" and len(n_made["rotations"]) != 1:
            problems.append(f"the new planner added {len(n_made['rotations'])} rotations, not 1")
        out.append((f"{what} from the game ({a['code']}: " + (f"flight {tw['time']}'s times" if what == "fix one" else "every time and day change" if what == "fix all"
                    else f"{tw['pair'][0]}/{tw['pair'][1]} {tw['route']['hub']}–{tw['route']['dest']} on its first aircraft") + f"): {dict(nk)}, the same rows as the old "
                    "planner's for the same action, logged as planner with the tab's ID; the copy put back after each", problems))
    return out


# ---------- 6. the new Check's own saves
async def wait_saved(pl, mark, rows=1):
    await rs.wait_for(lambda: log_since(mark), lambda got: len(got) >= rows, seconds=30)
    await settle(pl.pg, 300)
    await pl.pg.wait_for_function("() => /^(saved|preview · not saved)$/.test((document.querySelector('[data-save-state]') || {}).textContent || '')", timeout=30000)
    await pl.pg.wait_for_function("() => (document.querySelector('main[data-screen=check]') || {dataset: {}}).dataset.checkReady === 'yes'", timeout=60000)
    await settle(pl.pg, 400)


def logged(mark, want, client):
    rows = log_since(mark)
    got = kinds(rows)
    problems = [] if got == want else [f"the tables changed by {dict(got)}, expected {dict(want)}"]
    problems += [f"a change-log row names {r['actor']} ({r['detail']}), not planner (the tab's ID)" for r in rows if r["actor"] != "planner" or r["detail"] != client]
    return problems, rows


def aircraft_row(aid):
    return json.loads(psql(f"select coalesce((select to_jsonb(a) from public.aircraft a where a.id = {int(aid)}), 'null')").strip())


async def own_saves(old, new, today):
    out = []
    await refresh(new)
    await new_check(new)
    client = await new.pg.evaluate("window.__eqPlanner.client")
    pg = new.pg

    # Mark checked: an aircraft due its check (one made due for the test when none is, and put back after)
    due = await pg.evaluate("[...document.querySelectorAll('[data-checked]')].map(b => b.dataset.checked)")
    made = None
    if not due:
        # an aircraft in the old list of tails whose rotations were all launched more than a week ago: with no check and no
        # schedule change since, its check is due
        pick = json.loads(psql(f"""select coalesce((select json_build_object('id', a.id, 'reg', a.registration, 'checked', a.checked_on, 'changed', a.schedule_changed_on)
            from public.aircraft a where a.world_id = {WORLD} and a.status = 'active' and a.extra ? 'tails_index'
             and exists (select 1 from public.flight_legs l join public.rotations r on r.id = l.rotation_id where l.aircraft_id = a.id and r.launched_on is not null)
             and not exists (select 1 from public.flight_legs l join public.rotations r on r.id = l.rotation_id where l.aircraft_id = a.id and r.launched_on > :'t'::date - 8)
             order by a.id limit 1)::text, 'null')""", t=today).strip())
        if pick:
            psql(f"""begin; select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'check_side_by_side_test', true);
                update public.aircraft set checked_on = null, schedule_changed_on = null where id = {int(pick['id'])}; commit;""")
            made = pick
            await refresh(new)
            await new_check(new)
            due = await pg.evaluate("[...document.querySelectorAll('[data-checked]')].map(b => b.dataset.checked)")
    if due:
        reg = due[0]
        aid = int(psql("select id from public.aircraft where registration = :'r' and world_id = " + WORLD, r=reg).strip())
        before = aircraft_row(aid)
        mark = marks()
        await pg.click(f"[data-checked={json.dumps(reg)}]")
        await wait_saved(new, mark)
        problems, rows = logged(mark, Counter({("aircraft", "update"): 1}), client)
        if rows and set(rows[0]["fields"]) - {"checked_on", "updated_at"}:
            problems.append(f"the update changed {rows[0]['fields']}, not just checked_on")
        if (aircraft_row(aid) or {}).get("checked_on") != today:
            problems.append("the aircraft isn't checked today")
        if await pg.evaluate("s => !!document.querySelector(s)", f"[data-checked={json.dumps(reg)}]"):
            problems.append("the check is still listed as due")
        await old.reopen()
        shown = await old.run(f"(state.tails.find(t => t.id === {json.dumps(reg)}) || {{}}).checkedOn || null")
        if shown != today:
            problems.append(f"the old planner, opened again, shows it checked on {shown!r}")
        psql(f"""begin; select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'check_side_by_side_test', true);
            update public.aircraft set checked_on = nullif(:'c', '')::date, schedule_changed_on = nullif(:'s', '')::date where id = {aid}; commit;""",
             c=(made or before)["checked" if made else "checked_on"] or "", s=(made or before)["changed" if made else "schedule_changed_on"] or "")
        out.append((f"Mark checked ({reg}{', made due for the test' if made else ''}): one update of its checked_on, logged as planner with the tab's ID; the old "
                    "planner, opened again, shows it checked today", problems))
    else:
        out.append(("Mark checked", ["no aircraft with a launched rotation to check on the copy"]))

    # Refitted to, Keep as is and Show again, on the cabins listed
    await refresh(new)
    await new_check(new)
    refit = await pg.evaluate("(document.querySelector('[data-refit]') || {dataset: {}}).dataset.refit || ''")
    if refit:
        reg, code = refit.split("|", 1)
        aid = int(psql("select id from public.aircraft where registration = :'r' and world_id = " + WORLD, r=reg).strip())
        before, mark = aircraft_row(aid), marks()
        spent = int(psql("select coalesce(max(id), 0) from public.spending_log").strip())
        await pg.click(f"[data-refit={json.dumps(refit)}]")
        await wait_saved(new, mark, rows=2)
        problems, rows = logged(mark, Counter({("aircraft", "update"): 1, ("spending_log", "insert"): 1}), client)
        row = json.loads(psql(f"select coalesce((select to_jsonb(s) from public.spending_log s where s.id > {spent} order by s.id limit 1), 'null')").strip()) or {}
        cfg = psql("select code from public.cabin_configs where id = (select cabin_config_id from public.aircraft where id = %d)" % aid).strip()
        if cfg != code:
            problems.append(f"the aircraft's cabin is {cfg!r}, not {code!r}")
        if (row.get("kind"), float(row.get("amount") or 0), row.get("note"), row.get("spent_on"), row.get("aircraft_id")) != ("loss", 200000.0, f"cabin refit {reg} → {code}", today, None):
            problems.append(f"the money spent: {row.get('kind')} {row.get('amount')} {row.get('note')!r} on {row.get('spent_on')}, aircraft {row.get('aircraft_id')}")
        await old.reopen()
        o = json.loads(await old.run(f"""JSON.stringify({{ config: (state.tails.find(t => t.id === {json.dumps(reg)}) || {{}}).config || null,
            capex: (state.capex || []).filter(c => c.note === {json.dumps(f'cabin refit {reg} → {code}')}) }})"""))
        if o["config"] != code or [(c.get("date"), c.get("amountM"), c.get("kind")) for c in o["capex"]] != [(today, 0.2, "loss")]:
            problems.append(f"the old planner, opened again, shows the cabin {o['config']!r} and the money spent {o['capex']}")
        psql(f"""begin; select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'check_side_by_side_test', true);
            update public.aircraft set cabin_config_id = {before['cabin_config_id'] if before.get('cabin_config_id') is not None else 'null'} where id = {aid};
            delete from public.spending_log where id > {spent}; commit;""")
        out.append((f"Refitted to ({reg} → {code}): the aircraft's cabin and the refit's 0.2M loss (spending_log, as the old planner's capex entry), one action "
                    "logged as planner with the tab's ID; the old planner, opened again, shows both", problems))
    else:
        out.append(("Refitted to: no aircraft on the copy whose cabin differs from its markets' with a layout to refit to", []))

    await refresh(new)
    await new_check(new)
    keep = await pg.evaluate("(document.querySelector('[data-cabkeep]') || {dataset: {}}).dataset.cabkeep || ''")
    if keep:
        reg, cabin = keep.split("|", 1)
        mark = marks()
        await pg.click(f"[data-cabkeep={json.dumps(keep)}]")
        await wait_saved(new, mark)
        problems, _ = logged(mark, Counter({("aircraft_cabin_keeps", "insert"): 1}), client)
        if await pg.evaluate("s => !!document.querySelector(s)", f"[data-cabkeep={json.dumps(keep)}]"):
            problems.append("it's still listed to decide")
        await old.reopen()
        shown = json.loads(await old.run(f"JSON.stringify((state.cabinKeep || {{}})[{json.dumps(keep)}] || null)"))
        if (shown or {}).get("date") != today:
            problems.append(f"the old planner, opened again, shows the keep as {shown}")
        out.append((f"Keep as is ({reg}, {cabin}): one aircraft_cabin_keeps row, logged as planner with the tab's ID; the old planner, opened again, keeps it "
                    "as is from today", problems))
        mark = marks()
        await pg.evaluate("document.querySelector('[data-board=Cabins] details.gsub').open = true")
        await pg.click(f"[data-cabundo={json.dumps(keep)}]")
        await wait_saved(new, mark)
        problems, _ = logged(mark, Counter({("aircraft_cabin_keeps", "delete"): 1}), client)
        if not await pg.evaluate("s => !!document.querySelector(s)", f"[data-cabkeep={json.dumps(keep)}]"):
            problems.append("it isn't listed to decide again")
        await old.reopen()
        if json.loads(await old.run(f"JSON.stringify((state.cabinKeep || {{}})[{json.dumps(keep)}] || null)")):
            problems.append("the old planner, opened again, still keeps it as is")
        out.append((f"Show again ({reg}): its keep deleted, logged as planner with the tab's ID; the old planner, opened again, lists it to decide", problems))
    else:
        out.append(("Keep as is and Show again: no aircraft on the copy to keep as is", []))

    # an order logged under the rotation
    await refresh(new)
    await new_check(new)
    a = COPY["airlines"][0]
    mark = marks()
    await pg.click(f"[data-gmove={json.dumps((a['code'] or '') + '|freq')}]")
    await wait_saved(new, mark)
    problems, rows = logged(mark, Counter({("growth_log", "insert"): 1}), client)
    await old.reopen()
    lm = json.loads(await old.run(f"JSON.stringify(lastMove({json.dumps(a['name'])}))"))
    if not lm or (lm.get("move"), lm.get("date"), lm.get("note")) != ("freq", today, "logged in the planner"):
        problems.append(f"the old planner, opened again, shows the last move {lm}")
    if rows:
        psql(f"""begin; select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'check_side_by_side_test', true);
            delete from public.growth_log where id = {int(rows[0]['id'])}; commit;""")
    out.append((f"log an order ({a['code']} as Frequency): one growth_log row, logged as planner with the tab's ID; the old planner, opened again, shows it as "
                "the last move (the row taken out again after)", problems))
    return out


# ---------- 7. a preview, 8. a phone and the screenshots
async def preview(p, port, env, facts, staff, moment, seen):
    pv = NewCheck(p, port, env, facts)
    seen.append(pv)
    problems = []
    try:
        await pv.open(host="127.0.0.1", moment=moment)
        await pv.pg.emulate_media(reduced_motion="reduce")
        await pv.sign_in(*staff)
        n0, mark = counts(), marks()
        await new_check(pv)
        clicked = []
        for sel in ("[data-checked]", "[data-cabkeep]", "[data-gmove]"):
            if await pv.pg.evaluate("s => !!document.querySelector(s)", sel):
                await pv.pg.click(sel)
                clicked.append(sel)
                await settle(pv.pg, 600)
        state = await pv.pg.evaluate("(document.querySelector('[data-save-state]') || {}).textContent")
        if clicked and state != "preview · not saved":
            problems.append(f"the header says {state!r}, not \"preview · not saved\"")
        if "planner_save" in pv.rpcs:
            problems.append("the preview sent planner_save() to the copy")
        if log_since(mark):
            problems.append("the tables changed")
        problems += count_changes(n0, counts()) + pv.errors
    finally:
        await pv.close()
    return (f"a preview address (127.0.0.1) shows Check, and {', '.join(clicked) or 'nothing'} there send no write "
            f"(it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})"), problems


async def phone(p, port, env, facts, staff, moment, seen, answers):
    ph = NewCheck(p, port, env, facts, width=380, height=800)
    ph.answers = answers
    seen.append(ph)
    problems = []
    scroll = "Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth"
    try:
        await ph.open(moment=moment)
        await ph.pg.emulate_media(reduced_motion="reduce")
        await ph.sign_in(*staff)
        await new_check(ph)
        await new_game(ph)
        if (over := await ph.pg.evaluate(scroll)) > 0:
            wide = await ph.pg.evaluate("""() => [...document.querySelectorAll('main[data-screen=check] *')].filter(e => e.getBoundingClientRect().right > window.innerWidth + 1
                && !e.closest('.tblwrap, .tscroll')).slice(0, 4).map(e => e.tagName + '.' + [...e.classList].join('.'))""")
            problems.append(f"Check, every board open, scrolls sideways by {over} px at 380 px wide (too wide: {wide})")
        opener = await ph.pg.evaluate("(document.querySelector('[data-gcopen]') || {dataset: {}}).dataset.gcopen || ''")
        if opener:
            await ph.pg.click(f"[data-gcopen={json.dumps(opener)}]")
            await ph.pg.wait_for_selector("[data-gc-modal] .modal", timeout=10000)
            if (over := await ph.pg.evaluate(scroll)) > 0:
                problems.append(f"a game check's pop-up scrolls the page sideways by {over} px")
        problems += ph.errors
    finally:
        await ph.close()
    return "at 380 px wide Check, every board open, and a game check's pop-up have no sideways scroll and no errors; wide tables scroll in their own box", problems


async def screenshots(old, new):
    if not SCREENS_DIR:
        return
    Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    for width, height in ((1280, 900), (380, 800)):
        await old.pg.set_viewport_size({"width": width, "height": height})
        await new.pg.set_viewport_size({"width": width, "height": height})
        await old.check()
        await settle(old.pg, 400)
        await old.pg.screenshot(path=str(Path(SCREENS_DIR) / f"old-check-{width}.png"), full_page=True, timeout=90000)
        await new_check(new)
        await settle(new.pg, 400)
        await new.pg.screenshot(path=str(Path(SCREENS_DIR) / f"check-{width}.png"), full_page=True, timeout=90000)
    await old.pg.set_viewport_size({"width": 1440, "height": 1000})
    await new.pg.set_viewport_size({"width": 1280, "height": 900})


# ---------- what the copy holds
def read_copy():
    airlines = json.loads(psql(f"""select coalesce(json_agg(json_build_object('id', a.id, 'code', a.iata_code, 'game_id', a.game_id,
              'name', coalesce(a.planner_name, a.public_name, a.game_name, 'Airline ' || a.game_id)) order by a.position nulls last, a.id), '[]')
              from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id where g.kind = 'ours' and a.world_id = {WORLD}""").strip())
    # each airline's first route (by id) from one of its bases that isn't removed, one it doesn't fly yet first, with its two
    # airports' offsets in minutes: the game's round trip the planner hasn't got goes on it
    unflown = {}
    for r in json.loads(psql(f"""select coalesce(json_agg(x order by x.airline_id), '[]') from (
              select distinct on (r.airline_id) r.airline_id, r.hub_code as hub, r.dest_code as dest,
                     exists (select 1 from public.rotations ro where ro.route_id = r.id) as flown,
                     round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh, round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od
                from public.routes r
                join public.airports ah on ah.code = r.hub_code left join public.world_airports wh on wh.world_id = r.world_id and wh.airport_code = r.hub_code
                join public.airports ad on ad.code = r.dest_code left join public.world_airports wd on wd.world_id = r.world_id and wd.airport_code = r.dest_code
               where r.world_id = {WORLD} and not r.removed
                 and exists (select 1 from public.airline_bases b where b.airline_id = r.airline_id and b.airport_code = r.hub_code)
               order by r.airline_id, exists (select 1 from public.rotations ro where ro.route_id = r.id), r.id) x""").strip()):
        unflown[r["airline_id"]] = r
    no_mct = set(psql(f"""select b.airport_code from public.airline_bases b
              left join public.world_airports w on w.world_id = b.world_id and w.airport_code = b.airport_code
              where b.world_id = {WORLD} and w.mct_min is null""").split())
    COPY.update(airlines=airlines, unflown=unflown, no_mct=no_mct)
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
    try:
        held = set_aside(psql, moment)
        atexit.register(lambda: put_back_loads(psql, held))
        airlines = read_copy()
        problems = [] if airlines else ["the copy has none of our airlines"]
    except Exception as e:
        held, airlines, problems = {}, [], [why(e)]
    step(not problems, f"the moment: {moment} (the copy's latest capture plus one hour); typed loads and day flags entered after it set aside until the test "
         "ends (" + ", ".join(f"{t}: {len(json.loads(held.get(t) or '[]'))}" for t in HELD) + f"); the copy: {len(airlines)} of our airlines, "
         f"{len(COPY.get('no_mct', []))} bases with no minimum connection time of their own", problems)
    if problems:
        sys.exit(1)

    tag = secrets.token_hex(4)
    staff = (f"check-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="check-side-by-side-"))
    seen = []
    answers = {}
    try:
        root = web_copy(work)
        with serve(root) as port:
            async with async_playwright() as p:
                old = OldCheck(p, port, env, facts, lib_js, moment=moment)
                new = NewCheck(p, port, env, nfacts, width=1280, height=900)
                seen += [old, new]
                try:
                    n0, mark = counts(), marks()
                    await old.open()
                    await old.sign_in(*staff)
                    await old.ready()
                    await new.open(moment=moment)
                    await new.pg.emulate_media(reduced_motion="reduce")
                    await new.sign_in(*staff)
                    await new_check(new, expand=False)
                    problems = list(old.errors) + list(new.errors)
                    if log_since(mark):
                        problems.append("opening the planners changed the tables")
                    problems += count_changes(n0, counts())
                    if abs(await new.pg.evaluate("Date.now()") - ms(moment)) > 1000:
                        problems.append("the new planner's clock isn't frozen at the moment")
                    if await new.pg.evaluate("!!document.querySelector('main[data-screen=check] [data-not-built]')"):
                        problems.append("Check is still a placeholder")
                except Exception as e:
                    problems = [why(e)] + old.errors[:3] + new.errors[:3]
                step(not problems, "both planners opened at the moment, signed in as test staff, the new one on Check; opening them wrote nothing", problems)
                if problems:
                    sys.exit(1)

                for check in (folding,):
                    try:
                        label, problems = await check(old, new)
                    except Exception as e:
                        label, problems = check.__name__, [why(e)]
                    step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                t = time.monotonic()
                try:
                    label, problems, _ = await boards(old, new)
                except Exception as e:
                    label, problems = "every board", [why(e)]
                step(not problems, label + f" ({time.monotonic() - t:.0f} s)", problems + new.errors[:3] + old.errors[:3])
                t = time.monotonic()
                try:
                    label, problems = await report_days(old, new)
                except Exception as e:
                    label, problems = "the daily load report", [why(e)]
                step(not problems, label + f" ({time.monotonic() - t:.0f} s)", problems + new.errors[:3] + old.errors[:3])
                try:
                    await screenshots(old, new)
                except Exception as e:
                    print(f"      the screenshots: {why(e)}", flush=True)

                # ---------- 5. the game check
                tw = None
                try:
                    planner = json.loads(await old.run("JSON.stringify(Object.fromEntries(airlines().map(al => [al, plannerFlights(al)])))"))
                    links = json.loads(await old.run("JSON.stringify(state.ref.gameLinks || {})"))
                    answers, tw, err = game_answers(planner, links)
                    old.answers = new.answers = answers
                    label, problems = await game_check(old, new)
                    label += (f"; the game answering {len(answers)} airlines (" + ", ".join(sorted(str(k) for k in answers)) + f"), 502 for {err['code'] if err else 'none'}"
                              + (f", {tw['airline']['code']}'s with {tw['time']}'s times changed, {tw['days']}'s days, {tw['gone']} taken out, {tw['valid']} valid "
                                 f"only from a date added, and {tw['pair'][0]}/{tw['pair'][1]} on {tw['route']['hub']}–{tw['route']['dest']}"
                                 f" ({'a route it flies already' if tw['route']['flown'] else 'a route it does not fly yet'})" if tw else ""))
                    if not tw:
                        problems.append("no airline with four flights and a route from one of its bases, to put differences into")
                except Exception as e:
                    label, problems = "the game check", [why(e)]
                step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                if tw:
                    try:
                        for label, problems in await game_saves(old, new, tw):
                            step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                    except Exception as e:
                        step(False, "fix one, fix all and add a flight from the game", [why(e)] + new.errors[:3] + old.errors[:3])
                for k, v in KNOWN.items():
                    where = f" (e.g. {'; '.join(v['where'][:4])})" if v["where"] else ""
                    print(f"      known difference \"{k}\": used {v['used']} time(s){where}. {v['rule']}"[:1800], flush=True)

                # ---------- 6. the new Check's own saves
                try:
                    for label, problems in await own_saves(old, new, today):
                        step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                except Exception as e:
                    step(False, "Mark checked, Refitted to, Keep as is, Show again and logging an order in the new Check", [why(e)] + new.errors[:3] + old.errors[:3])
                await old.close()
                await new.close()

                # ---------- 7 and 8
                for check, args in ((preview, ()), (phone, (answers,))):
                    try:
                        label, problems = await check(p, port, env, nfacts, staff, moment, seen, *args)
                    except Exception as e:
                        label, problems = check.__name__, [why(e)]
                    step(not problems, label, problems)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    outside = sorted({h for x in seen for h in x.outside})
    stopped = ", ".join(sorted({h for x in seen for h in x.stopped})) or "nothing"
    step(not outside, f"nothing went outside ({sum(x.copy for x in seen)} requests answered by the copy, {sum(x.local for x in seen)} "
                      f"from the local server; stopped: {stopped})", ["reached: " + ", ".join(outside)] if outside else [])
    print(f"\n{len(failures)} Check side-by-side step(s) failed" if failures else "\nCheck side by side: all passed", flush=True)
    print(f"      the Check side by side took {time.monotonic() - started:.0f} s", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
