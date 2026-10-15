"""The public website's automatic check (decision #9).

Opens every page of the site on the frozen sample, with the clock frozen at its moment and nothing reaching the real
database, and checks each one shows its content with no errors: home, flights, destinations, live network, our airlines
and each airline's page, the newsroom and an article, investors, about, gander monthly, an unknown address, and the
link into the planner. Then the planner's addresses (#18 build pull requests 13 and 14): the planner at /planner/ (its
sign-in form, its files from /app/, no errors) and at a screen's own address; the addresses used while it was built
(/planner/next/...) moved to the same address under /planner/; the old planner's address (/planner/old/), gone with it in
the clean-up, goes to /planner/.
Then the trip search (#19): on a small made-up week, transfers follow the planning library's connection rule
(web/assets/rules.js, built by npm run build): one at exactly the airport's minimum connection time and one at exactly
8 hours are offered, one a minute under the minimum and one of 9 hours (which the old 10-hour window offered) are not;
the same on a feed without content.connection_max_wait_h (8 hours), and the 9-hour one is offered when the feed says
10; the page loads rules.js with no errors.
Then every airport's name and photo (spec docs/specs/2026-10-15-last-leftovers.md §2): with the airports' website names
and city photos given as data (content.airport_cities, exactly as database/migrations/20261015220000_last_leftovers.sql
fills site_content), the website gives each of the 1,337 airports in web/assets/airports.json the name and photo it gave
before they moved out of its code (tests/fixtures/airport_cities.expected.json, recorded at 7fc2a99). The page's own
apName and apPhoto answer: site.js is served with one line added that hands them to the test.

Every page is opened twice (#13, pull request 8): on the feed site_public() gives since then, which carries our airlines
(names, codes, colours, text and order, from the airlines table), and on the feed without them, so the website's own
copy is used (the sample's own feed, with its airlines key taken out when it has one: samples made since pull request 9
have it). Both show the airlines in the site's order; with the airlines in the feed, the text comes from the feed.

Usage: python3 tests/site_test.py
"""
import asyncio, contextlib, json, sys
from urllib.parse import urlsplit
from harness import FIX, ROOT, WEB, serve, sample
from playwright.async_api import async_playwright

failures = []

# The airlines key as site_public() builds it from the airlines rows (20261009210000_planner_tables.sql), in the data's
# order (position: the planner's), with one role changed so the test can tell the feed's text from the website's copy.
FROM_FEED = "Transatlantic and the Americas (as the data says)"
FEED_AIRLINES = [
    {"key": "Pan American", "name": "Pan Am", "code": "AW", "color": "#2A8FD8", "slug": "pan-am", "region": "North America and across the Atlantic",
     "role": FROM_FEED, "photo": "New York", "position": 1,
     "blurb": "Pan Am is the group's airline for North America and the Atlantic. From New York JFK it connects the United States with Europe, Mexico and the Caribbean, and feeds the rest of the group through London and Paris."},
    {"key": "Kingfisher", "name": "Kingfisher", "code": "KF", "color": "#D7263D", "slug": "kingfisher", "region": "India and South Asia",
     "role": "India, South Asia and the long-haul links from Delhi", "photo": "Delhi", "position": 2,
     "blurb": "Kingfisher connects India from its Delhi hub, flying to cities across the country and long-haul from Delhi to London, Paris, Amsterdam and New York."},
    {"key": "Ryanair", "name": "Ryanair", "code": "FR", "color": "#F1C21B", "slug": "ryanair", "region": "Europe",
     "role": "Europe, point to point", "photo": "Paris", "position": 3,
     "blurb": "Ryanair flies Europe point to point from Paris CDG and Amsterdam, with simple fares, two aircraft types and quick turnarounds."},
    {"key": "Virgin Atlantic", "name": "Virgin Atlantic", "code": "VS", "color": "#8E1537", "slug": "virgin-atlantic", "region": "the United Kingdom and Europe",
     "role": "London and Europe", "photo": "London", "position": 4,
     "blurb": "Virgin Atlantic flies the group's London network from Gatwick, with Manchester and Edinburgh as further bases, linking Britain with more than thirty European cities and with Pan Am across the Atlantic."},
    {"key": "China Eastern", "name": "China Eastern", "code": "MU", "color": "#1C3F8C", "slug": "china-eastern", "region": "China and North-East Asia",
     "role": "China and North-East Asia", "photo": "Shanghai", "position": 5,
     "blurb": "China Eastern flies across China from Shanghai Pudong, with bases at Xi'an, Kunming and Beijing Daxing. It links China with Japan, Korea, Taiwan, Hong Kong and South-East Asia."},
    {"key": "Malaysia Airlines", "name": "Malaysia Airlines", "code": "MH", "color": "#0F8C8C", "slug": "malaysia-airlines", "region": "South-East Asia",
     "role": "South-East Asia and the KUL connecting hub", "photo": "Kuala Lumpur", "position": 6,
     "blurb": "Malaysia Airlines connects China, India and South-East Asia through its Kuala Lumpur hub, linking around forty cities."},
]
SITE_ORDER = ["Pan Am", "Virgin Atlantic", "Ryanair", "Kingfisher", "China Eastern", "Malaysia Airlines"]   # as the site shows them


