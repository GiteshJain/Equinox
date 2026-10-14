"""The new planner's Home side by side with the old Home on the rehearsal's copy (decision #18, build pull request 5,
spec docs/specs/2026-10-13-home.md §3): the pull request's own new planner (built into web/app/) and the old planner
(web/planner/), both at their live addresses, signed in as the same test staff user, at the same frozen moment, reading
a full local copy of Supabase restored from last night's backup.

Run by database/rehearse.sh, last (after the captured figures). Like tests/captured_figures_test.py it uses
tests/real_saves_test.py's helpers and request mapping, needs the copy, so it isn't part of tests/run_all.sh, and
nothing goes outside.

1. The moment: the copy's latest capture plus one hour, to the millisecond, as tests/captured_figures_test.py takes it.
   The captured figures read typed loads and day flags only as entered by then, while the old planner reads every one,
   so those entered later are set aside while the test runs and put back when it ends.
2. The old Home, opened as captured_figures_test.py opens the old planner (with its hook, from a copy of web/; the
   planner in web/planner/ is unchanged), its clock frozen at the moment; once it has read the capture, the backups
   and the jobs it draws Home again, and its boards are read from the page.
3. The new Home at the same moment, signed in through its own form; its boards are read from the page (data-figure and
   its data attributes). Opening either planner writes nothing. Both ask for reduced motion, so the hero's globe holds
   still (STILL below); the phone in step 7 keeps it turning.
4. Side by side: the key figures, aircraft on order (each airline's count and summary, each aircraft's row), needs
   attention (how many, how many dismissed, the groups in their order, and every item's group, words, seriousness,
   link and dismissal key), coming up (every row) and the to-do board (the open ones with their dates and steps, the
   ones done in the last 7 days, how many older) must equal the old Home's. So must the parts added in the Building
   chat's review: the hero, the game clocks, the map as first drawn (every route, base and airport with its tip,
   colour and width), with the busiest airline picked (centred on it, its routes coloured by load) and with Planned,
   and the airline cards. The loads behind them must equal the old planner's to the decimal: the group's average
   economy load from airline_cards() (and its fallback from the load reports) and every route's 7-day loads from
   route_loads(), against the old planner's own figures. The look: the computed styles of each part of Home and of what
   it draws by ::before (the folds' chevrons, the dots, the cards' bar), both pages the same width, at 1280 and 380 px. A difference fails and names the board, the item and both values, unless it
   is a known difference (KNOWN below, each with its rule), which is printed with how often it was used and both values.
   Since the switch (build pull request 13) the interline line is compared too, and, because last night's copy may have
   every interline pair answered (so neither Home shows it), once more with every agreement set to "requested" for the
   test: both Homes read again must show the same line and the same needs attention; the statuses are then put back.
5. Real saves in the new Home, by its own buttons: tick the first open to-do; add one with two steps; the old planner,
   opened again, shows the same to-do board; delete the new one (the planner asks in the page, never a browser
   dialog); dismiss an item of needs attention with ×; the old planner shows it dismissed too; show again; the old
   planner shows none dismissed. Each writes exactly its rows, logged as planner with the tab's ID.
6. A preview address (127.0.0.1) shows Home, and a tick, an add and a dismiss there send no write.
7. At 380 px wide Home has no sideways scroll and no errors. The screenshots of the new Home and of the old Home at
   380 px and at 1280 px are taken by step 4's look, each pair at the same width and moment, before step 5's saves; they
   go to HOME_SCREENS_DIR (the run's home-screens artifact), when it's set.
8. Nothing went outside: no request reached the live Supabase host or any address but the local server and the copy.

Prints registrations, airport codes, counts and the boards' words, never anything else from the rows, since the log is
posted on the pull request. Never prints the local keys or the test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL, SECRET_TABLES and HOME_SCREENS_DIR.
Usage: python3 tests/home_side_by_side_test.py
"""
import asyncio, atexit, json, os, re, secrets, shutil, sys, tempfile
from collections import Counter
from pathlib import Path
from harness import ROOT, WEB, LIVE_HOST, serve, settle
from playwright.async_api import async_playwright
import real_saves_test as rs
from real_saves_test import (count_changes, counts, is_planner_user, library, local_env, log_since, make_user, marks, planner_facts,
                             psql, token_for, why)
import planner_next_test as pn
from captured_figures_test import HOOK, HOOK_BEFORE, HELD, put_back, set_aside

SCREENS_DIR = os.environ.get("HOME_SCREENS_DIR")
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"
# the old planner's screens by its own names, and the new planner's for the same screen
OLD_VIEW = {"home": "home", "routes": "routes", "tails": "tails", "hub": "hubs", "review": "check", "finance": "review",
            "interline": "interline", "photos": "photos", "ref": "reference"}
failures = []

