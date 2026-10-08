/* equinox. one-click capture — runs inside your logged-in AirlineSim page, reads tables, sends them to the planner. Reads only; never acts in the game. */
(async function () {
  const KEY = "__CAPTURE_KEY__", SB = "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/capture_ingest", ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZWN3c3llZHZ3Y3hnZHptaG9xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMTg5MzcsImV4cCI6MjEwNTc5NDkzN30.tC56dOgmPeYB3m58aDy4ADnnaZ3613P6MFp2pVXUj_Y";
  const box = document.createElement("div"); box.style.cssText = "position:fixed;top:12px;right:12px;z-index:999999;background:#0A1230;color:#fff;font:14px/1.5 system-ui,sans-serif;padding:14px 18px;border-radius:14px;box-shadow:0 20px 50px rgba(0,0,0,.4);max-width:360px;white-space:pre-line";
  const log = t => { box.textContent += (box.textContent ? "\n" : "") + t; }; document.body.appendChild(box); log("equinox. capture…");
  const cells = tr => [...tr.querySelectorAll("td,th")].map(td => td.textContent.replace(/\s+/g, " ").trim());
  const rowsOf = doc => [...doc.querySelectorAll("table tr")].map(cells).filter(r => r.some(x => x));
  const get = async url => { const r = await fetch(url, { credentials: "include" }); if (!r.ok) throw new Error(url + " " + r.status); return new DOMParser().parseFromString(await r.text(), "text/html"); };
  const send = async (airline, kind, rows, page) => { const r = await fetch(SB, { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" }, body: JSON.stringify({ p_key: KEY, p_airline: airline, p_kind: kind, p_page: page, p_rows: rows }) }); return r.json(); };
  try {
    const evDoc = await get("/action/enterprise/schedule");
    const NAMES = ["Pan American", "Kingfisher", "Ryanair", "Virgin Atlantic", "China Eastern", "Malaysia Airlines"]; const txt = evDoc.body.textContent, i = txt.indexOf("Events overview for ");
    const airline = (i >= 0 && NAMES.find(n => txt.slice(i + 20, i + 80).trim().startsWith(n))) || prompt("Which airline is this? (Pan American, Kingfisher, Ryanair, Virgin Atlantic, China Eastern or Malaysia Airlines)"); if (!airline) return;
    log("Airline: " + airline);
    let r = await send(airline, "events", rowsOf(evDoc), "/action/enterprise/schedule"); log("Events: " + (r.rows ?? r.error));
    // bank statement: follow the "next" links so every page of the last days is read
    let url = "/app/finance/accounting/2", all = [], pages = 0, oldest = null; const since = Date.now() - 3 * 864e5;
    while (url && pages < 15) {
      const doc = await get(url); const rows = rowsOf(doc).filter(x => /^\d\d\.\d\d\. \d\d:\d\d/.test(x[0])); all.push(...rows); pages++;
      const last = rows[rows.length - 1]; if (last) { const d = last[0]; const t = Date.UTC(new Date().getUTCFullYear(), +d.slice(3, 5) - 1, +d.slice(0, 2), +d.slice(7, 9), +d.slice(10, 12)); oldest = t; if (t < since) break; }
      const next = [...doc.querySelectorAll("a")].find(a => a.textContent.trim() === ">"); url = next ? new URL(next.getAttribute("href"), new URL(url, location.origin)).href : null;
    }
    r = await send(airline, "statement", all, "/app/finance/accounting/2"); log("Statement: " + (r.rows ?? r.error) + " lines, " + pages + " pages");
    const pnl = await get("/app/finance/accounting/0"); r = await send(airline, "pnl", rowsOf(pnl), "/app/finance/accounting/0"); log("Income statement: " + (r.rows ?? r.error));
    const bal = await get("/app/finance/accounting/1"); r = await send(airline, "balance", rowsOf(bal), "/app/finance/accounting/1"); log("Balance sheet: " + (r.rows ?? r.error));
    if (location.pathname.includes("/app/com/loads")) { const rows = rowsOf(document); r = await send(airline, "loads", rows, location.pathname); log("Loads: " + (r.rows ?? r.error) + " flights" + (r.days ? " → planner report updated" : "")); }
    else log("Loads: skipped (run this on Load monitoring with −24h and 100% set)");
    log("Done. You can close this."); box.onclick = () => box.remove(); setTimeout(() => box.remove(), 25000);
  } catch (e) { log("Problem: " + e.message); box.onclick = () => box.remove(); }
})();
