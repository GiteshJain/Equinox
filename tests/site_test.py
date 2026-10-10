"""The public website's automatic check (decision #9).

Opens every page of the site on the frozen sample, with the clock frozen at its moment and nothing reaching the real
database, and checks each one shows its content with no errors: home, flights, destinations, live network, our airlines
and each airline's page, the newsroom and an article, investors, about, gander monthly, an unknown address, and the
link into the planner.

Every page is opened twice (#13, pull request 8): on the feed site_public() gives since then, which carries our airlines
(names, codes, colours, text and order, from the airlines table), and on the sample's own feed, which doesn't, so the
website's own copy is used. Both show the airlines in the site's order; with the airlines in the feed, the text comes
from the feed.

Usage: python3 tests/site_test.py
"""
import asyncio, contextlib, json, sys
from harness import serve, sample
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


async def main():
    S = sample()
    old = S["site_public"]
    assert "airlines" not in old, "the sample's feed already has airlines: the fallback isn't tested any more"
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
            await b.close()
    print(f"\n{len(failures)} website check(s) failed" if failures else "\nwebsite: all passed")
    sys.exit(1 if failures else 0)


asyncio.run(main())
