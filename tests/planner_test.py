"""The planner's automatic checks (decision #9), on the frozen sample with the clock frozen at its moment.

1. Every screen opens: all nine screens, each airline's Review page and the main pop-ups (route, aircraft, plan card)
   open with no errors and show content.
2. Look-only previews (#8): on a preview address a change saves nothing and says so; on the live address it saves,
   through the adapter (#13, pull request 9): planner_state_put() with the whole document, the tab's ID and as base the
   saved_at it loaded from planner_state_get(); nothing is written to the old rows.
   A copy the planner kept in the browser after a failed save is pushed from the base stored with it (#13, pull request
   9); one with nothing unsaved isn't pushed; an older planner's copy, with no base, is pushed with none, as before.
3. Loads by hand: on an airline's Review page, a typed day and a paste from the game each save, and send only the days
   they changed, through save_loads() (fix of 9 Oct: the buttons did nothing there, and saves rewrote whole months).
4. Known answers: the numbers on the screens that matter (Home, the group and each airline's Review page with the cash
   forecast, route profit and fare plan, the Check lists, hub connections, aircraft, interline) match the saved answers in
   tests/fixtures/planner_numbers.expected.json. A difference prints exactly what changed. After an intended change,
   run with --update and commit the new answers with the change, saying why they moved.
5. Home's job warnings (#13 pull request 7, design §7): with job_runs and backup_runs as the stand-in answers them,
   Home warns when the last good backup is more than 30 hours old or its last run failed, when the latest snapshot is
   more than 30 hours old or the 10:00 UTC job hasn't run for 30 hours, when the month's archive hasn't run by the 3rd,
   and when any job's last run failed (naming it and its note; the archive per table and month), and shows none of
   these when all is well.

Usage: python3 tests/planner_test.py [--update]
"""
import asyncio, datetime, difflib, json, re, sys
from harness import FIX, serve, open_planner, go, settle, sample
from playwright.async_api import async_playwright

EXPECTED = FIX / "planner_numbers.expected.json"
VIEWS = ["home", "routes", "tails", "hub", "review", "finance", "interline", "photos", "ref"]
LEASES = {"A321neo": "0.24M", "A320neo": "0.21M", "XLR": "0.29M", "E195": "0.18M", "A350": "0.72M"}   # manual §9
failures = []


def check(ok, name, detail=""):
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok or not detail else "\n      " + detail.replace("\n", "\n      ")))
    if not ok:
        failures.append(name)


LINES = """(el) => el ? el.innerText.split('\\n').map(s => s.replace(/\\s+/g, ' ').trim()).filter(Boolean) : null"""
BOARD = f"""(title) => {{ const h = [...document.querySelectorAll('#view h3')].find(x => x.textContent.trim().startsWith(title));
  return ({LINES})(h && (h.closest('.board') || h.parentElement)); }}"""


async def board(pg, title):
    return await pg.evaluate(BOARD, title)


async def readout(pg):
    out = {}
    await go(pg, "home")
    out["home: key figures"] = await pg.evaluate("[...document.querySelectorAll('#view .kpi')].map(k => k.innerText.replace(/\\s+/g, ' ').trim())")
    out["home: aircraft on order"] = await board(pg, "Aircraft on order")
    out["home: needs attention"] = await board(pg, "Needs attention")
    await go(pg, "finance")
    out["review: the group today"] = await board(pg, "The group today")
    out["review: next order per airline"] = await pg.evaluate("[...document.querySelectorAll('.fcard')].map(c => { const dt = [...c.querySelectorAll('dt')].find(d => /Next order/.test(d.textContent)); return c.querySelector('b').textContent + ': ' + (dt ? dt.nextElementSibling.textContent.trim() : '?'); })")
    for al in await pg.evaluate("[...document.querySelectorAll('[data-final]')].map(x => x.dataset.final)"):
        await pg.evaluate(f"document.querySelector('[data-final=\"{al}\"]').click()"); await settle(pg)
        for title in ("Cash, next 14 days", "Route profit", "Fare plan"):
            out[f"review {al}: {title}"] = await board(pg, title)
        await go(pg, "finance")
    await go(pg, "review")
    out["check: lists"] = await pg.evaluate("[...document.querySelectorAll('#view h4.gh')].map(x => x.innerText.replace(/\\s+/g, ' ').trim())")
    await go(pg, "hub")
    out["hubs: connections at the first hub"] = await pg.evaluate(f"({LINES})(document.querySelector('#view'))")
    await go(pg, "tails")
    out["tails"] = await pg.evaluate(f"({LINES})(document.querySelector('#view'))")
    await go(pg, "interline")
    out["interline"] = await pg.evaluate(f"({LINES})(document.querySelector('#view'))")
    return out


