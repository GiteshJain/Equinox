"""The new planner's Routes side by side with the old Routes on the rehearsal's copy (decision #18, build pull request 6,
spec docs/specs/2026-10-13-routes.md §4): the pull request's own new planner (built into web/app/) and the old planner
(web/planner/), both at their live addresses, signed in as the same test staff user, at the same frozen moment, reading
a full local copy of Supabase restored from last night's backup.

Run by database/rehearse.sh, last (after the Home side by side). Like tests/home_side_by_side_test.py it uses
tests/real_saves_test.py's helpers and request mapping, needs the copy, so it isn't part of tests/run_all.sh, and
nothing goes outside.

1. The moment: the copy's latest capture plus one hour, as tests/captured_figures_test.py takes it; typed loads and day
   flags entered after it are set aside while the test runs and put back when it ends.
2. Both planners open at the moment (the old one from a copy of web/ with captured_figures_test.py's hook, so the test
   can set its screen's state; web/planner/ itself is unchanged). Opening them writes nothing.
3. For every airline, the list: every row (route, city, trunk, stars, market, distance, its load, round trips a day with
   their bank fit, aircraft and numbers) with its first base picked and with all bases; the order under each sort; and
   the rows each filter leaves (each base alone, each focus city's trunks, each star, each market, active only, three
   distance ranges, a search), with the count line and the Remove-unflown button.
4. For every flown route, the header (stars, airline, market, distance, the two offsets, the estimated block, the
   market's plan, service and banks), its loads, and every frequency: both lines (times both ways, block, est, day
   markers, each flight's load), every pill and its words, the connections at both ends (every flight, time,
   connection and days, and the note) and the form (days, aircraft, numbers, the four times and their placeholders,
   service, price, the loads typed, launched, notes); in local time, and in UTC for a sample. For the first unflown route
   of each airline, the header and the next free numbers. The route pop-up Home's map opens, for a sample.
5. Real saves through the new Routes' own controls: add a route, edit its stars and its market, add a frequency, type its
   days and times, change its time, delete it, remove the route, change an offset on an airport only one flight uses (the
   page lists the flights that move and asks in itself) and put it back. Each writes exactly its rows, logged as planner
   with the tab's ID; the old planner, opened again, shows the same route and frequency with the same local times.
6. A preview address (127.0.0.1) shows Routes, and an add, a change and an edit there send no write.
7. At 380 px wide the list and a route have no sideways scroll and no errors. Screenshots of the list and a route, new
   and old, at 380 and 1280 px go to ROUTES_SCREENS_DIR (the run's routes-screens artifact) when it's set.
8. Nothing went outside.

A difference fails and names the airline, the route and both values, unless it is a known difference (KNOWN below, each
with its rule), printed with how often it was used and examples. Prints codes, flight numbers, counts and the screens'
words, never anything else from the rows, since the log is posted on the pull request; never the local keys or the
test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL, SECRET_TABLES and ROUTES_SCREENS_DIR.
Usage: python3 tests/routes_side_by_side_test.py
"""
import asyncio, atexit, json, os, re, secrets, shutil, sys, tempfile, time
from collections import Counter
from pathlib import Path
from urllib.parse import quote
from harness import LIVE_HOST, serve, settle
from playwright.async_api import async_playwright
import real_saves_test as rs
from real_saves_test import count_changes, counts, is_planner_user, library, local_env, log_since, make_user, marks, planner_facts, psql, token_for, why
import planner_next_test as pn
from captured_figures_test import HELD, ms, put_back, set_aside
from home_side_by_side_test import web_copy

SCREENS_DIR = os.environ.get("ROUTES_SCREENS_DIR")
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"
UTC_SAMPLE = 3        # flown routes per airline also compared in UTC
POPUP_SAMPLE = 2      # flown routes per airline whose Home pop-up is compared
# STILL: both planners ask for reduced motion before Home is first drawn, as tests/home_side_by_side_test.py does, so the
# hero's globe holds still. Without it the pop-up step, on Home, took 5 to 6 minutes on two runs (once timing out)
# against 70 seconds on the first, most likely the turning globe keeping the runner's processor busy. Nothing on Routes
# moves.
failures = []
started = time.monotonic()
COPY = {"mct_differs": {}, "est_routes": set(), "est_flights": set(), "loads": {}}   # what the copy holds: read_copy() and main()

