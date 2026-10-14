"""Every kind of save the new planner makes, through its own controls, on the rehearsal's copy, against the rows recorded
for it (decision #18, build pull request 14, the clean-up: what replaces the side by sides' saves).

The side by sides (build pull requests 5 to 13) saved through each screen's own controls in the new planner and in the old
one from the same copy, and proved both wrote the same rows. The old planner is gone, so the new planner's rows are kept as
recorded answers instead: tests/fixtures/planner_saves.expected.json, recorded in the clean-up's first rehearsal, where
this test ran after every side by side had passed on the same copy (the pull request says which run). A change to what any
save writes fails here, so it has to be meant: update the recorded answer in the same pull request and say why.

Run by database/rehearse.sh after tests/planner_next_test.py, on the copy with every pending change. It needs the copy,
so it isn't part of tests/run_all.sh. Like planner_next_test.py: a test staff user made through the copy's sign-in, the
pull request's own new planner (web/app/) at its live address with the live Supabase host answered by the copy, its clock
frozen at the copy's latest capture plus one hour, and nothing goes outside. /api/game-schedule is answered by the test
(the saved sample tests/fixtures/schedule_113.expected.json, and the airline's own flights with a few changes), and the
photo bucket in the browser (the copy has no storage service).

Each save, through the screen's own controls, one action at a time:
  Home: add a to-do with two steps; tick it; add another and delete it; dismiss an item of needs attention; show again.
  Routes: add a route; edit its stars; edit its market; add a frequency; type its days and four times (each box one
    action); change its departure; delete it; remove the route; change an airport's UTC offset; put it back.
  Tails: add a tail; change its maintenance gap; change its base; remove it; remove a delivery (one made for the test);
    file an arrived aircraft (made for the test) from its plan card with the game matching, then again with it
    differing (File with the game's times).
  Check: the game check's fix one, fix all and add a flight; Mark checked; Keep as is; Show again; Refitted to; log an order.
  Review: cash and fixed costs; loads typed; loads pasted with the day marked complete; + fare plan; remove.
  Interline: a status; a note.
  Reference: a bank time; a constant; a type's minimum turn; Add config; a night ban; a removed route restored; a time zone.
  Photos: a destination photo uploaded.
What the test makes for a save (an aircraft to file, a delivery to remove, a check made due, a layout to refit, a to-do to
tick) is made with psql as the test, never through the planner, so it isn't part of the answer.

Each save's answer, compared with the recorded one:
  - sent: what the planner sent, one line per change of its planner_save() call ("planner_save todos update done,done_at":
    the table, the operation and the columns it sets), per other database call ("rpc save_loads p_days,p_month"), and per
    file sent to the bucket ("upload airports/<code>-<time>.jpg image/jpeg JPEG 320x200"), with how many of each;
  - written: the change log's rows for it ("todos update done,done_at": an update with the columns that changed;
    "todo_items insert": a row added), with how many of each; for a photo, the website's row (site_content media);
  - logged: who the change log names: "planner tab" (the tab's ID) or "planner save_loads".
A count that depends on the night's data is recorded as "*" (shown again: every dismissal there is), and a save whose
columns depend on it (an airport's offset moving its flights, which can cross midnight) is recorded without them.
A save that can't be tried on the night's copy (no route offering a fare plan) is reported as not tried, not failed.

With RECORD_SAVES=1 a save with no recorded answer passes and says so; every answer found goes to SAVES_OUT_DIR (the run's
planner-saves artifact) either way, as planner_saves.json, ready to be committed as the recorded answers.

Prints table, column and screen names, registrations, codes and counts, never values from the rows, since the log is
posted on the pull request. Never prints the local keys or the test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL, SECRET_TABLES, SAVES_OUT_DIR, RECORD_SAVES.
Usage: python3 tests/planner_saves_test.py
"""
import asyncio, json, os, re, secrets, struct, subprocess, sys, time, zlib
from collections import Counter
from pathlib import Path
from urllib.parse import parse_qs, quote, urlencode, urlsplit
from harness import FIX, ROOT, serve, settle
from playwright.async_api import async_playwright
from local_copy import WORLD, local_env, log_since, marks, moment as copy_moment, one, psql, staff_user, wait_for, why
import planner_next_test as pn

EXPECTED = FIX / "planner_saves.expected.json"
OUT_DIR = os.environ.get("SAVES_OUT_DIR")
RECORD = os.environ.get("RECORD_SAVES") == "1"
failures, found, untried = [], {}, []
started = time.monotonic()


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:16]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


def expected():
    try:
        return json.loads(EXPECTED.read_text())["saves"]
    except FileNotFoundError:
        return {}


# ---------- the new planner, with the game and the photo bucket answered by the test, and what it sends recorded
class Saver(pn.Planner):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.sent = []          # every write it sent: {"rpc": name, "args": {...}} or {"upload": ...}
        self.game = {}          # the game's answer by game ID (/api/game-schedule); None for a 502
        self.schedule = None    # one answer for every airline (filing), when set

    async def open(self, *a, **k):
        pg = await super().open(*a, **k)
        await pg.route("**/api/game-schedule*", self.answer_game)
        await self.ctx.route("**/storage/v1/**", self.bucket)
        return pg

    async def forward(self, r):
        req = r.request
        if req.method == "POST" and req.url.startswith(self.f["live_url"] + "/rest/v1/rpc/"):
            name = urlsplit(req.url).path.rsplit("/", 1)[-1]
            if name != "is_planner_user":
                try:
                    args = json.loads(req.post_data or "{}")
                except Exception:
                    args = {}
                self.sent.append({"rpc": name, "args": args})
        await super().forward(r)

    async def answer_game(self, r):
        if self.schedule is not None:
            await r.fulfill(body=json.dumps(self.schedule), content_type="application/json")
            return
        u = parse_qs(urlsplit(r.request.url).query).get("u", [""])[0]
        m = re.search(r"enterprises/(\d+)", u) or re.match(r"^(\d+)$", u)
        body = self.game.get(m[1]) if m else None
        if body is None:
            await r.fulfill(status=502, body=json.dumps({"error": "The game answered 502."}), content_type="application/json")
        else:
            await r.fulfill(body=json.dumps(body), content_type="application/json")

    async def bucket(self, r):
        req = r.request
        path = urlsplit(req.url).path.split("/storage/v1/", 1)[-1]
        if req.method == "GET":
            await r.fulfill(status=404, content_type="application/json", body='{"error":"not in the test"}')
            return
        body = req.post_data_buffer or b""
        part = re.search(rb"Content-Type: (image/[\w.+-]+)", body)
        obj = path.split("object/", 1)[-1]
        self.sent.append({"upload": {"method": req.method, "object": obj, "type": part[1].decode() if part else "", "image": image_facts(body)}})
        if req.method == "DELETE":
            await r.fulfill(status=200, content_type="application/json", body="[]")
        else:
            await r.fulfill(status=200, content_type="application/json", body=json.dumps({"Key": obj, "Id": "test"}))


def image_facts(body):
    i = body.find(b"\xff\xd8\xff")
    if i >= 0:
        j = i + 2
        while j < len(body) - 9:
            if body[j] != 0xFF:
                j += 1
                continue
            m = body[j + 1]
            if m in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", body[j + 5:j + 9])
                return f"JPEG {w}x{h}"
            if m == 0xD8 or m == 0x01 or 0xD0 <= m <= 0xD7 or m == 0xFF:
                j += 2 if m != 0xFF else 1
                continue
            j += 2 + struct.unpack(">H", body[j + 2:j + 4])[0]
        return "JPEG"
    return "no picture" if body else ""