async def screens(pg, errors):
    for v in VIEWS:
        before = len(errors)
        await go(pg, v)
        n = await pg.evaluate("document.querySelector('#view').innerText.trim().length")
        check(n > 200 and len(errors) == before, f"screen opens: {v}", f"{n} characters shown; errors: {errors[before:]}")
    await go(pg, "finance")
    for al in await pg.evaluate("[...document.querySelectorAll('[data-final]')].map(x => x.dataset.final)"):
        before = len(errors)
        await pg.evaluate(f"document.querySelector('[data-final=\"{al}\"]').click()"); await settle(pg)
        boards = await pg.evaluate("[...document.querySelectorAll('#view h3')].map(h => h.textContent.trim())")
        ok = any(b.startswith("Cash, next 14 days") for b in boards) and len(errors) == before
        check(ok, f"Review page opens: {al}", f"boards: {boards[:8]}; errors: {errors[before:]}")
        await go(pg, "finance")
    for view, sel, name in (("home", ".wmap [data-route]", "route pop-up"), ("review", "[data-tailm]", "aircraft pop-up"),
                            ("home", "[data-plancard]", "plan card")):
        before = len(errors)
        await go(pg, view)
        if not await pg.evaluate(f"!!document.querySelector('{sel}')"):
            check(False, f"pop-up opens: {name}", f"nothing to click ({sel}) on {view}"); continue
        await pg.evaluate(f"document.querySelector('{sel}').dispatchEvent(new MouseEvent('click', {{bubbles: true}}))"); await settle(pg, 400)
        shown = await pg.evaluate("(document.getElementById('modalroot').innerText.trim().length) + (document.querySelector('#view .plancard, #view .pcard, #view [data-plan]') ? 1 : 0)")
        check(shown > 0 and len(errors) == before, f"pop-up opens: {name}", f"shown: {shown}; errors: {errors[before:]}")
        await pg.keyboard.press("Escape"); await go(pg, "home")


LOADS_WRITES = "JSON.stringify(window.__WRITES.filter(w => w.rpc === 'save_loads' || w.t === 'planner_loads'))"


async def manual_loads(p, port):
    b, pg, errors = await open_planner(p, port, live=True)
    pg.on("dialog", lambda d: asyncio.ensure_future(d.dismiss()))
    day = await pg.evaluate("new Date().toISOString().slice(0, 10)")
    await go(pg, "finance")
    await pg.evaluate("document.querySelector('[data-final]').click()"); await settle(pg)
    if not await pg.evaluate("!!document.getElementById('lfsave')"):
        check(False, "loads by hand: the form is on the Review page"); await b.close(); return
    # a whole day typed in
    await pg.evaluate("document.querySelector('[data-q]').value = '1001 60'; document.getElementById('lfsave').click()")
    await settle(pg)
    w = json.loads(await pg.evaluate(LOADS_WRITES))
    sent = w[0]["args"] if len(w) == 1 and w[0].get("rpc") == "save_loads" else {}
    days = sent.get("p_days", {})
    ok = sent.get("p_month") == day[:7] and list(days) == [day] and "f" in days[day] and days[day].get("done") is True
    check(ok, "loads by hand: a typed day saves only that day, through save_loads", f"writes: {json.dumps(w)[:400]}")
    # a paste from the game: one flight under 95% (set) and one full (cleared)
    dm = f"{day[8:10]}.{day[5:7]}."
    paste = "\n".join([f"KF 1008\tVT-AAE\tAMS\t{dm} 02:45 LT\tDEL\t{dm} 10:00 LT\t500\t100 / 150\t900\t10 / 12\t--\t--\t--\t--",
                        f"KF 1009\tVT-AAE\tDEL\t{dm} 12:00 LT\tAMS\t{dm} 18:00 LT\t500\t150 / 150\t900\t12 / 12\t--\t--\t--\t--"])
    await pg.evaluate("t => { const d = document.querySelector('details.lfpaste'); d.open = true; document.getElementById('lfpaste-in').value = t; document.getElementById('lfpaste-read').click(); }", paste)
    await settle(pg)
    await pg.evaluate("window.__WRITES.length = 0; document.getElementById('lfpaste-save').click()"); await settle(pg)
    w = json.loads(await pg.evaluate(LOADS_WRITES))
    sent = w[0]["args"] if len(w) == 1 and w[0].get("rpc") == "save_loads" else {}
    d = sent.get("p_days", {}).get(day, {})
    ok = (list(sent.get("p_days", {})) == [day] and d.get("set") == {"Kingfisher|1008": 68} and d.get("del") == ["Kingfisher|1009"]
          and "f" not in d)
    check(ok, "loads by hand: a paste sets and clears single flights only, through save_loads", f"writes: {json.dumps(w)[:400]}")
    check(not errors, "loads by hand: no errors", "\n".join(errors[:5]))
    await b.close()


