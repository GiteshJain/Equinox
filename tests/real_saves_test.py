"""Real saves (decision #17): the pull request's own planner, signed in as a test staff user, saves for real into a full
local copy of Supabase restored from last night's backup, and the tables are read back afterwards.

Run by database/rehearse.sh, once the restore, the pending changes and the SQL tests have passed. It needs that copy
(Docker and the backup), so it isn't part of tests/run_all.sh. Since the switch-over (#13, pull request 9) the planner
reads and saves the tables through the adapter, and it runs in one of two phases (REAL_SAVES_PHASE):
  - after (the default): on the copy with every pending change, this pull request's included;
  - before: on the copy with only the changes live already has. Cloudflare publishes the planner when a pull request is
    merged and its migration is applied afterwards, so the new planner must also save into the database as it is until
    then (the rehearsal's pass 0, when a pull request changes both).

1. Test users: two accounts made through the local sign-in's admin API, with throwaway passwords made here: one added
   to planner_users (staff), one not. They exist only in the copy.
2. The planner opens at its live address (mapped to a local server, as tests/harness.py does), so it saves. Every
   request for the live Supabase host is answered by the local copy instead, with the live public key swapped for the
   local one. The planner's Supabase library, the exact version it names, comes from npm and is served in place of the
   CDN copy. Any other outside request is stopped.
3. It signs in through the planner's own form as staff. Opening it saves nothing: no table changes (no change-log row),
   and the old rows (planner_state, planner_loads) stay as they were.
4. It saves three things through the adapter, one at a time, and after each reads the copy with psql:
   - ticks the first open to-do: planner_state_get() changes only in that to-do's done and doneAt, and the tables in
     exactly that row (todos: done, done_at), logged as actor planner with the tab's ID;
   - changes the first plan card's title. The planner has no field for that, so it goes through the planner's own
     backup screen (Reference > Data: export, change the title, import), which saves the whole document: only that
     title changes (plan_cards.title), logged the same way;
   - types a load for one flight on the Review page (Manual entry > Loads by hand, through save_loads()), on the latest
     recent day with no loads yet in planner_loads_get(): that day, and only that day, has the typed load and is done;
     load_entries and load_days change, logged as planner (save_loads).
   savedAt and version are bookkeeping and may change. A missing key counts as null. After each save planner_state is
   as it was (the planner no longer writes it) and no table's row count changed but change_log's (and the load tables'
   for a typed load).
   After: planner_loads is as it was too, and no job_runs row is written (the side by side is gone).
   Before: save_loads() still writes planner_loads (that day only), and the side by side copies and compares it, ok.
Only after:
5. The old rows refuse a direct write: as postgres "frozen since <date>; write to the tables"; as staff through the data
   API, refused. Neither changes.
6. Two tabs: two pages load the same version. The first ticks a to-do; the second, still showing it unticked, saves a
   new title for that to-do (a clash) and for another (no clash) through its backup screen. The second keeps its other
   title, skips the clashing one, reloads with the message naming it, and then saves that to-do's title from what it
   reloaded, without another reload.
7. A preview address reads through the getters and saves nothing: no write reaches the copy, no table changes.
8. The guards: the account that isn't staff reads no planner_state rows and its writes are refused; signed out and as
   that account, the new tables and views read nothing and refuse a new row; the getters, the write functions and
   adapter_clean_days() refuse both; staff put and remove one item through the data API, logged as planner.
9. Rollback: private.unfreeze_planner_state() makes planner_state and planner_loads equal the getters exactly; the old
   planner code (the last planner that saved planner_state itself, commit OLD_PLANNER, served the same way) then signs
   in and saves a to-do tick into planner_state, which the side by side copies into the tables, comparison ok.
10. Nothing went outside: no request reached the live Supabase host or any address other than the local server, the
   local data API and the served library.

Prints one line per step (ok/FAIL), and no row contents beyond ids and the names of the fields that changed, because the
log is posted on the pull request. Never prints the local keys or the test passwords.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV (a file holding `supabase status -o env`), LOCAL_DB_URL,
SECRET_TABLES and REAL_SAVES_PHASE (before or after). Usage: python3 tests/real_saves_test.py
"""
import asyncio, datetime, json, os, re, secrets, shutil, subprocess, sys, tarfile, tempfile, time, urllib.error, urllib.request
from pathlib import Path
from urllib.parse import urlsplit
from harness import ROOT, WEB, LIVE_HOST, serve, settle, go
from playwright.async_api import async_playwright

PLANNER = WEB / "planner" / "index.html"
COUNTS = ROOT / "database" / "backup" / "counts.sql"
DB = os.environ.get("LOCAL_DB_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
SKIP = os.environ.get("SECRET_TABLES", "public.ingest_secret,public.capture_keys,public.report_access")
PHASE = os.environ.get("REAL_SAVES_PHASE", "after")
BEFORE = PHASE == "before"
# the last planner that saved planner_state itself (as pull request 8 left it): what a rollback of the switch-over reverts to
OLD_PLANNER = "eb4c3efe2276b387429d579a8b262110b2e9fbf7"
LOAD = 61                         # the load typed for one flight (under 95%, so the planner keeps it)
BOOKKEEPING = {"savedAt", "version"}
# The planner tables of #13 (migration 20261009210000_planner_tables.sql): staff only, closed to everyone else
NEW_TABLES = ("worlds", "groups", "airlines", "airline_bases", "airline_aircraft_types", "countries", "airports",
              "world_airports", "aircraft_types", "cabin_configs", "aircraft", "aircraft_cabin_keeps", "markets",
              "service_profiles", "routes", "rotations", "flight_legs", "plan_cards", "plan_card_legs", "todos",
              "todo_items", "growth_log", "spending_log", "fare_plan", "interline_agreements", "monthly_checks",
              "dismissals", "cash_entries", "load_entries", "load_days", "settings", "world_rules", "change_log")
NEW_VIEWS = ("flight_legs_local", "flight_no_clashes")
# The adapter's write side (migration 20261010210000_adapter_write_side.sql): its jobs table and view, staff read only
JOB_TABLES = ("job_runs",)
JOB_VIEWS = ("adapter_check_days",)
WRITERS = ("planner_state_put", "planner_item_put", "planner_item_delete", "adapter_clean_days")
# The capture data in the new model (migration 20261009230000_capture_data.sql): staff read them, nobody else, and only the
# capture's functions write the tables
CAPTURE_TABLES = ("game_flights", "game_payments")
CAPTURE_VIEWS = ("game_loads", "game_flight_pnl", "game_ops_recent", "capture_cash")
# The adapter's read side (migration 20261010120000_planner_data_load.sql): staff only
GETTERS = ("planner_state_get", "planner_state_version", "planner_loads_get")
# The adapter's writes, as the planner calls them
SAVES = ("planner_state_put", "save_loads", "planner_item_put", "planner_item_delete")
failures = []


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:12]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


