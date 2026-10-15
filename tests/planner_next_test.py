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
2. Every screen has its boards: Home (key figures, the network, needs attention, coming up, the to-do board, our
   airlines in their position order and colours on the network's buttons); Routes on its list, with our airlines on its
   buttons in their order; Tails, its list and the deliveries board; Hubs on the first base's board with every base in
   its list; Check, its six boards, folded, in the old order, with the copy's airlines on the Capture board, and five
   (no Aircraft checks) with the one-week checks off; Review, the
   cards for the copy's airlines in their order and the first one's page; Interline with its agreements and the
   interline countries, Photos with a logo for each of our airlines, Reference with its sections folded. The header has
   the search box and the Website button. (Each screen was compared with the old planner's by a side by side until the
   clean-up, build pull request 14; tests/planner_saves_test.py now checks every kind of save against recorded rows.)
3. window.__eqPlanner.save() ticks the first open to-do: exactly that row changes (done, done_at), logged as actor
   planner with the tab's ID; the answer gives the row's new updated_at. A second save from that updated_at puts it
   back, so the next change needs no new read and the real saves that follow still find their open to-dos.
4. Two tabs read the same to-do; the first changes its title; the second's change to that row comes back as a clash
   carrying the first's title, and the second's change to another row in the same call isn't written either. The
   second tab shows the row as it is now and names it.
5. A preview address (127.0.0.1) reads, says "preview · not saved", sends no write, and its notice links to the live
   planner at /planner/.
6. Every screen opens at the frozen moment (the copy's latest capture plus one hour), at 1280 and 380 px wide: ready,
   no errors, no sideways scroll (Check and Review with every board open, Reference with every section open) and no
   link into the old planner's address (/planner/old/) or one used while the planner was built (/planner/next/); a
   screenshot of each at each width goes to PLANNER_SCREENS_DIR (the run's planner-screens artifact), when it's set.
6b. Check's Systems board (#23) at the frozen moment: the first board on Check, a line for each of our airlines' evening
   capture and one each for the snapshot, backup, archive, clean-ups, world scan, the planner's build (stamped) and the
   three usage figures, every one marked green, amber or red (printed). Then a short page made on purpose (#21): half of
   an airline's latest loads page, stored just after the latest capture and judged short, is listed on Home's needs
   attention in the Capture group linking to Check, and marks that airline amber on the board; then it is deleted.
7. The addresses (the switch, build pull request 13, and the clean-up, 14), as tests/harness.py serves them from
   web/_redirects the way Cloudflare does: /planner and /planner/ open the planner, and so does a deep address
   (/planner/review/VS, signed in there, shows Virgin's Review); every /planner/next/... address answers 301 with the same
   address under /planner/ (/planner/next/routes opens Routes at /planner/routes); /planner/old and everything under it
   answer 301 to /planner/ (the old planner is gone); the built planner (web/app/) has no link to /planner/old/ or
   /planner/next/.
8. Nothing went outside: no request reached the live Supabase host or any address but the local server and the copy.

Prints one line per step (ok/FAIL), and nothing from the rows beyond ids, counts and the names of changed fields, since
the log is posted on the pull request. Never prints the local keys or the test passwords.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV (a file holding `supabase status -o env`), LOCAL_DB_URL,
SECRET_TABLES and PLANNER_SCREENS_DIR. Usage: python3 tests/planner_next_test.py
"""
import asyncio, datetime, http.client, json, os, re, secrets, sys
from pathlib import Path
from urllib.parse import urlsplit
from harness import ROOT, WEB, LIVE_HOST, NEW_PLANNER, serve, settle
from playwright.async_api import async_playwright
from local_copy import (count_changes, counts, is_planner_user, jobs_since, local_env, log_since, make_user, marks, moment, ms, one, psql,
                        put_back_check_days, set_check_days, token_for, why)

CONFIG = ROOT / "app" / "planner" / "src" / "data" / "config.ts"
PAGE = WEB / "app" / "index.html"
SCREENS = [("home", "/planner/"), ("routes", "/planner/routes"), ("tails", "/planner/tails"),
           ("hubs", "/planner/hubs"), ("check", "/planner/check"), ("review", "/planner/review"),
           ("interline", "/planner/interline"), ("photos", "/planner/photos"), ("reference", "/planner/reference")]
SCREENS_DIR = os.environ.get("PLANNER_SCREENS_DIR")
# A link into the old planner, or to an address used while the new one was built (the switch: none may be left)
OLD_LINK = re.compile(r"^(https?://[^/]+)?/planner/(old|next)(/|$|\?|#)")
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


# ---------- 2. Home ----------
async def home_opens(pl):
    """Home is rebuilt (build pull request 5): no placeholder, its boards there (the hero, the map, needs attention,
    coming up, the to-do board, a card for each of our airlines) and the game clocks under the header, our airlines on
    the map's buttons in their order, with their colours. Its figures are compared with the old Home's by
    tests/home_side_by_side_test.py."""
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
        cards: document.querySelectorAll('.agrid .acard').length, clocks: document.querySelectorAll('#clocks .zc').length })""")
    problems = []
    if boards["notBuilt"]:
        problems.append("Home still shows the placeholder's line to the old planner")
    if boards["figures"] != 5:
        problems.append(f"{boards['figures']} key figure(s), expected 5")
    problems += [f"no {k} board" for k in ("network", "attention", "comingUp", "todo", "hero") if not boards[k]]
    if not boards["clocks"]:
        problems.append("no game clocks under the header")
    if not want:
        problems.append("the copy has none of our airlines")
    if [a["name"] for a in got] != [a["name"] for a in want]:
        problems.append(f"airlines on the network's buttons {[a['name'] for a in got]}, the copy has {[a['name'] for a in want]}")
    elif [a["color"].lower() for a in got] != [a["color"].lower() for a in want]:
        problems.append("an airline's colour isn't the copy's: " + ", ".join(g["name"] for g, w in zip(got, want) if g["color"].lower() != w["color"].lower()))
    if boards["cards"] != len(want):
        problems.append(f"{boards['cards']} airline card(s), the copy has {len(want)} of our airlines")
    return (f"Home is rebuilt, not a placeholder: the hero, its key figures, the map, needs attention, coming up, the to-do board and "
            f"the airline cards, with the copy's {len(want)} airlines in their order and colours, and the game clocks ({boards['clocks']} time zones)"), problems


async def routes_opens(pl):
    """Routes is rebuilt (build pull request 6): no placeholder; it opens on its list (the first airline's routes with
    its first base picked) with our airlines on its buttons in their order. Its figures are compared with the old
    Routes' by tests/routes_side_by_side_test.py."""
    want = [r for r in psql(f"""select a.iata_code from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                 where g.kind = 'ours' and a.world_id = {WORLD} order by a.position nulls last, a.id""").splitlines() if r]
    await pl.pg.click("[data-screen-link=routes]")
    await pl.pg.wait_for_selector("main[data-screen=routes][data-routes-ready=yes]", timeout=60000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate("""({ notBuilt: !!document.querySelector('main[data-screen=routes] [data-not-built]'),
        airlines: [...document.querySelectorAll('.toolbar .seg [data-al]')].map(b => b.dataset.al),
        rows: document.querySelectorAll('#routelist .row').length, count: (document.querySelector('.toolbar .count') || {}).textContent || '' })""")
    problems = []
    if got["notBuilt"]:
        problems.append("Routes still shows the placeholder's line to the old planner")
    if got["airlines"] != want:
        problems.append(f"airlines on Routes' buttons {got['airlines']}, the copy has {want}")
    if not got["rows"]:
        problems.append("Routes lists no route")
    await pl.pg.click("[data-screen-link=home]")
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return f"Routes is rebuilt, not a placeholder: it opens on its list ({got['count']}) with the copy's {len(want)} airlines on its buttons in their order", problems


async def tails_opens(pl):
    """Tails is rebuilt (build pull request 7): no placeholder; it opens on its list (the first airline's aircraft in
    service) and the deliveries board, with our airlines on its buttons in their order. Its figures are compared with the
    old Tails' by tests/tails_side_by_side_test.py."""
    want = [r for r in psql(f"""select a.iata_code from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                 where g.kind = 'ours' and a.world_id = {WORLD} order by a.position nulls last, a.id""").splitlines() if r]
    await pl.pg.click("[data-screen-link=tails]")
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
    await pl.pg.click("[data-screen-link=home]")
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return f"Tails is rebuilt, not a placeholder: it opens on its list ({got['count']}) and the deliveries, with the copy's {len(want)} airlines on its buttons", problems


async def hubs_opens(pl):
    """Hubs is rebuilt (build pull request 8): no placeholder; it opens on the first base's board (its count line, the day
    strip, the week grid, the flight list and the connections), with every base and focus city in its list in the bases'
    order. Its figures are compared with the old Hubs' by tests/hubs_side_by_side_test.py."""
    want = list(dict.fromkeys(r for r in psql(f"""select b.airport_code from public.airline_bases b where b.world_id = {WORLD}
                                                order by b.position nulls last, b.id""").splitlines() if r))
    await pl.pg.click("[data-screen-link=hubs]")
    await pl.pg.wait_for_selector("main[data-screen=hubs][data-hubs-ready=yes]", timeout=60000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate("""({ notBuilt: !!document.querySelector('main[data-screen=hubs] [data-not-built]'),
        bases: [...document.querySelectorAll('#h-hub option')].map(o => o.value), hub: document.querySelector('main[data-screen=hubs]').dataset.hub,
        count: (document.querySelector('[data-figure="hubs: count"]') || {}).textContent || '',
        boards: ['hubs: day strip', 'hubs: hours', 'hubs: week', 'hubs: flights', 'hubs: connections']
          .filter(f => !document.querySelector('[data-figure="' + f + '"]')) })""")
    problems = []
    if got["notBuilt"]:
        problems.append("Hubs still shows the placeholder's line to the old planner")
    if got["bases"] != want:
        problems.append(f"bases in Hubs' list {got['bases']}, the copy has {want}")
    if want and got["hub"] != want[0]:
        problems.append(f"Hubs opens on {got['hub']!r}, not the first base {want[0]}")
    if not got["count"]:
        problems.append("Hubs shows no count line")
    if got["boards"]:
        problems.append(f"Hubs is missing {', '.join(got['boards'])}")
    await pl.pg.click("[data-screen-link=home]")
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return f"Hubs is rebuilt, not a placeholder: it opens on {got['hub']}'s board ({got['count']}), with the copy's {len(want)} bases in its list", problems


async def check_opens(pl):
    """Check is rebuilt (build pull request 9): no placeholder; it opens with its six boards in the old Check's order, every
    one folded (the old Check folded them all on arrival), and the Capture board lists our airlines the capture covers, in
    their order. Its figures are compared with the old Check's by tests/check_side_by_side_test.py. With the one-week
    checks off (aircraft_check_after_days 0, set by the test), it has five: no Aircraft checks."""
    want = [r for r in psql(f"""select coalesce(a.planner_name, a.public_name, a.game_name) from public.airlines a
                                join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                where g.kind = 'ours' and a.world_id = {WORLD}
                                order by a.position nulls last, a.id""").splitlines() if r]
    await pl.pg.click("[data-screen-link=check]")
    await pl.pg.wait_for_selector("main[data-screen=check][data-check-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate("""({ notBuilt: !!document.querySelector('main[data-screen=check] [data-not-built]'),
        boards: [...document.querySelectorAll('main[data-screen=check] .board:not(.sysboard) > h3.rh')].map(h => h.dataset.rkey),
        folded: [...document.querySelectorAll('main[data-screen=check] .board:not(.sysboard)')].every(b => b.classList.contains('rcol')),
        capture: [...document.querySelectorAll('[data-figure="check: capture table"] tr')].slice(1).map(tr => (tr.querySelector('td b') || {}).textContent || '') })""")
    problems = []
    if got["notBuilt"]:
        problems.append("Check still shows the placeholder's line to the old planner")
    order = ["Capture", "Growth", "Aircraft checks", "Cabins", "Game check", "Daily load report"]
    if got["boards"] != order:
        problems.append(f"Check's boards are {got['boards']}, not {order}")
    if not got["folded"]:
        problems.append("Check's boards aren't all folded on arrival")
    if not got["capture"] or any(n not in want for n in got["capture"]) or got["capture"] != sorted(got["capture"], key=want.index):
        problems.append(f"the Capture board lists {got['capture']}, the copy's airlines are {want}")
    # the checks off (aircraft_check_after_days 0, spec docs/specs/2026-10-15-aircraft-checks-off.md): five boards, no
    # Aircraft checks; then on again (7), as main() set them
    set_check_days(0)
    try:
        await pl.pg.reload()
        await pl.pg.wait_for_selector("main[data-screen=check][data-check-ready=yes]", timeout=90000)
        await settle(pl.pg, 300)
        off = await pl.pg.evaluate("[...document.querySelectorAll('main[data-screen=check] .board:not(.sysboard) > h3.rh')].map(h => h.dataset.rkey)")
    finally:
        set_check_days(7)
    if off != [k for k in order if k != "Aircraft checks"]:
        problems.append(f"with the checks off (0), Check's boards are {off}, not the five without Aircraft checks")
    await pl.pg.reload()
    await pl.pg.wait_for_selector("main[data-screen=check][data-check-ready=yes]", timeout=90000)
    await pl.pg.click("[data-screen-link=home]")
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return (f"Check is rebuilt, not a placeholder: its {len(got['boards'])} boards in the old order, folded on arrival, the Capture board with "
            f"{len(got['capture'])} airlines; with the checks off, {len(off)} boards and no Aircraft checks"), problems


async def review_opens(pl):
    """Review is rebuilt (build pull request 10): no placeholder; it opens with a card for each of our airlines the captured
    figures cover, in their order, and the first one's page (its boards folded on arrival, as Check's). Its figures are
    compared with the old Review's by tests/review_side_by_side_test.py."""
    want = [r for r in psql(f"""select coalesce(a.planner_name, a.public_name, a.game_name) from public.airlines a
                                join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                where g.kind = 'ours' and a.world_id = {WORLD} and a.active
                                order by a.position nulls last, a.id""").splitlines() if r]
    await pl.pg.click("[data-screen-link=review]")
    await pl.pg.wait_for_selector("main[data-screen=review][data-review-ready=yes]", timeout=90000)
    await settle(pl.pg, 300)
    got = await pl.pg.evaluate("""({ notBuilt: !!document.querySelector('main[data-screen=review] [data-not-built]'),
        cards: [...document.querySelectorAll('main[data-screen=review] .fcard .fch b')].map(b => b.textContent),
        on: (document.querySelector('main[data-screen=review] .fcard.on .fch b') || {}).textContent || '',
        boards: [...document.querySelectorAll('main[data-screen=review] .board > h3.rh')].map(h => h.dataset.rkey),
        folded: [...document.querySelectorAll('main[data-screen=review] .board')].every(b => b.classList.contains('rcol')) })""")
    problems = []
    if got["notBuilt"]:
        problems.append("Review still shows the placeholder's line to the old planner")
    if got["cards"] != want:
        problems.append(f"Review's cards are {got['cards']}, the copy's airlines are {want}")
    if want and got["on"] != want[0]:
        problems.append(f"Review opens on {got['on']!r}, not the first airline {want[0]!r}")
    page = [b for b in got["boards"] if b != "The group today"]
    if page != ["Profit", "Cash, next 14 days", "Route profit", "Fare plan", "Manual entry"]:
        problems.append(f"Review's boards are {got['boards']}")
    if not got["folded"]:
        problems.append("Review's boards aren't all folded on arrival")
    await pl.pg.click("[data-screen-link=home]")
    await pl.pg.wait_for_selector("main[data-screen=home][data-home-ready=yes]", timeout=60000)
    return f"Review is rebuilt, not a placeholder: a card for each of the copy's {len(got['cards'])} airlines in order, the first one's page with its {len(got['boards'])} boards, folded on arrival", problems


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
        await pl.pg.click(f"[data-screen-link={sid}]")
        await pl.pg.wait_for_selector(f"main[data-screen={sid}][{ready}=yes]", timeout=90000)
        await settle(pl.pg, 300)
        if await pl.pg.evaluate(f"!!document.querySelector('main[data-screen={sid}] [data-not-built]')"):
            problems.append(f"{sid} still shows the placeholder's line to the old planner")
    await pl.pg.click("[data-screen-link=interline]")
    await pl.pg.wait_for_selector("main[data-screen=interline][data-interline-ready=yes]", timeout=60000)
    il = await pl.pg.evaluate("""({ boards: !!document.querySelector('[data-figure="interline: agreements"]') && !!document.querySelector('[data-figure="interline: countries"]'),
        countries: document.querySelectorAll('[data-figure="interline: countries"] tr').length - 1 })""")
    if not il["boards"] or il["countries"] < 1:
        problems.append(f"Interline has no agreements board or interline countries ({il})")
    seen.append(f"Interline with {il['countries']} interline countries")
    await pl.pg.click("[data-screen-link=photos]")
    await pl.pg.wait_for_selector("main[data-screen=photos][data-photos-ready=yes]", timeout=60000)
    logos = await pl.pg.evaluate("[...document.querySelectorAll('main[data-screen=photos] [data-lg]')].map(c => c.dataset.lg)")
    if logos != want:
        problems.append(f"Photos' logos are for {logos}, the copy's airlines are {want}")
    seen.append(f"Photos with {len(logos)} logos")
    await pl.pg.click("[data-screen-link=reference]")
    await pl.pg.wait_for_selector("main[data-screen=reference][data-reference-ready=yes]", timeout=60000)
    ref = await pl.pg.evaluate("""({ sections: [...document.querySelectorAll('main[data-screen=reference] details.rsec')].map(d => d.dataset.section),
        open: [...document.querySelectorAll('main[data-screen=reference] details.rsec')].filter(d => d.open).length })""")
    if ref["open"] or len(ref["sections"]) < 11:
        problems.append(f"Reference's sections {ref['sections']}, {ref['open']} open on arrival (all should be folded)")
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", "/reference/constants")
    await pl.pg.wait_for_function("() => (document.querySelector('details.rsec[data-section=constants]') || {}).open === true", timeout=30000)
    seen.append(f"Reference with {len(ref['sections'])} sections, folded, /reference/constants opening Constants")
    await pl.pg.click("[data-screen-link=home]")
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
READY = {"home": "main[data-screen=home][data-home-ready=yes]", "routes": "main[data-screen=routes][data-routes-ready=yes]",
         "tails": "main[data-screen=tails][data-tails-ready=yes]", "hubs": "main[data-screen=hubs][data-hubs-ready=yes]",
         "check": "main[data-screen=check][data-check-ready=yes]", "review": "main[data-screen=review][data-review-ready=yes]",
         "interline": "main[data-screen=interline][data-interline-ready=yes]", "photos": "main[data-screen=photos][data-photos-ready=yes]",
         "reference": "main[data-screen=reference][data-reference-ready=yes]"}


async def screens(p, port, env, facts, staff, seen, moment):
    """Every screen opens on the copy at the frozen moment (the copy's latest capture plus one hour), signed in as test
    staff, at 1280 and at 380 px wide: ready (it has read everything), no errors, no sideways scroll (Check and Review with
    every board open, Reference with every section open), and no link into the old planner or to /planner/next/. With
    PLANNER_SCREENS_DIR set, a screenshot of each at each width goes there (the run's planner-screens artifact). What
    replaced the side by sides' screen checks (build pull request 14)."""
    problems = []
    scroll = "(() => Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth)()"
    links = shots = 0
    if SCREENS_DIR:
        Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    for width, height in ((1280, 900), (380, 800)):
        ph = Planner(p, port, env, facts, width=width, height=height)
        seen.append(ph)
        try:
            await ph.open(moment=moment)
            await ph.pg.emulate_media(reduced_motion="reduce")   # the globe holds still, so two screenshots of a moment are the same
            await ph.sign_in(*staff)
            if abs(await ph.pg.evaluate("Date.now()") - ms(moment)) > 1000:
                problems.append(f"{width} px: the planner's clock isn't frozen at the moment")
            for sid, href in SCREENS:
                e0 = len(ph.errors)
                await ph.pg.click(f"[data-screen-link={sid}]")
                await ph.pg.wait_for_selector(f"main[data-screen={sid}]", timeout=15000)
                path = await ph.pg.evaluate("location.pathname")
                if path != href:
                    problems.append(f"{sid}: its address is {path}, expected {href}")
                try:
                    await ph.pg.wait_for_selector(READY[sid], timeout=90000)
                    await settle(ph.pg, 400)
                except Exception:
                    problems.append(f"{sid}: it isn't ready at {width} px wide")
                if sid in ("check", "review"):
                    await ph.pg.click("#rev-expall")   # every board open: the widest the screen gets
                    await settle(ph.pg, 300)
                if sid == "reference":
                    await ph.pg.evaluate("document.querySelectorAll('main[data-screen=reference] details.rsec').forEach(d => { d.open = true; })")
                    await settle(ph.pg, 400)
                over = await ph.pg.evaluate(scroll)
                if over > 0:
                    problems.append(f"{sid}: the page scrolls sideways by {over} px at {width} px wide")
                hrefs = await ph.pg.evaluate("[...document.querySelectorAll('a[href]')].map(a => a.getAttribute('href'))")
                links += len(hrefs)
                problems += [f"{sid}: a link to {h}" for h in hrefs if OLD_LINK.match(h or "")]
                problems += [f"{sid} at {width} px: {e}" for e in ph.errors[e0:]]
                if SCREENS_DIR:
                    await ph.pg.screenshot(path=str(Path(SCREENS_DIR) / f"{sid}-{width}.png"), full_page=True, timeout=90000)
                    shots += 1
            if width == 380:
                await ph.pg.goto(f"http://{LIVE_HOST}:{port}/planner/review/VS")
                await ph.pg.wait_for_selector(READY["review"], timeout=90000)
                await ph.pg.click("#rev-expall")
                await settle(ph.pg, 300)
                if await ph.pg.evaluate(scroll) > 0:
                    problems.append("review/VS, opened directly, scrolls sideways at 380 px")
            problems += [e for e in ph.errors if not any(e in x for x in problems)]
        finally:
            await ph.close()
    return (f"every screen ({len(SCREENS)}) opens on the copy at the moment ({moment}), at 1280 and 380 px wide: ready, no errors, no sideways "
            f"scroll (Check and Review with every board open, Reference with every section open), and none of their {links} links goes into "
            f"the old planner or to /planner/next/" + (f"; {shots} screenshots kept" if shots else "")), problems


# ---------- 6b. Check's Systems board, and a short page on Home (decisions #21, #23) ----------
SYS_FIXED = ["snapshot", "backup", "archive", "cleanup", "scan", "build", "usage|database", "usage|report_pdfs", "usage|site_public"]
SYS_LINES = """[...document.querySelectorAll('[data-figure="check: systems"] .sysline')].map(li => ({ key: li.dataset.sys, mark: li.dataset.mark,
    label: (li.querySelector('.syslabel') || {}).textContent || '', when: (li.querySelector('.syswhen') || {}).textContent || '',
    text: (li.querySelector('.systext') || {}).textContent || '', dot: !!li.querySelector('.sysmark.' + li.dataset.mark) }))"""


async def open_check(ph):
    await ph.pg.click("[data-screen-link=check]")
    await ph.pg.wait_for_selector(READY["check"], timeout=90000)
    await settle(ph.pg, 400)
    return await ph.pg.evaluate(SYS_LINES)


async def systems_board(p, port, env, facts, staff, seen, moment):
    """Check's Systems board (#23) on the copy at the frozen moment: at the top of Check, open, one line for each of our
    airlines' evening capture and one each for the snapshot, the backup, the archive, the clean-ups, the world scan, the
    planner's build (stamped by the build) and the three usage figures, every one with a green, amber or red mark. The
    lines and their marks are printed (names, marks, dates and sizes only)."""
    problems = []
    ids = [int(r) for r in psql(f"""select al.airline_id from private.fig_airlines({WORLD}) al where al.home_code is not null order by al.ord""").split() if r]
    ph = Planner(p, port, env, facts)
    seen.append(ph)
    try:
        await ph.open(moment=moment)
        await ph.sign_in(*staff)
        lines = await open_check(ph)
        first = await ph.pg.evaluate("(document.querySelector('main[data-screen=check] .board') || {}).id || ''")
        if first != "systems":
            problems.append(f"the Systems board isn't Check's first board (the first is {first or 'none'})")
        want = [f"capture|{i}" for i in ids] + SYS_FIXED
        if [l["key"] for l in lines] != want:
            problems.append(f"the board's lines are {[l['key'] for l in lines]}, expected {want}")
        problems += [f"{l['label'] or l['key']}: no mark ({l['mark']!r})" for l in lines if l["mark"] not in ("ok", "warn", "bad") or not l["dot"]]
        build = next((l for l in lines if l["key"] == "build"), None)
        if build and build["mark"] != "ok":
            problems.append("the planner's build line has no stamp: " + build["text"])
        problems += ph.errors
    finally:
        await ph.close()
    words = {"ok": "green", "warn": "amber", "bad": "red"}
    shown = "; ".join(f"{l['label']}: {words.get(l['mark'], l['mark'])}" + (f", {l['when']}" if l["when"] else "") + f" ({l['text'][:90]})" for l in lines)
    return f"Check's Systems board on the copy at {moment}: {len(lines)} lines, each marked: {shown}", problems


async def short_page(p, port, env, facts, staff, seen, moment):
    """A short page made on purpose (#21), then put back: half of an airline's latest loads page, stored just after the
    copy's latest capture and judged by private.capture_check() against what the copy expects of it, is short; Home's
    needs attention lists it in the Capture group linking to Check, and Check's board marks that airline amber. The page
    is deleted afterwards, and the copy's raw pages are as they were."""
    problems = []
    before = psql("select count(*) from public.game_capture_raw").strip()
    rid = made = verdict = None
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
        items = await ph.pg.evaluate("""[...document.querySelectorAll('[data-figure="home: needs attention"] [data-att-item]')]
            .map(li => ({ kind: li.dataset.attKind, cls: li.dataset.cls, screen: li.dataset.screen, key: li.dataset.attKey,
                          text: li.textContent, href: (li.querySelector('a') || {}).getAttribute ? li.querySelector('a').getAttribute('href') : '' }))""")
        hit = [i for i in items if "capture came in short" in i["text"] and made["airline"] in i["text"]]
        if not hit:
            problems.append(f"Home's needs attention doesn't list {made['airline']}'s short page (it lists {len(items)} items)")
        elif hit[0]["kind"] != "capture" or hit[0]["screen"] != "check" or hit[0]["cls"] != "warn" or "/check" not in (hit[0]["href"] or ""):
            problems.append(f"the short page's item isn't an amber Capture item linking to Check: {hit[0]}")
        lines = await open_check(ph)
        line = next((l for l in lines if l["key"] == f"capture|{made['airline_id']}"), None)
        if not line or line["mark"] != "warn" or "short" not in line["text"]:
            problems.append(f"Check's board doesn't mark {made['airline']} amber for the short page: {line}")
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
            f"is judged short ({(verdict or {}).get('note', '?')}), Home lists it in the Capture group linking to Check, "
            f"Check's board marks that airline amber; then put back"), problems


# ---------- 7. the addresses (the switch) ----------
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
    ("/planner", 301, "/planner/"), ("/planner/", 200, "new"), ("/planner/review/VS", 200, "new"),
    ("/planner/routes/PA/JFK-ORD", 200, "new"),
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

    # the new planner: signed in at a deep address, an address from the build, then Home at /planner/
    pl = Planner(p, port, env, facts)
    seen.append(pl)
    try:
        await pl.open(path="/planner/review/VS")
        await pl.fill_sign_in(*staff)
        await pl.pg.wait_for_selector("main[data-screen=review][data-review-ready=yes]", timeout=90000)
        got = await pl.pg.evaluate("[location.pathname, document.querySelector('main[data-screen=review]').dataset.airline]")
        if got != ["/planner/review/VS", "VS"]:
            problems.append(f"/planner/review/VS, signed in there, shows {got[0]} on {got[1]!r}")
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

    return (f"the addresses: /planner/ and a deep address open the planner; {sum(1 for a in ADDRESSES if '/next' in a[0])} "
            f"/planner/next/ addresses answer 301 with the same address under /planner/; {sum(1 for a in ADDRESSES if '/old' in a[0])} "
            f"/planner/old addresses answer 301 to /planner/; the built planner has no link to either"), problems


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
        # the one-week checks on (7) whatever last night's backup holds; put back at the end
        checks_were = set_check_days(7)
    except Exception as e:
        problems = [why(e)]
    step(not problems, "test users: one staff, one not, made through the copy's sign-in; the one-week checks on (7, set by the test)", problems)
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
                for check in (home_opens, routes_opens, tails_opens, hubs_opens, check_opens, review_opens, last_screens_open, tick_todo):
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
    put_back_check_days(checks_were)

    outside = sorted({h for x in seen for h in x.outside})
    stopped = ", ".join(sorted({h for x in seen for h in x.stopped})) or "nothing"
    problems = (["reached: " + ", ".join(outside)] if outside else []) + ([] if pl.copy else ["the planner never reached the copy"])
    step(not problems, f"nothing went outside ({sum(x.copy for x in seen)} requests answered by the copy, {sum(x.local for x in seen)} "
                       f"from the local server; stopped: {stopped})", problems)
    print(f"\n{len(failures)} new-planner step(s) failed" if failures else "\nnew planner: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
