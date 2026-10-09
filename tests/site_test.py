"""The public website's automatic check (decision #9).

Opens every page of the site on the frozen sample, with the clock frozen at its moment and nothing reaching the real
database, and checks each one shows its content with no errors: home, flights, destinations, live network, our airlines
and each airline's page, the newsroom and an article, investors, about, gander monthly, an unknown address, and the
link into the planner.

Usage: python3 tests/site_test.py
"""
import asyncio, contextlib, json, sys
from harness import serve, sample
from playwright.async_api import async_playwright

failures = []


def check(ok, name, detail=""):
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok or not detail else "\n      " + detail))
    if not ok:
        failures.append(name)


async def main():
    S = sample()
    pub = json.dumps(S["site_public"])
    slugs = ["pan-am", "virgin-atlantic", "ryanair", "kingfisher", "china-eastern", "malaysia-airlines"]
    post = S["site_public"]["posts"][0]["slug"]
    pages = [("/", "home"), ("/flights", "flight schedules"), ("/destinations", "destinations"), ("/network", "live network"),
             ("/airlines", "our airlines")] + [(f"/airlines/{s}", f"airline page: {s}") for s in slugs] + [
             ("/news", "newsroom"), (f"/news/{post}", "a news article"), ("/investors", "investors"), ("/about", "about"),
             ("/newsletter", "gander monthly"), ("/no-such-page", "an unknown address (the not-found page)")]
    with serve() as port:
        async with async_playwright() as p:
            b = await p.chromium.launch()
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
                check(resp.status == 200 and n > (40 if "unknown" in name else 150) and title and len(errors) == before, f"page opens: {name}",
                      f"status {resp.status}, {n} characters, title {title!r}, errors {errors[before:]}")
            r = await pg.goto(f"http://127.0.0.1:{port}/planner")
            check(r.url.endswith("/planner/") and r.status == 200, "the planner link reaches the planner", f"ended at {r.url} ({r.status})")
            await b.close()
    print(f"\n{len(failures)} website check(s) failed" if failures else "\nwebsite: all passed")
    sys.exit(1 if failures else 0)


asyncio.run(main())