def why(e):
    return f"{type(e).__name__}: {(str(e).strip().splitlines() or [''])[0][:240]}"


# ---------- what the planner itself names: the live address, its public key and its Supabase library ----------
def planner_facts(html=None):
    html = html or PLANNER.read_text()
    url = re.search(r'const SB_URL = "(https://[^"]+)"', html)
    key = re.search(r'const SB_KEY = "([^"]+)"', html)
    lib = re.search(r'<script src="(https://cdn\.jsdelivr\.net/npm/@supabase/supabase-js@([0-9][0-9A-Za-z.-]*)/dist/umd/supabase\.js)"', html)
    if not (url and key and lib):
        return None
    return {"live_url": url[1].rstrip("/"), "live_key": key[1], "lib_url": lib[1], "lib_version": lib[2]}


def library(version):
    """The package's own UMD build, from npm (which checks the download against the registry)."""
    with tempfile.TemporaryDirectory() as d:
        out = subprocess.run(["npm", "pack", f"@supabase/supabase-js@{version}", "--pack-destination", d, "--silent"],
                             capture_output=True, text=True, timeout=180)
        if out.returncode:
            raise RuntimeError("npm pack failed: " + (out.stderr.strip().splitlines() or ["no output"])[-1][:200])
        with tarfile.open(Path(d) / out.stdout.strip().splitlines()[-1]) as t:
            return t.extractfile("package/dist/umd/supabase.js").read()


# ---------- the local copy: its address and keys, psql, the data API ----------
def local_env():
    env = {}
    for line in Path(os.environ["LOCAL_SUPABASE_ENV"]).read_text().splitlines():
        m = re.match(r'^([A-Z_]+)="(.*)"$', line)
        if m:
            env[m[1]] = m[2]
    if urlsplit(env.get("API_URL", "")).hostname not in ("127.0.0.1", "localhost"):
        raise RuntimeError("the copy's data API address is missing or isn't local")
    if not env.get("ANON_KEY") or not env.get("SERVICE_ROLE_KEY"):
        raise RuntimeError("the copy's keys are missing")
    env["API_URL"] = env["API_URL"].rstrip("/")
    return env


def psql(sql, **var):
    args = ["psql", DB, "-X", "-At", "-q", "-v", "ON_ERROR_STOP=1"] + [a for k, v in var.items() for a in ("-v", f"{k}={v}")]
    r = subprocess.run(args, input=sql, capture_output=True, text=True, timeout=120)
    if r.returncode:
        raise RuntimeError("psql: " + (r.stderr.strip().splitlines() or ["failed"])[0][:200])
    return r.stdout


def counts():
    r = subprocess.run(["psql", DB, "-X", "-At", "-v", "ON_ERROR_STOP=1", "-v", f"skip={SKIP}", "-f", str(COUNTS)],
                       capture_output=True, text=True, timeout=120)
    if r.returncode:
        raise RuntimeError("counting rows failed")
    return dict(line.rsplit(" ", 1) for line in r.stdout.splitlines() if line.strip())


def read_doc():
    """The planner's document as it reads it: planner_state_get()."""
    g = json.loads(psql("select public.planner_state_get()::text").strip())
    return {"doc": json.loads(g["json"]), "saved_at": int(g["saved_at"])}


def read_loads():
    """The planner's loads as it reads them: planner_loads_get(), by month."""
    out = psql("select coalesce(json_object_agg(month, json_build_object('json', json, 'saved_at', saved_at)), '{}') "
               "from public.planner_loads_get()").strip()
    return {m: {"doc": json.loads(r["json"]), "saved_at": int(r["saved_at"])} for m, r in json.loads(out).items()}


def read_old():
    """The old rows as they stand: planner_state and every planner_loads month (text and saved_at)."""
    out = psql("""select json_build_object(
                    'state', (select json_build_object('json', json, 'saved_at', saved_at) from public.planner_state where id = 'main'),
                    'loads', coalesce((select json_object_agg(month, json_build_object('json', json, 'saved_at', saved_at)) from public.planner_loads), '{}'))""").strip()
    return json.loads(out)


_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # straight to the copy, never through a proxy


