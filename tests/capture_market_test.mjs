// The market pages in the capture (capture/capture_all.user.js 1.9, now 1.10; spec docs/specs/2026-10-30-market-pages.md), with no
// browser and no game: the script's own file runs in Node, where (with no page) it only hands over its logic (eqScan), as
// tests/capture_scan_test.mjs runs it. The sample is the game's Market Analysis page, DUB to AMS with Ryanair open, as
// Gitesh saved it on 30 Oct 04:51 UTC (tests/fixtures/market_DUBAMS_2026-10-30.html), with the account menu, the holdings
// list, the cash, the credits and the injected userscripts cut out; the rest as saved.
//   1. The page: the filters as the saved setup has them, every flight with its classes and prices (KL 8: Y 120, C 245,
//      Cargo 91; EI 506: F 457; our FR 3044), the shares (KLM 68.46, -10.32; Aer Lingus 24.61; Ryanair 6.94), the
//      historic weeks with figures (week 43: 9,616 seats, 122 AS$), our service profile (R, 318), the open airline (112).
//   2. What goes to capture_market(): fares by prefix and class (nothing per flight), shares, weeks, no HTML.
//   3. The filters: one changed is named; the four listing calls read from the load script, and nothing else (the
//      Pricing and settings forms) passes the check every post goes through; the bodies that set them.
//   4. Whole runs against a stand-in for the game: GETs only when the filters are right, one switch per airline; filters
//      off set right through their calls and then read, each noted; a filter that won't take stops the run, named; the
//      wrong airline open stops it; a page that doesn't read is sent as failed and skipped; more than 10% failed isn't
//      finished; the session lost stops it; Stop stops it; a run carried on.
//   4b. (1.10, the first live run of 30 Oct) The game shows its flat list, with no grouped table, while Group by flight
//      is off: the filter is set before the page is read, so an airline whose Group by flight was off reads every page; a
//      page that still doesn't read says what the game served (title, heading, address, the airline open, Group by
//      flight); the wrong airline open on a page without its table stops the run. Kingfisher's DEL→BOM, saved the same day
//      (tests/fixtures/market_DELBOM_2026-10-30.html): our own flights only, no rival, is a normal page. The service code
//      is the profile's leading token ("S2 (min 800km)" → S2).
//   5. The file and the sample: version 1.10, capture_market() with the key, the only POST to the game through the filter
//      check; the sample holds nothing of the account.
// Usage: node tests/capture_market_test.mjs
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const read = p => readFileSync(new URL(p, here), "utf8");
const source = read("../capture/capture_all.user.js");
const saved = read("fixtures/market_DUBAMS_2026-10-30.html");
const kingfisher = read("fixtures/market_DELBOM_2026-10-30.html");

const sandbox = { URL };
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "capture/capture_all.user.js" });
const S = sandbox.eqScan;
const plain = v => JSON.parse(JSON.stringify(v));

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

const page = plain(S.readMarketPage(saved));
const flight = no => page.flights.find(f => f.flight === no);
const cls = (f, c) => f.classes.find(x => x.cls === c);

