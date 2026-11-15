// ==UserScript==
// @name         equinox. apply fare plan
// @namespace    equinox
// @version      1.5
// @description  One button, Apply fare plan: makes every fare change on this week's fare plan that the captures haven't seen yet, and sets back every route whose captured fares are off its level, for every airline (the database lists them, one airline at a time since 1.3: capture_fare_actions_by_airline), in the game's Ticket price adjustment: route by route, each direction on its own, baseline default price. One change at a time, 2 seconds apart, while you watch; it stops at the first problem. It changes prices only, and refuses any change outside its own limit (settings fares_script_min_pct and fares_script_max_pct, 55% to 135% of the default price). Since 1.5 it takes new versions from its update address and keeps the capture key in the userscript app's own storage, asked for once. The next capture ticks the changes off on the fare plan, and shows the routes set back at their level. Install it as the capture script, with your capture key in place of the placeholder.
// @updateURL    https://raw.githubusercontent.com/GiteshJain/Equinox/main/capture/fares_apply.user.js
// @downloadURL  https://raw.githubusercontent.com/GiteshJain/Equinox/main/capture/fares_apply.user.js
// @match        https://gander.airlinesim.aero/*
// @grant        GM.getValue
// @grant        GM.setValue
// @grant        GM.deleteValue
// ==/UserScript==
// Spec docs/specs/2026-10-21-fares-userscript.md; manual §5. Since 1.1 (spec docs/specs/2026-10-21-frequencies-and-fares.md
// §3) the list also holds set-back changes (fix: a route whose captured fares don't match its level, with no fare plan
// row): each is made exactly as any other change, and the panel says "set back" for it. The logic (reading the form,
// building a change's address, checking the game's answer) is plain functions over the pages' HTML, without the page,
// so tests/fares_userscript_test.mjs runs this same file in Node: there, with no page, it only hands those functions over
// (as eqFares) and does nothing else.
// Since 1.5 (15 Nov, to-do 247 with to-do 218 step 3, spec docs/specs/2026-11-15-self-updating-scripts.md): it updates from
// its @updateURL, keeps the key in the userscript app's own storage (asked for once in prompt(), the one browser dialog),
// stops before anything when a newer version is out, and refuses, before making anything, any change whose level is
// under settings.fares_script_min_pct (55) or over fares_script_max_pct (135) % of the default price, or disagrees with
// its own level; capture_fare_actions_by_airline()'s list gives the two numbers, and without them nothing is made.
(function (root) {
  "use strict";

  // ---------------------------------------------------------------- the key and the version (shared block)
  // The same lines in capture_all.user.js and fares_apply.user.js (tests/userscript_key_test.mjs checks they match; since
  // capture 1.17 and fares 1.5, 15 Nov, to-do 247, spec docs/specs/2026-11-15-self-updating-scripts.md §3 and §4).
  // The key: the KEY line below keeps the placeholder in the repository. The unattended run (equinox-backups) fills it
  // in its own copy, and then that key is used and the app's storage is never touched. Unfilled, as on Gitesh's Mac, the
  // key is read from the userscript app's own storage (GM.getValue, Tampermonkey's and the Userscripts app's), which the
  // game's page can't reach; the first press asks for it once in the browser's own prompt() box (Gitesh, 15 Nov, choice 3
  // B) and keeps it there (GM.setValue). A key the database refuses ("bad key") is forgotten and asked for once more.
  // It is never put in the page, sessionStorage, localStorage, the panel or the console.
  // The guard: on a device, each press first reads the newest version from the update address; a script behind it stops
  // before doing anything and says to update; an address that doesn't answer is a line and the press goes on. A run whose
  // state was started by another version stops too ("updated during the run").
  const KEY_NAME = "capture_key", GUARD_TIMEOUT_MS = 5000;
  const unfilled = k => typeof k !== "string" || !k.trim() || /^__[A-Z_]+__$/.test(k.trim());
  const versionOf = text => { const m = String(text == null ? "" : text).match(/^\/\/\s*@version\s+(\S+)\s*$/m); return m ? m[1] : null; };
  // whether version b is newer than a, number by number (1.10 is newer than 1.9), as the userscript apps compare them
  function isNewer(a, b) {
    const x = String(a).split("."), y = String(b).split(".");
    for (let i = 0; i < Math.max(x.length, y.length); i++) {
      const p = parseInt(x[i] || "0", 10) || 0, q = parseInt(y[i] || "0", 10) || 0;
      if (p !== q) return q > p;
    }
    return false;
  }
  const behindWords = (name, own, latest) => `equinox. ${name}: this is version ${own}, and ${latest} is out, so nothing was done. `
    + "Update it (Tampermonkey's menu → Check for userscript updates; in the Userscripts app, its popup → Update), reload the page and press again.";
  const midRunWords = (name, was, now) => `equinox. ${name}: the script was updated during the run (started on ${was || "an older version"}, now ${now}), so it stopped here. `
    + "What's done stays done: press again.";
  const askWords = name => `equinox. ${name}: paste the capture key once. It is kept in this browser's userscript storage, not in the script or the page.`;
  const againWords = name => `equinox. ${name}: the database didn't accept the key kept in this browser. Paste the capture key again.`;
  const isBadKey = r => !!r && r.ok === false && r.error === "bad key";
  // the newest version at the update address: ok, behind (with the newest) or unknown (with why); fetchText(url) gives
  // the file's text or throws
  async function versionCheck(fetchText, own, url) {
    let text, timer;
    try { text = await Promise.race([fetchText(url), new Promise((_, no) => { timer = setTimeout(() => no(new Error("no answer in " + GUARD_TIMEOUT_MS / 1000 + " s")), GUARD_TIMEOUT_MS); })]); }
    catch (e) { return { state: "unknown", why: e && e.message ? e.message : String(e) }; }
    finally { clearTimeout(timer); }
    const latest = versionOf(text);
    if (!latest) return { state: "unknown", why: "no @version at the update address" };
    return isNewer(own, latest) ? { state: "behind", latest } : { state: "ok", latest };
  }
  // the key: the filled-in placeholder (from text), the one kept in storage (stored), or asked for and kept (asked);
  // store is the app's GM object or null, ask(words) the prompt() box (null when nothing was typed)
  async function keyOf(baked, store, ask, words) {
    if (!unfilled(baked)) return { key: baked, from: "text" };
    if (!store) return { error: "the userscript app gives this script no storage (GM.getValue)" };
    const kept = await store.getValue(KEY_NAME, null);
    if (typeof kept === "string" && kept.trim()) return { key: kept.trim(), from: "stored" };
    if (!ask) return { error: "no key kept in this browser" };
    const typed = ask(words);
    if (typeof typed !== "string" || !typed.trim()) return { error: "no key typed" };
    await store.setValue(KEY_NAME, typed.trim());
    return { key: typed.trim(), from: "asked" };
  }
  // before a press does anything: the guard (only on a device), then the key. io: { name, own, url, baked, store, ask,
  // fetchText }. Answers { key, from, lines } or { stop: the words to show }.
  async function prepare(io) {
    const lines = [];
    if (unfilled(io.baked)) {
      const v = await versionCheck(io.fetchText, io.own, io.url);
      if (v.state === "behind") return { stop: behindWords(io.name, io.own, v.latest) };
      if (v.state === "unknown") lines.push(`couldn't check for a newer version (${v.why}); going on with ${io.own}`);
    }
    const k = await keyOf(io.baked, io.store, io.ask, askWords(io.name));
    if (k.error) return { stop: `equinox. ${io.name}: no capture key (${k.error}). Press again and paste the key when asked.` };
    return { key: k.key, from: k.from, lines };
  }
  // the first call with the key, call(key) → the database's answer; a "bad key" answer to a kept or typed key forgets it
  // and asks once more. Answers { answer, key } (key null when nothing more was typed).
  async function withKey(io, prep, call) {
    let answer = await call(prep.key);
    if (!isBadKey(answer) || prep.from === "text") return { answer, key: prep.key };
    if (io.store) await io.store.deleteValue(KEY_NAME);
    const k = await keyOf(io.baked, io.store, io.ask, againWords(io.name));
    if (k.error) return { answer, key: null };
    answer = await call(k.key);
    if (isBadKey(answer) && io.store) await io.store.deleteValue(KEY_NAME);
    return { answer, key: k.key };
  }
  // a run carried on after a page load: stopped when another version started it; else the key, without asking
  async function resumeKey(io, state) {
    if (unfilled(io.baked) && state && state.version !== io.own) return { stop: midRunWords(io.name, state.version, io.own) };
    const k = await keyOf(io.baked, io.store, null);
    return k.error ? { stop: `equinox. ${io.name}: the run can't carry on (${k.error}).` } : { key: k.key, from: k.from };
  }
  const keyLib = { KEY_NAME, GUARD_TIMEOUT_MS, unfilled, versionOf, isNewer, behindWords, midRunWords, askWords, againWords, isBadKey, versionCheck, keyOf, prepare, withKey, resumeKey };
  // ---------------------------------------------------------------- end of the shared block

  const VERSION = "1.5";                              // the @version above
  const FORM = "/action/enterprise/flightsPrices";   // the game's Ticket price adjustment, for the airline active in the session
  const PAUSE_MS = 2000;                              // between one change and the next
  const CLASSES = ["economy", "business"];            // the classes the fare plan changes, in the form's order
  const LETTER = { economy: "Y", business: "C" };     // as the answer's Service Class shows them

  // ---------------------------------------------------------------- the logic, without the page
  const decode = s => s.replace(/&nbsp;/g, " ").replace(/&#(\d+);/g, (m, n) => String.fromCharCode(+n))
    .replace(/&#x([0-9a-f]+);/gi, (m, n) => String.fromCharCode(parseInt(n, 16)))
    .replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  const textOf = html => decode(String(html).replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();
  const attr = (tag, name) => { const m = tag.match(new RegExp("\\b" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", "i")); return m ? decode(m[1] ?? m[2] ?? m[3]) : null; };

  // a <select name="..."> of the page: its options as { value, text }, or null when the page has none
  function selectOptions(html, name) {
    const m = String(html).match(new RegExp("<select\\b[^>]*\\bname\\s*=\\s*[\"']?" + name + "\\b[^>]*>([\\s\\S]*?)</select>", "i"));
    if (!m) return null;
    return [...m[1].matchAll(/<option\b([^>]*)>([\s\S]*?)(?=<option\b|<\/option>|$)/gi)].map(o => ({ value: attr("<x " + o[1] + ">", "value") ?? textOf(o[2]), text: textOf(o[2]) }));
  }

  // the airports of the fares form: each IATA code to its game id (a:<id>) in the From list and in the To list, read from
  // the page's own options, whose text ends with "(IATA)"; a country (c:<id>) is never used. Null when the page has no
  // fares form (the session lost, or another page).
  function airportsOf(html) {
    const lists = { from: selectOptions(html, "fromCode"), to: selectOptions(html, "toCode") };
    if (!lists.from || !lists.to) return null;
    const out = { from: {}, to: {}, names: {}, twice: [] };
    for (const side of ["from", "to"]) {
      for (const o of lists[side]) {
        const m = o.text.match(/\(([A-Z0-9]{3})\)\s*$/);
        if (!/^a:\d+$/.test(o.value) || !m) continue;
        const code = m[1];
        if (out[side][code] && out[side][code] !== o.value) { if (!out.twice.includes(code)) out.twice.push(code); continue; }
        out[side][code] = o.value;
        out.names[code] = o.text.replace(/^[-\s]+/, "").replace(/\s*\([A-Z0-9]{3}\)\s*$/, "");
      }
    }
    return out;
  }

  // a change from the database, checked before anything is sent: null when it can be made, else why not
  function actionProblem(a, limits) {
    if (!a || typeof a !== "object") return "no change";
    if (!/^\d+$/.test(String(a.game_id ?? ""))) return "no airline game ID";
    for (const end of ["from", "to"]) if (!/^[A-Z0-9]{3}$/.test(String(a[end] ?? ""))) return "no airport code for " + end;
    if (a.from === a.to) return "the same airport at both ends";
    if (a.sign !== "+" && a.sign !== "-") return "no + or − sign";
    const pct = Number(a.pct);
    if (a.pct === null || a.pct === "" || !Number.isInteger(pct) || pct < 0 || pct > 100) return "the game takes a whole percent from 0 to 100, not " + a.pct;
    if (!Array.isArray(a.classes) || !a.classes.length || a.classes.some(c => !CLASSES.includes(c)) || new Set(a.classes).size !== a.classes.length)
      return "classes must be economy and/or business, not " + JSON.stringify(a.classes);
    // the script's own limit (since 1.5, 15 Nov, manual §5): the level the change sets, baseline default price, is 100 − pct
    // for − and 100 + pct for +; it must agree with the change's own level, and stay inside the settings' limits
    const level = a.sign === "-" ? 100 - pct : 100 + pct;
    if (a.level !== undefined && a.level !== null && Number(a.level) !== level)
      return `its level is ${a.level}% but the change says ${a.sign === "-" ? "−" : "+"}${pct}% (${level}% of the default price)`;
    if (limits) {
      if (level < limits.min_pct) return `its level, ${level}% of the default price, is under the fares script's limit of ${limits.min_pct}% (settings.fares_script_min_pct)`;
      if (level > limits.max_pct) return `its level, ${level}% of the default price, is over the fares script's limit of ${limits.max_pct}% (settings.fares_script_max_pct)`;
    }
    return null;
  }
  // the limits the database gives (capture_fare_actions_by_airline()'s list, since 15 Nov), or null when they aren't two numbers
  const limitsOf = l => l && typeof l === "object" && Number.isFinite(Number(l.min_pct)) && Number.isFinite(Number(l.max_pct))
    && l.min_pct !== null && l.max_pct !== null && l.min_pct !== "" && l.max_pct !== "" && Number(l.min_pct) < Number(l.max_pct)
    ? { min_pct: Number(l.min_pct), max_pct: Number(l.max_pct) } : null;

  // the form's ids for a change's two airports, or why it can't be made on this form
  function idsFor(airports, a) {
    for (const code of [a.from, a.to]) if (airports.twice.includes(code)) return { problem: code + " is in the fares form twice, with different ids" };
    if (!airports.from[a.from]) return { problem: a.from + " isn't in the fares form's From list" };
    if (!airports.to[a.to]) return { problem: a.to + " isn't in the fares form's To list" };
    return { from: airports.from[a.from], to: airports.to[a.to] };
  }

  // one change is one GET of the form, as the form itself sends it: adjust, the two airports, any service profile, + or −,
  // the percent, baseline default price, and the classes ticked
  function changeUrl(a, ids) {
    const q = [["adjust", "true"], ["fromCode", ids.from], ["toCode", ids.to], ["serviceProfileId", "0"], ["factor", a.sign === "-" ? "-1" : "1"],
               ["percent", String(Number(a.pct))], ["base", "standard"]];
    for (const c of CLASSES) if (a.classes.includes(c)) q.push([c, "true"]);
    return FORM + "?" + q.map(([k, v]) => k + "=" + encodeURIComponent(v)).join("&");
  }

  // a table's rows as cell texts, tolerant of closing tags left out
  const tableRows = html => html.split(/<tr\b/i).slice(1).map(tr => tr.split(/<t[hd]\b/i).slice(1).map(td => textOf("<x" + td.replace(/<\/t[hd]>[\s\S]*$/i, ""))));

  // the answer's "Changed Airport Pairs": each row's From, To, Service Class, Old Price and New Price, or null when the
  // page has no such table
  function changedPairs(html) {
    html = String(html);
    const at = html.search(/Changed\s+Airport\s+Pairs/i);
    const tables = [...html.matchAll(/<table\b[\s\S]*?<\/table>/gi)].map(m => ({ at: m.index, html: m[0] }));
    for (const t of (at >= 0 ? tables.filter(x => x.at > at) : []).concat(tables)) {
      const rows = tableRows(t.html), hi = rows.findIndex(r => r.some(c => /service\s*class/i.test(c)));
      if (hi < 0) continue;
      const h = rows[hi].map(c => c.toLowerCase()), col = rx => h.findIndex(c => rx.test(c));
      const iF = col(/^from\b/), iT = col(/^to\b/), iC = col(/class/), iO = col(/^old/), iN = col(/^new/);
      if (iF < 0 || iT < 0 || iC < 0) continue;
      return rows.slice(hi + 1).filter(r => r.length > Math.max(iF, iT, iC))
        .map(r => ({ from: r[iF], to: r[iT], cls: r[iC], old: iO >= 0 ? r[iO] || "" : "", new: iN >= 0 ? r[iN] || "" : "" }));
    }
    return null;
  }

  const classOf = cell => ({ y: "economy", economy: "economy", c: "business", business: "business", f: "first", first: "first" })[String(cell).trim().toLowerCase()] || null;
  // an answer's From or To cell is the airport: its code ("LHR"), its name with the code ("London Heathrow (LHR)"; the
  // game's real answer puts the code in its own link inside the brackets, which reads "New York ( JFK )"), or the name
  // the fares form gives it
  function isAirport(cell, code, names) {
    const c = String(cell).trim(), m = c.match(/\(\s*([A-Z0-9]{3})\s*\)\s*$/);
    if (c === code || (m && m[1] === code)) return true;
    const name = names && names[code];
    return !!name && c.toLowerCase() === name.toLowerCase();
  }

  // the game's answer to one change: ok with the rows found, one for each class it named on that From and To; else why not
  function checkAnswer(html, a, names) {
    const rows = changedPairs(html);
    if (!rows) return airportsOf(html)
      ? { ok: false, why: "the game's answer listed no Changed Airport Pairs" }
      : { ok: false, why: "the game's answer wasn't the fares page: the session may have been lost", session: true };
    const found = [];
    for (const c of a.classes) {
      const r = rows.find(x => isAirport(x.from, a.from, names) && isAirport(x.to, a.to, names) && classOf(x.cls) === c);
      if (!r) return { ok: false, why: `the game's answer has no ${LETTER[c]} (${c}) row for From ${a.from} to ${a.to}` };
      found.push({ cls: LETTER[c], old: r.old, new: r.new });
    }
    return { ok: true, rows: found };
  }

  // capture_fare_actions()'s answer as the run needs it: each airline (in the database's order) with its changes and how
  // many of them set a route back (fix), the totals, and any change that can't be made as it stands
  function planOf(doc) {
    if (!doc || doc.ok !== true || !Array.isArray(doc.airlines) || !Array.isArray(doc.actions))
      return { error: (doc && (doc.error || doc.message || doc.hint)) || "no answer" };
    // since 1.5: no plan without the fares script's own limit
    const limits = limitsOf(doc.limits);
    if (!limits) return { error: "the database didn't give the fares script's limits (settings.fares_script_min_pct and fares_script_max_pct)" };
    const airlines = doc.airlines.map(al => ({ game_id: String(al.game_id), name: al.name || al.game_name || String(al.game_id),
                                              actions: doc.actions.filter(x => String(x.game_id) === String(al.game_id)) }));
    for (const al of airlines) al.fixes = al.actions.filter(a => a.fix === true).length;
    const problems = [];
    for (const al of airlines) for (const a of al.actions) { const p = actionProblem(a, limits); if (p) problems.push({ airline: al.name, action: a, why: p }); }
    for (const a of doc.actions) if (!airlines.some(al => al.game_id === String(a.game_id))) problems.push({ airline: String(a.game_id), action: a, why: "an airline the list doesn't name" });
    return { week_of: doc.week_of || null, limits, airlines, total: airlines.reduce((n, al) => n + al.actions.length, 0),
             fixes: airlines.reduce((n, al) => n + al.fixes, 0), problems };
  }

  // the fare plan read one airline at a time (since 1.3, 2 Nov): every airline in one call took about 70 s, past its 30 s
  // limit and the API's 60 s. First the list (no fare ladder worked out), then each airline in a call of its own (10 to
  // 15 s each on 2 Nov), put together as capture_fare_actions() answered: one document for planOf(). call(fn, body) is
  // the database call; progress(name, i, n) is told before each airline. The first answer that isn't ok is the answer,
  // with the airline it was for.
  async function readPlan(call, key, progress) {
    const FN = "capture_fare_actions_by_airline";
    const list = await call(FN, { p_key: key, p_game_id: null });
    if (!list || list.ok !== true || !Array.isArray(list.airlines)) return list;
    const doc = { ok: true, world: list.world, week_of: null, as_of: list.as_of, limits: list.limits === undefined ? null : list.limits, airlines: [], actions: [] };
    for (let i = 0; i < list.airlines.length; i++) {
      const al = list.airlines[i], name = al.name || al.game_name || String(al.game_id);
      if (progress) progress(name, i + 1, list.airlines.length);
      const one = await call(FN, { p_key: key, p_game_id: Number(al.game_id) });
      if (!one || one.ok !== true || !Array.isArray(one.airlines) || !Array.isArray(one.actions))
        return { ok: false, error: `${name}: ` + ((one && (one.error || one.message || one.hint)) || "no answer") };
      doc.week_of = doc.week_of || one.week_of || null;
      doc.airlines.push(...one.airlines); doc.actions.push(...one.actions);
    }
    return doc;
  }

  // a change in words; a set-back change (fix) says so first
  const changeWords = a => (a.fix === true ? "set back: " : "")
    + (a.text || `From ${a.from} to ${a.to}: ${a.sign === "-" ? "−" : "+"}${a.pct}% of the default price, ${a.classes.join(" and ")}`);
  // an airline's count for the panel: "12 changes (2 set back)"
  const countWords = al => plural(al.actions.length, "change", "changes") + (al.fixes ? ` (${al.fixes} set back)` : "");
  const progressWords = (name, done, total) => `${name}: ${done} of ${total}`;
  const plural = (n, one, many) => n + " " + (n === 1 ? one : many);

  const lib = { VERSION, FORM, PAUSE_MS, selectOptions, airportsOf, actionProblem, limitsOf, idsFor, changeUrl, changedPairs, checkAnswer, planOf, readPlan, changeWords, countWords, progressWords };
  Object.assign(lib, keyLib);
  if (typeof document === "undefined" || !root.location || !root.sessionStorage) { root.eqFares = lib; return; }

  // ---------------------------------------------------------------- in the game
  const KEY = "__CAPTURE_KEY__", ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZWN3c3llZHZ3Y3hnZHptaG9xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMTg5MzcsImV4cCI6MjEwNTc5NDkzN30.tC56dOgmPeYB3m58aDy4ADnnaZ3613P6MFp2pVXUj_Y", RPC = "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/";
  // the key (since 1.5): the filled-in placeholder, else the one kept in the app's storage (prepare, withKey)
  const UPDATE_URL = "https://raw.githubusercontent.com/GiteshJain/Equinox/main/capture/fares_apply.user.js";
  const store = typeof GM !== "undefined" && GM && typeof GM.getValue === "function" ? GM : null;
  const io = { name: "fares", own: VERSION, url: UPDATE_URL, baked: KEY, store, ask: words => root.prompt(words),
               fetchText: async u => { const r = await fetch(u, { cache: "no-store" }); if (!r.ok) throw new Error("HTTP " + r.status); return r.text(); } };
  const ST = "eq_fares_apply", STALE_MS = 3 * 60 * 1000;   // a run untouched for 3 minutes isn't picked up again by itself
  const get = () => { try { return JSON.parse(sessionStorage.getItem(ST) || "null"); } catch (e) { return null; } };
  const set = s => { s.at = Date.now(); sessionStorage.setItem(ST, JSON.stringify(s)); };
  const clear = () => sessionStorage.removeItem(ST);
  const update = fn => { const s = get(); if (s) { fn(s); set(s); } return s; };
  const rpc = async (fn, body) => { const r = await fetch(RPC + fn, { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" }, body: JSON.stringify(body) }); return r.json(); };
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const pathOf = u => new URL(u, location.href).pathname.replace(/;.*$/, "");   // without a ;jsessionid
  let stopping = false;

  // which airline the game has open: its selected-enterprise cookie, where the browser lets the page read it (else null)
  function openAirline() {
    const fs = root.frontendSettings, name = (fs && fs.selectedEnterpriseCookieName) || "airlinesim-selectedEnterpriseId-" + location.hostname.split(".")[0];
    const c = document.cookie.split(/;\s*/).find(x => x.startsWith(name + "="));
    const v = c ? decodeURIComponent(c.slice(name.length + 1)) : null;
    return v && /^\d+$/.test(v) ? v : null;
  }

  // the panel, like the capture's, with its buttons in the page (no browser dialogs but the key's prompt, once)
  function panel() {
    let b = document.getElementById("eq-fares-panel");
    if (!b) {
      b = document.createElement("div"); b.id = "eq-fares-panel";
      b.style.cssText = "position:fixed;top:12px;right:12px;z-index:999999;background:#0A1230;color:#fff;font:14px/1.5 system-ui,sans-serif;padding:14px 18px;border-radius:14px;box-shadow:0 20px 50px rgba(0,0,0,.4);max-width:380px";
      const t = document.createElement("div"); t.className = "eq-fares-text"; t.style.whiteSpace = "pre-line";
      const k = document.createElement("div"); k.className = "eq-fares-buttons"; k.style.cssText = "margin-top:10px;display:flex;gap:8px;flex-wrap:wrap";
      b.append(t, k); document.body.appendChild(b);
    }
    return b;
  }
  function show(text, buttons) {
    const b = panel(); b.querySelector(".eq-fares-text").textContent = text;
    const k = b.querySelector(".eq-fares-buttons"); k.textContent = "";
    for (const [label, fn, main] of buttons || []) {
      const x = document.createElement("button"); x.textContent = label;
      x.style.cssText = "border:0;border-radius:999px;padding:7px 14px;font:700 13px system-ui,sans-serif;cursor:pointer;" + (main ? "background:#F6B44B;color:#0A1230" : "background:#26305a;color:#fff");
      x.onclick = fn; k.appendChild(x);
    }
  }
  const close = () => { const b = document.getElementById("eq-fares-panel"); if (b) b.remove(); };
  const stopButton = ["Stop", () => { stopping = true; update(t => { t.stop = true; }); show("Stopping after this change…"); }];
  const lines = s => (s.log || []).join("\n");
  const note = (s, line) => { s.log = (s.log || []).concat(line).slice(-12); };

  // the end: each airline's changes made, and why it stopped if it did; nothing is kept for a later page
  function finish(s, why) {
    clear();
    const made = s.airlines.filter(al => al.actions.length).map(al => `${al.name}: ${plural(s.made[al.game_id] || 0, "change", "changes")} made of ${al.actions.length}`);
    show((why ? "Stopped. " + why + "\n\n" : "Done: every planned fare change is made.\n\n") + made.join("\n")
      + "\n\nThe next capture ticks them off on the fare plan" + (s.airlines.some(al => al.fixes) ? ", and shows the routes set back at their level." : ".")
      + (why ? " What's done stays done: run Apply fare plan again to make the rest (it reads only what the captures haven't seen yet, and a change made twice does no harm)." : ""),
      [["Close", close, true]]);
  }
  const stopAt = (s, al, a, why) => finish(s, `${progressWords(al.name, s.j, al.actions.length)}, at change ${s.j + 1}: ${changeWords(a)}.\nWhy: ${why}.`);

  // the next airline with changes after the current one, or -1
  const nextAirline = (s, from) => { for (let i = from; i < s.airlines.length; i++) if (s.airlines[i].actions.length) return i; return -1; };

  async function step() {
    const s = get(); if (!s) return;
    if (s.stop || stopping) return finish(s, "You pressed Stop.");
    const al = s.airlines[s.i];
    if (s.phase === "switch") { s.phase = "open"; note(s, "Switching to " + al.name + "…"); set(s); location.href = "/app/enterprise/dashboard?select=" + encodeURIComponent(al.game_id); return; }
    if (s.phase === "open") { s.phase = "form"; note(s, al.name + ": opening the fares page…"); set(s); location.href = FORM; return; }
    if (s.phase === "form") {
      if (pathOf(location.href) !== FORM) return finish(s, `${al.name}: the fares page didn't open (the game showed ${location.pathname}): the session may have been lost.`);
      const open = openAirline();
      if (open && open !== al.game_id) return finish(s, `${al.name}: the game has airline ${open} open, not ${al.name} (${al.game_id}): the switch didn't take.`);
      const airports = airportsOf(document.documentElement.outerHTML);
      if (!airports) return finish(s, `${al.name}: the fares form isn't on the page: the session may have been lost.`);
      for (let j = 0; j < al.actions.length; j++) {
        const ids = idsFor(airports, al.actions[j]);
        if (ids.problem) return finish(s, `${al.name}, change ${j + 1} of ${al.actions.length}: ${changeWords(al.actions[j])}.\nWhy: ${ids.problem}. Nothing was changed for ${al.name}.`);
        al.actions[j].ids = ids;
      }
      s.names = airports.names; s.phase = "change"; s.j = 0; note(s, progressWords(al.name, 0, al.actions.length)); set(s);
      return run();
    }
    if (s.phase === "change") return run();
  }

  // the changes of the open airline, one GET each, 2 seconds apart, each checked against the answer
  async function run() {
    let s = get(); if (!s) return;
    const al = s.airlines[s.i];
    show(lines(s), [stopButton]);
    while (s.j < al.actions.length) {
      if (s.stop || stopping) return finish(s, `You pressed Stop (${progressWords(al.name, s.j, al.actions.length)}).`);
      const a = al.actions[s.j], open = openAirline();
      if (open && open !== al.game_id) return stopAt(s, al, a, `the game has airline ${open} open, not ${al.name} (${al.game_id})`);
      let r, html;
      try { r = await fetch(changeUrl(a, a.ids), { credentials: "include" }); html = await r.text(); }
      catch (e) { return stopAt(s, al, a, "the game didn't answer (" + e.message + "): the session may have been lost"); }
      if (!r.ok) return stopAt(s, al, a, "the game answered HTTP " + r.status);
      if (r.redirected && pathOf(r.url) !== FORM) return stopAt(s, al, a, "the game sent it to " + pathOf(r.url) + ": the session may have been lost");
      const c = checkAnswer(html, a, s.names);
      if (!c.ok) return stopAt(s, al, a, c.why);
      s = update(t => { t.j += 1; t.made[al.game_id] = (t.made[al.game_id] || 0) + 1;
        t.log = (t.log || []).filter(x => !x.startsWith(al.name + ": ")); note(t, progressWords(al.name, t.j, al.actions.length) + " · " + changeWords(a) + " · " + c.rows.map(x => `${x.cls} ${x.old} → ${x.new}`).join(", ")); });
      if (!s) return;
      if (s.stop || stopping) show(lines(s) + "\nStopping…"); else show(lines(s), [stopButton]);
      if (s.j < al.actions.length || nextAirline(s, s.i + 1) >= 0) { await sleep(PAUSE_MS); s = get(); if (!s) return; }
    }
    const i = nextAirline(s, s.i + 1);
    if (i < 0) return finish(s, null);
    s.i = i; s.j = 0; s.phase = "switch"; s.names = null; set(s);
    return step();
  }

  // the button: read the list, show each airline's count, and ask once in the panel before anything is changed
  async function begin(btn) {
    const s = get();
    if (s) { show(lines(s), [stopButton]); return; }
    btn.disabled = true;
    // since 1.5: first the guard (an out-of-date script stops here) and the key (asked for once, then kept in the app's storage)
    let prep;
    try { prep = await prepare(io); } catch (e) { prep = { stop: "equinox. fares: couldn't read the key or the version (" + e.message + ")." }; }
    if (prep.stop) { btn.disabled = false; return show(prep.stop, [["Close", close, true]]); }
    show("equinox. fares: reading this week's fare plan…");
    let plan;
    try {
      const got = await withKey(io, prep, k => readPlan(rpc, k, (name, i, n) => show(`equinox. fares: reading this week's fare plan… ${name} (${i} of ${n})`)));
      plan = planOf(got.answer);
    } catch (e) { plan = { error: e.message }; }
    btn.disabled = false;
    if (plan.error) return show("equinox. fares: couldn't read the fare plan (" + plan.error + "). Check the capture key.", [["Close", close, true]]);
    if (plan.problems.length) {
      const p = plan.problems[0];
      return show(`equinox. fares: a change on the fare plan can't be made as it stands, so nothing was changed.\n${p.airline}: ${p.action && p.action.from ? changeWords(p.action) : "a change"}.\nWhy: ${p.why}.`, [["Close", close, true]]);
    }
    if (!plan.total) return show("equinox. fares: nothing to change. The fare plan has no changes this week that the captures haven't seen yet, and no route is off its level. Put the week's moves on the fare plan in Performance first.", [["Close", close, true]]);
    const minutes = Math.max(1, Math.round(plan.total * (PAUSE_MS + 1000) / 60000));
    show(`Apply fare plan${plan.week_of ? ", week of " + plan.week_of : ""}\n\n` + plan.airlines.map(al => `${al.name}: ${countWords(al)}`).join("\n")
      + `\n\n${plural(plan.total, "change", "changes")} in all${plan.fixes ? `, ${plan.fixes} of them setting a route back to its level` : ""}, one every 2 seconds: about ${plural(minutes, "minute", "minutes")}. Leave this tab open and watch; Stop is here throughout. It changes prices only.`,
      [["Go ahead", () => {
        const first = plan.airlines.findIndex(al => al.actions.length);
        const t = { phase: "switch", version: VERSION, i: first, j: 0, airlines: plan.airlines, made: {}, names: null, stop: false, log: [] };
        note(t, "Applying the fare plan…"); set(t); show(lines(t), [stopButton]); step();
      }, true], ["Cancel", close]]);
  }

  function addButton() {
    if (document.getElementById("eq-fares-btn")) return;
    const b = document.createElement("button"); b.id = "eq-fares-btn"; b.textContent = "Apply fare plan";
    b.style.cssText = "position:fixed;bottom:64px;left:16px;z-index:999998;background:#F6B44B;color:#0A1230;border:0;border-radius:999px;padding:10px 16px;font:700 13px system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.35);cursor:pointer";
    b.onclick = () => begin(b);
    document.body.appendChild(b);
  }

  addButton();
  const s = get();
  if (s) {
    // a run carries on across the page loads it makes (switching airline, opening the fares page); one left for minutes
    // (the tab closed, the session lost and signed in again) isn't picked up by itself
    if (Date.now() - (s.at || 0) > STALE_MS) finish(s, "The run was interrupted (nothing happened for over 3 minutes)" + (s.airlines[s.i] ? `, at ${progressWords(s.airlines[s.i].name, s.j, s.airlines[s.i].actions.length)}` : "") + ".");
    else if (unfilled(KEY) && s.version !== VERSION) finish(s, midRunWords("fares", s.version, VERSION).replace(/^equinox\. fares: /, ""));   // since 1.5
    else { show(lines(s), [stopButton]); setTimeout(step, 800); }
  }
})(typeof window !== "undefined" ? window : globalThis);
