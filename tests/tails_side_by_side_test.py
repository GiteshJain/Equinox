"""The new planner's Tails side by side with the old Tails on the rehearsal's copy (decision #18, build pull request 7,
spec docs/specs/2026-10-13-tails.md, "Checks"): the pull request's own new planner (built into web/app/) and the old
planner (web/planner/), both at their live addresses, signed in as the same test staff user, at the same frozen moment,
reading a full local copy of Supabase restored from last night's backup.

Run by database/rehearse.sh, last (after the Routes side by side). Like tests/routes_side_by_side_test.py it uses
tests/real_saves_test.py's helpers and request mapping, needs the copy, so it isn't part of tests/run_all.sh, and nothing
goes outside. /api/game-schedule is answered from a saved sample (tests/fixtures/schedule_113.expected.json, the
function's answer for a saved game page), with the filed aircraft's plan-card flights put in as the game would show them.

1. The moment: the copy's latest capture plus one hour, as tests/captured_figures_test.py takes it.
2. Both planners open at the moment (the old one from a copy of web/ with captured_figures_test.py's hook, so the test
   can set its screen's state and call its own functions; web/planner/ itself is unchanged). Opening them writes nothing.
3. For every airline, the list: every row (tail and its red dot, type, cabin, base, legs a week, block hours a day,
   maintenance with its hours, routes), the count and the chips; and the rows each filter leaves (each base, each type,
   Flying, No flights, Needs a look).
4. For every aircraft in service, its page: the header with its figures and maintenance, the fields and their values
   (the choices offered compared too), the week strip (every bar: day, place, width, colour, words), its legs by flight
   number (days, times, duration, ground to next, the turn or gap), and its issues against the old tailIssues(). The
   aircraft pop-up Home opens (?aircraft=), for a sample, against the old tailModal.
5. For every airline, the deliveries board (the old renderDeliveries) with each status filter, and every plan card on it
   (the old planCard).
6. Filing one arrived aircraft from its plan card, twice: with the game answering "matches" (it files at once) and
   "differs" (File with the game's times). Each time the new planner files first, the old planner (opened again) shows
   the aircraft flying the same frequencies, the copy is put back, and the old planner files the same card the same way:
   both write the same rows (the aircraft, its first cabin fit, every rotation and leg, the card's legs).
7. Add a tail, change its maintenance gap and base, and remove it, through the new Tails' own controls: each writes only
   its row, logged as planner with the tab's ID; the old planner, opened again, shows each.
8. A preview address (127.0.0.1) shows Tails, and Add a tail, an edit and File into planner there send no write.
9. At 380 px wide the list (as cards), an aircraft and the deliveries have no sideways scroll and no errors. Screenshots of
   the list and an aircraft, new and old, at 380 and 1280 px go to TAILS_SCREENS_DIR (the run's tails-screens artifact).
   Home's "Open fleet ›" and "File into planner" open Tails.
10. Nothing went outside.

A difference fails and names the airline, the aircraft and both values, unless it is a known difference (KNOWN below,
each with its rule), printed with how often it was used and examples. Prints registrations, codes, flight numbers, counts
and the screens' words, never anything else from the rows, since the log is posted on the pull request; never the local
keys or the test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL, SECRET_TABLES and TAILS_SCREENS_DIR.
Usage: python3 tests/tails_side_by_side_test.py
"""
import asyncio, json, os, secrets, shutil, sys, tempfile, time
from collections import Counter
from pathlib import Path
from harness import FIX, LIVE_HOST, serve, settle
from playwright.async_api import async_playwright
import real_saves_test as rs
from real_saves_test import count_changes, counts, is_planner_user, library, local_env, log_since, make_user, marks, planner_facts, psql, token_for, why
import planner_next_test as pn
from captured_figures_test import ms
from home_side_by_side_test import web_copy

SCREENS_DIR = os.environ.get("TAILS_SCREENS_DIR")
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"
POPUP_SAMPLE = 2      # aircraft per airline whose pop-up is compared
failures = []
started = time.monotonic()
COPY = {}
ARRIVAL = "the plan card's arrival"
CARD_COPY = "the card's copy of its legs"