# Where the new Home follows its spec and the old Home did otherwise. Each is allowed only where its test says, and
# printed with how often it was used and both values.
# (The average load was one, until the Building chat's review: airline_cards() now gives the old Home's own figure, every
# captured flight of the group over the last 8 days, so it must be equal, and step 4's loads check it to the decimal.)
# (The interline line was one, until the switch, build pull request 13: the new Home words it from Interline's rows, on
# the setting interline_rules, so it must be equal, and the side by side says what each Home's line reads.)
KNOWN = {
    "order on a tie": {
        "rule": "aircraft that tie (the same check day, the same delivery time) are in the old planner's list order, kept only in "
                "the adapter's extra; the new planner orders them by aircraft id. The same aircraft, in another order.",
        "used": 0, "where": []},
    "what a map click opens": {
        "rule": "the old map's tips end with what a click opens there (a route's or a plan card's pop-up). A route's pop-up came "
                "with Routes (build pull request 6), so a route's tip now ends as the old one's; a plan card's pop-up isn't rebuilt "
                "yet, so a planned route's tip ends with where a click goes instead (the aircraft in Aircraft on order). Everything "
                "before that last part is compared.",
        "used": 0, "where": []},
    "the hero's times": {
        "rule": "the old hero (eqStats) counts a flight as today's when its hub's local weekday is today's UTC weekday, and gives "
                "each return its outbound's weekdays; the library (summary.now, positions) uses each leg's own UTC weekdays "
                "(flight_legs.days_utc). Flights near midnight UTC can count on another day, and aircraft on an overnight "
                "return be in the air or not.",
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


# ---------- reading the two Homes ----------
OLD_HOME = r"""() => {
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const boards = [...document.querySelectorAll("#view .board")];
  const titled = t => boards.find(b => { const h = b.querySelector(":scope > h3.rh, :scope > .maph h3.rh"); return h && T(h).startsWith(t); });
  const out = { kpis: [...document.querySelectorAll("#view .kpis .kpi")].map(T) };
  const oob = document.querySelector("#view .oob");
  out.onOrder = oob ? { chips: [...oob.querySelectorAll(".gsum .gchip")].map(T), groups: [...oob.querySelectorAll("details.gsec")].map(d => ({
      summary: T(d.querySelector("summary")),
      rows: [...d.querySelectorAll("tr[id^='oo-']")].map(tr => { const td = [...tr.querySelectorAll("td")];
        return { cells: td.slice(0, 6).map(T), file: !!tr.querySelector("[data-planfile]"), noCard: /no plan card/.test(T(td[6])) }; }) })) } : null;
  const att = titled("Needs attention");
  const top = att.querySelector(":scope > ul.att");
  out.attention = {
    note: T(att.querySelector("h3 .note")),
    hidden: T([...att.querySelectorAll(":scope > .dim")].find(x => /dismissed/.test(x.textContent))),
    top: top ? [...top.children].map(li => li.classList.contains("attg") ? "group: " + T(li.querySelector("summary b")) + " · " + li.querySelectorAll("ul.sub > li").length
                                                                       : "item: " + T(li.querySelector("button.link"))) : [],
    items: top ? [...top.querySelectorAll("li:not(.attg)")].map(li => { const b = li.querySelector("button.link"), g = li.closest("li.attg");
      return { group: g ? T(g.querySelector("summary b")) : "", cls: li.className.trim(), text: T(b), view: b.dataset.goto || "",
               tail: b.dataset.gotail || "", route: b.dataset.goroute || "", key: (li.querySelector("[data-dismiss]") || {dataset: {}}).dataset.dismiss || "" }; }) : [],
  };
  const up = titled("Coming up");
  out.comingUp = [...up.querySelectorAll("table.tbl tr")].filter(tr => tr.querySelector("td")).map(tr => [...tr.querySelectorAll("td")].map(T));
  const todo = document.querySelector("#view .todob");
  const item = li => ({ key: (li.querySelector("[data-tododone]") || {dataset: {}}).dataset.tododone || "", title: T(li.querySelector(".ttl b")),
    when: T(li.querySelector(".ttl .dim")), steps: [...li.querySelectorAll("ol > li")].map(T), done: !!(li.querySelector("input[type=checkbox]") || {}).checked });
  out.todo = { note: T(todo.querySelector("h3 .note")), open: [...todo.querySelectorAll(":scope > ul.todo > li")].map(item),
    done: [...todo.querySelectorAll("details.tdone ul.todo > li")].map(item), fold: T(todo.querySelector("details.tdone summary")) };
  return out;
}"""

NEW_HOME = r"""() => {
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const out = { kpis: [...document.querySelectorAll('[data-figure="home: key figures"]')].map(T) };
  const oob = document.querySelector('[data-figure="home: aircraft on order"]');
  out.onOrder = oob ? { chips: [...oob.querySelectorAll(".gsum .gchip")].map(T), groups: [...oob.querySelectorAll("details.gsec")].map(d => ({
      summary: T(d.querySelector("summary")),
      rows: [...d.querySelectorAll("tr[data-oo-row]")].map(tr => { const td = [...tr.querySelectorAll("td")];
        return { cells: td.slice(0, 6).map(T), file: !!tr.querySelector("[data-file-into-planner]"), noCard: /no plan card/.test(T(td[6])) }; }) })) } : null;
  const att = document.querySelector('[data-figure="home: needs attention"]');
  const top = att.querySelector(":scope > ul.att");
  out.attention = {
    note: T(att.querySelector("h3 .note")),
    hidden: T(att.querySelector("[data-dismissed]")),
    top: top ? [...top.children].map(li => li.classList.contains("attg") ? "group: " + T(li.querySelector("summary b")) + " · " + li.querySelectorAll("ul.sub > li").length
                                                                       : "item: " + T(li.querySelector(".link"))) : [],
    items: [...att.querySelectorAll("[data-att-item]")].map(li => { const g = li.closest("li.attg");
      return { group: g ? T(g.querySelector("summary b")) : "", cls: li.dataset.cls, text: T(li.querySelector(".link")), view: li.dataset.screen,
               tail: li.dataset.tail, route: li.dataset.route, key: li.dataset.attKey, href: li.querySelector(".link").getAttribute("href") }; }),
  };
  out.comingUp = [...document.querySelectorAll("#coming-up tr[data-up]")].map(tr => [...tr.querySelectorAll("td")].map(T));
  const todo = document.querySelector("#todo");
  const item = li => ({ key: li.dataset.todo, title: T(li.querySelector(".ttl b")), when: T(li.querySelector(".ttl .dim")),
    steps: [...li.querySelectorAll("ol > li")].map(T), done: li.dataset.done === "yes" });
  out.todo = { note: T(todo.querySelector("h3 .note")), open: [...todo.querySelectorAll("[data-todo-list=open] > li")].map(item),
    done: [...todo.querySelectorAll("[data-todo-list=done] > li")].map(item), fold: T(todo.querySelector("details.tdone summary")) };
  return out;
}"""


# The hero, the game clocks, the map and the airline cards, read the same way from either page: both draw them with the
# same classes (the new planner ports the old planner's markup); the map's airports sit in a group of their own in the
# new one, and its route hits are marked data-route-id there (data-route in the old).
PARTS = r"""(old) => {
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  const cls = e => [...e.classList].sort().join(" ");
  const hero = { air: T(document.querySelector("#eqh-air")), hello: T(document.querySelector("#eqh-hi")),
    tiles: [...document.querySelectorAll(".eqh-tiles > div")].map(d => [T(d.querySelector("b")), T(d.querySelector("span"))]) };
  const clocks = [...document.querySelectorAll("#clocks .zc")].map(z => (z.classList.contains("day") ? "day" : "night") + " " + T(z.querySelector(".zt")) + " · " + T(z.querySelector(".zh")));
  const w = document.querySelector(".mapwrap"), s = w && w.querySelector("svg.wmap");
  const map = !s ? null : {
    note: T(document.querySelector(old ? "#view .mapb .rh .note" : "[data-board=network] .rh .note")),
    view: s.getAttribute("viewBox"), key: !!w.querySelector(".mapkey"),
    routes: (() => { const arcs = [...s.querySelectorAll(".arcs path")], hits = [...s.querySelectorAll(old ? ".hits path.hit[data-route]" : ".hits path.hit[data-route-id]")];
      return arcs.map((a, i) => ({ tip: hits[i] ? hits[i].getAttribute("data-tip") : "", stroke: (a.getAttribute("stroke") || "").toLowerCase(), width: a.getAttribute("stroke-width") })); })(),
    planned: (() => { const arcs = [...s.querySelectorAll(".parcs path")], hits = [...s.querySelectorAll(".hits path.hit[data-reg]")];
      return arcs.map((a, i) => ({ tip: hits[i] ? hits[i].getAttribute("data-tip") : "", stroke: (a.getAttribute("stroke") || "").toLowerCase() })); })(),
    hubs: [...s.querySelectorAll("g.hub")].map(g => { const c = g.querySelector("circle:not(.hitc)"), h = g.querySelector("circle.hitc");
      return { cls: cls(g), r: c.getAttribute("r"), fill: (c.getAttribute("fill") || "").toLowerCase(), tip: h.getAttribute("data-tip"), code: T(g.querySelector("text")) }; }),
    airports: [...s.querySelectorAll("circle.ap")].map(c => { const h = c.nextElementSibling, l = h && h.nextElementSibling;
      return { cls: cls(c), tip: h ? h.getAttribute("data-tip") : "", label: l && l.matches("text.al") ? T(l) : "" }; }),
  };
  const cards = [...document.querySelectorAll(".agrid .acard")].map(c => ({
    name: (c.querySelector(".ach img") || {}).alt || T(c.querySelector(".ach b")), logo: !!c.querySelector(".ach img.alogo"),
    flying: T(c.querySelector(".ach .pill")) + " (" + ((c.querySelector(".ach .pill") || {}).className || "") + ")",
    tags: [...c.querySelectorAll(".acb .hubtag")].map(t => [T(t), t.classList.contains("on"), t.classList.contains("fc"), t.title]),
    figures: T(c.querySelector(".acs")), pills: [...c.querySelectorAll(".acf .pill")].map(p => cls(p) + ": " + T(p)),
    link: T(c.querySelector(".link")), photo: c.classList.contains("eqphoto") }));
  return { hero, clocks, map, cards };
}"""


def comma_set(s):
    return sorted(x.strip() for x in s.split(","))


def core(tip):
    """A map tip without its last part, which says what a click opens (known: "what a map click opens")."""
    return tip.rsplit(" · ", 1)[0]


def compare_map(om, nm, label):
    """The map drawn by each, as it stands: its note and view, every route (tip, colour, width), every planned route,
    every base and every airport with their tips."""
    p = []
    if (om is None) != (nm is None):
        return [f"{label}: the old Home {'has' if om else 'has no'} map, the new {'has' if nm else 'has no'}"]
    if om is None:
        return p
    if om["note"] != nm["note"]:
        p.append(f"{label}: the note: old {om['note']!r}, new {nm['note']!r}")
    ov, nv = [float(x) for x in om["view"].split()], [float(x) for x in nm["view"].split()]
    if any(abs(a - b) > 0.15 for a, b in zip(ov, nv)):
        p.append(f"{label}: the view (viewBox): old {om['view']}, new {nm['view']}")
    if om["key"] != nm["key"]:
        p.append(f"{label}: the loads key: old {'shown' if om['key'] else 'none'}, new {'shown' if nm['key'] else 'none'}")
    for part in ("routes", "planned"):
        tips_differ = [x for x, y in zip(sorted(om[part], key=lambda r: core(r["tip"])), sorted(nm[part], key=lambda r: core(r["tip"]))) if x["tip"] != y["tip"]]
        if tips_differ:
            known("what a map click opens", f"{label}: {part}, e.g. old {tips_differ[0]['tip'].rsplit(' · ', 1)[-1]!r}")
        oc = Counter(json.dumps(dict(r, tip=core(r["tip"])), sort_keys=True) for r in om[part])
        nc = Counter(json.dumps(dict(r, tip=core(r["tip"])), sort_keys=True) for r in nm[part])
        for k in sorted((oc - nc).keys())[:8]:
            p.append(f"{label}: {part}: only the old map has {k}")
        for k in sorted((nc - oc).keys())[:8]:
            p.append(f"{label}: {part}: only the new map has {k}")
    for part in ("hubs", "airports"):
        oc, nc = Counter(json.dumps(x, sort_keys=True) for x in om[part]), Counter(json.dumps(x, sort_keys=True) for x in nm[part])
        for k in sorted((oc - nc).keys())[:8]:
            p.append(f"{label}: {part}: only the old map has {k}")
        for k in sorted((nc - oc).keys())[:8]:
            p.append(f"{label}: {part}: only the new map has {k}")
    return p


def compare_parts(o, n):
    """The hero, the game clocks, the map (as first drawn) and the airline cards."""
    p = []
    oh, nh = o["hero"], n["hero"]
    if oh["hello"] != nh["hello"]:
        p.append(f"the hero's greeting: old {oh['hello']!r}, new {nh['hello']!r}")
    if [t[1] for t in oh["tiles"]] != [t[1] for t in nh["tiles"]]:
        p.append(f"the hero's tiles: old {oh['tiles']}, new {nh['tiles']}")
    else:
        for (ov, ol), (nv, nl) in zip(oh["tiles"], nh["tiles"]):
            if ov == nv:
                continue
            if ol in ("flights today", "departing in the next hour"):
                known("the hero's times", f"{ol}: old {ov}, new {nv}")
            else:
                p.append(f"the hero's tile {ol!r}: old {ov!r}, new {nv!r}")
    if oh["air"] != nh["air"]:
        known("the hero's times", f"aircraft in the air: old {oh['air']}, new {nh['air']}")
    if o["clocks"] != n["clocks"]:
        p.append(f"the game clocks: old {o['clocks']}, new {n['clocks']}")
    p += compare_map(o["map"], n["map"], "the map, all airlines")
    oc, nc = {c["name"]: c for c in o["cards"]}, {c["name"]: c for c in n["cards"]}
    if list(oc) != list(nc):
        p.append(f"the airline cards: old {list(oc)}, new {list(nc)}")
    for name in oc:
        a, b = oc[name], nc.get(name)
        if b is None:
            continue
        for k in ("logo", "flying", "tags", "figures", "pills", "link", "photo"):
            if a[k] != b[k]:
                p.append(f"the airline card {name}: {k}: old {a[k]!r}, new {b[k]!r}")
    return p


def compare(old, new):
    """Problems, board by board: each names the board, the item and both values."""
    p = []
    # key figures
    if len(old["kpis"]) != len(new["kpis"]):
        p.append(f"key figures: the old Home shows {len(old['kpis'])}, the new {len(new['kpis'])}")
    for i, (o, n) in enumerate(zip(old["kpis"], new["kpis"])):
        if o == n:
            continue
        p.append(f"key figures: figure {i + 1}: old {o!r}, new {n!r}")

    # aircraft on order
    oo, no = old["onOrder"], new["onOrder"]
    if (oo is None) != (no is None):
        p.append(f"aircraft on order: the old Home {'has' if oo else 'has no'} board, the new {'has' if no else 'has no'}")
    elif oo:
        if oo["chips"] != no["chips"]:
            p.append(f"aircraft on order: airlines and counts: old {oo['chips']}, new {no['chips']}")
        for og, ng in zip(oo["groups"], no["groups"]):
            if og["summary"] != ng["summary"]:
                p.append(f"aircraft on order: summary: old {og['summary']!r}, new {ng['summary']!r}")
            if og["rows"] != ng["rows"]:
                if sorted(map(json.dumps, og["rows"])) == sorted(map(json.dumps, ng["rows"])):
                    known("order on a tie", "aircraft on order: " + og["summary"].split(" ", 2)[0])
                else:
                    for i, (a, b) in enumerate(zip(og["rows"], ng["rows"])):
                        if a != b:
                            p.append(f"aircraft on order: row {i + 1} ({a['cells'][0]}): old {a}, new {b}")
                    if len(og["rows"]) != len(ng["rows"]):
                        p.append(f"aircraft on order: {og['summary'][:30]}: old {len(og['rows'])} rows, new {len(ng['rows'])}")
        if len(oo["groups"]) != len(no["groups"]):
            p.append(f"aircraft on order: old {len(oo['groups'])} airlines, new {len(no['groups'])}")

    # needs attention (the interline line included since the switch, build pull request 13)
    oa, na = old["attention"], new["attention"]
    o_items, n_items = list(oa["items"]), list(na["items"])
    if interline_line(old) != interline_line(new):
        p.append(f"needs attention: the interline line: old {interline_line(old)!r}, new {interline_line(new)!r}")
    if oa["note"] != na["note"]:
        p.append(f"needs attention: how many: old {oa['note']!r}, new {na['note']!r}")
    if oa["hidden"] != na["hidden"]:
        p.append(f"needs attention: dismissed: old {oa['hidden']!r}, new {na['hidden']!r}")
    if oa["top"] != na["top"]:
        p.append(f"needs attention: the groups in their order: old {oa['top']}, new {na['top']}")
    norm = lambda x: (x["group"], x["cls"], x["text"], OLD_VIEW.get(x["view"], x["view"]) if "href" not in x else x["view"], x["tail"], x["route"], x["key"])
    oc, nc = Counter(norm(x) for x in o_items), Counter(norm(x) for x in n_items)
    for k in sorted((oc - nc).keys(), key=str):
        p.append(f"needs attention: only the old Home has: group {k[0] or '(alone)'}, {k[1]}, {k[2]!r}, link {k[3]} {k[4]}{k[5]}, key {k[6]!r}")
    for k in sorted((nc - oc).keys(), key=str):
        p.append(f"needs attention: only the new Home has: group {k[0] or '(alone)'}, {k[1]}, {k[2]!r}, link {k[3]} {k[4]}{k[5]}, key {k[6]!r}")
    if not (oc - nc) and not (nc - oc) and [norm(x) for x in o_items] != [norm(x) for x in n_items]:
        groups = {norm(x)[0] for x, y in zip(o_items, n_items) if norm(x) != norm(y)}
        if groups <= {"Maintenance", "Turns and positions", "One-week checks due"}:
            known("order on a tie", "needs attention: " + ", ".join(sorted(groups)))
        else:
            p.append(f"needs attention: the same items in another order, in {', '.join(sorted(groups))}")

    # coming up
    if len(old["comingUp"]) != len(new["comingUp"]):
        p.append(f"coming up: old {len(old['comingUp'])} rows, new {len(new['comingUp'])}")
    for i, (o, n) in enumerate(zip(old["comingUp"], new["comingUp"])):
        if o == n:
            continue
        if o[0] == n[0] and o[1].split(" ", 1)[0] == "Check" == n[1].split(" ", 1)[0] and comma_set(o[1][6:]) == comma_set(n[1][6:]):
            known("order on a tie", "coming up " + o[0].split(" ·")[0])
            continue
        p.append(f"coming up: row {i + 1}: old {o}, new {n}")

    # the to-do board
    ot, nt = old["todo"], new["todo"]
    for part in ("note", "fold"):
        if ot[part] != nt[part]:
            p.append(f"to-do: {part}: old {ot[part]!r}, new {nt[part]!r}")
    for part in ("open", "done"):
        if ot[part] != nt[part]:
            ok_, nk_ = [x["key"] for x in ot[part]], [x["key"] for x in nt[part]]
            if ok_ != nk_:
                p.append(f"to-do: the {part} ones (ids, in order): old {ok_}, new {nk_}")
            for a, b in zip(ot[part], nt[part]):
                if a != b and a["key"] == b["key"]:
                    p.append(f"to-do {a['key']}: old {a}, new {b}")
    return p


def interline_line(h):
    """The interline line in needs attention (the old Home's, and the new one's since the switch), or None."""
    return next((x["text"] for x in h["attention"]["items"] if x["text"].startswith("Interline:")), None)


def summary(h):
    a = h["attention"]
    return (f"{len(h['kpis'])} key figures ({' · '.join(h['kpis'])}); aircraft on order: {', '.join(h['onOrder']['chips']) if h['onOrder'] else 'none'}; "
            f"needs attention: {a['note']}{', ' + a['hidden'] if a['hidden'] else ''} ({'; '.join(a['top'][:14])}); "
            f"coming up: {len(h['comingUp'])} rows; to-do: {h['todo']['note']}")


# ---------- the loads behind Home, to the decimal ----------
OLD_LOADS = r"""() => JSON.parse(window.__eqOld(`JSON.stringify((() => {
  const cap = Object.values(CAP.loads).filter(x => x.eco != null && x.flight_date >= addDays(today(), -7)).map(x => +x.eco);
  const routes = Object.entries(loadStats()).filter(([k]) => !k.startsWith("F|")).map(([k, a]) => [k, a.n, a.sum, a.days.size]);
  let n = 0, s = 0; for (const r of routes) { n += r[1]; s += r[2]; }
  return { captured: cap.length, captured_avg: cap.length ? cap.reduce((a, b) => a + b, 0) / cap.length : null, reported: n, reported_avg: n ? s / n : null, routes };
})())`))"""


def loads_exact(moment, old_loads):
    """The group's average economy load (from captures, and its fallback from the load reports) and each route's loads
    over 7 days, as airline_cards() and route_loads() give them at the moment, against the old planner's own figures."""
    p = []
    cards = json.loads(psql(f"select (x - 'airlines' - 'group_today')::text from private.fig_airline_cards({WORLD}, :'m'::timestamptz) x", m=moment))
    rl = json.loads(psql("select coalesce(jsonb_agg(jsonb_build_array(a.planner_name || '|' || (r ->> 'hub') || '|' || (r ->> 'dest'), (r ->> 'departures')::int, "
                         f"(r ->> 'sum')::numeric, (r ->> 'days')::int)), '[]')::text from jsonb_array_elements(private.fig_route_loads({WORLD}, :'m'::timestamptz) -> 'routes') r "
                         "join public.airlines a on a.id = (r ->> 'airline_id')::bigint", m=moment))
    o = old_loads
    close = lambda a, b: (a is None and b is None) or (a is not None and b is not None and abs(float(a) - float(b)) < 1e-9)
    if o["captured"]:
        if cards.get("load_7_days_from") != "captures" or cards.get("load_7_days_flights") != o["captured"] or not close(cards.get("load_7_days"), o["captured_avg"]):
            p.append(f"the group's average load: old {o['captured_avg']} over {o['captured']} captured flights, airline_cards() {cards.get('load_7_days')} over "
                     f"{cards.get('load_7_days_flights')} from {cards.get('load_7_days_from')}")
    elif cards.get("load_7_days_from") != ("reports" if o["reported"] else None) or not close(cards.get("load_7_days"), o["reported_avg"]):
        p.append(f"the group's average load: old {o['reported_avg']} over {o['reported']} reported flights, airline_cards() {cards.get('load_7_days')} from {cards.get('load_7_days_from')}")
    n = sum(r[1] for r in rl)
    fallback = sum(float(r[2]) for r in rl) / n if n else None
    if n != o["reported"] or not close(fallback, o["reported_avg"]):
        p.append(f"the load reports' average (the fallback): old {o['reported_avg']} over {o['reported']} flights, route_loads() {fallback} over {n}")
    om, nm = {r[0]: r for r in o["routes"]}, {r[0]: r for r in rl}
    for k in sorted(set(om) | set(nm)):
        a, b = om.get(k), nm.get(k)
        if a is None or b is None:
            p.append(f"route loads: {k}: only {'route_loads()' if a is None else 'the old planner'} has it")
        elif a[1] != b[1] or a[3] != b[3] or abs(float(a[2]) - float(b[2])) > 1e-6:
            p.append(f"route loads: {k}: old {a[1]} departures, sum {a[2]}, {a[3]} days; route_loads() {b[1]}, {b[2]}, {b[3]}")
    label = (f"the loads behind Home equal the old planner's to the decimal: the group's average economy load "
             f"({cards.get('load_7_days')} over {cards.get('load_7_days_flights')} flights, from {cards.get('load_7_days_from')}), its fallback from "
             f"the load reports ({fallback} over {n} flights) and each route's loads over 7 days ({len(rl)} routes)")
    return label, p


async def map_views(old, new):
    """The map with one airline picked (centred on its busiest base, its routes coloured by load), then with Planned
    shown, in both planners, against each other; then back to all airlines."""
    p = []
    names = await new.pg.evaluate("[...document.querySelectorAll('[data-board=network] .mleg .mf[title]')].map(b => b.title)")
    busiest = await new.pg.evaluate(r"""() => { const n = {}; for (const h of document.querySelectorAll('svg.wmap .hits path.hit[data-route-id]'))
      { const a = h.getAttribute('data-tip').split(' · ')[1]; n[a] = (n[a] || 0) + 1; } return Object.entries(n).sort((a, b) => b[1] - a[1])[0][0]; }""")
    al = busiest if busiest in names else names[0]
    await old.pg.click(f"#view .mapb [data-mapal={json.dumps(al)}]")
    await new.pg.click(f"[data-board=network] .mleg .mf[title={json.dumps(al)}]")
    await new.pg.wait_for_selector("[data-board=network][data-map-loads=ready]", timeout=30000)
    await settle(old.pg, 600)
    await settle(new.pg, 600)
    o1, n1 = await old.pg.evaluate(PARTS, True), await new.pg.evaluate(PARTS, False)
    p += compare_map(o1["map"], n1["map"], f"the map, {al} with its loads")
    coloured = Counter(r["stroke"] for r in n1["map"]["routes"]) if n1["map"] else Counter()
    await old.pg.click("#view .mapb [data-mapal='']")
    await new.pg.click("[data-board=network] .mleg .mf:not([title])")
    await old.pg.click("#view [data-mapopt=planned]")
    await new.pg.click(".mapopt button")
    await new.pg.wait_for_function("document.querySelectorAll('svg.wmap .parcs path').length > 0 || !document.querySelector('[data-oo-row]')", timeout=30000)
    await settle(old.pg, 600)
    await settle(new.pg, 600)
    o2, n2 = await old.pg.evaluate(PARTS, True), await new.pg.evaluate(PARTS, False)
    p += compare_map(o2["map"], n2["map"], "the map with Planned")
    planned = len(n2["map"]["planned"]) if n2["map"] else 0
    await old.pg.click("#view [data-mapopt=planned]")
    await new.pg.click(".mapopt button")
    await settle(old.pg, 400)
    await settle(new.pg, 400)
    colours = ", ".join(f"{c} ×{k}" for c, k in coloured.most_common())
    return (f"the map with one airline ({al}: centred on its busiest base, its {sum(coloured.values())} routes coloured by load: {colours}) and with "
            f"Planned ({planned} planned routes) equals the old map"), p


# ---------- the look: computed styles, part by part ----------
LOOK = [   # (part, the old planner's selector, the new planner's)
    ("hero", "#eqhero", "#eqhero"), ("hero title", ".eqh-t", ".eqh-t"), ("hero greeting", ".eqh-hi", ".eqh-hi"), ("hero tile", ".eqh-tiles div", ".eqh-tiles div"),
    ("hero tile figure", ".eqh-tiles b", ".eqh-tiles b"), ("hero tile words", ".eqh-tiles span", ".eqh-tiles span"),
    ("clocks", "#clocks", "#clocks"), ("clock", "#clocks .zc", "#clocks .zc"), ("clock time", "#clocks .zt", "#clocks .zt"), ("clock zone", "#clocks .zo", "#clocks .zo"),
    ("clock bases", "#clocks .zh", "#clocks .zh"), ("the band", "#terminator", "#terminator"), ("page", "body", "body"), ("the screen", "#view", "main.view"),
    ("map board", "#view .mapb", "[data-board=network]"), ("map title", "#view .mapb .rh", "[data-board=network] .rh"),
    ("map note", "#view .mapb .rh .note", "[data-board=network] .rh .note"), ("airline button, on", "#view .mapb .mf.on", "[data-board=network] .mf.on"),
    ("airline button", "#view .mapb .mf:not(.on)", "[data-board=network] .mf:not(.on)"), ("map box", "#view .mapwrap", ".mapwrap"), ("map", "svg.wmap", "svg.wmap"),
    ("zoom button", ".mapz button", ".mapz button"), ("Planned button", ".mapopt button", ".mapopt button"), ("sea", ".wmap .sea", ".wmap .sea"),
    ("land", ".wmap .land", ".wmap .land"), ("night", ".wmap .night", ".wmap .night"), ("route line", ".wmap .arcs path", ".wmap .arcs path"),
    ("base dot", ".wmap .hub.live circle", ".wmap .hub.live circle"), ("base code", ".wmap .hub.live text", ".wmap .hub.live text"), ("airport", ".wmap circle.ap", ".wmap circle.ap"),
    ("on order", "#view .oob", "[data-figure='home: aircraft on order']"), ("on order title", "#view .oob .rh", "[data-figure='home: aircraft on order'] .rh"),
    ("count chip", ".oob .gchip", "[data-figure='home: aircraft on order'] .gchip"), ("airline row", ".oob details.gsec", "[data-figure='home: aircraft on order'] details.gsec"),
    ("airline row head", ".oob details.gsec > summary", "[data-figure='home: aircraft on order'] details.gsec > summary"),
    ("to-file pill", ".oob summary .pill", "[data-figure='home: aircraft on order'] summary .pill"),
    ("two columns", "#view .hgrid", "main .hgrid"), ("needs attention", "#view .hgrid > .board", "#attention"), ("attention line", "#view .hgrid .att > li", "#attention .att > li"),
    ("attention words", "#view .hgrid .att > li .link", "#attention .att > li .link"), ("attention group", "#view .att > li.attg", "#attention .att > li.attg"),
    ("coming up tag", "#view .evt", "#coming-up .evt"), ("table head", "#view .hgrid .tbl th", "#coming-up .tbl th"), ("table cell", "#view .hgrid .tbl td", "#coming-up .tbl td"),
    ("coming up day", "#view .hgrid .tbl td b", "#coming-up .tbl td b"),
    ("to-do board", "#view .todob", "#todo"), ("to-do line", "#view .todob ul.todo > li", "#todo ul.todo > li"), ("to-do title", "#view .todob .ttl b", "#todo .ttl b"),
    ("to-do words", "#view .todob .tbody", "#todo .tbody"), ("to-do steps", "#view .todob ol", "#todo ol"), ("to-do date words", "#view .todob .ttl .dim", "#todo .ttl .dim"),
    ("to-do title box", "#todo-title", "#todo-title"), ("to-do date box", "#todo-date", "#todo-date"), ("Add", "#todo-add", "#todo-add"),
    ("airline cards", "#view .agrid", ".agrid"), ("airline card", "#view .acard", ".acard"), ("card head", "#view .ach", ".ach"), ("card pill", "#view .ach .pill", ".ach .pill"),
    ("base tag", "#view .hubtag.on", ".hubtag.on"), ("focus city tag", "#view .hubtag.fc", ".hubtag.fc"), ("card figures", "#view .acs", ".acs"),
    ("card figure", "#view .acs b", ".acs b"), ("card words", "#view .acs span", ".acs span"), ("card bases", "#view .acb", ".acb"),
    ("card pills", "#view .acf .pill", ".acf .pill"), ("Open fleet", "#view .acard .link", ".acard .link"),
    # drawn by ::before: the folds' chevrons, the attention dots, the cards' colour bar, the clocks' day or night dot
    ("airline row arrow", ".oob details.gsec > summary::before", "[data-figure='home: aircraft on order'] details.gsec > summary::before"),
    ("done fold", "#view .todob details.tdone > summary", "#todo details.tdone > summary"),
    ("done fold arrow", "#view .todob details.tdone > summary::before", "#todo details.tdone > summary::before"),
    ("attention dot", "#view .hgrid .att > li::before", "#attention .att > li::before"),
    ("card colour bar", "#view .acard::before", ".acard::before"), ("clock dot", "#clocks .zc::before", "#clocks .zc::before"),
]
LOOK_PROPS = ["display", "position", "color", "background-color", "background-image", "font-family", "font-size", "font-weight", "font-stretch", "line-height",
              "letter-spacing", "font-variant-numeric", "font-feature-settings", "text-transform", "text-align", "white-space", "padding-top", "padding-right",
              "padding-bottom", "padding-left", "margin-top", "margin-bottom", "border-top-left-radius", "border-top-width", "border-top-color", "border-left-width",
              "box-shadow", "gap", "opacity", "fill", "stroke", "stroke-width", "r", "grid-template-columns", "flex-basis", "min-height"]
# a part drawn by ::before or ::after has these too (its size, except the card's bar, which is as wide as the card)
PSEUDO_PROPS = ["content", "transform", "width", "height", "margin-right", "background-size", "list-style-type"]
SIZE_FREE = {"card colour bar"}
# STILL: both planners here are opened asking for reduced motion, so the hero's globe is drawn once and holds still. A
# full-page screenshot of the turning globe (WebGL drawn by the CPU on the runners) took 10 to 30 s and once timed out;
# held still, under a second. The phone step (7) and tests/planner_next_test.py keep it turning.
SHOT_MS = 90000
STYLES = """([pairs, props, pprops]) => pairs.map(([name, sel]) => { const [s, pseudo] = sel.split(/(?=::(?:before|after)$)/);
  const el = document.querySelector(s); if (!el) return [name, null];
  const cs = getComputedStyle(el, pseudo || null); const o = {};
  for (const p of (pseudo ? props.concat(pprops) : props)) o[p] = cs.getPropertyValue(p); return [name, o]; })"""


async def look(old, new):
    """The computed styles of each part of Home, the old planner's against the new's, at 1280 and at 380 px wide (both
    pages the same width), and of what each draws by ::before (a fold's chevron, a dot, a bar) with its content, size
    and turn; both Homes' screenshots at each width go into the artifact. Sizes that depend on the content (an
    element's width and height, a grid's columns) aren't compared; a gap only on flex or grid boxes, where it shows."""
    p, n_parts, neither = [], 0, []
    for width, height in ((1280, 900), (380, 800)):
        await old.pg.set_viewport_size({"width": width, "height": height})
        await new.pg.set_viewport_size({"width": width, "height": height})
        await settle(old.pg, 900)
        await settle(new.pg, 900)
        os_ = dict(await old.pg.evaluate(STYLES, [[[n, o] for n, o, _ in LOOK], LOOK_PROPS, PSEUDO_PROPS]))
        ns_ = dict(await new.pg.evaluate(STYLES, [[[n, s] for n, _, s in LOOK], LOOK_PROPS, PSEUDO_PROPS]))
        for name, _, _ in LOOK:
            o, x = os_.get(name), ns_.get(name)
            if o is None and x is None:
                # neither Home draws it on this copy (no aircraft on order, say): nothing to compare, named in the line
                if name not in neither:
                    neither.append(name)
                continue
            if o is None or x is None:
                p.append(f"{width} px: {name}: {'the old Home has none' if o is None else ''}{' and ' if o is None and x is None else ''}{'the new Home has none' if x is None else ''}")
                continue
            n_parts += 1
            diffs = [f"{k} old {o[k]!r}, new {x[k]!r}" for k in o
                     if o[k] != x[k] and not (k == "gap" and "flex" not in o["display"] and "grid" not in o["display"]) and not (k == "grid-template-columns")
                     and not (name in SIZE_FREE and k in ("width", "height"))]
            if diffs:
                p.append(f"{width} px: {name}: " + "; ".join(diffs)[:600])
        if SCREENS_DIR:   # both Homes at the same moment, width and state (before step 5's saves), so each pair compares
            Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
            await old.pg.screenshot(path=str(Path(SCREENS_DIR) / f"old-home-{width}.png"), full_page=True, timeout=SHOT_MS)
            await new.pg.screenshot(path=str(Path(SCREENS_DIR) / f"home-{width}.png"), full_page=True, timeout=SHOT_MS)
    await old.pg.set_viewport_size({"width": 1440, "height": 1000})
    await new.pg.set_viewport_size({"width": 1280, "height": 900})
    return (f"the look: {len(LOOK)} parts of Home (the hero, the game clocks and the band, the map, aircraft on order, needs attention, coming up, "
            f"the to-do board, the airline cards, and what they draw by ::before) have the old Home's computed styles at 1280 and 380 px "
            f"({n_parts} compared" + (f"; drawn by neither Home on this copy: {', '.join(neither)}" if neither else "") + ")"), p


# ---------- the planners ----------
def web_copy(dest):
    """A copy of web/ (the new planner's build included) with the hook added to the old planner, before its boot."""
    root = Path(dest) / "web"
    shutil.copytree(WEB, root)
    page = root / "planner" / "index.html"
    html = page.read_text()
    if html.count(HOOK_BEFORE) != 1:
        raise RuntimeError("the old planner's boot line isn't where the test expects it")
    page.write_text(html.replace(HOOK_BEFORE, HOOK + HOOK_BEFORE, 1))
    return root


class OldHome(rs.Planner):
    """The old planner (real_saves_test.py's), its clock frozen at the moment before its scripts run."""

    def __init__(self, *a, moment, **k):
        super().__init__(*a, **k)
        self.moment = moment

    async def page(self, host=LIVE_HOST):
        self.pg = pg = await self.ctx.new_page()
        await pg.clock.set_fixed_time(self.moment)
        await pg.emulate_media(reduced_motion="reduce")   # as the new Home here (STILL)
        pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
        pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
              if m.type == "error" and "Failed to load resource" not in m.text else None)
        pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await pg.goto(f"http://{host}:{self.port}/planner/old/")
        return pg

    async def home(self):
        """Once the old planner has read the capture, the backups and the jobs, Home drawn again and read."""
        pg = self.pg
        await pg.wait_for_function("() => window.__eqOld && window.__eqOld('CAP.at') > 0 && window.__eqOld('CAP.backupLoaded') "
                                   "&& window.__eqOld('CAP.jobsLoaded')", timeout=60000)
        await pg.evaluate("() => window.__eqOld('ui.view = \"home\"; render(); true')")
        await settle(pg, 800)
        return await pg.evaluate(OLD_HOME)

    async def reopen(self):
        """The old planner opened again in a new tab (signed in already), as Gitesh would look after a change."""
        await self.pg.close()
        await self.page()
        await self.pg.wait_for_function("() => window.__eqDataLoaded === true", timeout=60000)
        return await self.home()


async def new_home(pl):
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=90000)
    await settle(pl.pg, 600)
    return await pl.pg.evaluate(NEW_HOME)


