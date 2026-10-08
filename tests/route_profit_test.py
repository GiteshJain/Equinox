import json, asyncio
from playwright.async_api import async_playwright
exec(open('/home/claude/ctest.py').read().split("async def run(")[0])
C=json.load(open('/home/claude/capture_export.json'))
G={"game_capture_raw":C['runs'],"game_loads":C['loads'],"game_events":C['events'],"game_balance":C['balance'],"game_ops_recent":C['ops'],"game_flight_pnl":C['pnl']}
async def go():
    async with async_playwright() as p:
        b=await p.chromium.launch(); ctx=await b.new_context(viewport={"width":1440,"height":1000})
        await ctx.add_init_script("localStorage.setItem('gander-auth', JSON.stringify({access_token:'t'}));")
        pg=await ctx.new_page(); errs=[]; pg.on("pageerror", lambda e: errs.append(str(e)[:200])); ST=stub(G)
        async def route(r):
            u=r.request.url
            if "supabase" in u and u.endswith(".js"): await r.fulfill(body=ST, content_type="application/javascript")
            elif "/rest/v1/planner_data" in u: await r.fulfill(body=json.dumps([{"value":json.loads(DATA)}]), content_type="application/json")
            else: await r.continue_()
        await pg.route("**/*", route); await pg.goto("http://127.0.0.1:8765/planner/"); await pg.wait_for_timeout(3500)
        await pg.evaluate("document.querySelector('nav button[data-view=finance]').click()"); await pg.wait_for_timeout(900)
        await pg.evaluate("document.querySelector('[data-final=Kingfisher]').click()"); await pg.wait_for_timeout(1200)
        res=await pg.evaluate("""(()=>{const h=[...document.querySelectorAll('h3')].find(x=>/^Route profit/.test(x.textContent)); if(!h) return {err:'NO BOARD'}; const bd=h.closest('.board');
          const tabs=[...bd.querySelectorAll('table')]; const rows=t=>[...t.querySelectorAll('tr')].slice(1).map(tr=>[...tr.children].map(td=>td.textContent.trim()).join(' | '));
          return {note: bd.querySelector('.note[style]') ? bd.querySelector('.note[style]').textContent : '', routes: tabs[0]?rows(tabs[0]):[], aircraft: tabs[1]?rows(tabs[1]):[], fares: bd.innerText.includes('None yet')}})()""")
        print("note:", res.get('note')); print("ROUTES (first 8):"); [print("  ", r) for r in res.get('routes',[])[:8]]
        print("   … weakest:"); [print("  ", r) for r in res.get('routes',[])[-4:]]
        print("AIRCRAFT:"); [print("  ", r) for r in res.get('aircraft',[])]
        print("fare changes section shows 'none yet':", res.get('fares'))
        await pg.evaluate("(()=>{const h=[...document.querySelectorAll('h3')].find(x=>/^Route profit/.test(x.textContent)); h.scrollIntoView({block:'start'}); window.scrollBy(0,-90)})()"); await pg.wait_for_timeout(500)
        await pg.screenshot(path="/home/claude/shots/routeprofit_kf.png", clip={"x":0,"y":0,"width":1440,"height":700})
        print("errors:", errs); await b.close()
asyncio.run(go())
