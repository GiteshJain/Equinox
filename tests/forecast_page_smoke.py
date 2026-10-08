# Browser smoke test for the ordering parts of the planner, fed the saved capture of 8 Oct 2026.
# Serve web/ first:  python3 -m http.server 8765 --directory web
# Then:              python3 tests/forecast_page_smoke.py
# Prints the Review cards' "Next order", Kingfisher's forecast board, the Home/Growth order flags, the monthly checks,
# and any page errors.
import asyncio, json, pathlib, runpy, sys
from playwright.async_api import async_playwright

HERE = pathlib.Path(__file__).parent
cap = runpy.run_path(str(HERE / "fixtures" / "capture_2026-10-08.py"))["data"]()
STATE = {"version": 1, "ref": {
    "hubs": [{"code": c, "airline": al} for al, c in cap["home"].items()],
    "types": cap["types"], "configs": cap["configs"]}}
DATA = {"routes": [], "utc": cap["utc"], "coords": {}, "countries": {}}
TABLES = {
    "game_balance": [dict(b, captured_on=b["captured_at"][:10]) for b in cap["bal"]],
    "game_events": cap["events"], "game_ops_recent": list(cap["ops"].values()),
    "game_capture_raw": [{"airline": al, "kind": "balance", "captured_at": b["captured_at"]} for al, b in ((x["airline"], x) for x in cap["bal"])],
}
STUB = """
window.__STATE=%s; window.__G=%s;
window.supabase={createClient:()=>({
 from:(t)=>{const q={t, select(){return q},eq(){return q},order(){return q},gte(){return q},lte(){return q},like(){return q},limit(){return q},range(){return q},
   async maybeSingle(){return {data: t==='planner_state'?{json:JSON.stringify(window.__STATE),saved_at:1}:null,error:null}},
   then(r){r({data: window.__G[t]||[], error:null})}, async upsert(){return {error:null}}}; return q;},
 rpc: async(n)=>({data: n==='site_public' ? {content:{media:{photos:{},airports:{}}}} : true, error:null}),
 storage:{from:()=>({upload:async()=>({error:null}),getPublicUrl:()=>({data:{publicUrl:'https://example.com/x.jpg'}}),remove:async()=>({})})},
 auth:{getSession:async()=>({data:{session:{user:{email:'staff@example.com'}}}}),onAuthStateChange(cb){return {data:{subscription:{unsubscribe(){}}}}},signOut:async()=>{}}
})};
""" % (json.dumps(STATE), json.dumps(TABLES))


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(); ctx = await b.new_context(viewport={"width": 1440, "height": 1000})
        await ctx.add_init_script("localStorage.setItem('gander-auth', JSON.stringify({access_token:'t'}));")
        pg = await ctx.new_page(); errs = []
        pg.on("pageerror", lambda e: errs.append("pageerror: " + str(e)[:200]))
        pg.on("console", lambda m: errs.append("console: " + m.text[:160]) if m.type == "error" and "Failed to load resource" not in m.text else None)   # outside requests are blocked on purpose

        async def route(r):
            u = r.request.url
            if "supabase" in u and u.endswith(".js"): await r.fulfill(body=STUB, content_type="application/javascript")
            elif "/rest/v1/planner_data" in u: await r.fulfill(body=json.dumps([{"value": DATA}]), content_type="application/json")
            elif "/api/game-schedule" in u: await r.fulfill(body=json.dumps({"flights": []}), content_type="application/json")
            elif "127.0.0.1" in u or u.startswith("data:"): await r.continue_()
            else: await r.abort()
        await pg.route("**/*", route); await pg.goto("http://127.0.0.1:8765/planner/"); await pg.wait_for_timeout(3500)
        await pg.evaluate("document.querySelector('nav button[data-view=finance]').click()"); await pg.wait_for_timeout(1200)
        cards = await pg.evaluate("[...document.querySelectorAll('.fcard')].map(c=>{const dt=[...c.querySelectorAll('dt')].find(d=>/Next order/.test(d.textContent)); return c.querySelector('b').textContent+': '+(dt?dt.nextElementSibling.textContent:'?')})")
        print("Review cards, next order:"); [print("  " + c) for c in cards]
        await pg.evaluate("document.querySelector('[data-final=\"Virgin Atlantic\"]').click()"); await pg.wait_for_timeout(800)
        fb = await pg.evaluate("(()=>{const h=[...document.querySelectorAll('h3')].find(x=>/^Cash, next 14 days/.test(x.textContent)); if(!h) return 'NO BOARD'; const bd=h.closest('.board'); return h.querySelector('.note').textContent + '\\n  ' + bd.querySelector('.fcsafe').textContent.replace(/\\s+/g,' ').trim()})()")
        print("Virgin forecast board:\n  " + fb)
        sal = await pg.evaluate("/staff salar/i.test(document.body.innerText)")
        print("Staff-salary check anywhere on Review:", sal)
        await pg.evaluate("document.querySelector('nav button[data-view=review]').click()"); await pg.wait_for_timeout(1200)
        flags = await pg.evaluate("[...document.querySelectorAll('.gptr .pill')].map(x=>x.textContent)")
        print("Growth order flags:", flags)
        await pg.evaluate("document.querySelector('nav button[data-view=home]').click()"); await pg.wait_for_timeout(1000)
        print("errors:", errs or "none")
        await b.close()
        return 1 if errs else 0

sys.exit(asyncio.run(main()))