# ---------- 4c. the interline line with pairs open (the switch, build pull request 13)
AGREEMENTS = f"""select coalesce(json_agg(json_build_object('id', a.id, 'status', a.status) order by a.id), '[]')
                 from public.interline_agreements a where a.world_id = {WORLD}"""


def set_statuses(rows):
    psql("""begin;
      select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'home_side_by_side_test', true);
      update public.interline_agreements x set status = s.status
        from jsonb_to_recordset(:'r'::jsonb) as s(id bigint, status text) where x.id = s.id and x.status is distinct from s.status;
      commit;""", r=json.dumps(rows))


async def interline_open(old, new):
    """Last night's copy may have every interline pair answered (14 Oct: 2 agreements, both signed), so neither Home shows
    the interline line. Every agreement is set to "requested" (to_sign) for the test, both Homes are read again, and
    needs attention must be the same in both with the line counting those pairs; then each row's status is put back."""
    rows = json.loads(psql(AGREEMENTS).strip())
    if not rows:
        return "the interline line with pairs open: the copy has no interline agreement to open (not tried)", []
    problems = []
    try:
        set_statuses([{"id": r["id"], "status": "to_sign"} for r in rows])
        o = await old.reopen()
        await new.pg.reload()
        n = await new_home(new)
        lo, ln = interline_line(o), interline_line(n)
        if not lo or not ln:
            problems.append(f"the interline line: old {lo!r}, new {ln!r} (both should show one)")
        problems += [x for x in compare(o, n) if x.startswith("needs attention")]
    finally:
        set_statuses(rows)
    if json.loads(psql(AGREEMENTS).strip()) != rows:
        problems.append("the agreements' statuses weren't put back")
    # both Homes as they were, for what follows
    await old.reopen()
    await new.pg.reload()
    await new_home(new)
    return (f"the interline line with pairs open: with the copy's {len(rows)} agreement(s) set to requested for the test, both Homes "
            f"say {ln!r}, and needs attention is the same in both; the statuses put back"), problems


