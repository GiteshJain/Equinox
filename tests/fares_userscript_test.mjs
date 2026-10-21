// The fares userscript (capture/fares_apply.user.js; spec docs/specs/2026-10-21-fares-userscript.md §3) on the game's
// pages, with no browser and no game: the script's own file runs in Node, where (with no page) it only hands over its
// logic. On the dated samples: the fares form Gitesh saved on 21 Oct (tests/fixtures/flightsPrices_2026-10-21.html) and
// the answer to one change, made by hand from his screenshot (tests/fixtures/flightsPrices_answer_2026-10-21.html).
// Checks: the airport map read from the form; the GET address for a + and a − change, with one class and with both; the
// answer read, the right rows found and a missing row caught; a change that can't be made refused before anything is
// sent; capture_fare_actions()'s answer grouped by airline; and the file's header, key placeholder, pause and no dialogs.
// Usage: node tests/fares_userscript_test.mjs
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const source = readFileSync(new URL("../capture/fares_apply.user.js", here), "utf8");
const form = readFileSync(new URL("fixtures/flightsPrices_2026-10-21.html", here), "utf8");
const answer = readFileSync(new URL("fixtures/flightsPrices_answer_2026-10-21.html", here), "utf8");

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "capture/fares_apply.user.js" });
const F = sandbox.eqFares;
// values made inside the script's own context compare by their JSON
const plain = v => JSON.parse(JSON.stringify(v));

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

const action = (from, to, sign, pct, classes, extra = {}) => ({ game_id: 112, airline: "Pan Am", n: 1, route: from + "–" + to, from, to, sign, pct, classes, plan_ids: classes.map((c, i) => 100 + i), ...extra });

await check("the script hands over its logic in Node and touches no page", () => {
  assert.ok(F, "eqFares isn't there");
  for (const f of ["airportsOf", "changeUrl", "checkAnswer", "changedPairs", "planOf", "actionProblem", "idsFor"]) assert.equal(typeof F[f], "function", f);
  assert.equal(F.FORM, "/action/enterprise/flightsPrices");
});

// ---------------------------------------------------------------- the airport map
const airports = F.airportsOf(form);
await check("the airport map: all 37 airports of the saved form, each in From and To with its a: id", () => {
  assert.ok(airports, "no form read");
  assert.equal(Object.keys(airports.from).length, 37);
  assert.deepEqual(plain(airports.to), plain(airports.from));
  assert.equal(airports.from.JFK, "a:3551"); assert.equal(airports.from.LHR, "a:1054"); assert.equal(airports.from.YYZ, "a:1701");
  assert.equal(airports.from.ORD, "a:3360"); assert.equal(airports.from.CDG, "a:878");
  assert.deepEqual(plain(airports.twice), []);
  assert.ok(Object.values(airports.from).every(v => /^a:\d+$/.test(v)), "a value that isn't an airport's");
});
await check("the airport map: countries (c:) and anywhere are never used; names without the dashes and code", () => {
  assert.ok(form.includes('value="c:54">United Kingdom'), "the sample has no country to leave out");
  assert.ok(!Object.values(airports.from).some(v => v.startsWith("c:")) && !("" in airports.from));
  assert.equal(airports.names.LHR, "London Heathrow"); assert.equal(airports.names.ORD, "Chicago O'Hare");
});
await check("the airport map: an airport not in the form is missing; a page without the form gives none", () => {
  assert.equal(airports.from.DEL, undefined);
  assert.match(plain(F.idsFor(airports, action("JFK", "DEL", "+", 5, ["economy"]))).problem, /DEL isn't in the fares form's To list/);
  assert.match(plain(F.idsFor(airports, action("DEL", "JFK", "+", 5, ["economy"]))).problem, /DEL isn't in the fares form's From list/);
  assert.equal(F.airportsOf("<html><body>Please sign in</body></html>"), null);
});
await check("the airport map: one code under two ids is refused, not guessed", () => {
  const twice = form.replace('<option value="a:3552">-- New York La Guardia (LGA)</option>', '<option value="a:3552">-- New York La Guardia (LGA)</option><option value="a:9999">-- Somewhere Else (LGA)</option>');
  const a = F.airportsOf(twice);
  assert.deepEqual(plain(a.twice), ["LGA"]);
  assert.match(plain(F.idsFor(a, action("JFK", "LGA", "+", 5, ["economy"]))).problem, /LGA is in the fares form twice/);
});

