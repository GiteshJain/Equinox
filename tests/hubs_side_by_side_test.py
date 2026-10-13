"""The new planner's Hubs side by side with the old Hubs on the rehearsal's copy (decision #18, build pull request 8,
spec docs/specs/2026-10-13-hubs.md, "Checks"): the pull request's own new planner (built into web/app/) and the old
planner (web/planner/), both at their live addresses, signed in as the same test staff user, at the same frozen moment,
reading a full local copy of Supabase restored from last night's backup.

Run by database/rehearse.sh, last (after the Tails side by side). Like tests/tails_side_by_side_test.py it uses
tests/real_saves_test.py's helpers and request mapping, needs the copy, so it isn't part of tests/run_all.sh, and nothing
goes outside. Hubs only reads, so nothing here changes the copy.

1. The moment: the copy's latest capture plus one hour, as tests/captured_figures_test.py takes it (Hubs doesn't depend on
   it; the planners open at it as the other side-by-side tests do).
2. Both planners open at the moment (the old one from a copy of web/ with captured_figures_test.py's hook, so the test can
   set its screen's state; web/planner/ itself is unchanged). Opening them writes nothing.
3. For every base and focus city in the old Hubs' list, on every day (no sampling: 26 airports and 7 days took about two
   minutes on the copy of 13 Oct): the list of bases and the days, the count line (departures and arrivals that day,
   departures a week against the cap with "over cap", the next free pair and the last used), a focus city's note, the
   strip (every bank window and every tick: class, place, width, words), the hourly bars (every bar's height), the legend,
   the week grid (every cell's shade, bank window, departures and arrivals, the totals and the day marked), the flight
   list (every row with its bank pill) or its empty line, and the connections table (the heading with its city pairs, every
   row: the bank, the airports arriving and leaving, the city pairs, the examples; the note).
4. Its addresses: /planner/next/hubs opens the first base on Monday; /planner/next/hubs/<airport>?day=<0-6>, opened
   directly, reopens that board; the day buttons and the list of bases move the address.
5. A preview address (127.0.0.1) shows Hubs and sends no write.
6. At 380 px wide a hub and a focus city have no sideways scroll and no errors; the day strip and the week grid scroll
   inside their own box. Screenshots of a hub and a focus city, new and old, at 380 and 1280 px go to HUBS_SCREENS_DIR
   (the run's hubs-screens artifact).
7. Nothing went outside.

A difference fails and names the airport, the day and both values, unless it is a known difference (KNOWN below, each with
its rule), printed with how often it was used and examples. Prints airport codes, flight numbers, counts and the screens'
words, never anything else from the rows, since the log is posted on the pull request; never the local keys or the test
password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL, SECRET_TABLES and HUBS_SCREENS_DIR.
Usage: python3 tests/hubs_side_by_side_test.py
"""
import asyncio, json, os, re, secrets, shutil, sys, tempfile, time
from pathlib import Path
from harness import LIVE_HOST, serve, settle
from playwright.async_api import async_playwright
import real_saves_test as rs
from real_saves_test import count_changes, counts, is_planner_user, library, local_env, log_since, make_user, marks, planner_facts, psql, token_for, why
import planner_next_test as pn
from captured_figures_test import ms
from home_side_by_side_test import web_copy

SCREENS_DIR = os.environ.get("HUBS_SCREENS_DIR")
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
failures = []
started = time.monotonic()
COPY = {}

