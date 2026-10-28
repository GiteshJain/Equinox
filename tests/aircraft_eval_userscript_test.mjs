// The aircraft evaluation userscript (capture/aircraft_eval.user.js; spec docs/specs/2026-10-27-aircraft-evaluation-script.md,
// the Building chat's design) on the game's pages, with no browser and no game: the script's own file runs in Node, where
// (with no page) it only hands over its logic. On Gitesh's two saved pages of 27 Oct: the tool with JFK to SGN selected
// and no aircraft added (tests/fixtures/aircraft_eval_form_2026-10-27.html, page version 134) and with three types added
// and Comfort applied (tests/fixtures/aircraft_eval_result_2026-10-27.html, version 138).
// Checks: the three forms and their actions read from each page; the empty table read as no rows; the result's three
// rows (the A350-900's 17 figures exactly, the A321NEO Light and Embraer 195 E2 as cannot operate, the game's type ids);
// the route's h2 and names; the settings as selected; the add list matched by text and the missing types worked out; the
// three POST bodies from the page's own field names and values; a missing type and a page without the table refused;
// whole runs against a stand-in for the game that answers with the saved pages (only the tool's three forms sent, each
// from the latest page; a run that needs nothing added or set sends only the route; each way a run stops);
// capture_eval_runs()'s answer read and its errors; the panel's words; and the file's header, key placeholder, pauses,
// no dialogs and no other page of the game.
// Usage: node tests/aircraft_eval_userscript_test.mjs
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const source = readFileSync(new URL("../capture/aircraft_eval.user.js", here), "utf8");
const formPage = readFileSync(new URL("fixtures/aircraft_eval_form_2026-10-27.html", here), "utf8");
const resultPage = readFileSync(new URL("fixtures/aircraft_eval_result_2026-10-27.html", here), "utf8");

const sandbox = { URL };
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "capture/aircraft_eval.user.js" });
const E = sandbox.eqEval;
const plain = v => JSON.parse(JSON.stringify(v));   // values made inside the script's own context compare by their JSON

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

// the 17 types, as settings.aircraft_eval_types holds them (migration 20261027210000_aircraft_eval.sql)
const TYPES = ["Airbus A320NEO", "Airbus A320NEO Heavy", "Airbus A320NEO Light", "Airbus A320NEO SHARP", "Airbus A321LR",
  "Airbus A321NEO", "Airbus A321NEO Heavy", "Airbus A321NEO Light", "Airbus A321NEO Medium", "Airbus A321XLR",
  "Airbus A321XLR Heavy", "Airbus A321XLR Light", "Airbus A350-1000", "Airbus A350-900", "Airbus A350-900ULR",
  "Embraer 190 E2", "Embraer 195 E2"];
const BASE = "https://gander.airlinesim.aero/app/aircraft/evaluation";

await check("the script hands over its logic in Node and touches no page", () => {
  assert.ok(E, "eqEval isn't there");
  for (const f of ["formsOf", "tableOf", "routeOf", "routeProblem", "addValues", "missingTypes", "settingsFor", "routeBody", "addBody", "settingsBody", "resultOf", "runOne", "planOf"])
    assert.equal(typeof E[f], "function", f);
  assert.equal(E.TOOL, "/app/aircraft/evaluation");
});

