"""The new planner on the rehearsal's copy (decision #18, build pull request 1, spec §7): the pull request's own new
planner, built into web/app/, at its live address (/planner/next/), signed in as test staff, reading from and saving
into a full local copy of Supabase restored from last night's backup, with the tables read back afterwards.

Run by database/rehearse.sh after the restore, the pending changes and the SQL tests have passed, and after it has built
the new planner (npm ci, npm run build). Like tests/real_saves_test.py, whose helpers it uses, it needs that copy, so it
isn't part of tests/run_all.sh. Same test users (made here through the copy's sign-in, one staff and one not), same
request mapping (the live Supabase address answered by the copy, its public key swapped for the copy's), and the same
rule: nothing goes outside.

1. Sign-in through the new planner's own form, as staff; the account that isn't staff is refused and signed out, with
   the old planner's message; opening the planner writes nothing (no change_log row, no table's row count changes).
2. Home (build pull request 5) is no longer a placeholder: it opens with its boards (key figures, the network, needs
   attention, coming up, the to-do board) and our airlines (our group's, in their position order, with their colours)
   on the network's buttons. tests/home_side_by_side_test.py compares its figures with the old Home's. Routes (build
   pull request 6) is no longer a placeholder either: it opens on its list, with our airlines on its buttons in their
   order; tests/routes_side_by_side_test.py compares it with the old Routes.
3. window.__eqPlanner.save() ticks the first open to-do: exactly that row changes (done, done_at), logged as actor
   planner with the tab's ID; the answer gives the row's new updated_at. A second save from that updated_at puts it
   back, so the next change needs no new read and the real saves that follow still find their open to-dos.
4. Two tabs read the same to-do; the first changes its title; the second's change to that row comes back as a clash
   carrying the first's title, and the second's change to another row in the same call isn't written either. The
   second tab shows the row as it is now and names it.
5. A preview address (127.0.0.1) reads, says "preview · not saved", and sends no write.
6. At 380 px wide, Home, Routes and the seven placeholder screens have no sideways scroll and no errors.
7. Nothing went outside: no request reached the live Supabase host or any address but the local server and the copy.

Prints one line per step (ok/FAIL), and nothing from the rows beyond ids, counts and the names of changed fields, since
the log is posted on the pull request. Never prints the local keys or the test passwords.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV (a file holding `supabase status -o env`), LOCAL_DB_URL and
SECRET_TABLES. Usage: python3 tests/planner_next_test.py
"""
import asyncio, datetime, json, re, secrets, sys
from urllib.parse import urlsplit
from harness import ROOT, WEB, LIVE_HOST, serve, settle
from playwright.async_api import async_playwright
from real_saves_test import (count_changes, counts, is_planner_user, jobs_since, local_env, log_since, make_user, marks,
                             psql, token_for, why)

CONFIG = ROOT / "app" / "planner" / "src" / "data" / "config.ts"
PAGE = WEB / "app" / "index.html"
SCREENS = [("home", "/planner/next/"), ("routes", "/planner/next/routes"), ("tails", "/planner/next/tails"),
           ("hubs", "/planner/next/hubs"), ("check", "/planner/next/check"), ("review", "/planner/next/review"),
           ("interline", "/planner/next/interline"), ("photos", "/planner/next/photos"), ("reference", "/planner/next/reference")]
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

    async def open(self, host=LIVE_HOST, path="/planner/next/", moment=None):
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
        if "planner_save" in pv.rpcs:
            problems.append("the preview sent planner_save() to the copy")
        if log_since(mark):
            problems.append("the tables changed")
        problems += count_changes(n0, counts()) + pv.errors
    finally:
        await pv.close()
    return f"a preview address reads (Home shown) and sends no write (it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})", problems


# ---------- 6. a phone ----------
async def phone(p, port, env, facts, staff, seen):
    ph = Planner(p, port, env, facts, width=380, height=800)
    seen.append(ph)
    problems = []
    scroll = "(() => Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth)()"
    try:
        await ph.open()
        await ph.sign_in(*staff)
        for sid, href in SCREENS:
            e0 = len(ph.errors)
            await ph.pg.click(f"[data-screen-link={sid}]")
            await ph.pg.wait_for_selector(f"main[data-screen={sid}]", timeout=15000)
            await settle(ph.pg, 300)
            path = await ph.pg.evaluate("location.pathname")
            if path != href:
                problems.append(f"{sid}: its address is {path}, expected {href}")
            built = sid in ("home", "routes")   # rebuilt (build pull requests 5 and 6); the other seven are still placeholders
            ready = {"home": "main[data-screen=home][data-home-ready=yes]", "routes": "main[data-screen=routes][data-routes-ready=yes]"}
            if built:
                try:
                    await ph.pg.wait_for_selector(ready[sid], timeout=60000)
                    await settle(ph.pg, 300)
                except Exception:
                    problems.append(f"{sid}: it isn't ready at 380 px wide")
            if not built and not await ph.pg.evaluate("!!document.querySelector('[data-not-built] a[href=\"/planner/\"]')"):
                problems.append(f"{sid}: no line linking to the old planner")
            over = await ph.pg.evaluate(scroll)
            if over > 0:
                problems.append(f"{sid}: the page scrolls sideways by {over} px at 380 px wide")
            problems += [f"{sid}: {e}" for e in ph.errors[e0:]]
        await ph.pg.goto(f"http://{LIVE_HOST}:{port}/planner/next/review/VS")
        await ph.pg.wait_for_selector("main[data-screen=review]", timeout=30000)
        if await ph.pg.evaluate(scroll) > 0:
            problems.append("review/VS, opened directly, scrolls sideways")
        problems += ph.errors
    finally:
        await ph.close()
    return f"at 380 px wide, Home, Routes and the {len(SCREENS) - 2} placeholder screens have no sideways scroll and no errors", problems


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
                for check in (home_opens, routes_opens, tick_todo):
                    e0 = len(pl.errors)
                    try:
                        label, problems = await check(pl)
                    except Exception as e:
                        label, problems = check.__name__.replace("_", " "), [why(e)]
                    step(not problems, label, problems + pl.errors[e0:])
            await pl.close()
            for check in (two_tabs, preview, phone):
                try:
                    label, problems = await check(p, port, env, facts, staff, seen)
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