# Where the new Hubs follows its spec and the old Hubs did otherwise. Each is allowed only where its test says, and printed
# with how often it was used and examples.
KNOWN = {
    "regions": {
        "rule": "the old Hubs named the region of each airport arriving and leaving from a list of countries by region typed into "
                "its code (REGION_OF, regionOf). The list isn't in the database, so the new table counts the flights by the airport's "
                "country (airports.country_code), data the library has; the spec asks to say so rather than copy the list into the "
                "screen. Only the words after each count of airports in the connections table: the count of airports, and how many "
                "flights the words add up to, must be the same.",
        "used": 0, "where": []},
    "an airport two airlines share": {
        "rule": "the old list names a base once for each airline based there (ref.hubs); the new list names each airport once. Its "
                "board is the same either way (the old planner's hub(code): the first base there).",
        "used": 0, "where": []},
    "block estimates": {
        "rule": "a leg without a typed arrival takes the estimate: the old planner fitted its estimates to the times typed in "
                "(estBlockFor); the library uses 25 min + distance ÷ the type's speed (manual §4, #19 spec §5, as "
                "tests/rules_library_test.py allows). Only at an airport where a rotation with an estimated leg lands or leaves.",
        "used": 0, "where": []},
    "minimum connection time": {
        "rule": "manual §4: each airport's minimum connection time (world_airports.mct_min). The old planner gives a base with no "
                "figure no arrival windows and feeds no bank from it; the library uses 90 minutes where mct_min is empty (#19 spec §5, "
                "as tests/rules_library_test.py allows). Only at a base with no mct_min.",
        "used": 0, "where": []},
}


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:30]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


def known(name, where):
    if where in KNOWN[name]["where"]:
        return
    KNOWN[name]["used"] += 1
    KNOWN[name]["where"].append(where)


# ---------- reading either Hubs: the new one draws the old one's markup, so one reader serves both (root: the old #view,
# the new main[data-screen=hubs])
READ = r"""(sel) => {
  const R = document.querySelector(sel);
  if (!R) return null;
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const cls = e => [...e.classList].sort().join(" ");
  const st = (e, p) => e.style.getPropertyValue(p);
  const pill = c => { const p = c.querySelector(".pill"); return p ? "{" + cls(p) + "}" : ""; };
  const boards = [...R.querySelectorAll(".board")];
  const day = boards.find(b => b.querySelector(".strip"));
  const week = boards.find(b => b.querySelector("table.wg"));
  const conn = boards.find(b => { const h = b.querySelector("h3.rh"); return h && T(h).startsWith("Connections at "); });
  const focus = boards.find(b => b.classList.contains("note"));
  const flights = [...R.querySelectorAll("table.tbl")].find(t => { const th = t.querySelector("th"); return th && T(th) === "Time"; });
  const sel_ = R.querySelector(".toolbar select");
  const count = R.querySelector(".toolbar .count");
  return {
    title: T(R.querySelector(".vh h1")) + " | " + T(R.querySelector(".vh p")),
    options: sel_ ? [...sel_.options].map(o => o.value) : [],
    selected: sel_ ? sel_.value : "",
    days: [...R.querySelectorAll(".toolbar .seg button")].map(b => (b.classList.contains("on") ? "*" : "") + T(b)),
    count: T(count) + (count && count.querySelector(".pill") ? " " + pill(count) : ""),
    focus: focus ? T(focus) : "",
    wins: day ? [...day.querySelectorAll(".strip .win")].map(w => [cls(w), st(w, "left"), st(w, "width"), w.title, T(w)].join("~")) : null,
    ticks: day ? [...day.querySelectorAll(".strip .tick")].map(t => [cls(t), st(t, "left"), t.title].join("~")) : null,
    hours: day ? [...day.querySelectorAll(".hours .hr")].map(h => [...h.querySelectorAll(".bar")].map(b => cls(b) + ":" + st(b, "height")).join(",") + "|" + T(h.querySelector("span"))) : null,
    legend: day ? T(day.querySelector(".legend")) : null,
    weekHead: week ? T(week.querySelector(":scope > b")) + " | " + T(week.querySelector(":scope > .note")) : null,
    week: week ? [...week.querySelectorAll("table.wg tr")].map(tr => (tr.classList.contains("cur") ? "*" : "") + [...tr.children].map(c =>
      c.tagName === "TD" && !c.classList.contains("sum") ? [cls(c), st(c, "--k"), T(c.querySelector(".d")), T(c.querySelector(".a"))].join("/")
        : T(c) + (c.colSpan > 1 ? "@" + c.colSpan : "")).join(" ")) : null,
    flights: flights ? [...flights.querySelectorAll("tr")].map(tr => [...tr.children].map(c => T(c) + pill(c)).join(" | ")) : null,
    empty: T(R.querySelector(".empty")),
    conn: conn ? {
      head: T(conn.querySelector("h3.rh")), dim: T(conn.querySelector(":scope > .dim")), note: T(conn.querySelector(":scope > .note")),
      rows: [...conn.querySelectorAll("table.tbl tr")].map(tr => [...tr.children].map(c => ({
        t: T(c), first: T(c.firstChild), dim: T(c.querySelector(".dim")) }))),
    } : null,
  };
}"""
OLD_ROOT, NEW_ROOT = "#view", "main[data-screen=hubs]"

