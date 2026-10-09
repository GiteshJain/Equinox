"""Real saves (decision #17): the pull request's own planner, signed in as a test staff user, saves for real into a full
local copy of Supabase restored from last night's backup, and the tables are read back afterwards.

Run by database/rehearse.sh as its last step, once the restore, the pending changes and the SQL tests have passed. It
needs that copy (Docker and the backup), so it isn't part of tests/run_all.sh.

1. Test users: two accounts made through the local sign-in's admin API, with throwaway passwords made here: one added
   to planner_users (staff), one not. They exist only in the copy.
2. The planner opens at its live address (mapped to a local server, as tests/harness.py does), so it saves. Every
   request for the live Supabase host is answered by the local copy instead, with the live public key swapped for the
   local one. The planner's Supabase library, the exact version it names, comes from npm and is served in place of the
   CDN copy. Any other outside request is stopped.
3. It signs in through the planner's own form as staff (opening it must save nothing), then saves three things, one at
   a time, and after each reads the tables with psql:
   - ticks the first open to-do as done: planner_state changes only in that to-do's done and doneAt;
   - changes the first plan card's title. The planner has no field for that, so it goes through the planner's own
     backup screen (Reference > Data: export, change the title, import), which saves the whole document:
     planner_state changes only in that title;
   - types a load for one flight on the Review page (Manual entry > Loads by hand, saved through save_loads()), on the
     latest recent day with no loads yet: that month's planner_loads row has the typed load for that day and flight,
     and every other day and month is unchanged.
   savedAt and version are bookkeeping and may change, and saved_at must move forward. A missing key counts as null.
   After each save the other planner table is untouched and no table's row count changed (database/backup/counts.sql).
4. The guard: signed in as the account that isn't staff, through the data API directly, planner_state reads no rows,
   and the planner's own write (an upsert) and save_loads() are refused; the tables don't change.
5. Nothing went outside: no request reached the live Supabase host or any address other than the local server, the
   local data API and the served library.

Prints one line per step (ok/FAIL), and no row contents beyond ids and the names of the fields that changed, because the
log is posted on the pull request. Never prints the local keys or the test passwords.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV (a file holding `supabase status -o env`), LOCAL_DB_URL and
SECRET_TABLES. Usage: python3 tests/real_saves_test.py
"""
import asyncio, datetime, json, os, re, secrets, subprocess, sys, tarfile, tempfile, time, urllib.error, urllib.request
from pathlib import Path
from urllib.parse import urlsplit
from harness import ROOT, WEB, LIVE_HOST, serve, settle, go
from playwright.async_api import async_playwright

PLANNER = WEB / "planner" / "index.html"
COUNTS = ROOT / "database" / "backup" / "counts.sql"
DB = os.environ.get("LOCAL_DB_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
SKIP = os.environ.get("SECRET_TABLES", "public.ingest_secret,public.capture_keys,public.report_access")
LOAD = 61                         # the load typed for one flight (under 95%, so the planner keeps it)
BOOKKEEPING = {"savedAt", "version"}
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
def planner_facts():
    html = PLANNER.read_text()
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


def read_state():
    out = psql("select json_build_object('json', json, 'saved_at', saved_at) from public.planner_state where id = 'main'").strip()
    if not out:
        raise RuntimeError("the copy has no planner_state row")
    row = json.loads(out)
    return {"doc": json.loads(row["json"]), "raw": row["json"], "saved_at": int(row["saved_at"])}


def read_loads():
    out = psql("select coalesce(json_object_agg(month, json_build_object('json', json, 'saved_at', saved_at)), '{}') "
               "from public.planner_loads").strip()
    return {m: {"doc": json.loads(r["json"]), "raw": r["json"], "saved_at": int(r["saved_at"])} for m, r in json.loads(out).items()}


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


def count_changes(before, after, allow=()):
    return [f"row count changed: {t}: {before.get(t, 'none')} -> {after.get(t, 'none')}"
            for t in sorted(set(before) | set(after)) if before.get(t) != after.get(t) and t not in allow]


def months_changed(a, b, skip=()):
    return [m for m in sorted(set(a) | set(b)) if m not in skip and a.get(m) != b.get(m)]


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
        self.served = 0          # times the planner's library was served from npm's copy
        self.local = 0           # requests to the local server
        self.stopped = set()     # hosts whose requests were stopped
        self.outside = []        # responses that came over the network from anywhere but the local server: must stay empty
        self.errors = []         # page errors and console errors, as they happen
        self.dialogs = []        # alerts the planner showed (dismissed)
        self.b = self.api = None

    async def open(self):
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
              if m.type == "error" and "Failed to load resource" not in m.text else None)
        pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await pg.goto(f"http://{LIVE_HOST}:{self.port}/planner/")
        return pg

    async def route(self, r):
        req, u = r.request, r.request.url
        live, host = self.f["live_url"], urlsplit(r.request.url)
        if u.startswith(live + "/"):
            self.copy += 1
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

    async def sign_in(self, email, password):
        pg = self.pg
        await pg.wait_for_selector("#g-email", timeout=30000)
        await pg.fill("#g-email", email)
        await pg.fill("#g-pass", password)
        await pg.click("#g-in")
        # it reloads once after signing in (so the route research loads with the session), then reads the copy
        await pg.wait_for_function("""() => window.__eqDataLoaded === true && window.__eqPreview === false
            && (!document.getElementById('gate') || document.getElementById('gate').style.display === 'none')
            && /cloud/.test((document.getElementById('savestate') || {}).textContent || '')""", timeout=60000)
        await settle(pg, 1500)


