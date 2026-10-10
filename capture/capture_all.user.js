// ==UserScript==
// @name         equinox. capture all airlines
// @namespace    equinox
// @version      1.4
// @description  One button: for each of the world's airlines (the database lists them), captures loads, finances and payments for the planner. Salaries are a separate script (salary_adjust.user.js), run by hand on one airline.
// @match        https://gander.airlinesim.aero/*
// @grant        none
// ==/UserScript==
(function () {
  const KEY = "__CAPTURE_KEY__", ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZWN3c3llZHZ3Y3hnZHptaG9xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMTg5MzcsImV4cCI6MjEwNTc5NDkzN30.tC56dOgmPeYB3m58aDy4ADnnaZ3613P6MFp2pVXUj_Y", RPC = "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/";
  // the airlines to capture come from the database (capture_airlines, with the key), as [game ID, name, the game's name]
  const airlinesOf = s => (s && s.airlines) || [];
  const ST = "eq_capture_all"; const get = () => { try { return JSON.parse(sessionStorage.getItem(ST) || "null"); } catch (e) { return null; } }; const set = s => sessionStorage.setItem(ST, JSON.stringify(s)); const clear = () => sessionStorage.removeItem(ST);
  const cells = tr => [...tr.querySelectorAll("td,th")].map(td => td.textContent.replace(/\s+/g, " ").trim());
  const rowsOf = doc => [...doc.querySelectorAll("table tr")].map(cells).filter(r => r.some(x => x));
  const fetchDoc = async url => { const r = await fetch(url, { credentials: "include" }); if (!r.ok) throw new Error(url + " " + r.status); return new DOMParser().parseFromString(await r.text(), "text/html"); };
  const rpc = async (fn, body) => { const r = await fetch(RPC + fn, { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" }, body: JSON.stringify(body) }); return r.json(); };
  const send = (gameId, kind, rows, page) => rpc("capture_ingest", { p_key: KEY, p_airline: String(gameId), p_kind: kind, p_page: page, p_rows: rows });   // the airline by its game ID
  const loadAirlines = async () => { const r = await rpc("capture_airlines", { p_key: KEY }); if (!r || !r.ok || !Array.isArray(r.airlines) || !r.airlines.length) throw new Error((r && (r.error || r.message)) || "no airlines"); return r.airlines.map(a => [a.game_id, a.name, a.game_name || a.name]); };
  const panel = () => { let b = document.getElementById("eq-cap-panel"); if (!b) { b = document.createElement("div"); b.id = "eq-cap-panel"; b.style.cssText = "position:fixed;top:12px;right:12px;z-index:999999;background:#0A1230;color:#fff;font:14px/1.5 system-ui,sans-serif;padding:14px 18px;border-radius:14px;box-shadow:0 20px 50px rgba(0,0,0,.4);max-width:380px;white-space:pre-line"; document.body.appendChild(b); } return b; };
  const log = t => { const s = get(); if (s) { s.log = (s.log || []).concat(t).slice(-40); set(s); } panel().textContent = (get() ? get().log.join("\n") : t); };
  const currentId = async list => { const d = await fetchDoc("/action/enterprise/schedule"); const t = d.body.textContent, i = t.indexOf("Events overview for "); const n = i >= 0 ? t.slice(i + 20, i + 60).trim() : ""; const hit = list.find(a => n.startsWith(a[2]) || n.startsWith(a[1])); return hit ? hit[0] : null; };
  async function captureCurrent(id, name) {
    let r = await send(id, "events", rowsOf(await fetchDoc("/action/enterprise/schedule")), "/action/enterprise/schedule"); log(name + " · events " + (r.rows ?? r.error));
    let url = "/app/finance/accounting/2", all = [], pages = 0; const since = Date.now() - 3 * 864e5;
    while (url && pages < 15) { const doc = await fetchDoc(url); const rows = rowsOf(doc).filter(x => /^\d\d\.\d\d\. \d\d:\d\d/.test(x[0])); all.push(...rows); pages++;
      const last = rows[rows.length - 1]; if (last) { const d = last[0]; if (Date.UTC(new Date().getUTCFullYear(), +d.slice(3, 5) - 1, +d.slice(0, 2), +d.slice(7, 9), +d.slice(10, 12)) < since) break; }
      const next = [...doc.querySelectorAll("a")].find(a => a.textContent.trim() === ">"); url = next ? new URL(next.getAttribute("href"), new URL(url, location.origin)).href : null; }
    r = await send(id, "statement", all, "/app/finance/accounting/2"); log(name + " · statement " + (r.rows ?? r.error) + " lines, " + pages + " pages");
    r = await send(id, "pnl", rowsOf(await fetchDoc("/app/finance/accounting/0")), "/app/finance/accounting/0"); log(name + " · income statement " + (r.rows ?? r.error));
    r = await send(id, "balance", rowsOf(await fetchDoc("/app/finance/accounting/1")), "/app/finance/accounting/1"); log(name + " · balance sheet " + (r.rows ?? r.error));
    r = await send(id, "loads", rowsOf(document), location.pathname); log(name + " · loads " + (r.rows ?? r.error) + " flights");
  }
  const onLoads = () => location.pathname.includes("/app/com/loads");
  function setFilter() {   // -24h until now only, load factor on, "less than or equal", 100%
    const q = n => document.querySelector('[name="' + n + '"]'); const fire = el => el.dispatchEvent(new Event("change", { bubbles: true }));
    const tick = (n, v) => { const el = q(n); if (el && el.checked !== v) { el.checked = v; fire(el); } };
    tick("filters:timeFrame-check", true); tick("filters:timeFrameM48", false); tick("filters:timeFrameM24", true); tick("filters:timeFrame0", false); tick("filters:timeFrame24", false); tick("filters:timeFrame48", false);
    tick("filters:origin-check", false); tick("filters:destination-check", false); tick("filters:fleet-check", false); tick("filters:flightNumberGroup-check", false); tick("filters:loadFactor-check", true);
    const m = q("filters:loadFactor-method"); if (m) { const opt = [...m.options].find(o => /less than or equal/i.test(o.textContent)); if (opt && m.value !== opt.value) { m.value = opt.value; fire(m); } }
    const lf = q("filters:loadFactor"); if (lf && lf.value !== "100") { lf.value = "100"; fire(lf); }
  }
  function nextAirline() {
    const t = get(); if (!t) return; t.i = t.i + 1;
    if (t.i < airlinesOf(t).length) { t.phase = "switch"; set(t); step(); } else { t.phase = "home"; set(t); location.href = "/app/enterprise/dashboard?select=" + t.start; }
  }
  async function step() {
    const s = get(); if (!s) return;
    const [id, name] = airlinesOf(s)[s.i] || [];
    if (s.phase === "switch") { s.phase = "open"; set(s); location.href = "/app/enterprise/dashboard?select=" + id; return; }
    if (s.phase === "open") { s.phase = "filter"; set(s); location.href = "/app/com/loads"; return; }
    if (s.phase === "filter" && onLoads()) { setFilter(); s.phase = "capture"; set(s); await new Promise(r => setTimeout(r, 1500));
      const upd = [...document.querySelectorAll("a")].find(a => /Update Results/.test(a.textContent)); if (upd) { upd.click(); setTimeout(() => { const t = get(); if (t && t.phase === "capture") step(); }, 4000); } else { log("No Update Results link; capturing as is"); step(); } return; }
    if (s.phase === "capture" && onLoads()) { try { await captureCurrent(id, name); } catch (e) { log(name + " · problem: " + e.message); }
      nextAirline(); return; }
    if (s.phase === "home") { log("Done: all " + airlinesOf(s).length + " airlines captured. Back on the airline you started with."); panel().onclick = () => { panel().remove(); clear(); }; clear(); return; }
  }
  function addButton() {
    if (document.getElementById("eq-cap-btn")) return; const b = document.createElement("button"); b.id = "eq-cap-btn"; b.textContent = "Capture all airlines"; b.style.cssText = "position:fixed;bottom:16px;right:16px;z-index:999998;background:#F6B44B;color:#0A1230;border:0;border-radius:999px;padding:10px 16px;font:700 13px system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.35);cursor:pointer";
    b.onclick = async () => { b.disabled = true; let list;
      try { list = await loadAirlines(); } catch (e) { panel().textContent = "equinox. capture: couldn't get the airlines to capture (" + e.message + "). Check the capture key."; b.disabled = false; return; }
      const start = (await currentId(list)) || list[0][0];
      set({ i: 0, phase: "switch", start, airlines: list, log: ["equinox. capture, all airlines…"] }); log("Starting: " + list.map(a => a[1]).join(", ")); step(); };
    document.body.appendChild(b);
  }
  addButton(); const s = get(); if (s) { panel().textContent = (s.log || []).join("\n"); setTimeout(step, 800); }
})();
