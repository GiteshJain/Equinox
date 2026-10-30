"""The new planner on the rehearsal's copy (decision #18, build pull request 1, spec §7): the pull request's own new
planner, built into web/app/, at its live address (/planner/ since the switch, build pull request 13), signed in as test
staff, reading from and saving into a full local copy of Supabase restored from last night's backup, with the tables read
back afterwards.

Run by database/rehearse.sh after the restore, the pending changes and the SQL tests have passed, and after it has built
the new planner (npm ci, npm run build). It needs that copy, so it isn't part of tests/run_all.sh; its helpers for the
copy are in tests/local_copy.py. Test users made here through the copy's sign-in (one staff and one not), the live
Supabase address answered by the copy (its public key swapped for the copy's), and one rule: nothing goes outside.

1. Sign-in through the new planner's own form, as staff; the account that isn't staff is refused and signed out, with
   the old planner's message; opening the planner writes nothing (no change_log row, no table's row count changes).
2. Every screen has its boards (the screens grouped by when they're used since 20 Oct, spec
   docs/specs/2026-10-20-today-performance-systems.md): Home (the hero, needs attention's summary cards before the map
   since 23 Oct, each See all opening its section on Today with its list showing, key figures, the network, the airline
   cards, our airlines in their position order and colours on the network's buttons; needs attention's lists, coming up,
   the to-do board and, since 23 Oct, aircraft on order no longer there); Today, its answer at the top (All clear or what's waiting) with the capture in one line, then Orders
   with a card for each of our airlines, Aircraft to file, Needs attention, Game check, the to-do board and Coming up, all
   open, with no Collapse all; Routes on its list, with our airlines on its buttons in their order; Tails, its list and
   the deliveries board, and (21 Oct) the plan cards' cabins: every plan card not yet filed with the cabin its routes call
   for (the library's card.cabinFor), printed, and one opened on Tails suggesting the same, with Use the suggestion and
   its amber as its cabin calls for; Performance, a scorecard for each of the copy's airlines in their order, the fare
   ladder's links (since 26 Oct one per airline, to /planner/performance/<code>#fare-ladder, and no fare_ladder call
   while the group page opens) and the group's rows closed (since 22 Oct: the group today when shown, Growth signals,
   Main hubs, Flights by day), then a scorecard opens its airline's page (Profit, Cash next 14 days, Route profit with its fare index and 14-day
   load sparkline, Aircraft, Fare changes, Fare plan; Route profit alone open since 22 Oct), and (22 Oct) its first route's name opens the route page: its header, the last 7
   days against the 7 before, its five boards open with as many events and rivals as route_story() gives, its links to
   Routes (which links back, "The route's story ›") and to the airline's page, and Competition's threats each linking to
   their route's page; then each airline's page (since 26 Oct) has its own fare ladder under its scorecard, one card,
   its lists opened with See the changes, its moves in one line, its count of changes in the game matching its game
   actions (route by route since 21 Oct), its game actions and its routes table each cut to 10 rows with "show all N"; Systems, the Systems board first, then its four boards folded (Capture with the copy's
   airlines, Fleet and Cabin charges since 22 Oct, Manual entry; Cabins went on 21 Oct, Aircraft checks with the one-week checks
   on 22 Oct); Interline with its agreements and the interline countries, Photos with a logo for each
   of our airlines, Reference with its sections folded. The header has the search box and the Website button, and no
   Hubs, Check or Review. (Each screen was compared with the old planner's by a side by side until the clean-up, build
   pull request 14; tests/planner_saves_test.py now checks every kind of save against recorded rows.)
3. window.__eqPlanner.save() ticks the first open to-do: exactly that row changes (done, done_at), logged as actor
   planner with the tab's ID; the answer gives the row's new updated_at. A second save from that updated_at puts it
   back, so the next change needs no new read and the real saves that follow still find their open to-dos.
4. Two tabs read the same to-do; the first changes its title; the second's change to that row comes back as a clash
   carrying the first's title, and the second's change to another row in the same call isn't written either. The
   second tab shows the row as it is now and names it.
5. A preview address (127.0.0.1) reads, says "preview · not saved", sends no write, and its notice links to the live
   planner at /planner/.
6. Every screen opens at the frozen moment (the copy's latest capture plus one hour), at 1280 and 380 px wide: ready,
   no errors, no sideways scroll (Systems with every board open, Reference with every section open, Performance with
   every row open, and an airline's page with its fare ladder card open, its lists cut and then opened in full), no link into the
   old planner's address (/planner/old/), one used while the planner was built (/planner/next/) or a screen that went
   on 20 Oct (/planner/hubs, /planner/check, /planner/review); and one airline's Performance page the same way, and
   (22 Oct) the route pages of a busy legacy route and a busy Ryanair route (every event shown, then cut again); a
   screenshot of each at each width goes to PLANNER_SCREENS_DIR (the run's planner-screens artifact), when it's set.
   Since 28 Oct a sample 7-day line (made for the test on the airline Tails opens on, removed after) is on Tails'
   deliveries board with its slots at both widths, and among Today's Orders' open lines (1 of 7) with its link to Tails.
6b. The Systems board (#23) at the frozen moment: the first board on Systems, a line for each of our airlines' evening
   capture and one each for the snapshot, backup, archive, clean-ups, world scan, the planner's build (stamped) and the
   three usage figures, every one marked green, amber or red (printed). Then a short page made on purpose (#21): half of
   an airline's latest loads page, stored just after the latest capture and judged short, is listed on Today's needs
   attention in the Capture group linking to Systems, Today's capture line says it came in short, and the board marks
   that airline amber; then it is deleted.
7. The addresses (the switch, build pull request 13, the clean-up, 14, and 20 Oct), as tests/harness.py serves them from
   web/_redirects the way Cloudflare does: /planner and /planner/ open the planner, and so does a deep address
   (/planner/performance/VS); /planner/check answers 301 to /planner/today (the query kept), /planner/review/... to the
   same address under /planner/performance/, /planner/hubs/... to /planner/performance; signed in, /planner/review/VS
   lands on Virgin's Performance page, /planner/check on Today, /planner/hubs on Performance and /planner/check?day=…
   on Performance's Flights by day on that day; every /planner/next/... address answers 301 with the same address under
   /planner/ (/planner/next/routes opens Routes at /planner/routes); /planner/old and everything under it answer 301 to
   /planner/ (the old planner is gone); the built planner (web/app/) has no link to /planner/old/ or /planner/next/.
8. Nothing went outside: no request reached the live Supabase host or any address but the local server and the copy.

Prints one line per step (ok/FAIL), and nothing from the rows beyond ids, counts and the names of changed fields, since
the log is posted on the pull request. Never prints the local keys or the test passwords.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV (a file holding `supabase status -o env`), LOCAL_DB_URL,
SECRET_TABLES and PLANNER_SCREENS_DIR. Usage: python3 tests/planner_next_test.py
"""
import asyncio, datetime, http.client, json, os, re, secrets, subprocess, sys
from pathlib import Path
from urllib.parse import urlsplit
from harness import ROOT, WEB, LIVE_HOST, NEW_PLANNER, serve, settle
from playwright.async_api import async_playwright
from local_copy import (count_changes, counts, is_planner_user, jobs_since, local_env, log_since, make_user, marks, moment, ms, one, psql,
                        token_for, why)

CONFIG = ROOT / "app" / "planner" / "src" / "data" / "config.ts"
PAGE = WEB / "app" / "index.html"
SCREENS = [("home", "/planner/"), ("today", "/planner/today"), ("routes", "/planner/routes"), ("tails", "/planner/tails"),
           ("performance", "/planner/performance"), ("competition", "/planner/competition"), ("interline", "/planner/interline"), ("photos", "/planner/photos"),
           ("reference", "/planner/reference"), ("systems", "/planner/systems")]
SCREENS_DIR = os.environ.get("PLANNER_SCREENS_DIR")
# A link into the old planner, to an address used while the new one was built (the switch: none may be left), or to a
# screen that went on 20 Oct (Hubs, Check, Review: every link moved to Today, Performance or Systems)
OLD_LINK = re.compile(r"^(https?://[^/]+)?/planner/(old|next|hubs|check|review)(/|$|\?|#)")
NOT_STAFF = "This account doesn't have access to the planner."
AUTH_KEY = "equinox-planner-auth"
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"
failures = []


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:12]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


def planner_facts():
    """The live Supabase address and public key the new planner names (app/planner/src/data/config.ts)."""
    text = CONFIG.read_text()
    url = re.search(r'export const SB_URL = "(https://[^"]+)"', text)
    key = re.search(r'export const SB_KEY = "([^"]+)"', text)
    return {"live_url": url[1].rstrip("/"), "live_key": key[1]} if url and key else None


def todo_row(tid):
    """A to-do as the copy has it (every column), or None."""
    out = psql(f"select coalesce((select to_jsonb(t)::text from public.todos t where t.id = {int(tid)}), 'null')").strip()
    return json.loads(out)


def micros(iso):
    """A time as the data API gives it, in microseconds since 1970."""
    d = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return int(d.timestamp()) * 1_000_000 + d.microsecond


class Planner:
    """The new planner in its own browser: its live address mapped to the local server, the live Supabase address answered
    by the copy. As tests/real_saves_test.py's Planner, without a CDN library: the new planner's Supabase library is in
    its own build."""

    def __init__(self, p, port, env, facts, width=1280, height=900):
        self.p, self.port, self.env, self.f, self.size = p, port, env, facts, {"width": width, "height": height}
        self.copy = 0          # requests for the live Supabase host, answered by the copy
        self.rpcs = []         # the functions it called on the copy, in order
        self.local = 0         # requests to the local server
        self.stopped = set()   # hosts whose requests were stopped
        self.outside = []      # responses that came over the network from anywhere but the local server: must stay empty
        self.errors = []       # page errors and console errors
        self.dialogs = []      # browser dialogs it opened (dismissed): the planner asks in the page, so this stays empty
        self.b = self.api = self.ctx = self.pg = None
        self.closing = False   # set by close()
        self.inflight = 0      # requests on their way through route()
        self.checks = []       # the address checks (where), awaited by close()

    async def open(self, host=LIVE_HOST, path=NEW_PLANNER, moment=None):
        """Opens the planner; with a moment (ISO), its clock stays at that moment (tests/home_side_by_side_test.py)."""
        rules = f"MAP {LIVE_HOST} 127.0.0.1:{self.port}, MAP * ~NOTFOUND, EXCLUDE 127.0.0.1, EXCLUDE localhost"
        self.b = await self.p.chromium.launch(args=[f"--host-resolver-rules={rules}", "--no-proxy-server"])
        self.api = await self.p.request.new_context()
        self.ctx = await self.b.new_context(viewport=self.size, timezone_id="UTC", locale="en-US", service_workers="block")
        await self.ctx.route("**/*", self.route)
        await self.ctx.route_web_socket(re.compile(".*"), self.socket)
        self.ctx.on("response", lambda r: self.checks.append(asyncio.ensure_future(self.where(r))))
        self.pg = await self.ctx.new_page()
        if moment:
            await self.pg.clock.set_fixed_time(moment)
        self.pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
        self.pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
                   if m.type == "error" and "Failed to load resource" not in m.text else None)
        self.pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await self.pg.goto(f"http://{host}:{self.port}{path}")
        return self.pg

    async def route(self, r):
        # Home reads more now (the hero, the map), so a request can still be on its way when the browser closes: close()
        # lets it finish first, and an error once closing has begun is expected and dropped. Any other error is raised
        # as before.
        self.inflight += 1
        try:
            await self.forward(r)
        except Exception:
            if not self.closing:
                raise
        finally:
            self.inflight -= 1

    async def forward(self, r):
        req, u = r.request, r.request.url
        live, host = self.f["live_url"], urlsplit(u)
        if u.startswith(live + "/"):
            self.copy += 1
            m = re.match(r"^/rest/v1/rpc/([^/?]+)", u[len(live):])
            if m:
                self.rpcs.append(m[1])
            key, anon = self.f["live_key"], self.env["ANON_KEY"]
            headers = {k: v.replace(key, anon) for k, v in (await req.all_headers()).items()
                       if not k.startswith(":") and k.lower() not in ("host", "content-length", "connection", "accept-encoding", "cookie")}
            res = await self.api.fetch(self.env["API_URL"] + u[len(live):], method=req.method, headers=headers,
                                       data=req.post_data_buffer, max_redirects=0, fail_on_status_code=False, timeout=30000)
            await r.fulfill(response=res, headers={k: v for k, v in res.headers.items()
                                                   if k.lower() not in ("content-encoding", "content-length", "transfer-encoding")})
        elif host.hostname in (LIVE_HOST, "127.0.0.1") and host.port == self.port:
            self.local += 1
            await r.continue_()
        elif u.startswith(("data:", "blob:")):
            await r.continue_()
        else:
            self.stopped.add(host.hostname or u.split(":", 1)[0])
            await r.abort()

    async def socket(self, ws):
        self.stopped.add(urlsplit(ws.url).hostname or "a web socket")
        await ws.close()

    async def where(self, res):
        try:
            addr = await res.server_addr()
        except Exception:
            addr = None
        if addr and not (addr.get("ipAddress") in ("127.0.0.1", "::1", "[::1]") and int(addr.get("port") or 0) == self.port):
            self.outside.append(urlsplit(res.url).hostname or "an unknown address")

    async def close(self):
        """Closes the browser once the requests on their way have finished (up to 5 s), then waits (up to 5 s) for the
        ones it cut off and for the address checks, so no call is left with an error no one reads (a closed-page
        traceback in the log, after the test has passed)."""
        for _ in range(50):
            if not self.inflight:
                break
            await asyncio.sleep(0.1)
        self.closing = True
        if self.b:
            await self.b.close()
        for _ in range(50):
            if not self.inflight:
                break
            await asyncio.sleep(0.1)
        if self.checks:
            await asyncio.gather(*self.checks, return_exceptions=True)
        if self.api:
            await self.api.dispose()

    async def fill_sign_in(self, email, password):
        await self.pg.wait_for_selector("#g-email", timeout=30000)
        await self.pg.fill("#g-email", email)
        await self.pg.fill("#g-pass", password)
        await self.pg.click("#g-in")

    async def sign_in(self, email, password):
        """Signs in through the new planner's own form and waits for Home with everything it reads."""
        await self.fill_sign_in(email, password)
        await self.pg.wait_for_selector("[data-shell] main[data-screen=home][data-home-ready=yes]", timeout=90000)
        await self.pg.wait_for_function("!!window.__eqPlanner", timeout=30000)
        await settle(self.pg, 500)

    async def read(self, table, match):
        return await self.pg.evaluate("([t, m]) => window.__eqPlanner.read(t, m)", [table, match])

    async def save(self, changes):
        return await self.pg.evaluate("c => window.__eqPlanner.save(c)", changes)

    async def client(self):
        return await self.pg.evaluate("window.__eqPlanner.client")


# ---------- 1. sign-in ----------
async def sign_in_staff(pl, staff):
    n0, mark = counts(), marks()
    await pl.open()
    await pl.sign_in(*staff)
    problems = list(pl.errors)
    rows = log_since(mark)
    if rows:
        problems.append("opening the planner changed the tables: " + ", ".join(sorted({r["table"] for r in rows})))
    problems += count_changes(n0, counts())
    if "is_planner_user" not in pl.rpcs:
        problems.append("it didn't check the account with is_planner_user()")
    if await pl.pg.evaluate("(document.querySelector('[data-save-state]') || {}).textContent") != "saved":
        problems.append("the header's save state isn't \"saved\" at the live address")
    if await pl.pg.evaluate("window.__eqPlanner.preview") is not False:
        problems.append("the live address counts as a preview")
    return "sign in as test staff through the new planner's own form at its live address; opening it wrote nothing", problems


