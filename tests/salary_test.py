import asyncio, json
from playwright.async_api import async_playwright
ROWS=[1508,1734,528,414,1400,754,786,604,852,872,452,776,970,720,720]
CUR=[1617,1859,565,444,1540,809,843,647,913,935,485,832,1040,792,792]
BASE="http://127.0.0.1:8767"
async def run(mode):
    async with async_playwright() as p:
        b=await p.chromium.launch(); pg=await b.new_page(); errs=[]; pg.on("pageerror", lambda e: errs.append(str(e)[:200]))
        await pg.goto(BASE+"/app/enterprise/dashboard"); await pg.wait_for_timeout(400)
        await pg.evaluate("m => { sessionStorage.clear(); sessionStorage.setItem('mock_mode', m); sessionStorage.setItem('eq_capture_all', JSON.stringify({ i: 5, phase: 'salary', start: 112, salaryUrl: location.origin + '/app/hr/overview', salaryTried: false, salaryChanged: 0, log: ['equinox. capture, all airlines…'] })); }", mode)
        await pg.goto(BASE+"/app/hr/overview")
        for _ in range(70):
            await pg.wait_for_timeout(1000)
            if "dashboard" in pg.url: break
        await pg.wait_for_timeout(1500)
        saved=json.loads(await pg.evaluate("sessionStorage.getItem('mock_sal') || '{}'")); clicks=await pg.evaluate("sessionStorage.getItem('mock_clicks')")
        final=[int(saved.get(str(i), CUR[i])) for i in range(len(ROWS))]; ok=all(abs(f-round(a*1.10))<=1 for f,a in zip(final,ROWS)); print('   final salaries:', final)
        panel=await pg.evaluate("(document.getElementById('eq-cap-panel')||{textContent:''}).textContent")
        print(f"[{mode}] adjust presses: {clicks} | every salary at country average +10%: {ok} | ended on: {pg.url.split('/')[-1]}\n   panel: {panel[-170:]}\n   errors: {errs}")
        # second run on the same day: nothing should change
        if mode=='ajax':
            await pg.evaluate("() => { sessionStorage.setItem('mock_clicks', '0'); sessionStorage.setItem('eq_capture_all', JSON.stringify({ i: 5, phase: 'salary', start: 112, salaryUrl: location.origin + '/app/hr/overview', salaryTried: false, salaryChanged: 0, log: ['rerun'] })); }")
            await pg.goto(BASE+"/app/hr/overview")
            for _ in range(20):
                await pg.wait_for_timeout(1000)
                if "dashboard" in pg.url: break
            rc=await pg.evaluate("sessionStorage.getItem('mock_clicks')")
            print(f"   rerun presses: {rc} (expect 0)")
        await b.close()
async def main():
    await run('reload'); await run('ajax')
asyncio.run(main())