async def look_only(p, port):
    saved = sample()["planner_state"].get("savedAt") or 1
    for live in (False, True):
        name = ("live address: a change saves, through planner_state_put() with the tab's ID and the loaded saved_at as base"
                if live else "preview address: a change saves nothing and says so")
        b, pg, errors = await open_planner(p, port, live=live)
        await go(pg, "home")
        box = "input[data-tododone]"
        if not await pg.evaluate(f"!!document.querySelector('{box}')"):
            check(False, name, "no to-do to tick on Home"); await b.close(); continue
        tid = await pg.evaluate(f"document.querySelector('{box}').dataset.tododone")
        await pg.click(box); await pg.wait_for_timeout(900)
        writes = await pg.evaluate("window.__WRITES.map(w => w.t || w.rpc || 'file')")
        put = await pg.evaluate("(window.__WRITES.filter(w => w.rpc === 'planner_state_put').pop() || {}).args || null")
        tab = await pg.evaluate("window.__eqTab || ''")
        label = await pg.evaluate("document.getElementById('savestate').textContent")
        notice = await pg.evaluate("!!document.querySelector('.eqpreview')")
        if live:
            doc = json.loads(put["p_json"]) if put and put.get("p_json") else {}
            todo = next((t for t in doc.get("todos") or [] if t.get("id") == tid), {})
            ok = (set(writes) == {"planner_state_put"} and todo.get("done") is True and put.get("p_client") == tab and tab.startswith("tab-")
                  and put.get("p_base") == saved and not notice and "preview" not in label)
        else:
            ok = writes == [] and notice and "preview" in label
        check(ok, name, f"writes {writes}, base {put and put.get('p_base')} (loaded {saved}), tab {'set' if tab else 'none'}, "
                        f"indicator '{label}', notice {notice}")
        await b.close()


async def stored_copies(p, port):
    """A copy the planner kept in the browser because a cloud save failed (#13, pull request 9) carries the base it was
    made from: with a change the cloud never got (its savedAt isn't that base), it is pushed from that base, so the
    server keeps whatever changed elsewhere since; with nothing unsaved, the cloud's copy is taken and nothing is sent.
    An older planner's copy, with no base, is pushed with none when it is the later one, as before."""
    S = sample()
    saved = S["planner_state"].get("savedAt") or 1
    tid = next((t.get("id") for t in S["planner_state"].get("todos") or [] if not t.get("done")), None)
    if not tid:
        check(False, "a copy kept in the browser", "the sample has no open to-do"); return

    def copy(base, saved_at):
        d = json.loads(json.dumps(S["planner_state"]))
        for t in d["todos"]:
            if t.get("id") == tid:
                t["done"] = True
        d["savedAt"] = saved_at
        if base is not None:
            d["__base"] = base
        return d
    for name, stored, want in (
            ("a copy kept in the browser with an unsaved change is pushed from the base stored with it", copy(saved - 5000, saved + 60000), saved - 5000),
            ("a copy kept in the browser with its base and nothing unsaved isn't pushed: the cloud's copy is taken", copy(saved - 5000, saved - 5000), "nothing"),
            ("an older planner's copy, with no base, is pushed with none when it is the later one, as before", copy(None, saved + 60000), None)):
        b, pg, errors = await open_planner(p, port, live=True, stored=stored)
        await pg.wait_for_timeout(900)
        puts = await pg.evaluate("window.__WRITES.filter(w => w.rpc === 'planner_state_put').map(w => w.args)")
        if want == "nothing":
            ticked = await pg.evaluate("id => { const x = [...document.querySelectorAll('input[data-tododone]')].find(e => e.dataset.tododone === id); return x ? x.checked : null; }", tid)
            ok, detail = not puts and ticked is False, f"{len(puts)} save(s) sent; the to-do shown {'ticked' if ticked else 'unticked' if ticked is False else 'nowhere'}"
        else:
            first = puts[0] if puts else {}
            todo = next((t for t in json.loads(first.get("p_json") or "{}").get("todos") or [] if t.get("id") == tid), {})
            ok = bool(puts) and first.get("p_base") == want and todo.get("done") is True
            detail = f"{len(puts)} save(s) sent; base {first.get('p_base')} (want {want}); the unsaved tick {'sent' if todo.get('done') else 'not sent'}"
        check(ok and not errors, name, detail + (f"; errors {errors[:3]}" if errors else ""))
        await b.close()


