// The planner's screen figures on a fixed, dated sample, against saved answers (decision #18, the clean-up, build pull
// request 14: with the side by sides gone, what keeps the screens' own figures from moving unnoticed).
//
// The sample is tests/fixtures/report_2026-10-12.json.gz (rules_input()'s answer as export_for_report('rules') gave it
// on the rehearsal's copy of the 12 Oct backup, tests/README.md "The report sample"). On it, the planning library
// (lib/rules/dist, built by npm run build) works out what the screens show (the settings added since 12 Oct take the
// library cases' values, lib/rules/cases/_base.json, which are the manual's):
//   - Home: the key figures, the airline cards and the figures now (summary.keyFigures, airlineCards, now, at the sample's
//     moment);
//   - Hubs: every base's and focus city's board on every day (its counts, its flights in each bank and outside them, the
//     cap, the next flight-number pair, and a fingerprint of the whole flight list) and its connections table (the
//     counts, each row's city pairs, and a fingerprint of every pair);
//   - Tails: every aircraft's week (legs, block minutes, block hours a day, routes, gaps at target, estimated legs), its
//     maintenance, its issues and its rotations off wave;
//   - the schedule checks Check and Routes show (night bans, route gaps, flight-number clashes, departures per airport
//     against the cap).
// The figures from the capture (Review's and Check's money, growth and loads) are the database's and are guarded there
// (database/tests/captured_figures_test.sql and the other figure tests); the library's rules by its cases
// (lib/rules/cases). Each answer here was recorded from the planner as the side by sides left it, with the Hubs fix of
// the same pull request (an arrival named with a bank only when it can make it, design §16): the count of arrivals the
// fix moves out of the banks on the sample is printed.
//
// A difference prints where (the screen, airport, day or registration, and the figure), never more than 40 lines, and
// fails. After an intended change: UPDATE_FIGURES=1 node tests/planner_figures.mjs writes the answers again; say in the
// pull request which moved and why (manual §1).
// Usage: node tests/planner_figures.mjs   (after npm run build)
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";

const here = new URL(".", import.meta.url);
const LIB = new URL("../lib/rules/dist/index.js", here);
const SAMPLE = new URL("fixtures/report_2026-10-12.json.gz", here);
const EXPECTED = new URL("fixtures/planner_figures.expected.json", here);
if (!existsSync(LIB)) {
  console.log("FAIL  the planning library isn't built (lib/rules/dist): run npm ci && npm run build first");
  process.exit(1);
}
const { buildRules, block, summary, hubs, banks, aircraftWeek, maintenance, tails, schedule } = await import(LIB.href);

const s = JSON.parse(gunzipSync(readFileSync(SAMPLE)).toString("utf8"));
// Settings added after the sample was made (13 Oct and later) take the values the library's cases give them
// (lib/rules/cases/_base.json, the manual's numbers), so the screens' figures can be worked out on it
const base = JSON.parse(readFileSync(new URL("../lib/rules/cases/_base.json", here), "utf8")).input;
const filled = Object.keys(base.settings).filter((k) => !(k in s.rules.settings)).sort();
for (const k of filled) s.rules.settings[k] = base.settings[k];
const rules = buildRules(s.rules);
const legs = block.timedLegs(rules);
const print = (x) => createHash("sha256").update(JSON.stringify(x)).digest("hex").slice(0, 16);
const tally = (list) => Object.fromEntries([...list.reduce((m, k) => m.set(k, (m.get(k) ?? 0) + 1), new Map())].sort());

// ---- Home
const home = { key_figures: summary.keyFigures(rules, legs), airline_cards: summary.airlineCards(rules, legs), now: summary.now(rules, s.frozen_at, legs) };

