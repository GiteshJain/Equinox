// ==UserScript==
// @name         equinox. salaries (this airline)
// @namespace    equinox
// @version      1.0
// @description  One button: sets every position of the airline you are on to 10% above the country average, pressing adjust for each. Only that airline; run it when you choose. Separate from the capture.
// @match        https://gander.airlinesim.aero/*
// @grant        none
// ==/UserScript==
(function () {
  // Manual §7 (10 Oct 2026): salaries are adjusted by hand, one airline at a time, never by the capture.
  const SALARY_FACTOR = 1.10;   // 10% above the country average
  const ST = "eq_salary"; const get = () => { try { return JSON.parse(sessionStorage.getItem(ST) || "null"); } catch (e) { return null; } };
  const set = s => sessionStorage.setItem(ST, JSON.stringify(s)); const clear = () => sessionStorage.removeItem(ST);
  const URL_KEY = "eq_salary_url";   // the Employee overview address, remembered once found
  const remembered = () => { try { return localStorage.getItem(URL_KEY); } catch (e) { return null; } };
  const remember = u => { try { localStorage.setItem(URL_KEY, u); } catch (e) {} };

  const panel = () => { let b = document.getElementById("eq-sal-panel"); if (!b) { b = document.createElement("div"); b.id = "eq-sal-panel"; b.style.cssText = "position:fixed;top:12px;left:12px;z-index:999999;background:#0A1230;color:#fff;font:14px/1.5 system-ui,sans-serif;padding:14px 18px;border-radius:14px;box-shadow:0 20px 50px rgba(0,0,0,.4);max-width:380px;white-space:pre-line;cursor:pointer"; b.title = "Click to close"; b.onclick = () => b.remove(); document.body.appendChild(b); } return b; };
  const say = t => { panel().textContent = t; };

  // the airline you are on, as the game names it on the events page
  async function currentAirline() {
    try { const r = await fetch("/action/enterprise/schedule", { credentials: "include" }); const d = new DOMParser().parseFromString(await r.text(), "text/html");
      const t = d.body.textContent, i = t.indexOf("Events overview for "); return i >= 0 ? t.slice(i + 20, i + 70).split(/\s{2,}|\n/)[0].trim() : ""; } catch (e) { return ""; }
  }
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
  async function adjust() {   // one position at a time; if "adjust" reloads the page, the run carries on from the reloaded page
    for (let guard = 0; guard < 40; guard++) {
      const s = get(); if (!s) return;
      const todo = salaryRows().find(r => Math.abs(r.cur - r.target) > 1);
      if (!todo) { say(s.name + " · salaries: " + (s.changed ? s.changed + " adjusted to 10% above the country average" : "already 10% above the country average") + "\nOnly this airline was changed."); clear(); return; }
      s.changed = (s.changed || 0) + 1; set(s);
      say(s.name + " · adjusting " + s.changed + "…");
      todo.input.focus(); todo.input.value = String(todo.target);
      todo.input.dispatchEvent(new Event("input", { bubbles: true })); todo.input.dispatchEvent(new Event("change", { bubbles: true }));
      todo.btn.click();
      await new Promise(r => setTimeout(r, 2500));
    }
    const s = get(); if (s) { say(s.name + " · salaries: stopped after 40 changes; press the button again to carry on"); clear(); }
  }
  async function start(b) {
    b.disabled = true;
    const name = (await currentAirline()) || "This airline";
    if (!confirm("Set every salary at " + name + " to 10% above the country average?\n\nOnly " + name + " is changed.")) { b.disabled = false; return; }
    set({ name, changed: 0 });
    if (onSalaryPage()) { remember(location.href); return adjust(); }
    const url = findSalaryLink() || remembered();
    if (!url) { say(name + " · salaries: open the Employee overview page, then press the button again."); clear(); b.disabled = false; return; }
    say(name + " · opening the Employee overview…"); location.href = url;
  }
  function addButton() {
    if (document.getElementById("eq-sal-btn")) return; const b = document.createElement("button"); b.id = "eq-sal-btn"; b.textContent = "Salaries: this airline";
    b.style.cssText = "position:fixed;bottom:16px;left:16px;z-index:999998;background:#2A8FD8;color:#fff;border:0;border-radius:999px;padding:10px 16px;font:700 13px system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.35);cursor:pointer";
    b.onclick = () => start(b); document.body.appendChild(b);
  }
  addButton();
  if (onSalaryPage()) remember(location.href);
  if (get()) { if (onSalaryPage()) setTimeout(adjust, 800); else { say("Salaries: the Employee overview page didn't open. Open it and press the button again."); clear(); } }
})();