def _ago(hours):
    """A moment this many hours before the sample's frozen clock, as the database sends it."""
    t = datetime.datetime.fromisoformat(sample()["frozen_at"]) - datetime.timedelta(hours=hours)
    return t.astimezone(datetime.timezone.utc).isoformat()


def _run(job, hours, status="ok", note=None, **extra):
    return dict({"job": job, "status": status, "started_at": _ago(hours), "finished_at": _ago(hours - 0.01),
                 "for_month": None, "note": note or f"{job} {status}", "details": {}}, **extra)


# Home's warnings for the automatic jobs (#13 pull request 7, design §7), from job_runs and backup_runs as the stand-in
# answers them, with the clock at the sample's moment (10 Oct 13:37 UTC, past the 3rd): (scenario, tables, the
# warnings Home must show, as the start of each line). "All is well" must show none of them.
GOOD_JOBS = [_run("cleanup", 3.3), _run("snapshot_fallback", 3.6, details={"taken": False}), _run("snapshot", 10),
             _run("cleanup", 27.3, "failed", "clean-up: an earlier failure, fixed since"), _run("snapshot_fallback", 27.6),
             _run("archive", 222, details={"table": "game_flights"}, for_month="2026-08-01"),
             _run("archive", 222.5, "failed", "an earlier try", details={"table": "game_flights"}, for_month="2026-08-01")]
GOOD_BACKUPS = [{"ran_at": _ago(5), "kind": "nightly", "ok": True, "tables": 70, "rows": 20000, "files": 57, "bytes": 1, "note": None},
                {"ran_at": _ago(2), "kind": "test", "ok": False, "tables": 70, "rows": 20000, "files": 57, "bytes": 1, "note": "a dry run failed"}]
JOB_WORDS = ("Backup:", "Daily snapshot", "Nightly jobs", "Monthly archive", "Clean-up", "10:00 UTC snapshot job")
JOB_SCENARIOS = [
    ("all is well (a dry run failed, an earlier clean-up failed and was fixed, the archive ran on the 1st)",
     {"job_runs": GOOD_JOBS, "backup_runs": GOOD_BACKUPS}, []),
    ("the last good backup more than 30 hours old",
     {"job_runs": GOOD_JOBS, "backup_runs": [dict(GOOD_BACKUPS[0], ran_at=_ago(40))]}, ["Backup: last good copy 40 hours ago"]),
    ("the backup's last run failed",
     {"job_runs": GOOD_JOBS, "backup_runs": [dict(GOOD_BACKUPS[0], ran_at=_ago(1), ok=False, note="restore check failed: a table is missing")] + GOOD_BACKUPS},
     ["Backup: the last run failed (Sat, Oct 10 12:37 UTC): restore check failed: a table is missing"]),
    ("the latest snapshot more than 30 hours old (the capture and the 10:00 UTC job both stopped)",
     {"job_runs": [r for r in GOOD_JOBS if not r["job"].startswith("snapshot")] + [_run("snapshot", 40), _run("snapshot_fallback", 33.6)]},
     ["Daily snapshot: the last was 34 hours ago", "Nightly jobs: the 10:00 UTC job last ran 34 hours ago"]),
    ("the 10:00 UTC job not run for over 30 hours while the capture still takes its snapshots (the scheduler stopped)",
     {"job_runs": [r for r in GOOD_JOBS if r["job"] != "snapshot_fallback"] + [_run("snapshot_fallback", 51.6)]},
     ["Nightly jobs: the 10:00 UTC job last ran 52 hours ago"]),
    ("the month's archive not run by the 3rd",
     {"job_runs": [r for r in GOOD_JOBS if r["job"] != "archive"] + [_run("archive", 920, details={"table": "game_events"}, for_month="2026-07-01")]},
     ["Monthly archive: hasn't run this month (the nightly backup runs it from the 1st; last ran Wed, Sep 2"]),
    ("jobs whose last run failed: the clean-up, the 10:00 UTC job, one table and month of the archive",
     {"job_runs": [_run("cleanup", 3.2, "failed", "statement lines: 3 of the 120 older than 14 days aren't in game_flights or game_payments, so none were deleted"),
                   _run("snapshot_fallback", 3.5, "failed", "snapshot fallback: division by zero"),
                   _run("archive", 100, "failed", "game_events 2026-08: the copy on the GitHub release didn't match (SHA-256)",
                        details={"table": "game_events"}, for_month="2026-08-01")] + GOOD_JOBS},
     ["Clean-up (10:20 UTC): the last run failed (Sat, Oct 10 10:25 UTC): statement lines: 3 of the 120 older than 14 days aren't in game_flights or game_payments, so none were deleted",
      "10:00 UTC snapshot job: the last run failed (Sat, Oct 10 10:07 UTC): snapshot fallback: division by zero",
      "Monthly archive (game_events 2026-08): the last run failed (Tue, Oct 6 09:37 UTC): game_events 2026-08: the copy on the GitHub release didn't match (SHA-256)"]),
]