# Where the new Routes follows its spec and the old Routes did otherwise. Each is allowed only where its test says, and
# printed with how often it was used and examples.
KNOWN = {
    "block estimates": {
        "rule": "an arrival left empty takes the estimate: the old planner fitted its estimates to the times typed in (estBlockFor, "
                "and 830 km/h for a market without an aircraft); the library uses 25 min + distance ÷ the type's speed (manual §4, "
                "#19 spec §5, as tests/rules_library_test.py allows). Only on a frequency with an estimated time, and the header's "
                "estimate; everything that follows from the estimate there (the arrival, its bank fit, the ground time, a night ban) "
                "may differ with it.",
        "used": 0, "where": []},
    "minimum connection time": {
        "rule": "manual §4: each airport's minimum connection time (world_airports.mct_min). The old planner uses its hub's figure, or "
                "90 minutes elsewhere (mctAt); the library uses 90 only where mct_min is empty (#19 spec §5, as tests/rules_library_test.py "
                "allows). Only for the connections at an airport where the two figures differ (worked out at the start, both read from "
                "the planners themselves).",
        "used": 0, "where": []},
    "added checks": {
        "rule": "the spec (§1) asks Routes for every check, the aircraft's position and the second-daily gap included; the old "
                "Routes showed neither, so those pills (marked data-check=added) are the library's alone and aren't compared.",
        "used": 0, "where": []},
    "order on a tie": {
        "rule": "routes that tie under a sort (the same stars and distance, the same load, ...) are in the research's order: the "
                "old planner's planner_data list, the new planner's routes table by id. The same routes, another order.",
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
    KNOWN[name]["where"].append(where)


# ---------- reading either Routes: the new one draws the old one's markup, so one reader serves both
READ = r"""() => {
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const cls = e => [...e.classList].filter(c => c !== "pill").sort().join(" ");
  const pills = root => (root ? [...root.querySelectorAll(".pill")].map(p => cls(p) + ": " + T(p)) : []);
  function readList() {
    const rows = [...document.querySelectorAll("#routelist .row")].map(r => ({
      key: T(r.querySelector(".rk b")).replace("–", "-"), city: T(r.querySelector(".rk .city")), rm: T(r.querySelector(".rm")), rs: T(r.querySelector(".rs")),
      stars: [...T(r.querySelector(".rm .stars"))].filter(c => c === "★").length - [...T(r.querySelector(".rm .stars .off"))].length,
      trunk: !!r.querySelector(".rm .pill.trunk"), pills: pills(r.querySelector(".rs")) }));
    const chips = [...document.querySelectorAll(".chips")].map(c => [...c.querySelectorAll(".chip")].map(b => (b.classList.contains("on") ? "*" : "") + T(b)));
    return { count: T(document.querySelector(".toolbar .count")), rows, chips, rmButton: T(document.querySelector("#rm-filtered")),
             empty: T(document.querySelector("#routelist .empty")) };
  }
  function readDetail() {
    const d = document.querySelector("#detail");
    if (!d) return null;
    const h = d.querySelector(".dhead");
    const lines = f => [...f.querySelectorAll(":scope > .fl")].filter(l => !l.matches("[data-check=added]"));
    const freq = f => ({
      lines: lines(f).map(T), pills: lines(f).flatMap(l => pills(l)),
      added: [...f.querySelectorAll(":scope > .fl[data-check=added] .pill")].map(p => cls(p) + ": " + T(p)),
      cx: [...f.querySelectorAll("details.cx")].map(c => ({ at: T(c.querySelector(".cxap")).replace(/^At /, ""), summary: T(c.querySelector("summary")),
        heads: [...c.querySelectorAll(".cxh")].map(T), rows: [...c.querySelectorAll("table tr")].map(tr => [...tr.children].map(T).join(" | ")),
        note: T(c.querySelector(".note")), empty: T(c.querySelector(":scope > .dim")) })),
      form: Object.fromEntries([...f.querySelectorAll(".fg [data-k]")].map(i => [i.dataset.k, i.value + (i.placeholder ? " [" + i.placeholder + "]" : "")])),
      labels: [...f.querySelectorAll(".fg label")].map(l => (l.firstChild && l.firstChild.nodeType === 3 ? l.firstChild.textContent : "").trim()),
    });
    const lfs = d.querySelector(".lfs");
    return {
      h2: T(h && h.querySelector("h2")), dsub: h ? [...h.querySelectorAll(".dsub")].map(T) : [],
      utc: h ? [...h.querySelectorAll(".dsub input[data-utc]")].map(i => i.dataset.utc + "=" + i.value) : [],
      empty: T(d.querySelector(".empty")), loads: lfs ? (lfs.children.length ? [...lfs.children].map(T) : [T(lfs)]) : [],
      bar: [...d.querySelectorAll(".lfbar i")].map(i => i.className + ":" + i.style.flexGrow), freqs: [...d.querySelectorAll(".freq")].map(freq),
      addFreq: !!d.querySelector("#add-freq"),
    };
  }
  function readPopup() {
    const m = document.querySelector(".modal");
    if (!m) return null;
    return { head: T(m.querySelector(".mhead > div")), stats: [...m.querySelectorAll(".mstats > div")].map(T), statPills: pills(m.querySelector(".mstats")),
             rows: [...m.querySelectorAll(".mbody table tr")].map(tr => [...tr.children].map(T).join(" | ")), note: T(m.querySelector(".mbody .note")),
             empty: T(m.querySelector(".mbody > .dim")), foot: T(m.querySelector(".mfoot")) };
  }
"""
READ_LIST = READ + "return readList(); }"
READ_DETAIL = READ + "return readDetail(); }"
READ_POPUP = READ + "return readPopup(); }"
SORTS = ["stars", "distUp", "distDown", "dest", "load"]


# ---------- the two planners
class OldRoutes(rs.Planner):
    """The old planner (real_saves_test.py's), its clock frozen at the moment before its scripts run, with the hook."""

    def __init__(self, *a, moment, **k):
        super().__init__(*a, **k)
        self.moment = moment
        self.mode = "local"   # the time mode it's shown in (set without saving it), as the new planner's toggle

    async def page(self, host=LIVE_HOST):
        self.pg = pg = await self.ctx.new_page()
        await pg.clock.set_fixed_time(self.moment)
        await pg.emulate_media(reduced_motion="reduce")   # as the new planner here (STILL)
        pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
        pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
              if m.type == "error" and "Failed to load resource" not in m.text else None)
        pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await pg.goto(f"http://{host}:{self.port}/planner/")
        return pg

    async def ready(self):
        await self.pg.wait_for_function("() => window.__eqOld && window.__eqOld('CAP.at') > 0 && window.__eqOld('CAP.backupLoaded') "
                                        "&& window.__eqOld('CAP.jobsLoaded')", timeout=60000)

    async def run(self, js):
        return await self.pg.evaluate("s => window.__eqOld(s)", js)

    async def view(self, airline, f, route=None):
        """The old Routes with its state set as the new planner's address says (f: the filters, as for the new)."""
        st = {"view": "routes", "airline": airline, "hubs": f["bases"], "markets": f.get("markets", []), "stars": f.get("stars", []),
              "dmin": f.get("kmFrom", ""), "dmax": f.get("kmTo", ""), "sort": f.get("sort", "stars"), "activeOnly": bool(f.get("active")),
              "q": f.get("q", ""), "trunkOnly": bool(f.get("trunks")), "route": route, "addingRoute": False, "editRoute": False, "modal": None}
        await self.run(f"Object.assign(ui, {json.dumps(st)}); state.ref.timeMode = {json.dumps(self.mode)}; render(); true")
        await settle(self.pg, 120)

    async def reopen(self):
        await self.pg.close()
        await self.page()
        await self.pg.wait_for_function("() => window.__eqDataLoaded === true", timeout=60000)
        await self.ready()


def query(f):
    """The new planner's address for the filters (model.ts's filtersQuery, written out again here)."""
    enc = lambda xs: ",".join(quote(x, safe="").replace("%20", "+") for x in xs)
    p = []
    if f.get("airline"):
        p.append("airline=" + quote(f["airline"]))
    if f.get("bases") is not None:
        p.append("bases=" + (enc(f["bases"]) if f["bases"] else "all"))
    if f.get("trunks"):
        p.append("trunks=1")
    if f.get("stars"):
        p.append("stars=" + ",".join(map(str, f["stars"])))
    if f.get("markets"):
        p.append("markets=" + enc(f["markets"]))
    if f.get("kmFrom") or f.get("kmTo"):
        p.append(f"km={quote(f.get('kmFrom', ''))}-{quote(f.get('kmTo', ''))}")
    if f.get("active"):
        p.append("active=1")
    if f.get("sort", "stars") != "stars":
        p.append("sort=" + f["sort"])
    if f.get("q"):
        p.append("q=" + quote(f["q"]))
    return ("?" + "&".join(p)) if p else ""


async def new_go(pl, to, detail=None):
    """The new planner at one of its addresses (inside the router, as a click would take it; the address under
    /planner/next), once it has read everything and, for a route, drawn it (or given up after 10 s, so the comparison
    names what's missing)."""
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", to)
    await pl.pg.wait_for_function("""want => { const m = document.querySelector('main[data-screen=routes]');
        return !!m && m.dataset.routesReady === 'yes' && decodeURIComponent(m.dataset.routesView || '') === decodeURIComponent(want); }""",
                                  arg=to, timeout=60000)
    if detail:
        try:
            await pl.pg.wait_for_selector(f"[data-route-detail={json.dumps(detail)}]", timeout=10000)
        except Exception:
            pass
    await settle(pl.pg, 150)


async def set_mode(old, new, mode):
    """Both planners in local or UTC time, neither saving it (the old one's state.ref.timeMode, the new one's toggle)."""
    old.mode = mode
    await old.run(f"state.ref.timeMode = {json.dumps(mode)}; render(); true")
    if await new.pg.evaluate("document.querySelector('#timemode').dataset.timeMode") != mode:
        await new.pg.click("#timemode")
        await new.pg.wait_for_function("m => document.querySelector('#timemode').dataset.timeMode === m", arg=mode)
    await settle(new.pg, 200)


# ---------- comparing
def dist_of(row):
    m = re.search(r"([\d,]+) km$", row["rm"])
    return int(m[1].replace(",", "")) if m else 0


def tie_key(row, sort, loads, focus_first):
    dest = row["key"].split("-", 1)[1]
    k = {"stars": (-row["stars"], dist_of(row)), "distUp": (dist_of(row),), "distDown": (-dist_of(row),), "dest": (dest,),
         "load": (round(loads.get(row["key"], 999), 9), -row["stars"])}[sort]
    return ((0 if row["trunk"] else 1),) + k if focus_first else k


def compare_order(old_rows, new_rows, sort, loads, focus_first, label):
    """The same routes, in the same order up to ties under the sort (known: order on a tie)."""
    ok, nk = [r["key"] for r in old_rows], [r["key"] for r in new_rows]
    if ok == nk:
        return []
    if sorted(ok) != sorted(nk):
        only_o, only_n = sorted(set(ok) - set(nk)), sorted(set(nk) - set(ok))
        return [f"{label}: {len(ok)} routes in the old list, {len(nk)} in the new" + (f"; only the old has {only_o[:8]}" if only_o else "")
                + (f"; only the new has {only_n[:8]}" if only_n else "")]
    group = lambda rows: [(tie_key(r, sort, loads, focus_first), r["key"]) for r in rows]
    go, gn = group(old_rows), group(new_rows)
    if [k for k, _ in go] != [k for k, _ in gn]:
        i = next(i for i, (a, b) in enumerate(zip(go, gn)) if a[0] != b[0])
        return [f"{label}: the order differs at row {i + 1}: old {go[i][1]}, new {gn[i][1]}"]
    known("order on a tie", f"{label}: e.g. {next(a for a, b in zip(ok, nk) if a != b)}")
    return []


def compare_rows(old, new, label, est_routes):
    p = []
    if old["count"] != new["count"]:
        p.append(f"{label}: the count: old {old['count']!r}, new {new['count']!r}")
    if old["rmButton"] != new["rmButton"]:
        p.append(f"{label}: the remove button: old {old['rmButton']!r}, new {new['rmButton']!r}")
    nm = {r["key"]: r for r in new["rows"]}
    for o in old["rows"]:
        n = nm.get(o["key"])
        if not n:
            continue
        for k in ("city", "rm", "rs", "trunk", "pills", "stars"):
            if o[k] != n[k]:
                if k in ("rs", "pills") and o["key"] in est_routes:
                    known("block estimates", f"{label} {o['key']}: old {o[k]!r}, new {n[k]!r}")
                else:
                    p.append(f"{label} {o['key']}: {k}: old {o[k]!r}, new {n[k]!r}")
    return p


def has_est(freq):
    return any(" est" in l for l in freq["lines"]) or any("est]" in v for v in freq["form"].values())


def typed(form):
    """The form's values as typed (without the placeholders, which show estimates)."""
    return {k: v.split(" [")[0] for k, v in form.items()}


def est_rows_only(x, y):
    """Whether two connection sections differ only in rows whose flight has an estimated time (its arrival, so its
    connection, follows the estimate)."""
    diff = set(x["rows"]) ^ set(y["rows"])
    return bool(diff) and all(r.split(" | ")[0] in COPY["est_flights"] for r in diff)


def compare_detail(o, n, label):
    """A route's header and frequencies, the old Routes' against the new's."""
    p = []
    if o is None or n is None:
        return [f"{label}: the {'old' if o is None else 'new'} Routes shows no route"]
    for k in ("h2", "utc", "empty", "loads", "bar", "addFreq"):
        if o[k] != n[k]:
            p.append(f"{label}: {k}: old {o[k]!r}, new {n[k]!r}")
    est_re = re.compile(r"Est\. block (\S+) on")
    if o["dsub"] != n["dsub"]:
        oo, nn = [est_re.sub("Est. block * on", x) for x in o["dsub"]], [est_re.sub("Est. block * on", x) for x in n["dsub"]]
        if oo == nn:
            ob, nb = (est_re.search(" ".join(d)) for d in (o["dsub"], n["dsub"]))
            known("block estimates", f"{label}: the header's {ob[1] if ob else '?'} against {nb[1] if nb else '?'}")
        else:
            p.append(f"{label}: the header: old {o['dsub']!r}, new {n['dsub']!r}")
    if len(o["freqs"]) != len(n["freqs"]):
        p.append(f"{label}: old {len(o['freqs'])} frequencies, new {len(n['freqs'])}")
    for i, (a, b) in enumerate(zip(o["freqs"], n["freqs"])):
        fl = f"{label} frequency {i + 1} ({(a['lines'] or ['?'])[0].split(' ')[0]})"
        if b["added"]:
            known("added checks", f"{fl}: {'; '.join(b['added'])[:160]}")
        est = has_est(a) or has_est(b)
        for k in ("lines", "pills", "form", "labels"):
            if a[k] == b[k]:
                continue
            if est and k in ("lines", "pills"):
                known("block estimates", f"{fl}: {k}: old {a[k]!r}, new {b[k]!r}"[:300])
            elif est and k == "form" and typed(a[k]) == typed(b[k]):
                known("block estimates", f"{fl}: the estimates shown in the empty boxes")
            else:
                p.append(f"{fl}: {k}: old {a[k]!r}, new {b[k]!r}")
        oc, nc = {c["at"]: c for c in a["cx"]}, {c["at"]: c for c in b["cx"]}
        if list(oc) != list(nc):
            p.append(f"{fl}: the connections at {list(oc)} (old), {list(nc)} (new)")
        for at in oc:
            x, y = oc[at], nc.get(at)
            if y is None or x == y:
                continue
            if est:
                known("block estimates", f"{fl}: connections at {at} (this frequency's estimated time)")
            elif at in COPY["mct_differs"]:
                a_, b_ = COPY["mct_differs"][at]
                known("minimum connection time", f"{fl}: at {at} (the old planner's {a_} min, the library's {b_}): old {x['summary']!r}, new {y['summary']!r}")
            elif est_rows_only(x, y):
                known("block estimates", f"{fl}: connections at {at}: flights with an estimated arrival "
                                         f"{sorted({r.split(' | ')[0] for r in set(x['rows']) ^ set(y['rows'])})[:6]}")
            else:
                for k in ("summary", "heads", "rows", "note", "empty"):
                    if x[k] != y[k]:
                        p.append(f"{fl}: connections at {at}: {k}: old {x[k]!r}, new {y[k]!r}"[:600])
    return p


# ---------- 3. the lists
async def lists(old, new, airlines):
    p, views = [], 0
    for al in airlines:
        name, code = al["name"], al["code"]
        bases, focus = al["bases"], al["focus"]
        loads = {k[1]: v for k, v in COPY["loads"].items() if k[0] == al["id"]}
        if not bases:
            continue

        async def both(f, label, full=False):
            nonlocal views
            views += 1
            await old.view(name, f)
            o = await old.pg.evaluate(READ_LIST)
            await new_go(new, "/routes" + query(dict(f, airline=code)))
            n = await new.pg.evaluate(READ_LIST)
            focus_first = any(b in focus for b in f["bases"])
            out = compare_order(o["rows"], n["rows"], f.get("sort", "stars"), loads, focus_first, f"{code} {label}")
            if full or o["count"] != n["count"]:
                out += compare_rows(o, n, f"{code} {label}", COPY["est_routes"])
            if full and o["chips"] != n["chips"]:
                out.append(f"{code} {label}: the chips: old {o['chips']}, new {n['chips']}")
            if o["empty"] != n["empty"]:
                out.append(f"{code} {label}: the empty list: old {o['empty']!r}, new {n['empty']!r}")
            return out, o, n

        try:
            x, _, _ = await both({"bases": [bases[0]]}, f"first base ({bases[0]})", full=True)
            p += x
            x, o_all, _ = await both({"bases": []}, "all bases", full=True)
            p += x
            for s in SORTS[1:]:
                p += (await both({"bases": [], "sort": s}, f"all bases, sorted {s}"))[0]
            for b in bases[1:]:
                p += (await both({"bases": [b]}, f"base {b}"))[0]
            for b in focus:
                p += (await both({"bases": [b], "trunks": True}, f"{b}'s trunks"))[0]
            for s in (5, 4, 3, 2, 1):
                p += (await both({"bases": [], "stars": [s]}, f"{s} stars"))[0]
            for m in [c[1:] if c.startswith("*") else c for c in (o_all["chips"][2][1:] if len(o_all["chips"]) > 2 else [])]:
                p += (await both({"bases": [], "markets": [m]}, f"market {m or '(none)'}"))[0]
            p += (await both({"bases": [], "active": True}, "active only"))[0]
            for lo, hi in (("", "1000"), ("1000", "3000"), ("3000", "")):
                p += (await both({"bases": [], "kmFrom": lo, "kmTo": hi}, f"{lo or 0}–{hi or '…'} km"))[0]
            q = o_all["rows"][0]["key"].split("-")[1][:1] if o_all["rows"] else "A"
            p += (await both({"bases": [], "q": q}, f"search {q!r}"))[0]
        except Exception as e:
            p.append(f"{code}: {why(e)}")
    return (f"every airline's list equals the old one ({views} views: each airline's rows with its first base and with all, five sorts, "
            "each base, each focus city's trunks, each star, each market, active only, three distance ranges and a search)"), p


# ---------- 4. the routes
async def route_pair(old, new, al, hub, dest, label):
    """One route in both planners, read."""
    await old.view(al["name"], {"bases": [hub]}, route=f"{al['name']}|{hub}|{dest}")
    o = await old.pg.evaluate(READ_DETAIL)
    await new_go(new, f"/routes/{al['code']}/{hub}-{dest}", detail=f"{hub}-{dest}")
    n = await new.pg.evaluate(READ_DETAIL)
    return compare_detail(o, n, f"{al['code']} {hub}–{dest} ({label})"), n


async def routes_side_by_side(old, new, airlines, which, label):
    p, n_routes, n_freqs = [], 0, 0
    for al in airlines:
        for hub, dest in which.get(al["name"], []):
            try:
                x, n = await route_pair(old, new, al, hub, dest, label)
                p += x
                n_routes += 1
                n_freqs += len((n or {}).get("freqs", []))
            except Exception as e:
                p.append(f"{al['code']} {hub}–{dest} ({label}): {why(e)}")
    return n_routes, n_freqs, p


async def popups(old, new, airlines, flown, route_ids):
    p, n = [], 0
    await new.pg.evaluate("t => window.__eqPlanner.go(t)", "/")
    await new.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=90000)
    await new.pg.wait_for_selector("svg.wmap .hits path.hit[data-route-id]", timeout=60000)
    on_map = set(await new.pg.evaluate("[...document.querySelectorAll('svg.wmap .hits path.hit[data-route-id]')].map(h => h.dataset.routeId)"))
    for al in airlines:
        sample = [(h, d) for h, d in flown.get(al["name"], []) if str(route_ids[(al["name"], h, d)]) in on_map][:POPUP_SAMPLE]
        for hub, dest in sample:
            key = f"{al['name']}|{hub}|{dest}"
            try:
                await old.run("ui.view = 'home'; ui.modal = null; render(); true")
                await old.run(f"ui.modal = {{kind: 'route', key: {json.dumps(key)}}}; render(); true")
                await old.pg.wait_for_timeout(200)   # drawn at once: no wait for the network (with settle() this step took 6 min on one run)
                o = await old.pg.evaluate(READ_POPUP)
                rid = route_ids[(al["name"], hub, dest)]
                await new.pg.evaluate("id => document.querySelector(`svg.wmap .hits path.hit[data-route-id='${id}']`)"
                                      ".dispatchEvent(new MouseEvent('click', {bubbles: true}))", str(rid))
                await new.pg.wait_for_selector(f"[data-route-popup='{hub}-{dest}'][data-popup-ready=yes]", timeout=60000)
                await new.pg.wait_for_timeout(200)
                x = await new.pg.evaluate(READ_POPUP)
                await new.pg.click(".modal .mx")
                await new.pg.wait_for_selector(".modal", state="detached", timeout=10000)
                n += 1
                for k in ("head", "stats", "statPills", "rows", "note", "empty", "foot"):
                    a, b = (o or {}).get(k), (x or {}).get(k)
                    if a == b:
                        continue
                    if k == "rows" and f"{hub}-{dest}" in COPY["est_routes"]:
                        known("block estimates", f"the pop-up of {al['code']} {hub}–{dest}: its bank fit")
                    else:
                        p.append(f"the pop-up of {al['code']} {hub}–{dest}: {k}: old {a!r}, new {b!r}")
            except Exception as e:
                p.append(f"the pop-up of {al['code']} {hub}–{dest}: {why(e)}")
    await old.run("ui.modal = null; ui.view = 'routes'; render(); true")
    return n, p