# The old Hubs' arrivals that name a bank they wait more than connection_max_wait_h for (waveAt's a.n with status late): the
# new list names them the same way (banks.bankOfArrival's next); counted here so the pull request can say how many.
OLD_LATE = r"""JSON.stringify((() => { let n = 0; const where = [];
  for (const f of state.freqs) { const c = M.computeFreq(f); if (!c) continue;
    for (const [w, at, no] of [[c.wave, c.route.hub, c.noBack], [c.waveDest, c.route.dest, c.noOut]]) {
      if (w && w.a && w.a.n && w.a.status === "late") { n += c.rtWk; if (where.length < 6) where.push(at + " " + (no || "?") + " (bank " + w.a.n + ", " + M.hhmm(w.a.wait) + " ahead)"); } } }
  return { n, where }; })())"""


# ---------- the two planners
class OldHubs(rs.Planner):
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
        await self.pg.wait_for_function("() => window.__eqOld && window.__eqDataLoaded === true", timeout=60000)

    async def run(self, js):
        return await self.pg.evaluate("s => window.__eqOld(s)", js)

    async def view(self, code, day):
        st = {"view": "hub", "hubCode": code, "day": day, "modal": None}
        await self.run(f"Object.assign(ui, {json.dumps(st)}); render(); true")
        await settle(self.pg, 60)


async def new_go(pl, to):
    """The new planner at one of its addresses (inside the router), once Hubs has drawn that board."""
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", to)
    await new_wait(pl, to)


async def new_wait(pl, to, timeout=60000):
    await pl.pg.wait_for_function("""want => { const m = document.querySelector('main[data-screen=hubs]');
        return !!m && m.dataset.hubsReady === 'yes' && decodeURIComponent(m.dataset.hubsView || '') === decodeURIComponent(want); }""", arg=to, timeout=timeout)
    await settle(pl.pg, 60)


def place(code, day):
    return f"/hubs/{code}" + (f"?day={day}" if day else "")


# ---------- 3. the boards
def first_diff(a, b):
    a, b = a or [], b or []
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else "(none)"
        y = b[i] if i < len(b) else "(none)"
        if x != y:
            return f"item {i}: old {x!r}, new {y!r}" + (f" ({len(a)} old, {len(b)} new)" if len(a) != len(b) else "")
    return ""


def total(words):
    """How many flights words like "North America 7 · Europe 2" or "US 5 · IN 2" add up to."""
    return sum(int(x.rsplit(" ", 1)[-1]) for x in words.split(" · ") if x.strip() and x.rsplit(" ", 1)[-1].isdigit())