def check(ok, name, detail=""):
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok or not detail else "\n      " + detail))
    if not ok:
        failures.append(name)


async def new_planner(b, port):
    """The planner's addresses as Cloudflare serves them (tests/harness.py follows web/_redirects), since the switch (#18
    build pull request 13): /planner opens the planner at /planner/ with its sign-in form, its files come from /app/,
    with no errors and no request outside the local server; a screen's own address gives the same page; /planner/next/...
    (the addresses used while it was built) goes (301) to the same address under /planner/; /planner/old/ (the old
    planner's address, gone with it in the clean-up, build pull request 14) goes (301) to /planner/. Built by `npm run
    build` (tests/run_all.sh runs it first). Signed out, the planner reads nothing, so nothing is answered for it.
    tests/planner_next_test.py signs in at each on the rehearsal's copy."""
    print("--- the planner's addresses: the planner at /planner/; /planner/next/ and /planner/old/ moved there")
    if not (WEB / "app" / "index.html").is_file():
        check(False, "the new planner is built (web/app/index.html)", "run npm ci && npm run build first")
        return
    ctx = await b.new_context(viewport={"width": 1280, "height": 900}, timezone_id="UTC", locale="en-US")
    pg = await ctx.new_page(); errors, files, outside = [], [], []
    pg.on("pageerror", lambda e: errors.append("page error: " + str(e)[:300]))
    pg.on("console", lambda m: errors.append("console: " + m.text[:300]) if m.type == "error" and "Failed to load resource" not in m.text else None)
    pg.on("response", lambda r: files.append((urlsplit(r.url).path, r.status)) if f":{port}/app/" in r.url else None)

    async def route(r):
        u = r.request.url
        if f":{port}/" in u or u.startswith("data:"):
            await r.continue_()
        else:
            outside.append(urlsplit(u).hostname or u[:40])
            await r.abort()
    await pg.route("**/*", route)
    resp = await pg.goto(f"http://127.0.0.1:{port}/planner")
    with contextlib.suppress(Exception):
        await pg.wait_for_selector("#g-email", timeout=15000)
    form = await pg.evaluate("!!document.querySelector('#g-email') && !!document.querySelector('#g-pass') && !!document.querySelector('#g-in')")
    check(resp.status == 200 and urlsplit(resp.url).path == "/planner/" and form and not errors,
          "the new planner: /planner opens it at /planner/ with its sign-in form, and no errors",
          f"status {resp.status} at {resp.url}, sign-in form {'shown' if form else 'missing'}, errors {errors}")
    js = [p for p, s in files if p.startswith("/app/assets/") and p.endswith(".js")]
    css = [p for p, s in files if p.startswith("/app/assets/") and p.endswith(".css")]
    bad = [f"{p} ({s})" for p, s in files if s != 200]
    check(js and css and not bad, f"the new planner: its files load from /app/ ({len(js)} script(s), {len(css)} stylesheet(s))",
          f"loaded {files}, failed {bad}")
    check(not outside or set(outside) <= {"fonts.googleapis.com", "fonts.gstatic.com"},
          "the new planner: signed out, it asks nothing of the database (only the fonts were stopped)", f"stopped: {sorted(set(outside))}")
    resp = await pg.goto(f"http://127.0.0.1:{port}/planner/review/VS")
    with contextlib.suppress(Exception):
        await pg.wait_for_selector("#g-email", timeout=15000)
    check(resp.status == 200 and urlsplit(resp.url).path == "/planner/review/VS" and await pg.evaluate("!!document.querySelector('#g-email')"),
          "the new planner: a screen's own address (/planner/review/VS) gives the same page")
    for path, want in (("/planner/next", "/planner/"), ("/planner/next/routes", "/planner/routes"), ("/planner/next/review/VS", "/planner/review/VS")):
        resp = await pg.goto(f"http://127.0.0.1:{port}{path}")
        first = await resp.request.redirected_from.response() if resp.request.redirected_from else None
        with contextlib.suppress(Exception):
            await pg.wait_for_selector("#g-email", timeout=15000)
        check(first is not None and first.status == 301 and urlsplit(resp.url).path == want and resp.status == 200
              and await pg.evaluate("!!document.querySelector('#g-email')"),
              f"an address used while it was built, {path}, goes (301) to {want}, the new planner",
              f"{first.status if first else 'no redirect'}, ended at {resp.url} ({resp.status})")
    for path in ("/planner/old", "/planner/old/", "/planner/old/index.html"):
        resp = await pg.goto(f"http://127.0.0.1:{port}{path}")
        first = await resp.request.redirected_from.response() if resp.request.redirected_from else None
        with contextlib.suppress(Exception):
            await pg.wait_for_selector("#g-email", timeout=15000)
        check(first is not None and first.status == 301 and urlsplit(resp.url).path == "/planner/" and resp.status == 200
              and await pg.evaluate("!!document.querySelector('#g-email')"),
              f"the old planner's address, {path}, goes (301) to /planner/, the planner",
              f"{first.status if first else 'no redirect'}, ended at {resp.url} ({resp.status})")
    await ctx.close()


