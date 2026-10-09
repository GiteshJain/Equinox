"""The planner's automatic checks (decision #9), on the frozen sample with the clock frozen at its moment.

1. Every screen opens: all nine screens, each airline's Review page and the main pop-ups (route, aircraft, plan card)
   open with no errors and show content.
2. Look-only previews (#8): on a preview address a change saves nothing and says so; on the live address it saves.
3. Loads by hand: on an airline's Review page, a typed day and a paste from the game each save, and send only the days
   they changed, through save_loads() (fix of 9 Oct: the buttons did nothing there, and saves rewrote whole months).
4. Known answers: the numbers on the screens that matter (Home, the group and each airline's Review page with the cash
   forecast, route profit and fare plan, the Check lists, hub connections, aircraft, interline) match the saved answers in
   tests/fixtures/planner_numbers.expected.json. A difference prints exactly what changed. After an intended change,
   run with --update and commit the new answers with the change, saying why they moved.

Usage: python3 tests/planner_test.py [--update]
"""
import asyncio, difflib, json, re, sys
from harness import FIX, serve, open_planner, go, settle
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
    for live in (False, True):
        name = "live address: a change saves" if live else "preview address: a change saves nothing and says so"
        b, pg, errors = await open_planner(p, port, live=live)
        await go(pg, "home")
        box = "input[data-tododone]"
        if not await pg.evaluate(f"!!document.querySelector('{box}')"):
            check(False, name, "no to-do to tick on Home"); await b.close(); continue
        await pg.click(box); await pg.wait_for_timeout(900)
        writes = await pg.evaluate("window.__WRITES.map(w => w.t || w.rpc || 'file')")
        label = await pg.evaluate("document.getElementById('savestate').textContent")
        notice = await pg.evaluate("!!document.querySelector('.eqpreview')")
        ok = ("planner_state" in writes and not notice and "preview" not in label) if live else (writes == [] and notice and "preview" in label)
        check(ok, name, f"writes {writes}, indicator '{label}', notice {notice}")
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
            await part("loads by hand", manual_loads(p, port))
    leases_named(got)
    compare(got)
    print(f"\n{len(failures)} planner check(s) failed" if failures else "\nplanner: all passed")
    sys.exit(1 if failures else 0)


asyncio.run(main())
