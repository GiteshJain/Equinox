// The schedule check (functions/api/game-schedule.js) on a saved game page (decision #9).
// Runs the real function with the game replaced by tests/fixtures/game_schedule_113.html.gz (Kingfisher, 8 Oct 2026).
// Checks: the session cookie is carried through the game's redirect, the airline and all 48 flights are read, every
// flight has its fields, the result matches the saved answer, and bad links and game errors give clear errors.
// Usage: node tests/schedule_test.mjs [--update]   (--update rewrites the saved answer; only for an intended change)
import { readFileSync, writeFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import assert from "node:assert/strict";
import { onRequestGet } from "../functions/api/game-schedule.js";

const here = new URL(".", import.meta.url);
const html = gunzipSync(readFileSync(new URL("fixtures/game_schedule_113.html.gz", here))).toString("utf8");
const expectedFile = new URL("fixtures/schedule_113.expected.json", here);
const ask = (u) => onRequestGet({ request: new Request("https://equinox-alliance.com/api/game-schedule?u=" + encodeURIComponent(u)) });

// The game answers like the real one: a redirect that sets the session cookie, then the page (only with the cookie).
const calls = [];
globalThis.fetch = async (url, init) => {
  calls.push({ url: String(url), cookie: init.headers.cookie });
  if (calls.length === 1) return new Response(null, { status: 302, headers: { location: String(url), "set-cookie": "JSESSIONID=abc; Path=/; HttpOnly" } });
  if (!/JSESSIONID=abc/.test(init.headers.cookie)) return new Response("no session", { status: 403 });
  return new Response(html, { status: 200, headers: { "content-type": "text/html" } });
};

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

const res = await ask("https://gander.airlinesim.aero/app/info/enterprises/113?tab=3");
const body = await res.json();
await check("answers 200 with JSON, not cached", () => { assert.equal(res.status, 200); assert.equal(res.headers.get("cache-control"), "no-store"); });
await check("keeps the game's session cookie through the redirect", () => { assert.equal(calls.length, 2); assert.match(calls[1].cookie, /JSESSIONID=abc/); });
await check("reads the airline", () => assert.equal(body.airline, "Kingfisher Airlines"));
await check("reads all 48 flights (as the live check found on 8 Oct)", () => assert.equal(body.flights.length, 48));
await check("every flight has its code, number, airports, days and times", () => {
  for (const f of body.flights) {
    assert.match(f.code, /^[A-Z0-9]{2}$/); assert.match(f.no, /^\d{1,4}$/);
    assert.match(f.from, /^[A-Z0-9]{3}$/); assert.match(f.to, /^[A-Z0-9]{3}$/); assert.notEqual(f.from, f.to);
    assert.match(f.days, /^[1-7]+$/); assert.match(f.dep, /\d{1,2}:\d{2}/); assert.match(f.arr, /\d{1,2}:\d{2}/);
  }
});
const answer = { id: body.id, airline: body.airline, flights: body.flights };
if (process.argv.includes("--update")) { writeFileSync(expectedFile, JSON.stringify(answer, null, 1) + "\n"); console.log("saved answer updated"); }
await check("matches the saved answer", () => assert.deepEqual(answer, JSON.parse(readFileSync(expectedFile, "utf8"))));

await check("a link that isn't a Gander enterprise is refused", async () => {
  const r = await ask("https://example.com/evil"); assert.equal(r.status, 400); assert.match((await r.json()).error, /isn't a Gander enterprise link/);
});
await check("a game error is reported, not passed on as a schedule", async () => {
  globalThis.fetch = async () => new Response("down", { status: 500 });
  const r = await ask("113"); assert.equal(r.status, 502); assert.match((await r.json()).error, /The game answered 500/);
});

console.log(failures ? `\n${failures} schedule check(s) failed` : "\nschedule check: all passed");
process.exit(failures ? 1 : 0);