# The trip search on the planning library's connection rule (#19, spec docs/specs/2026-10-13-callers.md §3): a small
# made-up Virgin Atlantic week at Gatwick (every airport here is at UTC+0), Gatwick's minimum connection time 60 minutes.
# Edinburgh's flight lands at Gatwick at 09:15; the flights out leave 59 minutes, exactly 60 minutes, exactly 8 hours and
# 9 hours later.
TRIP_FREQS = [   # (destination, out, back: departure and arrival local, flight numbers)
    ("EDI", "06:00", "07:15", "08:00", "09:15", "9101", "9102"),   # the feeder: EDI-LGW lands 09:15
    ("BHD", "10:14", "11:30", "12:15", "13:30", "9501", "9502"),   # 59 minutes: a minute under the minimum
    ("LIS", "10:15", "12:45", "13:30", "16:00", "9201", "9202"),   # exactly the minimum connection time
    ("MAN", "17:15", "18:15", "19:00", "20:00", "9401", "9402"),   # exactly 8 hours
    ("DUB", "18:15", "19:30", "20:15", "21:30", "9301", "9302"),   # 9 hours: found by the old 10-hour window, not now
]
TRIP_EXPECT = {   # destination from Edinburgh -> the trip offered (flight numbers), or None, with the rule's window
    8: {"BHD": None, "LIS": "VS9102>VS9201", "MAN": "VS9102>VS9401", "DUB": None},
    10: {"BHD": None, "LIS": "VS9102>VS9201", "MAN": "VS9102>VS9401", "DUB": "VS9102>VS9301"},
}


def trip_feed(base, wait):
    """The sample's feed with only the made-up week; content.connection_max_wait_h as given (None: the key left out)."""
    content = {"mct": {"LGW": 60}}
    if wait is not None:
        content["connection_max_wait_h"] = wait
    freqs = [{"r": f"Virgin Atlantic|LGW|{d}", "t": "G-TEST1", "a": a, "b": b2, "c": c, "d": d2, "days": "1234567", "o": o, "k": k, "l": "2026-10-01"}
             for d, a, b2, c, d2, o, k in TRIP_FREQS]
    return dict(base, airlines=FEED_AIRLINES, hubs=[{"code": "LGW", "airline": "Virgin Atlantic", "role": "hub"}],
                tails=[{"id": "G-TEST1", "airline": "Virgin Atlantic", "type": "A321 NEO LIGHT"}], freqs=freqs, content=content)