def compare_connections(oc, nc, label, code):
    if oc is None or nc is None:
        return [] if oc == nc else [f"{label}: the connections board: old {'there' if oc else 'missing'}, new {'there' if nc else 'missing'}"]
    p = []
    for k in ("head", "dim", "note"):
        if oc[k] != nc[k]:
            p.append(f"{label}: the connections {k}: old {oc[k]!r}, new {nc[k]!r}")
    if len(oc["rows"]) != len(nc["rows"]):
        return p + [f"{label}: the connections table: old rows {[r[0]['t'] for r in oc['rows']]}, new {[r[0]['t'] for r in nc['rows']]}"]
    for orow, nrow in zip(oc["rows"], nc["rows"]):
        if len(orow) != len(nrow):
            p.append(f"{label}: a connections row: old {[c['t'] for c in orow]}, new {[c['t'] for c in nrow]}")
            continue
        name = orow[0]["t"]
        for i, (o, n) in enumerate(zip(orow, nrow)):
            if i in (1, 2) and len(orow) == 5 and o["dim"] != n["dim"]:
                if o["first"] != n["first"] or total(o["dim"]) != total(n["dim"]):
                    p.append(f"{label} {name}: {'arriving from' if i == 1 else 'leaving to'}: old {o['first']} ({o['dim']}), new {n['first']} ({n['dim']})")
                else:
                    known("regions", f"{code} {name} {'arriving' if i == 1 else 'leaving'}: old '{o['dim']}', new '{n['dim']}'")
            elif o["t"] != n["t"]:
                p.append(f"{label} {name}: cell {i}: old {o['t']!r}, new {n['t']!r}")
    return p


def compare_board(o, n, label, code):
    if o is None or n is None:
        return [f"{label}: old {'drawn' if o else 'not drawn'}, new {'drawn' if n else 'not drawn'}"]
    p = []
    for k in ("title", "selected", "days", "count", "focus", "wins", "ticks", "hours", "legend", "weekHead", "week", "flights", "empty"):
        if o[k] == n[k]:
            continue
        what = first_diff(o[k], n[k]) if isinstance(o[k], list) or isinstance(n[k], list) else f"old {o[k]!r}, new {n[k]!r}"
        if code in COPY["est"]:
            known("block estimates", f"{label}: {k}: {what}"[:240])
        elif code in COPY["no_mct"] and k in ("wins", "ticks", "week", "flights"):
            known("minimum connection time", f"{label}: {k}: {what}"[:240])
        else:
            p.append(f"{label}: {k}: {what}")
    cp = compare_connections(o["conn"], n["conn"], label, code)
    if cp and code in COPY["est"]:
        for x in cp:
            known("block estimates", x[:240])
        cp = []
    elif cp and code in COPY["no_mct"]:
        for x in cp:
            known("minimum connection time", x[:240])
        cp = []
    return p + cp


async def boards(old, new):
    old_codes = json.loads(await old.run("JSON.stringify(state.ref.hubs.map(h => h.code))"))
    codes = list(dict.fromkeys(old_codes))
    p, views, figs = [], 0, {"ticks": 0, "flights": 0, "cells": 0, "pairs": 0, "rows": 0, "empty": 0, "focus": 0}
    first = True
    for code in codes:
        for day in range(7):
            views += 1
            await old.view(code, day)
            o = await old.pg.evaluate(READ, OLD_ROOT)
            await new_go(new, place(code, day))
            n = await new.pg.evaluate(READ, NEW_ROOT)
            label = f"{code} {DAYS[day]}"
            if first and o and n:
                first = False
                if o["options"] != n["options"]:
                    if list(dict.fromkeys(o["options"])) == n["options"]:
                        known("an airport two airlines share", f"old list {len(o['options'])} entries, new {len(n['options'])} airports")
                    else:
                        p.append(f"the list of bases: {first_diff(o['options'], n['options'])}")
            p += compare_board(o, n, label, code)
            if n:
                figs["ticks"] += len(n["ticks"] or [])
                figs["flights"] += max(0, len(n["flights"] or []) - 1)
                figs["cells"] += max(0, len(n["week"] or []) - 1) * 96
                figs["empty"] += 1 if n["empty"] else 0
                if day == 0:
                    figs["focus"] += 1 if n["focus"] else 0
                    m = re.search(r"(\d+) city pairs linked", (n["conn"] or {}).get("head", ""))
                    figs["pairs"] += int(m[1]) if m else 0
                    figs["rows"] += max(0, len((n["conn"] or {}).get("rows", [])) - 1)
    label = (f"every base's and focus city's board equals the old Hubs' on every day ({len(codes)} airports × 7 days = {views} boards, "
             f"{figs['focus']} of them focus cities with their note: the list of bases and the days, the count line, the bank windows, "
             f"{figs['ticks']} ticks, the hourly bars, the week grid ({figs['cells']} cells), {figs['flights']} flight rows with their bank "
             f"({figs['empty']} empty days), and the connections table: {figs['pairs']} city pairs in {figs['rows']} rows)")
    return codes, label, p


