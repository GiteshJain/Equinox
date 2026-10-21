"""Runs scripts/scanner/gscan.py, unchanged, on saved pages instead of the game, and prints what it would send.

tests/capture_scan_test.mjs runs it to compare the capture's scan (capture/capture_all.user.js 1.5, spec
docs/specs/2026-10-21-scan-in-capture.md §3) with gscan.py's own rules on the same pages. Nothing reaches the network or
the home folder: gscan.py's page fetcher (gfetch.get) answers from the pages given, its database calls are recorded, its
working files (~/ents.json, ~/apid.json, the key files) live in memory, and its pauses take no time. A page not given
fails as a page the game didn't answer, which gscan.py logs and skips.

Usage: python3 -I tests/gscan_reference.py < pages.json
  pages.json: {"scan": <scan id>, "pages": {"<full game address>": "<the page's HTML>", ...}}
Prints JSON: {"ents": {game ID: name}, "apid": {code: id}, "sent": [{"kind", "payload"}], "log": [lines]}, gscan.py's
airlines phase and then its airports phase, as Claude runs them (python3 gscan.py airlines <scan>; ... airports <scan>).
"""
import builtins, contextlib, io, json, os, pathlib, sys, time, types, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
GSCAN = ROOT / "scripts" / "scanner" / "gscan.py"
HOME = "/home/claude/"   # the folder gscan.py's paths are written for

job = json.load(sys.stdin)
pages, scan = job["pages"], int(job["scan"])
files = {HOME + ".sb_anon": "anon-placeholder", HOME + ".ingest_secret": "secret-placeholder"}
sent, log = [], []


def get(url):
    if url not in pages:
        raise OSError("not saved: " + url)
    return pages[url]


class MemoryFile(io.StringIO):
    def __init__(self, path, mode):
        super().__init__("" if "w" in mode else files[path])
        self.path, self.mode = path, mode

    def write(self, s):   # kept as it's written: gscan.py never closes its files
        n = super().write(s)
        if "w" in self.mode:
            files[self.path] = self.getvalue()
        return n


real_open, real_exists = builtins.open, os.path.exists


def fake_open(path, mode="r", *a, **k):
    if str(path).startswith(HOME):
        if "r" in mode and str(path) not in files:
            raise FileNotFoundError(path)
        return MemoryFile(str(path), mode)
    return real_open(path, mode, *a, **k)


class Answer:
    def __init__(self, body):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self):
        return self.body


def fake_urlopen(req, timeout=None):
    body = json.loads(req.data)
    sent.append({"kind": body["p_kind"], "payload": body["p_payload"]})
    return Answer(b'{"ok": true}')


gfetch = types.ModuleType("gfetch")
gfetch.get = get
sys.modules["gfetch"] = gfetch
builtins.open = fake_open
os.path.exists = lambda p: (str(p) in files) if str(p).startswith(HOME) else real_exists(p)
urllib.request.urlopen = fake_urlopen
time.sleep = lambda s: None

source = GSCAN.read_text()
out = io.StringIO()
for phase in ("airlines", "airports"):
    sys.argv = ["gscan.py", phase, str(scan)]
    with contextlib.redirect_stdout(out):
        try:
            exec(compile(source, str(GSCAN), "exec"), {"__name__": "__main__"})
        except SystemExit:
            pass
builtins.open, os.path.exists = real_open, real_exists
log = [line.split(" ", 1)[1] if " " in line else line for line in out.getvalue().splitlines()]   # without the clock
print(json.dumps({"ents": json.loads(files.get(HOME + "ents.json", "{}")), "apid": json.loads(files.get(HOME + "apid.json", "{}")),
                  "sent": sent, "log": log}))