KNOWN = {
    "block estimates": {
        "rule": "a leg without a typed arrival takes the estimate: the old planner fitted its estimates to the times typed in (estBlockFor); "
                "the library uses 25 min + distance ÷ the type's speed (manual §4, #19 spec §5, as tests/rules_library_test.py allows). Only on "
                "an aircraft one of whose legs has an estimated block; everything that follows from it there (block hours, maintenance, the "
                "strip, arrivals and gaps, issues) may differ with it.",
        "used": 0, "where": []},
    "choices offered": {
        "rule": "the types an aircraft may have come from airline_aircraft_types (the old planner's BUY_TYPES) and its cabins from the "
                "layouts' cabins (Standard for a low-cost airline, every other cabin for the rest), not the old Tails' name patterns "
                "(typesFor, configsFor) typed into its code (design §2: one source). Only the options of the Type and Config boxes; the "
                "values shown must be the same.",
        "used": 0, "where": []},
    "remove a delivery": {
        "rule": "the old deliveries board (renderDeliveries, no longer shown by the old Tails) has a remove link on each row; the spec "
                "asks the new board for the deliveries, their status filters and plan cards, not for removing an order, so the "
                "actions cell is compared without it.",
        "used": 0, "where": []},
    ARRIVAL: {
        "rule": "filing with the game's times, the old planner sets the card's arrival to the game's but stores only its departure and "
                "its old block (plan_card_legs.block_min), so the card loses the game's arrival when it is read again; the new planner "
                "stores the game's arrival (the spec: the card takes the game's times). Only block_min, only on a card leg whose "
                "game block differs.",
        "used": 0, "where": []},
    CARD_COPY: {
        "rule": "the old planner's storage keeps a plan card's legs whole in plan_cards.extra.legs when its leg rows can't give them "
                "back as typed; filing with the game's times, the old card's legs gain the game's weekdays (and the game's arrival "
                "beside the old block), so its save writes that copy. The new planner keeps the game's departure, arrival and "
                "weekdays in the leg rows themselves (dep_utc_min, block_min, days_utc) and no copy; the old planner, opened "
                "again, shows the card's legs with the same times and days either way (compared below). Only the card's "
                "extra.legs and the one plan_cards update that writes it.",
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


# ---------- reading either Tails: the new one draws the old one's markup, so one reader serves both
READ = r"""() => {
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const pill = p => (p ? [...p.classList].sort().join(" ") + "|" + (p.title || "") + "|" + T(p) : "");
  function readList() {
    const rows = [...document.querySelectorAll("tr[data-tail]")].map(tr => { const td = [...tr.querySelectorAll("td")];
      return { reg: tr.dataset.tail, cells: td.slice(0, 8).map(T), dot: !!tr.querySelector(".dot"), maint: pill(td[6] && td[6].querySelector(".pill")) }; });
    // the chips by their label: {"Base": ["*All", "JFK"], "Type": [...], "Status": [...]}
    const chips = {};
    for (const c of document.querySelectorAll(".chips")) {
      if (!c.querySelector("[data-tf]")) continue;
      let at = "";
      for (const e of c.children) {
        if (e.classList.contains("chiplbl")) { at = T(e); chips[at] = []; }
        else if (e.classList.contains("chip") && at) chips[at].push((e.classList.contains("on") ? "*" : "") + T(e));
      }
    }
    return { count: T(document.querySelector(".toolbar .count")), rows, chips };
  }
  function readDetail() {
    const d = document.querySelector("#detail");
    if (!d) return null;
    const h = d.querySelector(".dhead");
    return {
      h2: T(h && h.querySelector("h2")), dsub: T(h && h.querySelector(".dsub")), maint: pill(h && h.querySelector(".dsub .pill")),
      fields: [...d.querySelectorAll(".fg [data-tk]")].map(i => ({ k: i.dataset.tk, v: i.value, opts: i.tagName === "SELECT" ? [...i.options].map(o => o.value) : null })),
      labels: [...d.querySelectorAll(".fg label")].map(l => (l.firstChild && l.firstChild.nodeType === 3 ? l.firstChild.textContent : "").trim()),
      del: T(d.querySelector("[data-tdel]")),
      axis: [...d.querySelectorAll(".wk-axis span")].map(s => T(s) + "@" + s.style.left),
      bars: [...d.querySelectorAll(".wk-row")].map(r => T(r.querySelector(".wk-day")) + ": " + [...r.querySelectorAll(".leg")]
        .map(l => [l.classList.contains("bad") ? "bad" : "ok", l.style.left, l.style.width, l.title, T(l)].join("~")).sort().join(" ; ")),
      note: T(d.querySelector(".note")),
      table: [...d.querySelectorAll("table.tbl tr")].map(tr => [...tr.children].map(T).join(" | ")),
      pills: [...d.querySelectorAll("table.tbl .pill")].map(p => pill(p)),
      empty: T(d.querySelector(".empty")),
      issues: [...d.querySelectorAll(".ckb .pill")].map(T),
    };
  }
  function readPopup(root) {
    const m = (root || document).querySelector(".modal");
    if (!m) return null;
    return { head: T(m.querySelector(".mhead > div")), stats: [...m.querySelectorAll(".mstats > div")].map(T),
             statPills: [...m.querySelectorAll(".mstats .pill")].map(p => pill(p)), issues: [...m.querySelectorAll(".ckb .pill")].map(p => pill(p)),
             rows: [...m.querySelectorAll(".mbody table tr")].map(tr => [...tr.children].map(T).join(" | ")), empty: T(m.querySelector(".mbody > .dim")),
             foot: [...m.querySelectorAll(".mfoot button")].map(T) };
  }
  function readBoard(b) {
    if (!b) return null;
    return { head: T(b.querySelector("h3.rh")), dim: T(b.querySelector(":scope > .dim")),
      chips: [...b.querySelectorAll(".chips .chip")].map(c => (c.classList.contains("on") ? "*" : "") + T(c)), showing: T(b.querySelector(".chips .dim")),
      rows: [...b.querySelectorAll("table.tbl tr:not(.planrow)")].filter(tr => !tr.closest(".pcard")).map(tr => { const td = [...tr.children];
        return { cells: td.slice(0, 7).map(T), status: pill(td[6] && td[6].querySelector(".pill")), actions: T(td[7]), card: !!(td[7] && td[7].querySelector("[data-plancard]")) }; }) };
  }
  function readCard(c) {
    if (!c) return null;
    return { head: T(c.querySelector(".pch")), rows: [...c.querySelectorAll("table tr")].map(tr => [...tr.children].map(T).join(" | ")),
             foot: T(c.querySelector(".pfoot")), file: !!c.querySelector("[data-planfile]"), filed: !!c.querySelector(".pfoot .pill.ok") };
  }
"""
READ_CHECK = READ + """const m = document.querySelector(".modal"); if (!m) return null;
  return { head: T(m.querySelector(".mhead > div")), paras: [...m.querySelectorAll(".mbody p")].map(T),
           rows: [...m.querySelectorAll(".mbody table tr")].map(tr => [...tr.children].map(T).join(" | ")),
           pills: [...m.querySelectorAll(".mbody table .pill")].map(p => pill(p)), foot: [...m.querySelectorAll(".mfoot button")].map(T) }; }"""
READ_LIST = READ + "return readList(); }"
READ_DETAIL = READ + "return readDetail(); }"
READ_POPUP = READ + "return readPopup(); }"
# the old pop-up as its tailModal() draws it, read like the old board and cards (drawing the old Home to open it timed out)
OLD_POPUP = READ + """const reg = arguments[0];
  const d = document.createElement("div");
  d.innerHTML = window.__eqOld(`(() => { const was = ui.modal; ui.modal = {kind: "tail", key: ${JSON.stringify(reg)}};
    try { return tailModal(); } finally { ui.modal = was; } })()`);
  return readPopup(d); }"""
READ_NEW_BOARD = READ + "return readBoard(document.querySelector('[data-figure=\"tails: deliveries\"]')); }"
READ_OLD_BOARD = READ + """const d = document.createElement("div"); d.innerHTML = window.__eqOld("renderDeliveries()");
  const out = readBoard(d.querySelector(".board")); return out; }"""
READ_NEW_CARD = READ + "return readCard(document.querySelector('[data-figure=\"tails: deliveries\"] .pcard')); }"
OLD_CARD = READ + """const reg = arguments[0];
  const d = document.createElement("div"); d.innerHTML = window.__eqOld(`planCard(${JSON.stringify(reg)}, deliveryRows().find(x => x.reg === ${JSON.stringify(reg)}),
    { canFile: deliveryRows().find(x => x.reg === ${JSON.stringify(reg)}).status !== "on order" })`);
  return readCard(d.querySelector(".pcard")); }"""


# ---------- the two planners
class OldTails(rs.Planner):
    """The old planner (real_saves_test.py's), its clock frozen at the moment before its scripts run, with the hook."""

    def __init__(self, *a, moment, **k):
        super().__init__(*a, **k)
        self.moment = moment
        self.schedule = None   # the game's answer to /api/game-schedule, when set

    async def page(self, host=LIVE_HOST):
        self.pg = pg = await self.ctx.new_page()
        await pg.clock.set_fixed_time(self.moment)
        await pg.emulate_media(reduced_motion="reduce")
        pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
        pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
              if m.type == "error" and "Failed to load resource" not in m.text else None)
        pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await pg.route("**/api/game-schedule*", lambda r: answer_schedule(r, self.schedule))
        await pg.goto(f"http://{host}:{self.port}/planner/")
        return pg

    async def ready(self):
        await self.pg.wait_for_function("() => window.__eqOld && window.__eqOld('CAP.at') > 0", timeout=60000)

    async def run(self, js):
        return await self.pg.evaluate("s => window.__eqOld(s)", js)

    async def view(self, airline, tf=None, tail=None, df=None):
        st = {"view": "tails", "airline": airline, "tf": tf or {}, "df": df or {}, "tail": tail, "modal": None, "planOpen": None, "fileCheck": None}
        await self.run(f"Object.assign(ui, {json.dumps(st)}); render(); true")
        await settle(self.pg, 80)

    async def reopen(self):
        await self.pg.close()
        await self.page()
        await self.pg.wait_for_function("() => window.__eqDataLoaded === true", timeout=60000)
        await self.ready()


class NewTails(pn.Planner):
    """The new planner (planner_next_test.py's), with /api/game-schedule answered by the test."""

    schedule = None

    async def open(self, *a, **k):
        pg = await super().open(*a, **k)
        await pg.route("**/api/game-schedule*", lambda r: answer_schedule(r, self.schedule))
        return pg


async def answer_schedule(r, body):
    if body is None:
        await r.fulfill(status=502, body=json.dumps({"error": "The game answered 502."}), content_type="application/json")
    else:
        await r.fulfill(body=json.dumps(body), content_type="application/json")


async def new_go(pl, to, page=None):
    """The new planner at one of its addresses (inside the router), once Tails has read everything and, for an aircraft,
    drawn it (or given up after 10 s, so the comparison names what's missing)."""
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", to)
    await pl.pg.wait_for_function("""want => { const m = document.querySelector('main[data-screen=tails]');
        return !!m && m.dataset.tailsReady === 'yes' && decodeURIComponent(m.dataset.tailsView || '') === decodeURIComponent(want); }""", arg=to, timeout=60000)
    if page:
        try:
            await pl.pg.wait_for_selector(f"[data-tail-page={json.dumps(page)}]", timeout=10000)
        except Exception:
            pass
    await settle(pl.pg, 120)


def q(**f):
    from urllib.parse import urlencode
    f = {k: v for k, v in f.items() if v}
    return ("?" + urlencode(f)) if f else ""


# ---------- 3. the lists
def compare_rows(o, n, label):
    p = []
    if o["count"] != n["count"]:
        p.append(f"{label}: the count: old {o['count']!r}, new {n['count']!r}")
    if [r["reg"] for r in o["rows"]] != [r["reg"] for r in n["rows"]]:
        p.append(f"{label}: old rows {[r['reg'] for r in o['rows']]}, new {[r['reg'] for r in n['rows']]}")
    nm = {r["reg"]: r for r in n["rows"]}
    for r in o["rows"]:
        x = nm.get(r["reg"])
        if not x:
            continue
        for k in ("cells", "dot", "maint"):
            if r[k] == x[k]:
                continue
            if r["reg"] in COPY["est"]:
                known("block estimates", f"{label} {r['reg']}: {k}")
            else:
                p.append(f"{label} {r['reg']}: {k}: old {r[k]!r}, new {x[k]!r}")
    return p


async def lists(old, new, airlines):
    p, views = [], 0
    for al in airlines:
        async def both(tf, label, chips=False):
            nonlocal views
            views += 1
            await old.view(al["name"], tf)
            o = await old.pg.evaluate(READ_LIST)
            await new_go(new, "/tails" + q(airline=al["code"], base=tf.get("base"), type=tf.get("type"), status=tf.get("status")))
            n = await new.pg.evaluate(READ_LIST)
            out = compare_rows(o, n, f"{al['code']} {label}")
            if chips and o["chips"] != n["chips"]:
                out.append(f"{al['code']} {label}: the chips: old {o['chips']}, new {n['chips']}")
            return out, o
        try:
            x, o_all = await both({}, "all", chips=True)
            p += x
            for b in [c.lstrip("*") for c in o_all["chips"].get("Base", [])[1:]]:
                p += (await both({"base": b}, f"base {b}", chips=True))[0]
            for t in [c.lstrip("*") for c in o_all["chips"].get("Type", [])[1:]]:
                p += (await both({"type": t}, f"type {t}"))[0]
            for s in ("flying", "idle", "warn"):
                p += (await both({"status": s}, f"status {s}"))[0]
        except Exception as e:
            p.append(f"{al['code']}: {why(e)}")
    return f"every airline's list equals the old one ({views} views: each airline's rows, count and chips, each base, each type, Flying, No flights and Needs a look)", p


# ---------- 4. every aircraft's page, and the pop-up
def compare_detail(o, n, old_issues, label, reg):
    p = []
    if o is None or n is None:
        return [f"{label}: the {'old' if o is None else 'new'} Tails shows no aircraft"]
    est = reg in COPY["est"]
    for k in ("h2", "dsub", "maint", "labels", "del", "axis", "bars", "note", "table", "pills", "empty"):
        if o[k] == n[k]:
            continue
        if est and k in ("dsub", "maint", "bars", "table", "pills"):
            known("block estimates", f"{label}: {k}")
        else:
            p.append(f"{label}: {k}: old {o[k]!r}, new {n[k]!r}"[:900])
    if [f["k"] for f in o["fields"]] != [f["k"] for f in n["fields"]]:
        p.append(f"{label}: the fields: old {[f['k'] for f in o['fields']]}, new {[f['k'] for f in n['fields']]}")
    for a, b in zip(o["fields"], n["fields"]):
        if a["opts"] != b["opts"]:
            # a box's options differ: its value may too, where the aircraft's own type or cabin is on one list only
            known("choices offered", f"{label}: {a['k']}: old {a['opts']}, new {b['opts']}" + (f" (shown: old {a['v']!r}, new {b['v']!r})" if a["v"] != b["v"] else "")[:300])
        elif a["v"] != b["v"]:
            p.append(f"{label}: {a['k']}: old {a['v']!r}, new {b['v']!r}")
    issues = [x for x in n["issues"] if not x.startswith("schedule clean")]
    if issues != old_issues:
        if est:
            known("block estimates", f"{label}: issues")
        else:
            p.append(f"{label}: the issues: old tailIssues() {old_issues}, new {issues}")
    if not old_issues and not any(x.startswith("schedule clean") for x in n["issues"]):
        p.append(f"{label}: no issues, but the page doesn't say the schedule is clean")
    return p


async def pages(old, new, airlines):
    p, n_pages = [], 0
    for al in airlines:
        for reg in COPY["tails"].get(al["id"], []):
            label = f"{al['code']} {reg}"
            try:
                await old.view(al["name"], {}, tail=reg)
                o = await old.pg.evaluate(READ_DETAIL)
                old_issues = json.loads(await old.run(f"JSON.stringify(tailIssues({json.dumps(reg)}))"))
                await new_go(new, f"/tails/{reg}", page=reg)
                n = await new.pg.evaluate(READ_DETAIL)
                p += compare_detail(o, n, old_issues, label, reg)
                n_pages += 1
            except Exception as e:
                p.append(f"{label}: {why(e)}")
    return n_pages, p


async def popups(old, new, airlines):
    p, n = [], 0
    for al in airlines:
        for reg in COPY["tails"].get(al["id"], [])[:POPUP_SAMPLE]:
            try:
                o = await old.pg.evaluate(OLD_POPUP.replace("arguments[0]", json.dumps(reg)))
                await new.pg.evaluate("t => window.__eqPlanner.go(t)", "/?aircraft=" + reg)
                await new.pg.wait_for_selector(f"[data-aircraft-popup={json.dumps(reg)}][data-popup-ready=yes]", timeout=60000)
                await new.pg.wait_for_timeout(150)
                x = await new.pg.evaluate(READ_POPUP)
                await new.pg.click(".modal .mx")
                await new.pg.wait_for_selector("[data-aircraft-popup]", state="detached", timeout=10000)
                n += 1
                for k in ("head", "stats", "statPills", "issues", "rows", "empty", "foot"):
                    if (o or {}).get(k) == (x or {}).get(k):
                        continue
                    if reg in COPY["est"] and k in ("stats", "statPills", "issues", "rows"):
                        known("block estimates", f"the pop-up of {reg}: {k}")
                    else:
                        p.append(f"the pop-up of {al['code']} {reg}: {k}: old {(o or {}).get(k)!r}, new {(x or {}).get(k)!r}"[:600])
            except Exception as e:
                p.append(f"the pop-up of {al['code']} {reg}: {why(e)}")
    return n, p


# ---------- 5. the deliveries
def compare_board(o, x, label):
    p = []
    if o is None or x is None:
        return [f"{label}: the {'old' if o is None else 'new'} board isn't there"]
    for k in ("head", "dim", "chips", "showing"):
        if o[k] != x[k]:
            p.append(f"{label}: {k}: old {o[k]!r}, new {x[k]!r}")
    if len(o["rows"]) != len(x["rows"]):
        return p + [f"{label}: old {len(o['rows'])} rows, new {len(x['rows'])}: old {[r['cells'][:1] for r in o['rows']]}, new {[r['cells'][:1] for r in x['rows']]}"]
    for a, b in zip(o["rows"], x["rows"]):
        for k in ("cells", "status", "card"):
            if a[k] != b[k]:
                p.append(f"{label} {(a['cells'] or ['?'])[0]}: {k}: old {a[k]!r}, new {b[k]!r}")
        if a["actions"] != b["actions"]:
            if a["actions"].replace(" · remove", "").replace("remove", "") == b["actions"]:
                known("remove a delivery", f"{label} {(a['cells'] or ['?'])[0]}")
            else:
                p.append(f"{label} {(a['cells'] or ['?'])[0]}: the actions: old {a['actions']!r}, new {b['actions']!r}")
    return p


async def deliveries(old, new, airlines):
    p, views, cards = [], 0, 0
    for al in airlines:
        for status in ("", "on order", "unscheduled", "flying"):
            label = f"{al['code']} deliveries ({status or 'open'})"
            try:
                await old.view(al["name"], {}, df={"status": status} if status else {})
                o = await old.pg.evaluate(READ_OLD_BOARD)
                await new_go(new, "/tails" + q(airline=al["code"], **({"del": status} if status else {})))
                x = await new.pg.evaluate(READ_NEW_BOARD)
                p += compare_board(o, x, label)
                views += 1
            except Exception as e:
                p.append(f"{label}: {why(e)}")
        for reg, flying in COPY["cards"].get(al["id"], []):
            try:
                await old.view(al["name"], {})
                o = await old.pg.evaluate(OLD_CARD.replace("arguments[0]", json.dumps(reg)))
                await new_go(new, "/tails" + q(airline=al["code"], **({"del": "flying"} if flying else {}), card=reg))
                x = await new.pg.evaluate(READ_NEW_CARD)
                if o != x:
                    p.append(f"{al['code']} {reg}'s plan card: old {o!r}, new {x!r}"[:900])
                cards += 1
            except Exception as e:
                p.append(f"{al['code']} {reg}'s plan card: {why(e)}")
    return f"every airline's deliveries board equals the old one ({views} views: open, on order, arrived and flying), and every plan card on it ({cards})", p


# ---------- 6. filing
def max_ids():
    return json.loads(psql("""select json_build_object('rotations', coalesce((select max(id) from public.rotations), 0),
        'flight_legs', coalesce((select max(id) from public.flight_legs), 0), 'spending_log', coalesce((select max(id) from public.spending_log), 0),
        'routes', coalesce((select max(id) from public.routes), 0))""").strip())


def snapshot(aid, card_id):
    return json.loads(psql(f"""select json_build_object(
        'aircraft', (select to_jsonb(a) from public.aircraft a where a.id = {int(aid)}),
        'card', (select to_jsonb(c) from public.plan_cards c where c.id = {int(card_id)}),
        'legs', (select coalesce(jsonb_agg(to_jsonb(l) order by l.position), '[]') from public.plan_card_legs l where l.plan_card_id = {int(card_id)}))""").strip())


def written(aid, card_id, ids):
    """The rows a filing wrote, as they stand: the aircraft, its plan card and its legs, and the rotations, legs, money spent and
    routes made since ids (without their ids and times, which differ between two filings)."""
    drop = ("id", "created_at", "updated_at")
    d = json.loads(psql(f"""select json_build_object(
        'aircraft', (select to_jsonb(a) - 'updated_at' from public.aircraft a where a.id = {int(aid)}),
        'card', (select to_jsonb(c) - 'updated_at' from public.plan_cards c where c.id = {int(card_id)}),
        'card_legs', (select coalesce(jsonb_agg(to_jsonb(l) - 'updated_at' order by l.position), '[]') from public.plan_card_legs l where l.plan_card_id = {int(card_id)}),
        'rotations', (select coalesce(jsonb_agg(to_jsonb(r) order by r.id), '[]') from public.rotations r where r.id > {int(ids['rotations'])}),
        'legs', (select coalesce(jsonb_agg(to_jsonb(l) order by l.rotation_id, l.leg_no), '[]') from public.flight_legs l where l.id > {int(ids['flight_legs'])}),
        'spending', (select coalesce(jsonb_agg(to_jsonb(s) order by s.id), '[]') from public.spending_log s where s.id > {int(ids['spending_log'])}),
        'routes', (select coalesce(jsonb_agg(to_jsonb(r) order by r.id), '[]') from public.routes r where r.id > {int(ids['routes'])}))""").strip())
    for r in d["rotations"]:
        r["legacy_key"] = (r.get("legacy_key") or "")[:-3]
    for k in ("rotations", "legs", "spending", "routes"):
        d[k] = [{c: v for c, v in r.items() if c not in drop + ("rotation_id", "route_id" if k == "routes" else "")} for r in d[k]]
    return d


def put_back(snap, ids):
    """The copy as it was before a filing: the rows it made removed, the aircraft and the card's legs as they were."""
    a = snap["aircraft"]
    psql(f"""begin;
      select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'tails_side_by_side_test', true);
      delete from public.flight_legs where id > {int(ids['flight_legs'])} or rotation_id > {int(ids['rotations'])};
      delete from public.rotations where id > {int(ids['rotations'])};
      delete from public.spending_log where id > {int(ids['spending_log'])};
      delete from public.routes where id > {int(ids['routes'])};
      update public.aircraft x set status = s.status, base_code = s.base_code, cabin_config_id = s.cabin_config_id, extra = s.extra, retired_on = s.retired_on,
             checked_on = s.checked_on, schedule_changed_on = s.schedule_changed_on, maintenance_note = s.maintenance_note, registration = s.registration,
             aircraft_type_id = s.aircraft_type_id
        from jsonb_populate_record(null::public.aircraft, :'a'::jsonb) s where x.id = s.id;
      update public.plan_card_legs x set dep_utc_min = s.dep_utc_min, block_min = s.block_min, days_utc = s.days_utc, flight_no = s.flight_no,
             origin_code = s.origin_code, dest_code = s.dest_code, service_code = s.service_code
        from jsonb_populate_recordset(null::public.plan_card_legs, :'l'::jsonb) s where x.id = s.id;
      update public.plan_cards x set base_code = s.base_code, title = s.title, note = s.note, extra = s.extra
        from jsonb_populate_record(null::public.plan_cards, :'c'::jsonb) s where x.id = s.id;
      commit;""", a=json.dumps(a), l=json.dumps(snap["legs"]), c=json.dumps(snap["card"]))


def compare_written(n, o, label, game_blocks_differ=()):
    p = []
    for k in ("aircraft", "rotations", "legs", "spending", "routes"):
        if n[k] != o[k]:
            p.append(f"{label}: {k}: new {n[k]!r}, old {o[k]!r}"[:900])
    # the card row: the same, but for the old planner's copy of its legs (known difference)
    nc, oc = dict(n["card"] or {}), dict(o["card"] or {})
    ne, oe = dict(nc.pop("extra", None) or {}), dict(oc.pop("extra", None) or {})
    if "legs" in oe and "legs" not in ne:
        known(CARD_COPY, f"{label}: card {oc.get('id')}: the old planner's copy of its {len(oe['legs'] or [])} legs")
        oe.pop("legs")
    if nc != oc or ne != oe:
        p.append(f"{label}: the card: new {dict(nc, extra=ne)!r}, old {dict(oc, extra=oe)!r}"[:900])
    for a, b in zip(n["card_legs"], o["card_legs"]):
        for c in a:
            if a[c] == b.get(c):
                continue
            if c == "block_min" and a.get("position") in game_blocks_differ:
                known(ARRIVAL, f"{label}: card leg {a.get('position')} (flight {a.get('flight_no')}): new {a[c]}, old {b.get(c)}")
            else:
                p.append(f"{label}: the card's leg {a.get('position')}: {c}: new {a[c]!r}, old {b.get(c)!r}")
    if len(n["card_legs"]) != len(o["card_legs"]):
        p.append(f"{label}: the card has {len(n['card_legs'])} legs after the new filing, {len(o['card_legs'])} after the old")
    return p


OLD_FREQS = """JSON.stringify(state.freqs.filter(f => f.tail === %s).map(f => ({ routeKey: f.routeKey, days: f.days, noOut: f.noOut, noBack: f.noBack,
  depHub: f.depHub, arrDest: f.arrDest, depDest: f.depDest, arrHub: f.arrHub, service: f.service, price: f.price, launched: f.launched }))
  .sort((a, b) => String(a.noOut).localeCompare(String(b.noOut))))"""
# the card's legs as the old planner shows them: number, airports, times and days (no days = every day, as its check reads
# them); the block is left out (known difference "the plan card's arrival": the arrival shown is the same)
OLD_CARD_LEGS = """JSON.stringify((((state.plans || {})[%s] || {}).legs || []).map(L => ({ no: String(L.no), from: L.from, to: L.to, dep: L.dep,
  arr: L.arr || "", days: String(L.days || "1234567").split("").sort().join("") })))"""


def shift(hhmm, m):
    h, mm = (int(x) for x in hhmm.split(":"))
    t = (h * 60 + mm + m) % 1440
    return f"{t // 60:02d}:{t % 60:02d}"


def game_answer(card_legs, airline_code, changes=None):
    """The saved sample's answer with the card's flights put in as the game shows them (changes: index → (dep shift,
    arr shift) in minutes), and the sample's own flights of other numbers kept."""
    s = json.loads((FIX / "schedule_113.expected.json").read_text())
    nos = {str(L["no"]) for L in card_legs}
    mine = []
    for i, L in enumerate(card_legs):
        d, a = (changes or {}).get(i, (0, 0))
        mine.append({"code": airline_code or "XX", "no": str(L["no"]), "from": L["from"], "to": L["to"], "days": "1234567", "dep": shift(L["dep"], d),
                     "arr": shift(L["arr"], a) if L.get("arr") else "", "type": "32N", "valid": ""})
    return dict(s, flights=[f for f in s["flights"] if f["no"] not in nos] + mine)


async def file_new(new, al, reg, mode):
    """Files in the new Tails: the deliveries board with the card open, File into planner; with the game differing, File
    with the game's times in the check."""
    await new_go(new, "/tails" + q(airline=al["code"], card=reg))
    await new.pg.click(f"[data-figure='tails: deliveries'] [data-planfile={json.dumps(reg)}]")
    if mode == "differs":
        await new.pg.wait_for_selector(f"[data-file-check={json.dumps(reg)}][data-file-ready=yes]", timeout=60000)
        shown = await new.pg.evaluate(READ_CHECK)
        await new.pg.click(f"[data-filegame={json.dumps(reg)}]")
        return shown
    return None


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


async def refresh(new):
    """The new planner loaded again (signed in already, its clock still frozen), so it reads what the test put back."""
    await new.pg.reload()
    await new.pg.wait_for_function("!!window.__eqPlanner", timeout=60000)
    await new.pg.wait_for_selector("main[data-screen]", timeout=60000)
    await settle(new.pg, 300)


async def filing(old, new, al, reg, aid, card_id):
    out = []
    snap = snapshot(aid, card_id)
    await old.reopen()
    card = json.loads(await old.run(f"JSON.stringify(state.plans[{json.dumps(reg)}])"))
    legs = card.get("legs") or []
    for mode, changes in (("matches", None), ("differs", {0: (10, 15)})):
        answer = game_answer(legs, al["code"], changes)
        new.schedule = answer
        old.schedule = answer
        differ = {1} if changes else set()
        problems = []
        # the new planner files first, loaded again so it reads the copy as it is now
        await refresh(new)
        client = await new.pg.evaluate("window.__eqPlanner.client")
        ids, mark = max_ids(), marks()
        summary = await file_new(new, al, reg, mode)
        await rs.wait_for(lambda: log_since(mark), lambda got: len(got) >= 3, seconds=60)
        await until_quiet()
        await new.pg.wait_for_function("() => /^(saved)$/.test((document.querySelector('[data-save-state]') || {}).textContent || '')", timeout=30000)
        new_log = log_since(mark)
        n_rows = written(aid, card_id, ids)
        problems += [f"a change-log row names {r['actor']} ({r['detail']}), not planner (the tab's ID)" for r in new_log if r["actor"] != "planner" or r["detail"] != client]
        if mode == "matches" and await new.pg.evaluate("!!document.querySelector('[data-file-check]')"):
            problems.append("the check was shown although every leg matches")
        if mode == "differs" and "differ" not in " ".join((summary or {}).get("paras", [])):
            problems.append(f"the check says {(summary or {}).get('paras')!r}")
        try:
            await new.pg.wait_for_selector(f"[data-tail-page={json.dumps(reg)}]", timeout=30000)
        except Exception:
            problems.append("the new planner didn't open the aircraft after filing it")
        await old.reopen()
        old_view_new = json.loads(await old.run(OLD_FREQS % json.dumps(reg)))
        old_card_new = json.loads(await old.run(OLD_CARD_LEGS % json.dumps(reg)))
        in_tails = await old.run(f"state.tails.some(t => t.id === {json.dumps(reg)})")
        if not in_tails:
            problems.append("the old planner, opened again, doesn't list the aircraft among its tails")
        put_back(snap, ids)
        # then the old planner, on the copy as it was
        await old.reopen()
        ids2, mark2 = max_ids(), marks()
        await old.run(f"checkBeforeFile({json.dumps(reg)}); true")
        if mode == "differs":
            await old.pg.wait_for_selector(f"[data-filegame={json.dumps(reg)}]", timeout=60000)
            old_shown = await old.pg.evaluate(READ_CHECK)
            if old_shown != summary:
                problems.append(f"the check shown: old {old_shown!r}, new {summary!r}"[:900])
            await old.pg.click(f"[data-filegame={json.dumps(reg)}]")
        await rs.wait_for(lambda: log_since(mark2), lambda got: len(got) >= 3, seconds=60)
        await until_quiet()
        old_log = log_since(mark2)
        o_rows = written(aid, card_id, ids2)
        await old.reopen()
        old_view_old = json.loads(await old.run(OLD_FREQS % json.dumps(reg)))
        old_card_old = json.loads(await old.run(OLD_CARD_LEGS % json.dumps(reg)))
        put_back(snap, ids2)
        problems += compare_written(n_rows, o_rows, mode, differ)
        if old_card_new != old_card_old:
            problems.append(f"the old planner shows the card's legs after the new filing as {old_card_new}, after its own as {old_card_old}"[:900])
        # the old planner's save writing its copy of the card's legs (known difference CARD_COPY) is the one change it may add
        copy = "legs" in ((o_rows["card"] or {}).get("extra") or {}) and "legs" not in ((n_rows["card"] or {}).get("extra") or {})
        old_log_cmp = [r for r in old_log if not (copy and r["table"] == "plan_cards" and r["op"] == "update" and list(r["fields"]) == ["extra"])]
        nc, oc = Counter((r["table"], r["op"]) for r in new_log), Counter((r["table"], r["op"]) for r in old_log_cmp)
        if nc != oc:
            extra, fewer = oc - nc, nc - oc
            rows = [f"{r['table']} {r['op']} {r['id']} ({', '.join(r['fields']) or 'whole row'})" for r in old_log_cmp if (r["table"], r["op"]) in extra] \
                + [f"new only: {r['table']} {r['op']} {r['id']} ({', '.join(r['fields']) or 'whole row'})" for r in new_log if (r["table"], r["op"]) in fewer]
            problems.append(f"the new filing changed {dict(nc)}, the old {dict(oc)}" + (f" (the difference: {'; '.join(rows)})" if rows else ""))
        if old_view_new != old_view_old:
            problems.append(f"the old planner shows the new filing's frequencies {old_view_new}, its own {old_view_old}"[:900])
        n_rot = len(n_rows["rotations"])
        out.append((f"filing {al['code']} {reg} from its plan card, the game answering \"{mode}\""
                    + (" (it files at once)" if mode == "matches" else " (the check shown as the old planner shows it, then File with the game's times)")
                    + f": {n_rot} rotation(s) and {len(n_rows['legs'])} legs, the aircraft in service, {len(n_rows['spending'])} cabin fit(s)"
                    + (", the card's legs taking the game's times" if mode == "differs" else "")
                    + "; the same rows as the old planner's for the same card, logged as planner with the tab's ID; the old planner, opened again, "
                      "shows the aircraft flying the same frequencies and the card's legs at the same times", problems))
    return out


# ---------- 7. add, edit and remove a tail
async def wait_saved(pl, mark, rows=1):
    await rs.wait_for(lambda: log_since(mark), lambda got: len(got) >= rows, seconds=30)
    await settle(pl.pg, 300)
    await pl.pg.wait_for_function("() => /^(saved|preview · not saved)$/.test((document.querySelector('[data-save-state]') || {}).textContent || '')", timeout=30000)
    await pl.pg.wait_for_function("() => (document.querySelector('main[data-screen=tails]') || {dataset: {}}).dataset.tailsReady === 'yes'", timeout=60000)
    await settle(pl.pg, 500)


def logged(mark, want, client, rid=None):
    rows = log_since(mark)
    got = Counter((r["table"], r["op"]) for r in rows)
    problems = [] if got == want else [f"the tables changed by {dict(got)}, expected {dict(want)}"]
    problems += [f"a change-log row names {r['actor']} ({r['detail']}), not planner (the tab's ID)" for r in rows if r["actor"] != "planner" or r["detail"] != client]
    if rid is not None:
        problems += [f"another row changed: {r['table']} {r['id']}" for r in rows if r["id"] != str(rid)]
    return problems, rows


async def add_edit_remove(old, new, al, tag):
    out = []
    await refresh(new)
    pg, client = new.pg, await new.pg.evaluate("window.__eqPlanner.client")
    reg = "ZZ" + tag[:4].upper()
    await new_go(new, "/tails" + q(airline=al["code"]))
    n0, mark = counts(), marks()
    await pg.fill("#t-id", reg)
    for sel in ("#t-type", "#t-cfg", "#t-base"):
        v = await pg.evaluate(f"(document.querySelector('{sel}').options[1] || {{}}).value || ''")
        if v:
            await pg.select_option(sel, v)
    form = await pg.evaluate("['#t-type', '#t-cfg', '#t-base'].map(s => document.querySelector(s).value)")
    await pg.click("#t-add")
    await wait_saved(new, mark)
    problems, _ = logged(mark, Counter({("aircraft", "insert"): 1}), client)
    row = json.loads(psql(f"select coalesce((select to_jsonb(a) from public.aircraft a where a.registration = :'r' and a.world_id = {WORLD}), 'null')", r=reg).strip())
    count = int(psql(f"select count(*) from public.aircraft where world_id = {WORLD} and extra ? 'tails_index' and registration <> :'r'", r=reg).strip())
    if not row or row.get("status") != "active" or (row.get("extra") or {}).get("tails_index") != count:
        problems.append(f"the aircraft isn't in service at the end of the list of tails ({(row or {}).get('status')}, {(row or {}).get('extra')}, {count} before it)")
    problems += count_changes(n0, counts(), allow={"public.change_log", "public.aircraft"})
    await old.reopen()
    t = json.loads(await old.run(f"JSON.stringify(state.tails.find(t => t.id === {json.dumps(reg)}) || null)"))
    if not t or [t.get("type"), t.get("config"), t.get("base")] != form or t.get("airline") != al["name"]:
        problems.append(f"the old planner, opened again, shows {t}, the form had {form}")
    out.append((f"add a tail ({al['code']} {reg}, {' / '.join(form)}) by the form: one aircraft row, in service at the end of the list of tails, logged as planner "
                "with the tab's ID; the old planner, opened again, lists it with its type, cabin and base", problems))
    if not row:
        return out
    try:
        await pg.wait_for_selector(f"[data-tail-page={json.dumps(reg)}]", timeout=30000)
    except Exception:
        out.append(("open the added tail", ["the new planner didn't open it"]))
        return out

    # its maintenance gap, then its base, each one update of its row
    for k, v, col in (("maint", "test gap " + tag, "maintenance_note"), ("base", None, "base_code")):
        mark = marks()
        if k == "maint":
            await pg.fill(f"[data-tk={k}]", v)
            await pg.press(f"[data-tk={k}]", "Enter")
        else:
            opts = await pg.evaluate("[...document.querySelector('[data-tk=base]').options].map(o => o.value).filter(Boolean)")
            v = next((o for o in opts if o != form[2]), opts[0] if opts else "")
            await pg.select_option(f"[data-tk={k}]", v)
        await wait_saved(new, mark)
        problems, rows = logged(mark, Counter({("aircraft", "update"): 1}), client, row["id"])
        if rows and (col not in rows[0]["fields"] or set(rows[0]["fields"]) - {col, "updated_at"}):
            problems.append(f"the update changed {rows[0]['fields']}, not just {col}")
        await old.reopen()
        shown = await old.run(f"(state.tails.find(t => t.id === {json.dumps(reg)}) || {{}})[{json.dumps('maint' if k == 'maint' else 'base')}]")
        if shown != v:
            problems.append(f"the old planner, opened again, shows {shown!r}, not {v!r}")
        out.append((f"change its {'maintenance gap' if k == 'maint' else 'base'} ({v}): one update of its {col}, logged as planner with the tab's ID; "
                    "the old planner, opened again, shows it", problems))

    # remove it: asked in the page; retired, never deleted
    await new_go(new, "/tails" + q(airline=al["code"]))
    mark, d0 = marks(), len(new.dialogs)
    await pg.click(f"[data-deltail={json.dumps(reg)}]")
    await pg.click(".qpanel [data-confirm-yes]")
    await wait_saved(new, mark)
    problems, rows = logged(mark, Counter({("aircraft", "update"): 1}), client, row["id"])
    after = json.loads(psql(f"select coalesce((select to_jsonb(a) from public.aircraft a where a.id = {int(row['id'])}), 'null')").strip())
    if not after or after.get("status") != "retired" or not after.get("retired_on") or "tails_index" in (after.get("extra") or {}):
        problems.append(f"the aircraft isn't retired out of the list of tails ({(after or {}).get('status')}, {(after or {}).get('retired_on')})")
    if len(new.dialogs) > d0:
        problems.append("a browser dialog was opened")
    await old.reopen()
    if await old.run(f"state.tails.some(t => t.id === {json.dumps(reg)})"):
        problems.append("the old planner, opened again, still lists it")
    out.append(("remove it (the page asks itself): retired, never deleted, out of the list of tails, one update logged as planner with the tab's ID; "
                "the old planner, opened again, no longer lists it", problems))
    return out


# ---------- 8. a preview, 9. a phone and the screenshots
async def preview(p, port, env, facts, staff, moment, seen, al, reg, filing_reg):
    pv = NewTails(p, port, env, facts)
    seen.append(pv)
    problems = []
    try:
        await pv.open(host="127.0.0.1", moment=moment)
        await pv.pg.emulate_media(reduced_motion="reduce")
        await pv.sign_in(*staff)
        n0, mark = counts(), marks()
        await new_go(pv, "/tails" + q(airline=al["code"]))
        await pv.pg.fill("#t-id", "ZZPREV")
        await pv.pg.click("#t-add")
        await settle(pv.pg, 600)
        await new_go(pv, f"/tails/{reg}", page=reg)
        await pv.pg.fill("[data-tk=maint]", "preview check")
        await pv.pg.press("[data-tk=maint]", "Enter")
        await settle(pv.pg, 600)
        if filing_reg:
            pv.schedule = None   # the game can't be read: the check is shown, then filed with the card's times
            await new_go(pv, "/tails" + q(airline=filing_reg[0], card=filing_reg[1]))
            await pv.pg.click(f"[data-planfile={json.dumps(filing_reg[1])}]")
            await pv.pg.wait_for_selector("[data-file-check][data-file-ready=yes]", timeout=30000)
            await pv.pg.click(f"[data-filecard={json.dumps(filing_reg[1])}]")
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
    return (f"a preview address (127.0.0.1) shows Tails, and Add a tail, an edit of an aircraft{' and File into planner' if filing_reg else ''} there send no write "
            f"(it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})"), problems


async def phone(p, port, env, facts, staff, moment, seen, al, reg):
    ph = NewTails(p, port, env, facts, width=380, height=800)
    seen.append(ph)
    problems = []
    scroll = "Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth"
    try:
        await ph.open(moment=moment)
        await ph.pg.emulate_media(reduced_motion="reduce")
        await ph.sign_in(*staff)
        await new_go(ph, "/tails" + q(airline=al["code"]))
        if (over := await ph.pg.evaluate(scroll)) > 0:
            problems.append(f"the list scrolls sideways by {over} px at 380 px wide")
        if not await ph.pg.evaluate("getComputedStyle(document.querySelector('tr[data-tail]') || document.body).display === 'grid'"):
            problems.append("on a phone the list isn't cards")
        await new_go(ph, f"/tails/{reg}", page=reg)
        if (over := await ph.pg.evaluate(scroll)) > 0:
            problems.append(f"an aircraft scrolls sideways by {over} px at 380 px wide")
        if not await ph.pg.evaluate("getComputedStyle(document.querySelector('#taillist')).display === 'none'"):
            problems.append("on a phone the list doesn't give way to the aircraft")
        problems += ph.errors
    finally:
        await ph.close()
    return "at 380 px wide the list (as cards), the deliveries and an aircraft have no sideways scroll and no errors; the aircraft takes the page", problems


async def screenshots(old, new, al, reg):
    if not SCREENS_DIR:
        return
    Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    for width, height in ((1280, 900), (380, 800)):
        await old.pg.set_viewport_size({"width": width, "height": height})
        await new.pg.set_viewport_size({"width": width, "height": height})
        for what, t in (("list", None), ("aircraft", reg)):
            await old.view(al["name"], {}, tail=t)
            await settle(old.pg, 400)
            await old.pg.screenshot(path=str(Path(SCREENS_DIR) / f"old-tails-{what}-{width}.png"), full_page=True, timeout=90000)
            await new_go(new, "/tails" + q(airline=al["code"]) if t is None else f"/tails/{t}", page=t)
            await settle(new.pg, 400)
            await new.pg.screenshot(path=str(Path(SCREENS_DIR) / f"tails-{what}-{width}.png"), full_page=True, timeout=90000)
    await old.pg.set_viewport_size({"width": 1440, "height": 1000})
    await new.pg.set_viewport_size({"width": 1280, "height": 900})


async def home_links(new, airlines):
    await new.pg.evaluate("t => window.__eqPlanner.go(t)", "/")
    await new.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=90000)
    await settle(new.pg, 300)
    got = await new.pg.evaluate("""({ fleet: [...document.querySelectorAll('[data-open-fleet]')].map(a => [a.dataset.openFleet, a.getAttribute('href')]),
        file: [...document.querySelectorAll('[data-file-into-planner]')].map(a => a.getAttribute('href')) })""")
    problems = []
    for name, href in got["fleet"]:
        al = next((a for a in airlines if a["name"] == name), None)
        if not al or href != f"/planner/next/tails?airline={al['code']}":
            problems.append(f"{name}'s Open fleet goes to {href}")
    problems += [f"a File into planner goes to {h}" for h in got["file"] if not (h or "").startswith("/planner/next/tails?") or "file=" not in h]
    if not got["fleet"]:
        problems.append("Home shows no Open fleet")
    return (f"Home's Open fleet ({len(got['fleet'])}) and File into planner ({len(got['file'])}) open Tails, at the airline and filing that aircraft"), problems