async def tail_popups(old, new):
    """The aircraft pop-up a frequency's aircraft opens on Routes (build pull request 12, design §16: "the aircraft pop-up opens
    from Home only"), for one frequency of each airline that has an aircraft: the pop-up of that aircraft, against the old
    planner's tailModal(), as tests/tails_side_by_side_test.py compares the one Home opens."""
    import tails_side_by_side_test as ts
    picks = json.loads(psql("""select coalesce(json_agg(x order by x.position, x.code), '[]') from (
        select distinct on (al.id) al.iata_code as code, al.position, ro.id as rot, r.hub_code as hub, r.dest_code as dest, a.registration as reg,
               exists (select 1 from public.flight_legs e where e.aircraft_id = a.id and e.dep_utc_min is not null and e.block_min is null) as est
          from public.rotations ro join public.routes r on r.id = ro.route_id join public.airlines al on al.id = r.airline_id
          join public.flight_legs l on l.rotation_id = ro.id and l.leg_no = 1 join public.aircraft a on a.id = l.aircraft_id
         where ro.world_id = (select w.id from public.worlds w order by w.is_default desc, w.id limit 1) and not r.removed and a.status = 'active'
         order by al.id, ro.id) x""").strip())
    p, n = [], 0
    for x in picks:
        label = f"{x['code']} {x['hub']}–{x['dest']} ({x['reg']})"
        try:
            o = await old.pg.evaluate(ts.OLD_POPUP.replace("arguments[0]", json.dumps(x["reg"])))
            to = f"/routes/{x['code']}/{x['hub']}-{x['dest']}"
            await new_go(new, to, f"{x['hub']}-{x['dest']}")
            await new.pg.click(f".freq[data-rotation='{x['rot']}'] [data-tailm]")
            await new.pg.wait_for_selector(f"[data-aircraft-popup={json.dumps(x['reg'])}][data-popup-ready=yes]", timeout=60000)
            await new.pg.wait_for_timeout(150)
            if "aircraft=" not in await new.pg.evaluate("location.search"):
                p.append(f"{label}: the pop-up isn't in the address")
            y = await new.pg.evaluate(ts.READ_POPUP)
            await new.pg.click(".modal .mx")
            await new.pg.wait_for_selector("[data-aircraft-popup]", state="detached", timeout=10000)
            n += 1
            for k in ("head", "stats", "statPills", "issues", "rows", "empty", "foot"):
                a, b = (o or {}).get(k), (y or {}).get(k)
                if a == b:
                    continue
                if k in ("stats", "statPills", "issues", "rows") and x["est"]:
                    known("block estimates", f"the aircraft pop-up of {label}: {k}")
                else:
                    p.append(f"the aircraft pop-up of {label}: {k}: old {a!r}, new {b!r}"[:600])
        except Exception as e:
            p.append(f"the aircraft pop-up of {label}: {why(e)}")
    return n, p


