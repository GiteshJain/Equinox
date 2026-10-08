// Runs the planner's own cash-forecast code on a saved capture, outside the browser.
// Usage: python3 tests/fixtures/capture_2026-10-08.py > /tmp/cap.json
//        node tests/forecast_lease_test.mjs web/planner/index.html /tmp/cap.json
import { readFileSync } from "node:fs";

const [html, capFile] = process.argv.slice(2);
const src = readFileSync(html, "utf8"), cap = JSON.parse(readFileSync(capFile, "utf8"));
const grab = (from, to) => { const a = src.indexOf(from), b = src.indexOf(to, a); if (a < 0 || b < 0) throw new Error("not found: " + from); return src.slice(a, b); };

// the planner's own code: order helpers and the forecast (flights a day come from the fixture)
let code = grab("  const cabinCostM = ", "  function cabinOf(")
  + grab("  const BUY_TYPES = ", src.includes("  function buyingPower()") ? "  function buyingPower()" : "  const SPEND_ORDER")
  + grab("  const CUSHION = ", "  const fcDay = ") + grab("  function orderNow(", "  function fcNext(");
code = code.replace(/function flightsPerDay\(al\) \{[^\n]*\n/, "function flightsPerDay(al) { return FPD[al] || 0; }\n");
const env = {
  state: { ref: { types: cap.types, configs: cap.configs } },
  CAP: { bal: cap.bal, events: cap.events, ops: cap.ops },
  CAP_HOME: cap.home, FPD: cap.fpd,
  eqOff: c => cap.utc[c] ?? 0,
  buyingPower: () => [],
};
const run = new Function(...Object.keys(env), code + "\nreturn { cashForecast, orderNow };")(...Object.values(env));

const out = {};
for (const al of Object.keys(cap.home)) {
  const fc = run.cashForecast(al);
  out[al] = { low: +fc.low.v.toFixed(2), now: run.orderNow(al),
    safe: fc.safe.map(x => `${x.short}: ${x.d === 0 ? "now" + (x.n > 1 ? " (up to " + x.n + ")" : "") : x.d != null ? "day " + x.d : "not in 14 days"}${x.L != null ? " · lease " + x.L.toFixed(3) : ""}`) };
}
console.log(JSON.stringify(out, null, 1));