// ---------------------------------------------------------------- the GET address
const ids = (a) => plain(F.idsFor(airports, a));
await check("a + change with both classes: one GET with economy and business ticked", () => {
  const a = action("JFK", "LHR", "+", 5, ["economy", "business"]);
  assert.equal(F.changeUrl(a, ids(a)),
    "/action/enterprise/flightsPrices?adjust=true&fromCode=a%3A3551&toCode=a%3A1054&serviceProfileId=0&factor=1&percent=5&base=standard&economy=true&business=true");
});
await check("a − change with one class: factor -1, economy only", () => {
  const a = action("LHR", "JFK", "-", 15, ["economy"]);
  assert.equal(F.changeUrl(a, ids(a)),
    "/action/enterprise/flightsPrices?adjust=true&fromCode=a%3A1054&toCode=a%3A3551&serviceProfileId=0&factor=-1&percent=15&base=standard&economy=true");
});
await check("a + change in business only, and back to the default price (+0)", () => {
  const b = action("JFK", "ORD", "+", 10, ["business"]);
  assert.equal(F.changeUrl(b, ids(b)),
    "/action/enterprise/flightsPrices?adjust=true&fromCode=a%3A3551&toCode=a%3A3360&serviceProfileId=0&factor=1&percent=10&base=standard&business=true");
  const z = action("ORD", "JFK", "+", 0, ["economy", "business"]);
  assert.match(F.changeUrl(z, ids(z)), /&factor=1&percent=0&base=standard&economy=true&business=true$/);
});
await check("the address uses the form's own fields and values, and nothing else (no first class, no cargo, any service profile)", () => {
  const a = action("JFK", "LHR", "-", 5, ["economy", "business"]);
  const q = new URL(F.changeUrl(a, ids(a)), "https://gander.airlinesim.aero").searchParams;
  assert.deepEqual([...q.keys()], ["adjust", "fromCode", "toCode", "serviceProfileId", "factor", "percent", "base", "economy", "business"]);
  for (const [name, value] of [...q].filter(([k]) => !["fromCode", "toCode", "economy", "business"].includes(k))) {
    assert.ok(new RegExp(`name="${name}"`).test(form), name + " isn't a field of the form");
    if (name !== "percent") assert.ok(form.includes(`value="${value}"`), `${name}=${value} isn't one of the form's values`);
  }
  assert.ok(form.includes("<option>5</option>"), "the form's percent has no 5");
});

// ---------------------------------------------------------------- the answer
await check("the answer's Changed Airport Pairs: From, To, Service Class, Old and New Price", () => {
  assert.deepEqual(plain(F.changedPairs(answer)), [
    { from: "LHR", to: "JFK", cls: "C", old: "1,010", new: "1,010" },
    { from: "LHR", to: "JFK", cls: "Y", old: "407", new: "407" }]);
});
await check("the answer checked: both classes found for From LHR to JFK, and one class alone", () => {
  const c = plain(F.checkAnswer(answer, action("LHR", "JFK", "+", 0, ["economy", "business"]), airports.names));
  assert.equal(c.ok, true, c.why);
  assert.deepEqual(c.rows, [{ cls: "Y", old: "407", new: "407" }, { cls: "C", old: "1,010", new: "1,010" }]);
  assert.equal(plain(F.checkAnswer(answer, action("LHR", "JFK", "+", 0, ["business"]), airports.names)).ok, true);
});
await check("the answer checked: a missing row is caught (the other direction; a class the answer lacks)", () => {
  const back = plain(F.checkAnswer(answer, action("JFK", "LHR", "+", 0, ["economy"]), airports.names));
  assert.equal(back.ok, false); assert.match(back.why, /no Y \(economy\) row for From JFK to LHR/);
  const noC = answer.replace(/<tr>\s*<td>LHR<\/td>\s*<td>JFK<\/td>\s*<td>C<\/td>[\s\S]*?<\/tr>/, "");
  assert.ok(!/<td>C<\/td>/.test(noC), "the sample's C row wasn't taken out");
  const c = plain(F.checkAnswer(noC, action("LHR", "JFK", "+", 0, ["economy", "business"]), airports.names));
  assert.equal(c.ok, false); assert.match(c.why, /no C \(business\) row for From LHR to JFK/);
});
await check("the answer checked: airports named in full, or as the form names them, are read too", () => {
  const full = answer.replace(/<td>LHR<\/td>/g, "<td>London Heathrow (LHR)</td>").replace(/<td>JFK<\/td>/g, "<td><a href=\"#\">New York John F. Kennedy</a></td>");
  assert.equal(plain(F.checkAnswer(full, action("LHR", "JFK", "+", 0, ["economy", "business"]), airports.names)).ok, true);
});
await check("the answer checked: no table on the fares page, and a page that isn't the fares page (the session lost)", () => {
  const none = plain(F.checkAnswer(form, action("LHR", "JFK", "+", 0, ["economy"]), airports.names));
  assert.equal(none.ok, false); assert.match(none.why, /listed no Changed Airport Pairs/); assert.ok(!none.session);
  const lost = plain(F.checkAnswer("<html><body><form action=\"/auth/login\">Sign in</form></body></html>", action("LHR", "JFK", "+", 0, ["economy"]), airports.names));
  assert.equal(lost.ok, false); assert.match(lost.why, /session may have been lost/); assert.equal(lost.session, true);
});