# ---------- 4. addresses
async def addresses(new, port, codes):
    p = []
    pg = new.pg
    target = codes[1] if len(codes) > 1 else codes[0]
    await pg.goto(f"http://{LIVE_HOST}:{port}/planner/next/hubs/{target}?day=3")
    await new_wait(new, f"/hubs/{target}?day=3", timeout=90000)
    got = await pg.evaluate(READ, NEW_ROOT)
    if got["selected"] != target or "*Thu" not in got["days"]:
        p.append(f"/planner/next/hubs/{target}?day=3, opened directly, shows {got['selected']} on {[d for d in got['days'] if d.startswith('*')]}")
    await pg.click(".toolbar .seg button[data-day='5']")
    try:
        await new_wait(new, f"/hubs/{target}?day=5", timeout=15000)
    except Exception:
        p.append(f"Sat didn't move the address to /hubs/{target}?day=5 (it's {await pg.evaluate('location.pathname + location.search')})")
    other = codes[0]
    await pg.select_option("#h-hub", other)
    try:
        await new_wait(new, f"/hubs/{other}?day=5", timeout=15000)
    except Exception:
        p.append(f"picking {other} didn't move the address to /hubs/{other}?day=5 (it's {await pg.evaluate('location.pathname + location.search')})")
    await pg.click("[data-screen-link=hubs]")
    try:
        await new_wait(new, "/hubs", timeout=15000)
        got = await pg.evaluate(READ, NEW_ROOT)
        if got["selected"] != codes[0] or "*Mon" not in got["days"]:
            p.append(f"/planner/next/hubs shows {got['selected']} on {[d for d in got['days'] if d.startswith('*')]}, not {codes[0]} on Monday")
    except Exception as e:
        p.append(f"the header's Hubs link: {why(e)}")
    return (f"its addresses: /planner/next/hubs opens {codes[0]} on Monday; /planner/next/hubs/{target}?day=3, opened directly, reopens that "
            f"board; the day buttons and the list of bases move the address"), p


# ---------- 5. a preview, 6. a phone and the screenshots
async def preview(p, port, env, facts, staff, moment, seen, code):
    pv = pn.Planner(p, port, env, facts)
    seen.append(pv)
    problems = []
    try:
        await pv.open(host="127.0.0.1", moment=moment)
        await pv.pg.emulate_media(reduced_motion="reduce")
        await pv.sign_in(*staff)
        n0, mark = counts(), marks()
        await new_go(pv, place(code, 2))
        got = await pv.pg.evaluate(READ, NEW_ROOT)
        if not got or not got["flights"] and not got["empty"]:
            problems.append("the preview shows no board")
        state = await pv.pg.evaluate("(document.querySelector('[data-save-state]') || {}).textContent")
        if state != "preview · not saved":
            problems.append(f"the header says {state!r}, not \"preview · not saved\"")
        if "planner_save" in pv.rpcs:
            problems.append("the preview sent planner_save() to the copy")
        if log_since(mark):
            problems.append("the tables changed")
        problems += count_changes(n0, counts()) + pv.errors
    finally:
        await pv.close()
    return f"a preview address (127.0.0.1) shows Hubs ({code}) and sends no write (it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})", problems