def http(env, method, path, body=None, token=None, key=None, prefer=None):
    key = key or env["ANON_KEY"]
    h = {"apikey": key, "authorization": "Bearer " + (token or key), "content-type": "application/json"}
    if prefer:
        h["prefer"] = prefer
    req = urllib.request.Request(env["API_URL"] + path, method=method, headers=h,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        with _opener.open(req, timeout=30) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def make_user(env, email, password):
    code, _ = http(env, "POST", "/auth/v1/admin/users", {"email": email, "password": password, "email_confirm": True},
                   key=env["SERVICE_ROLE_KEY"])
    if code != 200:
        raise RuntimeError(f"the sign-in admin API answered {code} when making a test user")


def token_for(env, email, password):
    code, body = http(env, "POST", "/auth/v1/token?grant_type=password", {"email": email, "password": password})
    if code != 200:
        raise RuntimeError(f"signing in a test user answered {code}")
    return json.loads(body)["access_token"]


def is_planner_user(env, token):
    code, body = http(env, "POST", "/rest/v1/rpc/is_planner_user", {}, token=token)
    return code == 200 and json.loads(body) is True


# ---------- comparing: the paths that changed in a document (a missing key counts as null) ----------
def changed(a, b, path=""):
    if isinstance(a, dict) and isinstance(b, dict):
        return [c for k in sorted(set(a) | set(b), key=str) for c in changed(a.get(k), b.get(k), f"{path}.{k}" if path else str(k))]
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [f"{path} (length)"]
        return [c for i, (x, y) in enumerate(zip(a, b)) for c in changed(x, y, f"{path}[{i}]")]
    return [] if a == b and isinstance(a, bool) == isinstance(b, bool) else [path]   # 2 equals 2.0, but true isn't 1


def marks():
    """Where the change log and job_runs stand, so a save's own rows can be told apart."""
    return json.loads(psql("select json_build_object('log', coalesce((select max(id) from public.change_log), 0), "
                           "'job', coalesce((select max(id) from public.job_runs), 0))").strip())


def log_since(mark):
    """The change-log rows since the mark: table, op, id, the names of the fields an update changed, actor and detail."""
    return json.loads(psql(f"""select coalesce(json_agg(json_build_object('table', l.table_name, 'op', l.op, 'id', l.row_key ->> 'id',
                                  'fields', (select coalesce(json_agg(k order by k), '[]') from jsonb_object_keys(
                                               case when l.op = 'update' then l.new_values else '{{}}'::jsonb end) k),
                                  'actor', l.actor, 'detail', l.actor_detail) order by l.id), '[]')
                                 from public.change_log l where l.id > {int(mark['log'])}""").strip())


def jobs_since(mark):
    return json.loads(psql(f"""select coalesce(json_agg(json_build_object('job', job, 'status', status, 'note', note) order by id), '[]')
                                 from public.job_runs where id > {int(mark['job'])}""").strip())


def logged(mark, intended, detail):
    """After a save: the change-log rows since the mark are all ones the save should have made (intended(row)), and name
    actor planner with the given detail. Returns the problems and how many rows there were. Prints tables, ids and field
    names, never values."""
    rows = log_since(mark)
    problems = [] if rows else ["the tables didn't change"]
    for r in rows:
        if not intended(r):
            problems.append(f"the tables changed beyond the save: {r['table']} {r['op']} {r['id'] or ''} ({', '.join(r['fields']) or 'whole row'})")
        if r["actor"] != "planner" or r["detail"] != detail:
            problems.append(f"a change-log row names {r['actor']} ({r['detail']}), not planner ({detail})")
    return problems, len(rows)


def count_changes(before, after, allow=()):
    return [f"row count changed: {t}: {before.get(t, 'none')} -> {after.get(t, 'none')}"
            for t in sorted(set(before) | set(after)) if before.get(t) != after.get(t) and t not in allow]


def months_changed(a, b, skip=()):
    return [m for m in sorted(set(a) | set(b)) if m not in skip and a.get(m) != b.get(m)]


def old_rows_problems(o0, o1, loads_month=None, loads_day=None):
    """The old rows after a save: planner_state as it was; planner_loads as it was, except (before the switch-over) the
    typed day of its month."""
    problems = []
    if o1["state"] != o0["state"]:
        problems.append("planner_state changed (the planner no longer writes it)")
    for m in sorted(set(o0["loads"]) | set(o1["loads"])):
        a, b = o0["loads"].get(m), o1["loads"].get(m)
        if a == b:
            continue
        if m != loads_month:
            problems.append(f"planner_loads {m} changed")
            continue
        ja, jb = json.loads((a or {}).get("json") or "{}"), json.loads(b["json"])
        other = [d for d in sorted(set(ja) | set(jb)) if d not in (loads_day, "__savedAt") and ja.get(d) != jb.get(d)]
        if other:
            problems.append(f"planner_loads {m} changed on other days: {', '.join(other[:8])}")
    return problems


async def wait_for(read, moved, seconds=20):
    """Polls the copy until moved(read()) is true, or gives up; returns the last read."""
    end = time.monotonic() + seconds
    while True:
        got = read()
        if moved(got) or time.monotonic() > end:
            return got
        await asyncio.sleep(0.25)


# ---------- the browser: the planner at its live address, its database answered by the local copy ----------
class Planner:
    def __init__(self, p, port, env, facts, lib_js):
        self.p, self.port, self.env, self.f, self.lib = p, port, env, facts, lib_js
        self.copy = 0            # requests for the live Supabase host, answered by the local copy
        self.rpcs = []           # the functions it called on the copy, in order
        self.served = 0          # times the planner's library was served from npm's copy
        self.local = 0           # requests to the local server
        self.stopped = set()     # hosts whose requests were stopped
        self.outside = []        # responses that came over the network from anywhere but the local server: must stay empty
        self.errors = []         # page errors and console errors, as they happen
        self.dialogs = []        # alerts the planner showed (dismissed)
        self.b = self.api = None

    async def open(self, host=LIVE_HOST):
        # belt and braces: any name but the planner's own address fails to resolve, and no proxy is used
        rules = f"MAP {LIVE_HOST} 127.0.0.1:{self.port}, MAP * ~NOTFOUND, EXCLUDE 127.0.0.1, EXCLUDE localhost"
        self.b = await self.p.chromium.launch(args=[f"--host-resolver-rules={rules}", "--no-proxy-server"])
        self.api = await self.p.request.new_context()
        ctx = await self.b.new_context(viewport={"width": 1440, "height": 1000}, timezone_id="UTC", locale="en-US",
                                       service_workers="block", accept_downloads=True)
        await ctx.route("**/*", self.route)
        await ctx.route_web_socket(re.compile(".*"), self.socket)
        ctx.on("response", lambda r: asyncio.ensure_future(self.where(r)))
        self.pg = pg = await ctx.new_page()
        pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
        pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
              if m.type == "error" and "Failed to load resource" not in m.text and "Preview: not sent" not in m.text else None)
        pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await pg.goto(f"http://{host}:{self.port}/planner/")
        return pg

    async def route(self, r):
        req, u = r.request, r.request.url
        live, host = self.f["live_url"], urlsplit(r.request.url)
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
        elif u == self.f["lib_url"]:
            self.served += 1
            await r.fulfill(body=self.lib, content_type="application/javascript")
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
        """A response that came over the network has a server address; only the local server's is allowed."""
        try:
            addr = await res.server_addr()
        except Exception:
            addr = None
        if addr and not (addr.get("ipAddress") in ("127.0.0.1", "::1", "[::1]") and int(addr.get("port") or 0) == self.port):
            self.outside.append(urlsplit(res.url).hostname or "an unknown address")

    async def close(self):
        if self.b:
            await self.b.close()
        if self.api:
            await self.api.dispose()

    async def sign_in(self, email, password, preview=False):
        pg = self.pg
        await pg.wait_for_selector("#g-email", timeout=30000)
        await pg.fill("#g-email", email)
        await pg.fill("#g-pass", password)
        await pg.click("#g-in")
        # it reloads once after signing in (so the route research loads with the session), then reads the copy
        state = "/preview/" if preview else "/cloud/"
        await pg.wait_for_function(f"""() => window.__eqDataLoaded === true && window.__eqPreview === {'true' if preview else 'false'}
            && (!document.getElementById('gate') || document.getElementById('gate').style.display === 'none')
            && {state}.test((document.getElementById('savestate') || {{}}).textContent || '')""", timeout=60000)
        await settle(pg, 1500)

    async def tab(self):
        return await self.pg.evaluate("window.__eqTab || ''")