async def saved(pl, mark=None, rows=0):
    """Waits until the copy's change log has the save's rows (when a mark is given), then until the new planner's header
    says saved (or preview · not saved) again."""
    if mark is not None:
        await rs.wait_for(lambda: log_since(mark), lambda got: len(got) >= rows, seconds=30)
    await settle(pl.pg, 400)
    await pl.pg.wait_for_function("() => /^(saved|preview · not saved)$/.test((document.querySelector('[data-save-state]') || {}).textContent || '')",
                                  timeout=30000)
    await settle(pl.pg, 600)


def logged_only(mark, want, client):
    """The change-log rows since the mark are exactly want (a Counter of (table, op)), each logged as planner with the
    tab's ID. Returns the problems and the rows."""
    rows = log_since(mark)
    got = Counter((r["table"], r["op"]) for r in rows)
    problems = [] if got == want else [f"the tables changed by {dict(got)}, expected {dict(want)}"]
    problems += [f"a change-log row names {r['actor']} ({r['detail']}), not planner (the tab's ID)" for r in rows
                 if r["actor"] != "planner" or r["detail"] != client]
    return problems, rows


# ---------- 5. real saves in the new Home ----------
async def real_saves(new, old, tag):
    out = []
    pg = new.pg
    client = await pg.evaluate("window.__eqPlanner.client")

    # tick the first open to-do
    first = await pg.evaluate("(document.querySelector('[data-todo-list=open] > li') || {dataset: {}}).dataset.todo || ''")
    problems = []
    if not first:
        out.append(("tick a to-do", ["the new Home shows no open to-do"]))
    else:
        tid = int(psql(f"select id from public.todos where world_id = {WORLD} and coalesce(legacy_key, id::text) = :'k'", k=first).strip())
        before = pn.todo_row(tid)
        n0, mark = counts(), marks()
        await pg.click(f"[data-todo-list=open] > li[data-todo='{first}'] input[type=checkbox]")
        await saved(new, mark, 1)
        after = pn.todo_row(tid)
        problems, _ = logged_only(mark, Counter({("todos", "update"): 1}), client)
        if not (after and after.get("done") is True and after.get("done_at")):
            problems.append("the to-do isn't done in the copy")
        other = sorted(k for k in set(before) | set(after or {}) if k not in ("done", "done_at", "updated_at") and before.get(k) != (after or {}).get(k))
        if other:
            problems.append("other columns changed: " + ", ".join(other))
        problems += count_changes(n0, counts(), allow={"public.change_log"})
        if not await pg.evaluate(f"!!document.querySelector(\"[data-todo-list=done] > li[data-todo='{first}']\")"):
            problems.append("the new Home doesn't show it done")
        out.append((f"tick the first open to-do ({first}) by its box: done and done_at in exactly that row, logged as planner with the tab's ID", problems))

    # add one with two steps
    title = f"Home side by side {tag}"
    n0, mark = counts(), marks()
    await pg.fill("#todo-title", title)
    await pg.fill("#todo-steps", "First step\nSecond step")
    await pg.click("#todo-add")
    await saved(new, mark, 3)
    await pg.wait_for_function(f"[...document.querySelectorAll('[data-todo-list=open] .ttl b')].some(b => b.textContent === {json.dumps(title)})", timeout=30000)
    problems, _ = logged_only(mark, Counter({("todos", "insert"): 1, ("todo_items", "insert"): 2}), client)
    row = json.loads(psql(f"""select coalesce((select json_build_object('id', t.id, 'key', t.legacy_key, 'due', t.due_on,
                                 'steps', (select json_agg(i.body order by i.position) from public.todo_items i where i.todo_id = t.id))
                                 from public.todos t where t.world_id = {WORLD} and t.title = :'t'), 'null')""", t=title).strip())
    if not row:
        problems.append("the new to-do isn't in the copy")
    else:
        if row["steps"] != ["First step", "Second step"]:
            problems.append(f"its steps in the copy are {row['steps']}")
        if not re.fullmatch(r"t[0-9a-z]+", row["key"] or ""):
            problems.append(f"its old-planner id isn't made as the old planner makes one: {row['key']!r}")
    problems += count_changes(n0, counts(), allow={"public.change_log", "public.todos", "public.todo_items"})
    out.append((f"add a to-do with two steps by the form: one to-do and its two steps, as one action, logged as planner with the tab's ID", problems))

    # the old planner shows the same to-do board
    o, n = await old.reopen(), await new_home(new)
    diff = [x for x in compare(o, n) if x.startswith("to-do")]
    if row and not any(t["title"] == title and t["steps"] == ["First step", "Second step"] for t in o["todo"]["open"]):
        diff.append("the old planner doesn't show the new to-do with its two steps")
    out.append(("the old planner, opened again, shows the same to-do board (the ticked one done, the new one with its steps)", diff))

    # delete it: asked in the page, never a browser dialog
    problems = []
    if row:
        n0, mark, d0 = counts(), marks(), len(new.dialogs)
        sel = f"[data-todo-list=open] > li[data-todo='{row['key']}']"
        await pg.click(f"{sel} button.dismiss")
        await pg.wait_for_selector(f"{sel} [data-confirm]", timeout=10000)
        if "Delete this to-do?" not in (await pg.text_content(f"{sel} [data-confirm]") or ""):
            problems.append("the question in the page isn't \"Delete this to-do?\"")
        await pg.click(f"{sel} [data-confirm-yes]")
        await saved(new, mark, 3)
        await pg.wait_for_selector(sel, state="detached", timeout=30000)
        p2, _ = logged_only(mark, Counter({("todos", "delete"): 1, ("todo_items", "delete"): 2}), client)
        problems += p2
        if len(new.dialogs) > d0:
            problems.append("a browser dialog was opened: " + "; ".join(new.dialogs[d0:]))
        if psql(f"select count(*) from public.todos where id = {int(row['id'])}").strip() != "0":
            problems.append("the to-do is still in the copy")
    else:
        problems.append("there was no new to-do to delete")
    out.append(("delete it: the page asks \"Delete this to-do?\" in itself (no browser dialog); the to-do and its two steps go as one action, logged as planner with the tab's ID", problems))

    # dismiss an item of needs attention, then show again
    await pg.evaluate("document.querySelectorAll('#attention details').forEach(d => d.open = true)")
    item = await pg.evaluate("(() => { const li = document.querySelector('#attention [data-att-item]'); return li ? {key: li.dataset.attKey, text: li.querySelector('.link').textContent} : null })()")
    problems = []
    if not item:
        out.append(("dismiss an item of needs attention", ["the new Home lists nothing to dismiss"]))
        return out
    hidden0 = int(await pg.evaluate("(document.querySelector('#attention [data-dismissed]') || {dataset: {dismissed: '0'}}).dataset.dismissed"))
    n0, mark = counts(), marks()
    await pg.locator("#attention [data-att-item]").first.locator("button.dismiss").click()
    await saved(new, mark, 1)
    await pg.wait_for_function(f"(document.querySelector('#attention [data-dismissed]') || {{dataset: {{}}}}).dataset.dismissed === '{hidden0 + 1}'", timeout=30000)
    problems, _ = logged_only(mark, Counter({("dismissals", "insert"): 1}), client)
    if psql(f"select count(*) from public.dismissals where world_id = {WORLD} and alert_key = :'k'", k=item["key"]).strip() != "1":
        problems.append("the dismissal isn't in the copy under the item's key")
    problems += count_changes(n0, counts(), allow={"public.change_log", "public.dismissals"})
    o, n = await old.reopen(), await new_home(new)
    if o["attention"]["hidden"] != n["attention"]["hidden"]:
        problems.append(f"the old planner says {o['attention']['hidden']!r}, the new {n['attention']['hidden']!r}")
    if any(x["key"] == item["key"] for x in o["attention"]["items"]):
        problems.append("the old planner still lists the item")
    out.append((f"dismiss \"{item['text'][:60]}\" with ×: one dismissal under the old planner's key, logged as planner with the tab's ID; "
                f"the old planner, opened again, shows it dismissed too ({n['attention']['hidden']})", problems))

    rows = int(psql(f"select count(*) from public.dismissals where world_id = {WORLD}").strip())
    n0, mark = counts(), marks()
    await pg.click("#attention [data-show-again]")
    await saved(new, mark, rows)
    await pg.wait_for_function("!document.querySelector('#attention [data-dismissed]')", timeout=30000)
    problems, _ = logged_only(mark, Counter({("dismissals", "delete"): rows}), client)
    if psql(f"select count(*) from public.dismissals where world_id = {WORLD}").strip() != "0":
        problems.append("dismissals are left in the copy")
    o = await old.reopen()
    if o["attention"]["hidden"]:
        problems.append(f"the old planner still says {o['attention']['hidden']!r}")
    out.append((f"show again: every dismissal ({rows}) goes, as one action, logged as planner with the tab's ID; the old planner, opened again, shows none dismissed", problems))
    return out


