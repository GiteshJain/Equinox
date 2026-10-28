// ==UserScript==
// @name         equinox. aircraft evaluation
// @namespace    equinox
// @version      1.0
// @description  One button on the game's aircraft evaluation tool, Aircraft evaluation: runs the tool over every route on the run list the database keeps (capture_eval_runs) that has no result yet, one route after another, and saves what the tool shows for each aircraft type (capture_eval_result). It only reads the tool: it sends nothing but the tool's own three forms (the route, add aircraft and settings), never opens another page and changes nothing in the game. 2 seconds between runs, while you watch; it stops at the first problem. Install it as the capture script, with your capture key in place of the placeholder.
// @match        https://gander.airlinesim.aero/app/aircraft/evaluation*
// @grant        none
// ==/UserScript==
// Spec docs/specs/2026-10-27-aircraft-evaluation-script.md (the Building chat's design). The tool is a stateful page: its
// address carries a page version (?134) and each form's action is tied to it, so every POST uses the actions of the
// latest page fetched. The add list's values are positions in the list and shift as types are added, so types are
// matched by their text; the settings by their option text too. The logic (reading the tool's page, building each
// form's body, reading the table) is plain functions over the page's HTML, without the page, so
// tests/aircraft_eval_userscript_test.mjs runs this same file in Node: there, with no page, it only hands those
// functions over (as eqEval) and does nothing else.
(function (root) {
  "use strict";
  const TOOL = "/app/aircraft/evaluation";   // the tool's page; every form posts back to it
  const PAUSE_MS = 2000;                     // between one run and the next
  const POST_PAUSE_MS = 500;                 // between the POSTs inside a run
  const RUN_MS = 4250;                       // a run's time with its pause, for the estimate
  const SEATS = ["Standard", "Leisure", "Leisure Plus", "Comfort"];
  // the table's columns after the type's, as the tool heads them, and the field each becomes
  const COLUMNS = ["Flights per week", "Available seats", "Fuel", "Aircraft Handling", "ATC", "Landing Fees", "Maintenance",
                   "Capital cost", "Crew", "Fixed costs total", "per seat", "50%", "60%", "70%", "80%", "90%", "100%"];
  const FIGURES = ["flights_week", "seats", "fuel", "handling", "atc", "landing", "maintenance", "capital", "crew", "fixed_total", "per_seat"];
  const LOADS = [50, 60, 70, 80, 90, 100];
  // the settings every run uses besides its seat: age 0, Economy, price factor 100%, matched by the option's text
  const WANT = { age: t => /^0(\D|$)/.test(t), serviceClass: t => t === "Economy", priceFactor: t => t === "100%" };
  const SETTING_NAMES = { age: "age", serviceClass: "class", seat: "seat", priceFactor: "price_factor" };

  // ---------------------------------------------------------------- the logic, without the page
  const decode = s => s.replace(/&nbsp;/g, " ").replace(/&#(\d+);/g, (m, n) => String.fromCharCode(+n))
    .replace(/&#x([0-9a-f]+);/gi, (m, n) => String.fromCharCode(parseInt(n, 16)))
    .replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  const textOf = html => decode(String(html).replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").replace(/\(\s+/g, "(").replace(/\s+\)/g, ")").trim();
  const attr = (tag, name) => { const m = tag.match(new RegExp("\\b" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", "i")); return m ? decode(m[1] ?? m[2] ?? m[3]) : null; };
  const same = (a, b) => String(a).replace(/\s+/g, " ").trim() === String(b).replace(/\s+/g, " ").trim();

  // a select's options as { value, text, selected }; the one shown is the one marked selected, else the first
  function optionsOf(selectHtml) {
    const opts = [...String(selectHtml).matchAll(/<option\b([^>]*)>([\s\S]*?)(?=<option\b|<\/option>|<\/select>|$)/gi)]
      .map(o => ({ value: attr("<x " + o[1] + ">", "value") ?? textOf(o[2]), text: textOf(o[2]), selected: /\bselected\b/i.test(o[1]) }));
    return opts;
  }
  const shown = opts => opts.find(o => o.selected) || opts[0] || null;

  // a form's own fields: its inputs (name, type, value) and its selects (name, multiple, options), in the page's order
  function fieldsOf(inner) {
    const inputs = [...inner.matchAll(/<input\b[^>]*>/gi)].map(m => ({ name: attr(m[0], "name"), type: (attr(m[0], "type") || "text").toLowerCase(), value: attr(m[0], "value") ?? "" }))
      .filter(x => x.name);
    const selects = [...inner.matchAll(/<select\b([^>]*)>([\s\S]*?)<\/select>/gi)]
      .map(m => ({ name: attr("<x " + m[1] + ">", "name"), multiple: /\bmultiple\b/i.test(m[1]), options: optionsOf(m[2]) })).filter(x => x.name);
    return { inputs, selects };
  }

  // the tool's three forms on a page, each with its action (tied to the page's version) and its fields; a form the page
  // doesn't have is null. The first page has only the route form.
  function formsOf(html) {
    const out = { route: null, add: null, settings: null };
    for (const m of String(html).matchAll(/<form\b([^>]*)>([\s\S]*?)<\/form>/gi)) {
      const action = attr("<x " + m[1] + ">", "action"), f = fieldsOf(m[2]);
      if (!action) continue;
      if (/-aircraft\.eval\.route\.form$/.test(action)) {
        const text = f.inputs.filter(x => x.type === "text");
        const from = text.find(x => /^from\b/i.test(x.name)) || text[0], to = text.find(x => /^to\b/i.test(x.name)) || text[1];
        out.route = { action, from: from ? from.name : null, to: to ? to.name : null, names: { from: from ? from.value : "", to: to ? to.value : "" },
                      hidden: f.inputs.filter(x => x.type === "hidden").map(x => [x.name, x.value]) };
      } else if (/-evaluation-add$/.test(action)) {
        const list = f.selects.find(x => x.multiple) || f.selects[0];
        out.add = { action, name: list ? list.name : null, options: list ? list.options : [], hidden: f.inputs.filter(x => x.type === "hidden").map(x => [x.name, x.value]) };
      } else if (/-evaluation-settings$/.test(action)) {
        out.settings = { action, selects: f.selects, hidden: f.inputs.filter(x => x.type === "hidden").map(x => [x.name, x.value]) };
      }
    }
    return out;
  }

  // the route the page shows: its h2 ("Evaluation for route from … to …") and the names in the two boxes
  function routeOf(html) {
    const h = String(html).match(/<h2\b[^>]*>([\s\S]*?)<\/h2>/i), h2 = h ? textOf(h[1]) : null, f = formsOf(html).route;
    return { h2: h2 && /^Evaluation for route from /i.test(h2) ? h2 : null, from: f ? f.names.from : "", to: f ? f.names.to : "" };
  }
  // did the tool take the route? the h2, and both boxes holding names (not the codes typed)
  function routeProblem(html, from, to) {
    const r = routeOf(html);
    const ok = r.h2 && r.from && r.to && !same(r.from.toUpperCase(), from) && !same(r.to.toUpperCase(), to)
      && r.h2.includes(r.from) && r.h2.includes(r.to);
    return ok ? null : `the tool didn't take ${from} to ${to}`;
  }

  // a number as the tool writes it: 64,305 · 6.00 · 539 AS$ · -17% (a minus sign or hyphen); null when it isn't one
  function num(s) {
    const m = String(s).trim().replace(/[−–]/g, "-").match(/^(-?)\s*(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?\s*(?:[A-Z]{0,3}\$|%)?$/);
    return m ? Number(m[1] + m[2].replace(/,/g, "") + (m[3] || "")) : null;
  }
  // a profit cell, "-30,422 (-17%)": the amount and the margin, or null
  function profit(s) {
    const m = String(s).trim().match(/^(.+?)\s*\(\s*(.+?)\s*\)$/);
    if (!m) return null;
    const p = num(m[1]), g = /%$/.test(m[2].trim()) ? num(m[2]) : null;
    return p === null || g === null ? null : { profit: p, margin: g };
  }

  const cellsOf = tr => tr.split(/<td\b/i).slice(1).map(td => { const end = td.indexOf(">"); return { attrs: td.slice(0, end), html: td.slice(end + 1).replace(/<\/td>[\s\S]*$/i, "") }; });

  // the comparison table: one row per type added, each as capture_eval_result() takes it, and anything that didn't
  // read; null when the page has no table. With no types added the table's one row asks to select some: no rows.
  function tableOf(html) {
    const t = String(html).match(/<table\b[^>]*class\s*=\s*["'][^"']*\baircraftEvaluation\b[^"']*["'][^>]*>([\s\S]*?)<\/table>/i);
    if (!t) return null;
    const head = (t[1].match(/<thead\b[^>]*>([\s\S]*?)<\/thead>/i) || [, ""])[1];
    const heads = head.split(/<th\b/i).slice(1).map(x => textOf("<x" + x.replace(/<\/th>[\s\S]*$/i, "")));
    const out = { rows: [], problems: [] };
    if (heads.length && (heads.length !== COLUMNS.length + 1 || COLUMNS.some((c, i) => !same(heads[i + 1], c))))
      out.problems.push({ type: null, why: "the table's columns aren't the ones the script knows: " + heads.join(", ") });
    const body = (t[1].match(/<tbody\b[^>]*>([\s\S]*?)<\/tbody>/i) || [, t[1]])[1];
    for (const tr of body.split(/<tr\b/i).slice(1)) {
      const cells = cellsOf(tr);
      if (!cells.length) continue;
      const link = cells[0].html.match(/<a\b[^>]*href\s*=\s*["'][^"']*aircraftsType\?id=(\d+)[^"']*["'][^>]*>([\s\S]*?)<\/a>/i);
      if (!link) {
        if (cells.length === 1 && /select the aircraft types/i.test(textOf(cells[0].html))) continue;   // no types added yet
        out.problems.push({ type: null, why: "a row without its type: " + textOf(tr).slice(0, 80) });
        continue;
      }
      const name = textOf(link[2]), id = Number(link[1]), rest = cells.slice(1).map(c => textOf(c.html));
      if (rest.length === 1) {
        if (/cannot operate/i.test(rest[0])) out.rows.push(Object.assign({ type_name: name, game_type_id: id, can_operate: false, message: rest[0] },
                                                                        Object.fromEntries(FIGURES.concat(LOADS.flatMap(l => ["profit_" + l, "margin_" + l])).map(k => [k, null])), { cells: [name, rest[0]] }));
        else out.problems.push({ type: name, why: "one cell that doesn't say it cannot operate: " + rest[0] });
        continue;
      }
      if (rest.length !== COLUMNS.length) { out.problems.push({ type: name, why: `${rest.length} cells, not ${COLUMNS.length}` }); continue; }
      const row = { type_name: name, game_type_id: id, can_operate: true, message: null };
      const bad = [];
      FIGURES.forEach((k, i) => { row[k] = num(rest[i]); if (row[k] === null) bad.push(`${COLUMNS[i]} "${rest[i]}"`); });
      LOADS.forEach((l, j) => {
        const p = profit(rest[FIGURES.length + j]);
        row["profit_" + l] = p ? p.profit : null; row["margin_" + l] = p ? p.margin : null;
        if (!p) bad.push(`${l}% "${rest[FIGURES.length + j]}"`);
      });
      row.cells = [name].concat(rest);
      if (bad.length) out.problems.push({ type: name, why: "not a number: " + bad.join(", ") });
      else out.rows.push(row);
    }
    return out;
  }

  // the types on the run list that aren't in the table yet
  const missingTypes = (table, types) => types.filter(n => !table.rows.some(r => same(r.type_name, n)) && !table.problems.some(p => p.type && same(p.type, n)));

  // the add list's values for those types, read by their text from this page's list (the values shift as types are
  // added, and types in the table are left out of the list); or why not
  function addValues(form, names) {
    if (!form || !form.name) return { problem: "the page has no add list" };
    const values = [];
    for (const n of names) {
      const hits = form.options.filter(o => same(o.text, n));
      if (!hits.length) return { problem: n + " isn't in the tool's add list" };
      if (hits.length > 1) return { problem: n + " is in the tool's add list twice" };
      values.push(hits[0].value);
    }
    return { values };
  }

  // the settings the page shows, by their texts: { age, class, seat, price_factor }, or null without the settings form
  function settingsOf(form) {
    if (!form) return null;
    const out = {};
    for (const [field, key] of Object.entries(SETTING_NAMES)) { const s = form.selects.find(x => x.name === field), o = s && shown(s.options); out[key] = o ? o.text : null; }
    return out;
  }
  // what the settings form must send for a run (age 0, Economy, 100% and the run's seat, each value read by its text
  // from the page), whether the page shows them already, or why it can't
  function settingsFor(form, seat) {
    if (!form) return { problem: "the page has no settings form" };
    const pairs = form.hidden.slice(), want = Object.assign({}, WANT, { seat: t => t === seat });
    let ok = true;
    for (const s of form.selects) {
      const test = want[s.name];
      const o = test ? s.options.find(x => test(x.text)) : shown(s.options);
      if (!o) return { problem: test ? `the settings' ${s.name} list has no ${s.name === "seat" ? seat : "option the run needs"}` : `the settings' ${s.name} has no options` };
      if (test && shown(s.options) !== o) ok = false;
      pairs.push([s.name, o.value]);
    }
    for (const k of Object.keys(want)) if (!form.selects.some(s => s.name === k)) return { problem: "the settings form has no " + k };
    return { ok, pairs };
  }

  // a form's body as the browser sends it (application/x-www-form-urlencoded), from name and value pairs
  const body = pairs => pairs.map(([k, v]) => encodeURIComponent(k) + "=" + encodeURIComponent(v)).join("&");
  const routeBody = (form, from, to) => body(form.hidden.concat([[form.from, from], [form.to, to]]));
  const addBody = (form, values) => body(form.hidden.concat(values.map(v => [form.name, v])));
  const settingsBody = pairs => body(pairs);

  // a form's action as an address, resolved against the page it came from; null unless it posts back to the tool
  function actionUrl(action, pageUrl) {
    let u; try { u = new URL(action, pageUrl); } catch (e) { return null; }
    return u.pathname.replace(/;.*$/, "") === TOOL ? u.href : null;
  }

  // one run's result as capture_eval_result() takes it, from the page that shows it, or why it can't be read
  function resultOf(html, types, seat) {
    const table = tableOf(html), forms = formsOf(html);
    if (!table) return { problem: "the result didn't read: the page has no comparison table" };
    const p = table.problems[0];
    if (p) return { problem: "the result didn't read" + (p.type ? ": " + p.type : "") + " (" + p.why + ")" };
    const missing = missingTypes(table, types);
    if (missing.length) return { problem: "the result didn't read: no row for " + missing.join(", ") };
    const settings = settingsOf(forms.settings);
    if (!settings || settings.seat !== seat) return { problem: `the result didn't read: the page shows seat ${settings ? settings.seat : "(none)"}, not ${seat}` };
    const r = routeOf(html);
    return { doc: { from_name: r.from, to_name: r.to, settings, rows: table.rows }, canFly: table.rows.filter(x => x.can_operate && types.some(n => same(n, x.type_name))).length };
  }

  // capture_eval_runs()'s answer as the run needs it, or the error
  function planOf(doc) {
    if (!doc || doc.ok !== true) return { error: (doc && (doc.error || doc.message || doc.hint)) || "no answer" };
    if (!Array.isArray(doc.types) || !doc.types.length || doc.types.some(t => typeof t !== "string" || !t.trim())) return { error: "the answer has no list of types" };
    if (!Array.isArray(doc.runs)) return { error: "the answer has no runs" };
    const problems = [];
    for (const r of doc.runs) {
      if (!r || !/^\d+$/.test(String(r.id ?? ""))) problems.push({ run: r, why: "a run without its id" });
      else if (!/^[A-Z0-9]{3}$/.test(String(r.from)) || !/^[A-Z0-9]{3}$/.test(String(r.to))) problems.push({ run: r, why: "a run without two airport codes" });
      else if (!SEATS.includes(r.seat)) problems.push({ run: r, why: "a seat the script doesn't know: " + r.seat });
    }
    return { world: doc.world || null, types: doc.types, total: Number(doc.total) || 0, done: Number(doc.done) || 0,
             runs: doc.runs.map(r => ({ id: Number(r.id), pass: r.pass, seq: r.seq, from: r.from, to: r.to, seat: r.seat })), problems };
  }

  // one run, start to end, on the latest page: the route, any types still to add, the settings, the table read and
  // saved. io is the outside world: post(url, body) sends one of the tool's forms and answers { ok, status, url, html },
  // sleep(ms), and save(doc) is capture_eval_result(). Every form is taken from the latest page fetched, never an older
  // one, and only the tool's three forms are ever sent. Answers { page (the latest), canFly, saved }, or throws an Error
  // saying why it stopped.
  async function runOne(run, types, page, io) {
    const send = async (action, data) => {
      const url = actionUrl(action, page.url);
      if (!url) throw new Error("a form that doesn't post back to the tool (" + action + ")");
      const r = await io.post(url, data);
      if (!r.ok) throw new Error("the game answered HTTP " + r.status);
      const path = new URL(r.url || url).pathname.replace(/;.*$/, "");
      if (path !== TOOL) throw new Error("the game sent it to " + path + ": the session may have been lost");
      if (!formsOf(r.html).route) throw new Error("the answer wasn't the tool's page: the session may have been lost");
      page = { html: r.html, url: r.url || url };
    };
    // 1. the route
    const route = formsOf(page.html).route;
    if (!route) throw new Error("the tool's route form isn't on the page: the session may have been lost");
    await send(route.action, routeBody(route, run.from, run.to));
    const rp = routeProblem(page.html, run.from, run.to);
    if (rp) throw new Error(rp);
    // 2. any of the types not in the table yet, by their text in this page's add list
    let table = tableOf(page.html);
    if (!table) throw new Error("the page has no comparison table");
    let missing = missingTypes(table, types);
    if (missing.length) {
      const form = formsOf(page.html).add, add = addValues(form, missing);
      if (add.problem) throw new Error(add.problem);
      await io.sleep(POST_PAUSE_MS);
      await send(form.action, addBody(form, add.values));
      table = tableOf(page.html);
      missing = table ? missingTypes(table, types) : types;
      if (missing.length) throw new Error("still not in the table after adding: " + missing.join(", "));
    }
    // 3. the settings: age 0, Economy, 100% and the run's seat, by their texts
    let form = formsOf(page.html).settings, want = settingsFor(form, run.seat);
    if (want.problem) throw new Error(want.problem);
    if (!want.ok) {
      await io.sleep(POST_PAUSE_MS);
      await send(form.action, settingsBody(want.pairs));
      form = formsOf(page.html).settings; want = settingsFor(form, run.seat);
      if (want.problem || !want.ok) throw new Error("the settings didn't take (the page shows " + JSON.stringify(settingsOf(form)) + ")");
    }
    // 4. the table, and 5. saved
    const res = resultOf(page.html, types, run.seat);
    if (res.problem) throw new Error(res.problem);
    let saved;
    try { saved = await io.save(res.doc); } catch (e) { throw new Error("couldn't reach the database (" + e.message + ")"); }
    if (!saved || saved.ok !== true) throw new Error("the database didn't save it: " + ((saved && (saved.error || saved.message)) || "no answer"));
    return { page, canFly: res.canFly, saved };
  }

  // the panel's words
  const plural = (n, one, many) => n + " " + (n === 1 ? one : many);
  const runWords = r => `${r.from} to ${r.to}, ${r.seat}`;
  const askWords = (left, total) => `${plural(left, "run", "runs")} left of ${total}, about ${plural(Math.max(1, Math.round(left * RUN_MS / 60000)), "minute", "minutes")}. Leave this tab open and watch; Stop is here throughout. It only reads the tool: nothing in the game changes.`;
  const progressWords = (i, n, r, canFly) => `Run ${i} of ${n}: ${runWords(r)}` + (canFly === undefined || canFly === null ? "" : ` · ${canFly} can fly`);
  const endWords = (saved, left, why, at) => why
    ? `Stopped. ${plural(saved, "run", "runs")} saved.` + (at ? `\nAt run ${at.i} of ${at.n}: ${runWords(at.run)}.` : "") + `\nWhy: ${why}.\n\nWhat's saved stays saved: press Aircraft evaluation again to carry on from the first run without a result.`
    : `Done: ${plural(saved, "run", "runs")} saved` + (left ? `, ${left} still without a result.` : ". Every run on the list has its result.");

  const lib = { TOOL, PAUSE_MS, POST_PAUSE_MS, SEATS, COLUMNS, num, profit, formsOf, routeOf, routeProblem, tableOf, missingTypes, addValues,
                settingsOf, settingsFor, routeBody, addBody, settingsBody, actionUrl, resultOf, runOne, planOf, askWords, progressWords, endWords };
  if (typeof document === "undefined" || !root.location || !root.sessionStorage) { root.eqEval = lib; return; }

  // ---------------------------------------------------------------- in the game
  const KEY = "__CAPTURE_KEY__", ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZWN3c3llZHZ3Y3hnZHptaG9xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMTg5MzcsImV4cCI6MjEwNTc5NDkzN30.tC56dOgmPeYB3m58aDy4ADnnaZ3613P6MFp2pVXUj_Y", RPC = "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/";
  const ST = "eq_aircraft_eval", STALE_MS = 3 * 60 * 1000;   // a run untouched for 3 minutes isn't picked up again by itself
  const get = () => { try { return JSON.parse(sessionStorage.getItem(ST) || "null"); } catch (e) { return null; } };
  const set = s => { s.at = Date.now(); sessionStorage.setItem(ST, JSON.stringify(s)); };
  const clear = () => sessionStorage.removeItem(ST);
  const rpc = async (fn, args) => { const r = await fetch(RPC + fn, { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" }, body: JSON.stringify(args) }); return r.json(); };
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  let stopping = false;
  // the latest page of the tool: this tab's page to begin with, then each answer fetched
  let page = null;
  const thisPage = () => ({ html: document.documentElement.outerHTML, url: location.href });

  // the outside world for a run: the tool's forms by fetch with the session's cookies, and the clock (each run adds
  // its save, capture_eval_result())
  const io = {
    post: async (url, data) => {
      let r;
      try { r = await fetch(url, { method: "POST", credentials: "include", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: data }); }
      catch (e) { throw new Error("the game didn't answer (" + e.message + "): the session may have been lost"); }
      return { ok: r.ok, status: r.status, url: r.url, html: await r.text() };
    },
    sleep
  };

  // the panel, like the fares userscript's, with its buttons in the page (no browser dialogs)
  function panel() {
    let b = document.getElementById("eq-eval-panel");
    if (!b) {
      b = document.createElement("div"); b.id = "eq-eval-panel";
      b.style.cssText = "position:fixed;top:12px;right:12px;z-index:999999;background:#0A1230;color:#fff;font:14px/1.5 system-ui,sans-serif;padding:14px 18px;border-radius:14px;box-shadow:0 20px 50px rgba(0,0,0,.4);max-width:400px;max-height:80vh;overflow:auto";
      const t = document.createElement("div"); t.className = "eq-eval-text"; t.style.whiteSpace = "pre-line";
      const k = document.createElement("div"); k.className = "eq-eval-buttons"; k.style.cssText = "margin-top:10px;display:flex;gap:8px;flex-wrap:wrap";
      b.append(t, k); document.body.appendChild(b);
    }
    return b;
  }
  function show(text, buttons) {
    const b = panel(); b.querySelector(".eq-eval-text").textContent = text;
    const k = b.querySelector(".eq-eval-buttons"); k.textContent = "";
    for (const [label, fn, main] of buttons || []) {
      const x = document.createElement("button"); x.textContent = label;
      x.style.cssText = "border:0;border-radius:999px;padding:7px 14px;font:700 13px system-ui,sans-serif;cursor:pointer;" + (main ? "background:#F6B44B;color:#0A1230" : "background:#26305a;color:#fff");
      x.onclick = fn; k.appendChild(x);
    }
  }
  const close = () => { const b = document.getElementById("eq-eval-panel"); if (b) b.remove(); };
  const stopButton = ["Stop", () => { stopping = true; const s = get(); if (s) { s.stop = true; set(s); } show("Stopping after this step…"); }];
  const lines = s => (s.log || []).join("\n");
  const note = (s, line) => { s.log = (s.log || []).concat(line).slice(-8); };

  function finish(s, why) {
    clear();
    const at = why && s.runs[s.i] ? { i: s.i + 1, n: s.runs.length, run: s.runs[s.i] } : null;
    show(endWords(s.saved, s.runs.length - s.i, why, at), [["Close", close, true]]);
  }

  // the runs, one after another, each by fetch with the session's cookies; the tab stays where it is
  async function go() {
    let s = get(); if (!s) return;
    show(lines(s), [stopButton]);
    while (s.i < s.runs.length) {
      if (s.stop || stopping) return finish(s, "you pressed Stop");
      const run = s.runs[s.i];
      try {
        const r = await runOne(run, s.types, page, Object.assign({}, io, { save: doc => rpc("capture_eval_result", { p_key: KEY, p_run: run.id, p_doc: doc }) }));
        page = r.page;
        s = get() || s;
        s.saved += 1; s.i += 1;
        note(s, progressWords(s.i, s.runs.length, run, r.canFly));
        set(s);
        show(lines(s), [stopButton]);
      } catch (e) {
        return finish(s, e.message);
      }
      if (s.i < s.runs.length) { await sleep(PAUSE_MS); s = get(); if (!s) return; }
    }
    finish(s, null);
  }

  // the button: read the run list, and ask once in the panel before the first run
  async function begin(btn) {
    if (get()) { show(lines(get()), [stopButton]); return; }
    if (!formsOf(document.documentElement.outerHTML).route) return show("equinox. aircraft evaluation: the tool's route form isn't on this page. Open the aircraft evaluation tool and try again.", [["Close", close, true]]);
    btn.disabled = true; show("equinox. aircraft evaluation: reading the run list…");
    let plan;
    try { plan = planOf(await rpc("capture_eval_runs", { p_key: KEY })); } catch (e) { plan = { error: e.message }; }
    btn.disabled = false;
    if (plan.error) return show("equinox. aircraft evaluation: couldn't read the run list (" + plan.error + "). Check the capture key.", [["Close", close, true]]);
    if (plan.problems.length) return show(`equinox. aircraft evaluation: a run on the list can't be made as it stands, so nothing was run.\nWhy: ${plan.problems[0].why}.`, [["Close", close, true]]);
    if (!plan.runs.length) return show(`equinox. aircraft evaluation: nothing to run. Every one of the ${plan.total} runs on the list has its result.`, [["Close", close, true]]);
    show("Aircraft evaluation\n\n" + askWords(plan.runs.length, plan.total), [["Go ahead", () => {
      stopping = false; page = thisPage();
      const t = { runs: plan.runs, types: plan.types, i: 0, saved: 0, stop: false, log: [] };
      note(t, "Running the aircraft evaluation…"); set(t); go();
    }, true], ["Cancel", close]]);
  }

  function addButton() {
    if (document.getElementById("eq-eval-btn")) return;
    const b = document.createElement("button"); b.id = "eq-eval-btn"; b.textContent = "Aircraft evaluation";
    b.style.cssText = "position:fixed;bottom:64px;left:16px;z-index:999998;background:#F6B44B;color:#0A1230;border:0;border-radius:999px;padding:10px 16px;font:700 13px system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.35);cursor:pointer";
    b.onclick = () => begin(b);
    document.body.appendChild(b);
  }

  addButton();
  const s = get();
  if (s) {
    // a reload carries on from the run it was on, with this page as the latest; a run left for minutes (the tab closed,
    // the session lost and signed in again) isn't picked up by itself
    if (Date.now() - (s.at || 0) > STALE_MS) finish(s, "the run was interrupted (nothing happened for over 3 minutes)");
    else { page = thisPage(); show(lines(s), [stopButton]); setTimeout(go, 800); }
  }
})(typeof window !== "undefined" ? window : globalThis);