# ---------- the three saves ----------
async def tick_todo(pl, d0, l0, o0, n0):
    todos = d0["doc"].get("todos") or []
    i = next((i for i, t in enumerate(todos) if isinstance(t, dict) and not t.get("done")), None)
    if i is None:
        return "tick a to-do", ["last night's data has no open to-do to tick"]
    tid = todos[i].get("id")
    name = f"tick a to-do ({tid})"
    await go(pl.pg, "home")
    k = await pl.pg.evaluate("id => [...document.querySelectorAll('input[data-tododone]')].findIndex(x => x.dataset.tododone === id)", tid)
    if k < 0:
        return name, ["the first open to-do isn't on Home"]
    mark, tab = marks(), await pl.tab()
    row_id = psql("select id from public.todos where legacy_key = :'k' and world_id = (select id from public.worlds where is_default)", k=tid).strip()
    await pl.pg.locator("input[data-tododone]").nth(k).click()
    await wait_for(read_doc, lambda d: ((d["doc"].get("todos") or [{}] * (i + 1))[i] or {}).get("done") is True)
    await settle(pl.pg, 800)
    d1, l1, o1, n1 = read_doc(), read_loads(), read_old(), counts()
    want = {f"todos[{i}].done", f"todos[{i}].doneAt"}
    diff = changed(d0["doc"], d1["doc"])
    t1 = (d1["doc"].get("todos") or [])[i] if len(d1["doc"].get("todos") or []) > i else {}
    problems = []
    if t1.get("id") != tid or t1.get("done") is not True or not t1.get("doneAt"):
        problems.append(f"the to-do isn't saved as done (done: {t1.get('done')!r}, doneAt set: {bool(t1.get('doneAt'))})")
    other = [d for d in diff if d not in want | BOOKKEEPING]
    if other:
        problems.append("other fields changed in planner_state_get(): " + ", ".join(other[:12]))
    if months_changed(l0, l1):
        problems.append("planner_loads_get() changed: " + ", ".join(months_changed(l0, l1)))
    problems += old_rows_problems(o0, o1)
    problems += count_changes(n0, n1, allow={"public.change_log"})
    more, n = logged(mark, lambda r: r["table"] == "todos" and r["op"] == "update" and r["id"] == row_id
                     and set(r["fields"]) <= {"done", "done_at", "extra"}, tab)
    problems += more
    problems += [f"a job_runs row: {j['job']}" for j in jobs_since(mark)]
    return (f"{name}: {', '.join(d.split('.', 1)[1] for d in diff if d in want) or 'nothing'} changed; {n} change(s) to todos "
            f"(planner, the tab's ID); planner_state unchanged"), problems


async def export_doc(pg):
    await go(pg, "ref")
    if not await pg.evaluate("(document.querySelector('details.rsec[data-rsec=\"Data\"]') || {}).open === true"):
        await pg.click("details.rsec[data-rsec='Data'] > summary")
        await settle(pg, 300)
    async with pg.expect_download(timeout=30000) as dl:
        await pg.click("#exp")
    return json.loads(Path(await (await dl.value).path()).read_text())


async def import_doc(pg, doc):
    await pg.evaluate("t => { document.getElementById('io').value = t; }", json.dumps(doc, indent=1))
    await pg.click("#imp")


async def retitle_plan(pl, d0, l0, o0, n0):
    plans = d0["doc"].get("plans") or {}
    if not plans:
        return "change a plan card's title", ["last night's data has no plan card"]
    reg = next(iter(plans))
    name = f"change a plan card's title ({reg})"
    pg = pl.pg
    exported = await export_doc(pg)
    if reg not in (exported.get("plans") or {}):
        return name, ["the planner's export has no such plan card"]
    title = f"{plans[reg].get('title') or reg} · real-saves check {secrets.token_hex(3)}"
    exported["plans"][reg]["title"] = title
    mark, tab = marks(), await pl.tab()
    card_id = psql("""select c.id from public.plan_cards c join public.aircraft a on a.id = c.aircraft_id
                       where a.registration = :'r' and a.world_id = (select id from public.worlds where is_default)""", r=reg).strip()
    await import_doc(pg, exported)
    await wait_for(read_doc, lambda d: ((d["doc"].get("plans") or {}).get(reg) or {}).get("title") == title)
    await settle(pg, 800)
    d1, l1, o1, n1 = read_doc(), read_loads(), read_old(), counts()
    want = {f"plans.{reg}.title"}
    diff = changed(d0["doc"], d1["doc"])
    problems = []
    if await pg.evaluate("(document.getElementById('io') || {}).value || ''") != "Imported.":
        problems.append("the planner didn't take its own export back")
    if ((d1["doc"].get("plans") or {}).get(reg) or {}).get("title") != title:
        problems.append("the new title isn't in planner_state_get()")
    other = [d for d in diff if d not in want | BOOKKEEPING]
    if other:
        problems.append("other fields changed in planner_state_get(): " + ", ".join(other[:12]))
    if months_changed(l0, l1):
        problems.append("planner_loads_get() changed: " + ", ".join(months_changed(l0, l1)))
    problems += old_rows_problems(o0, o1)
    problems += count_changes(n0, n1, allow={"public.change_log"})
    more, n = logged(mark, lambda r: r["table"] == "plan_cards" and r["op"] == "update" and r["id"] == card_id
                     and r["fields"] == ["title"], tab)
    problems += more
    problems += [f"a job_runs row: {j['job']}" for j in jobs_since(mark)]
    return (f"{name}: {', '.join(d.split('.', 2)[2] for d in diff if d in want) or 'nothing'} changed; {n} change(s) to "
            "plan_cards (planner, the tab's ID); planner_state unchanged"), problems


async def pick_flight(pg, l0):
    """The latest recent day with no loads yet that has flights in the planner, and its first flight past its first week.
    A day that already has loads is left alone: typing replaces that day's whole entry (see tests/README.md)."""
    today = datetime.date.fromisoformat(await pg.evaluate("new Date().toISOString().slice(0, 10)"))
    has = lambda d: d.isoformat() in (l0.get(d.isoformat()[:7]) or {}).get("doc", {})
    days = [today - datetime.timedelta(n) for n in range(0, 15)] + [today + datetime.timedelta(n) for n in range(1, 8)]
    await go(pg, "review")
    at = today
    for d in (d for d in days if not has(d)):
        n = (d - at).days
        for _ in range(abs(n)):
            await pg.evaluate(f"document.querySelector('[data-lfday=\"{1 if n > 0 else -1}\"]').click()")
            await settle(pg, 100)
        at = d
        cards = await pg.evaluate("""() => [...document.querySelectorAll('.qcard')].map(c => {
            const h = c.querySelector('.qh'), img = h && h.querySelector(':scope > img.alogo'), b = h && h.querySelector(':scope > b');
            return { al: img ? img.alt : b ? b.textContent.trim() : '', nos: [...c.querySelectorAll('.qlist > span:not(.dim) > b')].map(x => x.textContent.trim()) }; })""")
        for c in cards:
            if c["al"] and c["nos"]:
                return d, c["al"], c["nos"][0]
    return None