# ---------- 5. real saves
def logged(mark, allowed, client, want=None):
    """The change-log rows since the mark: each one a table and row the action may change (allowed: (table, id) pairs, or
    (table, None) for any row of the table), exactly want (a Counter of (table, op)) when given, each logged as planner
    with the tab's ID. Returns the problems and the rows."""
    rows = log_since(mark)
    problems = [] if rows else ["nothing was written"]
    got = Counter((r["table"], r["op"]) for r in rows)
    if want is not None and got != want:
        problems.append(f"the tables changed by {dict(got)}, expected {dict(want)}")
    for r in rows:
        if (r["table"], r["id"]) not in allowed and (r["table"], None) not in allowed:
            problems.append(f"the tables changed beyond the action: {r['table']} {r['op']} {r['id'] or ''} ({', '.join(r['fields']) or 'whole row'})")
        if r["actor"] != "planner" or r["detail"] != client:
            problems.append(f"a change-log row names {r['actor']} ({r['detail']}), not planner (the tab's ID)")
    return problems, rows


async def wait_saved(pl, mark, rows=1):
    """Waits for the action's change-log rows, then for the header to say saved and Routes to have read everything again."""
    await rs.wait_for(lambda: log_since(mark), lambda got: len(got) >= rows, seconds=30)
    await settle(pl.pg, 300)
    await pl.pg.wait_for_function("() => /^(saved|preview · not saved)$/.test((document.querySelector('[data-save-state]') || {}).textContent || '')", timeout=30000)
    await pl.pg.wait_for_function("() => (document.querySelector('main[data-screen=routes]') || {dataset: {}}).dataset.routesReady === 'yes'", timeout=60000)
    await settle(pl.pg, 600)


