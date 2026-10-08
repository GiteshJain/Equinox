// ==UserScript==
// @name         equinox. capture all airlines
// @namespace    equinox
// @version      1.2
// @description  One button: for each of the six airlines, captures loads, finances and payments for the planner, then sets every salary to 10% above the country average (pressing adjust for each).
// @match        https://gander.airlinesim.aero/*
// @grant        none
// ==/UserScript==
(function () {
  const KEY = "__CAPTURE_KEY__", ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZWN3c3llZHZ3Y3hnZHptaG9xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMTg5MzcsImV4cCI6MjEwNTc5NDkzN30.tC56dOgmPeYB3m58aDy4ADnnaZ3613P6MFp2pVXUj_Y", SB = "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/capture_ingest";
  const AIRLINES = [[113, "Kingfisher"], [112, "Ryanair"], [114, "Pan American"], [203, "Virgin Atlantic"], [208, "China Eastern"], [210, "Malaysia Airlines"]];
  const ST = "eq_capture_all"; const get = () => { try { return JSON.parse(sessionStorage.getItem(ST) || "null"); } catch (e) { return null; } }; const set = s => sessionStorage.setItem(ST, JSON.stringify(s)); const clear = () => sessionStorage.removeItem(ST);
  const cells = tr => [...tr.querySelectorAll("td,th")].map(td => td.textContent.replace(/\s+/g, " ").trim());
  const rowsOf = doc => [...doc.querySelectorAll("table tr")].map(cells).filter(r => r.some(x => x));
  const fetchDoc = async url => { const r = await fetch(url, { credentials: "include" }); if (!r.ok) throw new Error(url + " " + r.status); return new DOMParser().parseFromString(await r.text(), "text/html"); };
  const send = async (airline, kind, rows, page) => { const r = await fetch(SB, { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" }, body: JSON.stringify({ p_key: KEY, p_airline: airline, p_kind: kind, p_page: page, p_rows: rows }) }); return r.json(); };
  const panel = () => { let b = document.getElementById("eq-cap-panel"); if (!b) { b = document.createElement("div"); b.id = "eq-cap-panel"; b.style.cssText = "position:fixed;top:12px;right:12px;z-index:999999;background:#0A1230;color:#fff;font:14px/1.5 system-ui,sans-serif;padding:14px 18px;border-radius:14px;box-shadow:0 20px 50px rgba(0,0,0,.4);max-width:380px;white-space:pre-line"; document.body.appendChild(b); } return b; };
  const log = t => { const s = get(); if (s) { s.log = (s.log || []).concat(t).slice(-40); set(s); } panel().textContent = (get() ? get().log.join("\n") : t); };
  const currentId = async () => { const d = await fetchDoc("/action/enterprise/schedule"); const t = d.body.textContent, i = t.indexOf("Events overview for "); const n = i >= 0 ? t.slice(i + 20, i + 60).trim() : ""; const hit = AIRLINES.find(a => n.startsWith(a[1])); return hit ? hit[0] : null; };
  async function captureCurrent(name) {
    let r = await send(name, "events", rowsOf(await fetchDoc("/action/enterprise/schedule")), "/action/enterprise/schedule"); log(name + " · events " + (r.rows ?? r.error));
    let url = "/app/finance/accounting/2", all = [], pages = 0; const since = Date.now() - 3 * 864e5;
    while (url && pages < 15) { const doc = await fetchDoc(url); const rows = rowsOf(doc).filter(x => /^\d\d\.\d\d\. \d\d:\d\d/.test(x[0])); all.push(...rows); pages++;
      const last = rows[rows.length - 1]; if (last) { const d = last[0]; if (Date.UTC(new Date().getUTCFullYear(), +d.slice(3, 5) - 1, +d.slice(0, 2), +d.slice(7, 9), +d.slice(10, 12)) < since) break; }
      const next = [...doc.querySelectorAll("a")].find(a => a.textContent.trim() === ">"); url = next ? new URL(next.getAttribute("href"), new URL(url, location.origin)).href : null; }
    r = await send(name, "statement", all, "/app/finance/accounting/2"); log(name + " · statement " + (r.rows ?? r.error) + " lines, " + pages + " pages");
    r = await send(name, "pnl", rowsOf(await fetchDoc("/app/finance/accounting/0")), "/app/finance/accounting/0"); log(name + " · income statement " + (r.rows ?? r.error));
    r = await send(name, "balance", rowsOf(await fetchDoc("/app/finance/accounting/1")), "/app/finance/accounting/1"); log(name + " · balance sheet " + (r.rows ?? r.error));
    r = await send(name, "loads", rowsOf(document), location.pathname); log(name + " · loads " + (r.rows ?? r.error) + " flights");
  }
  const onLoads = () => location.pathname.includes("/app/com/loads");
  // ---- salaries: every position to 10% above the country average, pressing "adjust" for each change
  const SALARY_FACTOR = 1.10;
  const onSalaryPage = () => /Employee overview/i.test(document.body.textContent) && /Country average/i.test(document.body.textContent);
  function findSalaryLink() {
    const links = [...document.querySelectorAll("a[href]")];
    const pick = re => links.find(a => re.test(a.textContent.trim()));
    const a = pick(/^employee overview$/i) || pick(/employee overview/i) || pick(/^employees$/i) || pick(/personnel|staff/i);
    return a ? new URL(a.getAttribute("href"), location.href).href : null;
  }
  function salaryRows() {
    const out = [];
    for (const tr of document.querySelectorAll("table tr")) {
      const input = tr.querySelector("input[type=text], input[type=number], input:not([type])"); if (!input) continue;
      const btn = [...tr.querySelectorAll("button, input[type=submit], input[type=button], a")].find(b => /^\s*adjust\s*$/i.test(b.textContent || b.value || "")); if (!btn) continue;   // not "adjust all"
      const cells = [...tr.children], i = cells.findIndex(td => td.contains(btn));
      const avgCell = cells.slice(i + 1).find(td => /^\s*[\d,.]+\s*AS\$\s*$/.test(td.textContent)); if (!avgCell) continue;   // the country average comes right after the adjust button
      const avg = +avgCell.textContent.replace(/[^\d]/g, ""); if (!avg) continue;
      out.push({ input, btn, avg, target: Math.round(avg * SALARY_FACTOR), cur: +String(input.value).replace(/[^\d]/g, "") });
    }
    return out;
  }
  async function adjustSalaries() {   // one position at a time; if "adjust" reloads the page, the run carries on from the reloaded page
    for (let guard = 0; guard < 40; guard++) {
      const todo = salaryRows().find(r => Math.abs(r.cur - r.target) > 1);
      if (!todo) return true;
      const st = get(); if (st) { st.salaryChanged = (st.salaryChanged || 0) + 1; set(st); }
      todo.input.focus(); todo.input.value = String(todo.target);
      todo.input.dispatchEvent(new Event("input", { bubbles: true })); todo.input.dispatchEvent(new Event("change", { bubbles: true }));
      todo.btn.click();
      await new Promise(r => setTimeout(r, 2500));
    }
    return true;
  }
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
    if (t.i < AIRLINES.length) { t.phase = "switch"; set(t); step(); } else { t.phase = "home"; set(t); location.href = "/app/enterprise/dashboard?select=" + t.start; }
  }
  async function step() {
    const s = get(); if (!s) return;
    const [id, name] = AIRLINES[s.i] || [];
    if (s.phase === "switch") { s.phase = "open"; set(s); location.href = "/app/enterprise/dashboard?select=" + id; return; }
    if (s.phase === "open") { s.phase = "filter"; set(s); location.href = "/app/com/loads"; return; }
    if (s.phase === "filter" && onLoads()) { setFilter(); s.phase = "capture"; set(s); await new Promise(r => setTimeout(r, 1500));
      const upd = [...document.querySelectorAll("a")].find(a => /Update Results/.test(a.textContent)); if (upd) { upd.click(); setTimeout(() => { const t = get(); if (t && t.phase === "capture") step(); }, 4000); } else { log("No Update Results link; capturing as is"); step(); } return; }
    if (s.phase === "capture" && onLoads()) { try { await captureCurrent(name); } catch (e) { log(name + " · problem: " + e.message); }
      const t = get() || s; const url = t.salaryUrl || findSalaryLink(); t.phase = "salary"; t.salaryChanged = 0; t.salaryTried = false;
      if (url) { t.salaryUrl = url; t.salaryTried = true; set(t); location.href = url; } else { set(t); log(name + " · salaries: couldn't find the Employee overview page"); nextAirline(); }
      return; }
    if (s.phase === "salary") {
      if (onSalaryPage()) { await adjustSalaries(); const t = get() || s; log(name + " · salaries: " + (t.salaryChanged ? t.salaryChanged + " adjusted to 10% above the country average" : "already 10% above the country average")); nextAirline(); return; }
      if (!s.salaryTried && s.salaryUrl) { s.salaryTried = true; set(s); location.href = s.salaryUrl; return; }
      log(name + " · salaries: Employee overview page not found"); nextAirline(); return; }
    if (s.phase === "home") { log("Done: all six airlines captured. Back on the airline you started with."); panel().onclick = () => { panel().remove(); clear(); }; clear(); return; }
  }
  function addButton() {
    if (document.getElementById("eq-cap-btn")) return; const b = document.createElement("button"); b.id = "eq-cap-btn"; b.textContent = "Capture all airlines"; b.style.cssText = "position:fixed;bottom:16px;right:16px;z-index:999998;background:#F6B44B;color:#0A1230;border:0;border-radius:999px;padding:10px 16px;font:700 13px system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.35);cursor:pointer";
    b.onclick = async () => { b.disabled = true; const start = (await currentId()) || AIRLINES[0][0];
      set({ i: 0, phase: "switch", start, log: ["equinox. capture, all airlines…"] }); log("Starting"); step(); };
    document.body.appendChild(b);
  }
  addButton(); const s = get(); if (s) { panel().textContent = (s.log || []).join("\n"); setTimeout(step, 800); }
})();
