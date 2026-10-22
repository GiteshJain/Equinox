// The world scan in the capture (capture/capture_all.user.js 1.5, now 1.6; spec docs/specs/2026-10-21-scan-in-capture.md §2, §3)
// on the game's pages, with no browser and no game: the script's own file runs in Node, where (with no page) it only
// hands over its logic (eqScan). On three saved samples:
//   - one letter page of the airline list, hand-made from gscan.py's patterns (tests/fixtures/scan_letter_K_2026-10-21.html);
//   - one airline's schedule page, saved from the game signed out (tests/fixtures/game_schedule_113.html.gz, Kingfisher,
//     the schedule check's sample);
//   - one airport page, hand-made from gscan.py's patterns (tests/fixtures/scan_airport_DEL_2026-10-21.html).
// The same rows must come out as from gscan.py's own rules: tests/gscan_reference.py runs scripts/scanner/gscan.py,
// unchanged, on the same pages (no network, no files) and the test compares what each would send: the airline list, the
// airport ids, the airline's payload, the airport's payload and the finish. Then: the airports to read in the migration
// are gscan.py's list; the scan's words, pace and 10% rule; and the file: a userscript with version 1.6 (since the fleet capture, 22 Oct), the capture key a
// placeholder, capture_scan() with it, no browser dialogs and only the game addresses it needs.
// Usage: node tests/capture_scan_test.mjs
import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import { spawnSync } from "node:child_process";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const read = p => readFileSync(new URL(p, here), "utf8");
const source = read("../capture/capture_all.user.js");
const letterK = read("fixtures/scan_letter_K_2026-10-21.html");
const schedule113 = gunzipSync(readFileSync(new URL("fixtures/game_schedule_113.html.gz", here))).toString("utf8");
const airportDEL = read("fixtures/scan_airport_DEL_2026-10-21.html");
const gscan = read("../scripts/scanner/gscan.py");
const migration = read("../database/migrations/20261021233000_scan_in_capture.sql");

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "capture/capture_all.user.js" });
const S = sandbox.eqScan;
// values made inside the script's own context compare by their JSON
const plain = v => JSON.parse(JSON.stringify(v));

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

// ---------------------------------------------------------------- gscan.py on the same pages
const GAME = "https://gander.airlinesim.aero";
const SCAN = 7;
const pages = { [GAME + S.letterUrl("K")]: letterK, [GAME + S.airlineUrl(113)]: schedule113, [GAME + S.airportUrl(1143)]: airportDEL };
const ran = spawnSync("python3", ["-I", new URL("gscan_reference.py", here).pathname], { input: JSON.stringify({ scan: SCAN, pages }), encoding: "utf8", maxBuffer: 1 << 26 });
let ref = null;
await check("gscan.py runs, unchanged, on the saved pages (tests/gscan_reference.py)", () => {
  assert.equal(ran.status, 0, "gscan_reference.py failed: " + (ran.stderr || ran.error));
  ref = JSON.parse(ran.stdout);
  assert.ok(ref.sent.some(x => x.kind === "airline") && ref.sent.some(x => x.kind === "airport") && ref.sent.some(x => x.kind === "finish"),
    "gscan.py didn't send an airline, an airport and finish: " + ref.log.join(" / "));
});
const sentOf = kind => (ref ? ref.sent.filter(x => x.kind === kind).map(x => x.payload) : []);

await check("the script hands over its logic in Node and touches no page", () => {
  assert.ok(S, "eqScan isn't there");
  for (const f of ["readLetterPage", "readSchedulePage", "readAirportPage", "airlinePayload", "airportPayload", "finishPayload", "tooManyFailed", "planOf"])
    assert.equal(typeof S[f], "function", f);
  assert.equal(S.letterUrl("A"), "/app/info/enterprises?letter=A");
  assert.equal(S.airlineUrl(113), "/app/info/enterprises/113?tab=3");
  assert.equal(S.airportUrl(1143), "/app/info/airports/1143");
});

