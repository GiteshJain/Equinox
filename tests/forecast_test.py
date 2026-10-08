import json, asyncio
from playwright.async_api import async_playwright
exec(open('/home/claude/ctest.py').read().split("async def run(")[0])
REAL={"game_capture_raw":[{"airline":"Kingfisher","kind":k,"captured_at":"2026-10-07T21:20:3%d+00:00"%i} for i,k in enumerate(["loads","statement","events","pnl","balance"])],
 "game_balance":[{"amount":6902068,"airline":"Kingfisher","captured_at":"2026-10-07T21:20:38.848803+00:00","captured_on":"2026-10-07"}],
 "game_ops_recent":[{"airline":"Kingfisher","flights":48,"income":2055084,"costs":803361,"hours":21.6,"last_ts":"2026-10-07T20:15:00+00:00"},{"airline":"China Eastern","flights":1,"income":23604,"costs":8199,"hours":0,"last_ts":"2026-10-07T03:30:00+00:00"}],
 "game_events":[{"airline":"Kingfisher","event_date":d,"event_time":t,"debit":m,"descr":x} for d,t,m,x in [("2026-10-08","07:35",237570,"Leasing payment for VT-AAK (Airbus A321NEO Light)"),("2026-10-08","07:37",286245,"Leasing payment for VT-AAC (Airbus A321XLR)"),("2026-10-08","16:35",719395,"Leasing payment for VT-AAB (Airbus A350-900ULR)"),("2026-10-09","04:37",286245,"Leasing payment for VT-AAD (Airbus A321XLR)"),("2026-10-09","09:04",647459,"Week-end closing of Kingfisher Airlines"),("2026-10-10","01:37",286245,"Leasing payment for VT-AAE (Airbus A321XLR)"),("2026-10-10","07:15",214510,"Leasing payment for VT-AAM (Airbus A320NEO Light)"),("2026-10-10","22:37",237570,"Leasing payment for VT-AAF (Airbus A321NEO Light)"),("2026-10-11","19:37",237570,"Leasing payment for VT-AAG (Airbus A321NEO Light)"),("2026-10-12","16:37",237570,"Leasing payment for VT-AAH (Airbus A321NEO Light)"),("2026-10-13","13:37",237570,"Leasing payment for VT-AAI (Airbus A321NEO Light)"),("2026-10-14","10:37",719395,"Leasing payment for VT-AAA (Airbus A350-900ULR)"),("2026-10-14","10:37",237570,"Leasing payment for VT-AAJ (Airbus A321NEO Light)")]]}
async def go():
    async with async_playwright() as p:
        b=await p.chromium.launch(); ctx=await b.new_context(viewport={"width":1440,"height":1000})
        await ctx.add_init_script("localStorage.setItem('gander-auth', JSON.stringify({access_token:'t'}));")
        pg=await ctx.new_page(); errs=[]; pg.on("pageerror", lambda e: errs.append(str(e)[:200]))
        ST=stub(REAL)
        async def route(r):
            u=r.request.url
            if "supabase" in u and u.endswith(".js"): await r.fulfill(body=ST, content_type="application/javascript")
            elif "/rest/v1/planner_data" in u: await r.fulfill(body=json.dumps([{"value":json.loads(DATA)}]), content_type="application/json")
            else: await r.continue_()
        await pg.route("**/*", route); await pg.goto("http://127.0.0.1:8765/planner/"); await pg.wait_for_timeout(3500)
        await pg.evaluate("document.querySelector('nav button[data-view=finance]').click()"); await pg.wait_for_timeout(1000)
        cards=await pg.evaluate("[...document.querySelectorAll('.fcard')].map(c=>{const dl=[...c.querySelectorAll('dt')].find(d=>/Next order/.test(d.textContent)); return c.querySelector('b').textContent+': '+(dl?dl.nextElementSibling.textContent:'')})")
        print("Finance cards, next order:", cards)
        await pg.evaluate("document.querySelector('[data-final=Kingfisher]').click()"); await pg.wait_for_timeout(1000)
        fb=await pg.evaluate("(()=>{const h=[...document.querySelectorAll('h3')].find(x=>/^Cash, next 14 days/.test(x.textContent)); if(!h) return 'NO BOARD'; const bd=h.closest('.board'); return [...bd.querySelectorAll('.fcfacts span, .fcsafe')].map(x=>x.textContent.replace(/\\s+/g,' ').trim()).join(' || ')})()")
        print("Kingfisher forecast:", fb)
        await pg.evaluate("(()=>{const h=[...document.querySelectorAll('h3')].find(x=>/^Cash, next 14 days/.test(x.textContent)); h.scrollIntoView({block:'start'}); window.scrollBy(0,-90)})()"); await pg.wait_for_timeout(500)
        await pg.screenshot(path="/home/claude/shots/forecast_kf.png", clip={"x":0,"y":0,"width":1440,"height":470})
        await pg.evaluate("document.querySelector('[data-final=\"China Eastern\"]').click()"); await pg.wait_for_timeout(800)
        ce=await pg.evaluate("(()=>{const h=[...document.querySelectorAll('h3')].find(x=>/^Cash, next 14 days/.test(x.textContent)); return h? h.closest('.board').querySelector('.dim').textContent:'none'})()")
        print("China Eastern (no full statement yet):", ce)
        await pg.evaluate("document.querySelector('nav button[data-view=review]').click()"); await pg.wait_for_timeout(1000)
        hp=await pg.evaluate("[...document.querySelectorAll('.hp')].map(x=>x.textContent.replace(/\\s+/g,' ').trim())")
        print("Hubs towards 750:", hp)
        print("errors:", errs); await b.close()
asyncio.run(go())