async def refuse_other(p, port, env, facts, other, seen):
    pl = Planner(p, port, env, facts)
    seen.append(pl)
    problems, n0, mark = [], counts(), marks()
    try:
        await pl.open()
        await pl.fill_sign_in(*other)
        await pl.pg.wait_for_function(f"(document.getElementById('g-msg') || {{}}).textContent === {json.dumps(NOT_STAFF)}", timeout=30000)
        await settle(pl.pg, 800)
        if await pl.pg.evaluate("!!document.querySelector('[data-shell]')"):
            problems.append("the account that isn't staff got past the sign-in")
        if await pl.pg.evaluate(f"localStorage.getItem({json.dumps(AUTH_KEY)})") is not None:
            problems.append("the account that isn't staff is still signed in on the device")
        if "is_planner_user" not in pl.rpcs:
            problems.append("it didn't check the account with is_planner_user()")
        if log_since(mark):
            problems.append("the refused account's visit changed the tables")
        problems += count_changes(n0, counts()) + pl.errors
    except Exception as e:
        problems.append(why(e))
    finally:
        await pl.close()
    return f"the account that isn't staff is refused and signed out (\"{NOT_STAFF}\"), and writes nothing", problems


async def open_screen(pg, sid):
    """Opens a screen from the top bar, as a person does (since 22 Oct, spec docs/specs/2026-10-22-planner-look-foundation.md):
    its link is in the bar, under More (Interline, Photos, Reference, Systems) or, on a phone, in the menu button's list."""
    link = f"header [data-screen-link={sid}]"
    for menu in ("header [data-menu=nav]", "header [data-menu=more]"):
        if await pg.is_visible(link):
            break
        if await pg.is_visible(menu):
            await pg.click(menu)
    await pg.click(link)


# ---------- 2. Home ----------
async def home_opens(pl):
    """Home is rebuilt (build pull request 5): no placeholder, its boards there (the hero, the map, a card for each of our
    airlines) and the game clocks in the top bar's clock panel (since 22 Oct; under the header before), our airlines on the map's buttons in their order, with their colours.
    Needs attention, coming up and the to-do board moved to Today on 20 Oct, so they aren't on Home. Its figures were
    compared with the old Home's by tests/home_side_by_side_test.py until the clean-up."""
    want = json.loads(psql(f"""select coalesce(json_agg(json_build_object(
            'name', coalesce(a.planner_name, a.public_name, a.game_name, 'Airline ' || a.game_id),
            'color', coalesce(a.livery_color, '#8B96A8')) order by a.position nulls last, a.id), '[]')
          from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
         where g.kind = 'ours' and a.world_id = {WORLD}""").strip())
    got = await pl.pg.evaluate("""[...document.querySelectorAll('[data-board=network] .mleg .mf[title]')].map(b => ({
        name: b.title, color: (b.querySelector('.lv') || {style: {getPropertyValue: () => ''}}).style.getPropertyValue('--lv').trim() }))""")
    boards = await pl.pg.evaluate("""({ notBuilt: !!document.querySelector('main[data-screen=home] [data-not-built]'),
        figures: document.querySelectorAll('[data-figure="home: key figures"]').length,
        network: !!document.querySelector('[data-board=network]'), attention: !!document.querySelector('[data-figure="home: needs attention"]'),
        comingUp: !!document.querySelector('#coming-up'), todo: !!document.querySelector('#todo'), hero: !!document.querySelector('#eqhero'),
        onOrder: !!document.querySelector('[data-figure="home: aircraft on order"]'),
        attCards: [...document.querySelectorAll('[data-figure="home: needs attention cards"] [data-wait-card]')].map(c => c.dataset.waitCard),
        seeAll: [...document.querySelectorAll('[data-figure="home: needs attention cards"] a[data-wait-href]')].map(a => a.getAttribute('href'))
          .filter(h => h.includes('#att-')),
        attBeforeMap: (() => { const c = document.querySelector('[data-figure="home: needs attention cards"]'), m = document.querySelector('[data-board=network]');
          return !!(c && m && (c.compareDocumentPosition(m) & Node.DOCUMENT_POSITION_FOLLOWING)); })(),
        cards: document.querySelectorAll('.agrid .acard').length, clocks: document.querySelectorAll('header #clocks .zc').length })""")
    problems = []
    # the clock button shows UTC now and opens the clocks; Escape shuts them
    await pl.pg.click("header [data-menu=clocks]")
    if not await pl.pg.is_visible("header #clocks .zc"):
        problems.append("the top bar's clock button doesn't open the game clocks")
    await pl.pg.keyboard.press("Escape")
    if boards["notBuilt"]:
        problems.append("Home still shows the placeholder's line to the old planner")
    if boards["figures"] != 5:
        problems.append(f"{boards['figures']} key figure(s), expected 5")
    problems += [f"no {k} board" for k in ("network", "hero") if not boards[k]]
    problems += [f"Home still has the {k} board, which moved to Today" for k in ("attention", "comingUp", "todo") if boards[k]]
    # 23 Oct (spec docs/specs/2026-10-23-attention-on-home.md): needs attention's summary cards after the hero, before
    # the map, each See all opening its group's section on Today; no aircraft on order board
    if boards["onOrder"]:
        problems.append("Home still has the aircraft on order board")
    if not boards["attCards"]:
        problems.append("Home has no needs attention cards (nor the all-clear line)")
    elif not boards["attBeforeMap"]:
        problems.append("Home's needs attention cards aren't before the network map")
    problems += [f"a See all links to {h}, not a section on Today" for h in boards["seeAll"] if not h.startswith("/planner/today#att-")]
    if not boards["clocks"]:
        problems.append("no game clocks in the top bar's clock panel")
    if not want:
        problems.append("the copy has none of our airlines")
    if [a["name"] for a in got] != [a["name"] for a in want]:
        problems.append(f"airlines on the network's buttons {[a['name'] for a in got]}, the copy has {[a['name'] for a in want]}")
    elif [a["color"].lower() for a in got] != [a["color"].lower() for a in want]:
        problems.append("an airline's colour isn't the copy's: " + ", ".join(g["name"] for g, w in zip(got, want) if g["color"].lower() != w["color"].lower()))
    if boards["cards"] != len(want):
        problems.append(f"{boards['cards']} airline card(s), the copy has {len(want)} of our airlines")
    # each See all opens Today at its section, with the list open
    for h in boards["seeAll"][:1]:
        await pl.pg.click(f'[data-figure="home: needs attention cards"] a[data-wait-href="{h.removeprefix("/planner")}"]')
        await pl.pg.wait_for_selector("main[data-screen=today][data-today-ready=yes]", timeout=90000)
        await settle(pl.pg, 300)
        sec = h.split("#", 1)[1]
        shown = await pl.pg.evaluate(f"(() => {{ const s = document.getElementById({json.dumps(sec)}); return !!s && !s.hidden && !!s.querySelector('[data-att-item]'); }})()")
        if not shown:
            problems.append(f"See all ({h}) doesn't open Today with that section's list showing")
        await open_screen(pl.pg, 'home')
        await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return (f"Home is rebuilt, not a placeholder: the hero, needs attention's cards ({len(boards['attCards'])}, before the map; "
            f"{len(boards['seeAll'])} See all opening Today's sections), its key figures, the map and the airline cards (needs attention's lists, coming up "
            f"and the to-do board on Today; no aircraft on order), with the copy's {len(want)} airlines in their order and colours, and the game clocks "
            f"({boards['clocks']} time zones)"), problems