// ---- Hubs, and how many arrivals the fix moves out of the banks (the first bank, however long the wait, before it)
let moved = 0, arrivalsBanked = 0;
const hubsOut = {};
for (const code of hubs.airports(rules)) {
  const days = [];
  for (let day = 0; day < 7; day++) {
    const b = hubs.board(rules, code, day, legs);
    for (const f of b.flights) {
      if (f.kind !== "arr" || f.bank == null) continue;
      arrivalsBanked++;
      const base = banks.airlineBaseAt(rules, code, f.airline_id);
      const before = base && banks.bankWindows(rules, base).length ? banks.bankOfArrival(rules, base, f.local_min).next ?? 0 : 0;
      if (before !== f.bank) moved++;
    }
    days.push({
      departures: b.departures_today, arrivals: b.arrivals_today,
      in_banks: tally(b.flights.filter((f) => f.bank != null).map((f) => `${f.kind} ${f.bank}`)),
      departures_week: b.departures_week, cap: b.cap, over_cap: b.over_cap, next_pair: b.next_pair,
      banks: b.banks.length, flights: print(b.flights),
    });
  }
  const t = hubs.connectionsTable(rules, code, legs);
  hubsOut[code] = {
    days,
    connections: { arrivals: t.arrivals, departures: t.departures, city_pairs: t.pairs.length, rows: t.rows.map((r) => [r.n, r.city_pairs]), pairs: print(t.pairs) },
  };
}

// ---- Tails
const tailsOut = {};
for (const a of [...rules.aircraft.values()].filter((x) => x.status === "active").sort((x, y) => x.id - y.id)) {
  const w = aircraftWeek.forAircraft(rules, a, legs);
  const m = maintenance.forAircraft(rules, a, legs, w);
  tailsOut[a.registration] = {
    week: w ? { legs: w.legs_week, block_min: w.block_min_week, block_hours_day: w.block_hours_day, routes: w.routes,
                gaps_at_target: w.gaps_at_target, estimated_legs: w.estimated_legs, departures: print(w.legs) } : null,
    maintenance: m.ratio == null ? { none: m.reason } : { pct: m.pct, level: m.level, need_min_week: m.need_min_week, have_min_week: m.have_min_week },
    issues: tails.issues(rules, a, legs, w, m),
    off_wave: tails.offWave(rules, a.id),
  };
}

// ---- the schedule checks
const sc = schedule.scheduleChecks(rules, legs);
const scheduleOut = Object.fromEntries(Object.entries(sc).map(([k, v]) => [k, Array.isArray(v) ? { count: v.length, all: print(v) } : v]));

const found = { sample: "report_2026-10-12.json.gz", as_of: s.frozen_at, home, hubs: hubsOut, tails: tailsOut, schedule: scheduleOut };
console.log(`the sample: ${found.sample} as of ${found.as_of}; ${Object.keys(hubsOut).length} hubs and focus cities, ${Object.keys(tailsOut).length} aircraft in service, ${legs.length} legs`
  + (filled.length ? `; settings added since, from the library's cases: ${filled.join(", ")}` : ""));
console.log(`      Hubs: ${moved} of ${arrivalsBanked} arrivals at their airline's base a week are outside the banks only since the fix (the old board named them with the first bank)`);

if (process.env.UPDATE_FIGURES === "1") {
  writeFileSync(EXPECTED, JSON.stringify(found, null, 1) + "\n");
  console.log(`ok    the answers written to tests/fixtures/planner_figures.expected.json`);
  process.exit(0);
}
if (!existsSync(EXPECTED)) {
  console.log("FAIL  no saved answers (tests/fixtures/planner_figures.expected.json): UPDATE_FIGURES=1 node tests/planner_figures.mjs");
  process.exit(1);
}
const want = JSON.parse(readFileSync(EXPECTED, "utf8"));
const diffs = [];
const walk = (a, b, path) => {
  if (diffs.length > 40) return;
  if (JSON.stringify(a) === JSON.stringify(b)) return;
  if (a && b && typeof a === "object" && typeof b === "object" && Array.isArray(a) === Array.isArray(b)) {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) walk(a[k], b[k], path ? `${path}.${k}` : k);
    return;
  }
  diffs.push(`${path}: now ${JSON.stringify(b)?.slice(0, 80)}, saved ${JSON.stringify(a)?.slice(0, 80)}`);
};
walk(want, found, "");
const screens = ["home", "hubs", "tails", "schedule"].map((k) => `${k} ${diffs.some((d) => d.startsWith(k + ".")) ? "differs" : "the same"}`);
if (diffs.length) {
  console.log(`FAIL  the screens' figures on the sample differ from the saved answers (${screens.join(", ")})`);
  for (const d of diffs.slice(0, 40)) console.log("      " + d);
  console.log("      after an intended change: UPDATE_FIGURES=1 node tests/planner_figures.mjs, and say in the pull request which moved and why");
  process.exit(1);
}
console.log(`ok    Home's key figures, cards and figures now, every Hubs board and connections table, every aircraft's week, maintenance and issues, and the schedule checks equal the saved answers`);