def test_png(w=320, h=200):
    rows = b"".join(b"\x00" + bytes(v for x in range(w) for v in (x * 255 // (w - 1), y * 255 // (h - 1), 160)) for y in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


# ---------- a save's answer
def sent_lines(sent, fields=True):
    out = []
    for s in sent:
        if "upload" in s:
            u = s["upload"]
            obj = re.sub(r"[0-9]{6,}", "<time>", u["object"])
            obj = re.sub(r"^(site-photos/)?(airports|logos)/[A-Z0-9]+", r"\1\2/<code>", obj)
            out.append(f"upload {u['method']} {obj} {u['type']} {u['image']}")
        elif s["rpc"] == "planner_save":
            for c in (s["args"].get("p_changes") or []):
                cols = sorted(set((c.get("values") or {}).keys()) | set((c.get("from") or {}).keys()))
                out.append(f"planner_save {c.get('table')} {c.get('op')}" + (f" {','.join(cols)}" if fields and cols else ""))
        else:
            out.append(f"rpc {s['rpc']}" + (f" {','.join(sorted(s['args']))}" if fields else ""))
    return out


def written_lines(rows, fields=True):
    return [f"{r['table']} {r['op']}" + (f" {','.join(r['fields'])}" if fields and r["op"] == "update" and r["fields"] else "") for r in rows]


def counted(lines, variable=()):
    c = Counter(lines)
    return {k: ("*" if any(k.startswith(v) for v in variable) else n) for k, n in sorted(c.items())}


def same(want, got):
    """The recorded answer and this run's: the same lines, the same counts where the recorded one gives a count."""
    if set(want) != set(got):
        return False
    return all(w == "*" or w == got[k] for k, w in want.items())


def diff(label, want, got):
    lines = []
    for k in sorted(set(want) | set(got)):
        if k not in got:
            lines.append(f"{label}: recorded {k!r} ×{want[k]}, not written now")
        elif k not in want:
            lines.append(f"{label}: now also {k!r} ×{got[k]}, not in the recorded answer")
        elif want[k] != "*" and want[k] != got[k]:
            lines.append(f"{label}: {k!r} ×{got[k]}, recorded ×{want[k]}")
    return lines


async def until_quiet(seconds=30, still_for=1.5):
    end, last, still = time.monotonic() + seconds, -1, 0.0
    while time.monotonic() < end:
        n = int(psql("select coalesce(max(id), 0) from public.change_log").strip())
        if n == last:
            still += 0.25
            if still >= still_for:
                return
        else:
            still = 0.0
        last = n
        await asyncio.sleep(0.25)


async def saved_state(pl):
    await pl.pg.wait_for_function("() => /^(saved)$/.test((document.querySelector('[data-save-state]') || {}).textContent || '')", timeout=30000)


class Saves:
    """Runs each save and checks its answer against the recorded one."""

    def __init__(self, pl):
        self.pl = pl
        self.want = expected()

    async def act(self, name, do, rows=1, variable=(), fields=True, extra=None, quiet=1.5):
        pl = self.pl
        problems = []
        n0 = len(pl.sent)
        client = await pl.client()
        mark = marks()
        e0 = len(pl.errors)
        try:
            await do()
            if rows:
                got = await wait_for(lambda: log_since(mark), lambda got: len(got) >= rows, seconds=45)
                if len(got) < rows:
                    problems.append(f"the change log has {len(got)} row(s) for it after 45 s, expected at least {rows}")
            await until_quiet(still_for=quiet)
            try:
                await saved_state(pl)
            except Exception:
                problems.append("the header doesn't say saved")
        except Exception as e:
            problems.append(why(e))
        log = log_since(mark)
        answer = {
            "sent": counted(sent_lines(pl.sent[n0:], fields), variable),
            "written": counted(written_lines(log, fields), variable),
            "logged": sorted({f"{r['actor']} {'tab' if r['detail'] == client else r['detail']}" for r in log}),
        }
        if extra:
            try:
                answer.update(extra())
            except Exception as e:
                problems.append("reading what it wrote: " + why(e))
        bad = [r for r in log if r["actor"] != "planner" or r["detail"] not in (client, "save_loads")]
        problems += [f"a change-log row names {r['actor']} ({r['detail']}), not planner with the tab's ID" for r in bad[:3]]
        problems += [e for e in pl.errors[e0:]][:4]
        found[name] = answer
        want = self.want.get(name)
        if want is None:
            if not RECORD:
                problems.append("no recorded answer for this save in tests/fixtures/planner_saves.expected.json")
            note = " (recorded now)"
        else:
            note = ""
            for k in ("sent", "written"):
                if not same(want.get(k, {}), answer[k]):
                    problems += diff(k, want.get(k, {}), answer[k])
            for k in [k for k in want if k not in ("sent", "written")]:
                if want[k] != answer.get(k):
                    problems.append(f"{k}: now {answer.get(k)!r}, recorded {want[k]!r}")
        words = "; ".join(f"{k} ×{v}" for k, v in answer["written"].items()) or "nothing written"
        step(not problems, f"{name}: {words}{note}", problems)
        return log

    def not_tried(self, why_not, *prefixes):
        """Saves that can't be tried on this copy (each named by the start of its name), and why."""
        untried.extend(prefixes)
        print(f"--    {' / '.join(prefixes)}: not tried on this copy ({why_not})", flush=True)


# ---------- going to a screen, as a click would (inside the router), once it has read everything
async def go(pl, to, ready, extra=None):
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", to)
    await pl.pg.wait_for_selector(ready, timeout=90000)
    if extra:
        await pl.pg.wait_for_function(extra, timeout=30000)
    await settle(pl.pg, 300)


async def reload(pl):
    """The planner loaded again (signed in already, its clock still frozen): it reads the copy as the test left it."""
    await pl.pg.reload()
    await pl.pg.wait_for_function("!!window.__eqPlanner", timeout=60000)
    await pl.pg.wait_for_selector("main[data-screen]", timeout=60000)
    await settle(pl.pg, 300)


def screen_ready(sid, view=None):
    attr = {"routes": "routes", "tails": "tails", "check": "check", "review": "review"}.get(sid)
    sel = f"main[data-screen={sid}][data-{sid}-ready=yes]"
    if view is not None and attr:
        return sel, f"""() => {{ const m = document.querySelector('main[data-screen={sid}]');
            return !!m && decodeURIComponent(m.dataset.{attr}View || '') === decodeURIComponent({json.dumps(view)}); }}"""
    return sel, None


async def to_screen(pl, sid, path):
    sel, extra = screen_ready(sid, path)
    await go(pl, path, sel, extra)


def as_test(sql, **v):
    """A change the test makes itself, named as the test in the change log."""
    psql("begin; select set_config('equinox.actor', 'test', true), set_config('equinox.actor_detail', 'planner_saves_test', true);\n"
         + sql + "\ncommit;", **v)


def quietly(sql, **v):
    """A change the test makes itself, outside the change log (postgres only)."""
    psql("set equinox.change_log = 'off';\n" + sql, **v)


def hhmm(m):
    m %= 1440
    return f"{m // 60:02d}:{m % 60:02d}"


# ---------- Home
async def home(s, pl, tag):
    pg = pl.pg
    await to_screen(pl, "home", "/")
    title = f"Saves test {tag}"
    await pg.wait_for_selector("#todo-title", timeout=30000)

    async def add(t):
        await pg.fill("#todo-title", t)
        await pg.fill("#todo-steps", "First step\nSecond step")
        await pg.click("#todo-add")
    await s.act("home: add a to-do with two steps", lambda: add(title), rows=3)
    key = psql(f"select coalesce((select legacy_key from public.todos where world_id = {WORLD} and title = :'t' order by id desc limit 1), '')", t=title).strip()
    sel = f"[data-todo-list=open] > li[data-todo='{key}']"
    try:
        await pg.wait_for_selector(sel, timeout=30000)
        await s.act("home: tick a to-do", lambda: pg.click(f"{sel} input[type=checkbox]"))
    except Exception as e:
        step(False, "home: tick a to-do", [why(e)])

    other = title + " (to delete)"
    await s.act("home: add a to-do, to delete", lambda: add(other), rows=3)
    key2 = psql(f"select coalesce((select legacy_key from public.todos where world_id = {WORLD} and title = :'t' order by id desc limit 1), '')", t=other).strip()
    sel2 = f"[data-todo-list=open] > li[data-todo='{key2}']"

    async def delete():
        await pg.wait_for_selector(sel2, timeout=30000)
        await pg.click(f"{sel2} button.dismiss")
        await pg.wait_for_selector(f"{sel2} [data-confirm]", timeout=10000)
        await pg.click(f"{sel2} [data-confirm-yes]")
    await s.act("home: delete a to-do (the page asks itself)", delete, rows=3)

    await pg.evaluate("document.querySelectorAll('#attention details').forEach(d => d.open = true)")
    if not await pg.evaluate("!!document.querySelector('#attention [data-att-item] button.dismiss')"):
        s.not_tried("needs attention lists nothing", "home: dismiss an item", "home: show again")
        return
    await s.act("home: dismiss an item of needs attention", lambda: pg.locator("#attention [data-att-item]").first.locator("button.dismiss").click())
    await s.act("home: show again", lambda: pg.click("#attention [data-show-again]"), variable=("planner_save dismissals delete", "dismissals delete"))


# ---------- Routes
def routes_query(code, hub):
    return "?" + "&".join([f"airline={quote(code)}", f"bases={quote(hub, safe='')}"])


async def routes(s, pl, al):
    pg = pl.pg
    code, aid, hub = al["code"], al["id"], al["bases"][0]
    dest = psql(f"""select coalesce(min(a.code), '') from public.airports a where a.lat is not null and a.lon is not null and a.utc_offset is not null
                     and a.code <> :'h' and length(a.code) = 3
                     and not exists (select 1 from public.routes r where r.airline_id = {int(aid)} and r.hub_code = :'h' and r.dest_code = a.code)
                     and not exists (select 1 from public.airline_bases b where b.airport_code = a.code)""", h=hub).strip()
    mkts = [m for m in psql(f"select name from public.markets where airline_id = {int(aid)} order by name").splitlines() if m]
    if not dest or len(mkts) < 2:
        s.not_tried(f"no airport to add a route to or fewer than two markets for {code}", "routes:")
        return
    await to_screen(pl, "routes", "/routes" + routes_query(code, hub))

    async def add_route():
        await pg.click("#add-route-btn")
        await pg.select_option("#r-hub", hub)
        await pg.fill("#r-dest", dest)
        await pg.select_option("#r-market", mkts[0])
        await pg.click("#r-add")
    await s.act("routes: add a route", add_route)
    route_id = psql(f"select coalesce((select id::text from public.routes where airline_id = {int(aid)} and hub_code = :'h' and dest_code = :'d'), '')", h=hub, d=dest).strip()
    if not route_id:
        return
    await pg.wait_for_selector(f"[data-route-detail='{hub}-{dest}']", timeout=30000)
    await pg.click("#edit-route")
    await s.act("routes: edit its stars", lambda: pg.select_option("[data-rk=stars]", "5"))
    await s.act("routes: edit its market", lambda: pg.select_option("[data-rk=market]", mkts[1]))
    await pg.click("#edit-route")
    await s.act("routes: add a frequency", lambda: pg.click("#add-freq"), rows=3)
    rot = psql(f"select coalesce(max(id)::text, '') from public.rotations where route_id = {int(route_id)}").strip()
    if not rot:
        return
    box = lambda k: f".freq[data-rotation='{rot}'] [data-k={k}]"

    async def type_into(sel, value):
        await pg.fill(sel, value)
        await pg.press(sel, "Enter")
    for k, v, what in (("days", "135", "its days"), ("depHub", "07:00", "its departure"), ("arrDest", "09:10", "its arrival"),
                       ("depDest", "10:20", "its return's departure"), ("arrHub", "12:40", "its return's arrival")):
        await s.act(f"routes: type {what}", lambda k=k, v=v: type_into(box(k), v))
    await s.act("routes: change its departure", lambda: type_into(box("depHub"), "07:30"))

    async def delete_freq():
        await pg.click(f".freq[data-rotation='{rot}'] button[data-del]")
        await pg.click(f".freq[data-rotation='{rot}'] [data-confirm-yes]")
    await s.act("routes: delete the frequency (the page asks itself)", delete_freq, rows=3)

    async def remove_route():
        await pg.wait_for_selector(f".freq[data-rotation='{rot}']", state="detached", timeout=30000)
        await pg.click("#rm-route")
        await pg.click(".qpanel [data-confirm-yes]")
    await s.act("routes: remove the route (the page asks itself)", remove_route)

    # an airport only one rotation uses (and no base, no plan card), with no row of its own in the world if there is one
    x = one(f"""select json_build_object('code', a.code, 'airline', min(ro.airline_id), 'hub', min(ro.hub_code), 'dest', min(ro.dest_code), 'off', min(a.utc_offset))
                  from public.airports a
                  join public.flight_legs l on a.code in (l.origin_code, l.dest_code)
                  left join public.rotations rt on rt.id = l.rotation_id left join public.routes ro on ro.id = rt.route_id
                 where a.utc_offset is not null and a.utc_offset between -11 and 13
                   and not exists (select 1 from public.airline_bases b where b.airport_code = a.code)
                   and not exists (select 1 from public.plan_card_legs pc where pc.origin_code = a.code or pc.dest_code = a.code)
                   and not exists (select 1 from public.world_airports wa where wa.world_id = {WORLD} and wa.airport_code = a.code
                                     and wa.utc_offset_override is not null)
                 group by a.code having count(distinct l.rotation_id) = 1 and count(l.rotation_id) = count(*)
                 order by exists (select 1 from public.world_airports wa where wa.world_id = {WORLD} and wa.airport_code = a.code), a.code limit 1""")
    xal = next((a for a in COPY["airlines"] if x and a["id"] == x["airline"]), None)
    if not x or not xal:
        s.not_tried("no airport only one of our flights uses", "routes: change an airport's UTC offset", "routes: put the offset back")
        return
    await to_screen(pl, "routes", f"/routes/{xal['code']}/{x['hub']}-{x['dest']}")
    await pg.wait_for_selector(f"[data-route-detail='{x['hub']}-{x['dest']}']", timeout=20000)
    utc_box = f".dsub input[data-utc='{x['code']}']"
    fresh = "insert" if not psql(f"select 1 from public.world_airports where world_id = {WORLD} and airport_code = :'c'", c=x["code"]).strip() else "update"

    async def offset(v):
        await type_into(utc_box, v)
        await pg.wait_for_selector(".qpanel [data-confirm-yes]", timeout=30000)
        await pg.click(".qpanel [data-confirm-yes]")
    # the legs' columns depend on the night's flight (a move can cross midnight), so this one is recorded without columns
    print(f"      the offset: {x['code']} ({xal['code']} {x['hub']}–{x['dest']}), its world row {'added' if fresh == 'insert' else 'there already'}", flush=True)
    await s.act("routes: change an airport's UTC offset", lambda: offset("%g" % (float(x["off"]) + 1)), rows=2, fields=False)
    await s.act("routes: put the offset back", lambda: offset(""), rows=2, fields=False)


# ---------- Tails
async def tails(s, pl, al, tag, now):
    pg = pl.pg
    code = al["code"]
    reg = "ZZ" + tag[:4].upper()
    await to_screen(pl, "tails", "/tails?" + urlencode({"airline": code}))

    async def add_tail():
        await pg.fill("#t-id", reg)
        for sel in ("#t-type", "#t-cfg", "#t-base"):
            v = await pg.evaluate(f"(document.querySelector('{sel}').options[1] || {{}}).value || ''")
            if v:
                await pg.select_option(sel, v)
        await pg.click("#t-add")
    await s.act("tails: add a tail", add_tail)
    try:
        await pg.wait_for_selector(f"[data-tail-page={json.dumps(reg)}]", timeout=30000)
    except Exception as e:
        step(False, "tails: open the added tail", [why(e)])
        return

    async def maint():
        await pg.fill("[data-tk=maint]", "test gap " + tag)
        await pg.press("[data-tk=maint]", "Enter")
    await s.act("tails: change its maintenance gap", maint)

    async def base():
        cur = await pg.evaluate("document.querySelector('[data-tk=base]').value")
        opts = await pg.evaluate("[...document.querySelector('[data-tk=base]').options].map(o => o.value).filter(Boolean)")
        await pg.select_option("[data-tk=base]", next((o for o in opts if o != cur), opts[0]))
    await s.act("tails: change its base", base)

    async def remove():
        await to_screen(pl, "tails", "/tails?" + urlencode({"airline": code}))
        await pg.click(f"[data-deltail={json.dumps(reg)}]")
        await pg.click(".qpanel [data-confirm-yes]")
    await s.act("tails: remove it (the page asks itself)", remove)

    # a delivery made for the test: on order, nothing points at it, last on the old list of deliveries
    dreg = "ZD" + tag[:4].upper()
    t = one(f"""select json_build_object('type', a.aircraft_type_id, 'config', a.cabin_config_id, 'base', b.airport_code)
                  from public.aircraft a join public.airline_bases b on b.airline_id = a.airline_id
                 where a.airline_id = {int(al['id'])} and a.status = 'active' and a.aircraft_type_id is not null and a.cabin_config_id is not null
                 order by a.id, b.position nulls last, b.id limit 1""")
    if not t:
        s.not_tried(f"{code} has no aircraft in service to copy", "tails: remove a delivery")
    else:
        as_test(f"""insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, ordered_on, delivery_at, order_base_code, order_config_id, extra)
                    select {WORLD}, {int(al['id'])}, :'r', {int(t['type'])}, 'on_order', :'d'::date, :'m'::timestamptz + interval '3 days', :'b', {int(t['config'])},
                           jsonb_build_object('deliveries_index', (select coalesce(max((x.extra ->> 'deliveries_index')::int), -1) + 1 from public.aircraft x
                                                                    where x.world_id = {WORLD} and x.extra ? 'deliveries_index'))""",
                r=dreg, d=now[:10], m=now, b=t["base"])
        await reload(pl)

        async def remove_delivery():
            await to_screen(pl, "tails", "/tails?" + urlencode({"airline": code}))
            await pg.wait_for_selector(f"[data-deldel={json.dumps(dreg)}]", timeout=20000)
            await pg.click(f"[data-deldel={json.dumps(dreg)}]")
        await s.act("tails: remove a delivery (on order, nothing pointing at it)", remove_delivery)

    await filing(s, pl, al, tag, now, t)


def card_flights(card_id, code):
    """The plan card's legs as the game shows them: local times at each end, every day."""
    legs = json.loads(psql(f"""select coalesce(json_agg(json_build_object('no', l.flight_no::text, 'from', l.origin_code, 'to', l.dest_code,
                    'dep', to_char(make_time(((l.dep_utc_min + o.oo) % 1440 + 1440) % 1440 / 60, ((l.dep_utc_min + o.oo) % 1440 + 1440) % 1440 % 60, 0), 'HH24:MI'),
                    'arr', to_char(make_time(((l.dep_utc_min + l.block_min + o.od) % 1440 + 1440) % 1440 / 60, ((l.dep_utc_min + l.block_min + o.od) % 1440 + 1440) % 1440 % 60, 0), 'HH24:MI'))
                    order by l.position), '[]')
              from public.plan_card_legs l
              cross join lateral (select coalesce(private.airport_offset_min(l.world_id, l.origin_code), 0) as oo,
                                         coalesce(private.airport_offset_min(l.world_id, l.dest_code), 0) as od) o
             where l.plan_card_id = {int(card_id)}""").strip())
    return [dict(L, code=code, days="1234567", type="32N", valid="") for L in legs]


def shift(t, m):
    h, mm = (int(x) for x in t.split(":"))
    return hhmm(h * 60 + mm + m)


async def filing(s, pl, al, tag, now, t):
    """An arrived aircraft made for the test, with a plan card of one round trip on a route its airline has: filed from the
    card with the game matching (it files at once), put back, then filed again with the game's times differing."""
    pg = pl.pg
    code, aid = al["code"], int(al["id"])
    r = one(f"""select json_build_object('id', r.id, 'hub', r.hub_code, 'dest', r.dest_code, 'block', coalesce(
                  (select min(l.block_min) from public.flight_legs l join public.rotations o on o.id = l.rotation_id where o.route_id = r.id and l.block_min is not null), 120))
                  from public.routes r join public.airline_bases b on b.airline_id = r.airline_id and b.airport_code = r.hub_code and b.role <> 'focus'
                 where r.airline_id = {aid} and not r.removed order by exists (select 1 from public.rotations o where o.route_id = r.id) desc, r.id limit 1""")
    if not t or not r:
        s.not_tried(f"{code} has no route from a hub or no aircraft to copy", "tails: file an arrived aircraft")
        return
    top = int(psql(f"select coalesce(max(flight_no), 1000) from public.flight_legs where airline_id = {aid}").strip())
    n1 = top + 101 + (top + 101) % 2
    freg = "ZF" + tag[:4].upper()
    blk = int(r["block"])
    as_test(f"""insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, ordered_on, delivery_at, order_base_code, order_config_id, extra)
                select {WORLD}, {aid}, :'r', {int(t['type'])}, 'delivered', :'d'::date - 30, :'m'::timestamptz - interval '2 hours', :'b', {int(t['config'])},
                       jsonb_build_object('deliveries_index', (select coalesce(max((x.extra ->> 'deliveries_index')::int), -1) + 1 from public.aircraft x
                                                                where x.world_id = {WORLD} and x.extra ? 'deliveries_index'));
                insert into public.plan_cards (world_id, airline_id, aircraft_id, base_code, title)
                select {WORLD}, {aid}, a.id, :'b', 'saves test' from public.aircraft a where a.world_id = {WORLD} and a.registration = :'r';
                insert into public.plan_card_legs (world_id, plan_card_id, position, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min)
                select {WORLD}, c.id, x.p, x.no, x.o, x.d, '{{1,2,3,4,5,6,7}}', x.dep, {blk}
                  from public.plan_cards c join public.aircraft a on a.id = c.aircraft_id
                 cross join (values (1, {n1}, :'b', :'x', 360), (2, {n1 + 1}, :'x', :'b', ({360 + blk + 60}) % 1440)) as x(p, no, o, d, dep)
                 where a.world_id = {WORLD} and a.registration = :'r';""",
            r=freg, d=now[:10], m=now, b=r["hub"], x=r["dest"])
    ids = one(f"""select json_build_object('aircraft', a.id, 'card', c.id) from public.aircraft a join public.plan_cards c on c.aircraft_id = a.id
                   where a.world_id = {WORLD} and a.registration = '{freg}'""")
    snap = psql(f"select to_jsonb(a)::text from public.aircraft a where a.id = {int(ids['aircraft'])}").strip()
    legs0 = psql(f"select coalesce(json_agg(l), '[]')::text from public.plan_card_legs l where l.plan_card_id = {int(ids['card'])}").strip()
    sample = json.loads((FIX / "schedule_113.expected.json").read_text())

    def put_back(top_ids):
        quietly(f"""delete from public.flight_legs where id > {int(top_ids['legs'])} or rotation_id > {int(top_ids['rot'])};
                    delete from public.rotations where id > {int(top_ids['rot'])};
                    delete from public.spending_log where id > {int(top_ids['spent'])};
                    delete from public.routes where id > {int(top_ids['route'])};
                    update public.aircraft x set status = s.status, base_code = s.base_code, cabin_config_id = s.cabin_config_id, extra = s.extra,
                           retired_on = s.retired_on, checked_on = s.checked_on, schedule_changed_on = s.schedule_changed_on, maintenance_note = s.maintenance_note
                      from jsonb_populate_record(null::public.aircraft, :'a'::jsonb) s where x.id = s.id;
                    update public.plan_card_legs x set dep_utc_min = s.dep_utc_min, block_min = s.block_min, days_utc = s.days_utc
                      from jsonb_populate_recordset(null::public.plan_card_legs, :'l'::jsonb) s where x.id = s.id;""", a=snap, l=legs0)

    for mode, changes in (("matching", None), ("differing", {0: (10, 15)})):
        flights = card_flights(ids["card"], code)
        for i, (d, a) in (changes or {}).items():
            flights[i] = dict(flights[i], dep=shift(flights[i]["dep"], d), arr=shift(flights[i]["arr"], a))
        nos = {f["no"] for f in flights}
        pl.schedule = dict(sample, flights=[f for f in sample["flights"] if f["no"] not in nos] + flights)
        top_ids = one("""select json_build_object('rot', coalesce((select max(id) from public.rotations), 0), 'legs', coalesce((select max(id) from public.flight_legs), 0),
                          'spent', coalesce((select max(id) from public.spending_log), 0), 'route', coalesce((select max(id) from public.routes), 0))""")
        await reload(pl)

        async def file():
            await to_screen(pl, "tails", "/tails?" + urlencode({"airline": code, "card": freg}))
            await pg.click(f"[data-figure='tails: deliveries'] [data-planfile={json.dumps(freg)}]")
            if mode == "differing":
                await pg.wait_for_selector(f"[data-file-check={json.dumps(freg)}][data-file-ready=yes]", timeout=60000)
                await pg.click(f"[data-filegame={json.dumps(freg)}]")
        try:
            await s.act(f"tails: file an arrived aircraft from its plan card, the game {mode}", file, rows=4, quiet=2.5)
        finally:
            put_back(top_ids)
    pl.schedule = None


# ---------- Check
def planner_flights(airline_id):
    rules = psql("select private.rules_input_doc(null, 'all')::text").strip()
    markets = psql(f"select coalesce(json_agg(json_build_object('id', m.id, 'default_type_id', m.default_type_id)), '[]')::text from public.markets m where m.world_id = {WORLD}").strip()
    r = subprocess.run(["node", str(ROOT / "tests" / "planner_flights.mjs")], input=f'{{"rules": {rules}, "markets": {markets}, "airline": {int(airline_id)}}}',
                       capture_output=True, text=True, timeout=120)
    if r.returncode:
        raise RuntimeError("planner_flights.mjs: " + (r.stderr.strip().splitlines() or ["failed"])[-1][:200])
    return json.loads(r.stdout)


async def check(s, pl, al, today):
    pg = pl.pg

    async def to_check():
        await to_screen(pl, "check", "/check")
        await pg.wait_for_function("() => !!window.EQ_LOGOS", timeout=20000)
        await settle(pg, 300)
        await pg.click("#rev-expall")
        await settle(pg, 200)

    # the game check: the airline's own flights, with one flight's times moved 10 minutes, another's days, and a round trip
    # it hasn't got on one of its routes; every other airline's game answers 502
    try:
        flights = planner_flights(al["id"])
    except Exception as e:
        step(False, "check: the airline's flights for the game check", [why(e)])
        flights = {}
    legs = {str(x["no"]): x for x in json.loads(psql(f"""select coalesce(json_agg(json_build_object('no', l.flight_no, 'dep', l.dep_utc_min, 'days', l.days_utc)), '[]')
              from public.flight_legs l where l.airline_id = {int(al['id'])} and l.flight_no is not null""").strip())}
    single = [no for no, e in sorted(flights.items(), key=lambda x: int(x[0]) if x[0].isdigit() else 0)
              if len(e) == 1 and e[0]["dep"] and e[0]["arr"] and no in legs and legs[no]["dep"] is not None and 30 <= legs[no]["dep"] <= 1380]
    route = one(f"""select json_build_object('hub', r.hub_code, 'dest', r.dest_code, 'oh', coalesce(private.airport_offset_min(r.world_id, r.hub_code), 0),
                    'od', coalesce(private.airport_offset_min(r.world_id, r.dest_code), 0))
              from public.routes r join public.airline_bases b on b.airline_id = r.airline_id and b.airport_code = r.hub_code
             where r.airline_id = {int(al['id'])} and not r.removed order by exists (select 1 from public.rotations o where o.route_id = r.id), r.id limit 1""")
    if len(single) < 2 or not route or not al.get("game_id"):
        s.not_tried(f"{al['code']} has fewer than two flights to change, no route or no game ID", "check: the game check")
    else:
        t0, t1 = single[0], single[1]
        game = []
        for no, entries in flights.items():
            for e in entries:
                g = {"code": al["code"], "no": no, "from": e["from"], "to": e["to"], "days": e["days"], "dep": e["dep"], "arr": e["arr"], "type": "32N", "valid": ""}
                if no == t0:
                    g.update(dep=shift(e["dep"], 10), arr=shift(e["arr"], 10))
                elif no == t1:
                    g["days"] = e["days"][:-1] if len(e["days"]) > 1 else ("2" if e["days"] == "1" else "1")
                game.append(g)
        top = max(int(n) for n in flights if n.isdigit())
        n1 = top + 101 + (top + 101) % 2
        arr = shift("10:00", 120 + route["od"] - route["oh"])
        back = shift(arr, 90)
        game += [{"code": al["code"], "no": str(n1), "from": route["hub"], "to": route["dest"], "days": "1234567", "dep": "10:00", "arr": arr, "type": "32N", "valid": ""},
                 {"code": al["code"], "no": str(n1 + 1), "from": route["dest"], "to": route["hub"], "days": "1234567", "dep": back,
                  "arr": shift(back, 120 + route["oh"] - route["od"]), "type": "32N", "valid": ""}]
        pl.game = {str(al["game_id"]): {"id": str(al["game_id"]), "airline": al["name"], "flights": game}}
        legs_before = psql(f"select coalesce(json_agg(l), '[]')::text from public.flight_legs l where l.airline_id = {int(al['id'])}").strip()
        fleet_before = psql(f"select coalesce(json_agg(a), '[]')::text from public.aircraft a where a.airline_id = {int(al['id'])}").strip()
        tops = one("""select json_build_object('rot', coalesce((select max(id) from public.rotations), 0), 'legs', coalesce((select max(id) from public.flight_legs), 0),
                      'route', coalesce((select max(id) from public.routes), 0))""")

        def put_back():
            quietly(f"""delete from public.flight_legs where id > {int(tops['legs'])} or rotation_id > {int(tops['rot'])};
                        delete from public.rotations where id > {int(tops['rot'])};
                        delete from public.routes where id > {int(tops['route'])};
                        update public.flight_legs x set dep_utc_min = s.dep_utc_min, block_min = s.block_min, days_utc = s.days_utc, flight_no = s.flight_no, aircraft_id = s.aircraft_id
                          from jsonb_populate_recordset(null::public.flight_legs, :'l'::jsonb) s where x.id = s.id
                           and (x.dep_utc_min, x.block_min, x.days_utc, x.flight_no, x.aircraft_id) is distinct from (s.dep_utc_min, s.block_min, s.days_utc, s.flight_no, s.aircraft_id);
                        update public.aircraft x set status = s.status, base_code = s.base_code, cabin_config_id = s.cabin_config_id, extra = s.extra,
                               retired_on = s.retired_on, checked_on = s.checked_on, schedule_changed_on = s.schedule_changed_on, maintenance_note = s.maintenance_note
                          from jsonb_populate_recordset(null::public.aircraft, :'a'::jsonb) s where x.id = s.id
                           and (x.status, x.base_code, x.cabin_config_id, x.extra, x.retired_on, x.checked_on, x.schedule_changed_on, x.maintenance_note)
                               is distinct from (s.status, s.base_code, s.cabin_config_id, s.extra, s.retired_on, s.checked_on, s.schedule_changed_on, s.maintenance_note);""",
                    l=legs_before, a=fleet_before)

        async def game_open(what):
            await reload(pl)
            await to_check()
            await pg.click("#gcheck")
            await pg.wait_for_function("() => /Last checked/.test((document.querySelector('[data-board=\"Game check\"] .toolbar .count') || {}).textContent || '')", timeout=60000)
            await settle(pg, 300)
            c = al["code"]
            if what == "fix all":
                await pg.click(f"[data-board='Game check'] [data-gcfixall={json.dumps(c)}]")
                return
            await pg.click(f"[data-gcopen={json.dumps(c)}]")
            await pg.wait_for_selector("[data-gc-modal] .modal", timeout=10000)
            if what == "fix one":
                k = await pg.evaluate("no => [...document.querySelectorAll('.modal table tr')].slice(1).findIndex(tr => (tr.children[0] || {}).textContent.trim() === no)", t0)
                await pg.click(f"[data-gcfix={json.dumps(c + '|' + str(k))}]")
            else:
                k = await pg.evaluate("no => [...document.querySelectorAll('.modal .impr')].findIndex(r => r.querySelector('b').textContent.trim() === no)", str(n1))
                await pg.click(f"[data-imp={json.dumps(c + '|' + str(k))}]")
        for what, label in (("fix one", "the game check: fix one (a flight's times)"), ("fix all", "the game check: fix all (a time and a day change)"),
                            ("add", "the game check: add a flight (a round trip on a route it has)")):
            try:
                await s.act(f"check: {label}", lambda what=what: game_open(what), quiet=2.5)
            finally:
                put_back()
        pl.game = {}

    # Mark checked: an aircraft made due for the test (its check and schedule change cleared)
    pick = one(f"""select json_build_object('id', a.id, 'reg', a.registration) from public.aircraft a where a.world_id = {WORLD} and a.status = 'active'
                   and exists (select 1 from public.flight_legs l join public.rotations r on r.id = l.rotation_id where l.aircraft_id = a.id and r.launched_on is not null)
                   and not exists (select 1 from public.flight_legs l join public.rotations r on r.id = l.rotation_id where l.aircraft_id = a.id and r.launched_on > :'t'::date - 8)
                 order by a.extra ? 'tails_index' desc, a.id limit 1""", t=today)
    if not pick:
        s.not_tried("no aircraft with every rotation launched more than a week ago", "check: Mark checked")
    else:
        as_test(f"update public.aircraft set checked_on = null, schedule_changed_on = null where id = {int(pick['id'])}")
        await reload(pl)
        await to_check()
        await s.act("check: Mark checked (an aircraft made due for the test)", lambda: pg.click(f"[data-checked={json.dumps(pick['reg'])}]"))

    # Cabins: an aircraft flying legs that want its cabin, given another layout of its type with a different cabin for the
    # test, so the board offers its own back: Keep as is, Show again, then Refitted to
    made = None
    await reload(pl)
    await to_check()
    listed = set(await pg.evaluate("[...document.querySelectorAll('[data-cabkeep]')].map(b => b.dataset.cabkeep.split('|')[0])"
                                   ".concat([...document.querySelectorAll('[data-cabundo]')].map(b => b.dataset.cabundo.split('|')[0]))"))
    for x in json.loads(psql(f"""select coalesce(json_agg(x order by x.id), '[]') from (
            select distinct on (a.id) a.id, a.registration as reg, a.cabin_config_id as cfg, c2.id as other
              from public.aircraft a join public.cabin_configs c on c.id = a.cabin_config_id
              join public.cabin_configs c2 on c2.world_id = a.world_id and c2.aircraft_type_id = a.aircraft_type_id and c2.cabin is distinct from c.cabin
             where a.world_id = {WORLD} and a.status = 'active' and exists (select 1 from public.flight_legs l where l.aircraft_id = a.id)
               and not exists (select 1 from public.aircraft_cabin_keeps k where k.aircraft_id = a.id)
             order by a.id, c2.id) x""").strip())[:6]:
        if x["reg"] in listed:
            continue
        as_test(f"update public.aircraft set cabin_config_id = {int(x['other'])} where id = {int(x['id'])}")
        await reload(pl)
        await to_check()
        if await pg.evaluate("r => !!document.querySelector(`[data-refit^='${r}|']`) && !!document.querySelector(`[data-cabkeep^='${r}|']`)", x["reg"]):
            made = x
            break
        as_test(f"update public.aircraft set cabin_config_id = {int(x['cfg'])} where id = {int(x['id'])}")
    if not made:
        s.not_tried("no aircraft could be given a layout to refit from", "check: Keep as is", "check: Show again", "check: Refitted to")
    else:
        k = await pg.evaluate("r => document.querySelector(`[data-cabkeep^='${r}|']`).dataset.cabkeep", made["reg"])
        await s.act("check: Keep as is", lambda: pg.click(f"[data-cabkeep={json.dumps(k)}]"))

        async def undo():
            await pg.evaluate("document.querySelector('[data-board=Cabins] details.gsub').open = true")
            await pg.click(f"[data-cabundo={json.dumps(k)}]")
        await s.act("check: Show again", undo)
        refit = await pg.evaluate("r => (document.querySelector(`[data-refit^='${r}|']`) || {dataset: {}}).dataset.refit || ''", made["reg"])
        await s.act("check: Refitted to", lambda: pg.click(f"[data-refit={json.dumps(refit)}]"), rows=2)

    await reload(pl)
    await to_check()
    a = COPY["airlines"][0]
    await s.act("check: log an order (as Frequency)", lambda: pg.click(f"[data-gmove={json.dumps((a['code'] or '') + '|freq')}]"))


# ---------- Review
async def review(s, pl, al, now):
    pg = pl.pg
    code, aid = al["code"], int(al["id"])

    async def to_review():
        await to_screen(pl, "review", f"/review/{code}")
        await pg.click("#rev-expall")
        await settle(pg, 200)

    # cash and fixed costs for today: none typed for the airline today, so the save adds its row
    log = json.loads(psql("select private.fig_cash_log(:'w'::bigint, :'m'::timestamptz)", w=COPY["world"], m=now).strip())
    me = next((x for x in log["airlines"] if x["airline_id"] == aid), None)
    if not me:
        s.not_tried(f"{code} isn't in the nightly log", "review: cash and fixed costs")
    else:
        as_test(f"delete from public.cash_entries where airline_id = {aid} and day = :'d'::date", d=log["today"])
        await reload(pl)
        await to_review()
        cash = f"{round((me['today']['shown_cash'] or 10) + 1.11, 2)}"
        fixed = f"{round((me['today']['shown_fixed'] or 0) + 0.37, 2)}"

        async def save_cash():
            await pg.fill(f"[data-cash={json.dumps(code)}]", cash)
            await pg.fill(f"[data-fixed={json.dumps(code)}]", fixed)
            await pg.click("#cashsave")
        await s.act("review: cash and fixed costs for today", save_cash)

    # loads by hand, on days after the moment that no capture or typed load has reached: the first such day from two days on
    # typed, the day after it pasted
    async def open_loads(ahead):
        await reload(pl)
        await to_review()
        await pg.evaluate("document.querySelector('[data-loads-by-hand]').open = true")
        for _ in range(ahead):
            await pg.click("[data-lfday='1']")
            await settle(pg, 150)
        await settle(pg, 400)

    picked = None
    for ahead in range(2, 8):
        day = psql(f"select (:'m'::timestamptz at time zone 'UTC')::date + {ahead}", m=now).strip()
        empty = psql(f"""select not exists (select 1 from public.load_entries e where e.world_id = {COPY['world']} and e.game_date = :'d'::date)
                            and not exists (select 1 from public.load_days x where x.world_id = {COPY['world']} and x.game_date = :'d'::date)
                            and not exists (select 1 from public.game_flights f where f.world_id = {COPY['world']} and f.game_date = :'d'::date)""", d=day).strip()
        if empty == "t":
            picked = (ahead, day)
            break
    no = psql(f"select coalesce(min(flight_no)::text, '') from public.flight_legs where airline_id = {aid} and flight_no is not null").strip()
    if not picked or not no:
        s.not_tried("no day ahead free of loads, or no flight number", "review: loads typed", "review: loads pasted")
    else:
        ahead, day = picked
        await open_loads(ahead)
        box = f"[data-q={json.dumps(code + '|x')}]"
        if not await pg.evaluate("s => !!document.querySelector(s)", box):
            s.not_tried(f"{code} has no box on {day}", "review: loads typed")
        else:
            async def typed():
                await pg.fill(box, f"{no} 60")
                await pg.click("#lfsave")
            await s.act("review: loads typed (one flight, a day with nothing yet)", typed, rows=2)
        day2 = psql("select (:'d'::date + 1)::text", d=day).strip()
        clear = psql(f"""select not exists (select 1 from public.load_entries e where e.world_id = {COPY['world']} and e.game_date = :'d'::date)
                            and not exists (select 1 from public.load_days x where x.world_id = {COPY['world']} and x.game_date = :'d'::date)""", d=day2).strip() == "t"
        nos = [n for n in psql(f"select distinct flight_no from public.flight_legs where airline_id = {aid} and flight_no is not null order by 1 limit 2").split() if n]
        if not clear or len(nos) < 2:
            s.not_tried("the next day has loads already, or fewer than two flight numbers", "review: loads pasted")
        else:
            text = (FIX / "load_table_sample.tsv").read_text()
            for k, v in {"{CODE}": code, "{NO1}": nos[0], "{NO2}": nos[1], "{TAIL}": "X-TEST", "{FROM1}": "AAA", "{TO1}": "BBB", "{FROM2}": "BBB",
                         "{TO2}": "AAA", "{DM}": f"{day2[8:10]}.{day2[5:7]}."}.items():
                text = text.replace(k, str(v))
            await open_loads(0)

            async def pasted():
                await pg.evaluate("document.querySelector('details.lfpaste').open = true")
                await pg.fill("#lfpaste-in", text)
                await pg.click("#lfpaste-read")
                await pg.wait_for_selector("[data-paste-preview] #lfpaste-save", timeout=10000)
                if not await pg.evaluate("d => !!(document.querySelector(`[data-lfmark='${d}']`) || {}).checked", day2):
                    await pg.click(f"[data-lfmark='{day2}']")
                await pg.click("#lfpaste-save")
            await s.act("review: loads pasted (one under 95%, one full), the day marked complete", pasted, rows=2)

    # + fare plan on a route that offers it, then remove a planned change
    offer = None
    for a in COPY["airlines"]:
        await to_screen(pl, "review", f"/review/{a['code']}")
        await pg.click("#rev-expall")
        key = await pg.evaluate("(document.querySelector('[data-fareadd]') || {dataset: {}}).dataset.fareadd || ''")
        if key:
            offer = (a, key)
            break
    if not offer:
        s.not_tried("no route offers a fare plan on this copy", "review: + fare plan", "review: remove a planned fare change")
        return
    a, key = offer
    await s.act("review: + fare plan", lambda: pg.click(f"[data-fareadd={json.dumps(key)}]"))
    fp = psql(f"select coalesce((select id::text from public.fare_plan where airline_id = {int(a['id'])} and status = 'planned' order by id desc limit 1), '')").strip()
    if fp:
        await s.act("review: remove a planned fare change", lambda: pg.click(f"[data-faredel='{int(fp)}']"))


# ---------- Interline, Reference and Photos
INTERLINE_READY = "main[data-screen=interline][data-interline-ready=yes]"
REF_READY = "main[data-screen=reference][data-reference-ready=yes]"
PHOTOS_READY = "main[data-screen=photos][data-photos-ready=yes]"


async def interline(s, pl):
    pg = pl.pg
    await go(pl, "/interline", INTERLINE_READY)
    rows = await pg.evaluate("""[...document.querySelectorAll('tr[data-il-row]')].map(tr => ({ k: tr.dataset.ilRow, status: tr.className.trim() || 'none' }))""")
    r = next((x for x in rows if x["status"] == "none"), None)
    if not r:
        s.not_tried("every row has an agreement", "interline:")
        return
    sel = lambda f: f"[data-il={json.dumps(r['k'])}][data-ilk={f}]"
    await s.act("interline: a status (none to requested: its row added)", lambda: pg.select_option(sel("status"), "requested"))

    async def note():
        await pg.fill(sel("notes"), "saves test note")
        await pg.press(sel("notes"), "Enter")
    await s.act("interline: a note on it", note)


async def reference(s, pl):
    pg = pl.pg
    w = COPY["world"]

    async def ref(slug):
        await go(pl, "/reference/" + slug, REF_READY, f"() => !!document.querySelector('details.rsec[data-section={slug}][open]')")

    async def fill(sel, v):
        await pg.fill(sel, v)
        await pg.press(sel, "Enter")
    hb = one(f"""select json_build_object('i', x.i, 'bank1', x.bank1) from (
                 select row_number() over (order by b.position, b.id) - 1 as i, b.role, to_char(b.bank_times[1], 'HH24:MI') as bank1
                   from public.airline_bases b where b.world_id = {w}) x where x.role = 'hub' and x.bank1 is not null order by x.i limit 1""")
    if hb:
        await ref("hubs")
        await s.act("reference: a hub's bank time", lambda: fill(f"[data-ref='hubs.{hb['i']}.banks.0']", shift(hb["bank1"], 5)))
    buf = one(f"select s.value from public.settings s where s.world_id = {w} and s.airline_id is null and s.key = 'bank_buffer_min'")
    if buf is not None:
        await ref("constants")
        await s.act("reference: a constant (the bank buffer)", lambda: fill("[data-ref='consts.buf']", str(int(buf) + 1)))
    tp = one(f"select json_build_object('min_turn', t.min_turn_min) from public.aircraft_types t where t.world_id = {w} order by t.id limit 1")
    if tp:
        await ref("aircraft")
        await s.act("reference: a type's minimum turn", lambda: fill("[data-ref='types.0.minTurn']", str(int(tp["min_turn"] or 0) + 5)))
    await ref("configs")
    await s.act("reference: Add config", lambda: pg.click("main[data-screen=reference] [data-addrow=configs]"))
    ban = one(f"""select to_json(r.dest_code) from public.routes r where r.world_id = {w} and not r.removed
                    and not exists (select 1 from public.world_airports wa where wa.world_id = r.world_id and wa.airport_code = r.dest_code) order by r.id limit 1""")
    if ban:
        async def night_ban():
            await pg.fill("#cf-code", ban)
            await pg.fill("#cf-val", "00:30-05:30")
            await pg.click("#cf-add")
        await ref("night-bans")
        await s.act("reference: a night ban (an airport with no row of its own)", night_ban)
    rm = one(f"""select json_build_object('key', coalesce(a.planner_name, a.public_name) || '|' || r.hub_code || '|' || r.dest_code)
                  from public.routes r join public.airlines a on a.id = r.airline_id where r.world_id = {w} and r.removed order by r.id limit 1""")
    if rm:
        await ref("removed")
        await s.act("reference: a removed route restored", lambda: pg.click(f"[data-restore={json.dumps(rm['key'])}]"))
    else:
        s.not_tried("no removed route", "reference: a removed route restored")
    tz = one(f"""select json_build_object('code', wa.airport_code, 'offset', ap.utc_offset) from public.world_airports wa join public.airports ap on ap.code = wa.airport_code
                  where wa.world_id = {w} and wa.utc_offset_override is null and ap.utc_offset is not null and wa.airport_code is distinct from :'b'
                    and not exists (select 1 from public.flight_legs l where l.world_id = {w} and (l.origin_code = wa.airport_code or l.dest_code = wa.airport_code))
                    and not exists (select 1 from public.plan_card_legs l where l.world_id = {w} and (l.origin_code = wa.airport_code or l.dest_code = wa.airport_code))
                  order by wa.airport_code limit 1""", b=ban or "")
    if tz:
        async def zone():
            await pg.fill("#utc-code", tz["code"])
            await pg.fill("#utc-val", f"{float(tz['offset']) + 1:g}")
            await pg.click("#utc-set")
            await pg.click("[data-confirm-yes]", timeout=20000)
        await ref("time-zones")
        await s.act("reference: a time zone (an airport no flight uses)", zone)
    else:
        s.not_tried("no airport with a row of its own that no flight uses", "reference: a time zone")


async def photos(s, pl):
    pg = pl.pg
    await go(pl, "/photos", PHOTOS_READY)
    code = await pg.evaluate("(() => { const c = [...document.querySelectorAll('[data-ph]')].find(c => !c.querySelector('.ph-img img')); return c ? c.dataset.ph : ''; })()")
    if not code:
        s.not_tried("every destination has a photo", "photos:")
        return
    entry = "select coalesce((select value -> 'airports' -> :'c' from public.site_content where key = 'media'), 'null'::jsonb)::text"

    async def upload():
        await pg.fill(f"[data-ph-credit={code}]", "Saves test")
        await pg.set_input_files(f"[data-ph-up={code}]", {"name": "test.png", "mimeType": "image/png", "buffer": test_png()})
        await wait_for(lambda: json.loads(psql(entry, c=code).strip()), lambda got: bool(got), seconds=20)
        await pg.wait_for_function("() => (document.querySelector('main[data-screen=photos]') || {dataset: {}}).dataset.photosBusy === ''", timeout=30000)

    def website_row():
        e = json.loads(psql(entry, c=code).strip()) or {}
        return {"website": sorted(e)}
    await s.act("photos: a destination photo uploaded (the bucket answered in the browser)", upload, rows=0, extra=website_row)


# ---------- what the copy holds
COPY = {}


def read_copy():
    COPY["world"] = int(psql(f"select {WORLD}").strip())
    COPY["airlines"] = json.loads(psql(f"""select coalesce(json_agg(json_build_object('id', a.id, 'code', a.iata_code, 'game_id', a.game_id,
              'name', coalesce(a.planner_name, a.public_name, a.game_name, 'Airline ' || a.game_id),
              'bases', (select coalesce(json_agg(b.airport_code order by b.position nulls last, b.id), '[]') from public.airline_bases b
                         where b.airline_id = a.id and b.role <> 'focus'))
              order by a.position nulls last, a.id), '[]')
              from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
             where g.kind = 'ours' and a.world_id = {WORLD} and a.active""").strip())


async def main():
    facts = pn.planner_facts()
    if not facts or not pn.PAGE.is_file():
        step(False, "the new planner is built and names its Supabase address", ["run npm ci && npm run build first"])
        sys.exit(1)
    try:
        env = local_env()
        read_copy()
        now = copy_moment()
    except Exception as e:
        step(False, "set up: the copy's address and keys, and what it holds", [why(e)])
        sys.exit(1)
    tag = secrets.token_hex(4)
    staff = (f"saves-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        problems = staff_user(env, *staff)
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)
    al = next((a for a in COPY["airlines"] if a["bases"] and a["code"]), None)
    if not al:
        step(False, "one of our airlines with a hub", ["none on the copy"])
        sys.exit(1)
    want = expected()
    print(f"the moment: {now} (the copy's latest capture plus one hour); the saves on {al['code']} (its hub {al['bases'][0]}); "
          f"{len(want)} recorded answers{' (recording)' if RECORD else ''}", flush=True)
    seen = []
    with serve() as port:
        async with async_playwright() as p:
            pl = Saver(p, port, env, facts)
            seen.append(pl)
            s = Saves(pl)
            try:
                await pl.open(moment=now)
                await pl.pg.emulate_media(reduced_motion="reduce")
                await pl.sign_in(*staff)
                for name, part in (("Home", lambda: home(s, pl, tag)), ("Routes", lambda: routes(s, pl, al)), ("Tails", lambda: tails(s, pl, al, tag, now)),
                                   ("Check", lambda: check(s, pl, al, now[:10])), ("Review", lambda: review(s, pl, al, now)), ("Interline", lambda: interline(s, pl)),
                                   ("Reference", lambda: reference(s, pl)), ("Photos", lambda: photos(s, pl))):
                    t = time.monotonic()
                    try:
                        await part()
                    except Exception as e:
                        step(False, f"{name}'s saves", [why(e)] + pl.errors[-3:])
                    print(f"      {name}: {time.monotonic() - t:.0f} s", flush=True)
            finally:
                await pl.close()

    # every save the recorded answers name was tried, or said why it couldn't be on this copy
    missing = [k for k in want if k not in found and not any(k.startswith(u) for u in untried)]
    step(not missing, f"every recorded save was tried ({len(found)} tried; not tried on this copy: {', '.join(untried) or 'none'})",
         [f"not tried, and no reason given: {k}" for k in missing])
    if OUT_DIR:
        Path(OUT_DIR).mkdir(parents=True, exist_ok=True)
        (Path(OUT_DIR) / "planner_saves.json").write_text(json.dumps({"saves": found}, indent=1, sort_keys=True) + "\n")
        print(f"      the answers found are in the run's planner-saves artifact ({len(found)} saves)", flush=True)
    outside = sorted({h for x in seen for h in x.outside})
    step(not outside, f"nothing went outside ({sum(x.copy for x in seen)} requests answered by the copy)", ["reached: " + ", ".join(outside)] if outside else [])
    print(f"\n{len(failures)} save step(s) failed" if failures else "\nevery save writes its recorded rows", flush=True)
    print(f"      the saves took {time.monotonic() - started:.0f} s", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
