"""The public website's automatic check (decision #9).

Opens every page of the site on the frozen sample, with the clock frozen at its moment and nothing reaching the real
database, and checks each one shows its content with no errors: home, flights, destinations, live network, our airlines
and each airline's page, the newsroom and an article, investors, about, gander monthly, an unknown address, and the
link into the planner. Then the new planner (#18) at /planner/next/: its sign-in form, its files from /app/, no errors;
and the old planner still at /planner/.

Every page is opened twice (#13, pull request 8): on the feed site_public() gives since then, which carries our airlines
(names, codes, colours, text and order, from the airlines table), and on the feed without them, so the website's own
copy is used (the sample's own feed, with its airlines key taken out when it has one: samples made since pull request 9
have it). Both show the airlines in the site's order; with the airlines in the feed, the text comes from the feed.

Usage: python3 tests/site_test.py
"""
import asyncio, contextlib, json, sys
from urllib.parse import urlsplit
from harness import WEB, serve, sample
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
    """The new planner (#18) as Cloudflare serves it (tests/harness.py follows web/_redirects): /planner/next/ opens its
    sign-in form, its files come from /app/, with no errors and no request outside the local server; a screen's own
    address gives the same page; /planner/ still opens the old planner. Built by `npm run build` (tests/run_all.sh runs
    it first). Signed out, it reads nothing, so nothing is answered for it."""
    print("--- the new planner at /planner/next/")
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
    resp = await pg.goto(f"http://127.0.0.1:{port}/planner/next")
    with contextlib.suppress(Exception):
        await pg.wait_for_selector("#g-email", timeout=15000)
    form = await pg.evaluate("!!document.querySelector('#g-email') && !!document.querySelector('#g-pass') && !!document.querySelector('#g-in')")
    check(resp.status == 200 and urlsplit(resp.url).path == "/planner/next/" and form and not errors,
          "the new planner: /planner/next opens /planner/next/ with its sign-in form, and no errors",
          f"status {resp.status} at {resp.url}, sign-in form {'shown' if form else 'missing'}, errors {errors}")
    js = [p for p, s in files if p.startswith("/app/assets/") and p.endswith(".js")]
    css = [p for p, s in files if p.startswith("/app/assets/") and p.endswith(".css")]
    bad = [f"{p} ({s})" for p, s in files if s != 200]
    check(js and css and not bad, f"the new planner: its files load from /app/ ({len(js)} script(s), {len(css)} stylesheet(s))",
          f"loaded {files}, failed {bad}")
    check(not outside or set(outside) <= {"fonts.googleapis.com", "fonts.gstatic.com"},
          "the new planner: signed out, it asks nothing of the database (only the fonts were stopped)", f"stopped: {sorted(set(outside))}")
    resp = await pg.goto(f"http://127.0.0.1:{port}/planner/next/review/VS")
    with contextlib.suppress(Exception):
        await pg.wait_for_selector("#g-email", timeout=15000)
    check(resp.status == 200 and await pg.evaluate("!!document.querySelector('#g-email')"),
          "the new planner: a screen's own address (/planner/next/review/VS) gives the same page")
    resp = await pg.goto(f"http://127.0.0.1:{port}/planner/")
    old = await pg.evaluate("!!document.querySelector('header nav button[data-view=routes]') && document.title === 'equinox. planner'")
    check(resp.status == 200 and old, "the old planner still opens at /planner/", f"status {resp.status}")
    await ctx.close()


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
                    check(r.url.endswith("/planner/") and r.status == 200, "the planner link reaches the planner", f"ended at {r.url} ({r.status})")
                await ctx.close()
            await new_planner(b, port)
            await b.close()
    print(f"\n{len(failures)} website check(s) failed" if failures else "\nwebsite: all passed")
    sys.exit(1 if failures else 0)


asyncio.run(main())