// ---------------------------------------------------------------- 1. the airline list
await check("a letter page: the airlines as gscan.py reads them (game ID and name, the later name winning)", () => {
  const byId = plain(S.addAirlines({}, S.readLetterPage(letterK)));
  const want = Object.fromEntries(Object.entries(ref.ents).map(([k, v]) => [Number(k), v]));
  assert.deepEqual(byId, plain(want));
  assert.deepEqual(plain(S.airlineList(byId)), [[52, "Korean Air Lines"], [88, "Kölner Luftverkehr"], [113, "Kingfisher Airlines"], [171, "KLM Royal Dutch Airlines"],
    [1404, "King's Wings"], [1999, "Kenya Airways Ltd"], [2042, "Kiwi & Co Air"]]);
});
await check("the airline list: every letter's airlines together, in gscan.py's order (by game ID)", () => {
  const a = S.addAirlines({}, [[300, "Alpha"], [12, "Aero"]]), b = S.addAirlines(a, [[113, "Kingfisher Airlines"], [12, "Aero Two"]]);
  assert.deepEqual(plain(S.airlineList(b)), [[12, "Aero Two"], [113, "Kingfisher Airlines"], [300, "Alpha"]]);
  assert.deepEqual(plain(S.airlineList({})), []);
  assert.deepEqual(plain(S.readLetterPage("<html><body>Please sign in</body></html>")), []);
});

// ---------------------------------------------------------------- 2. an airline's schedule
const sched = S.readSchedulePage(schedule113);
await check("an airline's schedule page: its flights, as gscan.py sends them (every field of every row)", () => {
  const theirs = sentOf("airline");
  assert.equal(theirs.length, 1, "gscan.py should have sent one airline (113), sent " + theirs.length);
  const mine = plain(S.airlinePayload(SCAN, 113, ref.ents["113"], sched.flights));
  assert.deepEqual(mine, theirs[0]);
  assert.equal(mine.n_flights, 48); assert.equal(mine.flights[0].length, 9);
  assert.deepEqual(mine.flights[0], ["KF", "1048", "AMD", "DEL", "1234567", "21:58", "23:17", "32N", "Kingfisher Airlines"]);
});
await check("an airline's schedule page: the airport ids it links, as gscan.py learns them", () => {
  assert.deepEqual(plain(sched.airports), ref.apid);
  assert.equal(sched.airports.DEL, 1143); assert.equal(sched.airports.JFK, 3551); assert.equal(sched.airports.LHR, 1054);
});
await check("an airline's schedule page without a table, or with no flights: nothing read, counted as gscan.py counts", () => {
  assert.deepEqual(plain(S.readSchedulePage("<html><body>Please sign in</body></html>")), { flights: [], airports: {} });
  const p = plain(S.airlinePayload(SCAN, 5, "Empty Air", []));
  assert.deepEqual(p, { snapshot_id: SCAN, enterprise_id: 5, name: "Empty Air", flights: [], n_flights: 0, n_weekly: 0, n_airports: 0 });
  const two = plain(S.airlinePayload(SCAN, 6, "Two", [["TW", "1", "AAA", "BBB", "135", "08:00", "09:00", "32N", ""], ["TW", "2", "BBB", "AAA", "135", "10:00", "11:00", "32N", ""]]));
  assert.equal(two.n_weekly, 6); assert.equal(two.n_airports, 2);
});

// ---------------------------------------------------------------- 3. an airport
await check("an airport page: its details, stations and news, as gscan.py sends them", () => {
  const theirs = sentOf("airport");
  assert.equal(theirs.length, 1, "gscan.py should have sent one airport (DEL), sent " + theirs.length);
  const mine = plain(S.airportPayload(SCAN, "DEL", sched.airports.DEL, S.readAirportPage(airportDEL)));
  assert.deepEqual(mine, theirs[0]);
  assert.deepEqual(mine.info, { size: "Mega airport", slots_per_5min: "22", slot_availability: "91%", min_transfer: "01:15 h",
                                night_ban: "no nighttime ban", runway: "4,430 m", country: "India", continent: "Asia" });
  assert.deepEqual(mine.stations.map(s => [s.enterprise_id, s.name, s.weekly, s.alliance, s.interline]),
    [[113, "Kingfisher Airlines", 1204, 204, true], [76, "Air India", 356, null, false], [57, "United Airlines", 14, 93, true], [2042, "Kiwi & Co Air", 7, null, true]]);
  assert.deepEqual(mine.news, [{ at: "2026-10-20 21:14", text: "Kingfisher Airlines has opened a new station at Kolkata ." },
                               { at: "2026-10-19 08:02", text: "Air India has opened a new station at Delhi ." }]);
});
await check("an airport page that isn't one: no details, stations or news", () => {
  const p = plain(S.readAirportPage("<html><body>Please sign in</body></html>"));
  assert.ok(Object.values(p.info).every(v => v === null)); assert.deepEqual(p.stations, []); assert.deepEqual(p.news, []);
});