// ---------------------------------------------------------------- 1. the page
await check("the script hands over the market pages' logic in Node", () => {
  for (const f of ["readMarketPage", "readMarketFilters", "filterProblems", "filterCalls", "isFilterCall", "filterBody", "openAirlineOf",
                   "fareSummary", "marketPagePayload", "marketPlanOf", "noMarketWords", "runMarkets", "marketState"])
    assert.equal(typeof S[f], "function", f);
  assert.equal(S.marketUrl("DUB", "AMS"), "/app/com/markets/DUBAMS");
  assert.equal(S.MARKET_PACE, 500);
});
await check("the filters as the saved setup has them: every class and status ticked, Ignore own flights off, Group by flight on", () => {
  assert.deepEqual(page.filters, {
    serviceClasses: [{ value: "0", label: "Y", checked: true }, { value: "1", label: "C", checked: true }, { value: "2", label: "F", checked: true }, { value: "3", label: "Cargo", checked: true }],
    flightStati: [{ value: "0", label: "booked", checked: true }, { value: "1", label: "inflight", checked: true }, { value: "2", label: "finished", checked: true }, { value: "3", label: "cancelled", checked: true }],
    ignoreCarriers: false, display: true });
  assert.deepEqual(plain(S.filterProblems(page.filters)), []);
});
await check("Current Availability: the pair, 51 flights, each with its prefix, aircraft, UTC times, status and classes", () => {
  assert.equal(page.from, "DUB"); assert.equal(page.to, "AMS");
  assert.equal(page.flights.length, 51);
  assert.deepEqual(flight("KL 8"), { flight: "KL 8", code: "KL", aircraft: "32Q", date: "2026-10-28", dep: "04:35", arr: "05:54", status: "finished",
    classes: [{ cls: "Y", seats: 0, price: 120 }, { cls: "C", seats: 0, price: 245 }, { cls: "Cargo", seats: 0, price: 91 }] });
  assert.equal(cls(flight("EI 506"), "F").price, 457);
  assert.deepEqual(flight("EI 506").classes.map(c => c.cls), ["Y", "C", "F", "Cargo"]);
  // our own flight: the number is a link and the aircraft cell carries the registration too
  assert.deepEqual(flight("FR 3044"), { flight: "FR 3044", code: "FR", aircraft: "295", date: "2026-10-28", dep: "23:25", arr: "00:44", status: "finished",
    classes: [{ cls: "Y", seats: 0, price: 102 }, { cls: "Cargo", seats: 10, price: 91 }] });
  assert.deepEqual([...new Set(page.flights.map(f => f.status))].sort(), ["booked", "finished", "inflight"]);
  assert.ok(page.flights.every(f => f.code && f.classes.length >= 2 && f.classes.every(c => Number.isFinite(c.price) && Number.isFinite(c.seats))), "a flight without its prefix or figures");
});
await check("Market Shares: week 44/2026 against 43/2026, passengers and cargo, each enterprise by its game id", () => {
  assert.equal(page.shares.week, "44/2026"); assert.equal(page.shares.previous, "43/2026");
  assert.deepEqual(page.shares.passengers, [
    { enterprise_id: 157, name: "KLM Royal Dutch Airlines", share: 68.46, change: -10.32 },
    { enterprise_id: 174, name: "Aer Lingus", share: 24.61, change: 11.37 },
    { enterprise_id: 112, name: "Ryanair", share: 6.94, change: -1.05 }]);
  assert.deepEqual(page.shares.cargo.map(s => [s.enterprise_id, s.share, s.change]), [[157, 58.27, -11.81], [174, 31.65, 13.85], [112, 10.07, -2.04]]);
});
await check("the historic weeks with figures only (week 36 on), week 43: 9,616 seats, 122 AS$", () => {
  assert.deepEqual(page.weeks.map(w => w.week), ["2026-36", "2026-37", "2026-38", "2026-39", "2026-40", "2026-41", "2026-42", "2026-43", "2026-44"]);
  assert.deepEqual(page.weeks.find(w => w.week === "2026-43"), { week: "2026-43", seats: 9616, price: 122 });
  assert.deepEqual(page.weeks.find(w => w.week === "2026-44"), { week: "2026-44", seats: 6268, price: 125 });
});
await check("our service profile on the pair, read from the settings form's On-Board Service: R (318); none when nothing is selected", () => {
  assert.deepEqual(page.service, { code: "R", game_id: 318 });
  const none = saved.replace('<option selected="selected" value="318">R</option>', '<option value="318">R</option>').replace('<option value="">no service profile</option>', '<option selected="selected" value="">no service profile</option>');
  assert.equal(plain(S.readMarketPage(none)).service, null);
});
await check("the airline that's open: 112, Ryanair (the game's settings and the main menu)", () => {
  assert.deepEqual(plain(S.openAirlineOf(saved)), { id: 112, name: "Ryanair" });
  assert.equal(S.openProblem(S.openAirlineOf(saved), { game_id: 112, name: "Ryanair" }), null);
  assert.match(S.openProblem(S.openAirlineOf(saved), { game_id: 114, name: "Pan Am" }), /airline 112 \(Ryanair\) open, not Pan Am \(114\)/);
});
await check("a page without Current Availability (signed out, or the page changed) gives its error", () => {
  assert.match(S.readMarketPage("<html><body>Please sign in</body></html>").error, /no Current Availability table/);
});

