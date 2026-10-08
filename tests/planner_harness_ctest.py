import json, asyncio, sys, datetime
from playwright.async_api import async_playwright
STATE=open('real_state.json').read(); LOADS=json.load(open('real_loads.json')); DATA=open('data.json').read()
rows=[{"month":m,"json":json.dumps(v)} for m,v in LOADS.items()]
d0=datetime.datetime.now(datetime.UTC).replace(tzinfo=None).strftime('%Y-%m-%d'); d1=(datetime.datetime.now(datetime.UTC).replace(tzinfo=None)-datetime.timedelta(days=1)).strftime('%Y-%m-%d')
nd=lambda n:(datetime.datetime.now(datetime.UTC).replace(tzinfo=None)+datetime.timedelta(days=n)).strftime('%Y-%m-%d')
SAMPLE={
 "game_capture_raw":[{"airline":"Kingfisher","kind":k,"captured_at":f"{d0}T21:20:3{i}+00:00"} for i,k in enumerate(["loads","statement","events","pnl","balance"])]+[{"airline":"Malaysia Airlines","kind":"loads","captured_at":f"{d1}T21:00:00+00:00"}],
 "game_loads":[{"airline":"Kingfisher","flight_date":d0,"code":"KF 1021","eco":100,"bus":100,"fst":None,"cargo":100,"eco_pax":156,"eco_seats":156,"bus_pax":16,"bus_seats":16,"fst_pax":None,"fst_seats":None},
               {"airline":"Kingfisher","flight_date":d0,"code":"KF 1001","eco":50,"bus":79,"fst":None,"cargo":97,"eco_pax":132,"eco_seats":264,"bus_pax":19,"bus_seats":24,"fst_pax":None,"fst_seats":None}],
 "game_balance":[{"airline":"Kingfisher","captured_on":d0,"amount":5753000,"captured_at":f"{d0}T21:20:38+00:00"}],
 "game_events":[{"airline":"Kingfisher","event_date":d0,"event_time":"07:35","debit":237570},
                {"airline":"Kingfisher","event_date":nd(1),"event_time":"07:35","debit":237570},
                {"airline":"Kingfisher","event_date":nd(2),"event_time":"09:04","debit":647459},
                {"airline":"Kingfisher","event_date":nd(8),"event_time":"07:35","debit":237570}]}
def stub(sample):
    return """
window.__STATE=%s; window.__LOADS=%s; window.__G=%s; window.__saves=0;
window.supabase={createClient:()=>({
 from:(t)=>{const q={t, select(){return q},eq(){return q},order(){return q},gte(){return q},lte(){return q},like(){return q},limit(){return q},range(){return q},
   async maybeSingle(){return {data: t==='planner_state'?{json:JSON.stringify(window.__STATE),saved_at:1}:null,error:null}},
   then(r){r({data: t==='planner_loads'?window.__LOADS:(window.__G[t]||[]),error:null})}, async upsert(){window.__saves++; return {error:null}}}; return q;},
 rpc: async(n)=>({data: n==='site_public' ? {content:{media:{photos:{},airports:{}}}} : true, error:null}),
 storage:{from:()=>({upload:async()=>({error:null}),getPublicUrl:()=>({data:{publicUrl:'https://example.com/x.jpg'}}),remove:async()=>({})})},
 auth:{getSession:async()=>({data:{session:{user:{email:'gitesh@example.com'}}}}),onAuthStateChange(cb){return {data:{subscription:{unsubscribe(){}}}}},signOut:async()=>{}}
})};
""" % (STATE, json.dumps(rows), json.dumps(sample))
async def run(label, sample):
    async with async_playwright() as p:
        b=await p.chromium.launch(); ctx=await b.new_context(viewport={"width":1440,"height":1000})
        await ctx.add_init_script("localStorage.setItem('gander-auth', JSON.stringify({access_token:'t'}));")
        pg=await ctx.new_page(); errs=[]
        pg.on("pageerror", lambda e: errs.append("pageerror: "+str(e)[:200])); pg.on("console", lambda m: errs.append("console: "+m.text[:160]) if m.type=="error" else None)
        S=stub(sample)
        async def route(r):
            u=r.request.url
            if "supabase" in u and u.endswith(".js"): await r.fulfill(body=S, content_type="application/javascript")
            elif "/rest/v1/planner_data" in u: await r.fulfill(body=json.dumps([{"value":json.loads(DATA)}]), content_type="application/json")
            elif "/api/game-schedule" in u: await r.fulfill(body=json.dumps({"flights":[]}), content_type="application/json")
            else: await r.continue_()
        await pg.route("**/*", route); await pg.goto("http://127.0.0.1:8765/planner/"); await pg.wait_for_timeout(4000)
        await pg.evaluate("document.querySelector('nav button[data-view=\"review\"]').click()"); await pg.wait_for_timeout(1500)
        board=await pg.evaluate("(()=>{const h=[...document.querySelectorAll('h3')].find(x=>/^Capture/.test(x.textContent)); if(!h) return 'NO BOARD'; return [...h.closest('.board').querySelectorAll('tr')].map(tr=>[...tr.children].map(td=>td.textContent.trim()).join(' | ')).join('\\n')})()")
        cash=await pg.evaluate("(()=>{const out=[]; document.querySelectorAll('input').forEach(i=>{const k=(i.dataset&&Object.values(i.dataset).join(' '))||''; if(/Kingfisher/.test(k)) out.push(k+'='+i.value)}); return out.slice(0,6)})()")
        print('cash/fixed inputs for Kingfisher:', cash)
        kf=await pg.evaluate("(()=>{const q=[...document.querySelectorAll('.qcard')].find(c=>/Kingfisher/i.test(c.innerHTML)); return q? q.querySelector('.qh').innerText.replace(/\\s+/g,' ') + ' || ' + [...q.querySelectorAll('.capl')].map(x=>x.parentElement.innerText.replace(/\\s+/g,' ')+(x.classList.contains('low')?' [low]':'')).join(' | '):'no KF card'})()")
        await pg.screenshot(path=f"/home/claude/shots/cap_{label}_review.png")
        # Reload button
        await pg.evaluate("document.querySelector('#cap-reload').click()"); await pg.wait_for_timeout(1200)
        reload_ok=await pg.evaluate("!!document.querySelector('#cap-reload') && /checked at/.test(document.querySelector('#cap-reload').parentElement.innerText)")
        await pg.evaluate("document.querySelector('nav button[data-view=\"finance\"]').click()"); await pg.wait_for_timeout(1500)
        fin=await pg.evaluate("[...document.querySelectorAll('.fcard')].map(c=>c.innerText.replace(/\\s+/g,' ').slice(0,80)).filter(t=>/Kingfisher/.test(t))")
        saves=await pg.evaluate("window.__saves")
        print(f"--- {label}\nCapture board: {board}\nKingfisher daily report: {kf}\nReload works: {reload_ok} | saves to cloud: {saves}\nFinance (Kingfisher card): {fin}\nerrors: {errs[:6]}")
        await b.close()
async def main():
    await run("empty", {})
    await run("sample", SAMPLE)
asyncio.run(main())