async def type_load(pl, d0, l0, o0, n0):
    pg, dl0 = pl.pg, len(pl.dialogs)
    got = await pick_flight(pg, l0)
    if not got:
        return "type a load", ["no day in the last two weeks or the next week is free of loads and has a flight in the planner"]
    day, al, no = got
    mo, key, iso = day.isoformat()[:7], f"{al}|{no}", day.isoformat()
    name = f"type a load ({iso}, {al} {no})"
    await go(pg, "finance")
    if not await pg.evaluate("al => { const c = [...document.querySelectorAll('[data-final]')].find(x => x.dataset.final === al); if (c) c.click(); return !!c; }", al):
        return name, ["the airline has no card on the Review page"]
    await settle(pg)
    if not await pg.evaluate("(() => { const s = document.querySelector('summary[data-det=\"lfman\"]'); return !!(s && s.parentElement.open); })()"):
        await pg.click("summary[data-det='lfman']")
        await settle(pg, 300)
    k = await pg.evaluate("al => [...document.querySelectorAll('[data-q]')].findIndex(x => x.dataset.q === al + '|x')", al)
    if k < 0:
        return name, ["the airline has no box under Loads by hand that day"]
    box = pg.locator("[data-q]").nth(k)
    if (await box.input_value()).strip():
        return name, ["the chosen day already has loads in the box"]
    await box.fill(f"{no} {LOAD}")
    mark = marks()
    await pg.click("#lfsave")
    await wait_for(read_loads, lambda l: ((l.get(mo) or {}).get("doc", {}).get(iso) or {}).get("f") == {key: LOAD})
    await settle(pg, 800)
    l1, d1, o1, n1 = read_loads(), read_doc(), read_old(), counts()
    problems = []
    a, b = (l0.get(mo) or {"doc": {}})["doc"], (l1.get(mo) or {"doc": {}})["doc"]
    entry = b.get(iso) if isinstance(b.get(iso), dict) else {}
    if entry.get("f") != {key: LOAD} or entry.get("done") is not True:
        problems.append(f"the day isn't saved as typed in planner_loads_get() (flights: {', '.join(sorted(entry.get('f') or {})) or 'none'}; "
                        f"done: {entry.get('done')!r})")
    other = [x for x in sorted(set(a) | set(b)) if x != iso and a.get(x) != b.get(x)]
    if other:
        problems.append("other days changed: " + ", ".join(other[:12]))
    if months_changed(l0, l1, skip={mo}):
        problems.append("other months changed: " + ", ".join(months_changed(l0, l1, skip={mo})))
    diff = [x for x in changed(d0["doc"], d1["doc"]) if x not in BOOKKEEPING]
    if diff:
        problems.append("planner_state_get() changed: " + ", ".join(diff[:12]))
    # before the switch-over save_loads() still writes planner_loads (that day only), and the side by side follows it
    problems += old_rows_problems(o0, o1, loads_month=mo if BEFORE else None, loads_day=iso)
    new_month = BEFORE and mo not in o0["loads"] and int(n1.get("public.planner_loads", 0)) == int(n0.get("public.planner_loads", 0)) + 1
    allow = {"public.change_log", "public.load_entries", "public.load_days"} | ({"public.job_runs"} if BEFORE else set()) \
        | ({"public.planner_loads"} if new_month else set())
    problems += count_changes(n0, n1, allow=allow)
    problems += [f"the planner said: {m}" for m in pl.dialogs[dl0:]]
    more, n = logged(mark, lambda r: r["table"] in ("load_entries", "load_days"), "save_loads")
    problems += more
    jobs = jobs_since(mark)
    if BEFORE:
        if not {"adapter_mirror", "adapter_check"} <= {j["job"] for j in jobs}:
            problems.append("job_runs has no mirror or no comparison for the planner_loads write")
        problems += [f"{j['job']} {j['status']}: {j['note']}"[:300] for j in jobs if j["status"] != "ok"]
    else:
        problems += [f"a job_runs row: {j['job']}" for j in jobs]
    typed = psql("""select e.eco_pct from public.load_entries e join public.airlines a on a.id = e.airline_id
                     where a.planner_name = :'al' and a.world_id = (select id from public.worlds where is_default)
                       and e.game_date = :'day'::date and e.flight_no = :'no'::int""", al=al, day=iso, no=no).strip()
    if not typed or float(typed) != LOAD:
        problems.append("load_entries doesn't have the typed load for that flight and day")
    return (f"{name}: saved by save_loads() to load_entries and load_days ({n} change(s), planner, save_loads); "
            + ("planner_loads that day too, its side-by-side comparison ok" if BEFORE else "planner_loads unchanged")), problems


# ---------- after the switch-over only ----------
def frozen_rows(env, staff):
    """The old rows refuse a direct write: as postgres with the freeze's message; as staff through the data API."""
    problems, o0 = [], read_old()
    for sql in ("update public.planner_state set saved_at = saved_at where id = 'main'",
                "insert into public.planner_loads (month, json, saved_at) values ('2099-12', '{}', 1)"):
        r = subprocess.run(["psql", DB, "-X", "-At", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql], capture_output=True, text=True, timeout=60)
        if r.returncode == 0 or not re.search(r"frozen since .+; write to the tables", r.stderr):
            problems.append("as postgres, " + ("an update of planner_state" if sql.startswith("update") else "an insert into planner_loads")
                            + " wasn't refused with \"frozen since ...; write to the tables\"")
    token = token_for(env, *staff)
    code, _ = http(env, "POST", "/rest/v1/planner_state", {"id": "main", "json": "{}", "saved_at": 1}, token=token,
                   prefer="resolution=merge-duplicates,return=minimal")
    if code not in (401, 403):
        problems.append(f"as staff through the data API, writing planner_state wasn't refused (answer {code})")
    if read_old() != o0:
        problems.append("an old row changed")
    since = psql("select private.planner_frozen_since('public.planner_state'::regclass)").strip()
    return problems, since


