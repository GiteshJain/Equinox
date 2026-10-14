"""Shared setup for the automatic checks (decision #9).

- serve(): serves web/ (or another copy of it, root=) on a local port the way Cloudflare does, in a background thread:
  the root's own _redirects rules, read from the file and applied as Cloudflare applies them (the first that matches
  wins; * matches anything and :splat repeats it; a 301 or 302 answers with the address, keeping the query; a 200
  serves the file at its target without looking at the rules again), then a folder's index.html, a file, or the home
  page for any other unknown address (the site has no 404.html). Since the switch (#18 build pull request 13): /planner/
  and everything below it give the new planner's page (web/app/index.html, built by `npm run build`), /planner/next/...
  redirects to the same address under /planner/, and /planner/old/ gives the old planner (web/planner/index.html).
- open_planner(): opens the old planner (at /planner/old/ since the switch) in headless Chromium with the database
  replaced by the frozen sample
  (tests/fixtures/sample_*.json.gz), the clock frozen at the sample's moment, and every outside request blocked.
  live=True opens it at equinox-alliance.com (mapped to the local server) so it behaves as the live planner; False
  opens it at 127.0.0.1, which is a look-only preview (#8).
Nothing here touches the real database or the game.
"""
import contextlib, functools, gzip, http.server, json, pathlib, socket, threading

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
FIX = ROOT / "tests" / "fixtures"
SAMPLE_FILE = sorted(FIX.glob("sample_*.json.gz"))[-1]
# The planners' addresses since the switch (#18 build pull request 13): the new planner at /planner/, the old one (the way
# back) at /planner/old/.
NEW_PLANNER = "/planner/"
OLD_PLANNER = "/planner/old/"


@functools.lru_cache(None)
def sample():
    return json.load(gzip.open(SAMPLE_FILE))


@functools.lru_cache(None)
def schedule_fixture():
    """The schedule check's answer for the saved Kingfisher page (made by running the real function on it)."""
    p = FIX / "schedule_113.expected.json"
    return json.loads(p.read_text()) if p.exists() else {"flights": []}


def redirect_rules(root=WEB):
    """The rules in the root's _redirects, in order: (source, target, status)."""
    f = pathlib.Path(root) / "_redirects"
    rules = []
    for line in (f.read_text().splitlines() if f.is_file() else []):
        parts = line.split()
        if not parts or parts[0].startswith("#"):
            continue
        rules.append((parts[0], parts[1], int(parts[2]) if len(parts) > 2 else 302))
    return rules


def splat_of(source, path):
    """What a rule's * matched in the address (the empty string for a source without one), or None if it doesn't match."""
    if "*" not in source:
        return "" if path == source else None
    head, tail = source.split("*", 1)
    if path.startswith(head) and path.endswith(tail) and len(path) >= len(head) + len(tail):
        return path[len(head):len(path) - len(tail)]
    return None


def resolve(rules, path):
    """Where Cloudflare sends an address: ("redirect", status, target), ("serve", target) for a 200 rule's target, or
    ("file", path) when no rule matches."""
    for source, target, status in rules:
        splat = splat_of(source, path)
        if splat is None:
            continue
        to = target.replace(":splat", splat)
        return ("serve", to) if status == 200 else ("redirect", status, to)
    return ("file", path)


class _Handler(http.server.SimpleHTTPRequestHandler):
    root = WEB
    rules = ()

    def __init__(self, *a, **k):
        super().__init__(*a, directory=str(self.root), **k)

    def log_message(self, *a):
        pass

    def do_GET(self):
        path, _, query = self.path.partition("?")
        how = resolve(self.rules, path)
        if how[0] == "redirect":                                # a 301 or 302 rule: the address, with the query kept
            self.send_response(how[1]); self.send_header("Location", how[2] + ("?" + query if query else "")); self.end_headers(); return
        if how[0] == "file" and path.endswith("/index.html"):   # Cloudflare sends a page's index.html to its folder (308)
            self.send_response(308); self.send_header("Location", path[:-len("index.html")]); self.end_headers(); return
        path = how[1]                                           # a 200 rule's target, or the address itself
        if path.endswith("/") and (self.root / path.lstrip("/") / "index.html").is_file():
            self.path = path + "index.html"                     # a folder's page, e.g. /app/ or /planner/
        elif (self.root / path.lstrip("/")).is_file():
            self.path = path
        elif "." not in path.rsplit("/", 1)[-1]:
            self.path = "/index.html"                           # no 404.html: Cloudflare serves the home page
        else:
            self.path = path
        return super().do_GET()


@contextlib.contextmanager
def serve(root=WEB):
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]
    handler = type("Handler", (_Handler,), {"root": pathlib.Path(root), "rules": tuple(redirect_rules(root))})
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True); t.start()
    try:
        yield port
    finally:
        httpd.shutdown()