async def type_into(pg, sel, value):
    """Types into a box and presses Enter, which saves it (as leaving the box does)."""
    await pg.fill(sel, value)
    await pg.press(sel, "Enter")


async def until(pg, read, ok, seconds=20):
    """Reads the page until ok(what it read), or gives up; returns the last read (the new planner reads again after a
    save, so its page can show the old rows for a moment)."""
    end = time.monotonic() + seconds
    while True:
        got = await pg.evaluate(read)
        if ok(got) or time.monotonic() > end:
            return got
        await asyncio.sleep(0.3)


def legs_of(rot):
    return json.loads(psql(f"select coalesce(json_agg(json_build_object('id', id, 'leg_no', leg_no, 'days', days_utc, 'dep', dep_utc_min, 'block', block_min) "
                           f"order by leg_no), '[]') from public.flight_legs where rotation_id = {int(rot)}").strip())


def local_times(d):
    """A route's frequencies' days and four local times, as its form shows them."""
    return [{k: v.split(" [")[0] for k, v in f["form"].items() if k in ("days", "depHub", "arrDest", "depDest", "arrHub")} for f in (d or {}).get("freqs", [])]


async def old_shows(old, new, al, hub, dest, label):
    """The old planner, opened again, shows the route as the new one does (header, lines, pills and form)."""
    await old.reopen()
    await old.view(al["name"], {"bases": [hub]}, route=f"{al['name']}|{hub}|{dest}")
    o = await old.pg.evaluate(READ_DETAIL)
    n = await new.pg.evaluate(READ_DETAIL)
    return [f"the old planner, opened again: {x}" for x in compare_detail(o, n, f"{al['code']} {hub}–{dest} ({label})")], o, n