# ---------- 6. a preview ----------
async def preview(p, port, env, facts, staff, moment, seen):
    pv = pn.Planner(p, port, env, facts)
    seen.append(pv)
    problems = []
    try:
        await pv.open(host="127.0.0.1", moment=moment)
        await pv.sign_in(*staff)
        n0, mark = counts(), marks()
        await pv.pg.click("[data-todo-list=open] > li input[type=checkbox]")
        await pv.pg.fill("#todo-title", "preview check")
        await pv.pg.click("#todo-add")
        await pv.pg.evaluate("document.querySelectorAll('#attention details').forEach(d => d.open = true)")
        if await pv.pg.evaluate("!!document.querySelector('#attention [data-att-item] button.dismiss')"):
            await pv.pg.click("#attention [data-att-item] button.dismiss")
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
    return f"a preview address shows Home and a tick, an add and a dismiss there send no write (it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})", problems


# ---------- 7. a phone, and the screenshots ----------
async def phone(p, port, env, facts, staff, moment, seen):
    ph = pn.Planner(p, port, env, facts, width=380, height=800)
    seen.append(ph)
    problems = []
    try:
        await ph.open(moment=moment)
        await ph.sign_in(*staff)
        await settle(ph.pg, 1500)
        over = await ph.pg.evaluate("Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth")
        if over > 0:
            problems.append(f"the page scrolls sideways by {over} px at 380 px wide")
        globe = await ph.pg.evaluate("(document.querySelector('[data-globe]') || {dataset: {}}).dataset.globe || 'none'")
        problems += ph.errors
    finally:
        await ph.close()
    return f"at 380 px wide Home has no sideways scroll and no errors (the globe: {globe})", problems