async def two_tabs(p, port, env, facts, lib, staff):
    """Two pages load the same version; the first ticks to-do X; the second, still showing X unticked, saves new titles for
    X (a clash) and Y (no clash). It keeps Y, skips X, reloads with the message naming X; then saves X's title from what
    it reloaded, without another reload."""
    d0 = read_doc()
    open_ids = [t.get("id") for t in d0["doc"].get("todos") or [] if isinstance(t, dict) and not t.get("done") and t.get("id")]
    if len(open_ids) < 2:
        return "two tabs", ["last night's data has fewer than two open to-dos"]
    x, y = open_ids[0], open_ids[1]
    a, b = Planner(p, port, env, facts, lib), Planner(p, port, env, facts, lib)
    problems = []
    try:
        await a.open(); await a.sign_in(*staff)
        await b.open(); await b.sign_in(*staff)
        tab_a, tab_b = await a.tab(), await b.tab()
        if not tab_a or tab_a == tab_b:
            problems.append("the two pages don't have two tab IDs")
        # the second page's view, as it loaded it (before the first saves)
        stale = await export_doc(b.pg)
        # the first page ticks X
        await go(a.pg, "home")
        k = await a.pg.evaluate("id => [...document.querySelectorAll('input[data-tododone]')].findIndex(z => z.dataset.tododone === id)", x)
        if k < 0:
            return "two tabs", ["the first open to-do isn't on Home"]
        await a.pg.locator("input[data-tododone]").nth(k).click()
        await wait_for(read_doc, lambda d: next((t for t in d["doc"].get("todos") or [] if t.get("id") == x), {}).get("done") is True)
        await settle(a.pg, 800)
        # the second page, from its stale view: X's title (clashes with the first page's tick) and Y's (doesn't)
        mark = marks()
        tx, ty = f"two tabs {secrets.token_hex(3)}: X", f"two tabs {secrets.token_hex(3)}: Y"
        for t in stale.get("todos") or []:
            if t.get("id") == x:
                t["title"] = tx
            if t.get("id") == y:
                t["title"] = ty
        await import_doc(b.pg, stale)
        try:
            await b.pg.wait_for_selector(".eqtoast", timeout=20000)
            toast = await b.pg.evaluate("(document.querySelector('.eqtoast') || {}).textContent || ''")
        except Exception:
            toast = ""
        await settle(b.pg, 800)
        d1 = read_doc()
        t_x = next((t for t in d1["doc"].get("todos") or [] if t.get("id") == x), {})
        t_y = next((t for t in d1["doc"].get("todos") or [] if t.get("id") == y), {})
        if t_x.get("done") is not True or t_x.get("title") == tx:
            problems.append("the clashing to-do isn't as the first page left it (the second overwrote it, or the tick is gone)")
        if t_y.get("title") != ty:
            problems.append("the second page's change to the other to-do wasn't kept")
        if "Newer changes were saved elsewhere" not in toast or f"todos {x}" not in toast:
            problems.append(f"the second page didn't reload with the message naming the skipped to-do (it said: {toast[:160]!r})")
        b_view = await export_doc(b.pg)
        if next((t for t in b_view.get("todos") or [] if t.get("id") == x), {}).get("done") is not True:
            problems.append("the second page didn't reload the first page's tick")
        rows = log_since(mark)
        if any(r["actor"] != "planner" or r["detail"] != tab_b for r in rows):
            problems.append("the second page's save isn't logged as planner with its tab's ID")
        # now, from what it reloaded, the second page saves X's title: no clash, no reload
        await settle(b.pg, 4800)   # the message goes after 4.5 s
        tx2 = f"two tabs {secrets.token_hex(3)}: X again"
        for t in b_view.get("todos") or []:
            if t.get("id") == x:
                t["title"] = tx2
        await import_doc(b.pg, b_view)
        await wait_for(read_doc, lambda d: next((t for t in d["doc"].get("todos") or [] if t.get("id") == x), {}).get("title") == tx2, seconds=15)
        await settle(b.pg, 1200)
        if next((t for t in read_doc()["doc"].get("todos") or [] if t.get("id") == x), {}).get("title") != tx2:
            problems.append("after reloading, the second page couldn't save the to-do it had been told to make again")
        if await b.pg.evaluate("!!document.querySelector('.eqtoast')"):
            problems.append("after reloading, the second page was told to reload again")
        problems += a.errors + b.errors
    finally:
        await a.close(); await b.close()
    return f"two tabs: the second kept its other to-do, skipped the one the first had ticked, reloaded naming it (todos {x}), then saved it", problems


async def preview(p, port, env, facts, lib, staff):
    """At a preview address the planner reads through the getters and saves nothing."""
    pv = Planner(p, port, env, facts, lib)
    problems, n0, mark = [], counts(), marks()
    try:
        await pv.open(host="127.0.0.1")
        await pv.sign_in(*staff, preview=True)
        await go(pv.pg, "home")
        box = pv.pg.locator("input[data-tododone]")
        if await box.count():
            await box.first.click()
            await settle(pv.pg, 1500)
        else:
            problems.append("no to-do to tick on Home")
        read = sorted(set(pv.rpcs) & set(GETTERS))
        if "planner_state_get" not in read or "planner_loads_get" not in read:
            problems.append(f"the preview didn't read through the getters (it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})")
        sent = [r for r in pv.rpcs if r in SAVES]
        if sent:
            problems.append("the preview sent a save to the copy: " + ", ".join(sent))
        if log_since(mark):
            problems.append("the tables changed")
        problems += count_changes(n0, counts())
        problems += pv.errors
    finally:
        await pv.close()
    return f"a preview address reads through the getters ({', '.join(sorted(set(pv.rpcs) & set(GETTERS)))}) and saves nothing", problems, pv


async def rollback(p, env, lib, staff):
    """private.unfreeze_planner_state(), then the old planner code (the base branch's) signs in and ticks a to-do."""
    problems = []
    res = json.loads(psql("select private.unfreeze_planner_state()::text").strip())
    g, o = json.loads(psql("select public.planner_state_get()::text").strip()), read_old()
    if json.loads(o["state"]["json"]) != json.loads(g["json"]) or int(o["state"]["saved_at"]) != int(g["saved_at"]):
        problems.append("after private.unfreeze_planner_state(), planner_state isn't planner_state_get() exactly")
    gl = read_loads()
    bad = [m for m in gl if m not in o["loads"] or json.loads(o["loads"][m]["json"]) != gl[m]["doc"] or int(o["loads"][m]["saved_at"]) != gl[m]["saved_at"]]
    if bad:
        problems.append("after private.unfreeze_planner_state(), these planner_loads months aren't the getter's: " + ", ".join(bad))
    # the old planner, as the base branch has it
    shown = subprocess.run(["git", "show", f"{OLD_PLANNER}:web/planner/index.html"], capture_output=True, text=True, cwd=ROOT)
    if shown.returncode:
        return "rollback", problems + [f"couldn't read the old planner (commit {OLD_PLANNER[:7]})"], None
    old_facts = planner_facts(shown.stdout)
    if not old_facts or "planner_state_put" in shown.stdout:
        return "rollback", problems + [f"commit {OLD_PLANNER[:7]}'s planner isn't the old one"], None
    if old_facts["lib_version"] != planner_facts()["lib_version"]:
        lib = library(old_facts["lib_version"])
    tmp = Path(tempfile.mkdtemp())
    try:
        shutil.copytree(WEB, tmp / "web")
        (tmp / "web" / "planner" / "index.html").write_text(shown.stdout)
        with serve(root=tmp / "web") as port:
            old = Planner(p, port, env, old_facts, lib)
            try:
                await old.open()
                await old.sign_in(*staff)
                s0 = read_old()["state"]
                d0 = json.loads(s0["json"])
                open_ids = [t.get("id") for t in d0.get("todos") or [] if isinstance(t, dict) and not t.get("done") and t.get("id")]
                if not open_ids:
                    return "rollback", problems + ["no open to-do left for the old planner to tick"], old
                await go(old.pg, "home")
                k = await old.pg.evaluate("id => [...document.querySelectorAll('input[data-tododone]')].findIndex(z => z.dataset.tododone === id)", open_ids[0])
                mark = marks()
                await old.pg.locator("input[data-tododone]").nth(k).click()
                s1 = await wait_for(lambda: read_old()["state"], lambda s: next((t for t in json.loads(s["json"]).get("todos") or []
                                                                                 if t.get("id") == open_ids[0]), {}).get("done") is True)
                await settle(old.pg, 1500)
                if int(s1["saved_at"]) <= int(s0["saved_at"]):
                    problems.append("the old planner's save didn't reach planner_state")
                jobs = jobs_since(mark)
                if not {"adapter_mirror", "adapter_check"} <= {j["job"] for j in jobs}:
                    problems.append("the side by side didn't copy and compare the old planner's save")
                problems += [f"{j['job']} {j['status']}: {j['note']}"[:300] for j in jobs if j["status"] != "ok"]
                if next((t for t in read_doc()["doc"].get("todos") or [] if t.get("id") == open_ids[0]), {}).get("done") is not True:
                    problems.append("the old planner's tick didn't reach the tables")
                problems += old.errors
            finally:
                await old.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return (f"rollback: private.unfreeze_planner_state() (frozen since {res.get('was_frozen_since')}) made planner_state and "
            f"{res.get('planner_loads_months')} planner_loads month(s) the getters' exactly; the old planner ({OLD_PLANNER[:7]}) then signed "
            "in and ticked a to-do into planner_state, copied into the tables, comparison ok"), problems, old