# A stand-in for the Supabase client: answers the planner's reads from the sample and records every write. Since the
# switch-over (#13, pull request 9) the planner reads its document and loads through the adapter's getters
# (planner_state_get, planner_loads_get, planner_state_version) and saves through planner_state_put and save_loads, so
# those are answered here; the old rows' tables are no longer read.
STUB = r"""
(() => {
  const S = window.__SAMPLE;
  const T = Object.assign({}, S.tables);
  const SAVED = S.planner_state.savedAt || 1;
  const READS = {
    site_public: () => S.site_public,
    is_planner_user: () => true,
    planner_state_get: () => ({ json: JSON.stringify(S.planner_state), saved_at: SAVED }),
    planner_loads_get: () => S.planner_loads,
    planner_state_version: () => SAVED,
  };
  const ANSWERS = {   // what the database answers a save with
    planner_state_put: () => ({ saved_at: Date.now(), applied: 1, skipped: 0, reload: false, skipped_items: [] }),
  };
  window.__WRITES = [];
  const write = (what) => { window.__WRITES.push(what); const a = what.rpc && ANSWERS[what.rpc]; return Promise.resolve({ data: a ? a() : null, error: null }); };
  function from(t) {
    let rows = (T[t] || []).slice();
    const q = {
      select() { return q; }, gte() { return q; }, lte() { return q; }, gt() { return q; }, lt() { return q; },
      like() { return q; }, ilike() { return q; }, in() { return q; },   // the sample is already cut to these filters
      eq(c, v) { rows = rows.filter(r => !(c in r) || String(r[c]) === String(v)); return q; },
      order(c, o) { const a = !(o && o.ascending === false) ? 1 : -1; rows.sort((x, y) => (x[c] > y[c] ? a : x[c] < y[c] ? -a : 0)); return q; },
      limit(n) { rows = rows.slice(0, n); return q; },
      range(a, b) { rows = rows.slice(a, b + 1); return q; },
      async maybeSingle() { return { data: rows[0] || null, error: null }; },
      async single() { return { data: rows[0] || null, error: null }; },
      then(res, rej) { return Promise.resolve({ data: rows, error: null }).then(res, rej); },
      upsert(row) { return write({ t, op: "upsert", row }); }, insert(row) { return write({ t, op: "insert", row }); },
      update(row) { return write({ t, op: "update", row }); }, delete() { return write({ t, op: "delete" }); },
    };
    return q;
  }
  const session = { access_token: "t", user: { email: "staff@example.com" } };
  const client = {
    from,
    rpc: async (n, args) => READS[n] ? { data: READS[n](), error: null } : write({ rpc: n, args }),
    storage: { from: (b) => ({ upload: (p) => write({ upload: p }), remove: (p) => write({ remove: p }),
      getPublicUrl: (p) => ({ data: { publicUrl: "https://example.com/" + p } }) }) },
    auth: { getSession: async () => ({ data: { session }, error: null }), getUser: async () => ({ data: { user: session.user }, error: null }),
      onAuthStateChange() { return { data: { subscription: { unsubscribe() {} } } }; },
      signOut: async () => ({}), signInWithPassword: async () => ({ data: { session }, error: null }), signUp: async () => ({ data: {}, error: null }) },
  };
  window.supabase = { createClient: () => client };
})();
"""

LIVE_HOST = "equinox-alliance.com"


async def open_planner(p, port, live=True, path=OLD_PLANNER, width=1440, height=1000, stored=None, tables=None):
    """Returns (browser, page, errors). errors collects page errors and console errors as they happen. stored: a copy
    of the planner to leave in the browser's storage before it opens (as a tab that couldn't reach the cloud leaves it).
    tables: tables the stand-in answers with instead of the sample's (e.g. {"job_runs": [...]}), for one page."""
    b = await p.chromium.launch(args=[f"--host-resolver-rules=MAP {LIVE_HOST} 127.0.0.1:{port}"])
    ctx = await b.new_context(viewport={"width": width, "height": height}, timezone_id="UTC", locale="en-US")
    await ctx.add_init_script("localStorage.setItem('gander-auth', JSON.stringify({access_token:'t'}));")
    if stored is not None:   # once per tab, before the planner's own scripts
        await ctx.add_init_script("if (!sessionStorage.getItem('stored-copy')) { sessionStorage.setItem('stored-copy', '1'); "
                                  f"localStorage.setItem('gander-planner', {json.dumps(json.dumps(stored))}); }}")
    pg = await ctx.new_page()
    errors = []
    pg.on("pageerror", lambda e: errors.append("page error: " + str(e)[:300]))
    pg.on("console", lambda m: errors.append("console: " + m.text[:300]) if m.type == "error" and "Failed to load resource" not in m.text else None)
    S = sample()
    if tables:
        S = dict(S, tables=dict(S["tables"], **tables))
    stub_js = "window.__SAMPLE=" + json.dumps(S) + ";" + STUB
    data_rows = json.dumps([{"value": S["planner_data"]}])

    async def route(r):
        u = r.request.url
        if "supabase" in u and u.endswith(".js"):
            await r.fulfill(body=stub_js, content_type="application/javascript")
        elif "/rest/v1/planner_data" in u:
            await r.fulfill(body=data_rows, content_type="application/json")
        elif "/api/game-schedule" in u:
            body = schedule_fixture() if "113" in u else {"flights": []}
            await r.fulfill(body=json.dumps(body), content_type="application/json")
        elif f":{port}/" in u or u.startswith("data:") or u.startswith("blob:"):
            await r.continue_()
        else:
            await r.abort()   # fonts, map tiles, the real database: nothing leaves the test
    await pg.route("**/*", route)
    await pg.clock.set_fixed_time(S["frozen_at"])
    host = LIVE_HOST if live else "127.0.0.1"
    await pg.goto(f"http://{host}:{port}{path}")
    await settle(pg)
    return b, pg, errors


async def settle(pg, ms=700):
    with contextlib.suppress(Exception):
        await pg.wait_for_load_state("networkidle", timeout=10000)
    await pg.wait_for_timeout(ms)


async def go(pg, view):
    await pg.evaluate(f"document.querySelector('nav button[data-view={view}]').click()")
    await settle(pg)