async def main():
    facts = planner_facts()
    nfacts = pn.planner_facts()
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

    # ---------- 1. the moment, and the copy as it stood then
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

    tag = secrets.token_hex(4)
    staff = (f"home-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="home-side-by-side-"))
    seen = []
    try:
        root = web_copy(work)
        with serve(root) as port:
            async with async_playwright() as p:
                # ---------- 2 and 3. both Homes at the moment
                old = OldHome(p, port, env, facts, lib_js, moment=moment)
                new = pn.Planner(p, port, env, nfacts, width=1280, height=900)
                seen += [old, new]
                o = n = None
                try:
                    n0, mark = counts(), marks()
                    await old.open()
                    await old.sign_in(*staff)
                    o = await old.home()
                    await new.open(moment=moment)
                    await new.pg.emulate_media(reduced_motion="reduce")   # STILL: set before Home and its globe are made
                    await new.sign_in(*staff)
                    n = await new_home(new)
                    problems = list(old.errors) + list(new.errors)
                    if log_since(mark):
                        problems.append("opening the planners changed the tables")
                    problems += count_changes(n0, counts())
                    if abs(await new.pg.evaluate("Date.now()") - rs_ms(moment)) > 1000:
                        problems.append("the new planner's clock isn't frozen at the moment")
                except Exception as e:
                    problems = [why(e)] + old.errors[:3] + new.errors[:3]
                step(o is not None and n is not None and not problems,
                     f"both planners opened at the moment, signed in as test staff; opening them wrote nothing", problems)
                if o is None or n is None:
                    sys.exit(1)
                print("      the old Home: " + summary(o), flush=True)
                print("      the new Home: " + summary(n), flush=True)

                # ---------- 4. side by side
                problems = compare(o, n)
                hrefs = sorted({x["href"] for x in n["attention"]["items"]})
                step(not problems, f"side by side, every board equals the old Home's: key figures, aircraft on order, needs attention "
                     f"({len(n['attention']['items'])} items with their groups, words, seriousness, links and keys; the interline line: "
                     f"{interline_line(n) or 'none in either'}), coming up "
                     f"({len(n['comingUp'])} rows) and the to-do board ({len(n['todo']['open'])} open, {len(n['todo']['done'])} done this week)", problems)
                print("      the new Home's links: " + ", ".join(hrefs[:12]) + (" …" if len(hrefs) > 12 else ""), flush=True)

                # ---------- 4b. the hero, the clocks, the map and the airline cards; the map's other views; the loads; the look
                try:
                    # the cards' logos (the website's file) and hub-city photos (site_public()) come after the boards, in both
                    await new.pg.wait_for_selector(".agrid[data-logos=ready][data-photos=ready]", timeout=30000)
                    try:   # the old planner keeps no photos at all when the website has none: then there's nothing to wait for
                        await old.pg.wait_for_function("() => window.__eqOld('!!eqMedia || !window.__eqsb')", timeout=20000)
                    except Exception:
                        pass
                    await old.pg.evaluate("() => window.__eqOld('render(); true')")
                    await settle(old.pg, 800)
                    await settle(new.pg, 300)
                    op_, np_ = await old.pg.evaluate(PARTS, True), await new.pg.evaluate(PARTS, False)
                    problems = compare_parts(op_, np_)
                    m = np_["map"] or {"routes": [], "hubs": [], "airports": []}
                    label = (f"the hero ({np_['hero']['air']} aircraft in the air; {' · '.join(v + ' ' + w for v, w in np_['hero']['tiles'])}), the game clocks "
                             f"({len(np_['clocks'])} time zones), the map ({len(m['routes'])} routes, {len(m['hubs'])} bases, {len(m['airports'])} airports, "
                             f"night as of the moment) and the airline cards ({len(np_['cards'])}) equal the old Home's")
                    print("      the airline cards: " + "; ".join(f"{c['name']}: {c['figures']}, {', '.join(c['pills'])}" for c in np_["cards"]), flush=True)
                except Exception as e:
                    label, problems = "the hero, the game clocks, the map and the airline cards", [why(e)]
                step(not problems, label, problems)
                for check in (map_views, look):
                    try:
                        label, problems = await check(old, new)
                    except Exception as e:
                        label, problems = check.__name__, [why(e)]
                    step(not problems, label, problems + new.errors[:3] + old.errors[:3])
                try:
                    label, problems = loads_exact(moment, await old.pg.evaluate(OLD_LOADS))
                except Exception as e:
                    label, problems = "the loads behind Home, to the decimal", [why(e)]
                step(not problems, label, problems)
                for k, v in KNOWN.items():
                    where = f" ({'; '.join(v['where'][:6])})" if v["where"] else ""
                    print(f"      known difference \"{k}\": used {v['used']} time(s){where}. {v['rule']}", flush=True)
                try:
                    label, problems = await interline_open(old, new)
                except Exception as e:
                    label, problems = "the interline line with pairs open", [why(e)]
                step(not problems, label, problems + new.errors[:3] + old.errors[:3])

                # ---------- 5. real saves
                try:
                    for label, problems in await real_saves(new, old, tag):
                        step(not problems, label, problems + new.errors + old.errors)
                except Exception as e:
                    step(False, "real saves in the new Home", [why(e)] + new.errors[:3] + old.errors[:3])
                await old.close()
                await new.close()

                # ---------- 6 and 7
                for check in (preview, phone):
                    try:
                        label, problems = await check(p, port, env, nfacts, staff, moment, seen)
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
    print(f"\n{len(failures)} Home side-by-side step(s) failed" if failures else "\nHome side by side: all passed", flush=True)
    sys.exit(1 if failures else 0)


def rs_ms(iso):
    from captured_figures_test import ms
    return ms(iso)


if __name__ == "__main__":
    asyncio.run(main())
