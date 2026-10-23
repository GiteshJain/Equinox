// ==UserScript==
// @name         equinox. capture all airlines
// @namespace    equinox
// @version      1.8
// @description  One button: for each of the world's airlines (the database lists them), captures loads, finances and payments for the planner, then the airline's fleet pages (each aircraft's condition, maintenance, seats and pilots). Then, when a world scan is due (the setting scan_every_days), scans the world as scripts/scanner/gscan.py does: every airline's schedule and overview page (its fleet and aircraft on order) and the airport pages, sent with the capture key. Keep the tab open; a scan evening takes about 5 minutes longer. Salaries are a separate script (salary_adjust.user.js), run by hand on one airline.
// @match        https://gander.airlinesim.aero/*
// @grant        none
// ==/UserScript==
// The capture (manual §7) is as it was in 1.4: the same pages, sent the same way, with the same verdicts. Since 1.5 (spec
// docs/specs/2026-10-21-scan-in-capture.md) it also scans the world after our airlines when capture_airlines() says a
// scan is due, unless a capture page failed: the airline list (26 letter pages), each airline's schedule and the airport
// pages capture_airlines() lists, read exactly as gscan.py reads them and sent through capture_scan() with the capture
// key, at gscan.py's pace. Since 1.6 (spec docs/specs/2026-10-22-fleet-capture.md §1) each airline's pages end with its
// fleets: the fleet list and every fleet with aircraft, each sent to capture_ingest() as page kind fleet, half a second
// apart. Since 1.7 the panel's lines scroll inside it and follow the newest one, so the last lines ("Done",
// "World scan done") stay in view however long the evening's log gets. Since 1.8 (spec
// docs/specs/2026-10-23-rival-fleets.md §2) the scan also reads each airline's overview page after its schedule
// (/app/info/enterprises/<id>: its fleet by type with aircraft on order, and its general figures) and sends it to
// capture_scan() as kind fleet; a failed overview page is logged and skipped, and never counts towards the 10% of failed
// airline pages that leave a scan unfinished. The reading of the pages is plain functions over the pages' HTML, without the page, so
// tests/capture_scan_test.mjs and tests/capture_fleet_test.mjs run this same file in Node, where (with no page) it only
// hands those functions over (as eqScan): the first compares what they read with what gscan.py reads from the same saved
// pages, the second reads a saved fleet page.
(function (root) {
  "use strict";

  // ---------------------------------------------------------------- the world scan's logic, without the page
  const VERSION = "1.8";                                      // the @version above, in the scan's notes
  const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const PACE = { letter: 400, airline: 500, fleet: 500, airport: 250 };   // ms between pages, gscan.py's own (1.8: fleet, the overview page)
  const MAX_FAILED_SHARE = 0.1;                                // more airline pages failed than this: the scan isn't finished
  const PAGE_TIMEOUT_MS = 40000;                               // gfetch.py's timeout
  const letterUrl = L => "/app/info/enterprises?letter=" + L;
  const airlineUrl = id => "/app/info/enterprises/" + id + "?tab=3";
  const airportUrl = id => "/app/info/airports/" + id;
  const overviewUrl = id => "/app/info/enterprises/" + id;   // 1.8: the overview tab, its Fleet table

  // html.unescape() as Python does it, for what the game's pages hold: numeric references and the named ones below (a
  // name not listed is decoded by the browser where there is one, else left as it is)
  const NAMED = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: "\u00a0", ndash: "\u2013", mdash: "\u2014", lsquo: "\u2018",
    rsquo: "\u2019", ldquo: "\u201c", rdquo: "\u201d", hellip: "\u2026", bull: "\u2022", euro: "\u20ac", trade: "\u2122", middot: "\u00b7",
    copy: "\u00a9", reg: "\u00ae", deg: "\u00b0", szlig: "\u00df", aacute: "\u00e1", agrave: "\u00e0", acirc: "\u00e2", auml: "\u00e4",
    atilde: "\u00e3", aring: "\u00e5", ccedil: "\u00e7", eacute: "\u00e9", egrave: "\u00e8", ecirc: "\u00ea", euml: "\u00eb", iacute: "\u00ed",
    igrave: "\u00ec", icirc: "\u00ee", iuml: "\u00ef", ntilde: "\u00f1", oacute: "\u00f3", ograve: "\u00f2", ocirc: "\u00f4", ouml: "\u00f6",
    otilde: "\u00f5", oslash: "\u00f8", uacute: "\u00fa", ugrave: "\u00f9", ucirc: "\u00fb", uuml: "\u00fc", yacute: "\u00fd", Aacute: "\u00c1",
    Auml: "\u00c4", Aring: "\u00c5", Ccedil: "\u00c7", Eacute: "\u00c9", Iacute: "\u00cd", Ntilde: "\u00d1", Oacute: "\u00d3", Ouml: "\u00d6",
    Oslash: "\u00d8", Uacute: "\u00da", Uuml: "\u00dc" };
  function decodeRef(m, body) {
    if (body[0] === "#") {
      const n = /^#x/i.test(body) ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      return Number.isFinite(n) && n > 0 && n <= 0x10ffff && !(n >= 0xd800 && n <= 0xdfff) ? String.fromCodePoint(n) : "\ufffd";
    }
    if (Object.prototype.hasOwnProperty.call(NAMED, body)) return NAMED[body];
    if (root.document && root.document.createElement) { const t = root.document.createElement("textarea"); t.innerHTML = m; return t.value; }
    return m;
  }
  const unescape = s => String(s).replace(/&(#\d+|#x[0-9a-f]+|[a-z][a-z0-9]*);/gi, decodeRef);
  // gscan.py's text(): tags to spaces, unescaped, whitespace collapsed, trimmed
  const text = s => unescape(String(s).replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
  const reEscape = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

  // one letter page of the airline list: each airline's game ID and name, as [id, name], in the page's order
  function readLetterPage(html) {
    return [...String(html).matchAll(/href="\.\/enterprises\/(\d+)"[^>]*>\s*([^<]{1,80}?)\s*</g)].map(m => [Number(m[1]), unescape(m[2])]);
  }
  // the airlines read so far, by game ID (a later page's name wins, as in gscan.py's dict)
  function addAirlines(byId, pairs) { const out = { ...(byId || {}) }; for (const [id, name] of pairs) out[id] = name; return out; }
  // the airlines in the order gscan.py scans them: by game ID
  const airlineList = byId => Object.keys(byId || {}).map(Number).sort((a, b) => a - b).map(id => [id, byId[id]]);

  // one airline's schedule page (?tab=3): its flights as gscan.py's rows, [code, number, from, to, weekdays, departure,
  // arrival, aircraft, operator], and every airport id the page links (code → id)
  function readSchedulePage(html) {
    html = String(html);
    const airports = {};
    for (const m of html.matchAll(/href="\.\.\/airports\/(\d+)"[^>]*>\s*([A-Z0-9]{3})\s*</g)) airports[m[2]] = Number(m[1]);
    const clean = html.replace(/<script[\s\S]*?<\/script>/g, "");
    const t = clean.match(/<table[\s\S]*?<\/table>/), table = t ? t[0] : "";
    const flights = []; let from = "", to = "";
    for (const row of table.match(/<tr[\s\S]*?<\/tr>/g) || []) {
      const cells = [...row.matchAll(/<t[hd][^>]*>([\s\S]*?)<\/t[hd]>/g)].map(c => text(c[1])), j = cells.join(" | ");
      const mf = j.match(/^from .*\(\s*([A-Z0-9]{3})\s*\)/), mt = j.match(/^to .*\(\s*([A-Z0-9]{3})\s*\)/);
      if (mf) { from = mf[1]; continue; }
      if (mt) { to = mt[1]; continue; }
      if (cells.length >= 4 && /^[A-Z0-9]{2,3} \d{1,5}[A-Z]?$/.test(cells[0])) {
        const [code, no] = cells[0].split(" "), days = (cells.length > 1 ? cells[1] : "").replace(/[^1-7]/g, "");
        flights.push([code, no, from, to, days, cells[2], cells[3], cells.length > 4 ? cells[4] : "", cells.length > 5 ? cells[5] : ""]);
      }
    }
    return { flights, airports };
  }
  // what capture_scan() takes for an airline, as gscan.py sends it to ingest_snapshot()
  function airlinePayload(scanId, id, name, flights) {
    return { snapshot_id: scanId, enterprise_id: id, name, flights, n_flights: flights.length,
             n_weekly: flights.reduce((n, f) => n + f[4].length, 0), n_airports: new Set(flights.flatMap(f => [f[2], f[3]])).size };
  }

  // one airport page: its details, the airlines stationed there and its news, as gscan.py reads them
  function readAirportPage(html) {
    html = String(html);
    const t = text(html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, ""));
    const kv = (label, next) => { const m = t.match(new RegExp(reEscape(label) + "\\s+(.*?)\\s+" + next)); return m ? m[1] : null; };
    const info = { size: kv("Airport size", "Slots"), slots_per_5min: kv("Slots (per 5 minutes)", "Slot Availability"),
                   slot_availability: kv("Slot Availability", "Min\\."), min_transfer: kv("Min. transfer time", "Nighttime"),
                   night_ban: kv("Nighttime ban", "Noise"), runway: kv("Runway", "Airport size"), country: kv("Country", "Continent"),
                   continent: kv("Continent", "Runway") };
    const stations = [];
    for (const row of html.match(/<tr>[\s\S]*?<\/tr>/g) || []) {
      const m = row.match(/href="\.\.\/enterprises\/(\d+)">([^<]*)<\/a>/), d = row.match(/([\d,]+)\s*Departures/);
      if (!(m && d)) continue;
      const al = row.match(/alliances\/(\d+)/), tds = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(x => x[1]);
      stations.push({ enterprise_id: Number(m[1]), name: unescape(m[2]).trim(), weekly: parseInt(d[1].replace(/,/g, ""), 10),
                      alliance: al ? Number(al[1]) : null, interline: tds.length > 3 ? /<(img|span|i)\b/.test(tds[3]) : false });
    }
    const news = [...t.matchAll(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) UTC\s+(.*?)(?=\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC|Found a mistake)/g)]
      .map(m => ({ at: m[1], text: m[2].trim() }));
    return { info, stations, news };
  }
  const airportPayload = (scanId, code, airportId, page) => ({ snapshot_id: scanId, code, airport_id: airportId, info: page.info, stations: page.stations, news: page.news });
  // 1.8 (spec docs/specs/2026-10-23-rival-fleets.md §1, §2): one airline's overview page, as gscan.py reads it: its Fleet
  // table (table.fleet: per type the link's text and its aircraftsType?id=, owned, leased, overall, leased out, on offer,
  // on order and the average age; tfoot the totals), General Information (code, alliance, headquarters, parent company,
  // founded) and General statistics (passengers, stations, fleet size, staff). An error when the page has neither the
  // Fleet table nor General Information (not the overview page, or the page changed); an airline with no aircraft at all
  // may have no Fleet table, so General Information alone reads as a fleet of none.
  const count = s => { const m = String(s).replace(/,/g, "").match(/-?\d+(?:\.\d+)?/); return m ? Number(m[0]) : null; };
  const FLEET_COLS = ["owned", "leased", "overall", "leased_out", "on_offer", "on_order"];
  function fleetRow(cells) {
    const out = {};
    FLEET_COLS.forEach((k, i) => { out[k] = cells.length > i ? count(text(cells[i])) : null; });
    out.avg_age_years = cells.length > 6 ? count(text(cells[6])) : null;
    return out;
  }
  const tdsOf = row => [...String(row).matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(c => c[1]);
  // the label-and-value table under a legend ("General Information"), as {label: the value's HTML}
  function legendTable(html, legend) {
    const m = html.match(new RegExp('<span class="legend">\\s*' + reEscape(legend) + '\\s*</span>[\\s\\S]*?<table[^>]*>([\\s\\S]*?)</table>'));
    if (!m) return null;
    const out = {};
    for (const row of m[1].match(/<tr[\s\S]*?<\/tr>/g) || []) { const c = tdsOf(row); if (c.length >= 2) out[text(c[0])] = c[1]; }
    return out;
  }
  function readOverviewPage(html) {
    html = String(html).replace(/<script[\s\S]*?<\/script>/g, "");
    const info = legendTable(html, "General Information"), stats = legendTable(html, "General statistics") || {};
    const fm = html.match(/<table[^>]*class="[^"]*\bfleet\b[^"]*"[^>]*>([\s\S]*?)<\/table>/);
    if (!fm && !info) return { error: "no Fleet table or General Information on the page" };
    const types = [];
    const body = fm ? (fm[1].match(/<tbody[^>]*>([\s\S]*?)<\/tbody>/) || [null, ""])[1] : "";
    for (const row of body.match(/<tr[\s\S]*?<\/tr>/g) || []) {
      const c = tdsOf(row);
      if (c.length < 8) continue;
      const name = text(c[0]), id = c[0].match(/aircraftsType\?id=(\d+)/);
      if (!name) continue;
      types.push({ type: name, type_id: id ? Number(id[1]) : null, ...fleetRow(c.slice(1)) });
    }
    const foot = fm ? (fm[1].match(/<tfoot[^>]*>([\s\S]*?)<\/tfoot>/) || [null, ""])[1] : "";
    const ft = tdsOf(foot);
    const totals = ft.length >= 7 ? fleetRow(ft)
      : { ...Object.fromEntries(FLEET_COLS.map(k => [k, types.reduce((n, t) => n + (t[k] || 0), 0)])), avg_age_years: null };
    const v = k => (info && info[k] != null ? text(info[k]) : null), raw = k => (info && info[k]) || "";
    const al = raw("Alliance").match(/alliances\/(\d+)/), hq = (v("Headquarters") || "").match(/\(\s*([A-Z0-9]{3})\s*\)/);
    const parent = raw("Parent company").match(/href="(?:\.\/|[^"]*enterprises\/)(\d+)"/), founded = (v("Founded") || "").match(/\d{4}-\d{2}-\d{2}/);
    const st = k => (stats[k] != null ? count(text(stats[k])) : null);
    return { name: v("Name") || null, types, totals,
             profile: { code: v("Code") || null, alliance: al ? v("Alliance") || null : null, alliance_id: al ? Number(al[1]) : null,
                        headquarters: hq ? hq[1] : null, parent_id: parent ? Number(parent[1]) : null, parent: parent ? v("Parent company") || null : null,
                        founded: founded ? founded[0] : null, passengers: st("Transported passengers"), stations: st("Stations"),
                        fleet_size: st("Fleet size"), staff: st("Staff") } };
  }
  // what capture_scan() takes for an overview page (kind fleet), as gscan.py sends it to ingest_snapshot(); with error in
  // place of the rows when the page didn't read
  function fleetScanPayload(scanId, id, name, read, error) {
    const base = { snapshot_id: scanId, enterprise_id: id, name };
    const err = error || (read && read.error) || (!read ? "nothing read" : null);
    return err ? { ...base, error: String(err) } : { ...base, types: read.types, totals: read.totals, profile: read.profile };
  }
  // finish, with gscan.py's note and what the capture's scan adds (1.8: the fleet pages read and failed)
  const finishPayload = (scanId, nAirlines, nAirports, failedAirlines, noId, fleetPages = 0, fleetFailed = 0) => ({ snapshot_id: scanId,
    note: `full scan: ${nAirlines} enterprises, ${nAirports} airports (Capture all airlines ${VERSION}; ${plural(failedAirlines, "airline page", "airline pages")} failed, ${plural(noId, "airport", "airports")} without an id; ${plural(fleetPages, "fleet page", "fleet pages")}, ${fleetFailed} failed)` });

  // more than 10% of the airlines failed (or none were read): the scan isn't finished
  const tooManyFailed = (failed, total) => !total || failed > MAX_FAILED_SHARE * total;
  // the ISO week of a moment (UTC), as game_scans.week: "43"
  function isoWeek(at) {
    const d = new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate()));
    d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
    return String(Math.ceil(((d - Date.UTC(d.getUTCFullYear(), 0, 1)) / 864e5 + 1) / 7));
  }
  // capture_airlines()'s world scan, as the capture needs it
  const planOf = r => ({ due: !!(r && r.scan_due === true), open: r && r.scan_open != null ? Number(r.scan_open) : null,
                         every: r && r.scan_every_days != null ? Number(r.scan_every_days) : null, latest: (r && r.scan_latest) || null,
                         airports: (r && Array.isArray(r.scan_airports) ? r.scan_airports : []).filter(c => /^[A-Z0-9]{3}$/.test(c)) });
  const when = iso => { const d = new Date(iso); return isNaN(d) ? String(iso) : d.toISOString().slice(0, 16).replace("T", " ") + " UTC"; };
  // why there's no scan tonight, or null when it runs
  function noScanWords(plan, failed) {
    if (!plan || plan.every == null) return "World scan: off (the world has no scan_every_days setting).";
    if (!plan.due) return `World scan: not due${plan.latest ? `; the last finished ${when(plan.latest.taken_at)}` : ""} (every ${plural(plan.every, "day", "days")}).`;
    if (failed) return `World scan: not tonight, because ${plural(failed, "capture page", "capture pages")} failed. Capture again; the scan follows while it's due.`;
    return null;
  }
  function progressWords(sc) {
    if (sc.step === "letters") return `World scan: reading the airline list, letter ${LETTERS[Math.min(sc.li, 25)]} of 26…`;
    if (sc.step === "airlines") return `World scan: ${sc.ai} of ${sc.list.length} airlines…`;
    if (sc.step === "airports") return `World scan: ${sc.list.length} airlines read; airports, ${sc.pi} of ${sc.airports.length}…`;
    return "World scan…";
  }
  const plural = (n, one, many) => n + " " + (n === 1 ? one : many);

  // ---------------------------------------------------------------- the fleet pages' logic, without the page (1.6)
  // Spec docs/specs/2026-10-22-fleet-capture.md §1: after each airline's other pages, the fleet list (/app/fleets, which
  // is also the Default fleet's page) and every fleet with aircraft in it (/app/fleets/<id>, Gitesh keeps one per hub),
  // each sent to capture_ingest() as page kind fleet. tests/capture_fleet_test.mjs reads a saved page with these.
  const FLEET_PACE = 500;                                      // ms between fleet pages, the scan's pace for an airline's page
  const fleetListUrl = "/app/fleets";
  const fleetUrl = id => (id == null ? fleetListUrl : "/app/fleets/" + id);
  const num = s => { const m = String(s == null ? "" : s).replace(/,/g, "").match(/-?\d+(?:\.\d+)?/); return m ? Number(m[0]) : null; };
  const cellsOf = row => [...String(row).matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(c => c[1]);
  // a cell's own line and its second line (the game's "subrow" under it)
  const split = cell => { const i = cell.search(/<div class="subrow/); return i < 0 ? [cell, ""] : [cell.slice(0, i), cell.slice(i)]; };
  // one fleet page: the airline's fleets (the list on the left: each fleet's game id, null for Default, its name and how
  // many aircraft it holds), the fleet shown (its heading) and its aircraft, each as the table shows it; or an error when
  // the page has no fleet table (not signed in, or the page changed)
  function readFleetPage(html) {
    html = String(html).replace(/<script[\s\S]*?<\/script>/g, "");
    const fleets = [];
    const lm = html.match(/<h3>\s*Fleets\s*<\/h3>[\s\S]*?<table[\s\S]*?<\/table>/);
    for (const row of (lm ? lm[0] : "").match(/<tr[\s\S]*?<\/tr>/g) || []) {
      const m = row.match(/<a href="([^"]*)"[^>]*>([\s\S]*?)<\/a>\s*\(\s*(?:<span>)?\s*([\d,]+)\s*(?:<\/span>)?\s*\)/);
      if (!m) continue;
      const id = m[1].match(/fleets\/(\d+)\/?(?:[?#][^"]*)?$/) || m[1].match(/^\.?\/?(\d+)(?:[?#][^"]*)?$/);
      fleets.push({ id: id ? Number(id[1]) : null, name: text(m[2]), aircraft: num(m[3]) });
    }
    const hm = html.match(/<div class="col-md-9">\s*<h2>([\s\S]*?)<\/h2>/);
    const tm = html.match(/<table[^>]*>\s*<thead[\s\S]*?Reg\.#[\s\S]*?<\/thead>\s*<tbody[^>]*>([\s\S]*?)<\/tbody>/);
    if (!tm) return { name: hm ? text(hm[1]) : null, fleets, aircraft: [], error: "no fleet table on the page" };
    const aircraft = [];
    for (const row of tm[1].match(/<tr[\s\S]*?<\/tr>/g) || []) {
      const c = cellsOf(row);
      if (c.length < 7) continue;
      const [regMain, regSub] = split(c[1]), [locMain, locSub] = split(c[3]), [ageMain, ageSub] = split(c[4]), [seatMain, seatSub] = split(c[5]);
      const registration = text(regMain);
      if (!registration) continue;
      const nick = text(regSub), codes = [...locMain.matchAll(/>\s*([A-Z0-9]{3})\s*<\/a>/g)].map(m => m[1]);
      const pct = [...text(ageSub).matchAll(/(-?\d+(?:\.\d+)?)\s*%/g)].map(m => Number(m[1]));
      const seats = text(seatMain).split("/").map(num), pilots = text(seatSub).toLowerCase();
      const owned = text(c[6]).match(/Owned:\s*(yes|no)\b/i), contract = c[6].match(/Contract status:\s*<span[^>]*>([\s\S]*?)<\/span>/);
      const type = c[2].match(/aircraftsType\?id=(\d+)/), game = c[6].match(/[/"]aircraft\/(\d+)\/0"/);
      aircraft.push({ registration, nickname: nick && nick !== "..." ? nick : null, type: text(c[2]) || null, type_id: type ? Number(type[1]) : null,
                      from: codes[0] || null, to: codes[1] || null, flight: text(locSub) || null, age_years: num(text(ageMain)),
                      condition_pct: pct.length > 0 ? pct[0] : null, maintenance_pct: pct.length > 1 ? pct[1] : null,
                      y: seats.length === 3 ? seats[0] : null, c: seats.length === 3 ? seats[1] : null, f: seats.length === 3 ? seats[2] : null,
                      pilots: pilots === "yes" ? true : pilots === "no" ? false : null,
                      owned: owned ? owned[1].toLowerCase() === "yes" : null, contract: contract ? text(contract[1]) || null : null,
                      game_id: game ? Number(game[1]) : null });
    }
    return { name: hm ? text(hm[1]) : null, fleets, aircraft };
  }
  // the fleets to read: every fleet with aircraft in it (one whose count didn't read is read too), the list's order
  const fleetsToRead = fleets => (fleets || []).filter(f => f.aircraft == null || f.aircraft > 0);
  // what capture_ingest() takes as a fleet page's rows: the run (when the airline's fleet list was read), which page of
  // how many, the fleet, the airline's fleets and the aircraft; with error instead of aircraft when the page didn't read
  function fleetPayload(run, page, of, fleet, fleets, read, error) {
    const base = { run, page, of, fleet: fleet ? { id: fleet.id, name: fleet.name } : null, fleets: fleets || [] };
    const err = error || (read && read.error) || (!read ? "nothing read" : null);
    return err ? { ...base, error: String(err) } : { ...base, aircraft: read.aircraft };
  }
  // the panel's words while a fleet page is read, for a fleet page the database answered (logged when it isn't ok), and
  // the airline's fleet pages in one line once they're all sent, so the panel keeps each airline's lines short
  const fleetProgress = (name, i, n) => `${name}: fleet ${i} of ${n}…`;
  const fleetOk = r => !!(r && r.ok === true && (!r.verdict || r.verdict.verdict === "ok"));
  function fleetSummary(name, replies) {
    const n = replies.length, ok = replies.filter(fleetOk).length, aircraft = replies.reduce((t, r) => t + (r && r.ok === true ? Number(r.rows) || 0 : 0), 0);
    return `${name} · fleets ${ok === n ? plural(n, "page", "pages") : `${ok} of ${n} pages`} ok, ${plural(aircraft, "aircraft", "aircraft")}`;
  }
  function fleetWords(name, i, n, r) {
    const head = `${name}: fleet ${i} of ${n}`;
    if (!r || r.ok !== true) return `${head} · didn't read (${(r && (r.error || r.message)) || "no answer"})`;
    const v = r.verdict && r.verdict.note;
    return `${head} · ${v || plural(Number(r.rows) || 0, "aircraft", "aircraft")}`;
  }

  const lib = { LETTERS, PACE, MAX_FAILED_SHARE, letterUrl, airlineUrl, airportUrl, overviewUrl, unescape, text, readLetterPage, addAirlines, airlineList,
                readSchedulePage, airlinePayload, readAirportPage, airportPayload, readOverviewPage, fleetScanPayload, finishPayload, tooManyFailed, isoWeek, planOf, noScanWords,
                progressWords, VERSION, FLEET_PACE, fleetListUrl, fleetUrl, readFleetPage, fleetsToRead, fleetPayload, fleetProgress, fleetWords,
                fleetOk, fleetSummary };
  if (typeof document === "undefined" || !root.location || !root.sessionStorage) { root.eqScan = lib; return; }

  // ---------------------------------------------------------------- in the game: the capture, as in 1.4, and the fleets (1.6)
  const KEY = "__CAPTURE_KEY__", ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZWN3c3llZHZ3Y3hnZHptaG9xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMTg5MzcsImV4cCI6MjEwNTc5NDkzN30.tC56dOgmPeYB3m58aDy4ADnnaZ3613P6MFp2pVXUj_Y", RPC = "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/";
  // the airlines to capture come from the database (capture_airlines, with the key), as [game ID, name, the game's name]
  const airlinesOf = s => (s && s.airlines) || [];
  const ST = "eq_capture_all"; const get = () => { try { return JSON.parse(sessionStorage.getItem(ST) || "null"); } catch (e) { return null; } }; const set = s => sessionStorage.setItem(ST, JSON.stringify(s)); const clear = () => sessionStorage.removeItem(ST);
  const cells = tr => [...tr.querySelectorAll("td,th")].map(td => td.textContent.replace(/\s+/g, " ").trim());
  const rowsOf = doc => [...doc.querySelectorAll("table tr")].map(cells).filter(r => r.some(x => x));
  const fetchDoc = async url => { const r = await fetch(url, { credentials: "include" }); if (!r.ok) throw new Error(url + " " + r.status); return new DOMParser().parseFromString(await r.text(), "text/html"); };
  const rpc = async (fn, body) => { const r = await fetch(RPC + fn, { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" }, body: JSON.stringify(body) }); return r.json(); };
  // a page the database didn't store and read counts as a failed capture: no world scan that evening (1.5)
  const failed = () => { const t = get(); if (t) { t.failed = (t.failed || 0) + 1; set(t); } };
  const send = async (gameId, kind, rows, page) => { const r = await rpc("capture_ingest", { p_key: KEY, p_airline: String(gameId), p_kind: kind, p_page: page, p_rows: rows }); if (!r || r.ok !== true) failed(); return r; };   // the airline by its game ID
  const loadAirlines = async () => { const r = await rpc("capture_airlines", { p_key: KEY }); if (!r || !r.ok || !Array.isArray(r.airlines) || !r.airlines.length) throw new Error((r && (r.error || r.message)) || "no airlines"); return { list: r.airlines.map(a => [a.game_id, a.name, a.game_name || a.name]), scan: planOf(r) }; };
  // the panel: its lines, the live progress line under them, and a Stop button while the world scan runs. Since 1.7 it
  // never grows past the window: its lines scroll, and follow the newest one unless Gitesh has scrolled up to read
  const panel = () => { let b = document.getElementById("eq-cap-panel"); if (!b) { b = document.createElement("div"); b.id = "eq-cap-panel"; b.style.cssText = "position:fixed;top:12px;right:12px;z-index:999999;background:#0A1230;color:#fff;font:14px/1.5 system-ui,sans-serif;padding:14px 18px;border-radius:14px;box-shadow:0 20px 50px rgba(0,0,0,.4);max-width:380px;max-height:calc(100vh - 24px);box-sizing:border-box;display:flex;flex-direction:column;white-space:pre-line"; const t = document.createElement("div"); t.className = "eq-cap-text"; t.style.cssText = "overflow-y:auto;flex:1 1 auto;min-height:0;overscroll-behavior:contain"; const k = document.createElement("div"); k.className = "eq-cap-buttons"; k.style.cssText = "margin-top:10px;display:flex;gap:8px"; b.append(t, k); document.body.appendChild(b); } return b; };
  const show = t => { const e = panel().querySelector(".eq-cap-text"), end = e.scrollHeight - e.scrollTop - e.clientHeight < 40; e.textContent = t; if (end) e.scrollTop = e.scrollHeight; };   // 1.7: follows the newest line unless scrolled up
  const lines = s => (s.log || []).join("\n") + (s.progress ? "\n" + s.progress : "");
  const log = t => { const s = get(); if (s) { s.log = (s.log || []).concat(t).slice(-40); set(s); } show(get() ? lines(get()) : t); };
  const buttons = list => { const k = panel().querySelector(".eq-cap-buttons"); k.textContent = ""; for (const [label, fn] of list) { const x = document.createElement("button"); x.textContent = label; x.style.cssText = "border:0;border-radius:999px;padding:7px 14px;font:700 13px system-ui,sans-serif;cursor:pointer;background:#F6B44B;color:#0A1230"; x.onclick = e => { e.stopPropagation(); fn(); }; k.appendChild(x); } };
  const closable = () => { buttons([]); panel().onclick = () => { panel().remove(); clear(); }; };
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
    await captureFleets(id, name);   // 1.6: then its fleets
  }
  // 1.6 (spec docs/specs/2026-10-22-fleet-capture.md §1): the airline's fleet list, then each fleet with aircraft, one
  // page at a time at FLEET_PACE, each sent as page kind fleet. A page that doesn't read is still sent, with its error, so
  // the database judges it broken (#21). The fleet pages don't hold back the world scan: the evening's other pages decide
  // that, as in 1.5.
  const sendFleet = async (gameId, rows, url) => { try { return await rpc("capture_ingest", { p_key: KEY, p_airline: String(gameId), p_kind: "fleet", p_page: url, p_rows: rows }); } catch (e) { return { ok: false, error: e.message }; } };
  const progress = t => { const s = get(); if (s) { s.progress = t; set(s); show(lines(s)); } };
  async function captureFleets(id, name) {
    const run = new Date().toISOString();
    let listHtml = null, list = null, why = null;
    try { listHtml = await page(fleetListUrl); list = readFleetPage(listHtml); if (list.error && !list.fleets.length) why = list.error; }
    catch (e) { why = e.message; }
    if (why) { const r = await sendFleet(id, fleetPayload(run, 1, 1, null, [], null, "the fleet list didn't read: " + why), fleetListUrl); log(fleetWords(name, 1, 1, r)); return; }
    const todo = fleetsToRead(list.fleets);
    if (!todo.length) { log(name + " · fleets: no aircraft in any fleet"); return; }
    const replies = [];
    for (let i = 0; i < todo.length; i++) {
      const f = todo[i], url = fleetUrl(f.id);
      progress(fleetProgress(name, i + 1, todo.length));
      let read = null, err = null;
      if (f.id != null) await sleep(FLEET_PACE);   // the scan's pace between the game's pages
      try { read = f.id == null ? list : readFleetPage(await page(url)); } catch (e) { err = e.message; }
      const r = await sendFleet(id, fleetPayload(run, i + 1, todo.length, f, list.fleets, read, err), url);
      replies.push(r);
      if (!fleetOk(r)) log(fleetWords(name, i + 1, todo.length, r));
    }
    progress(null); log(fleetSummary(name, replies));
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
    if (s.phase === "capture" && onLoads()) { try { await captureCurrent(id, name); } catch (e) { log(name + " · problem: " + e.message); failed(); }
      nextAirline(); return; }
    if (s.phase === "home") { log("Done: all " + airlinesOf(s).length + " airlines captured. Back on the airline you started with.");
      const why = noScanWords(s.scan, get().failed || 0);   // 1.5: then the world scan, when one is due
      if (why) { log(why); closable(); clear(); return; }
      const t = get(); t.phase = "scan"; t.sc = { step: "start", li: 0, byId: {}, list: [], ai: 0, apid: {}, airports: t.scan.airports, pi: 0, failedAirlines: 0, failedAirports: 0, noId: 0, fleetPages: 0, fleetFailed: 0 }; set(t);
      log(`World scan: due${t.scan.latest ? ` (the last finished ${when(t.scan.latest.taken_at)})` : ""}. About 5 minutes; keep this tab open. Stop is below.`);
      return scan(); }
    if (s.phase === "scan") return scan();
  }

  // ---------------------------------------------------------------- in the game: the world scan (1.5)
  let stopping = false;
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const save = sc => { const t = get(); if (!t) return null; if (t.sc && t.sc.stop) sc.stop = true; t.sc = sc; t.progress = progressWords(sc); set(t); show(lines(t)); return t; };
  // a game page as text, as gfetch.py gets it: a failed page throws
  async function page(url) {
    const c = new AbortController(), timer = setTimeout(() => c.abort(), PAGE_TIMEOUT_MS);
    try { const r = await fetch(url, { credentials: "include", signal: c.signal }); if (!r.ok) throw new Error("HTTP " + r.status); return await r.text(); }
    finally { clearTimeout(timer); }
  }
  // capture_scan(), tried three times 3 seconds apart when the call itself fails, as gscan.py's rpc() does
  async function scanSend(kind, payload) {
    let last = null;
    for (let a = 0; a < 3; a++) {
      try { const r = await fetch(RPC + "capture_scan", { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" }, body: JSON.stringify({ p_key: KEY, p_kind: kind, p_payload: payload }) });
        const body = await r.json().catch(() => null); if (r.ok) return body || { ok: false, error: "no answer" }; last = body || { ok: false, error: "HTTP " + r.status }; }
      catch (e) { last = { ok: false, error: e.message }; }
      if (a < 2) await sleep(3000);
    }
    return last;
  }
  const errorOf = r => (r && (r.error || r.message)) || "no answer";
  // the scan's end: finished or not, the panel says so and the run is over
  function end(words) { const t = get(); if (t) { t.progress = null; set(t); } log(words); closable(); clear(); }
  const stopButton = () => buttons([["Stop", () => { stopping = true; const t = get(); if (t && t.sc) { t.sc.stop = true; set(t); } show((get() ? lines(get()) : "") + "\nStopping after this page…"); }]]);
  const stopped = sc => stopping || sc.stop;
  const stopWords = sc => `World scan stopped (${progressWords(sc).replace(/^World scan: |…$/g, "")}). Not finished, so the Systems board keeps the last finished scan; the next evening's capture scans again while it's due.`;

  async function scan() {
    let t = get(); if (!t || !t.sc) return;
    const sc = t.sc; stopButton(); show(lines(t));
    if (sc.step === "start") {
      if (t.scan.open) { sc.id = t.scan.open; log(`World scan: carrying on with scan ${sc.id}, started within the hour.`); }
      else {
        const r = await scanSend("start", { week: isoWeek(new Date()), note: "Capture all airlines " + VERSION });
        if (!r || r.ok !== true) return end("World scan: couldn't start (" + errorOf(r) + "). Check the capture key; gscan.py by hand if the scan gets old.");
        sc.id = Number(r.snapshot_id); if (r.carried_on) log(`World scan: carrying on with scan ${sc.id}, started within the hour.`);
      }
      sc.step = "letters"; save(sc);
    }
    // 1. the airline list, 26 letter pages
    while (sc.step === "letters" && sc.li < LETTERS.length) {
      if (stopped(sc)) return end(stopWords(sc));
      try { sc.byId = addAirlines(sc.byId, readLetterPage(await page(letterUrl(LETTERS[sc.li])))); }
      catch (e) { log(`World scan: letter ${LETTERS[sc.li]} failed (${e.message}); skipped`); }
      sc.li++; save(sc); await sleep(PACE.letter);
    }
    if (sc.step === "letters") { sc.list = airlineList(sc.byId); sc.byId = {}; sc.step = "airlines"; save(sc); }
    // 2. each airline's schedule
    while (sc.step === "airlines" && sc.ai < sc.list.length) {
      if (stopped(sc)) return end(stopWords(sc));
      const [id, name] = sc.list[sc.ai];
      try {
        const read = readSchedulePage(await page(airlineUrl(id)));
        Object.assign(sc.apid, read.airports);
        const r = await scanSend("airline", airlinePayload(sc.id, id, name, read.flights));
        if (!r || r.ok !== true) throw new Error("not stored: " + errorOf(r));
      } catch (e) { sc.failedAirlines++; log(`World scan: ${name} (${id}) failed (${e.message}); skipped`); }
      // 1.8: then its overview page (its fleet and aircraft on order), flying or not; a failure is logged and skipped and
      // never counts towards the 10% that leave the scan unfinished
      await sleep(PACE.fleet);
      let read = null, err = null;
      try { read = readOverviewPage(await page(overviewUrl(id))); } catch (e) { err = e.message; }
      const fr = await scanSend("fleet", fleetScanPayload(sc.id, id, name, read, err));
      sc.fleetPages = (sc.fleetPages || 0) + 1;
      if (!fr || fr.ok !== true || err || (read && read.error)) {
        sc.fleetFailed = (sc.fleetFailed || 0) + 1;
        log(`World scan: ${name} (${id}) fleet page failed (${err || (read && read.error) || "not stored: " + errorOf(fr)}); skipped`);
      }
      sc.ai++; save(sc); await sleep(PACE.airline);
    }
    if (sc.step === "airlines") {
      if (tooManyFailed(sc.failedAirlines, sc.list.length))
        return end(sc.list.length ? `World scan not finished: ${sc.failedAirlines} of ${sc.list.length} airline pages failed, more than 10%. The Systems board keeps the last finished scan; capture again later, or run gscan.py by hand if it gets old.`
                                  : "World scan not finished: the airline list had no airlines (the letter pages failed). The Systems board keeps the last finished scan.");
      sc.step = "airports"; save(sc);
    }
    // 3. the airport pages capture_airlines() listed, each by the id the schedules gave it
    while (sc.step === "airports" && sc.pi < sc.airports.length) {
      if (stopped(sc)) return end(stopWords(sc));
      const code = sc.airports[sc.pi], aid = sc.apid[code];
      if (!aid) { sc.noId++; sc.pi++; save(sc); continue; }
      try {
        const r = await scanSend("airport", airportPayload(sc.id, code, aid, readAirportPage(await page(airportUrl(aid)))));
        if (!r || r.ok !== true) throw new Error("not stored: " + errorOf(r));
      } catch (e) { sc.failedAirports++; log(`World scan: airport ${code} failed (${e.message}); skipped`); }
      sc.pi++; save(sc); await sleep(PACE.airport);
    }
    // 4. finish: the database builds the scan's airport summaries, and the Systems board goes green
    const r = await scanSend("finish", finishPayload(sc.id, sc.list.length, sc.airports.length, sc.failedAirlines, sc.noId, sc.fleetPages || 0, sc.fleetFailed || 0));
    if (!r || r.ok !== true) return end("World scan: every page read, but finishing it failed (" + errorOf(r) + "). The Systems board keeps the last finished scan; the next evening's capture scans again.");
    end(`World scan done: ${sc.list.length} airlines (${plural(sc.failedAirlines, "page", "pages")} failed), ${sc.airports.length - sc.noId - sc.failedAirports} of ${sc.airports.length} airports read; ${plural(sc.fleetPages || 0, "fleet page", "fleet pages")}, ${sc.fleetFailed || 0} failed.`);
  }

  function addButton() {
    if (document.getElementById("eq-cap-btn")) return; const b = document.createElement("button"); b.id = "eq-cap-btn"; b.textContent = "Capture all airlines"; b.style.cssText = "position:fixed;bottom:16px;right:16px;z-index:999998;background:#F6B44B;color:#0A1230;border:0;border-radius:999px;padding:10px 16px;font:700 13px system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.35);cursor:pointer";
    b.onclick = async () => { b.disabled = true; let got;
      try { got = await loadAirlines(); } catch (e) { show("equinox. capture: couldn't get the airlines to capture (" + e.message + "). Check the capture key."); b.disabled = false; return; }
      const list = got.list, start = (await currentId(list)) || list[0][0];
      set({ i: 0, phase: "switch", start, airlines: list, scan: got.scan, failed: 0, log: ["equinox. capture, all airlines…"] }); log("Starting: " + list.map(a => a[1]).join(", ")); step(); };
    document.body.appendChild(b);
  }
  addButton(); const s = get(); if (s) { show(lines(s)); setTimeout(step, 800); }
})(typeof window !== "undefined" ? window : globalThis);
