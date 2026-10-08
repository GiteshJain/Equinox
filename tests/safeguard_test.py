import json, asyncio
from playwright.async_api import async_playwright
exec(open('/home/claude/ctest.py').read().split("async def run(")[0])
def stub2():
    base=stub({})
    # cloud copy's saved time is controllable from the test, to simulate someone else saving
    return base.replace("async maybeSingle(){return {data: t==='planner_state'?{json:JSON.stringify(window.__STATE),saved_at:1}:null,error:null}}",
                        "async maybeSingle(){return {data: t==='planner_state'?{json:JSON.stringify(window.__STATE),saved_at:(window.__cloudSaved||1)}:null,error:null}}")
async def go():
    async with async_playwright() as p:
        b=await p.chromium.launch(); ctx=await b.new_context(viewport={"width":1440,"height":1000})
        await ctx.add_init_script("localStorage.setItem('gander-auth', JSON.stringify({access_token:'t'}));")
        pg=await ctx.new_page(); errs=[]; pg.on("pageerror", lambda e: errs.append(str(e)[:200]))
        ST=stub2()
        async def route(r):
            u=r.request.url
            if "supabase" in u and u.endswith(".js"): await r.fulfill(body=ST, content_type="application/javascript")
            elif "/rest/v1/planner_data" in u: await r.fulfill(body=json.dumps([{"value":json.loads(DATA)}]), content_type="application/json")
            else: await r.continue_()
        await pg.route("**/*", route); await pg.goto("http://127.0.0.1:8765/planner/"); await pg.wait_for_timeout(3500)
        # normal save: cloud not newer -> writes
        await pg.evaluate("document.querySelector('nav button[data-view=home]').click()"); await pg.wait_for_timeout(600)
        await pg.fill("#todo-title", "Test to-do A"); await pg.evaluate("document.querySelector('#todo-add').click()"); await pg.wait_for_timeout(1200)
        s1=await pg.evaluate("window.__saves")
        # someone else saves a newer copy (Claude via the database)
        await pg.evaluate("window.__cloudSaved = Date.now() + 10000000")
        await pg.fill("#todo-title", "Test to-do B"); await pg.evaluate("document.querySelector('#todo-add').click()"); await pg.wait_for_timeout(1500)
        s2=await pg.evaluate("window.__saves"); toast=await pg.evaluate("(document.querySelector('.eqtoast')||{textContent:''}).textContent")
        hasB=await pg.evaluate("document.body.innerText.includes('Test to-do B')")
        print(f"normal save wrote to the cloud: {s1>=1} | after a newer cloud copy: extra writes {s2-s1} (expect 0) | change kept on screen: {hasB} (expect False)\n toast: {toast}")
        print("page errors:", errs); await b.close()
asyncio.run(go())