async def real_saves(old, new, al):
    out = []
    pg, client = new.pg, await new.pg.evaluate("window.__eqPlanner.client")
    name, code, aid, hub = al["name"], al["code"], al["id"], al["bases"][0]
    dest = psql(f"""select coalesce(min(a.code), '') from public.airports a where a.lat is not null and a.lon is not null and a.utc_offset is not null
                     and a.code <> :'h' and length(a.code) = 3
                     and not exists (select 1 from public.routes r where r.airline_id = {int(aid)} and r.hub_code = :'h' and r.dest_code = a.code)
                     and not exists (select 1 from public.airline_bases b where b.airport_code = a.code)""", h=hub).strip()
    mkts = [m for m in psql(f"select name from public.markets where airline_id = {int(aid)} order by name").splitlines() if m]
    if not dest or len(mkts) < 2:
        return [("real saves", [f"no airport to add a route to ({dest!r}) or fewer than two markets for {code}"])]

    # add a route by the form
    await new_go(new, "/routes" + query({"airline": code, "bases": [hub]}))
    n0, mark = counts(), marks()
    await pg.click("#add-route-btn")
    await pg.select_option("#r-hub", hub)
    await pg.fill("#r-dest", dest)
    await pg.select_option("#r-market", mkts[0])
    await pg.click("#r-add")
    await wait_saved(new, mark)
    problems, _ = logged(mark, {("routes", None)}, client, Counter({("routes", "insert"): 1}))
    row = json.loads(psql(f"select coalesce((select to_json(r) from public.routes r where r.airline_id = {int(aid)} and r.hub_code = :'h' and r.dest_code = :'d'), 'null')",
                          h=hub, d=dest).strip())
    if not row or row.get("source") != "added" or not row.get("distance_km") or not row.get("city"):
        problems.append("the route isn't in the copy as added, with its city and distance from the airport list")
    problems += count_changes(n0, counts(), allow={"public.change_log", "public.routes"})
    try:
        await pg.wait_for_selector(f"[data-route-detail='{hub}-{dest}']", timeout=30000)
    except Exception:
        problems.append("the new planner didn't open the route")
    out.append((f"add a route ({code} {hub}–{dest}, {mkts[0]}) by the form: one routes row, added, its city and distance from the airport list, "
                "logged as planner with the tab's ID; the new planner opens it", problems))
    if not row:
        return out
    route_id = row["id"]

    # edit its stars and its market
    await pg.click("#edit-route")
    for field, value, col in (("stars", "5", "stars_override"), ("market", mkts[1], "market_override_id")):
        mark = marks()
        await pg.select_option(f"[data-rk={field}]", value)
        await wait_saved(new, mark)
        problems, rows = logged(mark, {("routes", str(route_id))}, client, Counter({("routes", "update"): 1}))
        if rows and col not in rows[0]["fields"]:
            problems.append(f"{col} isn't among what changed: {rows[0]['fields']}")
        out.append((f"edit its {field} ({value}): one update of the route's {col}, logged as planner with the tab's ID", problems))
    await pg.click("#edit-route")

    # add a frequency, then type its days and times one box at a time, each box one action
    mark = marks()
    await pg.click("#add-freq")
    await wait_saved(new, mark, 3)
    problems, _ = logged(mark, {("rotations", None), ("flight_legs", None)}, client, Counter({("rotations", "insert"): 1, ("flight_legs", "insert"): 2}))
    rot = psql(f"select coalesce(max(id)::text, '') from public.rotations where route_id = {int(route_id)}").strip()
    rk = psql(f"select coalesce(legacy_key, '') from public.rotations where id = {int(rot or 0)}").strip()
    if not re.fullmatch(r"[0-9a-z]{7}", rk):
        problems.append(f"its old-planner id isn't made as the old planner makes one: {rk!r}")
    out.append(("add a frequency: a rotation and its two legs as one action (the next free numbers, every day, no times yet), logged as planner "
                "with the tab's ID", problems))
    if not rot:
        return out
    legs = legs_of(rot)
    allowed = {("flight_legs", str(x["id"])) for x in legs}
    sel = lambda k: f".freq[data-rotation='{rot}'] [data-k={k}]"
    times = (("days", "135"), ("depHub", "07:00"), ("arrDest", "09:10"), ("depDest", "10:20"), ("arrHub", "12:40"))
    problems = []
    for k, v in times:
        mark = marks()
        await type_into(pg, sel(k), v)
        await wait_saved(new, mark)
        p2, _ = logged(mark, allowed, client)
        problems += [f"{k}: {x}" for x in p2]
    form_js = f"() => Object.fromEntries([...document.querySelectorAll(\".freq[data-rotation='{rot}'] .fg [data-k]\")].map(i => [i.dataset.k, i.value]))"
    form = await until(pg, form_js, lambda f: all(f.get(k) == v for k, v in times))
    problems += [f"the new planner shows {k} {form.get(k)!r}, typed {v!r}" for k, v in times if form.get(k) != v]
    p2, o, _ = await old_shows(old, new, al, hub, dest, "after typing its times")
    problems += p2
    if typed(((o or {}).get("freqs") or [{"form": {}}])[0]["form"]).get("depHub") != "07:00":
        problems.append("the old planner doesn't show the 07:00 departure")
    out.append(("type its days (135) and four times (local), each box one action changing only its two legs, logged as planner with the tab's ID; "
                "the old planner, opened again, shows the same route and frequency with the same times", problems))

    # change its time
    mark = marks()
    await type_into(pg, sel("depHub"), "07:30")
    await wait_saved(new, mark)
    problems, _ = logged(mark, allowed, client)
    await until(pg, form_js, lambda f: f.get("depHub") == "07:30")
    p2, o, _ = await old_shows(old, new, al, hub, dest, "after its new time")
    problems += p2
    if typed(((o or {}).get("freqs") or [{"form": {}}])[0]["form"]).get("depHub") != "07:30":
        problems.append("the old planner doesn't show the 07:30 departure")
    out.append(("change its departure to 07:30: only its legs, logged as planner with the tab's ID; the old planner, opened again, shows 07:30", problems))

    # delete it: asked in the page
    mark, d0 = marks(), len(new.dialogs)
    await pg.click(f".freq[data-rotation='{rot}'] button[data-del]")
    await pg.click(f".freq[data-rotation='{rot}'] [data-confirm-yes]")
    await wait_saved(new, mark, 3)
    problems, _ = logged(mark, allowed | {("rotations", rot)}, client, Counter({("flight_legs", "delete"): 2, ("rotations", "delete"): 1}))
    if len(new.dialogs) > d0:
        problems.append("a browser dialog was opened: " + "; ".join(new.dialogs[d0:]))
    out.append(("delete it (the page asks \"Remove this frequency?\" itself): its two legs and its rotation as one action, logged as planner with the tab's ID", problems))

    # remove the route
    mark = marks()
    await pg.wait_for_selector(f".freq[data-rotation='{rot}']", state="detached", timeout=30000)
    await pg.click("#rm-route")
    await pg.click(".qpanel [data-confirm-yes]")
    await wait_saved(new, mark)
    problems, _ = logged(mark, {("routes", str(route_id))}, client, Counter({("routes", "update"): 1}))
    if psql(f"select coalesce((select removed::text from public.routes where id = {int(route_id)}), 'deleted')").strip() != "true":
        problems.append("the route isn't removed (removed, not deleted) in the copy")
    await old.reopen()
    if await old.run(f"M.routeMap.has({json.dumps(f'{name}|{hub}|{dest}')})"):
        problems.append("the old planner still lists the route")
    out.append(("remove the route (the page asks itself): removed, never deleted, one update logged as planner with the tab's ID; the old planner, "
                "opened again, no longer lists it", problems))

    # an offset on an airport only one flight uses (and no plan card leaves): the page lists what moves and asks; then put back
    pick = psql(f"""select coalesce((select json_build_object('code', a.code, 'rot', min(l.rotation_id), 'airline', min(ro.airline_id),
                            'hub', min(ro.hub_code), 'dest', min(ro.dest_code), 'off', min(a.utc_offset))
                      from public.airports a
                      join public.flight_legs l on a.code in (l.origin_code, l.dest_code)
                      left join public.rotations rt on rt.id = l.rotation_id left join public.routes ro on ro.id = rt.route_id
                     where a.utc_offset is not null and a.utc_offset between -11 and 13
                       and not exists (select 1 from public.airline_bases b where b.airport_code = a.code)
                       and not exists (select 1 from public.plan_card_legs pc where pc.origin_code = a.code)
                       and not exists (select 1 from public.world_airports wa where wa.world_id = {WORLD} and wa.airport_code = a.code
                                         and wa.utc_offset_override is not null)
                     group by a.code having count(distinct l.rotation_id) = 1 and count(l.rotation_id) = count(*)
                     order by a.code limit 1)::text, '')""").strip()
    if not pick:
        out.append(("change an offset on an airport one flight uses", ["the copy has no airport that only one flight uses"]))
        return out
    x = json.loads(pick)
    xal = next((a for a in COPY["airlines"] if a["id"] == x["airline"]), None)
    if not xal:
        out.append(("change an offset on an airport one flight uses", [f"its flight isn't one of our airlines' ({x['code']})"]))
        return out
    legs0 = legs_of(x["rot"])
    route_at = f"/routes/{xal['code']}/{x['hub']}-{x['dest']}"
    await new_go(new, route_at, detail=f"{x['hub']}-{x['dest']}")
    before = await new.pg.evaluate(READ_DETAIL)
    off = float(x["off"])
    put = "%g" % (off + 1)
    utc_box = f".dsub input[data-utc='{x['code']}']"
    mark, d0 = marks(), len(new.dialogs)
    await type_into(pg, utc_box, put)
    await pg.wait_for_selector(".qpanel [data-confirm-yes]", timeout=30000)
    question = await pg.text_content(".qpanel") or ""
    moves = await pg.evaluate("[...document.querySelectorAll('.qpanel [data-offset-moves] li')].map(l => l.textContent)")
    await pg.click(".qpanel [data-confirm-yes]")
    await wait_saved(new, mark, 2)
    allowed = {("world_airports", None)} | {("flight_legs", str(l["id"])) for l in legs0}
    problems, rows = logged(mark, allowed, client)
    if not any(r["table"] == "world_airports" for r in rows) or not any(r["table"] == "flight_legs" for r in rows):
        problems.append(f"expected the airport's row and its flight's legs: {dict(Counter((r['table'], r['op']) for r in rows))}")
    if not moves or "move" not in question:
        problems.append(f"the question doesn't list what moves ({len(moves)} line(s))")
    if len(new.dialogs) > d0:
        problems.append("a browser dialog was opened")
    after = await until(pg, READ_DETAIL, lambda d: f"{x['code']}={put}" in (d or {}).get("utc", []) and local_times(d) == local_times(before))
    if local_times(after) != local_times(before):
        problems.append(f"the local times moved: before {local_times(before)}, after {local_times(after)}")
    p2, o, _ = await old_shows(old, new, xal, x["hub"], x["dest"], "after the offset change")
    problems += p2
    if local_times(o) != local_times(before):
        problems.append(f"the old planner's local times aren't the ones before the change: {local_times(o)} against {local_times(before)}")
    out.append((f"change {x['code']}'s offset from {off:g} to {put} on {xal['code']} {x['hub']}–{x['dest']}: the page lists what moves ({len(moves)} leg(s)) "
                "and asks in itself; the airport's row and only that flight's legs change, logged as planner with the tab's ID; the local times stay, "
                "in both planners", problems))

    mark = marks()
    await type_into(pg, utc_box, "")
    await pg.wait_for_selector(".qpanel [data-confirm-yes]", timeout=30000)
    await pg.click(".qpanel [data-confirm-yes]")
    await wait_saved(new, mark, 2)
    problems, _ = logged(mark, allowed, client)
    if legs_of(x["rot"]) != legs0:
        problems.append(f"the legs aren't back as they were: {legs_of(x['rot'])} against {legs0}")
    back = await until(pg, READ_DETAIL, lambda d: f"{x['code']}={off:g}" in (d or {}).get("utc", []))
    if f"{x['code']}={off:g}" not in (back or {}).get("utc", []):
        problems.append(f"the new planner shows {(back or {}).get('utc')}, not the game's {off:g}")
    out.append((f"put it back (the box emptied: the game's offset, {off:g}): the legs exactly as before, logged as planner with the tab's ID", problems))
    return out