// ---------------------------------------------------------------- 2. what goes to the database
await check("the page's payload: fares by prefix and class (flights seen, lowest, average, highest, finished, sold out), shares, weeks, service; no HTML, nothing per flight", () => {
  const p = plain(S.marketPagePayload(7, { game_id: 112, name: "Ryanair" }, "DUB", "AMS", S.readMarketPage(saved), null));
  assert.deepEqual(Object.keys(p).sort(), ["airline", "dest", "fares", "ok", "origin", "previous_week", "run_id", "service", "shares", "week", "weeks"]);
  assert.equal(p.ok, true); assert.equal(p.airline, 112); assert.equal(p.week, "2026-44"); assert.equal(p.previous_week, "2026-43");
  assert.deepEqual(p.service, { code: "R", game_id: 318 });
  const fare = (code, c) => p.fares.find(f => f.code === code && f.cls === c);
  assert.deepEqual(fare("KL", "Y"), { code: "KL", cls: "Y", flights: 31, low: 120, avg: 120, high: 120, finished: 12, sold_out: 12 });
  assert.deepEqual(fare("EI", "F"), { code: "EI", cls: "F", flights: 15, low: 457, avg: 457, high: 457, finished: 6, sold_out: 6 });
  assert.deepEqual(fare("EI", "Y"), { code: "EI", cls: "Y", flights: 15, low: 156, avg: 156, high: 156, finished: 6, sold_out: 1 });
  assert.deepEqual(fare("FR", "Cargo"), { code: "FR", cls: "Cargo", flights: 5, low: 91, avg: 91, high: 91, finished: 2, sold_out: 0 });
  assert.equal(p.fares.length, 9);
  assert.deepEqual(p.shares.map(s => [s.kind, s.enterprise_id]), [["passengers", 157], ["passengers", 174], ["passengers", 112], ["cargo", 157], ["cargo", 174], ["cargo", 112]]);
  assert.equal(p.weeks.length, 9);
  const json = JSON.stringify(p);
  assert.ok(!/[<>]/.test(json) && json.length < 3000, "the payload holds HTML, or is far too big: " + json.length);
  assert.ok(!/KL 8|EI 506/.test(json), "a flight number is in the payload");
});
await check("an average over different prices, kept to cents; a failed page's payload carries its error only", () => {
  const f = [{ code: "XX", status: "booked", classes: [{ cls: "Y", seats: 9, price: 100 }] }, { code: "XX", status: "finished", classes: [{ cls: "Y", seats: 0, price: 101 }] },
             { code: "XX", status: "finished", classes: [{ cls: "Y", seats: 3, price: 102 }] }];
  assert.deepEqual(plain(S.fareSummary(f)), [{ code: "XX", cls: "Y", flights: 3, low: 100, avg: 101, high: 102, finished: 2, sold_out: 1 }]);
  assert.deepEqual(plain(S.fareSummary([{ code: "XX", status: "booked", classes: [{ cls: "C", seats: 1, price: 100 }] }, { code: "XX", status: "booked", classes: [{ cls: "C", seats: 1, price: 101 }] },
    { code: "XX", status: "booked", classes: [{ cls: "C", seats: 1, price: 101 }] }]))[0].avg, 100.67);
  assert.deepEqual(plain(S.marketPagePayload(7, { game_id: 112 }, "DUB", "AMS", null, "the game answered HTTP 502")),
    { run_id: 7, airline: 112, origin: "DUB", dest: "AMS", ok: false, error: "the game answered HTTP 502" });
});
await check("capture_airlines()'s market part read, and why there are no market pages tonight", () => {
  const plan = plain(S.marketPlanOf({ market_due: true, market_open: null, market_every_days: 7, market_latest: { id: 3, finished_at: "2026-10-23T03:00:00.000Z" },
    market_total: 3, market_done: 0, market_pages: [{ game_id: 112, code: "FR", name: "Ryanair", pages: [["DUB", "AMS"], ["AMS", "DUB"], ["bad", "x"]] }] }));
  assert.deepEqual(plan.airlines, [{ game_id: 112, code: "FR", name: "Ryanair", game_name: null, pages: [["DUB", "AMS"], ["AMS", "DUB"]] }]);
  assert.equal(S.noMarketWords(plan, 0, false), null);
  assert.match(S.noMarketWords(plan, 2, false), /not tonight, because 2 capture pages failed/);
  assert.match(S.noMarketWords(plan, 0, true), /Stop was pressed/);
  assert.match(S.noMarketWords({ ...plan, due: false }, 0, false), /^Market pages: not due; the last finished 2026-10-23 03:00 UTC \(every 7 days\)\.$/);
  assert.match(S.noMarketWords({ ...plan, every: 0 }, 0, false), /off \(market_every_days is 0\)/);
  assert.match(S.noMarketWords(S.marketPlanOf({}), 0, false), /off \(the world has no market_every_days setting\)/);
  assert.equal(S.marketProgress(120, 686, "Pan Am"), "Market pages: 120 of 686 (Pan Am)…");
});