// ---------------------------------------------------------------- the list from the database
await check("a change that can't be made is refused before anything is sent", () => {
  assert.equal(F.actionProblem(action("JFK", "LHR", "+", 5, ["economy"])), null);
  assert.match(F.actionProblem(action("JFK", "LHR", "+", 2.5, ["economy"])), /whole percent/);
  assert.match(F.actionProblem(action("JFK", "LHR", "+", 101, ["economy"])), /whole percent/);
  assert.match(F.actionProblem(action("JFK", "LHR", "−", 5, ["economy"])), /sign/);
  assert.match(F.actionProblem(action("JFK", "LHR", "+", 5, ["first"])), /classes/);
  assert.match(F.actionProblem(action("JFK", "LHR", "+", 5, [])), /classes/);
  assert.match(F.actionProblem(action("JFK", "JFK", "+", 5, ["economy"])), /same airport/);
  assert.match(F.actionProblem(action("JFK", "LHR", "+", 5, ["economy"], { game_id: null })), /game ID/);
});
await check("capture_fare_actions()'s answer grouped by airline, in its order, with the total; a bad key's answer an error", () => {
  const doc = { ok: true, world: "Gander", week_of: "2026-10-17",
    airlines: [{ game_id: 112, name: "Pan Am", count: 2 }, { game_id: 113, name: "Kingfisher", count: 0 }, { game_id: 114, name: "Ryanair", count: 1 }],
    actions: [action("JFK", "LHR", "+", 5, ["economy"]), action("LHR", "JFK", "+", 5, ["economy"]), action("CDG", "DUB", "-", 10, ["economy"], { game_id: 114, airline: "Ryanair" })] };
  const p = plain(F.planOf(doc));
  assert.equal(p.total, 3); assert.equal(p.week_of, "2026-10-17"); assert.deepEqual(p.problems, []);
  assert.deepEqual(p.airlines.map(a => [a.game_id, a.name, a.actions.length]), [["112", "Pan Am", 2], ["113", "Kingfisher", 0], ["114", "Ryanair", 1]]);
  const bad = plain(F.planOf({ ok: false, error: "bad key" }));
  assert.equal(bad.error, "bad key");
  assert.equal(plain(F.planOf({ code: "57014", message: "canceling statement due to statement timeout" })).error, "canceling statement due to statement timeout");
  const odd = plain(F.planOf({ ...doc, actions: [...doc.actions, action("JFK", "LHR", "+", 7.5, ["economy"])] }));
  assert.equal(odd.problems.length, 1); assert.match(odd.problems[0].why, /whole percent/);
});
await check("the panel's words: progress, and a change in words", () => {
  assert.equal(F.progressWords("Pan Am", 12, 50), "Pan Am: 12 of 50");
  assert.equal(F.changeWords(action("LHR", "JFK", "-", 5, ["economy", "business"])), "From LHR to JFK: −5% of the default price, economy and business");
  assert.equal(F.changeWords(action("LHR", "JFK", "+", 5, ["economy"], { text: "From LHR to JFK: +5% of the default price, economy" })),
    "From LHR to JFK: +5% of the default price, economy");
});

// ---------------------------------------------------------------- the file itself
await check("the file: a userscript for the game with a version, the key a placeholder, the public key only", () => {
  assert.match(source, /^\/\/ ==UserScript==/);
  assert.match(source, /^\/\/ @match\s+https:\/\/gander\.airlinesim\.aero\/\*$/m);
  assert.match(source, /^\/\/ @version\s+\d+\.\d+$/m);
  assert.match(source, /const KEY = "__CAPTURE_KEY__"/);
  assert.match(source, /rpc\("capture_fare_actions", \{ p_key: KEY \}\)/);
});
await check("the file: 2 seconds between changes, no browser dialogs, prices only", () => {
  assert.equal(F.PAUSE_MS, 2000);
  assert.ok(!/\b(?:alert|confirm|prompt)\s*\(/.test(source.replace(/^\s*\/\/.*$/gm, "")), "alert, confirm or prompt used");
  // the only game addresses it opens or calls: the airline switch, the fares page and its changes
  const paths = [...source.matchAll(/["'`](\/(?:app|action)\/[^"'`?$]*)/g)].map(m => m[1]);
  assert.deepEqual([...new Set(paths)].sort(), ["/action/enterprise/flightsPrices", "/app/enterprise/dashboard"]);
  assert.ok(!/method:\s*["']POST["'][^}]*airlinesim/i.test(source), "a POST to the game");
});

console.log(failures ? `\n${failures} fares userscript check(s) failed` : "\nfares userscript: all passed");
process.exit(failures ? 1 : 0);