// ---------------------------------------------------------------- the forms
await check("the three forms and their actions, read from each page (tied to its version: 134, 138)", () => {
  for (const [html, v] of [[formPage, "134-2"], [resultPage, "138-6"]]) {
    const f = plain(E.formsOf(html));
    assert.equal(f.route.action, `./evaluation?${v}.-aircraft.eval.route.form`);
    assert.equal(f.add.action, `./evaluation?${v}.-evaluation-add`);
    assert.equal(f.settings.action, `./evaluation?${v}.-evaluation-settings`);
    assert.equal(f.route.from, "from:phrase"); assert.equal(f.route.to, "to:phrase");
    assert.equal(f.add.name, "types");
    assert.deepEqual(f.settings.selects.map(s => s.name), ["age", "serviceClass", "seat", "priceFactor"]);
  }
});
await check("a first page with only the route form: no add or settings form, no table", () => {
  const first = formPage.replace(/<div>\s*<h2>[\s\S]*$/, "</div></body></html>");
  const f = plain(E.formsOf(first));
  assert.ok(f.route && !f.add && !f.settings);
  assert.equal(E.tableOf(first), null);
});
await check("the route: the h2 and the names in both boxes", () => {
  for (const html of [formPage, resultPage])
    assert.deepEqual(plain(E.routeOf(html)), { h2: "Evaluation for route from New York John F. Kennedy to Ho Chi Minh City Tan Son Nhat",
                                                from: "New York John F. Kennedy", to: "Ho Chi Minh City Tan Son Nhat" });
  assert.equal(E.routeProblem(resultPage, "JFK", "SGN"), null);
  const notTaken = formPage.replace('value="New York John F. Kennedy"', 'value="LGW"').replace('value="Ho Chi Minh City Tan Son Nhat"', 'value="CAI"').replace(/<h2>[\s\S]*?<\/h2>/, "");
  assert.equal(E.routeProblem(notTaken, "LGW", "CAI"), "the tool didn't take LGW to CAI");
  const codesKept = formPage.replace('value="New York John F. Kennedy"', 'value="lgw"');
  assert.equal(E.routeProblem(codesKept, "LGW", "SGN"), "the tool didn't take LGW to SGN");
});
await check("the settings as selected: Standard on the form page, Comfort (104) on the result page; values by text", () => {
  assert.deepEqual(plain(E.settingsOf(E.formsOf(formPage).settings)), { age: "0 year(s)", class: "Economy", seat: "Standard", price_factor: "100%" });
  const f = plain(E.formsOf(resultPage).settings);
  assert.deepEqual(plain(E.settingsOf(f)), { age: "0 year(s)", class: "Economy", seat: "Comfort", price_factor: "100%" });
  const seat = f.selects.find(s => s.name === "seat");
  assert.deepEqual(seat.options.find(o => o.selected), { value: "104", text: "Comfort", selected: true });
  assert.equal(plain(E.settingsFor(E.formsOf(resultPage).settings, "Comfort")).ok, true);
  const leisure = plain(E.settingsFor(E.formsOf(resultPage).settings, "Leisure"));
  assert.equal(leisure.ok, false);
  assert.deepEqual(leisure.pairs, [["age", "0"], ["serviceClass", "2"], ["seat", "102"], ["priceFactor", "100"]]);
  assert.deepEqual(plain(E.settingsFor(E.formsOf(formPage).settings, "Leisure Plus")).pairs.find(p => p[0] === "seat"), ["seat", "103"]);
  // values are read from the page, never hard-coded: a page whose Comfort is 204 sends 204
  const moved = resultPage.replace('<option selected="selected" value="104">Comfort</option>', '<option value="204">Comfort</option>');
  assert.deepEqual(plain(E.settingsFor(E.formsOf(moved).settings, "Comfort")).pairs.find(p => p[0] === "seat"), ["seat", "204"]);
  // age 3 or Business on the page means the settings must be sent again
  const aged = resultPage.replace('<option value="3">3 year(s)</option>', '<option selected="selected" value="3">3 year(s)</option>').replace('<option selected="selected" value="0">0 year(s)</option>', '<option value="0">0 year(s)</option>');
  assert.equal(plain(E.settingsFor(E.formsOf(aged).settings, "Comfort")).ok, false);
  assert.match(plain(E.settingsFor(E.formsOf(resultPage).settings, "Slimline")).problem, /no Slimline/);
});