async def trip_search(b, port, S, base):
    print("--- the trip search on the planning library's connection rule (web/assets/rules.js)")
    if not (WEB / "assets" / "rules.js").is_file():
        check(False, "the planning library's browser file is built (web/assets/rules.js)", "run npm ci && npm run build first")
        return
    for name, wait, window_h in [("8 hours in the feed", 8, 8), ("a feed without connection_max_wait_h", None, 8), ("10 hours in the feed", 10, 10)]:
        pub = json.dumps(trip_feed(base, wait))
        ctx = await b.new_context(viewport={"width": 1280, "height": 900}, timezone_id="UTC", locale="en-US")
        pg = await ctx.new_page(); errors, rules_js = [], []
        pg.on("pageerror", lambda e: errors.append("page error: " + str(e)[:300]))
        pg.on("console", lambda m: errors.append("console: " + m.text[:300]) if m.type == "error" and "Failed to load resource" not in m.text else None)
        pg.on("response", lambda r: rules_js.append(r.status) if urlsplit(r.url).path == "/assets/rules.js" else None)

        def answer(pub):   # (Playwright passes the request as a second argument to a handler that takes two)
            async def route(r):
                u = r.request.url
                if "/rest/v1/rpc/site_public" in u:
                    await r.fulfill(body=pub, content_type="application/json")
                elif f":{port}/" in u or u.startswith("data:"):
                    await r.continue_()
                else:
                    await r.abort()
            return route
        await pg.route("**/*", answer(pub))
        await pg.clock.set_fixed_time(S["frozen_at"])
        got, shown = {}, {}
        for dest in TRIP_EXPECT[window_h]:
            await pg.goto(f"http://127.0.0.1:{port}/flights?from=EDI&to={dest}&date=2026-10-12")
            with contextlib.suppress(Exception):
                await pg.wait_for_selector("#results .trip, #results .empty", timeout=10000)
            # each trip card's flight numbers, in order (site.js keeps findTrips to itself, so the page is read as shown)
            got[dest] = await pg.evaluate("[...document.querySelectorAll('#results .trip')].map(t => [...t.querySelectorAll('.lg b')].map(b => b.textContent.trim()).join('>'))")
            shown[dest] = await pg.evaluate("[...document.querySelectorAll('#results .trip')].length + ' trip(s): ' + (document.querySelector('#results') || {}).innerText")
        loaded = await pg.evaluate("!!(window.EqRules && window.EqRules.connections && window.EqRules.connections.isConnection)")
        check(rules_js and all(s == 200 for s in rules_js) and loaded and not errors,
              f"trip search, {name}: the page loads rules.js (window.EqRules) with no errors", f"rules.js answers {rules_js}, loaded {loaded}, errors {errors}")
        for dest, want in TRIP_EXPECT[window_h].items():
            gap = {"BHD": "59 minutes", "LIS": "exactly the minimum connection time (60 minutes)", "MAN": "exactly 8 hours", "DUB": "9 hours"}[dest]
            check(got[dest] == ([want] if want else []), f"trip search, {name}: Edinburgh to {dest} with a transfer of {gap} at Gatwick is {'offered' if want else 'not offered'}",
                  f"the page offers {got[dest]}; {shown[dest][:300]!r}")
        await ctx.close()


# The airports' website names and city photos, as data since 15 Oct (spec 2026-10-15 last leftovers §2): exactly what the
# migration puts in site_content, which site_public() gives as content.airport_cities
CITIES_MIGRATION = ROOT / "database" / "migrations" / "20261015220000_last_leftovers.sql"


def cities_as_data():
    parts = CITIES_MIGRATION.read_text(encoding="utf8").split("$airport_cities$")
    assert len(parts) == 3, "the migration's $airport_cities$ value isn't there once"
    return json.loads(parts[1])


async def airport_cities(b, port, S):
    print("--- every airport's name and photo, with the lists as data (content.airport_cities), as before they moved")
    want = json.loads((FIX / "airport_cities.expected.json").read_text(encoding="utf8"))["airports"]
    cities = cities_as_data()
    base = S["site_public"]
    pub = json.dumps(dict(base, content=dict(base.get("content") or {}, airport_cities=cities)))
    site_js = (WEB / "assets" / "site.js").read_text(encoding="utf8")
    end = site_js.rstrip().rindex("})();")
    hooked = site_js[:end] + "window.__eqSite = { apName, apPhoto };\n" + site_js[end:]   # the page's own functions, for the test
    ctx = await b.new_context(viewport={"width": 1280, "height": 900}, timezone_id="UTC", locale="en-US")
    pg = await ctx.new_page(); errors = []
    pg.on("pageerror", lambda e: errors.append("page error: " + str(e)[:300]))

    async def route(r):
        u = r.request.url
        if "/rest/v1/rpc/site_public" in u:
            await r.fulfill(body=pub, content_type="application/json")
        elif urlsplit(u).path == "/assets/site.js":
            await r.fulfill(body=hooked, content_type="text/javascript")
        elif f":{port}/" in u or u.startswith("data:"):
            await r.continue_()
        else:
            await r.abort()
    await pg.route("**/*", route)
    await pg.clock.set_fixed_time(S["frozen_at"])
    await pg.goto(f"http://127.0.0.1:{port}/destinations")
    got = {}
    with contextlib.suppress(Exception):
        await pg.wait_for_function("() => !!window.__eqSite && document.querySelectorAll('.dcard').length > 0", timeout=20000)
        got = await pg.evaluate("codes => Object.fromEntries(codes.map(c => [c, [window.__eqSite.apName(c), window.__eqSite.apPhoto(c)]]))", sorted(want))
    await ctx.close()
    moved = sorted(c for c in want if got.get(c) != want[c])
    named = sum(1 for c in want if c in cities["name"])
    pictured = sum(1 for c in want if want[c][1])
    check(bool(got) and not moved and not errors,
          f"every airport's name and photo on the website, with the lists as data: the same as before for all {len(want)} airports "
          f"({named} named by the list, {pictured} with a photo)",
          f"{len(moved)} differ: " + ", ".join(f"{c} {got.get(c)} (was {want[c]})" for c in moved[:6]) + (f"; errors {errors}" if errors else ""))