// ---------------------------------------------------------------- 4. finish, and what to read
await check("finish: gscan.py's note, with what the capture's scan adds", () => {
  const theirs = sentOf("finish");
  assert.equal(theirs.length, 1);
  const hubs = gscanHubs();
  const mine = plain(S.finishPayload(SCAN, Object.keys(ref.ents).length, hubs.length, 6, 50));
  assert.equal(mine.snapshot_id, theirs[0].snapshot_id);
  assert.ok(mine.note.startsWith(theirs[0].note + " "), `the note "${mine.note}" doesn't start with gscan.py's "${theirs[0].note}"`);
  assert.match(mine.note, /\(Capture all airlines 1\.6; 6 airline pages failed, 50 airports without an id\)$/);
  assert.match(plain(S.finishPayload(SCAN, 163, 77, 1, 1)).note, /^full scan: 163 enterprises, 77 airports \(Capture all airlines 1\.6; 1 airline page failed, 1 airport without an id\)$/);
});
function gscanHubs() { const m = gscan.match(/^AP="([A-Z0-9 ]+)"\.split\(\)/m); assert.ok(m, "gscan.py's airport list (AP) not found"); return m[1].split(" "); }
await check("the airports to read: the migration's big rival hubs are gscan.py's list, in its order", () => {
  const m = migration.match(/c_hubs constant text\[\] := array\[([^\]]+)\]/);
  assert.ok(m, "the migration's hub list not found");
  assert.deepEqual([...m[1].matchAll(/'([A-Z0-9]{3})'/g)].map(x => x[1]), gscanHubs());
});
await check("capture_airlines()'s answer read: due, open, the setting, the latest scan and the airports", () => {
  const p = plain(S.planOf({ ok: true, scan_due: true, scan_open: null, scan_every_days: 1, scan_latest: { id: 4, taken_at: "2026-10-20T01:02:03.000Z" },
                             scan_airports: ["DEL", "BOM", "JFK", "bad", ""] }));
  assert.deepEqual(p, { due: true, open: null, every: 1, latest: { id: 4, taken_at: "2026-10-20T01:02:03.000Z" }, airports: ["DEL", "BOM", "JFK"] });
  assert.deepEqual(plain(S.planOf({ ok: true, scan_due: false, scan_open: 9, scan_every_days: 3 })), { due: false, open: 9, every: 3, latest: null, airports: [] });
  assert.equal(S.planOf({ ok: true, airlines: [] }).due, false, "an answer from before 1.5's database (no scan_due) isn't a due scan");
});