// ---------------------------------------------------------------- 3. the filters
// the saved page with its filters as given (true = ticked)
function withFilters(html, f) {
  let h = html;
  const set = (name, value, on) => {
    const rx = new RegExp('<input name="pair:pair-panel:listing:filters:' + name + '" type="checkbox"(?: checked="checked")? value="' + value + '"');
    assert.ok(rx.test(h), "no box " + name + " " + value);
    h = h.replace(rx, '<input name="pair:pair-panel:listing:filters:' + name + '" type="checkbox"' + (on ? ' checked="checked"' : "") + ' value="' + value + '"');
  };
  for (const g of ["serviceClasses", "flightStati"]) for (const [v, on] of Object.entries(f[g] || {})) set(g, v, on);
  if ("ignoreCarriers" in f) h = h.replace(/<input type="checkbox"(?: checked="checked")? name="pair:pair-panel:listing:filters:ignoreCarriers"/, `<input type="checkbox"${f.ignoreCarriers ? ' checked="checked"' : ""} name="pair:pair-panel:listing:filters:ignoreCarriers"`);
  if ("display" in f) h = h.replace(/<input type="checkbox"(?: checked="checked")? name="pair:pair-panel:listing:filters:display"/, `<input type="checkbox"${f.display ? ' checked="checked"' : ""} name="pair:pair-panel:listing:filters:display"`);
  return h;
}
await check("one filter changed is named: 'cancelled' under Flight status; Ignore own flights ticked; Group by flight off", () => {
  const p = plain(S.filterProblems(S.readMarketFilters(withFilters(saved, { flightStati: { 3: false } }))));
  assert.deepEqual(p, [{ filter: "flightStati", label: "cancelled", where: "Flight status", want: true }]);
  assert.equal(S.filterWords(p[0]), "tick 'cancelled' under Flight status");
  const q = plain(S.filterProblems(S.readMarketFilters(withFilters(saved, { serviceClasses: { 2: false }, ignoreCarriers: true, display: false }))));
  assert.deepEqual(q.map(x => [x.filter, x.label, x.want]), [["serviceClasses", "F", true], ["ignoreCarriers", "Ignore own flights", false], ["display", "Group by flight", true]]);
  assert.equal(S.filterWords(q[1]), "untick 'Ignore own flights' under Settings");
  // a page without the filters at all
  assert.ok(plain(S.filterProblems(S.readMarketFilters("<html></html>"))).every(x => x.want === "on the page"));
});
const PAGE_URL = "https://gander.airlinesim.aero/app/com/markets/DUBAMS?11";
await check("the four listing calls, read from the page's load script, against the page's address; the bodies that set them", () => {
  const c = plain(S.filterCalls(saved, PAGE_URL));
  assert.deepEqual(Object.keys(c).sort(), ["display", "flightStati", "ignoreCarriers", "serviceClasses"]);
  assert.equal(c.flightStati, "https://gander.airlinesim.aero/app/com/markets/DUBAMS?11-1.0-pair-pair~panel-listing-filters-flightStati");
  for (const u of Object.values(c)) assert.ok(S.isFilterCall(u), u);
  const f = S.readMarketFilters(saved), n = encodeURIComponent("pair:pair-panel:listing:filters:flightStati");
  assert.equal(S.filterBody("flightStati", f), [0, 1, 2, 3].map(v => n + "=" + v).join("&"));
  assert.equal(S.filterBody("display", f), encodeURIComponent("pair:pair-panel:listing:filters:display") + "=on");
  assert.equal(S.filterBody("ignoreCarriers", f), "");
  assert.throws(() => S.filterBody("prices", f));
  assert.equal(S.wicketBase(saved), "com/markets/DUBAMS?11");
});
await check("nothing else on the page passes the check every post goes through: not the Pricing or settings forms, not another page", () => {
  const actions = [...saved.matchAll(/<form\b[^>]*action="([^"]*)"/g)].map(m => m[1]);
  assert.ok(actions.some(a => /settings~form/.test(a)), "the settings form isn't on the saved page");
  for (const a of actions) assert.ok(!S.isFilterCall(new URL(a, PAGE_URL).href), "a form passes: " + a);
  const calls = [...saved.matchAll(/"u":"([^"]*)"/g)].map(m => m[1]).filter(u => !/-listing-filters-(serviceClasses|flightStati|ignoreCarriers|display)$/.test(u));
  assert.ok(calls.some(u => /prices-0-reset/.test(u)), "the pricing reset calls aren't on the saved page");
  for (const u of calls) assert.ok(!S.isFilterCall(new URL(u, PAGE_URL).href), "a call passes: " + u);
  for (const u of ["https://gander.airlinesim.aero/action/enterprise/flightsPrices?adjust=true", "https://gander.airlinesim.aero/app/com/markets/DUBAMS?11-1.0-pair-pair~panel-listing-filters-display&x=1",
                   "https://elsewhere.test/app/com/markets/DUBAMS?11-1.0-pair-pair~panel-settings-settings~form"])
    assert.ok(!S.isFilterCall(u), u);
});