# ---------- what the copy holds
def read_copy(moment):
    airlines = json.loads(psql(f"""select coalesce(json_agg(json_build_object('id', a.id, 'code', a.iata_code,
              'name', coalesce(a.planner_name, a.public_name, a.game_name, 'Airline ' || a.game_id)) order by a.position nulls last, a.id), '[]')
              from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id where g.kind = 'ours' and a.world_id = {WORLD}""").strip())
    tails = {}
    for aid, reg in json.loads(psql(f"""select coalesce(json_agg(json_build_array(a.airline_id, a.registration) order by (a.extra ->> 'tails_index')::int, a.id), '[]')
              from public.aircraft a where a.world_id = {WORLD} and a.status = 'active' and a.extra ? 'tails_index'""").strip()):
        tails.setdefault(aid, []).append(reg)
    cards = {}
    for aid, reg, flying in json.loads(psql(f"""select coalesce(json_agg(json_build_array(a.airline_id, a.registration,
                exists (select 1 from public.flight_legs l where l.aircraft_id = a.id)) order by a.id), '[]')
              from public.aircraft a join public.plan_cards c on c.aircraft_id = a.id
             where a.world_id = {WORLD} and a.delivery_at is not null and a.status <> 'retired'""").strip()):
        cards.setdefault(aid, []).append((reg, flying))
    est = set(json.loads(psql(f"""select coalesce(json_agg(distinct a.registration), '[]') from public.flight_legs l join public.aircraft a on a.id = l.aircraft_id
              where l.world_id = {WORLD} and l.dep_utc_min is not null and l.block_min is null""").strip()))
    # an arrived aircraft waiting to be filed, with a plan card of at least two timed legs
    pick = json.loads(psql(f"""select coalesce((select json_build_object('aid', a.id, 'reg', a.registration, 'airline', a.airline_id, 'card', c.id)
              from public.aircraft a join public.plan_cards c on c.aircraft_id = a.id
             where a.world_id = {WORLD} and a.status = 'delivered' and a.delivery_at <= :'m'::timestamptz
               and (select count(*) from public.plan_card_legs l where l.plan_card_id = c.id and l.dep_utc_min is not null and l.block_min is not null) >= 2
               and not exists (select 1 from public.plan_card_legs l where l.plan_card_id = c.id and (l.dep_utc_min is null or l.block_min is null))
             order by a.delivery_at, a.id limit 1)::text, 'null')""", m=moment).strip())
    COPY.update(airlines=airlines, tails=tails, cards=cards, est=est, pick=pick)
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
    try:
        airlines = read_copy(moment)
        problems = [] if airlines and COPY["tails"] else ["the copy has none of our airlines or no aircraft in service"]
    except Exception as e:
        airlines, problems = [], [why(e)]
    step(not problems, f"the moment: {moment} (the copy's latest capture plus one hour); the copy: {len(COPY.get('airlines', []))} of our airlines, "
         f"{sum(len(v) for v in COPY.get('tails', {}).values())} aircraft in service, {sum(len(v) for v in COPY.get('cards', {}).values())} with a delivery and a plan card, "
         f"{len(COPY.get('est', []))} flying a leg with an estimated block; to file: {(COPY.get('pick') or {}).get('reg') or 'none'}", problems)
    if problems:
        sys.exit(1)

    tag = secrets.token_hex(4)
    staff = (f"tails-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="tails-side-by-side-"))
    seen = []
    first = next(a for a in airlines if COPY["tails"].get(a["id"]))
    reg0 = COPY["tails"][first["id"]][0]
    pick = COPY.get("pick")
    pick_al = next((a for a in airlines if pick and a["id"] == pick["airline"]), None)
    try:
        root = web_copy(work)
        with serve(root) as port:
            async with async_playwright() as p:
                old = OldTails(p, port, env, facts, lib_js, moment=moment)
                new = NewTails(p, port, env, nfacts, width=1280, height=900)
                seen += [old, new]
                try:
                    n0, mark = counts(), marks()
                    await old.open()
                    await old.sign_in(*staff)
                    await old.ready()
                    await new.open(moment=moment)
                    await new.pg.emulate_media(reduced_motion="reduce")
                    await new.sign_in(*staff)
                    await new_go(new, "/tails")
                    problems = list(old.errors) + list(new.errors)
                    if log_since(mark):
                        problems.append("opening the planners changed the tables")
                    problems += count_changes(n0, counts())
                    if abs(await new.pg.evaluate("Date.now()") - ms(moment)) > 1000:
                        problems.append("the new planner's clock isn't frozen at the moment")
                    if await new.pg.evaluate("!!document.querySelector('main[data-screen=tails] [data-not-built]')"):
                        problems.append("Tails is still a placeholder")
                except Exception as e:
                    problems = [why(e)] + old.errors[:3] + new.errors[:3]
                step(not problems, "both planners opened at the moment, signed in as test staff, the new one on Tails; opening them wrote nothing", problems)
                if problems:
                    sys.exit(1)

                t = time.monotonic()
                try:
                    label, problems = await lists(old, new, airlines)
                except Exception as e:
                    label, problems = "every airline's list", [why(e)]
                step(not problems, label + f" ({time.monotonic() - t:.0f} s)", problems + new.errors[:3] + old.errors[:3])
                try:
                    await screenshots(old, new, first, reg0)
                except Exception as e:
                    print(f"      the screenshots: {why(e)}", flush=True)
                t = time.monotonic()
                n_pages, problems = await pages(old, new, airlines)
                step(not problems and n_pages > 0, f"every aircraft's page equals the old one ({n_pages} aircraft: the header with its figures and maintenance, the fields, "
                     f"the week strip bar by bar, its legs by flight number with days, times, ground to next and the turn or gap, and its issues against the old "
                     f"tailIssues()) ({time.monotonic() - t:.0f} s)", (problems or ([] if n_pages else ["no aircraft compared"])) + new.errors[:3] + old.errors[:3])
                t = time.monotonic()
                try:
                    n, problems = await popups(old, new, airlines)
                except Exception as e:
                    n, problems = 0, [why(e)]
                step(not problems and n > 0, f"the aircraft pop-up Home opens equals the old one ({n} aircraft: base, block a day, legs a week, maintenance, the "
                     f"one-week check, the issues, its flights, Mark checked and Open in Tails) ({time.monotonic() - t:.0f} s)", problems or ["no aircraft compared"])
                t = time.monotonic()
                try:
                    label, problems = await deliveries(old, new, airlines)
                except Exception as e:
                    label, problems = "the deliveries", [why(e)]
                step(not problems, label + f" ({time.monotonic() - t:.0f} s)", problems + new.errors[:3] + old.errors[:3])
                for k, v in KNOWN.items():
                    where = f" (e.g. {'; '.join(v['where'][:4])})" if v["where"] else ""
                    print(f"      known difference \"{k}\": used {v['used']} time(s){where}. {v['rule']}"[:1800], flush=True)

                # ---------- 6. filing
                if pick and pick_al:
                    try:
                        for label, problems in await filing(old, new, pick_al, pick["reg"], pick["aid"], pick["card"]):
                            step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                    except Exception as e:
                        step(False, f"filing {pick['reg']}", [why(e)] + new.errors[:3] + old.errors[:3])
                    v = KNOWN[ARRIVAL]
                    print(f"      known difference \"{ARRIVAL}\": used {v['used']} time(s)" + (f" (e.g. {'; '.join(v['where'][:3])})" if v["where"] else ""), flush=True)
                else:
                    step(False, "filing an arrived aircraft from its plan card", ["the copy has no arrived aircraft waiting to be filed with a plan card of timed legs"])

                # ---------- 7. add, edit and remove
                try:
                    for label, problems in await add_edit_remove(old, new, first, tag):
                        step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                except Exception as e:
                    step(False, "add, edit and remove a tail in the new Tails", [why(e)] + new.errors[:3] + old.errors[:3])
                try:
                    label, problems = await home_links(new, airlines)
                except Exception as e:
                    label, problems = "Home's links to Tails", [why(e)]
                step(not problems, label, problems)
                await old.close()
                await new.close()

                # ---------- 8 and 9
                filing_reg = (pick_al["code"], pick["reg"]) if pick and pick_al else None
                for check, args in ((preview, (first, reg0, filing_reg)), (phone, (first, reg0))):
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
    print(f"\n{len(failures)} Tails side-by-side step(s) failed" if failures else "\nTails side by side: all passed", flush=True)
    print(f"      the Tails side by side took {time.monotonic() - started:.0f} s", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
