import json, asyncio, datetime, copy
from playwright.async_api import async_playwright
exec(open('/home/claude/ctest.py').read().split("async def run(")[0])
C=json.load(open('/home/claude/capture_export.json'))
G={"game_capture_raw":C['runs'],"game_loads":C['loads'],"game_events":C['events'],"game_balance":C['balance'],"game_ops_recent":C['ops'],"game_flight_pnl":C['pnl']}
tom=(datetime.datetime.now(datetime.UTC)+datetime.timedelta(days=1)).strftime('%Y-%m-%d')
async def page(p, Gx):
    b=await p.chromium.launch(); ctx=await b.new_context(viewport={"width":1440,"height":1000})
    await ctx.add_init_script("localStorage.setItem('gander-auth', JSON.stringify({access_token:'t'}));")
    pg=await ctx.new_page(); errs=[]; pg.on("pageerror", lambda e: errs.append(str(e)[:200])); ST=stub(Gx)
    async def route(r):
        u=r.request.url
        if "supabase" in u and u.endswith(".js"): await r.fulfill(body=ST, content_type="application/javascript")
        elif "/rest/v1/planner_data" in u: await r.fulfill(body=json.dumps([{"value":json.loads(DATA)}]), content_type="application/json")
        else: await r.continue_()
    await pg.route("**/*", route); await pg.goto("http://127.0.0.1:8765/planner/"); await pg.wait_for_timeout(3500)
    return b, pg, errs
async def go():
    async with async_playwright() as p:
        b, pg, errs = await page(p, G)
        print("Home average load:", await pg.evaluate("[...document.querySelectorAll('.kpi')].map(k=>k.textContent.replace(/\\s+/g,' ').trim()).find(t=>/load/.test(t))"))
        att=lambda: pg.evaluate("[...document.querySelectorAll('ul.att:not(.sub) > li')].map(li=>li.querySelector('summary')? li.querySelector('summary').textContent.replace(/\\s+/g,' ').trim()+' [group]' : li.textContent.replace('×','').trim().slice(0,110))")
        print("needs attention (fresh capture):", await att())
        # fare plan: add a sold-out Kingfisher route
        await pg.evaluate("document.querySelector('nav button[data-view=finance]').click()"); await pg.wait_for_timeout(900)
        await pg.evaluate("document.querySelector('[data-final=Kingfisher]').click()"); await pg.wait_for_timeout(1000)
        key=await pg.evaluate("(document.querySelector('[data-fareadd]')||{dataset:{}}).dataset.fareadd")
        await pg.evaluate("document.querySelector('[data-fareadd]').click()"); await pg.wait_for_timeout(900)
        print("added:", key, "| toast:", await pg.evaluate("(document.querySelector('.eqtoast')||{textContent:''}).textContent"))
        row=lambda: pg.evaluate("(()=>{const h=[...document.querySelectorAll('h3')].find(x=>/^Fare plan/.test(x.textContent)); const tr=h.closest('.board').querySelector('table tr:nth-child(2)'); return tr? [...tr.children].map(td=>td.textContent.trim()).join(' | ') : h.closest('.board').innerText.slice(0,120)})()")
        print("fare plan row:", await row())
        await pg.evaluate("document.querySelector('nav button[data-view=home]').click()"); await pg.wait_for_timeout(800)
        print("needs attention now:", await att())
        # the game change shows up in a later capture: same route, fare up 6%
        o,d=key.split('|')[1], key.split('|')[2]
        sample=[x for x in C['loads'] if x['airline']=='Kingfisher' and x['origin']==o and x['dest']==d][0]
        newrow=dict(sample); newrow.update({"flight_date":tom,"eco_fare":round(float(sample['eco_fare'])*1.06),"eco":100})
        await pg.evaluate("r => { window.__G.game_loads.push(r); }", newrow)
        await pg.evaluate("document.querySelector('nav button[data-view=review]').click()"); await pg.wait_for_timeout(800)
        await pg.evaluate("document.querySelector('#cap-reload').click()"); await pg.wait_for_timeout(1500)
        await pg.evaluate("document.querySelector('nav button[data-view=finance]').click()"); await pg.wait_for_timeout(900)
        print("after the change is captured:", await row())
        await pg.evaluate("document.querySelector('[data-faredel]').click()"); await pg.wait_for_timeout(700)
        print("after remove:", (await row())[:80])
        print("errors:", errs); await b.close()
        # a stale capture: last runs 30 hours ago
        G2=copy.deepcopy(G); old=(datetime.datetime.now(datetime.UTC)-datetime.timedelta(hours=30)).isoformat()
        for r in G2['game_capture_raw']: r['captured_at']=old
        b, pg, errs = await page(p, G2)
        print("needs attention (capture 30 h old):", await pg.evaluate("[...document.querySelectorAll('ul.att li')].map(li=>li.textContent.replace('×','').trim()).filter(t=>/[Cc]apture/.test(t)).slice(0,2)"))
        print("errors:", errs); await b.close()
asyncio.run(go())