# ---------- the guards ----------
def guard(env, email, password):
    o0, n0 = read_old(), counts()
    token = token_for(env, email, password)
    problems = []
    if is_planner_user(env, token):
        problems.append("public.is_planner_user() is true for it")
    code, body = http(env, "GET", "/rest/v1/planner_state?select=id", token=token)
    if code == 200 and json.loads(body) != []:
        problems.append(f"it read {len(json.loads(body))} planner_state row(s)")
    elif code not in (200, 401, 403):
        problems.append(f"reading planner_state answered {code}")
    code, _ = http(env, "POST", "/rest/v1/planner_state", {"id": "main", "json": "{}", "saved_at": 1}, token=token,
                   prefer="resolution=merge-duplicates,return=minimal")
    if code not in (401, 403):
        problems.append(f"writing planner_state wasn't refused (answer {code})")
    month = (sorted(o0["loads"]) or [datetime.date.today().isoformat()[:7]])[-1]
    code, _ = http(env, "POST", "/rest/v1/rpc/save_loads", {"p_month": month, "p_days": {}}, token=token)
    if code not in (401, 403):
        problems.append(f"save_loads() wasn't refused (answer {code})")
    if read_old() != o0:
        problems.append("an old row changed")
    return problems + count_changes(n0, counts())


def guard_new_tables(env, email, password):
    """Signed out (the public key alone) and as the account that isn't staff, through the data API: each new table and
    view reads no rows (signed out, anon has no grant at all, so the read is refused: 401; not staff, the staff rules
    leave nothing: 200 and []), and adding a row to each table is refused (401 signed out, 403 not staff). Prints
    answers only, never rows."""
    n0 = counts()
    tables, views = NEW_TABLES + CAPTURE_TABLES + JOB_TABLES, NEW_VIEWS + CAPTURE_VIEWS + JOB_VIEWS
    missing = [t for t in tables if f"public.{t}" not in n0]
    problems = [f"no such table on the copy: {', '.join(missing)}"] if missing else []
    for who, token, refused in (("signed out", None, 401), ("not staff", token_for(env, email, password), 403)):
        for t in tables + views:
            code, body = http(env, "GET", f"/rest/v1/{t}?select=*&limit=5", token=token)
            if who == "signed out" and code != 401:
                problems.append(f"{who}: reading {t} wasn't refused (answer {code}, expected 401)")
            elif who == "not staff" and code != 200:
                problems.append(f"{who}: reading {t} answered {code}, expected 200 with no rows")
            elif code == 200 and json.loads(body) != []:
                problems.append(f"{who}: read {len(json.loads(body))} row(s) of {t}")
        for t in tables:
            row = {"op": "insert"} if t == "change_log" else {"job": "backup"} if t == "job_runs" else {"created_at": "2026-10-09T00:00:00Z"}
            code, _ = http(env, "POST", f"/rest/v1/{t}", row, token=token, prefer="return=minimal")
            if code != refused:
                problems.append(f"{who}: adding a row to {t} wasn't refused (answer {code}, expected {refused})")
    return problems + count_changes(n0, counts())


def guard_getters(env, staff, other):
    """Through the data API: each getter refuses a signed-out caller (401) and the account that isn't staff (403), and
    gives staff (200) the same answer as psql, as postgres. Prints answers only, never documents."""
    problems = []
    for who, token, expected in (("signed out", None, 401), ("not staff", token_for(env, *other), 403)):
        for g in GETTERS:
            code, _ = http(env, "POST", f"/rest/v1/rpc/{g}", {}, token=token)
            if code != expected:
                problems.append(f"{who}: {g}() answered {code}, expected {expected}")
    token = token_for(env, *staff)
    code, body = http(env, "POST", "/rest/v1/rpc/planner_state_get", {}, token=token)
    mine = json.loads(psql("select public.planner_state_get()::text"))
    if code != 200:
        problems.append(f"staff: planner_state_get() answered {code}")
    elif json.loads(json.loads(body)["json"]) != json.loads(mine["json"]):
        problems.append("staff: planner_state_get() gave another document than psql")
    code, body = http(env, "POST", "/rest/v1/rpc/planner_loads_get", {}, token=token)
    mine = json.loads(psql("select coalesce(json_agg(json_build_object('month', month, 'json', json::json) order by month), '[]') from public.planner_loads_get()"))
    if code != 200:
        problems.append(f"staff: planner_loads_get() answered {code}")
    elif sorted(([r["month"], json.loads(r["json"])] for r in json.loads(body)), key=lambda x: x[0]) != [[r["month"], r["json"]] for r in mine]:
        problems.append("staff: planner_loads_get() gave other months than psql")
    code, body = http(env, "POST", "/rest/v1/rpc/planner_state_version", {}, token=token)
    if code != 200 or json.loads(body) != int(psql("select public.planner_state_version()").strip()):
        problems.append(f"staff: planner_state_version() answered {code}, or another time than psql")
    return problems


def guard_writers(env, staff, other):
    """Through the data API: the adapter's write functions and adapter_clean_days() refuse a signed-out caller (401) and
    the account that isn't staff (403); staff put one item (a dismissed alert) and remove it again, both logged as
    planner, role authenticated. Prints answers only."""
    problems, n0 = [], counts()
    calls = (("planner_state_put", {"p_json": "{}", "p_saved_at": None, "p_base": None, "p_client": "real-saves"}),
             ("planner_item_put", {"p_section": "dismissed", "p_key": "real-saves|refused", "p_value": "2026-10-10"}),
             ("planner_item_delete", {"p_section": "dismissed", "p_key": "real-saves|refused"}),
             ("adapter_clean_days", {}))
    for who, token, expected in (("signed out", None, 401), ("not staff", token_for(env, *other), 403)):
        for g, body in calls:
            code, _ = http(env, "POST", f"/rest/v1/rpc/{g}", body, token=token)
            if code != expected:
                problems.append(f"{who}: {g}() answered {code}, expected {expected}")
    token = token_for(env, *staff)
    key = f"real-saves|{secrets.token_hex(3)}"
    doc = lambda: json.loads(json.loads(psql("select public.planner_state_get()::text"))["json"])
    code, body = http(env, "POST", "/rest/v1/rpc/planner_item_put", {"p_section": "dismissed", "p_key": key, "p_value": "2026-10-10"}, token=token)
    if code != 200 or json.loads(body).get("applied") != 1:
        problems.append(f"staff: planner_item_put() answered {code}")
    elif (doc().get("dismissed") or {}).get(key) != "2026-10-10":
        problems.append("staff: the item put through the data API isn't in planner_state_get()")
    code, body = http(env, "POST", "/rest/v1/rpc/planner_item_delete", {"p_section": "dismissed", "p_key": key}, token=token)
    if code != 200 or json.loads(body).get("applied") != 1:
        problems.append(f"staff: planner_item_delete() answered {code}")
    elif key in (doc().get("dismissed") or {}):
        problems.append("staff: the item removed through the data API is still in planner_state_get()")
    logged_n = psql("""select count(*) from public.change_log where table_name = 'dismissals' and row_key ->> 'alert_key' = :'k'
                        and actor = 'planner' and db_role = 'authenticated'""", k=key).strip()
    if logged_n != "2":
        problems.append(f"staff: the item's put and removal logged {logged_n} time(s) as planner (authenticated), expected 2")
    code, body = http(env, "POST", "/rest/v1/rpc/adapter_clean_days", {}, token=token)
    if code != 200 or not isinstance(json.loads(body), int):
        problems.append(f"staff: adapter_clean_days() answered {code}")
    return problems + count_changes(n0, counts(), allow={"public.change_log"})