# ---------- 6. a preview
async def preview(p, port, env, facts, staff, moment, seen, al, route):
    pv = pn.Planner(p, port, env, facts)
    seen.append(pv)
    problems = []
    try:
        await pv.open(host="127.0.0.1", moment=moment)
        await pv.pg.emulate_media(reduced_motion="reduce")   # STILL
        await pv.sign_in(*staff)
        hub, dest = route
        await new_go(pv, f"/routes/{al['code']}/{hub}-{dest}", detail=f"{hub}-{dest}")
        n0, mark = counts(), marks()
        await pv.pg.click("#add-freq")
        await settle(pv.pg, 600)
        await pv.pg.click("#edit-route")
        await pv.pg.select_option("[data-rk=stars]", "1" if not await pv.pg.evaluate("document.querySelector('[data-rk=stars]').value === '1'") else "2")
        await settle(pv.pg, 600)
        await type_into(pv.pg, ".freq [data-k=notes]", "preview check")
        await settle(pv.pg, 1200)
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
    return (f"a preview address (127.0.0.1) shows Routes, and Add frequency, an edit of the route and a typed note there send no write "
            f"(it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})"), problems


# ---------- 7. a phone, and the screenshots
async def phone(p, port, env, facts, staff, moment, seen, al, route):
    ph = pn.Planner(p, port, env, facts, width=380, height=800)
    seen.append(ph)
    problems = []
    scroll = "Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth"
    try:
        await ph.open(moment=moment)
        await ph.pg.emulate_media(reduced_motion="reduce")   # STILL
        await ph.sign_in(*staff)
        await new_go(ph, "/routes" + query({"airline": al["code"]}))
        if (over := await ph.pg.evaluate(scroll)) > 0:
            problems.append(f"the list scrolls sideways by {over} px at 380 px wide")
        hub, dest = route
        await new_go(ph, f"/routes/{al['code']}/{hub}-{dest}", detail=f"{hub}-{dest}")
        await ph.pg.evaluate("document.querySelectorAll('details.cx').forEach(d => d.open = true)")
        await settle(ph.pg, 300)
        if (over := await ph.pg.evaluate(scroll)) > 0:
            problems.append(f"the route (its connections open) scrolls sideways by {over} px at 380 px wide")
        if not await ph.pg.evaluate("getComputedStyle(document.querySelector('#routelist')).display === 'none'"):
            problems.append("on a phone the list doesn't give way to the route")
        problems += ph.errors
    finally:
        await ph.close()
    return ("at 380 px wide the list and a route (its connections open) have no sideways scroll and no errors; the route takes the page, "
            "as in the old planner"), problems


async def screenshots(old, new, al, route):
    if not SCREENS_DIR:
        return
    Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    hub, dest = route
    for width, height in ((1280, 900), (380, 800)):
        await old.pg.set_viewport_size({"width": width, "height": height})
        await new.pg.set_viewport_size({"width": width, "height": height})
        for what, r in (("list", None), ("route", f"{al['name']}|{hub}|{dest}")):
            await old.view(al["name"], {"bases": [al["bases"][0]] if r is None else [hub]}, route=r)
            await settle(old.pg, 500)
            await old.pg.screenshot(path=str(Path(SCREENS_DIR) / f"old-routes-{what}-{width}.png"), full_page=True, timeout=90000)
            if r is None:
                await new_go(new, "/routes" + query({"airline": al["code"]}))
            else:
                await new_go(new, f"/routes/{al['code']}/{hub}-{dest}", detail=f"{hub}-{dest}")
            await settle(new.pg, 500)
            await new.pg.screenshot(path=str(Path(SCREENS_DIR) / f"routes-{what}-{width}.png"), full_page=True, timeout=90000)
    await old.pg.set_viewport_size({"width": 1440, "height": 1000})
    await new.pg.set_viewport_size({"width": 1280, "height": 900})


