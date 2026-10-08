import json, asyncio, urllib.parse
from playwright.async_api import async_playwright
exec(open('/home/claude/ctest.py').read().split("async def run(")[0])
S0=json.load(open('real_state.json')); LINKS=S0['ref']['gameLinks']; BY_LINK={v:k for k,v in LINKS.items()}
def legs(reg): return S0['plans'][reg]['legs']
def game_for(al):
    if al=='Virgin Atlantic':   # G-AADQ scheduled, arrivals a minute or two earlier than the card (as the game computes them)
        fl=[]
        for L in legs('G-AADQ'):
            h,m=map(int,L['arr'].split(':')); t=(h*60+m-1)%1440; fl.append({"no":L['no'],"from":L['from'],"to":L['to'],"dep":L['dep'],"arr":f"{t//60:02d}:{t%60:02d}","days":"1234567","valid":""})
        return 200, {"airline":al,"flights":fl}
    if al=='China Eastern': return 200, {"airline":al,"flights":[{"no":L['no'],"from":L['from'],"to":L['to'],"dep":L['dep'],"arr":L['arr'],"days":"1234567","valid":""} for L in legs('B-0167')]}
    return 502, {"error":"game unreachable (test)"}
async def go():
    async with async_playwright() as p:
        b=await p.chromium.launch(); ctx=await b.new_context(viewport={"width":1440,"height":1000})
        await ctx.add_init_script("localStorage.setItem('gander-auth', JSON.stringify({access_token:'t'}));")
        pg=await ctx.new_page(); errs=[]; pg.on("pageerror", lambda e: errs.append(str(e)[:200]))
        ST=stub({})
        async def route(r):
            u=r.request.url
            if "supabase" in u and u.endswith(".js"): await r.fulfill(body=ST, content_type="application/javascript")
            elif "/rest/v1/planner_data" in u: await r.fulfill(body=json.dumps([{"value":json.loads(DATA)}]), content_type="application/json")
            elif "/api/game-schedule" in u:
                link=urllib.parse.parse_qs(urllib.parse.urlparse(u).query)['u'][0]; code,body=game_for(BY_LINK.get(link,''))
                await r.fulfill(status=code, body=json.dumps(body), content_type="application/json")
            else: await r.continue_()
        await pg.route("**/*", route); await pg.goto("http://127.0.0.1:8765/planner/"); await pg.wait_for_timeout(3500)
        async def find(reg):
            for v in ["tails","home","routes","review"]:
                await pg.evaluate(f"document.querySelector('nav button[data-view=\"{v}\"]').click()"); await pg.wait_for_timeout(700)
                if await pg.evaluate(f"!!document.querySelector('[data-planfile=\"{reg}\"]')"): return v
        modal=lambda: pg.evaluate("(document.querySelector('#modalroot .modal')||{innerText:''}).innerText.replace(/\\s+/g,' ')")
        toast=lambda: pg.evaluate("(document.querySelector('.eqtoast')||{textContent:''}).textContent")
        # 1. game times differ by a minute: modal, then file with the game's times
        v=await find("G-AADQ"); await pg.evaluate("document.querySelector('[data-planfile=\"G-AADQ\"]').click()"); await pg.wait_for_timeout(1200)
        print("1. G-AADQ (Virgin, arrivals 1 min earlier in the game), found in view:", v); print("   modal:", (await modal())[:420])
        await pg.screenshot(path="/home/claude/shots/filecheck_modal.png")
        await pg.evaluate("document.querySelector('[data-filegame=\"G-AADQ\"]').click()"); await pg.wait_for_timeout(900)
        print("   after 'File with the game's times':", await toast(), "| modal closed:", not await modal(), "| still unfiled:", await pg.evaluate("!!document.querySelector('[data-planfile=\"G-AADQ\"]')"))
        await pg.evaluate("(document.querySelector('[data-plancard=\"G-AADQ\"]')||{click(){}}).click()"); await pg.wait_for_timeout(700)
        await pg.evaluate("(document.querySelector('[data-mclose]')||{click(){}}).click()"); await pg.wait_for_timeout(300)
        await pg.evaluate("document.querySelector('nav button[data-view=tails]').click()"); await pg.wait_for_timeout(700)
        await pg.evaluate("(document.querySelector('tr[data-tail=G-AADQ]')||{click(){}}).click()"); await pg.wait_for_timeout(900)
        txt=await pg.evaluate("document.querySelector('#view').innerText")
        print("   G-AADQ in Tails shows the game's arrivals 11:09 / 12:49 / 01:45:", all(x in txt for x in ['11:09','12:49','01:45']), "| card's 11:10 gone:", '11:10' not in txt)
        # 2. identical in the game: files straight away
        v=await find("B-0167"); await pg.evaluate("document.querySelector('[data-planfile=\"B-0167\"]').click()"); await pg.wait_for_timeout(1300)
        print("2. B-0167 (China Eastern, identical):", await toast(), "| modal open:", bool(await modal()))
        # 3. game unreachable: modal with the card option only
        v=await find("9M-AAK"); await pg.evaluate("document.querySelector('[data-planfile=\"9M-AAK\"]').click()"); await pg.wait_for_timeout(1200)
        print("3. 9M-AAK (game unreachable):", (await modal())[:260], "| game button offered:", await pg.evaluate("!!document.querySelector('[data-filegame]')"))
        await pg.evaluate("document.querySelector('[data-filecard=\"9M-AAK\"]').click()"); await pg.wait_for_timeout(800)
        print("   after 'File with the plan card's times':", await toast())
        print("page errors:", errs); await b.close()
asyncio.run(go())