async def today_opens(pl):
    """Today (20 Oct, spec docs/specs/2026-10-20-today-performance-systems.md): its answer at the top (All clear or what's
    waiting) with the capture in one line linking to Systems; then every board open, in order: Orders with a card for each
    of our airlines in their order (each delivery line once, with when it's safe; all safe types folded under the card
    since 21 Oct), Aircraft to file, Needs attention, Game check, the to-do board and Coming up; and no Collapse all."""
    want = [r for r in psql(f"""select coalesce(a.planner_name, a.public_name, a.game_name) from public.airlines a
                                join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                where g.kind = 'ours' and a.world_id = {WORLD} and a.active
                                order by a.position nulls last, a.id""").splitlines() if r]
    await open_screen(pl.pg, 'today')
    await pl.pg.wait_for_selector("main[data-screen=today][data-today-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate("""({
        answer: (document.querySelector('[data-figure="today: answer"]') || {dataset: {}}).dataset.allClear || '',
        title: (document.querySelector('[data-figure="today: answer"] .ansh') || {}).textContent || '',
        capture: (document.querySelector('[data-figure="today: capture"]') || {dataset: {}}).dataset.captureState || '',
        captureLink: (document.querySelector('[data-figure="today: capture"] a') || {getAttribute: () => ''}).getAttribute('href') || '',
        boards: [...document.querySelectorAll('main[data-screen=today] .board > h3.rh')].map(h => h.textContent.trim().split('\\n')[0]),
        figures: [...document.querySelectorAll('main[data-screen=today] [data-figure]')].map(b => b.dataset.figure),
        orders: [...document.querySelectorAll('[data-figure="today: orders"] .ordcard .ordh b')].map(b => b.textContent),
        lines: document.querySelectorAll('[data-figure="today: orders"] [data-order-line]').length,
        allSafe: document.querySelectorAll('[data-figure="today: orders"] details.ordall').length,
        allSafeOpen: document.querySelectorAll('[data-figure="today: orders"] details.ordall[open]').length,
        todo: !!document.querySelector('main[data-screen=today] #todo'), comingUp: !!document.querySelector('main[data-screen=today] #coming-up'),
        attention: !!document.querySelector('main[data-screen=today] #attention'), game: !!document.querySelector('main[data-screen=today] [data-board="Game check"] #gcheck'),
        folded: document.querySelectorAll('main[data-screen=today] .board.rcol').length, collapse: !!document.querySelector('main[data-screen=today] #rev-colall'),
        threats: [...document.querySelectorAll('main[data-screen=today] [data-att-item][data-att-kind=threat]')].map(li => li.querySelector('a').getAttribute('href')) })""")
    problems = []
    # the rivals' moves the latest scan showed (21 Oct, spec docs/specs/2026-10-21-competition-analysis.md §3): as many as
    # competition() gives with latest true, none dismissed on the copy, each linking to its airline's Competition page
    latest = int(psql(f"""select coalesce(sum((select count(*) from jsonb_array_elements(public.competition(al.airline_id) -> 'threats') t
                                                   where (t ->> 'latest')::boolean)), 0)
                          from private.fig_airlines({WORLD}) al""").strip() or 0)
    dismissed = int(psql("select count(*) from public.dismissals where alert_key like 'threat|%'").strip() or 0)
    if not dismissed and len(got["threats"]) != latest:
        problems.append(f"Today lists {len(got['threats'])} rival moves, competition() gives {latest} from the latest scan")
    problems += [f"a rival move links to {h}" for h in got["threats"] if not h.startswith("/planner/competition/")]
    if got["answer"] not in ("yes", "no"):
        problems.append("Today has no answer at the top (All clear or what's waiting)")
    if got["capture"] not in ("complete", "missing", "short", "broken"):
        problems.append(f"Today's capture line says nothing it should ({got['capture']!r})")
    if got["captureLink"] != "/planner/systems":
        problems.append(f"the capture line links to {got['captureLink']!r}, not Systems")
    order = ["today: answer", "today: orders", "today: aircraft to file", "today: needs attention", "today: game check"]
    seen = [f for f in got["figures"] if f in order]
    if seen[:len(order)] != order:
        problems.append(f"Today's boards are {seen}, not {order} in that order")
    if got["orders"] != want:
        problems.append(f"Today's orders are for {got['orders']}, the copy's airlines are {want}")
    if got["allSafeOpen"]:
        problems.append(f"{got['allSafeOpen']} order cards show all safe types on arrival (they should be folded)")
    problems += [f"Today has no {k}" for k in ("todo", "comingUp", "attention", "game") if not got[k]]
    if got["folded"]:
        problems.append(f"{got['folded']} of Today's boards are folded on arrival (all should be open)")
    if got["collapse"]:
        problems.append("Today has Collapse all")
    await open_screen(pl.pg, 'home')
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return (f"Today opens with its answer ({got['title'] or '?'}), the capture line ({got['capture']}) linking to Systems, and every board open: "
            f"orders for the copy's {len(got['orders'])} airlines ({got['lines']} delivery lines, all safe types folded on {got['allSafe']} cards), "
            f"aircraft to file, needs attention ({len(got['threats'])} rival moves from the latest scan), Game check, the to-do board and coming up"), problems


async def competition_opens(pl):
    """Competition (21 Oct, spec docs/specs/2026-10-21-competition-analysis.md §3): the group page with the scans' dates and
    the group line on top, a card for each of our airlines in their order and the threats; one airline's page (the first
    card's) with its boards in order (Market share, Threats, Openings, Rival profiles), a market card for each market and
    the openings cut to 10 with "show all" (opened and cut again), as competition() gives them on the copy. Since 23 Oct (spec
    docs/specs/2026-10-23-rival-fleets.md §5, §6) the group page's Order books board, one row per rival competition()'s
    order_flags give across our airlines, and on the airline's page a fleet line on every rival profile. Since 23 Oct (spec
    docs/specs/2026-10-23-rival-connections.md §5) the rivals' connecting departures beside direct on every market card,
    rival profile and opening competition() gives them for, with its number."""
    want = [r for r in psql(f"""select a.iata_code from public.airlines a
                                join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                where g.kind = 'ours' and a.world_id = {WORLD} and a.active
                                order by a.position nulls last, a.id""").splitlines() if r]
    await open_screen(pl.pg, 'competition')
    await pl.pg.wait_for_selector("main[data-screen=competition][data-competition-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    group = await pl.pg.evaluate("""({
        scans: (document.querySelector('[data-scans]') || {}).textContent || '',
        line: (document.querySelector('[data-figure="competition: group line"]') || {}).textContent || '',
        cards: [...document.querySelectorAll('[data-competition-card]')].map(c => c.dataset.competitionCard),
        threats: !!document.querySelector('[data-figure="competition: threats"]'),
        books: !!document.querySelector('[data-figure="competition: order books"]'),
        bookRows: [...document.querySelectorAll('[data-order-book]')].map(r => r.dataset.orderBook) })""")
    problems = []
    if not group["books"]:
        problems.append("Competition has no Order books board")
    books = json.loads(psql(f"""select coalesce(json_agg(distinct f ->> 'airline_id'), '[]') from public.airlines a
                                  join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                  cross join lateral jsonb_array_elements(coalesce(public.competition(a.id) -> 'order_flags', '[]')) f
                                  where g.kind = 'ours' and a.world_id = {WORLD} and a.active""").strip())
    if len(group["bookRows"]) != len(books):
        problems.append(f"Competition's Order books show {len(group['bookRows'])} rivals; competition() flags {len(books)}")
    if not group["scans"].startswith(("latest scan ", "no world scan")):
        problems.append(f"Competition's scans line says {group['scans']!r}")
    if group["cards"] != want:
        problems.append(f"Competition's cards are {group['cards']}, the copy's airlines are {want}")
    if not group["threats"]:
        problems.append("Competition has no threats board")
    code = (group["cards"] or ["?"])[0]
    await pl.pg.click(f"[data-competition-card='{code}']")
    await pl.pg.wait_for_selector(f"main[data-screen=competition][data-airline='{code}'][data-competition-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate("""({
        boards: [...document.querySelectorAll('main[data-screen=competition] .board')].map(b => b.dataset.board),
        markets: document.querySelectorAll('[data-market]').length, threats: document.querySelectorAll('main[data-screen=competition] [data-threat]').length,
        rows: document.querySelectorAll('[data-opening]').length, list: (document.querySelector('[data-list^="openings "]') || {dataset: {}}).dataset,
        more: !!document.querySelector('[data-list-more^="openings "]'), profiles: document.querySelectorAll('[data-profile]').length,
        fleets: document.querySelectorAll('[data-profile] [data-fleet]').length,
        mconn: [...document.querySelectorAll('[data-market] [data-connecting]')].map(e => +e.dataset.connecting),
        pconn: document.querySelectorAll('[data-profile] [data-connecting]').length,
        oconn: [...document.querySelectorAll('[data-opening]')].slice(0, 10).map(r => { const c = r.querySelector('[data-connecting]'); return c ? +c.dataset.connecting : null; }),
        first: [...document.querySelectorAll('[data-opening]')].slice(0, 5).map(r => r.dataset.opening) })""")
    if got["boards"] != ["Market share", "Threats", "Openings", "Rival profiles"]:
        problems.append(f"{code}'s Competition boards are {got['boards']}")
    aid = psql(f"select id from public.airlines where world_id = {WORLD} and iata_code = :'code'", code=code).strip()
    db = json.loads(psql(f"""select json_build_object('markets', jsonb_array_length(d -> 'markets'), 'threats', jsonb_array_length(d -> 'threats'),
                                 'openings', jsonb_array_length(d -> 'openings'), 'count', d -> 'openings_count', 'profiles', jsonb_array_length(d -> 'profiles'),
                                 'first', (select json_agg(o ->> 'route' order by (o ->> 'rank')::int) from jsonb_array_elements(d -> 'openings') o
                                           where (o ->> 'rank')::int <= 5),
                                 'mconn', (select coalesce(json_agg((m ->> 'connecting_weekly')::int order by i), '[]') from jsonb_array_elements(d -> 'markets') with ordinality x(m, i)
                                           where m ? 'connecting_weekly'),
                                 'pconn', (select count(*) from jsonb_array_elements(d -> 'profiles') p where p ? 'connecting_weekly'),
                                 'oconn', (select coalesce(json_agg((o ->> 'connecting_weekly')::int order by (o ->> 'rank')::int), '[]') from jsonb_array_elements(d -> 'openings') o
                                           where (o ->> 'rank')::int <= 10))
                            from (select public.competition({int(aid)}) as d) x""").strip())
    if got["markets"] != db["markets"] or got["threats"] != db["threats"] or got["profiles"] != db["profiles"]:
        problems.append(f"{code}: {got['markets']} markets, {got['threats']} threats and {got['profiles']} profiles shown; competition() gives "
                        f"{db['markets']}, {db['threats']} and {db['profiles']}")
    if got["fleets"] != got["profiles"]:
        problems.append(f"{code}: {got['fleets']} of its {got['profiles']} rival profiles show a fleet line")
    # the rivals' connecting departures (since 23 Oct, spec docs/specs/2026-10-23-rival-connections.md §5): beside direct on
    # every market card, rival profile and opening that competition() gives them for, with its number
    if got["mconn"] != db["mconn"] or got["pconn"] != db["pconn"]:
        problems.append(f"{code}: connecting shown on markets {got['mconn']} and {got['pconn']} profiles; competition() gives {db['mconn']} and {db['pconn']}")
    if got["oconn"] != (db["oconn"] or [])[:len(got["oconn"])]:
        problems.append(f"{code}: the openings show connecting {got['oconn']}; competition() gives {db['oconn']}")
    if got["rows"] != min(10, db["openings"]) or got["more"] != (db["openings"] > 10) or got["first"] != (db["first"] or [])[:len(got["first"])]:
        problems.append(f"{code}: the openings show {got['rows']} rows (show all: {got['more']}), first {got['first']}; competition() gives "
                        f"{db['openings']} of {db['count']}, first {db['first']}")
    if got["more"]:
        await pl.pg.click("[data-list-more^='openings ']")
        await settle(pl.pg, 200)
        n = await pl.pg.evaluate("document.querySelectorAll('[data-opening]').length")
        if n != db["openings"]:
            problems.append(f"{code}: show all opens {n} openings, not {db['openings']}")
        await pl.pg.click("[data-list-more^='openings ']")
        await settle(pl.pg, 200)
    await open_screen(pl.pg, 'home')
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return (f"Competition opens with {group['scans'] or 'no scans line'!r}, a card for each of the copy's {len(group['cards'])} airlines and "
            f"{len(group['bookRows'])} order books; {code}'s page has "
            f"{got['markets']} markets, {got['threats']} threats, {db['count']} openings ({got['rows']} shown, top: {', '.join(got['first'])}) and "
            f"{got['profiles']} rival profiles, each with its fleet line, and connecting departures beside direct on {len(got['mconn'])} markets "
            f"({sum(got['mconn'])} a week) and {got['pconn']} profiles, as competition() gives them"), problems


async def routes_opens(pl):
    """Routes is rebuilt (build pull request 6): no placeholder; it opens on its list (the first airline's routes with
    its first base picked) with our airlines on its buttons in their order. Its figures are compared with the old
    Routes' by tests/routes_side_by_side_test.py. Since 22 Oct (spec docs/specs/2026-10-22-planner-look-routes.md) the
    airline switch sits in the page head and the count under the list's tools, so they're found there."""
    want = [r for r in psql(f"""select a.iata_code from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                 where g.kind = 'ours' and a.world_id = {WORLD} order by a.position nulls last, a.id""").splitlines() if r]
    await open_screen(pl.pg, 'routes')
    await pl.pg.wait_for_selector("main[data-screen=routes][data-routes-ready=yes]", timeout=60000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate("""({ notBuilt: !!document.querySelector('main[data-screen=routes] [data-not-built]'),
        airlines: [...document.querySelectorAll('main[data-screen=routes] .rseg [data-al]')].map(b => b.dataset.al),
        rows: document.querySelectorAll('#routelist .row').length,
        count: (document.querySelector('main[data-screen=routes] [data-figure="routes: count"]') || {}).textContent || '' })""")
    problems = []
    if got["notBuilt"]:
        problems.append("Routes still shows the placeholder's line to the old planner")
    if got["airlines"] != want:
        problems.append(f"airlines on Routes' buttons {got['airlines']}, the copy has {want}")
    if not got["rows"]:
        problems.append("Routes lists no route")
    await open_screen(pl.pg, 'home')
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return f"Routes is rebuilt, not a placeholder: it opens on its list ({got['count']}) with the copy's {len(want)} airlines on its buttons in their order", problems


async def tails_opens(pl):
    """Tails is rebuilt (build pull request 7): no placeholder; it opens on its list (the first airline's aircraft in
    service) and the deliveries board, with our airlines on its buttons in their order. Its figures are compared with the
    old Tails' by tests/tails_side_by_side_test.py."""
    want = [r for r in psql(f"""select a.iata_code from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                 where g.kind = 'ours' and a.world_id = {WORLD} order by a.position nulls last, a.id""").splitlines() if r]
    await open_screen(pl.pg, 'tails')
    await pl.pg.wait_for_selector("main[data-screen=tails][data-tails-ready=yes]", timeout=60000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate("""({ notBuilt: !!document.querySelector('main[data-screen=tails] [data-not-built]'),
        airlines: [...document.querySelectorAll('.toolbar .seg [data-al]')].map(b => b.dataset.al),
        rows: document.querySelectorAll('#taillist tr[data-tail]').length, count: (document.querySelector('.toolbar .count') || {}).textContent || '',
        board: !!document.querySelector('[data-figure="tails: deliveries"]') })""")
    problems = []
    if got["notBuilt"]:
        problems.append("Tails still shows the placeholder's line to the old planner")
    if got["airlines"] != want:
        problems.append(f"airlines on Tails' buttons {got['airlines']}, the copy has {want}")
    if not got["rows"]:
        problems.append("Tails lists no aircraft")
    if not got["board"]:
        problems.append("Tails shows no deliveries board")
    await open_screen(pl.pg, 'home')
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return f"Tails is rebuilt, not a placeholder: it opens on its list ({got['count']}) and the deliveries, with the copy's {len(want)} airlines on its buttons", problems


async def plan_card_cabins(pl):
    """The plan card's cabin (21 Oct, spec docs/specs/2026-10-21-cabins-new-rule.md §3): for every plan card not yet filed
    (its aircraft on order or arrived, status on_order or delivered), the cabin its routes call for, worked out by the
    planning library (tests/plan_card_cabins.mjs: card.cabinFor on rules_input(world, 'all')), printed one line each
    (registration, the card's cabin, the suggestion and its reason, and whether it differs: codes only), the cards that
    differ counted. Then the first such card with legs, opened on Tails, says "suggested: <the library's code>" beside its
    Cabin box, with Use the suggestion when the card's own cabin isn't it, and a card cabin that differs in amber; and
    (21 Oct, spec docs/specs/2026-10-21-frequencies-and-fares.md §2) the fare level of each route it flies, once per
    route, since 26 Oct once per direction (spec docs/specs/2026-10-26-fare-ladder-per-direction.md §3), in the game's
    words, printed."""
    cards = json.loads(psql(f"""select coalesce(json_agg(json_build_object('registration', a.registration, 'aircraft_id', a.id, 'airline', al.iata_code,
                  'config_id', pc.config_id, 'card_code', cc.code, 'order_code', oc.code, 'on_board', a.delivery_at is not null,
                  'one_card', (select count(*) from public.plan_cards o where o.aircraft_id = a.id) = 1,
                  'legs', (select coalesce(json_agg(json_build_object('flight_no', l.flight_no, 'origin_code', l.origin_code, 'dest_code', l.dest_code,
                             'days_utc', l.days_utc, 'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min) order by l.position, l.id), '[]')
                             from public.plan_card_legs l where l.plan_card_id = pc.id))
                  order by al.position nulls last, a.delivery_at nulls last, a.id, pc.id), '[]')
              from public.plan_cards pc join public.aircraft a on a.id = pc.aircraft_id join public.airlines al on al.id = a.airline_id
              left join public.cabin_configs cc on cc.id = pc.config_id left join public.cabin_configs oc on oc.id = a.order_config_id
             where a.world_id = {WORLD} and a.status in ('on_order', 'delivered')""").strip())
    rules = psql("select private.rules_input_doc(null, 'all')::text").strip()
    r = subprocess.run(["node", str(ROOT / "tests" / "plan_card_cabins.mjs")], input=json.dumps({"rules": json.loads(rules), "cards": cards}),
                       capture_output=True, text=True, timeout=120)
    if r.returncode:
        return "the plan cards' cabins", ["plan_card_cabins.mjs: " + (r.stderr.strip().splitlines() or ["failed"])[-1][:200]]
    got = json.loads(r.stdout)
    problems = [f"{x['registration']}: {x['error']}" for x in got if x["error"]]
    print(f"      the plan cards not yet filed ({len(got)}), each with the cabin its routes call for:", flush=True)
    for c, x in zip(cards, got):
        mark = "no cabin chosen" if x["missing"] else "DIFFERS" if x["differs"] else "same"
        print(f"      {x['registration']} ({c['airline']}, {len(c['legs'])} legs): card {x['card'] or '—'}"
              f"{' (order ' + c['order_code'] + ')' if not x['card'] and c['order_code'] else ''} · suggested {x['suggested'] or '—'} · {mark}"
              f" · {x['reason'] or ''}", flush=True)
    # one card on Tails: the same suggestion, beside its Cabin box
    # (an aircraft on the deliveries board, with a delivery, and only the one card, so the board opens that card)
    pick = next(((c, x) for c, x in zip(cards, got) if c["legs"] and x["suggested"] and c["on_board"] and c["one_card"]), None)
    shown = None
    if pick:
        c, x = pick
        await pl.pg.goto(f"http://{LIVE_HOST}:{pl.port}{NEW_PLANNER}tails?airline={c['airline']}&del=&card={c['registration']}")
        await pl.pg.wait_for_selector("main[data-screen=tails][data-tails-ready=yes]", timeout=60000)
        card = f"[data-plan-card={json.dumps(c['registration'])}]"
        try:
            # the suggestion settles once the airline's routes and the markets are read
            await pl.pg.wait_for_function("([sel, code]) => { const s = document.querySelector(sel + ' [data-card-suggest]'); return !!s && s.dataset.cardSuggest === code; }",
                                          arg=[card, x["suggested"]], timeout=30000)
        except Exception:
            problems.append(f"{c['registration']}'s plan card on Tails doesn't show the suggested cabin {x['suggested']} within 30 s")
        shown = await pl.pg.evaluate("""sel => { const c = document.querySelector(sel); if (!c) return null;
            const s = c.querySelector('[data-card-suggest]'), cab = c.querySelector('[data-card-cabin]');
            return { code: s ? s.dataset.cardSuggest : null, text: s ? s.textContent : '', use: !!c.querySelector('[data-card-suggest-use]'),
                     cabin: cab ? cab.dataset.cardCabin : null, amber: !!c.querySelector('[data-card-cabin-differs]') }; }""", card)
        if shown is None:
            problems.append(f"{c['registration']}'s plan card didn't open on Tails")
        elif shown["code"] is not None:
            if shown["code"] != x["suggested"] or f"suggested: {x['suggested']}" not in shown["text"]:
                problems.append(f"{c['registration']}'s card suggests {shown['code']} on Tails, the library {x['suggested']}")
            if shown["use"] != (x["card"] != x["suggested"]):
                problems.append(f"{c['registration']}'s card {'offers' if shown['use'] else 'has no'} Use the suggestion, its cabin {x['card'] or 'none'}")
            differs = bool(shown["cabin"]) and shown["cabin"] != x["suggested"]
            if shown["amber"] != differs:
                problems.append(f"{c['registration']}'s cabin {shown['cabin'] or 'none'} {'is' if shown['amber'] else 'is not'} amber against {x['suggested']}")
        # the fare level of each route it flies (21 Oct, spec docs/specs/2026-10-21-frequencies-and-fares.md §2): since 26
        # Oct once per direction, on the direction's first leg, once fare_ladder() for the airline is read; printed (codes
        # and levels only)
        pairs = []
        for leg in c["legs"]:
            k = f"{leg['origin_code']}-{leg['dest_code']}"
            if k not in pairs:
                pairs.append(k)
        try:
            await pl.pg.wait_for_function("([sel, n]) => document.querySelectorAll(sel + ' [data-card-fare]').length === n", arg=[card, len(pairs)], timeout=30000)
        except Exception:
            problems.append(f"{c['registration']}'s plan card on Tails doesn't show a fare level for each of its {len(pairs)} directions within 30 s")
        fares = await pl.pg.evaluate("sel => [...document.querySelectorAll(sel + ' [data-card-fare]')].map(td => [td.dataset.cardFare, td.textContent])", card)
        print(f"      on Tails, {c['registration']}'s fare levels ({len(fares)} of its {len(pairs)} directions): "
              + ("; ".join(f"{k} {t}" for k, t in fares) or "none"), flush=True)
        if any(not re.fullmatch(r"(economy|business) [+−]\d+(\.\d)?%(, (economy|business) [+−]\d+(\.\d)?%)* of the default price|launch \([+−]\d+(\.\d)?% of the default price\)", t)
               for _, t in fares):
            problems.append(f"{c['registration']}'s fare levels aren't in the game's words: {fares}")
        await pl.pg.goto(f"http://{LIVE_HOST}:{pl.port}{NEW_PLANNER}")
        await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    differ = [x["registration"] for x in got if x["differs"] and not x["missing"]]
    missing = [x["registration"] for x in got if x["missing"]]
    return (f"the plan cards' cabins: {len(got)} card(s) not yet filed, {len(differ)} with a cabin that differs from the rule's, "
            f"{len(missing)} with none chosen" + (f"; {pick[0]['registration']} on Tails suggests {shown['code'] if shown else '—'}" if pick else "")), problems


async def no_hubs(pl):
    """Hubs went on 20 Oct (spec docs/specs/2026-10-20-today-performance-systems.md), and Check and Review became Today,
    Performance and Systems: the header names the nine screens in their new order, with no Hubs, Check or Review."""
    links = await pl.pg.evaluate("[...document.querySelectorAll('header [data-screen-link]')].map(a => a.dataset.screenLink)")
    want = [sid for sid, _ in SCREENS]
    problems = [] if links == want else [f"the header's screens are {links}, not {want}"]
    problems += [f"the header still links to {x}" for x in ("hubs", "check", "review") if x in links]
    return f"the header names the nine screens in their new order ({', '.join(links)}), with no Hubs, Check or Review", problems


async def systems_opens(pl):
    """Systems (20 Oct; Check's boards and Review's Manual entry until then): the Systems board first and open, then its
    four boards folded on arrival, in order (Capture, Fleet and Cabin charges since 22 Oct, Manual entry; the Cabins board went on
    21 Oct, spec docs/specs/2026-10-21-cabins-new-rule.md §1, and Aircraft checks on 22 Oct, spec
    docs/specs/2026-10-22-remove-aircraft-checks.md), the Capture board listing our airlines the capture covers, in their
    order."""
    want = [r for r in psql(f"""select coalesce(a.planner_name, a.public_name, a.game_name) from public.airlines a
                                join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                where g.kind = 'ours' and a.world_id = {WORLD}
                                order by a.position nulls last, a.id""").splitlines() if r]
    await open_screen(pl.pg, 'systems')
    await pl.pg.wait_for_selector("main[data-screen=systems][data-systems-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    boards_js = "[...document.querySelectorAll('main[data-screen=systems] .board:not(.sysboard) > h3.rh')].map(h => h.dataset.rkey)"
    got = await pl.pg.evaluate("""({ first: (document.querySelector('main[data-screen=systems] .board') || {}).id || '',
        boards: """ + boards_js + """,
        folded: [...document.querySelectorAll('main[data-screen=systems] .board:not(.sysboard)')].every(b => b.classList.contains('rcol')),
        capture: [...document.querySelectorAll('[data-figure="systems: capture table"] tr')].slice(1).map(tr => (tr.querySelector('td b') || {}).textContent || '') })""")
    problems = []
    if got["first"] != "systems":
        problems.append(f"the Systems board isn't the first board on Systems (the first is {got['first'] or 'none'})")
    order = ["Capture", "Fleet", "Cabin charges", "Manual entry"]
    if got["boards"] != order:
        problems.append(f"Systems' boards are {got['boards']}, not {order}")
    if not got["folded"]:
        problems.append("Systems' boards aren't all folded on arrival")
    if not got["capture"] or any(n not in want for n in got["capture"]) or got["capture"] != sorted(got["capture"], key=want.index):
        problems.append(f"the Capture board lists {got['capture']}, the copy's airlines are {want}")
    await open_screen(pl.pg, 'home')
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return (f"Systems opens with the Systems board first, then its {len(got['boards'])} boards folded in order, the Capture board with "
            f"{len(got['capture'])} airlines"), problems


async def performance_opens(pl):
    """Performance (20 Oct; Review's screen with Check's growth boards and load report until then): a scorecard for each of
    our airlines the captured figures cover, in their order, each with its figures against the same day last week (or
    saying there's no day a week ago), and the group's rows all closed on arrival (since 22 Oct: the group today when
    shown, Growth signals, Main hubs, Flights by day; opened with Expand all for the lists); each growth list shows its
    first 10 rows with "show all N" (21 Oct), which opens the rest in place and "show fewer" closes. Since 26 Oct (spec
    docs/specs/2026-10-26-fare-ladder-one-airline.md) the group page's fare ladder is a link per airline, in our airlines'
    order, each to /planner/performance/<code>#fare-ladder, and opening the group page calls fare_ladder() not at all
    (its requests are watched); tapping the first scorecard opens that airline's page, its name as its title and its six
    rows, Route profit alone open (since 22 Oct), the route profit table with its fare index and 14-day load sparkline.
    Then each airline's page (the first through its link on the group page) has its fare ladder, one section for that
    airline (#fare-ladder, under its scorecard, above the rows, open on arrival), with its moves in one line ("12 up, 30
    hold, 2 down"), the count of changes in the game ("24 changes in the game", as many as its game actions: since 21 Oct
    the set-back changes, in their own list first with its heading "3 directions off their level" (directions since 26
    Oct), and the week's moves), Put on the fare plan, and its lists opened with See the changes, its game actions and
    routes table each cut to 10 rows (one of each kind opened and closed again). Each airline's moves and how many game
    actions it has are printed (counts only)."""
    want = [r for r in psql(f"""select coalesce(a.planner_name, a.public_name, a.game_name) from public.airlines a
                                join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                where g.kind = 'ours' and a.world_id = {WORLD} and a.active
                                order by a.position nulls last, a.id""").splitlines() if r]
    rpc0 = len(pl.rpcs)
    await open_screen(pl.pg, 'performance')
    await pl.pg.wait_for_selector("main[data-screen=performance][data-performance-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    page = """({ cards: [...document.querySelectorAll('main[data-screen=performance] [data-figure="performance: scorecards"] .fcard .fch b')].map(b => b.textContent),
        codes: [...document.querySelectorAll('main[data-screen=performance] [data-figure="performance: scorecards"] .fcard')].map(b => b.dataset.final),
        wow: [...document.querySelectorAll('main[data-screen=performance] .fcard .fwow')].map(x => x.textContent),
        boards: [...document.querySelectorAll('main[data-screen=performance] .board > h3.rh')].map(h => h.dataset.rkey),
        folded: document.querySelectorAll('main[data-screen=performance] .board.rcol').length,
        airline: document.querySelector('main[data-screen=performance]').dataset.airline,
        path: location.pathname })"""
    got = await pl.pg.evaluate(page)
    problems = []
    if got["cards"] != want:
        problems.append(f"Performance's scorecards are {got['cards']}, the copy's airlines are {want}")
    if len(got["wow"]) != len(got["cards"]) or not all(got["wow"]):
        problems.append("a scorecard doesn't say what it's compared with")
    group = [b for b in got["boards"] if b != "The group today"]
    if group != ["Growth signals", "Main hubs", "Flights by day"]:
        problems.append(f"Performance's group boards are {got['boards']}")
    if got["folded"] != len(got["boards"]):
        problems.append(f"{got['folded']} of Performance's {len(got['boards'])} rows are closed on arrival (all should be)")
    # 26 Oct (spec docs/specs/2026-10-26-fare-ladder-one-airline.md §1): the fare ladder on the group page is a link per
    # airline, in our airlines' order, each to its page's fare ladder, and the group page reads no fare ladder
    ladder_calls = pl.rpcs[rpc0:].count("fare_ladder")
    if ladder_calls:
        problems.append(f"opening Performance's group page called fare_ladder {ladder_calls} time(s), not 0")
    links = await pl.pg.evaluate("""(() => { const s = document.querySelector('main[data-screen=performance] [data-board="Fare ladder"]');
        return s ? { heading: (s.querySelector('h2') || {}).textContent || '', lead: (s.querySelector('.perflead') || {}).textContent || '',
                     cards: s.querySelectorAll('[data-ladder]').length,
                     links: [...s.querySelectorAll('a[data-ladder-link]')].map(a => ({ code: a.dataset.ladderLink, href: a.getAttribute('href'), name: a.textContent.replace('›', '').trim() })) } : null; })()""")
    codes = [c for c in got["codes"] if c]
    if not links:
        problems.append("Performance's group page has no fare ladder section")
    else:
        if links["heading"] != "The fare ladder":
            problems.append(f"the group page's fare ladder section is headed {links['heading']!r}")
        if links["lead"] != "One airline at a time: open an airline for this Saturday's fare moves.":
            problems.append(f"the group page's fare ladder lead is {links['lead']!r}")
        if links["cards"]:
            problems.append(f"the group page still has {links['cards']} fare ladder card(s)")
        if [x["code"] for x in links["links"]] != codes:
            problems.append(f"the group page's fare ladder links are {[x['code'] for x in links['links']]}, the scorecards' airlines {codes}")
        for x in links["links"]:
            if x["href"] != f"/planner/performance/{x['code']}#fare-ladder":
                problems.append(f"the fare ladder link for {x['code']} goes to {x['href']!r}")
        if [x["name"] for x in links["links"]] != [n for n, c in zip(got["cards"], got["codes"]) if c]:
            problems.append(f"the fare ladder links are named {[x['name'] for x in links['links']]}")
    # 21 Oct: each growth list shows its first 10 rows with "show all N", which opens the rest in place and closes again
    await pl.pg.click("main[data-screen=performance] #rev-expall")   # 22 Oct: the rows open, so a growth list can be opened
    await settle(pl.pg, 300)
    lists_js = """[...document.querySelectorAll('main[data-screen=performance] [data-figure="performance: growth lists"] [data-list]')].map(d => ({
        list: d.dataset.list, rows: +d.dataset.listRows, shown: d.querySelectorAll('table tr').length - 1,
        button: (d.querySelector(':scope > [data-list-more]') || {}).textContent || '', visible: !!d.offsetParent }))"""
    lists = await pl.pg.evaluate(lists_js)
    for x in lists:
        want_shown, want_button = (10, f"show all {x['rows']}") if x["rows"] > 10 else (x["rows"], "")
        if x["shown"] != want_shown or x["button"] != want_button:
            problems.append(f"growth list {x['list']!r} of {x['rows']} shows {x['shown']} rows with {x['button']!r}, not {want_shown} with {want_button!r}")
    long = next((x for x in lists if x["rows"] > 10 and x["visible"]), None)
    if long:
        sel = f"main[data-screen=performance] [data-list={json.dumps(long['list'])}] > [data-list-more]"
        await pl.pg.click(sel)
        opened = next((x for x in await pl.pg.evaluate(lists_js) if x["list"] == long["list"]), {})
        if opened.get("shown") != long["rows"] or opened.get("button") != "show fewer":
            problems.append(f"\"show all {long['rows']}\" on {long['list']!r} shows {opened.get('shown')} rows with {opened.get('button')!r}")
        await pl.pg.click(sel)
        closed = next((x for x in await pl.pg.evaluate(lists_js) if x["list"] == long["list"]), {})
        if closed.get("shown") != 10:
            problems.append(f"\"show fewer\" on {long['list']!r} leaves {closed.get('shown')} rows")
    sizes = ", ".join("%s %d" % (x["list"], x["rows"]) for x in lists)
    cut_words = ("; growth lists cut to 10 (" + sizes + ")" + (", %r opened and closed" % long["list"] if long else "")) if lists else ""
    await pl.pg.click("main[data-screen=performance] [data-figure='performance: scorecards'] .fcard")
    await pl.pg.wait_for_function("() => !!(document.querySelector('main[data-screen=performance]') || {dataset: {}}).dataset.airline", timeout=30000)
    await pl.pg.wait_for_selector("main[data-screen=performance][data-performance-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    one = await pl.pg.evaluate(page)
    one["name"] = await pl.pg.evaluate("(document.querySelector('main[data-screen=performance] h1[data-perf-name]') || {}).textContent || ''")
    one["open"] = await pl.pg.evaluate("[...document.querySelectorAll('main[data-screen=performance] .board:not(.rcol) > h3.rh')].map(h => h.dataset.rkey)")
    if one["boards"] != ["Profit", "Cash, next 14 days", "Route profit", "Aircraft", "Fare changes", "Fare plan"]:
        problems.append(f"the airline's page has the boards {one['boards']}")
    cols = await pl.pg.evaluate("""(() => { const t = document.querySelector('main[data-screen=performance] [data-figure="performance: route profit table"]');
        return t ? { head: [...t.querySelectorAll('tr:first-child th')].map(h => h.textContent), sparks: t.querySelectorAll('svg.lspark').length,
                     rows: t.querySelectorAll('tr[data-rprow]').length } : null; })()""")
    if cols and ("Fare index" not in cols["head"] or "14 days" not in cols["head"] or cols["sparks"] != cols["rows"]):
        problems.append(f"the route profit table's columns are {cols['head']}, with {cols['sparks']} sparklines for {cols['rows']} routes")
    if one["open"] != ["Route profit"]:
        problems.append(f"the airline's page opens with {one['open']} open, not Route profit alone")
    if want and one["name"] != want[0]:
        problems.append(f"the first scorecard opens {one['name']!r}, not {want[0]!r}")
    if not one["path"].startswith("/planner/performance/") or not one["airline"]:
        problems.append(f"the airline's page is at {one['path']} ({one['airline']!r})")

    # 26 Oct (spec §2): each airline's page has its own fare ladder, one section, under its scorecard and above the rows;
    # the first opened through the group page's link, the others by their address with #fare-ladder
    ladder_js = """[...document.querySelectorAll('main[data-screen=performance] [data-figure="performance: fare ladder"] [data-ladder]')].map(x => ({
        code: x.dataset.ladder, moves: (x.querySelector('[data-ladder-moves]') || {}).textContent || '',
        changes: (x.querySelector('[data-ladder-changes]') || {}).textContent || '',
        plan: !!x.querySelector('[data-ladder-plan]'),
        off: (x.querySelector('[data-ladder-off]') || {}).textContent || '',
        fix_ways: new Set([...x.querySelectorAll('[data-ladder-fixes] li[data-way]')].map(li => li.dataset.way)).size,
        lists: [...x.querySelectorAll('[data-list]')].map(d => ({ list: d.dataset.list, rows: +d.dataset.listRows,
          shown: d.dataset.list.startsWith('actions ') || d.dataset.list.startsWith('fixes ') ? d.querySelectorAll('ol > li').length : d.querySelectorAll('table tr').length - 1,
          button: (d.querySelector(':scope > [data-list-more]') || {}).textContent || '' })) }))"""
    place_js = """(() => { const s = document.querySelector('main[data-screen=performance] #fare-ladder'); if (!s) return null;
        const head = document.querySelector('main[data-screen=performance] .perfhead'), rows = document.querySelector('main[data-screen=performance] .perfrows');
        return { board: s.dataset.board, figure: s.dataset.figure,
                 below_card: !!head && !!(head.compareDocumentPosition(s) & Node.DOCUMENT_POSITION_FOLLOWING),
                 above_rows: !!rows && !!(s.compareDocumentPosition(rows) & Node.DOCUMENT_POSITION_FOLLOWING),
                 error: (s.querySelector('[data-error]') || {}).textContent || '' }; })()"""
    ladder, opened_lists = [], []
    for i, c in enumerate(codes):
        if i == 0:
            await pl.pg.evaluate("t => window.__eqPlanner.go(t)", "/performance")
            await pl.pg.wait_for_selector("main[data-screen=performance][data-airline=''][data-performance-ready=yes]", timeout=90000)
            await pl.pg.click(f"main[data-screen=performance] a[data-ladder-link={json.dumps(c)}]")
        else:
            await pl.pg.evaluate("t => window.__eqPlanner.go(t)", f"/performance/{c}#fare-ladder")
        await pl.pg.wait_for_selector(f"main[data-screen=performance][data-airline={json.dumps(c)}][data-performance-ready=yes]", timeout=90000)
        await settle(pl.pg, 300)
        if i == 0:
            at = await pl.pg.evaluate("location.pathname + location.hash")
            if at != f"/planner/performance/{c}#fare-ladder":
                problems.append(f"the group page's fare ladder link for {c} opens {at}")
        where = await pl.pg.evaluate(place_js)
        if not where:
            problems.append(f"{c}'s page has no fare ladder (#fare-ladder)")
            continue
        if where["board"] != "Fare ladder" or where["figure"] != "performance: fare ladder board":
            problems.append(f"{c}'s fare ladder section is marked {where['board']!r} / {where['figure']!r}")
        if not where["below_card"] or not where["above_rows"]:
            problems.append(f"{c}'s fare ladder isn't under its scorecard and above its rows")
        if where["error"]:
            problems.append(f"{c}'s fare ladder says {where['error'][:120]!r}")
        # since 22 Oct each card's long lists open with See the changes, so it's opened first
        await pl.pg.evaluate("document.querySelectorAll('main[data-screen=performance] [data-ladder-open][aria-expanded=false]').forEach(b => b.click())")
        await settle(pl.pg, 300)
        here = await pl.pg.evaluate(ladder_js)
        if [x["code"] for x in here] != [c]:
            problems.append(f"{c}'s page has the fare ladder sections {[x['code'] for x in here]}, not its own alone")
        for x in here:
            if not re.fullmatch(r"\d+ up, \d+ hold, \d+ down", x["moves"]):
                problems.append(f"the fare ladder's line for {x['code']} is {x['moves']!r}, not \"N up, N hold, N down\"")
            if not x["plan"]:
                problems.append(f"the fare ladder has no Put on the fare plan for {x['code']}")
            # 21 Oct (route by route): the heading counts the changes to make in the game, as many as the actions listed:
            # the set-back changes (their own list, first, since 21 Oct) and the week's moves
            m = re.fullmatch(r"· (\d+|no) changes? in the game", x["changes"])
            n_moves = next((lst["rows"] for lst in x["lists"] if lst["list"].startswith("actions ")), 0)
            n_fixes = next((lst["rows"] for lst in x["lists"] if lst["list"].startswith("fixes ")), 0)
            n_actions = n_moves + n_fixes
            if not m or (0 if m.group(1) == "no" else int(m.group(1))) != n_actions:
                problems.append(f"the fare ladder's heading for {x['code']} says {x['changes']!r}, not its {n_actions} game actions")
            # the set-back list's heading names the directions it sets back ("3 directions off their level", since 26
            # Oct each direction its own level); none without one
            n_off = x["fix_ways"]
            want_off = "" if not n_fixes else f"{n_off} direction{'' if n_off == 1 else 's'} off {'its' if n_off == 1 else 'their'} level"
            if n_fixes and n_fixes <= 10 and x["off"] != want_off:
                problems.append(f"the fare ladder's set-back list for {x['code']} is headed {x['off']!r}, not {want_off!r}")
            if not n_fixes and x["off"]:
                problems.append(f"the fare ladder for {x['code']} has a set-back heading ({x['off']!r}) but no set-back changes")
            for lst in x["lists"]:
                want_shown, want_button = (10, f"show all {lst['rows']}") if lst["rows"] > 10 else (lst["rows"], "")
                if lst["shown"] != want_shown or lst["button"] != want_button:
                    problems.append(f"the fare ladder's {lst['list']!r} ({lst['rows']}) shows {lst['shown']} rows with {lst['button']!r}, not {want_shown} with {want_button!r}")
        # one long list of each kind, on the first airline's page that has one, opened in full and closed again
        for kind in ("fixes ", "actions ", "ladder "):
            if any(n.startswith(kind) for n in opened_lists):
                continue
            long_ladder = next((lst for x in here for lst in x["lists"] if lst["list"].startswith(kind) and lst["rows"] > 10), None)
            if not long_ladder:
                continue
            sel = f"main[data-screen=performance] [data-list={json.dumps(long_ladder['list'])}] > [data-list-more]"
            await pl.pg.click(sel)
            opened = next((lst for x in await pl.pg.evaluate(ladder_js) for lst in x["lists"] if lst["list"] == long_ladder["list"]), {})
            if opened.get("shown") != long_ladder["rows"] or opened.get("button") != "show fewer":
                problems.append(f"\"show all {long_ladder['rows']}\" on {long_ladder['list']!r} shows {opened.get('shown')} rows with {opened.get('button')!r}")
            await pl.pg.click(sel)
            opened_lists.append(long_ladder["list"])
        ladder += here
    if codes and not ladder:
        problems.append("no airline's page has a fare ladder section")
    count = lambda x, kind: next((lst["rows"] for lst in x["lists"] if lst["list"].startswith(kind)), 0)
    ladder_words = ("; each airline's page its fare ladder: " + " · ".join(f"{x['code']} {x['moves']} ({count(x, 'fixes ')} set-back and {count(x, 'actions ')} other game actions, {count(x, 'ladder ')} directions and cabins)" for x in ladder)
                    + (f", {' and '.join(repr(n) for n in opened_lists)} opened and closed" if opened_lists else "")) if ladder else ""
    await open_screen(pl.pg, 'home')
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return (f"Performance opens with a scorecard for each of the copy's {len(got['cards'])} airlines in order ({'; '.join(got['wow'][:1])}), "
            f"{len(links['links']) if links else 0} fare ladder links and no fare_ladder call, and the group's "
            f"{len(got['boards'])} rows closed{cut_words}; the first scorecard opens {one['path']} with its {len(one['boards'])} rows, Route profit open"
            + (f", its route profit table with the fare index and a 14-day sparkline on each of its {cols['rows']} routes" if cols else "")
            + ladder_words), problems


def busiest_route(code=None, not_code=None):
    """A busy route of our airline with that code, or of any of our airlines but not_code: the one with the most days
    with flights in the daily history (its airports either way, matched to it or to no route, as route_story() reads
    them), so its route page draws its since-launch chart where any can, then the most flights over the last 14 days:
    {code, id, hub, dest}, or None."""
    cond = f"a.iata_code = '{code}'" if code else f"a.iata_code is distinct from '{not_code}'"
    out = psql(f"""select a.iata_code || ' ' || r.id || ' ' || r.hub_code || ' ' || r.dest_code
                     from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                     join public.routes r on r.airline_id = a.id and not r.removed
                     join lateral (select count(distinct d.day) as days,
                                          coalesce(sum(d.flights) filter (where d.day > (select max(x.day) from public.route_days x where x.airline_id = a.id) - 14), 0) as flights
                                     from public.route_days d
                                    where d.airline_id = a.id and d.flights > 0 and (d.route_id = r.id or d.route_id is null)
                                      and ((d.origin_code = r.hub_code and d.dest_code = r.dest_code) or (d.origin_code = r.dest_code and d.dest_code = r.hub_code))) b on b.days > 0
                    where g.kind = 'ours' and a.world_id = {WORLD} and a.active and a.iata_code is not null and {cond}
                      and exists (select 1 from public.rotations rt where rt.route_id = r.id)
                    order by b.days desc, b.flights desc, a.position nulls last, a.id, r.id limit 1""").strip()
    if not out:
        return None
    c, rid, hub, dest = out.split()
    return {"code": c, "id": int(rid), "hub": hub, "dest": dest}


# the route page's boards in their order (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §1: ten, paired in
# two columns at 1100 px and wider)
ROUTE_BOARDS = ["Since launch", "Load by direction", "Loads by flight", "Profit an aircraft hour", "Rival fares", "Market share",
                "Rivals on the pair", "Rivals over time", "Events", "Connections"]
# the boards Routes' route detail shows of a route's story (since 30 Oct, spec docs/specs/2026-10-30-route-story-on-routes.md)
ROUTES_STORY_BOARDS = ["Since launch", "Load by direction", "Rival fares", "Market share", "Rivals over time", "Loads by flight", "Profit an aircraft hour"]
ROUTE_PAGE_JS = """(() => { const m = document.querySelector('main[data-route-page]'); if (!m) return null;
    const q = (s) => m.querySelector(s);
    return { path: location.pathname, route: m.dataset.routePage, airline: m.dataset.airline,
      title: (q('.rphead h1') || {}).textContent || '', fares: (q('[data-fares]') || {}).textContent || '',
      boards: [...m.querySelectorAll('.board > h3.rh')].map(h => h.dataset.rkey), folded: m.querySelectorAll('.board.rcol').length,
      tiles: m.querySelectorAll('[data-wk]').length, compared: (q('[data-figure="performance route: last 7 days"]') || {dataset: {}}).dataset.compared || '',
      chart: !!q('svg.storychart'), short: !!q('[data-story-short]'), markers: +((q('svg.storychart') || {dataset: {}}).dataset.markers || 0),
      events: +((q('[data-list="route events"]') || {dataset: {}}).dataset.listRows || 0),
      shown: m.querySelectorAll('[data-list="route events"] li').length,
      rivals: m.querySelectorAll('[data-rival]').length, conly: m.querySelectorAll('[data-connecting-rival]').length,
      cconn: m.querySelectorAll('[data-figure="performance route: rivals"] td[data-connecting]').length, ends: [...m.querySelectorAll('[data-end]')].map(e => e.dataset.end),
      conns: m.querySelectorAll('[data-conn]').length, nomarket: m.querySelectorAll('[data-no-market]').length,
      fareTables: m.querySelectorAll('[data-fares-direction]').length,
      back: (q('[data-back]') || {}).getAttribute ? q('[data-back]').getAttribute('href') : '',
      schedule: (q('[data-schedule]') || {}).getAttribute ? q('[data-schedule]').getAttribute('href') : '' }; })()"""


async def route_page_opens(pl):
    """The route page (22 Oct, spec docs/specs/2026-10-21-route-page.md §3): from the first airline's route profit table, its
    first route's name opens /planner/performance/<code>/<route>: the header (the route, its fare levels), the last 7 days
    against the 7 before (a tile for load, passengers, profit, profit an aircraft hour and the fares), and its boards open
    (since 30 Oct ten, ROUTE_BOARDS: the five market-page boards with the five before; spec
    docs/specs/2026-10-30-market-pages-planner.md §1; each market board saying so while there is no read), the chart there from 14 days
    with flights and a line saying so before, as many events and rivals as route_story() gives on the copy, 10 events
    shown at most, the connections at both ends; since 23 Oct (spec docs/specs/2026-10-23-rival-connections.md §5) Rivals on
    the pair's connecting column on every row and the rivals that only connect, as route_story() gives them. Its links: "Schedule in Routes" opens the route on Routes, whose header
    links back with "The route's story ›" (a flown route), and "‹ <airline>" opens the airline's page. Competition's threats
    each link to their route's page. Counts and codes only."""
    problems = []
    await open_screen(pl.pg, 'performance')
    await pl.pg.wait_for_selector("main[data-screen=performance][data-performance-ready=yes]", timeout=90000)
    await pl.pg.click("main[data-screen=performance] [data-figure='performance: scorecards'] .fcard")
    await pl.pg.wait_for_function("() => !!(document.querySelector('main[data-screen=performance]') || {dataset: {}}).dataset.airline", timeout=30000)
    await pl.pg.wait_for_selector("main[data-screen=performance][data-performance-ready=yes]", timeout=90000)
    link = await pl.pg.evaluate("(document.querySelector('[data-figure=\"performance: route profit table\"] a[data-route-link]') || {getAttribute: () => ''}).getAttribute('href')")
    code = await pl.pg.evaluate("document.querySelector('main[data-screen=performance]').dataset.airline")
    if link:
        await pl.pg.click("[data-figure='performance: route profit table'] a[data-route-link]")
    else:
        b = busiest_route(code=code) or busiest_route(not_code="")
        if not b:
            return "the route page: no route with flights on the copy to open", []
        link = f"/planner/performance/{b['code']}/{b['hub']}-{b['dest']}"
        await pl.pg.goto(f"http://{LIVE_HOST}:{pl.port}{link}")
    await pl.pg.wait_for_selector("main[data-route-page][data-performance-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate(ROUTE_PAGE_JS)
    if not got:
        return "the route page", ["the route profit table's route didn't open a route page"]
    if got["path"] != link:
        problems.append(f"the route's link is {link}, but the page is at {got['path']}")
    acode, key = got["airline"], got["route"]
    hub, dest = (key.split("-") + ["", ""])[:2]
    rid = one(f"""select to_json(r.id) from public.routes r join public.airlines a on a.id = r.airline_id
                   where a.world_id = {WORLD} and a.iata_code = '{acode}' and r.hub_code = '{hub}' and r.dest_code = '{dest}' order by r.removed, r.id limit 1""")
    doc = one(f"select public.route_story({int(rid)})") if rid else None
    if not doc:
        return "the route page", [f"no route {acode} {key} on the copy"]
    if got["boards"] != ROUTE_BOARDS or got["folded"]:
        problems.append(f"the route page's boards are {got['boards']} ({got['folded']} folded)")
    if not got["title"].startswith(f"{hub}–{dest}"):
        problems.append(f"the route page's title is {got['title']!r}")
    if got["tiles"] not in (5, 6):
        problems.append(f"the last 7 days have {got['tiles']} tiles, not 5 or 6")
    if len(doc["days"]) >= 14 and not got["chart"]:
        problems.append(f"{len(doc['days'])} days with flights, but no since-launch chart")
    if len(doc["days"]) < 14 and not got["short"]:
        problems.append(f"{len(doc['days'])} days with flights, but no line saying the chart starts at 14")
    if got["events"] != len(doc["events"]) or got["shown"] != min(10, len(doc["events"])):
        problems.append(f"the page lists {got['events']} events ({got['shown']} shown); route_story() gives {len(doc['events'])}")
    if got["rivals"] != len(doc["rivals"]["airlines"]):
        problems.append(f"the page lists {got['rivals']} rivals; route_story() gives {len(doc['rivals']['airlines'])}")
    # since 23 Oct: the rivals that only connect, and a connecting cell on every row, when route_story() has them
    conn_only = len(doc["rivals"].get("connecting_only") or [])
    has_conn = "connecting_weekly" in doc["rivals"]
    if got["conly"] != conn_only or got["cconn"] != ((got["rivals"] + conn_only) if has_conn else 0):
        problems.append(f"the page shows {got['conly']} connecting-only rivals and {got['cconn']} connecting cells; route_story() gives {conn_only} "
                        f"(connections {'worked out' if has_conn else 'not worked out'})")
    # since 30 Oct: with no market read every market board says so (Rival fares, Market share, the weeks under Rivals over
    # time); with one, a fares table each way
    if doc.get("market") is None and got["nomarket"] != 3:
        problems.append(f"route_story() has no market read, but {got['nomarket']} boards say so (3 expected)")
    if doc.get("market") is not None and got["fareTables"] != 2:
        problems.append(f"route_story() has a market read, but the page shows {got['fareTables']} fares tables (2 expected)")
    if got["ends"] != [hub, dest]:
        problems.append(f"the connections are at {got['ends']}, not {hub} and {dest}")
    if got["back"] != f"/planner/performance/{acode}" or got["schedule"] != f"/planner/routes/{acode}/{key}":
        problems.append(f"the route page links to {got['back']!r} and {got['schedule']!r}")
    # Schedule in Routes, and back with The route's story ›
    await pl.pg.click("main[data-route-page] [data-schedule]")
    await pl.pg.wait_for_selector("main[data-screen=routes][data-routes-ready=yes]", timeout=60000)
    await pl.pg.wait_for_selector("[data-route-detail]", timeout=30000)
    back = await pl.pg.evaluate("(document.querySelector('[data-route-detail] [data-route-page-link]') || {getAttribute: () => ''}).getAttribute('href')")
    flown = doc["now"]["departures"]["out"] or doc["now"]["departures"]["back"]
    if flown and back != link:
        problems.append(f"Routes' {key} links to {back!r}, not the route page {link}")
    if back:
        await pl.pg.click("[data-route-detail] [data-route-page-link]")
        await pl.pg.wait_for_selector("main[data-route-page][data-performance-ready=yes]", timeout=90000)
    else:
        await pl.pg.go_back()
        await pl.pg.wait_for_selector("main[data-route-page][data-performance-ready=yes]", timeout=90000)
    await pl.pg.click("main[data-route-page] [data-back]")
    await pl.pg.wait_for_function(f"() => location.pathname === '/planner/performance/{acode}'", timeout=30000)
    await pl.pg.wait_for_selector("main[data-screen=performance][data-performance-ready=yes]:not([data-route-page])", timeout=90000)
    # Competition's threats: each links to its route's page
    await open_screen(pl.pg, 'competition')
    await pl.pg.wait_for_selector("main[data-screen=competition][data-competition-ready=yes]", timeout=90000)
    threats = await pl.pg.evaluate("""({ n: document.querySelectorAll('[data-threat]').length,
        links: [...document.querySelectorAll('[data-threat] a[data-route-page-link]')].map(a => a.getAttribute('href')) })""")
    if len(threats["links"]) != threats["n"] or any(not re.fullmatch(r"/planner/performance/[A-Z0-9]+/[A-Z0-9]{3,4}-[A-Z0-9]{3,4}", h or "") for h in threats["links"]):
        problems.append(f"{threats['n']} threats on Competition, {len(threats['links'])} linking to a route page")
    await open_screen(pl.pg, 'home')
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return (f"the route page: {acode} {key} opens from the route profit table with its header, {got['tiles']} tiles for the last 7 days "
            f"({'compared' if got['compared'] == 'yes' else 'nothing to compare'}), its {len(got['boards'])} boards open, "
            f"{'the since-launch chart (' + str(got['markers']) + ' event markers)' if got['chart'] else 'the chart waiting for 14 days'}, "
            f"{got['events']} events ({got['shown']} shown), {got['rivals']} rivals and {got['conns']} city pairs shown at its two ends, as route_story() "
            f"gives them; Schedule in Routes and back ({'The route' + chr(39) + 's story ›' if back else 'not flown: no link back'}), ‹ airline to its page; "
            f"Competition's {threats['n']} threats each link to their route's page"), problems


async def last_screens_open(pl):
    """Interline, Photos and Reference are rebuilt (build pull request 12): no screen is a placeholder any more. Interline
    shows its agreements board and the interline countries; Photos a logo card for each of our airlines; Reference its
    sections, every one folded on arrival, the first one opened by its address. The header has the search box and the
    Website button. Their figures are compared with the old screens' by tests/reference_side_by_side_test.py."""
    want = [r for r in psql(f"""select coalesce(a.planner_name, a.public_name, a.game_name) from public.airlines a
                                join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                where g.kind = 'ours' and a.world_id = {WORLD}
                                order by a.position nulls last, a.id""").splitlines() if r]
    problems, seen = [], []
    if not await pl.pg.evaluate("!!document.querySelector('header #gsearch') && !!document.querySelector('header a.eqsite[href=\"/\"]')"):
        problems.append("the header has no search box or Website button")
    for sid, ready in (("interline", "data-interline-ready"), ("photos", "data-photos-ready"), ("reference", "data-reference-ready")):
        await open_screen(pl.pg, sid)
        await pl.pg.wait_for_selector(f"main[data-screen={sid}][{ready}=yes]", timeout=90000)
        await settle(pl.pg, 300)
        if await pl.pg.evaluate(f"!!document.querySelector('main[data-screen={sid}] [data-not-built]')"):
            problems.append(f"{sid} still shows the placeholder's line to the old planner")
    await open_screen(pl.pg, 'interline')
    await pl.pg.wait_for_selector("main[data-screen=interline][data-interline-ready=yes]", timeout=60000)
    il = await pl.pg.evaluate("""({ boards: !!document.querySelector('[data-figure="interline: agreements"]') && !!document.querySelector('[data-figure="interline: countries"]'),
        countries: document.querySelectorAll('[data-figure="interline: countries"] tr').length - 1 })""")
    if not il["boards"] or il["countries"] < 1:
        problems.append(f"Interline has no agreements board or interline countries ({il})")
    seen.append(f"Interline with {il['countries']} interline countries")
    await open_screen(pl.pg, 'photos')
    await pl.pg.wait_for_selector("main[data-screen=photos][data-photos-ready=yes]", timeout=60000)
    logos = await pl.pg.evaluate("[...document.querySelectorAll('main[data-screen=photos] [data-lg]')].map(c => c.dataset.lg)")
    if logos != want:
        problems.append(f"Photos' logos are for {logos}, the copy's airlines are {want}")
    seen.append(f"Photos with {len(logos)} logos")
    await open_screen(pl.pg, 'reference')
    await pl.pg.wait_for_selector("main[data-screen=reference][data-reference-ready=yes]", timeout=60000)
    ref = await pl.pg.evaluate("""({ sections: [...document.querySelectorAll('main[data-screen=reference] details.rsec')].map(d => d.dataset.section),
        open: [...document.querySelectorAll('main[data-screen=reference] details.rsec')].filter(d => d.open).length })""")
    if ref["open"] or len(ref["sections"]) < 11:
        problems.append(f"Reference's sections {ref['sections']}, {ref['open']} open on arrival (all should be folded)")
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", "/reference/constants")
    await pl.pg.wait_for_function("() => (document.querySelector('details.rsec[data-section=constants]') || {}).open === true", timeout=30000)
    seen.append(f"Reference with {len(ref['sections'])} sections, folded, /reference/constants opening Constants")
    await open_screen(pl.pg, 'home')
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return "no screen is a placeholder any more: " + ", ".join(seen) + "; the header has the search box and the Website button", problems


# ---------- 3. a to-do ticked through window.__eqPlanner.save() ----------
async def tick_todo(pl):
    tid = psql(f"select coalesce(min(t.id)::text, '') from public.todos t where t.world_id = {WORLD} and not t.done").strip()
    if not tid:
        return "tick the first open to-do", ["the copy has no open to-do"]
    tid = int(tid)
    name = f"window.__eqPlanner.save() ticks the first open to-do ({tid})"
    rows = await pl.read("todos", {"id": tid})
    if len(rows) != 1:
        return name, [f"the planner read {len(rows)} row(s) for it"]
    before, n0, mark, client = todo_row(tid), counts(), marks(), await pl.client()
    res = await pl.save([{"table": "todos", "op": "update", "key": {"id": tid}, "base": rows[0]["updated_at"],
                          "values": {"done": True, "done_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}}])
    after = todo_row(tid)
    problems = []
    if res.get("status") != "saved":
        problems.append(f"the save answered {res.get('status')}: {res.get('error') or res.get('message') or ''}"[:200])
    if not after or after.get("done") is not True or not after.get("done_at"):
        problems.append("the to-do isn't done in the copy")
    other = sorted(k for k in set(before or {}) | set(after or {}) if k not in ("done", "done_at", "updated_at") and (before or {}).get(k) != (after or {}).get(k))
    if other:
        problems.append("other columns changed: " + ", ".join(other))
    if after and after.get("updated_at") == (before or {}).get("updated_at"):
        problems.append("updated_at didn't move")
    saved = ((res.get("answer") or {}).get("rows") or [{}])[0]
    if after and (not saved.get("updated_at") or micros(saved["updated_at"]) != micros(after["updated_at"])):
        problems.append("the answer doesn't give the row's new updated_at")
    log = log_since(mark)
    if len(log) != 1:
        problems.append(f"{len(log)} change-log row(s), expected 1")
    for r in log:
        if not (r["table"] == "todos" and r["op"] == "update" and r["id"] == str(tid) and set(r["fields"]) <= {"done", "done_at"}):
            problems.append(f"the tables changed beyond the save: {r['table']} {r['op']} {r['id'] or ''} ({', '.join(r['fields'])})")
        if r["actor"] != "planner" or r["detail"] != client:
            problems.append(f"a change-log row names {r['actor']} ({r['detail']}), not planner (the tab's ID)")
    problems += count_changes(n0, counts(), allow={"public.change_log"})
    problems += [f"a job_runs row: {j['job']}" for j in jobs_since(mark)]
    state = await pl.pg.evaluate("(document.querySelector('[data-save-state]') || {}).textContent")
    if state != "saved":
        problems.append(f"the header says {state!r} after the save")
    # put it back, from the answer's updated_at as the base: the next change to a row needs no new read, and the copy
    # keeps its open to-dos for the real saves that follow
    if saved.get("updated_at"):
        back = await pl.save([{"table": "todos", "op": "update", "key": {"id": tid}, "base": saved["updated_at"],
                               "values": {"done": False, "done_at": (before or {}).get("done_at")}}])
        if back.get("status") != "saved":
            problems.append(f"putting it back from the answer's updated_at answered {back.get('status')}")
        elif {k: v for k, v in (todo_row(tid) or {}).items() if k != "updated_at"} != {k: v for k, v in (before or {}).items() if k != "updated_at"}:
            problems.append("putting it back didn't leave the row as it was")
    return (f"{name}: done and done_at changed in exactly that row, logged as planner with the tab's ID; put back by a second "
            "save from the answer's updated_at"), problems


# ---------- 4. two tabs ----------
async def two_tabs(p, port, env, facts, staff, seen):
    ids = [int(x) for x in psql(f"select t.id from public.todos t where t.world_id = {WORLD} order by t.done, t.id limit 2").split()]
    if len(ids) < 2:
        return "two tabs", ["the copy has fewer than two to-dos"]
    x, y = ids
    a, b = Planner(p, port, env, facts), Planner(p, port, env, facts)
    seen += [a, b]
    problems = []
    try:
        await a.open(); await a.sign_in(*staff)
        await b.open(); await b.sign_in(*staff)
        ca, cb = await a.client(), await b.client()
        if not ca or ca == cb:
            problems.append("the two tabs don't have two tab IDs")
        ax, = await a.read("todos", {"id": x})
        bx, = await b.read("todos", {"id": x})
        by, = await b.read("todos", {"id": y})
        y0 = todo_row(y)
        ta, tb = f"two tabs {secrets.token_hex(3)}: first", f"two tabs {secrets.token_hex(3)}: second"
        r1 = await a.save([{"table": "todos", "op": "update", "key": {"id": x}, "base": ax["updated_at"], "values": {"title": ta}}])
        if r1.get("status") != "saved":
            problems.append(f"the first tab's change wasn't saved ({r1.get('status')})")
        mark = marks()
        r2 = await b.save([{"table": "todos", "op": "update", "key": {"id": x}, "base": bx["updated_at"], "values": {"title": tb}},
                           {"table": "todos", "op": "update", "key": {"id": y}, "base": by["updated_at"], "values": {"title": tb}}])
        clashes = (r2.get("answer") or {}).get("clashes") or []
        if r2.get("status") != "clash":
            problems.append(f"the second tab's change answered {r2.get('status')}, not a clash")
        if [(c.get("table"), (c.get("key") or {}).get("id")) for c in clashes] != [("todos", x)]:
            problems.append("the clash doesn't name exactly the first tab's row")
        elif ((clashes[0].get("current") or {}).get("title")) != ta:
            problems.append("the clash doesn't carry the first tab's title")
        if (todo_row(x) or {}).get("title") != ta:
            problems.append("the clashing row isn't as the first tab left it")
        if todo_row(y) != y0:
            problems.append("the second tab's change to the other row was written")
        if log_since(mark):
            problems.append("the second tab's clashing call wrote something")
        await settle(b.pg, 300)
        cached_x = await b.pg.evaluate("k => window.__eqPlanner.cached('todos', k)", {"id": x})
        cached_y = await b.pg.evaluate("k => window.__eqPlanner.cached('todos', k)", {"id": y})
        if (cached_x or {}).get("title") != ta:
            problems.append("the second tab doesn't show the row as it is now")
        if (cached_y or {}).get("title") != by.get("title"):
            problems.append("the second tab still shows its unsaved change to the other row")
        msg = await b.pg.evaluate("[...document.querySelectorAll('[data-message]')].map(m => m.textContent).join(' | ')")
        if f"todos {x}" not in msg or "Not saved" not in msg:
            problems.append("the second tab didn't say which row clashed")
        problems += a.errors + b.errors
    finally:
        await a.close(); await b.close()
    return (f"two tabs: the second's change to to-do {x} came back as a clash with the first's title, its change to to-do {y} "
            "in the same call wasn't written, and it shows and names the row"), problems


# ---------- 5. a preview address ----------
async def preview(p, port, env, facts, staff, seen):
    pv = Planner(p, port, env, facts)
    seen.append(pv)
    problems = []
    try:
        await pv.open(host="127.0.0.1")
        await pv.sign_in(*staff)
        n0, mark = counts(), marks()
        tid = int(psql(f"select min(t.id) from public.todos t where t.world_id = {WORLD}").strip())
        row, = await pv.read("todos", {"id": tid})
        res = await pv.save([{"table": "todos", "op": "update", "key": {"id": tid}, "base": row["updated_at"], "values": {"title": "preview check"}}])
        await settle(pv.pg, 800)
        if res.get("status") != "preview":
            problems.append(f"the save answered {res.get('status')}, not preview")
        state = await pv.pg.evaluate("(document.querySelector('[data-save-state]') || {}).textContent")
        if state != "preview · not saved":
            problems.append(f"the header says {state!r}, not \"preview · not saved\"")
        if not await pv.pg.evaluate("!!document.querySelector('.eqpreview')"):
            problems.append("no preview notice on the page")
        link = await pv.pg.evaluate("(document.querySelector('.eqpreview a') || {href: ''}).href")
        if link != f"https://{LIVE_HOST}{NEW_PLANNER}":
            problems.append(f"the preview notice links to {link!r}, not the live planner at https://{LIVE_HOST}{NEW_PLANNER}")
        if "planner_save" in pv.rpcs:
            problems.append("the preview sent planner_save() to the copy")
        if log_since(mark):
            problems.append("the tables changed")
        problems += count_changes(n0, counts()) + pv.errors
    finally:
        await pv.close()
    return (f"a preview address reads (Home shown), sends no write (it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'}), and its "
            f"notice links to the live planner at {NEW_PLANNER}"), problems


# ---------- 6. every screen at the frozen moment, at 1280 and 380 px ----------
READY = {"home": "main[data-screen=home][data-home-ready=yes]", "today": "main[data-screen=today][data-today-ready=yes]",
         "routes": "main[data-screen=routes][data-routes-ready=yes]", "tails": "main[data-screen=tails][data-tails-ready=yes]",
         "performance": "main[data-screen=performance][data-performance-ready=yes]",
         "competition": "main[data-screen=competition][data-competition-ready=yes]",
         "interline": "main[data-screen=interline][data-interline-ready=yes]", "photos": "main[data-screen=photos][data-photos-ready=yes]",
         "reference": "main[data-screen=reference][data-reference-ready=yes]", "systems": "main[data-screen=systems][data-systems-ready=yes]"}


def first_airline():
    """Our first active airline's code (the one whose Performance page the screens open), or VS without one."""
    code = psql(f"""select coalesce((select a.iata_code from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                     where g.kind = 'ours' and a.world_id = {WORLD} and a.active and a.iata_code is not null
                     order by a.position nulls last, a.id limit 1), 'VS')""").strip()
    return code or "VS"


def sample_line(code):
    """A sample 7-day line for the screens (28 Oct, spec docs/specs/2026-10-27-long-haul-lines.md §2): on the airline whose
    Tails opens first, a line of the type of its first aircraft, two legs on its first route, and an aircraft on order made
    for the test holding offset 0 with its card, so Tails' deliveries board shows a line with its slots at both widths.
    Made outside the change log and removed again by the function it returns; nothing when the airline has no route or
    aircraft."""
    tag = secrets.token_hex(3).upper()
    reg, name = "ZN" + tag[:4], "screens sample line " + tag
    x = one(f"""select json_build_object('airline', a.id, 'type', t.aircraft_type_id, 'hub', r.hub_code, 'dest', r.dest_code)
                  from public.airlines a
                  join lateral (select x.aircraft_type_id from public.aircraft x where x.airline_id = a.id and x.aircraft_type_id is not null order by x.id limit 1) t on true
                  join lateral (select y.hub_code, y.dest_code from public.routes y where y.airline_id = a.id and not y.removed order by y.id limit 1) r on true
                 where a.world_id = {WORLD} and a.iata_code = :'c'""", c=code)
    if not x:
        return lambda: None
    psql(f"""set equinox.change_log = 'off';
             insert into public.plan_lines (world_id, airline_id, aircraft_type_id, name) values ({WORLD}, {int(x['airline'])}, {int(x['type'])}, :'n');
             insert into public.plan_line_legs (world_id, line_id, position, line_day, flight_no, origin_code, dest_code, dep_utc_min, block_min)
             select l.world_id, l.id, v.p, v.d, null, v.o, v.k, v.dep, 120 from public.plan_lines l
              cross join (values (1, 1, :'h', :'k', 360), (2, 2, :'k', :'h', 120)) as v(p, d, o, k, dep) where l.name = :'n';
             insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, delivery_at, order_base_code, acquired)
             values ({WORLD}, {int(x['airline'])}, :'r', {int(x['type'])}, 'on_order', now() + interval '20 days', :'h', 'new');
             insert into public.plan_cards (world_id, airline_id, aircraft_id, base_code, title, line_id, line_day_offset)
             select a.world_id, a.airline_id, a.id, :'h', :'n' || ' · 1 of 7', l.id, 0 from public.aircraft a, public.plan_lines l where a.registration = :'r' and l.name = :'n';
             insert into public.plan_card_legs (world_id, plan_card_id, position, origin_code, dest_code, days_utc, dep_utc_min, block_min)
             select c.world_id, c.id, g.position, g.origin_code, g.dest_code, array[g.line_day]::smallint[], g.dep_utc_min, g.block_min
               from public.plan_cards c join public.plan_line_legs g on g.line_id = c.line_id join public.aircraft a on a.id = c.aircraft_id where a.registration = :'r';""",
         n=name, h=x["hub"], k=x["dest"], r=reg)

    def remove():
        psql("""set equinox.change_log = 'off';
                delete from public.plan_card_legs where plan_card_id in (select c.id from public.plan_cards c join public.aircraft a on a.id = c.aircraft_id where a.registration = :'r');
                delete from public.plan_cards where aircraft_id in (select a.id from public.aircraft a where a.registration = :'r');
                delete from public.aircraft where registration = :'r';
                delete from public.plan_lines where name = :'n';""", n=name, r=reg)
    return remove


async def screens(p, port, env, facts, staff, seen, moment):
    """Every screen opens on the copy at the frozen moment (the copy's latest capture plus one hour), signed in as test
    staff, at 1280 and at 380 px wide: ready (it has read everything), no errors, no sideways scroll (Systems with every
    board open, Reference with every section open), and no link into the old planner, to /planner/next/ or to a screen
    that went on 20 Oct (Hubs, Check, Review); then one airline's Performance page the same way. With PLANNER_SCREENS_DIR
    set, a screenshot of each at each width goes there (the run's planner-screens artifact): Today, Performance (the group
    and one airline) and Systems among them. What replaced the side by sides' screen checks (build pull request 14)."""
    problems = []
    scroll = "(() => Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth)()"
    links = shots = 0
    code = first_airline()
    # the route page (22 Oct): a busy legacy route (any of our airlines but Ryanair) and a busy Ryanair route, each the one
    # with the most days with flights, so the since-launch chart is drawn where any route has 14
    route_pages = [r for r in (busiest_route(not_code="FR"), busiest_route(code="FR")) if r]
    # a sample line on the airline Tails opens on (28 Oct), so the deliveries board's line and its slots are looked at too
    tails_code = psql(f"""select coalesce((select a.iata_code from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                       where g.kind = 'ours' and a.world_id = {WORLD} and a.active order by a.position nulls last, a.id limit 1), '')""").strip()
    remove_line = sample_line(tails_code) if tails_code else (lambda: None)
    if SCREENS_DIR:
        Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    try:
        # since 30 Oct (spec docs/specs/2026-10-30-route-story-on-routes.md) also 1700 px, for Routes' route detail only: the
        # route's story in a third column from 1,600 px
        for width, height in ((1280, 900), (380, 800), (1700, 1000)):
            only_routes = width == 1700
            ph = Planner(p, port, env, facts, width=width, height=height)
            seen.append(ph)
            try:
                await ph.open(moment=moment)
                await ph.pg.emulate_media(reduced_motion="reduce")   # the globe holds still, so two screenshots of a moment are the same
                await ph.sign_in(*staff)
                if abs(await ph.pg.evaluate("Date.now()") - ms(moment)) > 1000:
                    problems.append(f"{width} px: the planner's clock isn't frozen at the moment")

                async def look(sid, name):
                    nonlocal links, shots
                    if sid == "systems":
                        await ph.pg.click("#rev-expall")   # every board open: the widest the screen gets
                        await settle(ph.pg, 300)
                    if sid == "performance" and not name.startswith("route-"):
                        # 22 Oct: every row and (on an airline's page since 26 Oct) its fare ladder card's changes open, the widest
                        # the page gets
                        await ph.pg.evaluate("""(() => { const b = document.querySelector('main[data-screen=performance] #rev-expall'); if (b) b.click();
                            document.querySelectorAll('main[data-screen=performance] [data-ladder-open][aria-expanded=false]').forEach(x => x.click()); })()""")
                        await settle(ph.pg, 400)
                    if sid == "reference":
                        await ph.pg.evaluate("document.querySelectorAll('main[data-screen=reference] details.rsec').forEach(d => { d.open = true; })")
                        await settle(ph.pg, 400)
                    if sid == "tails" and tails_code and not await ph.pg.evaluate("!!document.querySelector('[data-figure=\"tails: lines\"] [data-line-slot]')"):
                        problems.append(f"tails at {width} px: the sample line's slots aren't on the deliveries board")
                    if sid == "today" and tails_code and not await ph.pg.evaluate("!!document.querySelector('[data-figure=\"today: open lines\"] [data-open-line] a[data-line-link]')"):
                        problems.append(f"today at {width} px: the sample line (1 of 7) isn't among Orders' open lines")
                    over = await ph.pg.evaluate(scroll)
                    if over > 0:
                        problems.append(f"{name}: the page scrolls sideways by {over} px at {width} px wide")
                    if name.startswith("route-"):
                        # the route page's events (22 Oct): every one shown, then cut to 10 again
                        more = "main[data-route-page] [data-list-more]"
                        if await ph.pg.evaluate(f"(() => {{ const b = document.querySelector({json.dumps(more)}); if (b) b.click(); return !!b; }})()"):
                            await settle(ph.pg, 300)
                            over = await ph.pg.evaluate(scroll)
                            if over > 0:
                                problems.append(f"{name}: with every event shown, the page scrolls sideways by {over} px at {width} px wide")
                            await ph.pg.evaluate(f"document.querySelector({json.dumps(more)}).click()")
                            await settle(ph.pg, 200)
                    if name == "competition-airline":
                        # the openings (21 Oct): opened in full, the widest the page gets, then cut again
                        more = "main[data-screen=competition] [data-list-more]"
                        if await ph.pg.evaluate(f"(() => {{ const b = document.querySelector({json.dumps(more)}); if (b) b.click(); return !!b; }})()"):
                            await settle(ph.pg, 300)
                            over = await ph.pg.evaluate(scroll)
                            if over > 0:
                                problems.append(f"competition: with every opening shown, the page scrolls sideways by {over} px at {width} px wide")
                    if name == "performance-airline":
                        # the fare ladder (21 Oct; on the airline's page since 26 Oct): there, and its lists (game actions,
                        # routes) opened in full, then cut again
                        more = "main[data-screen=performance] [data-figure='performance: fare ladder'] [data-list] > [data-list-more]"
                        if not await ph.pg.evaluate("""!!document.querySelector('main[data-screen=performance] [data-figure="performance: fare ladder"]')"""):
                            problems.append(f"performance/{code} at {width} px: no fare ladder board")
                        n_open = await ph.pg.evaluate(f"(() => {{ const b = [...document.querySelectorAll({json.dumps(more)})]; b.forEach(x => x.click()); return b.length; }})()")
                        if n_open:
                            await settle(ph.pg, 300)
                            over = await ph.pg.evaluate(scroll)
                            if over > 0:
                                problems.append(f"performance: with the fare ladder's lists open, the page scrolls sideways by {over} px at {width} px wide")
                            await ph.pg.evaluate(f"document.querySelectorAll({json.dumps(more)}).forEach(x => x.click())")
                            await settle(ph.pg, 200)
                    hrefs = await ph.pg.evaluate("[...document.querySelectorAll('a[href]')].map(a => a.getAttribute('href'))")
                    links += len(hrefs)
                    problems.extend(f"{name}: a link to {h}" for h in hrefs if OLD_LINK.match(h or ""))
                    if SCREENS_DIR:
                        await ph.pg.screenshot(path=str(Path(SCREENS_DIR) / f"{name}-{width}.png"), full_page=True, timeout=90000)
                        shots += 1

                for sid, href in ([] if only_routes else SCREENS):
                    e0 = len(ph.errors)
                    await open_screen(ph.pg, sid)
                    await ph.pg.wait_for_selector(f"main[data-screen={sid}]", timeout=15000)
                    path = await ph.pg.evaluate("location.pathname")
                    if path != href:
                        problems.append(f"{sid}: its address is {path}, expected {href}")
                    try:
                        await ph.pg.wait_for_selector(READY[sid], timeout=90000)
                        await settle(ph.pg, 400)
                    except Exception:
                        problems.append(f"{sid}: it isn't ready at {width} px wide")
                    await look(sid, sid)
                    problems += [f"{sid} at {width} px: {e}" for e in ph.errors[e0:]]
                # one airline's Performance page, opened directly by its address
                if not only_routes:
                    e0 = len(ph.errors)
                    await ph.pg.goto(f"http://{LIVE_HOST}:{port}/planner/performance/{code}")
                    try:
                        await ph.pg.wait_for_selector(READY["performance"], timeout=90000)
                        await settle(ph.pg, 400)
                        if await ph.pg.evaluate("document.querySelector('main[data-screen=performance]').dataset.airline") != code:
                            problems.append(f"/planner/performance/{code} doesn't open {code}'s page")
                    except Exception:
                        problems.append(f"performance/{code}: it isn't ready at {width} px wide")
                    await look("performance", "performance-airline")
                    problems += [f"performance/{code} at {width} px: {e}" for e in ph.errors[e0:]]
                    # one airline's Competition page (21 Oct), opened directly by its address, its openings shown in full
                    e0 = len(ph.errors)
                    await ph.pg.goto(f"http://{LIVE_HOST}:{port}/planner/competition/{code}")
                    try:
                        await ph.pg.wait_for_selector(f"main[data-screen=competition][data-airline='{code}'][data-competition-ready=yes]", timeout=90000)
                        await settle(ph.pg, 400)
                    except Exception:
                        problems.append(f"competition/{code}: it isn't ready at {width} px wide")
                    await look("competition", "competition-airline")
                    problems += [f"competition/{code} at {width} px: {e}" for e in ph.errors[e0:]]
                # a route open on Routes (22 Oct, spec docs/specs/2026-10-22-planner-look-routes.md): the busy legacy route, opened
                # by its address, its detail beside the list (on a phone, full screen)
                for r in route_pages[:1]:
                    e0 = len(ph.errors)
                    addr = f"/planner/routes/{r['code']}/{r['hub']}-{r['dest']}"
                    await ph.pg.goto(f"http://{LIVE_HOST}:{port}{addr}")
                    try:
                        await ph.pg.wait_for_selector(f"{READY['routes']} [data-route-detail='{r['hub']}-{r['dest']}']", timeout=90000)
                        await settle(ph.pg, 400)
                    except Exception:
                        problems.append(f"{addr}: its route isn't open at {width} px wide")
                    # the route's story (30 Oct): a third column from 1,600 px, under the frequencies from 1,100 px, none below;
                    # its tiles and its seven boards, "Full story ›" to the route page
                    where = "[data-story-column]" if width >= 1600 else "[data-story-below]" if width >= 1100 else None
                    if where:
                        try:
                            await ph.pg.wait_for_selector(f"{where} [data-route-story], {where} [data-route-story-none]", timeout=90000)
                            await settle(ph.pg, 300)
                            st = await ph.pg.evaluate(f"""(() => {{ const m = document.querySelector({json.dumps(where)}); return {{
                                boards: [...m.querySelectorAll('.board > h3.rh')].map(h => h.dataset.rkey), tiles: m.querySelectorAll('[data-wk]').length,
                                full: (m.querySelector('[data-full-story]') || {{getAttribute: () => ''}}).getAttribute('href'), none: !!m.querySelector('[data-route-story-none]') }}; }})()""")
                            if not st["none"] and (st["boards"] != ROUTES_STORY_BOARDS or st["full"] != f"/planner/performance/{r['code']}/{r['hub']}-{r['dest']}"):
                                problems.append(f"{addr} at {width} px: the route's story shows {st['boards']} linking to {st['full']!r}")
                        except Exception:
                            problems.append(f"{addr} at {width} px: no route's story {'beside the route' if width >= 1600 else 'under the frequencies'}")
                    elif await ph.pg.evaluate("!!document.querySelector('[data-route-story], [data-story-column], [data-story-below]')"):
                        problems.append(f"{addr} at {width} px: the route's story shows under 1,100 px")
                    await look("routes", "routes-detail")
                    problems += [f"{addr} at {width} px: {e}" for e in ph.errors[e0:]]
                # the route page (22 Oct), opened directly by its address: a busy legacy route and a Ryanair route
                for r in ([] if only_routes else route_pages):
                    e0 = len(ph.errors)
                    addr = f"/planner/performance/{r['code']}/{r['hub']}-{r['dest']}"
                    await ph.pg.goto(f"http://{LIVE_HOST}:{port}{addr}")
                    try:
                        await ph.pg.wait_for_selector("main[data-route-page][data-performance-ready=yes]", timeout=90000)
                        await settle(ph.pg, 400)
                        if not await ph.pg.evaluate("!!document.querySelector('main[data-route-page] .rphead')"):
                            problems.append(f"{addr} at {width} px: no route page header")
                    except Exception:
                        problems.append(f"{addr}: it isn't ready at {width} px wide")
                    await look("performance", f"route-{r['code']}")
                    problems += [f"{addr} at {width} px: {e}" for e in ph.errors[e0:]]
                problems += [e for e in ph.errors if not any(e in x for x in problems)]
            finally:
                await ph.close()
    finally:
        remove_line()
    routes_words = " and ".join(f"{r['code']} {r['hub']}–{r['dest']}" for r in route_pages) or "no route with flights"
    return (f"every screen ({len(SCREENS)}), {code}'s Performance and Competition pages and the route pages of {routes_words} open on the copy at the moment ({moment}), at 1280 and 380 px wide (and Routes' route detail at 1700, with the route's story in its third column): "
            f"ready, no errors, no sideways scroll (Systems with every board open, Reference with every section open), and none of their {links} "
            f"links goes into the old planner, to /planner/next/ or to Hubs, Check or Review" + (f"; {shots} screenshots kept" if shots else "")), problems


# ---------- 6b. the Systems board, and a short page on Today (decisions #21, #23) ----------
SYS_FIXED = ["snapshot", "backup", "archive", "cleanup", "scan", "market", "build", "usage|database", "usage|report_pdfs", "usage|site_public"]
SYS_LINES = """[...document.querySelectorAll('[data-figure="systems: board"] .sysline')].map(li => ({ key: li.dataset.sys, mark: li.dataset.mark,
    label: (li.querySelector('.syslabel') || {}).textContent || '', when: (li.querySelector('.syswhen') || {}).textContent || '',
    text: (li.querySelector('.systext') || {}).textContent || '', dot: !!li.querySelector('.sysmark.' + li.dataset.mark) }))"""


async def open_systems(ph):
    await open_screen(ph.pg, 'systems')
    await ph.pg.wait_for_selector(READY["systems"], timeout=90000)
    await settle(ph.pg, 400)
    return await ph.pg.evaluate(SYS_LINES)


async def systems_board(p, port, env, facts, staff, seen, moment):
    """The Systems board (#23) on the copy at the frozen moment: at the top of Systems, open, one line for each of our
    airlines' evening capture and one each for the snapshot, the backup, the archive, the clean-ups, the world scan, (since
    30 Oct) the market pages, the planner's build (stamped by the build) and the three usage figures, every one with a green, amber or red mark. The
    lines and their marks are printed (names, marks, dates and sizes only). Since 22 Oct the fixed lines are tiles, worst
    first, and the captures a table under them."""
    problems = []
    ids = [int(r) for r in psql(f"""select al.airline_id from private.fig_airlines({WORLD}) al where al.home_code is not null order by al.ord""").split() if r]
    ph = Planner(p, port, env, facts)
    seen.append(ph)
    try:
        await ph.open(moment=moment)
        await ph.sign_in(*staff)
        lines = await open_systems(ph)
        first = await ph.pg.evaluate("(document.querySelector('main[data-screen=systems] .board') || {}).id || ''")
        if first != "systems":
            problems.append(f"the Systems board isn't the first board on Systems (the first is {first or 'none'})")
        # since 22 Oct (spec docs/specs/2026-10-22-planner-look-systems.md) the fixed lines are tiles, worst first (red, then
        # amber, then green, each in the board's order), and each airline's capture a row of the table under them
        rank = {"bad": 0, "warn": 1, "ok": 2}
        tiles = [l for l in lines if not l["key"].startswith("capture|")]
        caps = [l["key"] for l in lines if l["key"].startswith("capture|")]
        want_tiles = sorted(SYS_FIXED, key=lambda k: (rank.get(next((l["mark"] for l in tiles if l["key"] == k), ""), 3), SYS_FIXED.index(k)))
        if caps != [f"capture|{i}" for i in ids] or [l["key"] for l in tiles] != want_tiles:
            problems.append(f"the board's lines are {[l['key'] for l in lines]}, expected the tiles {want_tiles} and the capture rows {[f'capture|{i}' for i in ids]}")
        problems += [f"{l['label'] or l['key']}: no mark ({l['mark']!r})" for l in lines if l["mark"] not in ("ok", "warn", "bad") or not l["dot"]]
        build = next((l for l in lines if l["key"] == "build"), None)
        if build and build["mark"] != "ok":
            problems.append("the planner's build line has no stamp: " + build["text"])
        problems += ph.errors
    finally:
        await ph.close()
    words = {"ok": "green", "warn": "amber", "bad": "red"}
    shown = "; ".join(f"{l['label']}: {words.get(l['mark'], l['mark'])}" + (f", {l['when']}" if l["when"] else "") + f" ({l['text'][:90]})" for l in lines)
    return f"the Systems board on the copy at {moment}: {len(lines)} lines, each marked: {shown}", problems


async def short_page(p, port, env, facts, staff, seen, moment):
    """A short page made on purpose (#21), then put back: half of an airline's latest loads page, stored just after the
    copy's latest capture and judged by private.capture_check() against what the copy expects of it, is short; Today's
    needs attention lists it in the Capture group linking to Systems, Today's capture line says it came in short (or
    worse), and the Systems board marks that airline amber. The page is deleted afterwards, and the copy's raw pages are
    as they were."""
    problems = []
    before = psql("select count(*) from public.game_capture_raw").strip()
    rid = made = verdict = None
    cap = {}
    ph = Planner(p, port, env, facts)
    seen.append(ph)
    try:
        made = one(f"""with src as (select r.* from public.game_capture_raw r where r.world_id = {WORLD} and r.kind = 'loads'
                                      order by r.captured_at desc, r.id desc limit 1),
              rows_ as (select e, o, jsonb_array_length(e) >= 15 and e ->> 0 ~ '^[A-Z0-9]{{2,3}}\\s?\\d{{1,5}}' and e ->> 3 ~ '\\d{{2}}\\.\\d{{2}}\\. \\d{{2}}:\\d{{2}}' as flight
                          from src, jsonb_array_elements(src.rows) with ordinality x(e, o)),
              half as (select count(*) filter (where flight) / 2 as keep from rows_),
              kept as (select r.e, r.o, r.flight, count(*) filter (where r.flight) over (order by r.o) as nth from rows_ r)
              select json_build_object('world_id', src.world_id, 'airline_id', src.airline_id, 'airline', src.airline,
                       'rows', (select jsonb_agg(k.e order by k.o) from kept k, half where not k.flight or k.nth <= half.keep),
                       'read', (select keep from half), 'at', private.fig_ts(timestamptz '{moment}' - interval '50 minutes'))
                from src""")
        if not made:
            return "a short page made on purpose", ["the copy has no loads page to halve"]
        rid = int(psql("insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at) "
                       "values (:'w', :'a', :'n', 'loads', '/rehearsal/short-on-purpose', :'r'::jsonb, :'t') returning id",
                       w=made["world_id"], a=made["airline_id"], n=made["airline"], r=json.dumps(made["rows"]), t=made["at"]).strip())
        verdict = one(f"select private.capture_check({rid}, jsonb_build_object('ok', true, 'rows', {int(made['read'])}))")
        if not verdict or verdict.get("verdict") != "short":
            problems.append(f"half of {made['airline']}'s loads page isn't judged short: {verdict}")
        await ph.open(moment=moment)
        await ph.sign_in(*staff)
        await open_screen(ph.pg, 'today')
        await ph.pg.wait_for_selector(READY["today"], timeout=90000)
        await settle(ph.pg, 400)
        await ph.pg.evaluate("document.querySelectorAll('#attention details').forEach(d => d.open = true)")
        items = await ph.pg.evaluate("""[...document.querySelectorAll('[data-figure="today: needs attention"] [data-att-item]')]
            .map(li => ({ kind: li.dataset.attKind, cls: li.dataset.cls, screen: li.dataset.screen, key: li.dataset.attKey,
                          text: li.textContent, href: (li.querySelector('a') || {}).getAttribute ? li.querySelector('a').getAttribute('href') : '' }))""")
        hit = [i for i in items if "capture came in short" in i["text"] and made["airline"] in i["text"]]
        if not hit:
            problems.append(f"Today's needs attention doesn't list {made['airline']}'s short page (it lists {len(items)} items)")
        elif hit[0]["kind"] != "capture" or hit[0]["screen"] != "systems" or hit[0]["cls"] != "warn" or "/systems" not in (hit[0]["href"] or ""):
            problems.append(f"the short page's item isn't an amber Capture item linking to Systems: {hit[0]}")
        cap = await ph.pg.evaluate("""(() => { const c = document.querySelector('[data-figure="today: capture"]') || { dataset: {} };
            return { state: c.dataset.captureState || '', mark: c.dataset.mark || '', text: c.textContent || '' }; })()""")
        if cap["state"] not in ("short", "broken", "missing") or cap["mark"] == "ok" or "short" not in cap["text"]:
            problems.append(f"Today's capture line doesn't say the capture came in short: {cap['state']!r}, {cap['mark']!r}")
        lines = await open_systems(ph)
        line = next((l for l in lines if l["key"] == f"capture|{made['airline_id']}"), None)
        if not line or line["mark"] != "warn" or "short" not in line["text"]:
            problems.append(f"the Systems board doesn't mark {made['airline']} amber for the short page: {line}")
        problems += ph.errors
    except Exception as e:
        problems.append(why(e))
    finally:
        await ph.close()
        if rid is not None:
            psql(f"delete from public.game_capture_raw where id = {rid}")
        if psql("select count(*) from public.game_capture_raw").strip() != before:
            problems.append("the copy's raw pages weren't put back as they were")
    return (f"a short page made on purpose: half of {made['airline'] if made else '?'}'s latest loads page ({made['read'] if made else '?'} flights) "
            f"is judged short ({(verdict or {}).get('note', '?')}), Today lists it in the Capture group linking to Systems and its capture line "
            f"says {cap.get('state', '?')}, the Systems board marks that airline amber; then put back"), problems


# ---------- 7. the addresses (the switch, the clean-up and 20 Oct) ----------
def answer(port, path):
    """What the local server (tests/harness.py, which follows web/_redirects as Cloudflare does) answers for an address,
    without following a redirect: (status, Location, body)."""
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
    try:
        c.request("GET", path)
        r = c.getresponse()
        return r.status, r.getheader("Location"), r.read()
    finally:
        c.close()


def built_links():
    """Where the built new planner (web/app/) still names the old planner's address or an address used while it was built."""
    bad = []
    for f in sorted((WEB / "app").rglob("*")):
        if f.is_file() and f.suffix in (".js", ".html", ".css"):
            text = f.read_text(errors="replace")
            bad += [f"{f.relative_to(WEB)} names {n}" for n in ("/planner/old", "/planner/next", "data-not-built") if n in text]
    return bad


# (address, status, what it gives: "new" the planner's page, else where it redirects to)
ADDRESSES = [
    ("/planner", 301, "/planner/"), ("/planner/", 200, "new"), ("/planner/performance/VS", 200, "new"),
    ("/planner/today", 200, "new"), ("/planner/systems", 200, "new"), ("/planner/routes/PA/JFK-ORD", 200, "new"),
    ("/planner/check", 301, "/planner/today"), ("/planner/check?day=2026-10-12", 301, "/planner/today?day=2026-10-12"),
    ("/planner/review", 301, "/planner/performance"), ("/planner/review/VS", 301, "/planner/performance/VS"),
    ("/planner/review/PA/JFK-ORD", 301, "/planner/performance/PA/JFK-ORD"),
    ("/planner/hubs", 301, "/planner/performance"), ("/planner/hubs/DEL", 301, "/planner/performance"),
    ("/planner/next", 301, "/planner/"), ("/planner/next/", 301, "/planner/"), ("/planner/next/routes", 301, "/planner/routes"),
    ("/planner/next/review/VS", 301, "/planner/review/VS"), ("/planner/next/tails?airline=PA", 301, "/planner/tails?airline=PA"),
    ("/planner/old", 301, "/planner/"), ("/planner/old/", 301, "/planner/"), ("/planner/old/index.html", 301, "/planner/"),
]


async def addresses(p, port, env, facts, staff, seen):
    problems = []
    new_page = PAGE.read_bytes()
    for path, code, what in ADDRESSES:
        status, loc, body = answer(port, path)
        if status != code:
            problems.append(f"{path} answers {status}{' to ' + loc if loc else ''}, not {code}{' to ' + what if code != 200 else ''}")
        elif code != 200 and loc != what:
            problems.append(f"{path} goes to {loc}, not {what}")
        elif what == "new" and body != new_page:
            problems.append(f"{path} isn't the planner's page (web/app/index.html)")
    problems += built_links()

    # the planner: signed in at an old deep address (Review's), the old Check and Hubs, Check's load report on a day, an
    # address from the build, then Home at /planner/
    pl = Planner(p, port, env, facts)
    seen.append(pl)
    try:
        await pl.open(path="/planner/review/VS")
        await pl.fill_sign_in(*staff)
        await pl.pg.wait_for_selector("main[data-screen=performance][data-performance-ready=yes]", timeout=90000)
        got = await pl.pg.evaluate("[location.pathname, document.querySelector('main[data-screen=performance]').dataset.airline]")
        if got != ["/planner/performance/VS", "VS"]:
            problems.append(f"/planner/review/VS, signed in there, shows {got[0]} on {got[1]!r}, not Virgin's Performance page")
        for old, sid, want in (("/planner/check", "today", "/planner/today"), ("/planner/hubs", "performance", "/planner/performance")):
            await pl.pg.goto(f"http://{LIVE_HOST}:{port}{old}")
            await pl.pg.wait_for_selector(READY[sid], timeout=90000)
            path = await pl.pg.evaluate("location.pathname")
            if path != want:
                problems.append(f"{old} ended at {path}, not {want}")
        day = psql("select (now() at time zone 'UTC')::date - 3").strip()
        await pl.pg.goto(f"http://{LIVE_HOST}:{port}/planner/check?day={day}")
        await pl.pg.wait_for_function(f"() => (document.querySelector('main[data-screen=performance]') || {{dataset: {{}}}}).dataset.day === {json.dumps(day)}", timeout=60000)
        at = await pl.pg.evaluate("location.pathname + location.search")
        if at != f"/planner/performance?day={day}":
            problems.append(f"/planner/check?day={day} ended at {at}, not Performance's Flights by day on that day")
        resp = await pl.pg.goto(f"http://{LIVE_HOST}:{port}/planner/next/routes")
        hop = resp.request.redirected_from if resp else None
        first = await hop.response() if hop else None
        if not first or first.status != 301:
            problems.append(f"/planner/next/routes didn't answer 301 ({first.status if first else 'no redirect'})")
        await pl.pg.wait_for_selector("main[data-screen=routes][data-routes-ready=yes]", timeout=60000)
        path = await pl.pg.evaluate("location.pathname")
        if path != "/planner/routes":
            problems.append(f"/planner/next/routes ended at {path}, not /planner/routes")
        await pl.pg.goto(f"http://{LIVE_HOST}:{port}{NEW_PLANNER}")
        await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=90000)
        await settle(pl.pg, 1000)
        problems += pl.errors
    except Exception as e:
        problems.append("the new planner: " + why(e))
    finally:
        await pl.close()

    return (f"the addresses: /planner/ and a deep address open the planner; /planner/check goes to Today (and with a day, on to "
            f"Performance's Flights by day), /planner/review/VS to Virgin's Performance page, /planner/hubs to Performance; "
            f"{sum(1 for a in ADDRESSES if '/next' in a[0])} /planner/next/ addresses answer 301 with the same address under /planner/; "
            f"{sum(1 for a in ADDRESSES if '/old' in a[0])} /planner/old addresses answer 301 to /planner/; the built planner has no link to either"), problems


async def main():
    facts = planner_facts()
    if not facts:
        step(False, "the new planner names its Supabase address and public key", [f"not found in {CONFIG.relative_to(ROOT)}"])
        sys.exit(1)
    if not PAGE.is_file():
        step(False, "the new planner is built", ["web/app/index.html is missing: run npm ci && npm run build first"])
        sys.exit(1)
    try:
        env = local_env()
    except Exception as e:
        step(False, "set up: the copy's address and keys", [why(e)])
        sys.exit(1)
    tag = secrets.token_hex(4)
    staff = (f"planner-next-staff-{tag}@example.com", secrets.token_urlsafe(18))
    other = (f"planner-next-other-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        make_user(env, *other)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    step(not problems, "test users: one staff, one not, made through the copy's sign-in", problems)
    if problems:
        sys.exit(1)

    seen = []
    with serve() as port:
        async with async_playwright() as p:
            pl = Planner(p, port, env, facts)
            seen.append(pl)
            try:
                label, problems = await sign_in_staff(pl, staff)
                signed_in = True
            except Exception as e:
                label, problems, signed_in = "sign in as test staff through the new planner's own form", [why(e)] + pl.errors[:3], False
            step(not problems, label, problems)
            label, problems = await refuse_other(p, port, env, facts, other, seen)
            step(not problems, label, problems)
            if signed_in:
                for check in (home_opens, today_opens, routes_opens, tails_opens, plan_card_cabins, no_hubs, performance_opens, route_page_opens, competition_opens,
                              systems_opens, last_screens_open, tick_todo):
                    e0 = len(pl.errors)
                    try:
                        label, problems = await check(pl)
                    except Exception as e:
                        label, problems = check.__name__.replace("_", " "), [why(e)]
                    step(not problems, label, problems + pl.errors[e0:])
            await pl.close()
            for check in (two_tabs, preview, screens, systems_board, short_page, addresses):
                try:
                    label, problems = await check(p, port, env, facts, staff, seen, *([moment()] if check in (screens, systems_board, short_page) else []))
                except Exception as e:
                    label, problems = check.__name__.replace("_", " "), [why(e)]
                step(not problems, label, problems)

    outside = sorted({h for x in seen for h in x.outside})
    stopped = ", ".join(sorted({h for x in seen for h in x.stopped})) or "nothing"
    problems = (["reached: " + ", ".join(outside)] if outside else []) + ([] if pl.copy else ["the planner never reached the copy"])
    step(not problems, f"nothing went outside ({sum(x.copy for x in seen)} requests answered by the copy, {sum(x.local for x in seen)} "
                       f"from the local server; stopped: {stopped})", problems)
    print(f"\n{len(failures)} new-planner step(s) failed" if failures else "\nnew planner: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
