// The fleet pages in the capture (capture/capture_all.user.js 1.6; spec docs/specs/2026-10-22-fleet-capture.md §1), on a
// saved page, with no browser and no game: the script's own file runs in Node, where (with no page) it only hands over
// its logic (eqScan), as tests/capture_scan_test.mjs runs it. The sample is Pan Am's JFK fleet as Gitesh saved it from
// the game on 22 Oct (tests/fixtures/fleet_JFK_2026-10-22.html, 19 aircraft), scrubbed of the session (the user's name,
// the page's scripts and settings, the page versions in links); its aircraft rows are as saved.
//   1. The page: the airline's fleets (the list on the left, Default included), the fleet shown and every aircraft with
//      each field the database keeps, N003AW's 83% / 103.8% (the brief's), the two aircraft between flights (N004AW,
//      N020AW) on the ground at their airport.
//   2. The same page as the game serves it to the capture (links relative to the page, not the saved copy's full
//      addresses) reads the same; a nickname is read; a page without the fleet table (signed out) gives its error.
//   3. What the capture reads and sends: every fleet with aircraft (Default, JFK, ORD; the empty ones left out), each
//      fleet's address, the page kind fleet's rows (with the run, which page of how many and the airline's fleets; the
//      error in place of the aircraft when it didn't read), and the panel's words ("Pan Am: fleet 2 of 3…" while it reads,
//      then one line for the airline's fleet pages, and one for each page that wasn't ok).
//   4. The file: version 1.6, fleet pages sent to capture_ingest() with the key as kind fleet, half a second apart; the
//      sample holds nothing of the session.
// Usage: node tests/capture_fleet_test.mjs
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const read = p => readFileSync(new URL(p, here), "utf8");
const source = read("../capture/capture_all.user.js");
const saved = read("fixtures/fleet_JFK_2026-10-22.html");

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "capture/capture_all.user.js" });
const S = sandbox.eqScan;
const plain = v => JSON.parse(JSON.stringify(v));

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

const page = plain(S.readFleetPage(saved));
const REGS = ["N001AW", "N002AW", "N003AW", "N004AW", "N005AW", "N006AW", "N007AW", "N008AW", "N009AW", "N010AW", "N011AW", "N012AW",
  "N015AW", "N016AW", "N017AW", "N018AW", "N019AW", "N020AW", "N021AW"];

// ---------------------------------------------------------------- 1. the page
await check("the script hands over the fleet pages' logic in Node", () => {
  for (const f of ["readFleetPage", "fleetsToRead", "fleetPayload", "fleetUrl", "fleetProgress", "fleetWords"]) assert.equal(typeof S[f], "function", f);
  assert.equal(S.fleetListUrl, "/app/fleets");
  assert.equal(S.fleetUrl(231), "/app/fleets/231");
  assert.equal(S.fleetUrl(null), "/app/fleets");
});
await check("the fleet list: every fleet with its game id (Default's none) and how many aircraft it holds, in the page's order", () => {
  assert.deepEqual(page.fleets, [
    { id: null, name: "Default", aircraft: 1 }, { id: 233, name: "DFW", aircraft: 0 }, { id: 231, name: "JFK", aircraft: 19 },
    { id: 232, name: "LAX", aircraft: 0 }, { id: 235, name: "ORD", aircraft: 2 }, { id: 236, name: "SEA", aircraft: 0 }, { id: 234, name: "SFO", aircraft: 0 }]);
  assert.equal(page.name, "JFK");
  assert.equal(page.error, undefined);
});
await check("the fleet's 19 aircraft, as many as the list says, each registration in the page's order", () => {
  assert.equal(page.aircraft.length, 19);
  assert.deepEqual(page.aircraft.map(a => a.registration), REGS);
});
await check("an aircraft in the air: every field the database keeps (N001AW, ORD → JFK on AW 1003)", () => {
  assert.deepEqual(page.aircraft[0], { registration: "N001AW", nickname: null, type: "Airbus A321NEO Light", type_id: 3155, from: "ORD", to: "JFK",
    flight: "AW 1003", age_years: 0.1, condition_pct: 91, maintenance_pct: 105.3, y: 180, c: 15, f: 0, pilots: true, owned: false, contract: "active",
    game_id: 1873 });
});
await check("N003AW as the brief has it: 83% condition, 103.8% maintenance after the fix, 180/15/0", () => {
  const a = page.aircraft.find(x => x.registration === "N003AW");
  assert.deepEqual([a.condition_pct, a.maintenance_pct, a.y, a.c, a.f, a.from, a.to, a.flight], [83, 103.8, 180, 15, 0, "ATL", "JFK", "AW 1022"]);
});
await check("an aircraft between flights is on the ground at its airport, with no flight (N004AW at FRA, N020AW at JFK)", () => {
  const n4 = page.aircraft.find(x => x.registration === "N004AW"), n20 = page.aircraft.find(x => x.registration === "N020AW");
  assert.deepEqual([n4.from, n4.to, n4.flight, n4.type, n4.maintenance_pct], ["FRA", null, null, "Airbus A321XLR", 311.1]);
  assert.deepEqual([n20.from, n20.to, n20.flight, n20.type, n20.y, n20.c, n20.f, n20.age_years], ["JFK", null, null, "Embraer 195 E2", 100, 12, 0, 0]);
});
await check("every aircraft has its figures: condition and maintenance read, seats read, pilots yes, leased, contract active", () => {
  for (const a of page.aircraft) {
    assert.ok(Number.isFinite(a.condition_pct) && Number.isFinite(a.maintenance_pct), a.registration + ": condition or maintenance not read");
    assert.ok([a.y, a.c, a.f].every(Number.isInteger), a.registration + ": seats not read");
    assert.deepEqual([a.pilots, a.owned, a.contract], [true, false, "active"], a.registration);
    assert.ok(a.type && Number.isInteger(a.type_id) && Number.isInteger(a.game_id), a.registration + ": type or game id not read");
  }
  assert.equal(page.aircraft.reduce((n, a) => n + a.y + a.c + a.f, 0), 3188, "the seats on the page add up differently");
});