async def job_warnings(p, port):
    for name, tables, want in JOB_SCENARIOS:
        b, pg, errors = await open_planner(p, port, live=False, tables=tables)
        await go(pg, "home")
        lines = await pg.evaluate("[...document.querySelectorAll('#view ul.att button.link')].map(b => b.textContent.replace(/\\s+/g, ' ').trim())")
        shown = [x for x in lines if x.startswith(JOB_WORDS)]
        missing = [w for w in want if not any(x.startswith(w) for x in shown)]
        extra = [x for x in shown if not any(x.startswith(w) for w in want)]
        check(not missing and not extra and not errors, f"Home's job warnings: {name}",
              f"missing: {missing}; not expected: {extra}; errors: {errors[:3]}")
        await b.close()


def leases_named(got):
    text = json.dumps({k: v for k, v in got.items() if "Cash, next 14 days" in k})
    missing = [f"{t} {v}" for t, v in LEASES.items() if t in text and f"lease {v}" not in text]
    check(not missing, "leases on the forecast boards match the manual (§9)", f"not found: {missing}")


def compare(got):
    if "--update" in sys.argv:
        EXPECTED.write_text(json.dumps(got, indent=1, ensure_ascii=False) + "\n")
        print(f"saved answers updated ({len(got)} sections)")
    want = json.loads(EXPECTED.read_text())
    for key in sorted(set(want) | set(got)):
        a, b = want.get(key), got.get(key)
        if a == b:
            check(True, f"same answer: {key}")
            continue
        fmt = lambda x: x if isinstance(x, list) else [json.dumps(x)]
        diff = list(difflib.unified_diff(fmt(a or []), fmt(b or []), "saved answer", "now", lineterm="", n=1))
        check(False, f"same answer: {key}", "\n".join(diff[:40]) + ("\n..." if len(diff) > 40 else ""))


async def part(name, coro):
    try:
        return await coro
    except Exception as e:   # a broken screen can stop a part halfway; report it and carry on with the rest
        check(False, f"{name} ran to the end", f"{type(e).__name__}: {str(e).splitlines()[0][:300]}")


async def main():
    got = {}
    with serve() as port:
        async with async_playwright() as p:
            b, pg, errors = await open_planner(p, port, live=True)
            await part("screens", screens(pg, errors))
            await b.close()
            b, pg, errors = await open_planner(p, port, live=True)
            got = await part("reading the numbers", readout(pg)) or {}
            check(not errors, "no errors while reading the numbers", "\n".join(dict.fromkeys(errors[:10])))
            await b.close()
            await part("look-only previews", look_only(p, port))
            await part("copies kept in the browser", stored_copies(p, port))
            await part("loads by hand", manual_loads(p, port))
            await part("Home's job warnings", job_warnings(p, port))
    leases_named(got)
    compare(got)
    print(f"\n{len(failures)} planner check(s) failed" if failures else "\nplanner: all passed")
    sys.exit(1 if failures else 0)


asyncio.run(main())