// ---------------------------------------------------------------- the table
await check("the form page's empty table (\"Please select the aircraft types…\") reads as no rows", () => {
  assert.deepEqual(plain(E.tableOf(formPage)), { rows: [], problems: [] });
});
const table = plain(E.tableOf(resultPage));
await check("the result page's three rows: two cannot operate, with the game's type ids", () => {
  assert.deepEqual(table.problems, []);
  assert.deepEqual(table.rows.map(r => [r.type_name, r.game_type_id, r.can_operate]),
    [["Airbus A321NEO Light", 3155, false], ["Airbus A350-900", 3921, true], ["Embraer 195 E2", 20260, false]]);
  for (const r of [table.rows[0], table.rows[2]]) {
    assert.equal(r.message, "This type cannot operate on the selected relation.");
    assert.equal(r.seats, null); assert.equal(r.profit_50, null); assert.equal(r.margin_100, null);
    assert.deepEqual(r.cells, [r.type_name, "This type cannot operate on the selected relation."]);
  }
});
await check("the A350-900's 17 figures exactly, the profits and margins from −30,422 (−17%) to 143,458 (41%)", () => {
  const r = table.rows[1];
  assert.deepEqual([r.flights_week, r.seats, r.fuel, r.handling, r.atc, r.landing, r.maintenance, r.capital, r.crew, r.fixed_total, r.per_seat],
    [6, 377, 64305, 631, 3014, 1592, 11949, 116764, 5128, 203382, 539]);
  assert.deepEqual([50, 60, 70, 80, 90, 100].map(l => [r["profit_" + l], r["margin_" + l]]),
    [[-30422, -17], [4538, 2], [38578, 16], [73538, 26], [108498, 34], [143458, 41]]);
  assert.deepEqual(r.cells, ["Airbus A350-900", "6.00", "377", "64,305", "631", "3,014", "1,592", "11,949", "116,764", "5,128", "203,382", "539 AS$",
    "-30,422 (-17%)", "4,538 (2%)", "38,578 (16%)", "73,538 (26%)", "108,498 (34%)", "143,458 (41%)"]);
});
await check("numbers as the tool writes them, and what isn't one", () => {
  assert.equal(E.num("64,305"), 64305); assert.equal(E.num("6.00"), 6); assert.equal(E.num("539 AS$"), 539);
  assert.equal(E.num("−1,592"), -1592); assert.equal(E.num("-17%"), -17); assert.equal(E.num("1,234,567"), 1234567);
  for (const s of ["", "n/a", "12,34", "1.2.3", "AS$"]) assert.equal(E.num(s), null, s);
  assert.deepEqual(plain(E.profit("-30,422 (-17%)")), { profit: -30422, margin: -17 });
  assert.equal(E.profit("-30,422"), null); assert.equal(E.profit("-30,422 (-17)"), null);
});
await check("a row that doesn't read is a problem, not a row: a figure that isn't a number, a cell missing, a changed layout", () => {
  const bad = resultPage.replace('<td class="number">64,305</td>', '<td class="number">n/a</td>');
  const t = plain(E.tableOf(bad));
  assert.equal(t.rows.length, 2); assert.equal(t.problems[0].type, "Airbus A350-900"); assert.match(t.problems[0].why, /not a number: Fuel "n\/a"/);
  const short = plain(E.tableOf(resultPage.replace('<td class="number">64,305</td>', "")));
  assert.match(short.problems[0].why, /16 cells, not 17/);
  const cols = plain(E.tableOf(resultPage.replace("<th>Fuel</th>", "<th>Fuel cost</th>")));
  assert.match(cols.problems[0].why, /columns aren't the ones the script knows/);
});

// ---------------------------------------------------------------- the add list
await check("the add list matched by text: on the form page all 17 are in the list, at their positions", () => {
  const add = E.formsOf(formPage).add;
  assert.deepEqual(plain(E.missingTypes(E.tableOf(formPage), TYPES)), TYPES);
  assert.deepEqual(plain(E.addValues(add, TYPES)).values, ["38", "39", "40", "41", "48", "49", "50", "51", "52", "53", "54", "55", "72", "73", "74", "256", "261"]);
});
await check("on the result page the three added aren't in the list, the values have shifted, and 14 types are missing", () => {
  const add = E.formsOf(resultPage).add;
  for (const n of ["Airbus A321NEO Light", "Airbus A350-900", "Embraer 195 E2"]) assert.match(plain(E.addValues(add, [n])).problem, /isn't in the tool's add list/);
  const missing = plain(E.missingTypes(E.tableOf(resultPage), TYPES));
  assert.equal(missing.length, 14);
  assert.ok(!missing.includes("Airbus A350-900") && missing.includes("Airbus A350-900ULR") && missing.includes("Embraer 190 E2"));
  const v = plain(E.addValues(add, missing)).values;
  assert.equal(v.length, 14);
  assert.equal(v[missing.indexOf("Airbus A350-900ULR")], "72");   // 74 on the form page
  assert.equal(v[missing.indexOf("Embraer 190 E2")], "254");      // 256 on the form page
});
await check("a type the add list doesn't have, or has twice, is refused", () => {
  assert.equal(plain(E.addValues(E.formsOf(formPage).add, ["Airbus A999"])).problem, "Airbus A999 isn't in the tool's add list");
  const twice = formPage.replace('<option value="73">Airbus A350-900</option>', '<option value="73">Airbus A350-900</option><option value="999">Airbus A350-900</option>');
  assert.equal(plain(E.addValues(E.formsOf(twice).add, ["Airbus A350-900"])).problem, "Airbus A350-900 is in the tool's add list twice");
});

// ---------------------------------------------------------------- the POST bodies
await check("the three POST bodies from the page's own field names and values (the add form with several types)", () => {
  const f = E.formsOf(resultPage);
  assert.equal(E.routeBody(f.route, "LGW", "CAI"), "from%3Aphrase=LGW&to%3Aphrase=CAI");
  assert.equal(E.addBody(f.add, ["72", "254"]), "types=72&types=254");
  assert.equal(E.settingsBody(plain(E.settingsFor(f.settings, "Leisure Plus")).pairs), "age=0&serviceClass=2&seat=103&priceFactor=100");
  // a hidden field in the form goes with it
  const hidden = resultPage.replace('<div id="id6ef_hf_0" hidden="" class="hidden-fields"></div>', '<div id="id6ef_hf_0" hidden="" class="hidden-fields"><input type="hidden" name="id6ef_hf_0" value=""></div>');
  assert.equal(E.addBody(E.formsOf(hidden).add, ["72"]), "id6ef_hf_0=&types=72");
});
await check("a form's action resolved against its page; one that doesn't post back to the tool is refused", () => {
  assert.equal(E.actionUrl("./evaluation?138-6.-evaluation-add", BASE + "?138"), BASE + "?138-6.-evaluation-add");
  assert.equal(E.actionUrl("./evaluation?138-6.-evaluation-add", BASE + ";jsessionid=ABC?138"), BASE + "?138-6.-evaluation-add");
  assert.equal(E.actionUrl("../../action/enterprise/aircraftsType?id=3921", BASE + "?138"), null);
  assert.equal(E.actionUrl("/app/enterprise/dashboard", BASE), null);
});

// ---------------------------------------------------------------- the result as it's sent
await check("a missing type and a page without the table are refused; the three-type page is short of 14", () => {
  assert.match(plain(E.resultOf(resultPage, TYPES, "Comfort")).problem, /^the result didn't read: no row for Airbus A320NEO, /);
  assert.equal(plain(E.resultOf("<html><body><form action=\"/login\"></form></body></html>", TYPES, "Comfort")).problem, "the result didn't read: the page has no comparison table");
  const three = ["Airbus A321NEO Light", "Airbus A350-900", "Embraer 195 E2"];
  const r = plain(E.resultOf(resultPage, three, "Comfort"));
  assert.equal(r.canFly, 1);
  assert.deepEqual(Object.keys(r.doc), ["from_name", "to_name", "settings", "rows"]);
  assert.equal(r.doc.from_name, "New York John F. Kennedy"); assert.equal(r.doc.rows.length, 3);
  assert.deepEqual(r.doc.settings, { age: "0 year(s)", class: "Economy", seat: "Comfort", price_factor: "100%" });
  assert.match(plain(E.resultOf(resultPage, three, "Leisure")).problem, /shows seat Comfort, not Leisure/);
});

// ---------------------------------------------------------------- whole runs, against a stand-in for the game
// The tool's pages as the game would answer: each answer a new page version, its forms' actions tied to it.
const version = (html, from, to) => html.replaceAll(`?${from}.`, `?${to}.`);
const rowsOf = html => html.match(/<tbody>[\s\S]*?<\/tbody>/)[0].split(/(?=<tr>)/).filter(x => x.startsWith("<tr>"));
const [cannotRow, a350Row] = rowsOf(resultPage);
// the result page with all 17 types in the table (the first two can't operate) and gone from the add list
function full17(seat, v) {
  let n = 0;
  const rows = TYPES.map((t, i) => (i < 2 ? cannotRow.replace("Airbus A321NEO Light", t) : a350Row.replace("Airbus A350-900", t).replace("id=3921", "id=" + (5000 + i)))
    .replace(/evaluations-\d+-remove/, () => `evaluations-${n++}-remove`)).join("");
  let html = resultPage.replace(/<tbody>[\s\S]*?<\/tbody>/, "<tbody>" + rows + "</tbody>");
  for (const t of TYPES) html = html.replace(new RegExp(`<option value="\\d+">${t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}</option>\\n`), "");
  html = html.replace('<option selected="selected" value="104">Comfort</option>', '<option value="104">Comfort</option>')
             .replace(new RegExp(`<option value="(\\d+)">${seat}</option>`), `<option selected="selected" value="$1">${seat}</option>`);
  return version(html, "138-6", v);
}
// a stand-in for the game: answers each POST from its handler (by the form the address names), keeps every request
function game(handlers) {
  const sent = [], slept = [], saved = [];
  let n = 200;
  return {
    sent, slept, saved,
    io: {
      post: async (url, body) => {
        sent.push({ url, body });
        const kind = /aircraft\.eval\.route\.form$/.test(url) ? "route" : /evaluation-add$/.test(url) ? "add" : /evaluation-settings$/.test(url) ? "settings" : "other";
        const a = handlers[kind] ? handlers[kind](body, ++n) : { ok: false, status: 404, url, html: "" };
        return Object.assign({ ok: true, status: 200, url: BASE + "?" + n }, a);
      },
      sleep: async ms => { slept.push(ms); },
      save: async doc => { saved.push(doc); return handlers.save ? handlers.save(doc) : { ok: true, run: 1, saved: doc.rows.length, done: 1, total: 520 }; }
    }
  };
}
const run = (from, to, seat) => ({ id: 7, pass: 1, seq: 1, from, to, seat });

await check("a first run: route, then the 17 types added, then Leisure set, then saved; each form from the latest page", async () => {
  const g = game({
    route: (b, n) => ({ html: version(formPage, "134-2", `${n}-3`) }),
    add: (b, n) => ({ html: full17("Standard", `${n}-4`) }),
    settings: (b, n) => ({ html: full17("Leisure", `${n}-5`) })
  });
  const r = plain(await E.runOne(run("JFK", "SGN", "Leisure"), TYPES, { html: formPage, url: BASE + "?134" }, g.io));
  assert.deepEqual(g.sent.map(x => x.url), [BASE + "?134-2.-aircraft.eval.route.form", BASE + "?201-3.-evaluation-add", BASE + "?202-4.-evaluation-settings"]);
  assert.equal(g.sent[0].body, "from%3Aphrase=JFK&to%3Aphrase=SGN");
  assert.equal(g.sent[1].body, "types=38&types=39&types=40&types=41&types=48&types=49&types=50&types=51&types=52&types=53&types=54&types=55&types=72&types=73&types=74&types=256&types=261");
  assert.equal(g.sent[2].body, "age=0&serviceClass=2&seat=102&priceFactor=100");
  assert.deepEqual(g.slept, [500, 500], "half a second between the POSTs inside a run");
  assert.equal(g.saved.length, 1);
  assert.equal(g.saved[0].rows.length, 17); assert.equal(g.saved[0].settings.seat, "Leisure");
  assert.equal(r.canFly, 15); assert.equal(r.page.url, BASE + "?203");
});
await check("the next run on the same seat: only the route is sent, from the latest page's action", async () => {
  const start = { html: full17("Leisure", "203-5"), url: BASE + "?203" };
  const g = game({ route: (b, n) => ({ html: full17("Leisure", `${n}-6`) }) });
  await E.runOne(run("LGW", "CAI", "Leisure"), TYPES, start, g.io);
  assert.deepEqual(g.sent, [{ url: BASE + "?203-5.-aircraft.eval.route.form", body: "from%3Aphrase=LGW&to%3Aphrase=CAI" }]);
  assert.deepEqual(g.slept, []); assert.equal(g.saved.length, 1);
});
await check("a seat change (Leisure to Leisure Plus): route, then settings only", async () => {
  const g = game({ route: (b, n) => ({ html: full17("Leisure", `${n}-6`) }), settings: (b, n) => ({ html: full17("Leisure Plus", `${n}-7`) }) });
  await E.runOne(run("LGW", "CAI", "Leisure Plus"), TYPES, { html: full17("Leisure", "203-5"), url: BASE + "?203" }, g.io);
  assert.deepEqual(g.sent.map(x => x.url.replace(BASE, "")), ["?203-5.-aircraft.eval.route.form", "?201-6.-evaluation-settings"]);
  assert.equal(g.sent[1].body, "age=0&serviceClass=2&seat=103&priceFactor=100");
});
const stops = async (handlers, r, start = { html: full17("Leisure", "203-5"), url: BASE + "?203" }) => {
  const g = game(handlers);
  try { await E.runOne(r, TYPES, start, g.io); } catch (e) { return { why: e.message, g }; }
  throw new Error("it didn't stop");
};
await check("it stops, saying why: the route not taken, a type it can't add, settings that don't take", async () => {
  const notTaken = full17("Leisure", "204-6").replace('value="New York John F. Kennedy"', 'value="LGW"').replace(/<h2>[\s\S]*?<\/h2>/, "");
  assert.equal((await stops({ route: () => ({ html: notTaken }) }, run("LGW", "CAI", "Leisure"))).why, "the tool didn't take LGW to CAI");
  const noE195 = version(formPage, "134-2", "204-3").replace('<option value="261">Embraer 195 E2</option>', "");
  const a = await stops({ route: () => ({ html: noE195 }) }, run("JFK", "SGN", "Leisure"));
  assert.equal(a.why, "Embraer 195 E2 isn't in the tool's add list"); assert.equal(a.g.sent.length, 1);
  const b = await stops({ route: () => ({ html: version(formPage, "134-2", "204-3") }), add: () => ({ html: version(resultPage, "138-6", "205-4") }) }, run("JFK", "SGN", "Comfort"));
  assert.match(b.why, /^still not in the table after adding: Airbus A320NEO, /);
  const c = await stops({ route: () => ({ html: full17("Leisure", "204-6") }), settings: () => ({ html: full17("Leisure", "205-7") }) }, run("LGW", "CAI", "Comfort"));
  assert.match(c.why, /^the settings didn't take \(the page shows .*"seat":"Leisure"/);
});
await check("it stops, saying why: the session lost, an HTTP error, a result that doesn't read, the database refusing", async () => {
  assert.match((await stops({ route: () => ({ html: "<html><body>Please sign in</body></html>" }) }, run("LGW", "CAI", "Leisure"))).why, /wasn't the tool's page: the session may have been lost/);
  assert.match((await stops({ route: () => ({ html: "", url: "https://gander.airlinesim.aero/app/login" }) }, run("LGW", "CAI", "Leisure"))).why, /sent it to \/app\/login: the session may have been lost/);
  assert.equal((await stops({ route: () => ({ ok: false, status: 500, html: "" }) }, run("LGW", "CAI", "Leisure"))).why, "the game answered HTTP 500");
  const broken = full17("Leisure", "204-6").replace('<td class="number">64,305</td>', '<td class="number">—</td>');
  assert.match((await stops({ route: () => ({ html: broken }) }, run("LGW", "CAI", "Leisure"))).why, /^the result didn't read: Airbus A320NEO Light \(not a number: Fuel "—"\)$/);
  const refused = await stops({ route: () => ({ html: full17("Leisure", "204-6") }), save: () => ({ ok: false, error: "the result has no row for Embraer 195 E2" }) }, run("LGW", "CAI", "Leisure"));
  assert.equal(refused.why, "the database didn't save it: the result has no row for Embraer 195 E2");
  assert.match((await stops({}, run("LGW", "CAI", "Leisure"), { html: "<html></html>", url: BASE })).why, /route form isn't on the page/);
});

// ---------------------------------------------------------------- the list from the database
await check("capture_eval_runs()'s answer read, and its errors", () => {
  const doc = { ok: true, world: "Gander", types: TYPES, total: 520, done: 308,
    runs: [{ id: 11, pass: 1, seq: 20, from: "LGW", to: "CAI", seat: "Leisure Plus" }, { id: 12, pass: 4, seq: 1, from: "STN", to: "DUB", seat: "Standard" }] };
  const p = plain(E.planOf(doc));
  assert.equal(p.world, "Gander"); assert.equal(p.total, 520); assert.equal(p.done, 308); assert.equal(p.types.length, 17);
  assert.deepEqual(p.runs.map(r => r.id), [11, 12]); assert.deepEqual(p.problems, []);
  assert.equal(plain(E.planOf({ ok: false, error: "bad key" })).error, "bad key");
  assert.equal(plain(E.planOf({ code: "57014", message: "canceling statement due to statement timeout" })).error, "canceling statement due to statement timeout");
  assert.equal(plain(E.planOf(null)).error, "no answer");
  assert.equal(plain(E.planOf({ ...doc, types: [] })).error, "the answer has no list of types");
  assert.match(plain(E.planOf({ ...doc, runs: [{ id: 1, from: "LGW", to: "CAI", seat: "Comfort Plus" }] })).problems[0].why, /seat the script doesn't know/);
  assert.match(plain(E.planOf({ ...doc, runs: [{ id: 1, from: "LG", to: "CAI", seat: "Leisure" }] })).problems[0].why, /two airport codes/);
});
await check("the panel's words: the question, progress, the end", () => {
  assert.equal(E.askWords(212, 520), "212 runs left of 520, about 15 minutes. Leave this tab open and watch; Stop is here throughout. It only reads the tool: nothing in the game changes.");
  assert.equal(E.progressWords(37, 212, run("LGW", "CAI", "Leisure Plus"), 14), "Run 37 of 212: LGW to CAI, Leisure Plus · 14 can fly");
  assert.equal(E.endWords(212, 0, null), "Done: 212 runs saved. Every run on the list has its result.");
  assert.equal(E.endWords(36, 176, "the tool didn't take LGW to CAI", { i: 37, n: 212, run: run("LGW", "CAI", "Leisure Plus") }),
    "Stopped. 36 runs saved.\nAt run 37 of 212: LGW to CAI, Leisure Plus.\nWhy: the tool didn't take LGW to CAI.\n\nWhat's saved stays saved: press Aircraft evaluation again to carry on from the first run without a result.");
});

// ---------------------------------------------------------------- the file itself
const code = source.replace(/^\s*\/\/.*$/gm, "");
await check("the file: a userscript for the tool's page with a version, the key a placeholder, the public key only", () => {
  assert.match(source, /^\/\/ ==UserScript==/);
  assert.match(source, /^\/\/ @match\s+https:\/\/gander\.airlinesim\.aero\/app\/aircraft\/evaluation\*$/m);
  assert.match(source, /^\/\/ @version\s+\d+\.\d+$/m);
  assert.match(source, /const KEY = "__CAPTURE_KEY__"/);
  assert.match(source, /rpc\("capture_eval_runs", \{ p_key: KEY \}\)/);
  assert.match(source, /rpc\("capture_eval_result", \{ p_key: KEY, p_run: run\.id, p_doc: doc \}\)/);
});
await check("the file: 2 seconds between runs, half a second between POSTs, no browser dialogs", () => {
  assert.equal(E.PAUSE_MS, 2000); assert.equal(E.POST_PAUSE_MS, 500);
  assert.ok(!/\b(?:alert|confirm|prompt)\s*\(/.test(code), "alert, confirm or prompt used");
});
await check("the file: read only: no other page of the game, no page loads, the only game requests the tool's form POSTs", () => {
  const paths = [...code.matchAll(/["'`](\/(?:app|action)\/[^"'`?$]*)/g)].map(m => m[1]);
  assert.deepEqual([...new Set(paths)], ["/app/aircraft/evaluation"]);
  assert.ok(!/location\.(?:href\s*=|assign|replace)|\.submit\(\)|window\.open/.test(code), "a page load or a form submitted by the page");
  const fetches = [...code.matchAll(/fetch\(([^,)]+)/g)].map(m => m[1].trim());
  assert.deepEqual(fetches.sort(), ["RPC + fn", "url"], "fetch called with something else: " + fetches.join(", "));
  assert.ok(/const url = actionUrl\(action, page\.url\);\s*if \(!url\) throw/.test(code), "a form is sent without checking it posts back to the tool");
});

console.log(failures ? `\n${failures} aircraft evaluation userscript check(s) failed` : "\naircraft evaluation userscript: all passed");
process.exit(failures ? 1 : 0);