async def main():
    S = sample()
    old = {k: v for k, v in S["site_public"].items() if k != "airlines"}   # the feed without our airlines: the fallback
    feeds = [("feed with airlines", dict(old, airlines=FEED_AIRLINES)), ("old feed, no airlines", old)]
    slugs = ["pan-am", "virgin-atlantic", "ryanair", "kingfisher", "china-eastern", "malaysia-airlines"]
    post = old["posts"][0]["slug"]
    pages = [("/", "home"), ("/flights", "flight schedules"), ("/destinations", "destinations"), ("/network", "live network"),
             ("/airlines", "our airlines")] + [(f"/airlines/{s}", f"airline page: {s}") for s in slugs] + [
             ("/news", "newsroom"), (f"/news/{post}", "a news article"), ("/investors", "investors"), ("/about", "about"),
             ("/newsletter", "gander monthly"), ("/no-such-page", "an unknown address (the not-found page)")]
    with serve() as port:
        async with async_playwright() as p:
            b = await p.chromium.launch()
            for feed_name, feed in feeds:
                print(f"--- {feed_name}")
                pub = json.dumps(feed)
                ctx = await b.new_context(viewport={"width": 1280, "height": 900}, timezone_id="UTC", locale="en-US")
                pg = await ctx.new_page(); errors = []
                pg.on("pageerror", lambda e: errors.append("page error: " + str(e)[:300]))
                pg.on("console", lambda m: errors.append("console: " + m.text[:300]) if m.type == "error" and "Failed to load resource" not in m.text else None)

                async def route(r):
                    u = r.request.url
                    if "/rest/v1/rpc/site_public" in u:
                        await r.fulfill(body=pub, content_type="application/json")
                    elif "/rest/v1/" in u:
                        await r.fulfill(status=401, body='{"message":"not in the test"}', content_type="application/json")
                    elif f":{port}/" in u or u.startswith("data:"):
                        await r.continue_()
                    else:
                        await r.abort()
                await pg.route("**/*", route)
                await pg.clock.set_fixed_time(S["frozen_at"])
                for path, name in pages:
                    before = len(errors)
                    resp = await pg.goto(f"http://127.0.0.1:{port}{path}")
                    with contextlib.suppress(Exception):
                        await pg.wait_for_load_state("networkidle", timeout=10000)
                    await pg.wait_for_timeout(500)
                    n = await pg.evaluate("(document.querySelector('main') || document.body).innerText.trim().length")
                    title = await pg.title()
                    check(resp.status == 200 and n > (40 if "unknown" in name else 150) and title and len(errors) == before,
                          f"{feed_name}: page opens: {name}", f"status {resp.status}, {n} characters, title {title!r}, errors {errors[before:]}")
                    if path == "/airlines":
                        names = await pg.evaluate("[...document.querySelectorAll('.al-tile h3')].map(e => e.textContent.trim())")
                        check(names == SITE_ORDER, f"{feed_name}: our airlines are in the site's order", f"got {names}")
                        text = await pg.evaluate("document.querySelector('main').innerText")
                        if feed is old:
                            check("Transatlantic and the Americas" in text and FROM_FEED not in text,
                                  f"{feed_name}: the airlines' text is the website's own copy")
                        else:
                            check(FROM_FEED in text, f"{feed_name}: the airlines' text comes from the feed")
                if feed is old:
                    r = await pg.goto(f"http://127.0.0.1:{port}/planner")
                    check(r.url.endswith("/planner/") and r.status == 200 and await pg.evaluate("!!document.getElementById('root')"),
                          "the planner link reaches the planner (the new one, at /planner/)", f"ended at {r.url} ({r.status})")
                await ctx.close()
            await new_planner(b, port)
            await trip_search(b, port, S, old)
            await airport_cities(b, port, S)
            await b.close()
    print(f"\n{len(failures)} website check(s) failed" if failures else "\nwebsite: all passed")
    sys.exit(1 if failures else 0)


asyncio.run(main())