// ---------------------------------------------------------------- 5. the scan's words, pace and rules
await check("no scan tonight: not due, no setting, or a capture page failed; otherwise it runs", () => {
  const due = { due: true, open: null, every: 1, latest: null, airports: [] };
  assert.equal(S.noScanWords(due, 0), null);
  assert.equal(S.noScanWords({ ...due, due: false, latest: { id: 4, taken_at: "2026-10-21T01:30:00.000Z" } }, 0),
    "World scan: not due; the last finished 2026-10-21 01:30 UTC (every 1 day).");
  assert.equal(S.noScanWords({ ...due, every: null, due: false }, 0), "World scan: off (the world has no scan_every_days setting).");
  assert.equal(S.noScanWords(due, 2), "World scan: not tonight, because 2 capture pages failed. Capture again; the scan follows while it's due.");
  assert.equal(S.noScanWords(due, 1), "World scan: not tonight, because 1 capture page failed. Capture again; the scan follows while it's due.");
});
await check("the panel's progress: \"World scan: 120 of 163 airlines…\"", () => {
  assert.equal(S.progressWords({ step: "letters", li: 10 }), "World scan: reading the airline list, letter K of 26…");
  assert.equal(S.progressWords({ step: "airlines", ai: 120, list: new Array(163) }), "World scan: 120 of 163 airlines…");
  assert.equal(S.progressWords({ step: "airports", pi: 12, list: new Array(163), airports: new Array(70) }), "World scan: 163 airlines read; airports, 12 of 70…");
});
await check("more than 10% of the airlines failed (or none read): not finished", () => {
  assert.equal(S.tooManyFailed(0, 163), false); assert.equal(S.tooManyFailed(16, 163), false);
  assert.equal(S.tooManyFailed(17, 163), true); assert.equal(S.tooManyFailed(0, 0), true);
  assert.equal(S.tooManyFailed(1, 10), false); assert.equal(S.tooManyFailed(2, 10), true);
});
await check("gscan.py's pace: 0.4 s between letter pages, 0.5 s between airlines, 0.25 s between airports", () => {
  assert.deepEqual(plain(S.PACE), { letter: 400, airline: 500, airport: 250 });
  assert.match(gscan, /time\.sleep\(0\.4\)/); assert.match(gscan, /time\.sleep\(0\.5\)/); assert.match(gscan, /time\.sleep\(0\.25\)/);
  assert.equal(S.LETTERS, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
});
await check("the scan's week: the ISO week of the capture (UTC)", () => {
  assert.equal(S.isoWeek(new Date("2026-10-21T23:00:00Z")), "43");
  assert.equal(S.isoWeek(new Date("2026-10-19T00:30:00Z")), "43");
  assert.equal(S.isoWeek(new Date("2026-10-18T23:59:00Z")), "42");
  assert.equal(S.isoWeek(new Date("2027-01-01T12:00:00Z")), "53");
});
await check("html.unescape() as Python does it: numeric references, the usual names, and an unknown one left alone without a page", () => {
  assert.equal(S.unescape("Kiwi &amp; Co &#039;s &#x27;x&#x27; &eacute;t&eacute; &lt;b&gt; &nbsp;|"), "Kiwi & Co 's 'x' été <b>  |");
  assert.equal(S.unescape("&#0; &#xD800; &bogus;"), "� � &bogus;");
  assert.equal(S.text("  <b>from</b>\n <span>Delhi</span> (<a href=\"x\">DEL</a>)  "), "from Delhi ( DEL )");
});

// ---------------------------------------------------------------- the file itself
await check("the file: a userscript for the game, version 1.6, the key a placeholder, the public key only, capture_scan() with the key", () => {
  assert.match(source, /^\/\/ ==UserScript==/);
  assert.match(source, /^\/\/ @match\s+https:\/\/gander\.airlinesim\.aero\/\*$/m);
  assert.match(source, /^\/\/ @version\s+1\.6$/m);
  assert.equal(S.VERSION, "1.6", "the scan's notes name another version than @version");
  assert.match(source, /const KEY = "__CAPTURE_KEY__"/);
  assert.match(source, /RPC \+ "capture_scan"[\s\S]{0,300}p_key: KEY, p_kind: kind, p_payload: payload/);
  assert.match(source, /rpc\("capture_airlines", \{ p_key: KEY \}\)/);
  assert.match(source, /rpc\("capture_ingest", \{ p_key: KEY, p_airline: String\(gameId\), p_kind: kind, p_page: page, p_rows: rows \}\)/);
});
await check("the file: no browser dialogs, no POST to the game, and only the game addresses it needs", () => {
  assert.ok(!/\b(?:alert|confirm|prompt)\s*\(/.test(source.replace(/^\s*\/\/.*$/gm, "")), "alert, confirm or prompt used");
  const paths = [...source.matchAll(/["'`](\/(?:app|action)\/[^"'`?$]*)/g)].map(m => m[1]);
  assert.deepEqual([...new Set(paths)].sort(), ["/action/enterprise/schedule", "/app/com/loads", "/app/enterprise/dashboard", "/app/finance/accounting/0",
    "/app/finance/accounting/1", "/app/finance/accounting/2", "/app/fleets", "/app/fleets/", "/app/info/airports/", "/app/info/enterprises", "/app/info/enterprises/"]);
  assert.ok(!/method:\s*["']POST["'][^}]*airlinesim/i.test(source), "a POST to the game");
});

console.log(failures ? `\n${failures} capture scan check(s) failed` : "\ncapture scan: all passed");
process.exit(failures ? 1 : 0);