async def phone(p, port, env, facts, staff, moment, seen, codes):
    ph = pn.Planner(p, port, env, facts, width=380, height=800)
    seen.append(ph)
    problems = []
    scroll = "Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth"
    own = """sel => { const e = document.querySelector(sel); return e ? [e.scrollWidth, e.clientWidth, getComputedStyle(e).overflowX] : null; }"""
    try:
        await ph.open(moment=moment)
        await ph.pg.emulate_media(reduced_motion="reduce")
        await ph.sign_in(*staff)
        for code in codes:
            await new_go(ph, place(code, 0))
            if (over := await ph.pg.evaluate(scroll)) > 0:
                problems.append(f"{code} scrolls sideways by {over} px at 380 px wide")
            for sel, what in (("main[data-screen=hubs] .wgwrap", "the week grid"), ("main[data-screen=hubs] .hubscroll", "the day strip")):
                box = await ph.pg.evaluate(own, sel)
                if not box or box[2] not in ("auto", "scroll") or box[0] <= box[1]:
                    problems.append(f"{code}: {what} doesn't scroll inside its own box ({box})")
        problems += ph.errors
    finally:
        await ph.close()
    return (f"at 380 px wide {' and '.join(codes)} have no sideways scroll and no errors; the day strip and the week grid scroll inside "
            f"their own box"), problems


async def screenshots(old, new, codes):
    if not SCREENS_DIR:
        return
    Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    for width, height in ((1280, 900), (380, 800)):
        await old.pg.set_viewport_size({"width": width, "height": height})
        await new.pg.set_viewport_size({"width": width, "height": height})
        for code in codes:
            await old.view(code, 0)
            await settle(old.pg, 400)
            await old.pg.screenshot(path=str(Path(SCREENS_DIR) / f"old-hubs-{code}-{width}.png"), full_page=True, timeout=90000)
            await new_go(new, place(code, 0))
            await settle(new.pg, 400)
            await new.pg.screenshot(path=str(Path(SCREENS_DIR) / f"hubs-{code}-{width}.png"), full_page=True, timeout=90000)
    await old.pg.set_viewport_size({"width": 1440, "height": 1000})
    await new.pg.set_viewport_size({"width": 1280, "height": 900})