async def main():
    facts = planner_facts()
    print(f"phase: {'before this pull request''s database changes' if BEFORE else 'after every pending database change'}", flush=True)
    if not facts:
        step(False, "the planner names its Supabase address, public key and library",
             ["not found in web/planner/index.html, so the planner can't be pointed at the copy without changing it"])
        sys.exit(1)
    try:
        env = local_env()
        lib = library(facts["lib_version"])
    except Exception as e:
        step(False, f"set up: the copy's address and the planner's Supabase library ({facts['lib_version']}) from npm", [why(e)])
        sys.exit(1)

    # test users with throwaway passwords made here; they exist only in the copy
    tag = secrets.token_hex(4)
    staff = (f"real-saves-staff-{tag}@example.com", secrets.token_urlsafe(18))
    other = (f"real-saves-other-{tag}@example.com", secrets.token_urlsafe(18))
    name = "test users: one staff, one not, made through the copy's sign-in"
    try:
        make_user(env, *staff)
        make_user(env, *other)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    step(not problems, name, problems)
    if problems:
        sys.exit(1)

    planners = []
    with serve() as port:
        async with async_playwright() as p:
            pl = Planner(p, port, env, facts, lib)
            planners.append(pl)
            try:
                o0, n0, mark = read_old(), counts(), marks()
                await pl.open()
                await pl.sign_in(*staff)
                problems = list(pl.errors)
                if read_old() != o0:
                    problems.append("opening the planner changed planner_state or planner_loads")
                rows = log_since(mark)
                if rows:
                    problems.append("opening the planner changed the tables: " + ", ".join(sorted({r['table'] for r in rows})))
                problems += count_changes(n0, counts())
                if not {"planner_state_get", "planner_loads_get"} <= set(pl.rpcs):
                    problems.append(f"it didn't read through the getters (it called {', '.join(sorted(set(pl.rpcs))) or 'nothing'})")
                step(not problems, "sign in as test staff through the planner's own form (live address; it read planner_state_get() and "
                                   "planner_loads_get(), and opening it saved nothing)", problems)
                signed_in = True
            except Exception as e:
                step(False, "sign in as test staff through the planner's own form", [why(e)] + pl.errors[:3])
                signed_in = False
            if signed_in:
                for label, save in (("tick a to-do", tick_todo), ("change a plan card's title", retitle_plan), ("type a load", type_load)):
                    e0 = len(pl.errors)
                    try:
                        label, problems = await save(pl, read_doc(), read_loads(), read_old(), counts())
                    except Exception as e:
                        problems = [why(e)]
                    problems += pl.errors[e0:]
                    step(not problems, label, problems)
                sent = sorted(set(pl.rpcs) & set(SAVES))
                step(set(sent) == {"planner_state_put", "save_loads"},
                     f"the planner saved only through the adapter ({', '.join(sent) or 'nothing'})", [f"it called: {', '.join(sorted(set(pl.rpcs)))}"])
            await asyncio.sleep(0.5)
            await pl.close()

            if not BEFORE:
                try:
                    problems, since = frozen_rows(env, staff)
                except Exception as e:
                    problems, since = [why(e)], "?"
                step(not problems, f"the old rows refuse a direct write (\"frozen since {since}; write to the tables\" as postgres; refused "
                                   "as staff through the data API) and stay as they were", problems)
                try:
                    label, problems = await two_tabs(p, port, env, facts, lib, staff)
                except Exception as e:
                    label, problems = "two tabs", [why(e)]
                step(not problems, label, problems)
                try:
                    label, problems, pv = await preview(p, port, env, facts, lib, staff)
                    planners.append(pv)
                except Exception as e:
                    label, problems = "a preview address saves nothing", [why(e)]
                step(not problems, label, problems)

    if not BEFORE:
        for label, check in (("guard: an account that isn't staff reads no planner_state rows, and its writes are refused", lambda: guard(env, *other)),
                             (f"guard: signed out and not staff, the {len(NEW_TABLES) + len(CAPTURE_TABLES) + len(JOB_TABLES)} new tables and "
                              f"{len(NEW_VIEWS) + len(CAPTURE_VIEWS) + len(JOB_VIEWS)} views (the capture's and job_runs included) read no rows, "
                              "and adding a row to each is refused", lambda: guard_new_tables(env, *other)),
                             ("the adapter's read side: signed out and not staff, planner_state_get(), planner_state_version() and "
                              "planner_loads_get() are refused; staff get what psql gets", lambda: guard_getters(env, staff, other)),
                             ("the adapter's write side: signed out and not staff, " + ", ".join(f"{w}()" for w in WRITERS)
                              + " are refused; staff put and remove an item through the data API, logged as planner", lambda: guard_writers(env, staff, other))):
            try:
                problems = check()
            except Exception as e:
                problems = [why(e)]
            step(not problems, label, problems)
        async with async_playwright() as p:
            try:
                label, problems, old = await rollback(p, env, lib, staff)
                if old:
                    planners.append(old)
            except Exception as e:
                label, problems = "rollback", [why(e)]
            step(not problems, label, problems)

    outside = sorted({h for x in planners for h in x.outside})
    stopped = ", ".join(sorted({h for x in planners for h in x.stopped})) or "nothing"
    problems = (["reached: " + ", ".join(outside)] if outside else []) + \
               ([] if pl.copy and pl.served else ["the planner never reached the copy, or never loaded the served library"])
    step(not problems, f"nothing went outside ({sum(x.copy for x in planners)} requests answered by the copy, the library served from npm, "
                       f"{sum(x.local for x in planners)} from the local server; stopped: {stopped})", problems)
    print(f"\n{len(failures)} real-saves step(s) failed" if failures else "\nreal saves: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