# ---------- what the copy holds
def read_copy(moment):
    """Our airlines (with their bases and focus cities), the flown routes and the first unflown one of each airline, the
    routes' loads at the moment, and which flights have an estimated time."""
    airlines = json.loads(psql(f"""select coalesce(json_agg(json_build_object('id', a.id, 'code', a.iata_code,
              'name', coalesce(a.planner_name, a.public_name, a.game_name, 'Airline ' || a.game_id),
              'bases', (select coalesce(json_agg(b.airport_code order by b.position nulls last, b.id), '[]') from public.airline_bases b where b.airline_id = a.id),
              'focus', (select coalesce(json_agg(b.airport_code order by b.position nulls last, b.id), '[]') from public.airline_bases b
                         where b.airline_id = a.id and b.role = 'focus'))
              order by a.position nulls last, a.id), '[]')
              from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id where g.kind = 'ours' and a.world_id = {WORLD}""").strip())
    names = {a["id"]: a["name"] for a in airlines}
    flown, route_ids = {}, {}
    for aid, h, d, rid in json.loads(psql(f"""select coalesce(json_agg(json_build_array(r.airline_id, r.hub_code, r.dest_code, r.id) order by r.hub_code, r.dest_code), '[]')
              from public.routes r where r.world_id = {WORLD} and not r.removed and exists (select 1 from public.rotations o where o.route_id = r.id)""").strip()):
        if aid in names:
            flown.setdefault(names[aid], []).append((h, d))
            route_ids[(names[aid], h, d)] = rid
    unflown = {}
    for al in airlines:
        if al["bases"]:
            u = psql(f"""select coalesce(min(r.dest_code), '') from public.routes r where r.airline_id = {int(al['id'])} and r.hub_code = :'h' and not r.removed
                          and not exists (select 1 from public.rotations o where o.route_id = r.id)""", h=al["bases"][0]).strip()
            if u:
                unflown[al["name"]] = [(al["bases"][0], u)]
    loads = {(int(x[0]), f"{x[1]}-{x[2]}"): float(x[3]) for x in json.loads(psql(
        f"""select coalesce(json_agg(json_build_array(x ->> 'airline_id', x ->> 'hub', x ->> 'dest', (x ->> 'sum')::numeric / (x ->> 'departures')::numeric)), '[]')
              from jsonb_array_elements(private.fig_route_loads({WORLD}, :'m'::timestamptz) -> 'routes') x""", m=moment).strip())}
    est = json.loads(psql(f"""select json_build_object(
              'routes', coalesce(json_agg(distinct ro.hub_code || '-' || ro.dest_code), '[]'), 'flights', coalesce(json_agg(distinct l.flight_no::text), '[]'))
              from public.flight_legs l join public.rotations rt on rt.id = l.rotation_id join public.routes ro on ro.id = rt.route_id
             where l.world_id = {WORLD} and l.dep_utc_min is not null and l.block_min is null""").strip())
    mct = {c: (None if m is None else int(m)) for c, m in json.loads(psql(f"""select coalesce(json_agg(json_build_array(wa.airport_code, wa.mct_min)), '[]')
              from public.world_airports wa where wa.world_id = {WORLD}""").strip())}
    codes = sorted(set(json.loads(psql(f"""select coalesce(json_agg(distinct c), '[]') from (select origin_code c from public.flight_legs where world_id = {WORLD}
              union select dest_code from public.flight_legs where world_id = {WORLD}) x""").strip())))
    COPY.update(airlines=airlines, loads=loads, est_routes=set(est["routes"] or []), est_flights=set(est["flights"] or []), mct=mct, codes=codes)
    return airlines, flown, unflown, route_ids


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

    # ---------- 1. the moment
    moment = psql("select to_char((max(captured_at) + interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') from public.game_capture_raw").strip()
    try:
        held = set_aside(psql, moment)
        atexit.register(lambda: put_back(psql, held))
        problems = []
    except Exception as e:
        held, problems = {}, [why(e)]
    step(not problems, f"the moment: {moment} (the copy's latest capture plus one hour); typed loads and day flags entered after it set aside until "
         "the test ends (" + ", ".join(f"{t}: {len(json.loads(held.get(t) or '[]'))}" for t in HELD) + ")", problems)
    if problems:
        sys.exit(1)
    try:
        airlines, flown, unflown, route_ids = read_copy(moment)
        problems = [] if airlines and flown else ["the copy has none of our airlines or no flown route"]
    except Exception as e:
        problems = [why(e)]
    step(not problems, f"the copy: {len(COPY.get('airlines', []))} of our airlines, "
         f"{sum(len(v) for v in (flown if not problems else {}).values())} flown routes "
         f"({', '.join(f'{a['code']} {len(flown.get(a['name'], []))}' for a in COPY.get('airlines', []))}), "
         f"{len(COPY.get('est_routes', []))} with an estimated time", problems)
    if problems:
        sys.exit(1)

    tag = secrets.token_hex(4)
    staff = (f"routes-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="routes-side-by-side-"))
    seen = []
    first = next(a for a in airlines if flown.get(a["name"]))
    r0 = flown[first["name"]][0]
    try:
        root = web_copy(work)
        with serve(root) as port:
            async with async_playwright() as p:
                # ---------- 2. both planners at the moment
                old = OldRoutes(p, port, env, facts, lib_js, moment=moment)
                new = pn.Planner(p, port, env, nfacts, width=1280, height=900)
                seen += [old, new]
                try:
                    n0, mark = counts(), marks()
                    await old.open()
                    await old.sign_in(*staff)
                    await old.ready()
                    await new.open(moment=moment)
                    await new.pg.emulate_media(reduced_motion="reduce")   # STILL
                    await new.sign_in(*staff)
                    await new_go(new, "/routes")
                    await set_mode(old, new, "local")
                    problems = list(old.errors) + list(new.errors)
                    if log_since(mark):
                        problems.append("opening the planners changed the tables")
                    problems += count_changes(n0, counts())
                    if abs(await new.pg.evaluate("Date.now()") - ms(moment)) > 1000:
                        problems.append("the new planner's clock isn't frozen at the moment")
                    if await new.pg.evaluate("!!document.querySelector('main[data-screen=routes] [data-not-built]')"):
                        problems.append("Routes is still a placeholder")
                    # the minimum connection time at each airport our flights use: the old planner's (mctAt) against the library's
                    old_mct = json.loads(await old.run(f"JSON.stringify(Object.fromEntries({json.dumps(COPY['codes'])}.map(c => [c, M.mctAt(c)])))"))
                    COPY["mct_differs"] = {c: (old_mct.get(c), COPY["mct"].get(c) or 90) for c in COPY["codes"]
                                           if old_mct.get(c) != (COPY["mct"].get(c) or 90)}
                except Exception as e:
                    problems = [why(e)] + old.errors[:3] + new.errors[:3]
                step(not problems, "both planners opened at the moment, signed in as test staff, in local time, the new one on Routes; opening them wrote nothing", problems)
                if problems:
                    sys.exit(1)
                print(f"      the minimum connection time differs at {len(COPY['mct_differs'])} airport(s): "
                      + ", ".join(f"{c} (old {a}, library {b})" for c, (a, b) in sorted(COPY["mct_differs"].items())[:12]), flush=True)

                # ---------- 3 and 4. side by side
                t = time.monotonic()
                try:
                    label, problems = await lists(old, new, airlines)
                except Exception as e:
                    label, problems = "every airline's list", [why(e)]
                step(not problems, label + f" ({time.monotonic() - t:.0f} s)", problems + new.errors[:3] + old.errors[:3])
                try:
                    await screenshots(old, new, first, r0)
                except Exception as e:
                    print(f"      the screenshots: {why(e)}", flush=True)
                t = time.monotonic()
                n_routes, n_freqs, problems = await routes_side_by_side(old, new, airlines, flown, "local")
                step(not problems, f"every flown route equals the old Routes' in local time ({n_routes} routes, {n_freqs} frequencies: the header with its offsets, "
                     f"estimated block, plan, service and banks; the loads; both lines of each frequency with times both ways, block and est, day markers and "
                     f"each flight's load; every pill and its words; the connections at both ends; the form) ({time.monotonic() - t:.0f} s)",
                     problems + new.errors[:3] + old.errors[:3])
                try:
                    await set_mode(old, new, "utc")
                    n_routes, n_freqs, problems = await routes_side_by_side(old, new, airlines, {k: v[:UTC_SAMPLE] for k, v in flown.items()}, "UTC")
                    await set_mode(old, new, "local")
                except Exception as e:
                    n_routes, n_freqs, problems = 0, 0, [why(e)]
                step(not problems, f"in UTC, the same for {n_routes} flown routes ({n_freqs} frequencies; the old planner's mode set without saving it)",
                     problems + new.errors[:3] + old.errors[:3])
                n_routes, _, problems = await routes_side_by_side(old, new, airlines, unflown, "not flown")
                step(not problems, f"the first unflown route of each airline ({n_routes}): its header and the next free numbers equal the old Routes'", problems)
                t = time.monotonic()
                try:
                    n, problems = await popups(old, new, airlines, flown, route_ids)
                except Exception as e:
                    n, problems = 0, [why(e)]
                step(not problems and n > 0, f"the route pop-up Home's map opens equals the old one ({n} routes: distance, demand, flights a day, loads, "
                     "signal, every frequency with its times, days, aircraft and bank fit, market and city, Open in Routes) "
                     f"({time.monotonic() - t:.0f} s)", problems or ["no route compared"])
                t = time.monotonic()
                try:
                    n, problems = await tail_popups(old, new)
                except Exception as e:
                    n, problems = 0, [why(e)]
                step(not problems and n > 0, f"a frequency's aircraft on Routes opens its pop-up (in the address), equal to the old tailModal ({n} aircraft, one an "
                     f"airline: base, block a day, legs a week, maintenance, the one-week check, the issues, its flights) ({time.monotonic() - t:.0f} s)",
                     problems or ["no aircraft compared"])
                for k, v in KNOWN.items():
                    where = f" (e.g. {'; '.join(v['where'][:4])})" if v["where"] else ""
                    print(f"      known difference \"{k}\": used {v['used']} time(s){where}. {v['rule']}"[:1800], flush=True)

                # ---------- 5. real saves
                try:
                    for label, problems in await real_saves(old, new, first):
                        step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                except Exception as e:
                    step(False, "real saves in the new Routes", [why(e)] + new.errors[:3] + old.errors[:3])
                await old.close()
                await new.close()

                # ---------- 6 and 7
                for check in (preview, phone):
                    try:
                        label, problems = await check(p, port, env, nfacts, staff, moment, seen, first, r0)
                    except Exception as e:
                        label, problems = check.__name__, [why(e)]
                    step(not problems, label, problems)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    # ---------- 8. nothing went outside
    outside = sorted({h for x in seen for h in x.outside})
    stopped = ", ".join(sorted({h for x in seen for h in x.stopped})) or "nothing"
    step(not outside, f"nothing went outside ({sum(x.copy for x in seen)} requests answered by the copy, {sum(x.local for x in seen)} "
                      f"from the local server; stopped: {stopped})", ["reached: " + ", ".join(outside)] if outside else [])
    print(f"\n{len(failures)} Routes side-by-side step(s) failed" if failures else "\nRoutes side by side: all passed", flush=True)
    print(f"      the Routes side by side took {time.monotonic() - started:.0f} s", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