// ---------------------------------------------------------------- 4. whole runs against a stand-in for the game
// The stand-in: an open airline (changed only by switchTo), the listing's filters (kept between visits, as the game keeps
// them; changed only by a post to their call, unless that filter is stuck), and the saved page served for every pair,
// with its pair, open airline and filters as they are. Everything sent to the game and to the database is recorded.
// the game's flat list while Group by flight is off (1.10): no grouped table
const flatWhenOff = (html, f) => f.display ? html : html.replace('id="inventory-grouped-table"', 'id="inventory-flat-table"');
const ALL = { serviceClasses: { 0: true, 1: true, 2: true, 3: true }, flightStati: { 0: true, 1: true, 2: true, 3: true }, ignoreCarriers: false, display: true };
function standIn({ filters = ALL, stuck = [], open = 112, ignoreSwitch = false, badPages = [], lostAt = null, stopAfter = null, sendFails = [] } = {}) {
  const g = { open, filters: JSON.parse(JSON.stringify(filters)), gets: [], posts: [], switches: [], sends: [], logs: [], sleeps: [], state: null };
  const pageFor = (from, to) => flatWhenOff(withFilters(saved, g.filters), g.filters)
    .replace('"fixedEnterpriseId":112', `"fixedEnterpriseId":${g.open}`)
    .replace(/\(<a href="\.\.\/\.\.\/info\/airports\/1317">DUB<\/a>\)/, `(<a href="../../info/airports/1">${from}</a>)`)
    .replace(/\(<a href="\.\.\/\.\.\/info\/airports\/2245">AMS<\/a>\)/, `(<a href="../../info/airports/2">${to}</a>)`)
    .replaceAll("./DUBAMS?11", `./${from}${to}?11`);
  g.io = {
    get: async url => {
      g.gets.push(url);
      const m = url.match(/^\/app\/com\/markets\/([A-Z0-9]{3})([A-Z0-9]{3})$/);
      if (!m) throw new Error("the stand-in serves market pages only: " + url);
      if (lostAt && url === lostAt) return { ok: true, status: 200, url: "https://gander.airlinesim.aero/app/login", html: "<html>sign in</html>" };
      if (badPages.includes(m[1] + m[2])) return { ok: true, status: 200, url: "https://gander.airlinesim.aero" + url + "?12", html: "<html><body>Market Analysis, but changed</body></html>" };
      return { ok: true, status: 200, url: "https://gander.airlinesim.aero" + url + "?11", html: pageFor(m[1], m[2]) };
    },
    post: async (url, body, base) => {
      g.posts.push({ url, body, base });
      const which = url.match(/-listing-filters-(\w+)$/)[1];
      if (stuck.includes(which)) return { ok: true, status: 200, url, html: "<ajax-response></ajax-response>" };
      const vals = body ? body.split("&").map(kv => decodeURIComponent(kv.split("=")[1])) : [];
      if (which === "serviceClasses" || which === "flightStati") { for (const k of Object.keys(g.filters[which])) g.filters[which][k] = vals.includes(k); }
      else g.filters[which] = vals.length > 0;
      return { ok: true, status: 200, url, html: "<ajax-response></ajax-response>" };
    },
    sleep: async ms => { g.sleeps.push(ms); },
    send: async (kind, payload) => {
      g.sends.push({ kind, payload });
      if (kind === "start") return { ok: true, run_id: 41, carried_on: false };
      if (kind === "page" && sendFails.includes(payload.origin + payload.dest)) return { ok: false, error: "no" };
      return { ok: true };
    },
    switchTo: async id => { g.switches.push(id); if (!ignoreSwitch) g.open = id; return "here"; },
    save: st => { g.state = JSON.parse(JSON.stringify(st)); },
    stopped: () => stopAfter != null && g.sends.filter(s => s.kind === "page").length >= stopAfter,
    log: line => g.logs.push(line),
    progress: line => { if (line) g.logs.push("· " + line); }
  };
  return g;
}
const PLAN = S.marketPlanOf({ market_due: true, market_every_days: 7, market_total: 5, market_done: 0, market_pages: [
  { game_id: 112, code: "FR", name: "Ryanair", pages: [["DUB", "AMS"], ["AMS", "DUB"], ["DUB", "BCN"]] },
  { game_id: 114, code: "PA", name: "Pan Am", pages: [["JFK", "LHR"], ["LHR", "JFK"]] }] });

