// ==UserScript==
// @name         equinox. capture all airlines
// @namespace    equinox
// @version      1.10
// @description  One button: for each of the world's airlines (the database lists them), captures loads, finances and payments for the planner, then the airline's fleet pages (each aircraft's condition, maintenance, seats and pilots). Then, when a world scan is due (the setting scan_every_days), scans the world as scripts/scanner/gscan.py does: every airline's schedule and overview page (its fleet and aircraft on order) and the airport pages, sent with the capture key. Then, once a week (the setting market_every_days), reads the Market Analysis page of both directions of every pair our airlines fly, airline by airline, and sends only the figures (rivals' fares by class, market shares, weekly seats and prices); it sets the page's listing filters if they differ and never sends the page's Pricing or settings forms. Keep the tab open; a scan evening takes about 5 minutes longer, a market evening 10 to 15 more. Salaries are a separate script (salary_adjust.user.js), run by hand on one airline.
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
// pages, the second reads a saved fleet page. Since 1.9 (spec docs/specs/2026-10-30-market-pages.md) the evening ends,
// when capture_airlines() says they're due and no capture page failed, with the market pages: for each of our airlines
// (switching to it first, as the fares userscript does, and checking the page shows it open) the Market Analysis page of
// both directions of each pair it flies, read by fetch half a second apart and sent as figures to capture_market()
// (start, page, finish). When the page's listing filters differ from the saved setup it sets them through their own four
// listing calls, the only posts it makes to the game; it never sends the Pricing or settings forms.
// tests/capture_market_test.mjs reads the saved page (tests/fixtures/market_DUBAMS_2026-10-30.html) and runs whole runs
// against a stand-in for the game. Since 1.10 (the first live run, 30 Oct: every page of the four airlines whose Group by
// flight was off failed as "no Current Availability table", because the game then shows its flat list and the page was
// judged before its filters were set) each page is checked in this order: the airline open (on the first page after a
// switch, and on any page without its table), the filters (set when they differ), then the page read; a page that still
// doesn't read says what the game served (title, heading, address, the airline open, Group by flight). Our own flights
// alone are a normal page (tests/fixtures/market_DELBOM_2026-10-30.html, Kingfisher). The service code sent is the
// profile's leading token ("S2 (min 800km)" → "S2"), as the planner writes it.
(function (root) {
  "use strict";

  // ---------------------------------------------------------------- the world scan's logic, without the page
  const VERSION = "1.10";                                      // the @version above, in the scan's notes
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

  // ---------------------------------------------------------------- the market pages' logic, without the page (1.9)
  // Spec docs/specs/2026-10-30-market-pages.md: once a week (settings.market_every_days), after the world scan, the
  // Market Analysis page (/app/com/markets/<FROM><TO>) for both directions of every pair our airlines fly, read in the
  // browser; only the figures go to capture_market(). The page belongs to the airline that is open, so the pairs come
  // grouped by airline and the capture switches airline before each group. The game keeps the listing's filters between
  // visits: when one differs from the saved setup the capture sets it through that filter's own listing call (the only
  // posts it ever makes to the game; the page's Pricing and settings forms change our fares and are never sent), reads
  // the page again and stops only if a filter still differs. tests/capture_market_test.mjs reads the saved page with
  // these and runs whole runs against a stand-in for the game.
  const MARKET_PACE = 500;                                     // ms between market pages (and between filter calls)
  const marketUrl = (from, to) => "/app/com/markets/" + from + to;
  const FILTER = "pair:pair-panel:listing:filters:";           // the listing filters' field names start so
  const FILTER_CALLS = ["serviceClasses", "flightStati", "ignoreCarriers", "display"];
  const FILTER_LABEL = { serviceClasses: "Service classes", flightStati: "Flight status", ignoreCarriers: "Settings", display: "Settings" };
  // the setup on the saved page: every class and every status ticked, Ignore own flights off, Group by flight on
  const FILTER_WANT = { serviceClasses: true, flightStati: true, ignoreCarriers: false, display: true };
  const attrOf = (tag, name) => { const m = String(tag).match(new RegExp("\\b" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", "i")); return m ? unescape(m[1] ?? m[2]) : null; };
  // the listing's filters as the page's markup ticks them: each checkbox of the two groups (its value, its label and
  // whether it is ticked), and the two settings (ticked or not; null when the page has no such box)
  function readMarketFilters(html) {
    html = String(html);
    const out = { serviceClasses: [], flightStati: [], ignoreCarriers: null, display: null };
    for (const m of html.matchAll(/<input\b[^>]*>([^<]*)/gi)) {
      const tag = m[0].slice(0, m[0].indexOf(">") + 1), name = attrOf(tag, "name");
      if (!name || !name.startsWith(FILTER) || !/type\s*=\s*["']checkbox/i.test(tag)) continue;
      const which = name.slice(FILTER.length), checked = /\bchecked\b/i.test(tag);
      if (which === "serviceClasses" || which === "flightStati") out[which].push({ value: attrOf(tag, "value"), label: text(m[1]), checked });
      else if (which === "ignoreCarriers" || which === "display") out[which] = checked;
    }
    return out;
  }
  // how the filters differ from the setup: one entry per box, { filter, label, where, want }; a filter missing from the
  // page is a difference too (want "on the page")
  function filterProblems(f) {
    const out = [];
    for (const g of ["serviceClasses", "flightStati"]) {
      if (!f || !f[g] || !f[g].length) { out.push({ filter: g, label: null, where: FILTER_LABEL[g], want: "on the page" }); continue; }
      for (const b of f[g]) if (!b.checked) out.push({ filter: g, label: b.label, where: FILTER_LABEL[g], want: true });
    }
    for (const k of ["ignoreCarriers", "display"]) {
      const have = f ? f[k] : null, label = k === "display" ? "Group by flight" : "Ignore own flights";
      if (have === null || have === undefined) out.push({ filter: k, label, where: FILTER_LABEL[k], want: "on the page" });
      else if (have !== FILTER_WANT[k]) out.push({ filter: k, label, where: FILTER_LABEL[k], want: FILTER_WANT[k] });
    }
    return out;
  }
  const filterWords = p => p.want === "on the page" ? `${p.label ? `'${p.label}'` : "the boxes"} under ${p.where} isn't on the page`
    : `${p.want ? "tick" : "untick"} '${p.label}' under ${p.where}`;
  // the four listing calls, as the page's load script names them ("u":"./DUBAMS?11-1.0-pair-pair~panel-listing-filters-
  // display"), made absolute against the page's own address; nothing else on the page is ever an address to post to
  function filterCalls(html, pageUrl) {
    const out = {};
    for (const m of String(html).matchAll(/"u"\s*:\s*"([^"]*-pair-pair~panel-listing-filters-(serviceClasses|flightStati|ignoreCarriers|display))"/g)) {
      try { out[m[2]] = new URL(m[1], new URL(pageUrl, "https://gander.airlinesim.aero/")).href; } catch (e) { /* not an address */ }
    }
    return out;
  }
  // true only for one of the four listing calls of a market page: the one check every post to the game goes through
  function isFilterCall(url) {
    let u; try { u = new URL(url, "https://gander.airlinesim.aero/"); } catch (e) { return false; }
    return /^\/app\/com\/markets\/[A-Z0-9]{6}$/.test(u.pathname)
      && /^\?\d+-\d+\.\d+-pair-pair~panel-listing-filters-(serviceClasses|flightStati|ignoreCarriers|display)$/.test(u.search);
  }
  // the body a filter's call sends to set it as the setup wants, as the page's own Wicket call would serialise it: a
  // group's every box ticked; Group by flight ticked ("on"); Ignore own flights unticked (no field at all)
  function filterBody(filter, f) {
    const e = encodeURIComponent;
    if (filter === "serviceClasses" || filter === "flightStati") return (f && f[filter] ? f[filter] : []).map(b => e(FILTER + filter) + "=" + e(b.value)).join("&");
    if (filter === "display") return e(FILTER + "display") + "=on";
    if (filter === "ignoreCarriers") return "";
    throw new Error("not a listing filter: " + filter);
  }
  // the page's Wicket base address (Wicket.Ajax.baseUrl="com/markets/DUBAMS?11"), sent with each call as the page would
  const wicketBase = html => { const m = String(html).match(/Wicket\.Ajax\.baseUrl\s*=\s*"([^"]*)"/); return m ? m[1] : null; };
  // which airline the page has open: the game's settings (fixedEnterpriseId) and the name in the main menu
  function openAirlineOf(html) {
    html = String(html);
    const id = html.match(/"fixedEnterpriseId"\s*:\s*(\d+)/), name = html.match(/<a class="name"[^>]*>\s*<span>([^<]*)<\/span>/);
    return { id: id ? Number(id[1]) : null, name: name ? text(name[1]) : null };
  }
  // is the airline that's open the one we switched to? null when it is, else why not
  function openProblem(open, al) {
    if (open && open.id != null) return open.id === Number(al.game_id) ? null : `the game has airline ${open.id}${open.name ? ` (${open.name})` : ""} open, not ${al.name} (${al.game_id})`;
    if (open && open.name) return [al.name, al.game_name].filter(Boolean).some(n => open.name === n) ? null : `the game has ${open.name} open, not ${al.name} (${al.game_id})`;
    return "the page doesn't say which airline is open";
  }
  const price = s => { const m = String(s).replace(/,/g, "").match(/-?\d+(?:\.\d+)?/); return m ? Number(m[0]) : null; };
  const utcOf = title => { const m = String(title || "").match(/^\s*([\d:-]+)\s+UTC/); return m ? m[1] : null; };
  // one Market Analysis page: the pair, the filters, Current Availability (each flight: its number, prefix, aircraft,
  // date and times in UTC, status, and per class its seats left and price), Market Shares (the week, the previous week's
  // label, each enterprise's share and change in points, passengers and cargo), our service profile on the pair (the
  // settings form's On-Board Service, read only) and the historic weeks (capacities and prices with figures). An error
  // when the page has no Current Availability table (not a market page, or the session lost).
  function readMarketPage(html) {
    html = String(html);
    const h2 = html.match(/<h2>\s*<span>\s*<span>[^<]*<\/span>\s*\(<a[^>]*>([A-Z0-9]{3})<\/a>\)\s*<\/span>\s*-\s*<span>\s*<span>[^<]*<\/span>\s*\(<a[^>]*>([A-Z0-9]{3})<\/a>\)/);
    const filters = readMarketFilters(html);
    const tm = html.match(/<table[^>]*id="inventory-grouped-table"[^>]*>([\s\S]*?)<\/table>/);
    if (!tm) return { from: h2 ? h2[1] : null, to: h2 ? h2[2] : null, filters, error: "no Current Availability table on the page" };
    const flights = [];
    for (const b of tm[1].matchAll(/<tbody[^>]*>([\s\S]*?)<\/tbody>/g)) {
      const rows = b[1].match(/<tr[\s\S]*?<\/tr>/g) || [];
      if (!rows.length) continue;
      const first = [...rows[0].matchAll(/<td([^>]*)>([\s\S]*?)<\/td>/g)];
      if (first.length < 7) continue;
      const cell0 = first[0][2], flight = text(cell0.split(/<div/)[0]), pm = flight.match(/^([A-Z0-9]{2,3})\s+(\d{1,5}[A-Z]?)$/);
      const types = [...cell0.matchAll(/aircraftsType\?id=\d+"[^>]*>([^<]*)</g)];
      const statusCell = first.find(c => /flightStatusPanel/.test(c[1]));
      const f = { flight, code: pm ? pm[1] : null, aircraft: types.length ? text(types[types.length - 1][1]) : null,
                  date: utcOf(attrOf("<x" + first[1][1] + ">", "title")), dep: utcOf(attrOf("<x" + first[2][1] + ">", "title")),
                  arr: utcOf(attrOf("<x" + first[3][1] + ">", "title")), status: statusCell ? text(statusCell[2]) : null, classes: [] };
      for (const [i, row] of rows.entries()) {
        // the first row starts with the flight, date and two times (they span the flight's rows); then class, seats, price
        const c = [...row.matchAll(/<td([^>]*)>([\s\S]*?)<\/td>/g)].slice(i === 0 ? 4 : 0);
        if (c.length < 3) continue;
        const cls = text(c[0][2]);
        if (!/^(Y|C|F|Cargo)$/.test(cls)) continue;
        f.classes.push({ cls, seats: price(text(c[1][2])), price: price(text(c[2][2])) });
      }
      flights.push(f);
    }
    // Market Shares: the week shown, the previous week's link, and the two tables
    const ps = html.match(/<div class="row periodSelection">([\s\S]*?)<\/div>\s*<\/div>/);
    const lab = cls => { const m = ps && ps[1].match(new RegExp('class="[^"]*\\b' + cls + '\\b[^"]*"[^>]*>([\\s\\S]*?)</div>')); const t = m ? text(m[1]) : ""; return /^\d{1,2}\/\d{4}$/.test(t) ? t : null; };
    const shareTable = h => {
      const m = html.match(new RegExp("<h4>\\s*" + h + "\\s*</h4>[\\s\\S]*?<tbody[^>]*>([\\s\\S]*?)</tbody>"));
      const out = [];
      for (const row of (m ? m[1] : "").match(/<tr[\s\S]*?<\/tr>/g) || []) {
        const e = row.match(/href="[^"]*info\/enterprises\/(\d+)"[^>]*>([\s\S]*?)<\/a>/);
        if (!e) continue;
        const nums = [...row.matchAll(/<td class="number">([\s\S]*?)<\/td>/g)].map(x => x[1]);
        const ch = nums.length > 1 ? nums[1].match(/<span>\s*([+-]?\d+(?:\.\d+)?)\s*<\/span>/) : null;
        out.push({ enterprise_id: Number(e[1]), name: text(e[2]), share: nums.length ? price(text(nums[0])) : null, change: ch ? Number(ch[1]) : null });
      }
      return out;
    };
    // our service profile on the pair: the settings form's On-Board Service, the option selected (read only)
    const sp = html.match(/<select\b[^>]*name="serviceProfile-group:[^"]*:serviceProfile"[^>]*>([\s\S]*?)<\/select>/);
    const opt = sp ? [...sp[1].matchAll(/<option\b([^>]*)>([\s\S]*?)<\/option>/g)].find(o => /\bselected\b/i.test(o[1])) : null;
    const spValue = opt ? attrOf("<x" + opt[1] + ">", "value") : null;
    // 1.10: the code is the option's leading token: the game names its profiles "S2 (min 800km)", the planner "S2"
    const service = opt && spValue && /^\d+$/.test(spValue) ? { code: serviceToken(text(opt[2])), game_id: Number(spValue) } : null;
    // Historic Capacities and Prices: the two setData([...]) calls, joined by period; weeks with figures only
    const series = {};
    for (const m of html.matchAll(/\.setData\((\[[\s\S]*?\])\);/g)) {
      let rows; try { rows = JSON.parse(m[1]); } catch (e) { continue; }
      for (const r of rows) if (r && /^\d{6}$/.test(String(r.period))) {
        const s = series[r.period] || (series[r.period] = { period: Number(r.period), seats: null, price: null });
        if ("capacities" in r) s.seats = Number(r.capacities); if ("prices" in r) s.price = Number(r.prices);
      }
    }
    const weeks = Object.values(series).filter(w => (w.seats || 0) !== 0 || (w.price || 0) !== 0).sort((a, b) => a.period - b.period)
      .map(w => ({ week: String(w.period).slice(0, 4) + "-" + String(w.period).slice(4), seats: w.seats, price: w.price }));
    return { from: h2 ? h2[1] : null, to: h2 ? h2[2] : null, filters, flights,
             shares: { week: lab("current"), previous: lab("previous"), passengers: shareTable("Passengers"), cargo: shareTable("Cargo") },
             service, weeks };
  }
  // 1.10: a service profile's code as the planner writes it: the name's leading token before " (" ("S2 (min 800km)" → "S2")
  const serviceToken = name => { const t = String(name || "").split(" (")[0].trim(); return t || null; };
  // 1.10: whether the page has the grouped Current Availability table (Group by flight on)
  const hasGroupedTable = html => /<table[^>]*id="inventory-grouped-table"/.test(String(html));
  // 1.10: what a page that didn't read was, for its error: the title, the first heading after the menus, the address it
  // came from (without the game's host), the airline open and the Group by flight box
  function pageWhat(html, url) {
    html = String(html);
    const t = html.match(/<title>([\s\S]*?)<\/title>/), body = html.slice(Math.max(0, html.search(/<div class="bootstrap container-fluid">/)));
    const hd = body.match(/<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/), o = openAirlineOf(html), f = readMarketFilters(html);
    let at = String(url || ""); try { const u = new URL(at, "https://gander.airlinesim.aero/"); at = u.pathname + u.search; } catch (e) { /* as given */ }
    return [`title "${t ? text(t[1]) : ""}"`, `heading "${hd ? text(hd[1]).slice(0, 80) : ""}"`, `at ${at}`,
            `open ${o.id != null ? o.id : "?"}${o.name ? " " + o.name : ""}`,
            `Group by flight ${f.display === true ? "on" : f.display === false ? "off" : "not on the page"}`,
            /listing-flat~view/.test(html) && !hasGroupedTable(html) ? "the flat list shown" : null].filter(Boolean).join(", ");
  }
  // the fares as the database keeps them: per flight prefix and class, flights seen, lowest, average and highest price,
  // flights finished and finished with no seat left (sold out); nothing per flight
  function fareSummary(flights) {
    const by = new Map();
    for (const f of flights || []) for (const c of f.classes || []) {
      const code = f.code || f.flight, k = code + "|" + c.cls;
      if (!by.has(k)) by.set(k, { code, cls: c.cls, flights: 0, prices: [], finished: 0, sold_out: 0 });
      const x = by.get(k); x.flights++;
      if (c.price != null) x.prices.push(c.price);
      if (f.status === "finished") { x.finished++; if (c.seats === 0) x.sold_out++; }
    }
    return [...by.values()].map(x => ({ code: x.code, cls: x.cls, flights: x.flights, low: x.prices.length ? Math.min(...x.prices) : null,
      avg: x.prices.length ? Math.round(x.prices.reduce((a, b) => a + b, 0) / x.prices.length * 100) / 100 : null,
      high: x.prices.length ? Math.max(...x.prices) : null, finished: x.finished, sold_out: x.sold_out }));
  }
  const weekLabel = s => { const m = String(s || "").match(/^(\d{1,2})\/(\d{4})$/); return m ? m[2] + "-" + m[1].padStart(2, "0") : null; };
  // what capture_market() takes for a page: the figures only, never the HTML; with error instead when it didn't read
  function marketPagePayload(runId, al, from, to, read, error) {
    const base = { run_id: runId, airline: Number(al.game_id), origin: from, dest: to };
    const err = error || (read && read.error) || (!read ? "nothing read" : null);
    if (err) return { ...base, ok: false, error: String(err) };
    const sh = read.shares || {};
    return { ...base, ok: true, week: weekLabel(sh.week), previous_week: weekLabel(sh.previous),
             service: read.service || null, fares: fareSummary(read.flights),
             shares: [...(sh.passengers || []).map(s => ({ kind: "passengers", ...s })), ...(sh.cargo || []).map(s => ({ kind: "cargo", ...s }))],
             weeks: read.weeks || [] };
  }
  // capture_airlines()'s market pages, as the capture needs them
  const marketPlanOf = r => ({ due: !!(r && r.market_due === true), open: r && r.market_open != null ? Number(r.market_open) : null,
    every: r && r.market_every_days != null ? Number(r.market_every_days) : null, latest: (r && r.market_latest) || null,
    total: r && r.market_total != null ? Number(r.market_total) : 0, done: r && r.market_done != null ? Number(r.market_done) : 0,
    airlines: (r && Array.isArray(r.market_pages) ? r.market_pages : []).map(a => ({ game_id: Number(a.game_id), code: a.code || null, name: a.name || String(a.game_id),
      game_name: a.game_name || null, pages: (Array.isArray(a.pages) ? a.pages : []).filter(p => Array.isArray(p) && /^[A-Z0-9]{3}$/.test(p[0]) && /^[A-Z0-9]{3}$/.test(p[1])) })) });
  // why there are no market pages tonight, or null when they run
  function noMarketWords(plan, failed, stopped) {
    if (!plan || plan.every == null) return "Market pages: off (the world has no market_every_days setting).";
    if (plan.every <= 0) return "Market pages: off (market_every_days is 0).";
    if (!plan.due) return `Market pages: not due${plan.latest ? `; the last finished ${when(plan.latest.finished_at)}` : ""} (every ${plural(plan.every, "day", "days")}).`;
    if (stopped) return "Market pages: not tonight, because Stop was pressed.";
    if (failed) return `Market pages: not tonight, because ${plural(failed, "capture page", "capture pages")} failed. Capture again; they follow while they're due.`;
    if (!plan.airlines.some(a => a.pages.length)) return "Market pages: none left to read.";
    return null;
  }
  const marketProgress = (done, total, name) => `Market pages: ${done} of ${total}${name ? ` (${name})` : ""}…`;
  const pairWords = (from, to) => `${from}→${to}`;

  // One market run, start to end, from wherever its state says (a reload after switching airline carries on). io is the
  // outside world: get(url) and post(url, body, base) answer { ok, status, url, html } (post goes to the game, and is
  // refused here unless it is one of the four listing calls), sleep(ms), send(kind, payload) is capture_market(),
  // switchTo(game id) opens that airline (in the game it leaves the page and answers "away"), save(state), stopped(),
  // log(line) and progress(line). Answers { words } when the run is over, or { away: true } while the page is changing.
  async function runMarkets(st, io) {
    const post = async (url, body, base) => { if (!isFilterCall(url)) throw new Error("refused to post to " + url + ": only the listing's four filters are ever set"); return io.post(url, body, base); };
    const stopWords = () => `Market pages stopped (${st.done} of ${st.total} read). Not finished, so the Systems board keeps the last finished run; the next evening's capture reads them again while they're due.`;
    if (!st.run_id) {
      const r = await io.send("start", { version: VERSION, total: st.total, note: "Capture all airlines " + VERSION });
      if (!r || r.ok !== true) return { words: "Market pages: couldn't start (" + ((r && (r.error || r.message)) || "no answer") + ")." };
      st.run_id = Number(r.run_id); st.carried_on = !!r.carried_on; io.save(st);
      if (r.carried_on) io.log(`Market pages: carrying on with run ${st.run_id}, started within the hour.`);
    }
    while (st.ai < st.airlines.length) {
      const al = st.airlines[st.ai];
      if (st.pi >= al.pages.length) { st.ai++; st.pi = 0; io.save(st); continue; }
      if (st.switched !== al.game_id) {
        if (io.stopped()) return { words: stopWords() };
        st.switched = al.game_id; st.checked = false; io.save(st);
        io.log(`Market pages: switching to ${al.name}…`);
        if ((await io.switchTo(al.game_id)) === "away") return { away: true };
      }
      while (st.pi < al.pages.length) {
        if (io.stopped()) return { words: stopWords() };
        const [from, to] = al.pages[st.pi], url = marketUrl(from, to);
        io.progress(marketProgress(st.done, st.total, al.name));
        if (st.paced) await io.sleep(MARKET_PACE);
        st.paced = true;
        let g, read = null, err = null;
        try { g = await io.get(url); } catch (e) { return { words: `Market pages stopped on ${pairWords(from, to)}: the game didn't answer (${e.message}); the session may have been lost.` }; }
        const path = (() => { try { return new URL(g.url || url, "https://gander.airlinesim.aero/").pathname; } catch (e) { return ""; } })();
        if (g.ok && !path.startsWith("/app/com/markets/")) return { words: `Market pages stopped on ${pairWords(from, to)}: the game sent it to ${path}; the session may have been lost.` };
        if (!g.ok) err = "the game answered HTTP " + g.status;
        else {
          // 1.10: the airline that's open, on the first page after each switch and on any page without its table (a page
          // for another airline is never read as a failed page: the run stops, as spec'd)
          const noTable = !hasGroupedTable(g.html), open = openAirlineOf(g.html);
          if (!st.checked || (noTable && (open.id != null || open.name))) {
            const why = openProblem(open, al);
            if (why) return { words: `Market pages stopped on ${pairWords(from, to)}: ${why}: the switch didn't take.` };
            if (!st.checked) { st.checked = true; io.save(st); }
          }
          // 1.10: then the listing's filters, before the page is read: with Group by flight off the game shows its flat
          // list, which has no grouped table (the first live run, 30 Oct: every page of the four airlines whose Group by
          // flight was off failed as "no Current Availability table", the filter never set)
          let f = readMarketFilters(g.html), probs = filterProblems(f);
          const missing = probs.filter(p => p.want === "on the page").length;   // all four controls missing: not a market page
          if (probs.length && missing < 4) {
            // set each filter that differs through its own listing call, then read the page again
            const calls = filterCalls(g.html, g.url || url), base = wicketBase(g.html);
            for (const name of [...new Set(probs.map(p => p.filter))]) {
              const p = probs.find(x => x.filter === name);
              if (p.want === "on the page" || !calls[name]) return { words: `Market pages: couldn't set ${filterWords(p).replace(/^tick |^untick /, "")} on ${pairWords(from, to)}${calls[name] ? "" : " (its listing call isn't on the page)"}. Stopped.` };
              let r;
              try { r = await post(calls[name], filterBody(name, f), base); } catch (e) { return { words: `Market pages stopped on ${pairWords(from, to)}: setting ${FILTER_LABEL[name]} failed (${e.message}).` }; }
              if (!r || !r.ok) return { words: `Market pages stopped on ${pairWords(from, to)}: setting ${FILTER_LABEL[name]} failed (the game answered HTTP ${r ? r.status : "nothing"}).` };
              for (const q of probs.filter(x => x.filter === name)) io.log(`Market pages: set the filter, ${filterWords(q)} (on ${pairWords(from, to)}).`);
              await io.sleep(MARKET_PACE);
            }
            try { g = await io.get(url); } catch (e) { return { words: `Market pages stopped on ${pairWords(from, to)}: the game didn't answer (${e.message}); the session may have been lost.` }; }
            f = g.ok ? readMarketFilters(g.html) : f;
            probs = g.ok ? filterProblems(f) : probs;
            if (!g.ok || probs.length) {
              const p = probs[0];
              return { words: `Market pages: couldn't set ${p.label ? `'${p.label}'` : "the boxes"} under ${p.where} on ${pairWords(from, to)}. Stopped; set it on the page by hand, then press Capture again.` };
            }
          }
          read = readMarketPage(g.html);
          // 1.10: a page that still doesn't read says what the game served: its title and heading, its address, the
          // airline open and the Group by flight box
          if (read.error) { err = read.error + " (" + pageWhat(g.html, g.url || url) + ")"; read = null; }
        }
        const r = await io.send("page", marketPagePayload(st.run_id, al, from, to, read, err));
        if (err || !r || r.ok !== true) {
          st.failed++;
          io.log(`Market pages: ${al.name} ${pairWords(from, to)} failed (${err || "not stored: " + ((r && (r.error || r.message)) || "no answer")}); skipped`);
        }
        st.done++; st.pi++; io.save(st);
      }
    }
    io.progress(null);
    if (tooManyFailed(st.failed, st.done))
      return { words: st.done ? `Market pages not finished: ${st.failed} of ${st.done} pages failed, more than 10%. The Systems board keeps the last finished run.` : "Market pages: none read." };
    const r = await io.send("finish", { run_id: st.run_id, note: `${plural(st.done, "page", "pages")}, ${st.failed} failed (Capture all airlines ${VERSION})` });
    if (!r || r.ok !== true) return { words: "Market pages: every page read, but finishing the run failed (" + ((r && (r.error || r.message)) || "no answer") + ")." };
    return { words: `Market pages done: ${st.done}, ${st.failed} failed.`, finished: true };
  }
  // a new market run's state, from capture_airlines()'s plan
  const marketState = plan => ({ run_id: plan.open || null, airlines: plan.airlines.filter(a => a.pages.length), ai: 0, pi: 0,
    total: plan.total || plan.airlines.reduce((n, a) => n + a.pages.length, 0), done: plan.done || 0, failed: 0, switched: null, checked: false, paced: false });

  const lib = { LETTERS, PACE, MAX_FAILED_SHARE, letterUrl, airlineUrl, airportUrl, overviewUrl, unescape, text, readLetterPage, addAirlines, airlineList,
                readSchedulePage, airlinePayload, readAirportPage, airportPayload, readOverviewPage, fleetScanPayload, finishPayload, tooManyFailed, isoWeek, planOf, noScanWords,
                progressWords, VERSION, FLEET_PACE, fleetListUrl, fleetUrl, readFleetPage, fleetsToRead, fleetPayload, fleetProgress, fleetWords,
                fleetOk, fleetSummary, MARKET_PACE, marketUrl, FILTER_CALLS, readMarketFilters, filterProblems, filterWords, filterCalls, isFilterCall,
                filterBody, wicketBase, openAirlineOf, openProblem, readMarketPage, fareSummary, marketPagePayload, marketPlanOf, noMarketWords,
                marketProgress, runMarkets, marketState, hasGroupedTable, pageWhat, serviceToken };
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
  const loadAirlines = async () => { const r = await rpc("capture_airlines", { p_key: KEY }); if (!r || !r.ok || !Array.isArray(r.airlines) || !r.airlines.length) throw new Error((r && (r.error || r.message)) || "no airlines"); return { list: r.airlines.map(a => [a.game_id, a.name, a.game_name || a.name]), scan: planOf(r), markets: marketPlanOf(r) }; };   // 1.9: and the market pages
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
      if (why) { log(why); return startMarkets(); }   // 1.9: then the market pages, when they're due
      const t = get(); t.phase = "scan"; t.sc = { step: "start", li: 0, byId: {}, list: [], ai: 0, apid: {}, airports: t.scan.airports, pi: 0, failedAirlines: 0, failedAirports: 0, noId: 0, fleetPages: 0, fleetFailed: 0 }; set(t);
      log(`World scan: due${t.scan.latest ? ` (the last finished ${when(t.scan.latest.taken_at)})` : ""}. About 5 minutes; keep this tab open. Stop is below.`);
      return scan(); }
    if (s.phase === "scan") return scan();
    if (s.phase === "market") return markets();   // 1.9: carried on after switching airline
    if (s.phase === "market_home") { log("Back on the airline you started with."); closable(); clear(); return; }
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
  // the scan's end: finished or not, the panel says so; then (1.9) the market pages when they're due, else the run is over
  function end(words) { const t = get(); if (t) { t.progress = null; set(t); } log(words); return startMarkets(); }
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


  // ---------------------------------------------------------------- in the game: the market pages (1.9)
  // Spec docs/specs/2026-10-30-market-pages.md: after the world scan (or after the last airline when no scan is due),
  // when capture_airlines() says they're due and no capture page failed (and Stop wasn't pressed). The run itself is
  // runMarkets() above; here is only its outside world: the game's pages by fetch with the session's cookies, the four
  // listing calls, capture_market() with the capture key, switching airline by opening its dashboard (the page reloads
  // and the run carries on from sessionStorage), and the panel.
  async function marketSend(kind, payload) {
    let last = null;
    for (let a = 0; a < 3; a++) {
      try { const r = await fetch(RPC + "capture_market", { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" }, body: JSON.stringify({ p_key: KEY, p_kind: kind, p_payload: payload }) });
        const body = await r.json().catch(() => null); if (r.ok) return body || { ok: false, error: "no answer" }; last = body || { ok: false, error: "HTTP " + r.status }; }
      catch (e) { last = { ok: false, error: e.message }; }
      if (a < 2) await sleep(3000);
    }
    return last;
  }
  async function gameGet(url) {
    const c = new AbortController(), timer = setTimeout(() => c.abort(), PAGE_TIMEOUT_MS);
    try { const r = await fetch(url, { credentials: "include", signal: c.signal }); return { ok: r.ok, status: r.status, url: r.url, html: await r.text() }; }
    finally { clearTimeout(timer); }
  }
  // one of the listing's four filter calls, as the page's own Wicket call sends it (runMarkets() refuses any other address)
  async function filterPost(url, body, base) {
    if (!isFilterCall(url)) throw new Error("not a listing filter call: " + url);
    const headers = { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", "Wicket-Ajax": "true", "X-Requested-With": "XMLHttpRequest" };
    if (base) headers["Wicket-Ajax-BaseURL"] = base;
    const r = await fetch(url, { method: "POST", credentials: "include", headers, body });
    return { ok: r.ok, status: r.status, url: r.url, html: await r.text() };
  }
  const marketStop = () => buttons([["Stop", () => { stopping = true; const t = get(); if (t && t.mk) { t.mk.stop = true; set(t); } show((get() ? lines(get()) : "") + "\nStopping after this page…"); }]]);
  function startMarkets() {
    const t = get(); if (!t) return;
    const why = noMarketWords(t.markets, t.failed || 0, stopping || !!(t.sc && t.sc.stop));
    if (why) { log(why); closable(); clear(); return; }
    t.phase = "market"; t.mk = marketState(t.markets); set(t);
    const left = Math.max(0, t.mk.total - t.mk.done);
    log(`Market pages: due${t.markets.latest ? ` (the last finished ${when(t.markets.latest.finished_at)})` : ""}, ${left} of ${t.mk.total} to read, about ${plural(Math.max(1, Math.round(left * 1.2 / 60)), "minute", "minutes")}; keep this tab open. Stop is below.`);
    return markets();
  }
  async function markets() {
    const t = get(); if (!t || !t.mk) return;
    marketStop(); show(lines(t));
    const io = {
      get: gameGet, post: filterPost, sleep, send: marketSend,
      switchTo: id => { location.href = "/app/enterprise/dashboard?select=" + encodeURIComponent(id); return "away"; },
      save: mk => { const x = get(); if (!x) return; if (x.mk && x.mk.stop) mk.stop = true; x.mk = mk; set(x); },
      stopped: () => stopping || !!((get() || {}).mk || {}).stop,
      log: line => log(line),
      progress: line => progress(line)
    };
    let res;
    try { res = await runMarkets(t.mk, io); } catch (e) { res = { words: "Market pages stopped: " + e.message }; }
    if (res.away) return;
    const x = get(); if (x) { x.progress = null; set(x); }
    log(res.words);
    // back on the airline the capture started with
    const y = get();
    if (y && y.mk && y.mk.switched != null && String(y.mk.switched) !== String(y.start)) { y.phase = "market_home"; set(y); location.href = "/app/enterprise/dashboard?select=" + y.start; return; }
    closable(); clear();
  }

  function addButton() {
    if (document.getElementById("eq-cap-btn")) return; const b = document.createElement("button"); b.id = "eq-cap-btn"; b.textContent = "Capture all airlines"; b.style.cssText = "position:fixed;bottom:16px;right:16px;z-index:999998;background:#F6B44B;color:#0A1230;border:0;border-radius:999px;padding:10px 16px;font:700 13px system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.35);cursor:pointer";
    b.onclick = async () => { b.disabled = true; let got;
      try { got = await loadAirlines(); } catch (e) { show("equinox. capture: couldn't get the airlines to capture (" + e.message + "). Check the capture key."); b.disabled = false; return; }
      const list = got.list, start = (await currentId(list)) || list[0][0];
      set({ i: 0, phase: "switch", start, airlines: list, scan: got.scan, markets: got.markets, failed: 0, log: ["equinox. capture, all airlines…"] }); log("Starting: " + list.map(a => a[1]).join(", ")); step(); };
    document.body.appendChild(b);
  }
  addButton(); const s = get(); if (s) { show(lines(s)); setTimeout(step, 800); }
})(typeof window !== "undefined" ? window : globalThis);
