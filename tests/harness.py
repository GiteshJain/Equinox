"""Shared setup for the automatic checks (decision #9).

- serve(): serves web/ (or another copy of it, root=) on a local port the way Cloudflare does, in a background thread:
  the root's own _redirects rules, read from the file and applied as Cloudflare applies them (the first that matches
  wins; * matches anything and :splat repeats it; a 301 or 302 answers with the address, keeping the query; a 200
  serves the file at its target without looking at the rules again), then a folder's index.html, a file, or the home
  page for any other unknown address (the site has no 404.html). /planner/ and everything below it give the planner's
  page (web/app/index.html, built by `npm run build`); /planner/next/... redirects to the same address under /planner/,
  and /planner/old/ (the old planner's address, removed with it in the clean-up, build pull request 14) to /planner/.
- sample(): the frozen test sample (the newest tests/fixtures/sample_*.json.gz), for the website check;
  schedule_fixture(): the schedule check's answer for the saved Kingfisher page; settle(): waits for a page to go quiet.
Nothing here touches the real database or the game.
"""
import contextlib, functools, gzip, http.server, json, pathlib, socket, threading

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
FIX = ROOT / "tests" / "fixtures"
SAMPLE_FILE = sorted(FIX.glob("sample_*.json.gz"))[-1]
NEW_PLANNER = "/planner/"   # the planner's address (#18)


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


LIVE_HOST = "equinox-alliance.com"   # the live address, mapped to the local server by the tests that open the planner


async def settle(pg, ms=700):
    with contextlib.suppress(Exception):
        await pg.wait_for_load_state("networkidle", timeout=10000)
    await pg.wait_for_timeout(ms)