# ---------- the three saves ----------
async def tick_todo(pl, s0, l0, n0):
    todos = s0["doc"].get("todos") or []
    i = next((i for i, t in enumerate(todos) if isinstance(t, dict) and not t.get("done")), None)
    if i is None:
        return "tick a to-do", ["last night's data has no open to-do to tick"]
    tid = todos[i].get("id")
    name = f"tick a to-do ({tid})"
    await go(pl.pg, "home")
    k = await pl.pg.evaluate("id => [...document.querySelectorAll('input[data-tododone]')].findIndex(x => x.dataset.tododone === id)", tid)
    if k < 0:
        return name, ["the first open to-do isn't on Home"]
    await pl.pg.locator("input[data-tododone]").nth(k).click()
    await wait_for(read_state, lambda s: s["saved_at"] > s0["saved_at"])
    await settle(pl.pg, 800)
    s1, l1, n1 = read_state(), read_loads(), counts()
    want = {f"todos[{i}].done", f"todos[{i}].doneAt"}
    diff = changed(s0["doc"], s1["doc"])
    t1 = (s1["doc"].get("todos") or [])[i] if len(s1["doc"].get("todos") or []) > i else {}
    problems = []
    if s1["saved_at"] <= s0["saved_at"]:
        problems.append("planner_state wasn't saved (saved_at didn't move)")
    if t1.get("id") != tid or t1.get("done") is not True or not t1.get("doneAt"):
        problems.append(f"the to-do isn't saved as done (done: {t1.get('done')!r}, doneAt set: {bool(t1.get('doneAt'))})")
    other = [d for d in diff if d not in want | BOOKKEEPING]
    if other:
        problems.append("other fields changed in planner_state: " + ", ".join(other[:12]))
    if months_changed(l0, l1):
        problems.append("planner_loads changed: " + ", ".join(months_changed(l0, l1)))
    problems += count_changes(n0, n1)
    return f"{name}: {', '.join(d.split('.', 1)[1] for d in diff if d in want) or 'nothing'} changed", problems


async def retitle_plan(pl, s0, l0, n0):
    plans = s0["doc"].get("plans") or {}
    if not plans:
        return "change a plan card's title", ["last night's data has no plan card"]
    reg = next(iter(plans))
    name = f"change a plan card's title ({reg})"
    pg = pl.pg
    await go(pg, "ref")
    if not await pg.evaluate("(document.querySelector('details.rsec[data-rsec=\"Data\"]') || {}).open === true"):
        await pg.click("details.rsec[data-rsec='Data'] > summary")
        await settle(pg, 300)
    async with pg.expect_download(timeout=30000) as dl:
        await pg.click("#exp")
    exported = json.loads(Path(await (await dl.value).path()).read_text())
    if reg not in (exported.get("plans") or {}):
        return name, ["the planner's export has no such plan card"]
    title = f"{plans[reg].get('title') or reg} · real-saves check {secrets.token_hex(3)}"
    exported["plans"][reg]["title"] = title
    await pg.evaluate("t => { document.getElementById('io').value = t; }", json.dumps(exported, indent=1))
    await pg.click("#imp")
    await wait_for(read_state, lambda s: s["saved_at"] > s0["saved_at"])
    await settle(pg, 800)
    s1, l1, n1 = read_state(), read_loads(), counts()
    want = {f"plans.{reg}.title"}
    diff = changed(s0["doc"], s1["doc"])
    problems = []
    if await pg.evaluate("(document.getElementById('io') || {}).value || ''") != "Imported.":
        problems.append("the planner didn't take its own export back")
    if s1["saved_at"] <= s0["saved_at"]:
        problems.append("planner_state wasn't saved (saved_at didn't move)")
    if ((s1["doc"].get("plans") or {}).get(reg) or {}).get("title") != title:
        problems.append("the new title isn't in planner_state")
    other = [d for d in diff if d not in want | BOOKKEEPING]
    if other:
        problems.append("other fields changed in planner_state: " + ", ".join(other[:12]))
    if months_changed(l0, l1):
        problems.append("planner_loads changed: " + ", ".join(months_changed(l0, l1)))
    problems += count_changes(n0, n1)
    return f"{name}: {', '.join(d.split('.', 2)[2] for d in diff if d in want) or 'nothing'} changed", problems


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