await check("a whole run, filters right: only GETs of market pages, one switch per airline, start, five pages and finish", async () => {
  const g = standIn({ open: 999 });
  const res = plain(await S.runMarkets(S.marketState(PLAN), g.io));
  assert.equal(res.words, "Market pages done: 5, 0 failed.");
  assert.equal(g.posts.length, 0, "it posted to the game");
  assert.deepEqual(g.switches, [112, 114]);
  assert.deepEqual(g.gets, ["/app/com/markets/DUBAMS", "/app/com/markets/AMSDUB", "/app/com/markets/DUBBCN", "/app/com/markets/JFKLHR", "/app/com/markets/LHRJFK"]);
  assert.deepEqual(g.sends.map(s => s.kind), ["start", "page", "page", "page", "page", "page", "finish"]);
  assert.deepEqual(plain(g.sends.filter(s => s.kind === "page").map(s => [s.payload.run_id, s.payload.airline, s.payload.origin, s.payload.dest, s.payload.ok])),
    [[41, 112, "DUB", "AMS", true], [41, 112, "AMS", "DUB", true], [41, 112, "DUB", "BCN", true], [41, 114, "JFK", "LHR", true], [41, 114, "LHR", "JFK", true]]);
  assert.ok(g.sends.every(s => !/[<>]/.test(JSON.stringify(s.payload))), "HTML sent to the database");
  assert.deepEqual(plain(g.sends[0].payload), { version: "1.10", total: 5, note: "Capture all airlines 1.10" });
  assert.equal(g.sends[6].payload.run_id, 41);
  assert.ok(g.sleeps.length === 4 && g.sleeps.every(ms => ms === 500), "not half a second between pages: " + g.sleeps);
  assert.ok(g.logs.includes("· Market pages: 0 of 5 (Ryanair)…") && g.logs.includes("· Market pages: 3 of 5 (Pan Am)…"), g.logs.join("\n"));
});
await check("filters off: set right through their own calls (the only posts), each noted, the page read again and then read", async () => {
  const g = standIn({ filters: { ...ALL, flightStati: { 0: true, 1: true, 2: true, 3: false }, ignoreCarriers: true, display: false } });
  const res = plain(await S.runMarkets(S.marketState(PLAN), g.io));
  assert.equal(res.words, "Market pages done: 5, 0 failed.");
  assert.deepEqual(g.posts.map(p => p.url.replace(/^.*-listing-filters-/, "")), ["flightStati", "ignoreCarriers", "display"]);
  assert.ok(g.posts.every(p => S.isFilterCall(p.url) && p.url.startsWith("https://gander.airlinesim.aero/app/com/markets/DUBAMS?11-1.0-") && p.base === "com/markets/DUBAMS?11"));
  assert.equal(g.posts[0].body, [0, 1, 2, 3].map(v => encodeURIComponent("pair:pair-panel:listing:filters:flightStati") + "=" + v).join("&"));
  assert.equal(g.posts[1].body, ""); assert.equal(g.posts[2].body, encodeURIComponent("pair:pair-panel:listing:filters:display") + "=on");
  assert.deepEqual(g.logs.filter(l => /set the filter/.test(l)), [
    "Market pages: set the filter, tick 'cancelled' under Flight status (on DUB→AMS).",
    "Market pages: set the filter, untick 'Ignore own flights' under Settings (on DUB→AMS).",
    "Market pages: set the filter, tick 'Group by flight' under Settings (on DUB→AMS)."]);
  // the first page read twice (before and after), the game keeping the filters for the rest
  assert.deepEqual(g.gets.slice(0, 3), ["/app/com/markets/DUBAMS", "/app/com/markets/DUBAMS", "/app/com/markets/AMSDUB"]);
  assert.equal(g.sends.filter(s => s.kind === "page" && s.payload.ok).length, 5);
});
await check("a filter that won't take stops the run, named, before anything of the page is sent", async () => {
  const g = standIn({ filters: { ...ALL, flightStati: { 0: true, 1: true, 2: true, 3: false } }, stuck: ["flightStati"] });
  const res = plain(await S.runMarkets(S.marketState(PLAN), g.io));
  assert.equal(res.words, "Market pages: couldn't set 'cancelled' under Flight status on DUB→AMS. Stopped; set it on the page by hand, then press Capture again.");
  assert.deepEqual(g.sends.map(s => s.kind), ["start"]);
  assert.equal(g.posts.length, 1);
});
await check("the wrong airline open after the switch stops the run before anything is read", async () => {
  const g = standIn({ open: 107, ignoreSwitch: true });
  const res = plain(await S.runMarkets(S.marketState(PLAN), g.io));
  assert.match(res.words, /^Market pages stopped on DUB→AMS: the game has airline 107 \(Ryanair\) open, not Ryanair \(112\): the switch didn't take\.$/);
  assert.deepEqual(g.sends.map(s => s.kind), ["start"]);
  assert.equal(g.posts.length, 0);
});
await check("a page that doesn't read is sent as failed with its error and skipped; the run finishes when 10% or fewer failed", async () => {
  const many = S.marketPlanOf({ market_due: true, market_every_days: 7, market_pages: [{ game_id: 112, name: "Ryanair",
    pages: ["AAA", "BBB", "CCC", "DDD", "EEE", "FFF", "GGG", "HHH", "III", "JJJ"].map(c => ["DUB", c]) }] });
  const g = standIn({ badPages: ["DUBCCC"] });
  const res = plain(await S.runMarkets(S.marketState(many), g.io));
  assert.equal(res.words, "Market pages done: 10, 1 failed.");
  const bad = g.sends.find(s => s.kind === "page" && s.payload.dest === "CCC").payload;
  assert.deepEqual(plain(bad), { run_id: 41, airline: 112, origin: "DUB", dest: "CCC", ok: false,
    error: 'no Current Availability table on the page (title "", heading "", at /app/com/markets/DUBCCC?12, open ?, Group by flight not on the page)' });
  assert.ok(g.logs.some(l => /Ryanair DUB→CCC failed \(no Current Availability table on the page \(title "", .*\)\); skipped/.test(l)));
  // two of ten: not finished, no finish sent
  const h = standIn({ badPages: ["DUBCCC"], sendFails: ["DUBDDD"] });
  const r2 = plain(await S.runMarkets(S.marketState(many), h.io));
  assert.match(r2.words, /^Market pages not finished: 2 of 10 pages failed, more than 10%/);
  assert.ok(!h.sends.some(s => s.kind === "finish"));
});
await check("the session lost stops the run; Stop stops it; a run carried on starts nothing and reads only what's left", async () => {
  const g = standIn({ lostAt: "/app/com/markets/AMSDUB" });
  assert.match(plain(await S.runMarkets(S.marketState(PLAN), g.io)).words, /^Market pages stopped on AMS→DUB: the game sent it to \/app\/login; the session may have been lost\.$/);
  const h = standIn({ stopAfter: 2 });
  assert.match(plain(await S.runMarkets(S.marketState(PLAN), h.io)).words, /^Market pages stopped \(2 of 5 read\)/);
  assert.ok(!h.sends.some(s => s.kind === "finish"));
  const carried = S.marketPlanOf({ market_due: true, market_every_days: 7, market_open: 39, market_total: 5, market_done: 3,
    market_pages: [{ game_id: 114, name: "Pan Am", pages: [["JFK", "LHR"], ["LHR", "JFK"]] }] });
  const k = standIn();
  assert.equal(plain(await S.runMarkets(S.marketState(carried), k.io)).words, "Market pages done: 5, 0 failed.");
  assert.deepEqual(k.sends.map(s => s.kind), ["page", "page", "finish"]);
  assert.ok(k.sends.every(s => s.payload.run_id === 39));
  assert.deepEqual(k.switches, [114]);
});
await check("in the game the switch leaves the page: the run says so, and carries on from its saved state after the reload", async () => {
  const g = standIn();
  let away = true;
  const io = { ...g.io, switchTo: async id => { g.switches.push(id); g.open = id; if (away) { away = false; return "away"; } return "here"; } };
  const first = plain(await S.runMarkets(S.marketState(PLAN), io));
  assert.deepEqual(first, { away: true });
  assert.equal(g.state.switched, 112);
  const again = plain(await S.runMarkets(g.state, io));
  assert.equal(again.words, "Market pages done: 5, 0 failed.");
  assert.deepEqual(g.switches, [112, 114]);
  assert.equal(g.sends.filter(s => s.kind === "start").length, 1);
});

// ---------------------------------------------------------------- 4b. 1.10: the first live run's failures
await check("1.10: an airline whose Group by flight is off (the game's flat list, no grouped table) is read: the filter set first, every page read", async () => {
  const g = standIn({ filters: { ...ALL, display: false } });
  const res = plain(await S.runMarkets(S.marketState(PLAN), g.io));
  assert.equal(res.words, "Market pages done: 5, 0 failed.");
  assert.deepEqual(g.posts.map(p => p.url.replace(/^.*-listing-filters-/, "")), ["display"]);
  assert.deepEqual(g.logs.filter(l => /set the filter/.test(l)), ["Market pages: set the filter, tick 'Group by flight' under Settings (on DUB→AMS)."]);
  assert.ok(g.sends.filter(s => s.kind === "page").every(s => s.payload.ok), "a page failed");
});
await check("1.10: a page that still has no table says what the game served: title, heading, address, the airline open, Group by flight", async () => {
  const flat = withFilters(saved, { display: false }).replace('id="inventory-grouped-table"', 'id="inventory-flat-table"');
  assert.equal(S.hasGroupedTable(saved), true); assert.equal(S.hasGroupedTable(flat), false);
  assert.equal(S.pageWhat(flat, "https://gander.airlinesim.aero/app/com/markets/DUBAMS?11"),
    'title "Market Analysis | Gander | AirlineSim", heading "Market Analysis", at /app/com/markets/DUBAMS?11, open 112 Ryanair, Group by flight off');
  assert.equal(S.pageWhat("<html><head><title>Dashboard | Gander</title></head><body><div class=\"bootstrap container-fluid\"><h1>Overview</h1></div></body></html>", "/app/enterprise/dashboard"),
    'title "Dashboard | Gander", heading "Overview", at /app/enterprise/dashboard, open ?, Group by flight not on the page');
  // the right airline open, the filters right, still no table (the page changed): a failed page saying so, the run going on
  const g = standIn();
  const io = { ...g.io, get: async url => { const r = await g.io.get(url); return url.endsWith("AMSDUB") ? { ...r, html: r.html.replace('id="inventory-grouped-table"', 'id="something-else"') } : r; } };
  const res = plain(await S.runMarkets(S.marketState(PLAN), io));
  assert.equal(res.words, "Market pages not finished: 1 of 5 pages failed, more than 10%. The Systems board keeps the last finished run.");
  const bad = g.sends.find(s => s.kind === "page" && s.payload.origin === "AMS").payload;
  assert.equal(bad.error, 'no Current Availability table on the page (title "Market Analysis | Gander | AirlineSim", heading "Market Analysis", at /app/com/markets/AMSDUB?11, open 112 Ryanair, Group by flight on)');
});
await check("1.10: the wrong airline open on a later page without its table stops the run, as on the first page", async () => {
  const g = standIn();
  const io = { ...g.io, get: async url => { const r = await g.io.get(url); return url.endsWith("AMSDUB")
    ? { ...r, html: r.html.replace('"fixedEnterpriseId":112', '"fixedEnterpriseId":107').replace('id="inventory-grouped-table"', 'id="x"') } : r; } };
  const res = plain(await S.runMarkets(S.marketState(PLAN), io));
  assert.match(res.words, /^Market pages stopped on AMS→DUB: the game has airline 107 \(Ryanair\) open, not Ryanair \(112\): the switch didn't take\.$/);
  assert.equal(g.sends.filter(s => s.kind === "page").length, 1, "the page for another airline was sent");
});
await check("1.10: Kingfisher's DEL→BOM (our own flights only, no rival) is a normal page: 10 flights, KF only, 100% share, S2 (308)", () => {
  const p = plain(S.readMarketPage(kingfisher));
  assert.equal(p.error, undefined); assert.equal(p.from, "DEL"); assert.equal(p.to, "BOM");
  assert.equal(p.flights.length, 10); assert.deepEqual([...new Set(p.flights.map(f => f.code))], ["KF"]);
  assert.deepEqual(p.flights[0], { flight: "KF 1009", code: "KF", aircraft: "32Q", date: "2026-10-29", dep: "04:01", arr: "05:47", status: "finished",
    classes: [{ cls: "Y", seats: 0, price: 143 }, { cls: "C", seats: 0, price: 307 }, { cls: "Cargo", seats: 0, price: 104 }] });
  assert.deepEqual(p.shares.passengers, [{ enterprise_id: 113, name: "Kingfisher Airlines", share: 100, change: 0 }]);
  assert.deepEqual(p.service, { code: "S2", game_id: 308 });
  assert.deepEqual(plain(S.filterProblems(p.filters)), []);
  assert.deepEqual(plain(S.openAirlineOf(kingfisher)), { id: 113, name: "Kingfisher Airlines" });
  const pay = plain(S.marketPagePayload(1, { game_id: 113 }, "DEL", "BOM", S.readMarketPage(kingfisher), null));
  assert.equal(pay.ok, true);
  assert.deepEqual(pay.fares.map(f => [f.code, f.cls, f.flights, f.low, f.high]), [["KF", "Y", 10, 143, 150], ["KF", "C", 10, 307, 322], ["KF", "Cargo", 10, 104, 104]]);
  for (const bad of ["DevilsVengeance", "user?id=", "Your Holdings", "828,976", "Credits", "UserScript", "eyJ", "eq-uw", "const KEY", "shadowrootmode"])
    assert.ok(!kingfisher.includes(bad), "the Kingfisher sample still holds " + bad);
});
await check("1.10: the service code is the profile's leading token, as the planner writes it", () => {
  assert.equal(S.serviceToken("S2 (min 800km)"), "S2"); assert.equal(S.serviceToken("S3 (min 1500km)"), "S3");
  assert.equal(S.serviceToken("R"), "R"); assert.equal(S.serviceToken(" S1 "), "S1"); assert.equal(S.serviceToken(""), null);
});

// ---------------------------------------------------------------- 5. the file and the sample
await check("the file: version 1.10, capture_market() with the key, switching by the dashboard, the only POST to the game through the filter check", () => {
  assert.match(source, /^\/\/ @version\s+1\.10$/m);
  assert.equal(S.VERSION, "1.10");
  assert.match(source, /RPC \+ "capture_market"[\s\S]{0,300}p_key: KEY, p_kind: kind, p_payload: payload/);
  assert.match(source, /switchTo: id => \{ location\.href = "\/app\/enterprise\/dashboard\?select=" \+ encodeURIComponent\(id\); return "away"; \}/);
  const posts = [...source.matchAll(/method: "POST"/g)].length;
  assert.equal(posts, 4, "POSTs: capture_ingest/rpc, capture_scan, capture_market and the filter call, nothing else");
  const fp = source.slice(source.indexOf("async function filterPost"), source.indexOf("const marketStop"));
  assert.match(fp, /if \(!isFilterCall\(url\)\) throw new Error/);
  assert.match(source, /const post = async \(url, body, base\) => \{ if \(!isFilterCall\(url\)\) throw new Error/);
  assert.ok(!/submit\s*\(/.test(source.replace(/^\s*\/\/.*$/gm, "")), "a form submitted");
});
await check("the sample holds nothing of the account: no player name, profile, holdings, cash, credits or capture key", () => {
  for (const bad of ["DevilsVengeance", "user?id=", "Your Holdings", "Switch Enterprise", "828,976", "Credits", "UserScript", "eyJ", "eq-uw", "const KEY"])
    assert.ok(!saved.includes(bad), "the sample still holds " + bad);
  assert.ok(/^<!DOCTYPE html>\n<!-- The game's Market Analysis page, DUB to AMS/.test(saved), "the sample doesn't say what it is");
});

console.log(failures ? `\n${failures} capture market check(s) failed` : "\ncapture market: all passed");
process.exit(failures ? 1 : 0);