# ---------- what the copy holds
def read_copy():
    bases = json.loads(psql(f"""select coalesce(json_agg(json_build_array(b.airport_code, b.role, wa.mct_min) order by b.position nulls last, b.id), '[]')
              from public.airline_bases b left join public.world_airports wa on wa.world_id = b.world_id and wa.airport_code = b.airport_code
             where b.world_id = {WORLD}""").strip())
    est = set(json.loads(psql(f"""select coalesce(json_agg(distinct c), '[]') from (
              select l2.origin_code c from public.flight_legs l join public.flight_legs l2 on l2.rotation_id = l.rotation_id
               where l.world_id = {WORLD} and l.dep_utc_min is not null and l.block_min is null
              union select l2.dest_code from public.flight_legs l join public.flight_legs l2 on l2.rotation_id = l.rotation_id
               where l.world_id = {WORLD} and l.dep_utc_min is not null and l.block_min is null) x""").strip()))
    legs = int(psql(f"select count(*) from public.flight_legs where world_id = {WORLD}").strip())
    ours = int(psql(f"""select count(*) from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
              where g.kind = 'ours' and a.world_id = {WORLD}""").strip())
    COPY.update(bases=bases, est=est, no_mct={b[0] for b in bases if b[2] is None}, legs=legs, ours=ours,
                hub=next((b[0] for b in bases if b[1] != "focus"), None), focus=next((b[0] for b in bases if b[1] == "focus"), None))


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
    try:
        read_copy()
        problems = [] if COPY["bases"] and COPY["legs"] else ["the copy has no bases or no flight legs"]
    except Exception as e:
        problems = [why(e)]
    step(not problems, f"the moment: {moment} (the copy's latest capture plus one hour); the copy: {len(COPY.get('bases', []))} bases and focus cities "
         f"({sum(1 for b in COPY.get('bases', []) if b[1] == 'focus')} focus cities), {COPY.get('legs', 0)} flight legs, {COPY.get('ours', 0)} of our airlines; "
         f"{len(COPY.get('est', []))} airports with an estimated leg, {len(COPY.get('no_mct', []))} bases with no minimum connection time", problems)
    if problems:
        sys.exit(1)

    tag = secrets.token_hex(4)
    staff = (f"hubs-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="hubs-side-by-side-"))
    seen = []
    shots = [c for c in (COPY["hub"], COPY["focus"]) if c]
    try:
        root = web_copy(work)
        with serve(root) as port:
            async with async_playwright() as p:
                old = OldHubs(p, port, env, facts, lib_js, moment=moment)
                new = pn.Planner(p, port, env, nfacts, width=1280, height=900)
                seen += [old, new]
                try:
                    n0, mark = counts(), marks()
                    await old.open()
                    await old.sign_in(*staff)
                    await old.ready()
                    await new.open(moment=moment)
                    await new.pg.emulate_media(reduced_motion="reduce")
                    await new.sign_in(*staff)
                    await new_go(new, "/hubs")
                    problems = list(old.errors) + list(new.errors)
                    if log_since(mark):
                        problems.append("opening the planners changed the tables")
                    problems += count_changes(n0, counts())
                    if abs(await new.pg.evaluate("Date.now()") - ms(moment)) > 1000:
                        problems.append("the new planner's clock isn't frozen at the moment")
                    if await new.pg.evaluate("!!document.querySelector('main[data-screen=hubs] [data-not-built]')"):
                        problems.append("Hubs is still a placeholder")
                except Exception as e:
                    problems = [why(e)] + old.errors[:3] + new.errors[:3]
                step(not problems, "both planners opened at the moment, signed in as test staff, the new one on Hubs; opening them wrote nothing", problems)
                if problems:
                    sys.exit(1)

                t = time.monotonic()
                codes = []
                try:
                    codes, label, problems = await boards(old, new)
                except Exception as e:
                    label, problems = "every base's and focus city's board on every day", [why(e)]
                step(not problems and len(codes) > 0, label + f" ({time.monotonic() - t:.0f} s)",
                     (problems or ([] if codes else ["no board compared"])) + new.errors[:3] + old.errors[:3])
                for k, v in KNOWN.items():
                    where = f" (e.g. {'; '.join(v['where'][:4])})" if v["where"] else ""
                    print(f"      known difference \"{k}\": used {v['used']} time(s){where}. {v['rule']}"[:1800], flush=True)
                try:
                    late = json.loads(await old.run(OLD_LATE))
                    print(f"      kept from the old Hubs: {late['n']} arrival(s) a week name the bank they can next make although they land more than "
                          f"connection_max_wait_h before it" + (f" (e.g. {'; '.join(late['where'])})" if late["where"] else ""), flush=True)
                except Exception as e:
                    print(f"      the late arrivals: {why(e)}", flush=True)
                try:
                    await screenshots(old, new, shots)
                except Exception as e:
                    print(f"      the screenshots: {why(e)}", flush=True)
                if codes:
                    try:
                        label, problems = await addresses(new, port, codes)
                    except Exception as e:
                        label, problems = "its addresses", [why(e)]
                    step(not problems, label, problems + new.errors[:3])
                await old.close()
                await new.close()

                for check, args in ((preview, (COPY["hub"] or codes[0],)), (phone, (shots,))):
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
    print(f"\n{len(failures)} Hubs side-by-side step(s) failed" if failures else "\nHubs side by side: all passed", flush=True)
    print(f"      the Hubs side by side took {time.monotonic() - started:.0f} s", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