async def type_load(pl, s0, l0, n0):
    pg, d0 = pl.pg, len(pl.dialogs)
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
    await pg.click("#lfsave")
    await wait_for(read_loads, lambda l: mo in l and (mo not in l0 or l[mo]["saved_at"] > l0[mo]["saved_at"]))
    await settle(pg, 800)
    l1, s1, n1 = read_loads(), read_state(), counts()
    problems = []
    if mo not in l1 or (mo in l0 and l1[mo]["saved_at"] <= l0[mo]["saved_at"]):
        problems.append("planner_loads wasn't saved (saved_at didn't move)")
    else:
        a, b = (l0.get(mo) or {"doc": {}})["doc"], l1[mo]["doc"]
        entry = b.get(iso) if isinstance(b.get(iso), dict) else {}
        if entry.get("f") != {key: LOAD} or entry.get("done") is not True:
            problems.append(f"the day isn't saved as typed (flights saved: {', '.join(sorted(entry.get('f') or {})) or 'none'}; "
                            f"done: {entry.get('done')!r})")
        other = [d for d in sorted(set(a) | set(b)) if d not in (iso, "__savedAt") and a.get(d) != b.get(d)]
        if other:
            problems.append("other days changed: " + ", ".join(other[:12]))
    if months_changed(l0, l1, skip={mo}):
        problems.append("other months changed: " + ", ".join(months_changed(l0, l1, skip={mo})))
    if s1["raw"] != s0["raw"] or s1["saved_at"] != s0["saved_at"]:
        problems.append("planner_state changed: " + (", ".join(changed(s0["doc"], s1["doc"])[:12]) or "saved_at only"))
    new_month = mo not in l0 and int(n1.get("public.planner_loads", 0)) == int(n0.get("public.planner_loads", 0)) + 1
    problems += count_changes(n0, n1, allow={"public.planner_loads"} if new_month else ())
    problems += [f"the planner said: {m}" for m in pl.dialogs[d0:]]
    return name, problems


def guard(env, email, password):
    s0, l0, n0 = read_state(), read_loads(), counts()
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
    month = (sorted(l0) or [datetime.date.today().isoformat()[:7]])[-1]
    code, _ = http(env, "POST", "/rest/v1/rpc/save_loads", {"p_month": month, "p_days": {}}, token=token)
    if code not in (401, 403):
        problems.append(f"save_loads() wasn't refused (answer {code})")
    s1, l1, n1 = read_state(), read_loads(), counts()
    if s1 != s0:
        problems.append("planner_state changed")
    if l1 != l0:
        problems.append("planner_loads changed")
    return problems + count_changes(n0, n1)


async def main():
    facts = planner_facts()
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

    with serve() as port:
        async with async_playwright() as p:
            pl = Planner(p, port, env, facts, lib)
            try:
                s0, l0 = read_state(), read_loads()
                await pl.open()
                await pl.sign_in(*staff)
                s, l = read_state(), read_loads()
                problems = list(pl.errors)
                if s != s0:
                    problems.append("opening the planner saved planner_state by itself: " + (", ".join(changed(s0["doc"], s["doc"])[:12]) or "saved_at"))
                if months_changed(l0, l):
                    problems.append("opening the planner changed planner_loads: " + ", ".join(months_changed(l0, l)))
                step(not problems, "sign in as test staff through the planner's own form (live address; opening it saved nothing)", problems)
                signed_in = True
            except Exception as e:
                step(False, "sign in as test staff through the planner's own form", [why(e)] + pl.errors[:3])
                signed_in = False
            if signed_in:
                for label, save in (("tick a to-do", tick_todo), ("change a plan card's title", retitle_plan), ("type a load", type_load)):
                    e0 = len(pl.errors)
                    try:
                        s, l, n = read_state(), read_loads(), counts()
                        label, problems = await save(pl, s, l, n)
                    except Exception as e:
                        problems = [why(e)]
                    problems += pl.errors[e0:]
                    step(not problems, label, problems)
            await asyncio.sleep(0.5)
            await pl.close()

    try:
        problems = guard(env, *other)
    except Exception as e:
        problems = [why(e)]
    step(not problems, "guard: an account that isn't staff reads no planner_state rows, and its writes are refused", problems)

    stopped = ", ".join(sorted(pl.stopped)) or "nothing"
    problems = (["reached: " + ", ".join(sorted(set(pl.outside)))] if pl.outside else []) + \
               ([] if pl.copy and pl.served else ["the planner never reached the copy, or never loaded the served library"])
    step(not problems, f"nothing went outside ({pl.copy} requests answered by the copy, the library served from npm, "
                       f"{pl.local} from the local server; stopped: {stopped})", problems)
    print(f"\n{len(failures)} real-saves step(s) failed" if failures else "\nreal saves: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