// ---------------------------------------------------------------- 2. the page as the game serves it, a nickname, no table
await check("the page as the game serves it (links relative to /app/fleets/231) reads the same", () => {
  const live = saved.replace(/https:\/\/gander\.airlinesim\.aero\/app\/fleets\//g, "./")
    .replace(/https:\/\/gander\.airlinesim\.aero\/app\/fleets(?=")/g, "../fleets")
    .replace(/https:\/\/gander\.airlinesim\.aero\/app\//g, "../")
    .replace(/https:\/\/gander\.airlinesim\.aero\/action\//g, "../../action/");
  assert.notEqual(live, saved);
  assert.ok(!/href="https:\/\/gander\.airlinesim\.aero\/(app|action)\//.test(live), "a full address was left");
  assert.match(live, /href="\.\/233"/); assert.match(live, /href="\.\.\/info\/airports\/3360"/);
  assert.deepEqual(plain(S.readFleetPage(live)), page);
});
await check("a nickname is read; the game's \"...\" placeholder is none", () => {
  const named = saved.replace(/(<span>N002AW<\/span>\s*<div class="subrow"><span id="[^"]+"><span id="[^"]+">)\.\.\.(<\/span>)/, "$1Clipper Maid$2");
  assert.notEqual(named, saved);
  const got = plain(S.readFleetPage(named)).aircraft;
  assert.equal(got.find(a => a.registration === "N002AW").nickname, "Clipper Maid");
  assert.ok(got.filter(a => a.registration !== "N002AW").every(a => a.nickname === null));
});
await check("a page without the fleet table (signed out, or the page changed): its error, no aircraft", () => {
  assert.deepEqual(plain(S.readFleetPage("<html><body>Please sign in</body></html>")), { name: null, fleets: [], aircraft: [], error: "no fleet table on the page" });
  const noTable = saved.replace(/<thead[\s\S]*?<\/tbody>/, "");
  const got = plain(S.readFleetPage(noTable));
  assert.equal(got.error, "no fleet table on the page"); assert.equal(got.fleets.length, 7);
});

// ---------------------------------------------------------------- 3. what the capture reads and sends
await check("the fleets to read: every fleet with aircraft (Default, JFK, ORD), the empty ones left out, one whose count didn't read kept", () => {
  assert.deepEqual(plain(S.fleetsToRead(page.fleets)).map(f => f.name), ["Default", "JFK", "ORD"]);
  assert.deepEqual(plain(S.fleetsToRead([{ id: 1, name: "X", aircraft: null }, { id: 2, name: "Y", aircraft: 0 }])).map(f => f.name), ["X"]);
  assert.deepEqual(plain(S.fleetsToRead([])), []);
  assert.deepEqual(plain(S.fleetsToRead(undefined)), []);
});
await check("the page kind fleet's rows: the run, which page of how many, the fleet, the airline's fleets and the aircraft", () => {
  const jfk = page.fleets.find(f => f.name === "JFK");
  const p = plain(S.fleetPayload("2026-10-22T23:00:00.000Z", 2, 3, jfk, page.fleets, page));
  assert.deepEqual(Object.keys(p), ["run", "page", "of", "fleet", "fleets", "aircraft"]);
  assert.deepEqual([p.run, p.page, p.of, p.fleet], ["2026-10-22T23:00:00.000Z", 2, 3, { id: 231, name: "JFK" }]);
  assert.equal(p.fleets.length, 7); assert.equal(p.aircraft.length, 19);
  assert.deepEqual(p.aircraft[2], page.aircraft[2]);
});
await check("a page that didn't read is still sent, with its error in place of the aircraft, for the database to judge broken", () => {
  const ord = page.fleets.find(f => f.name === "ORD");
  assert.deepEqual(plain(S.fleetPayload("r", 3, 3, ord, page.fleets, null, "HTTP 502")),
    { run: "r", page: 3, of: 3, fleet: { id: 235, name: "ORD" }, fleets: page.fleets, error: "HTTP 502" });
  assert.equal(plain(S.fleetPayload("r", 1, 1, ord, [], { aircraft: [], error: "no fleet table on the page" })).error, "no fleet table on the page");
  assert.deepEqual(plain(S.fleetPayload("r", 1, 1, null, [], null, "the fleet list didn't read: HTTP 500")),
    { run: "r", page: 1, of: 1, fleet: null, fleets: [], error: "the fleet list didn't read: HTTP 500" });
});
await check("the panel: \"Pan Am: fleet 2 of 3…\" while it reads, then the database's verdict on the page", () => {
  assert.equal(S.fleetProgress("Pan Am", 2, 3), "Pan Am: fleet 2 of 3…");
  assert.equal(S.fleetWords("Pan Am", 2, 3, { ok: true, rows: 19, verdict: { verdict: "ok", note: "fleet JFK 19 aircraft" } }), "Pan Am: fleet 2 of 3 · fleet JFK 19 aircraft");
  assert.equal(S.fleetWords("Pan Am", 1, 3, { ok: true, rows: 1 }), "Pan Am: fleet 1 of 3 · 1 aircraft");
  assert.equal(S.fleetWords("Pan Am", 3, 3, { ok: false, error: "parse: HTTP 502", verdict: { verdict: "broken" } }), "Pan Am: fleet 3 of 3 · didn't read (parse: HTTP 502)");
  assert.equal(S.fleetWords("Pan Am", 1, 1, null), "Pan Am: fleet 1 of 1 · didn't read (no answer)");
});
await check("the panel: each airline's fleet pages in one line once sent (a page that wasn't ok also has its own line)", () => {
  const ok = n => ({ ok: true, rows: n, verdict: { verdict: "ok" } });
  assert.equal(S.fleetSummary("Pan Am", [ok(1), ok(19), ok(2)]), "Pan Am · fleets 3 pages ok, 22 aircraft");
  assert.equal(S.fleetSummary("Virgin", [ok(1)]), "Virgin · fleets 1 page ok, 1 aircraft");
  assert.equal(S.fleetSummary("Pan Am", [ok(19), { ok: true, rows: 0, verdict: { verdict: "short" } }, { ok: false, error: "parse: HTTP 502" }]),
    "Pan Am · fleets 1 of 3 pages ok, 19 aircraft");
  assert.equal(S.fleetOk({ ok: true, rows: 0, verdict: { verdict: "short" } }), false);
  assert.equal(S.fleetOk({ ok: true, rows: 3 }), true);
});

// ---------------------------------------------------------------- 4. the file and the sample
await check("the file: version 1.6 and later, fleet pages sent to capture_ingest() with the key as kind fleet, half a second apart, after the loads", () => {
  assert.match(source, /^\/\/ @version\s+1\.8$/m);
  assert.match(source, /rpc\("capture_ingest", \{ p_key: KEY, p_airline: String\(gameId\), p_kind: "fleet", p_page: url, p_rows: rows \}\)/);
  assert.equal(S.FLEET_PACE, 500);
  assert.match(source, /send\(id, "loads"[^\n]*\n\s*await captureFleets\(id, name\);/, "the fleets aren't read after the loads page");
});
await check("the sample holds nothing of the session: no user name, profile, scripts, settings or page versions", () => {
  for (const bad of ["DevilsVengeance", "user?id=", "frontendSettings", "as-sid", "<script", "Credits", "saved from url", "?16-", "?16#", "?16\""])
    assert.ok(!saved.includes(bad), "the sample still holds " + bad);
  assert.ok(/^<!DOCTYPE html>\n<!-- Pan Am's JFK fleet page/.test(saved), "the sample doesn't say what it is");
});

console.log(failures ? `\n${failures} capture fleet check(s) failed` : "\ncapture fleet: all passed");
process.exit(failures ? 1 : 0);
