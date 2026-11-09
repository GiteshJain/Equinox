// Salaries in the capture (capture/capture_all.user.js 1.12, 1.13; manual §7; brief docs/briefs/2026-11-04-salaries-in-capture.md,
// option A, Gitesh 4 Nov), with no browser and no game: the script's own file runs in Node, where (with no page) it only
// hands over its logic (eqScan), as tests/capture_scan_test.mjs runs it. There is no saved Employee overview page in the
// repository, so the sample (tests/fixtures/employee_overview_minimal_2026-11-05.html) is a minimal page built from the
// selectors of the retired script capture/salary_adjust.user.js, which worked on the live page: the first live run is the
// real test.
//   1. The page: each position's salary, its adjust control (a link, a button or a submit input; "adjust all" is not one)
//      and its country average, in the page's order; a page that isn't the Employee overview, or has no salary rows,
//      gives an error.
//   2. The rule: below the average → the average plus salary_above_average_pct (5) per cent, rounded as the old script
//      rounded (Math.round(average × 1.05)): Pilots 9,800 under 10,000 → 10,500; Ground staff 1,150 under 1,234 → 1,296
//      (1,295.7); Administration 3,000 under 3,010 → 3,161 (3,160.5). At the average (Flight attendants 2,100) and above it
//      (Technicians 4,620 over 4,200) left alone: nothing is ever lowered. The setting as capture_airlines() answers it.
//   3. Whole runs against a stand-in for the page: one adjust per position below, in the page's order, each with exactly
//      its target; the panel's line ("3 raised to 5% above the country average", "all at or above the average"); a run
//      carried on after a reload (the positions already adjusted not pressed again); an adjust that doesn't take is
//      named, not pressed again; a page that doesn't read is said and skipped; the final count from the page fetched again.
//   4. The file: version 1.13; the setting from capture_airlines(); salaries after the fleet pages; nothing about salaries
//      sent to the database; a salary page that doesn't read never calls failed(); the old salary script is gone.
// Usage: node tests/capture_salary_test.mjs
import { readFileSync, existsSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const read = p => readFileSync(new URL(p, here), "utf8");
const source = read("../capture/capture_all.user.js");
const sample = read("fixtures/employee_overview_minimal_2026-11-05.html");

const sandbox = { URL };
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "capture/capture_all.user.js" });
const S = sandbox.eqScan;
const plain = v => JSON.parse(JSON.stringify(v));

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

// ---------------------------------------------------------------- 1. the page
await check("the script hands over salaries' logic in Node", () => {
  for (const f of ["salaryPctOf", "salaryTarget", "isSalaryPage", "salaryLinkOf", "readSalaryPage", "salariesBelow", "salaryWords", "runSalaries"])
    assert.equal(typeof S[f], "function", f);
  assert.equal(S.SALARY_PACE, 2500, "the old script's 2.5 seconds after each adjust");
  assert.equal(S.SALARY_MAX_CHANGES, 40, "the old script's guard");
});
const page = plain(S.readSalaryPage(sample));
await check("the sample: five positions, each with its salary box, its current salary and its country average; \"adjust all\" isn't one", () => {
  assert.equal(page.error, undefined);
  assert.deepEqual(page.rows, [
    { n: 0, key: "Pilots", position: "Pilots", input: "salaries:rows:0:salary", current: 9800, avg: 10000 },
    { n: 1, key: "Flight attendants", position: "Flight attendants", input: "salaries:rows:1:salary", current: 2100, avg: 2100 },
    { n: 2, key: "Technicians", position: "Technicians", input: "salaries:rows:2:salary", current: 4620, avg: 4200 },
    { n: 3, key: "Ground staff", position: "Ground staff", input: "salaries:rows:3:salary", current: 1150, avg: 1234 },
    { n: 4, key: "Administration", position: "Administration", input: "salaries:rows:4:salary", current: 3000, avg: 3010 }]);
});
await check("a page that isn't the Employee overview, or has no salary rows, gives an error and no rows", () => {
  const notIt = plain(S.readSalaryPage("<html><body><h2>Dashboard</h2><table><tr><td>Cash</td><td>1,000 AS$</td></tr></table></body></html>"));
  assert.deepEqual(notIt.rows, []);
  assert.match(notIt.error, /not the Employee overview page/);
  const empty = plain(S.readSalaryPage("<h2>Employee overview</h2><p>Country average</p><table><tr><td>Pilots</td><td>10,000 AS$</td></tr></table>"));
  assert.deepEqual(empty.rows, []);
  assert.match(empty.error, /no salary rows/);
  assert.match(plain(S.readSalaryPage("")).error, /not the Employee overview page/);
});
await check("the link to the page, as the old script found it, without the game's page version", () => {
  const menu = '<ul><li><a href="./dashboard">Dashboard</a></li><li><a href="../enterprise/employees?7">Employee overview</a></li><li><a href="./staff">Staff</a></li></ul>';
  assert.equal(S.salaryLinkOf(menu, "https://gander.airlinesim.aero/app/com/loads"), "https://gander.airlinesim.aero/app/enterprise/employees");
  assert.equal(S.salaryLinkOf('<a href="/app/x/personnel">Personnel</a>', "/app/com/loads"), "https://gander.airlinesim.aero/app/x/personnel");
  assert.equal(S.salaryLinkOf('<a href="./dashboard">Dashboard</a>', "/app/com/loads"), null);
});

// ---------------------------------------------------------------- 2. the rule
await check("below the average → exactly 105% of it, rounded as the old script rounded; at or above → left alone", () => {
  assert.equal(S.salaryTarget(10000, 5), 10500);
  assert.equal(S.salaryTarget(1234, 5), 1296, "1,295.7 rounds to 1,296");
  assert.equal(S.salaryTarget(3010, 5), 3161, "3,160.5 rounds to 3,161");
  assert.equal(S.salaryTarget(3010, 5), Math.round(3010 * 1.05));
  assert.equal(S.salaryTarget(4200, 10), 4620, "the old script's 10% gives the old figure");
  assert.deepEqual(plain(S.salariesBelow(page.rows)).map(r => r.key), ["Pilots", "Ground staff", "Administration"]);
});
await check("the setting as capture_airlines() answers it: a number from 0 to 50, else null (salaries left alone)", () => {
  assert.equal(S.salaryPctOf({ salary_above_average_pct: 5 }), 5);
  assert.equal(S.salaryPctOf({ salary_above_average_pct: "7.5" }), 7.5);
  assert.equal(S.salaryPctOf({ salary_above_average_pct: 0 }), 0);
  for (const bad of [{}, { salary_above_average_pct: null }, { salary_above_average_pct: -1 }, { salary_above_average_pct: 80 }, { salary_above_average_pct: "five" }, null])
    assert.equal(S.salaryPctOf(bad), null, JSON.stringify(bad));
});

// ---------------------------------------------------------------- 3. whole runs against a stand-in
// The stand-in holds the page's salaries; adjust sets one (or, with "sticky", leaves some as they were) and rebuilds the
// page's HTML with the new value, as the reloaded page would show it.
function standIn(html, { sticky = [], reloadAfter = null, lostFirst = [] } = {}) {
  const g = { html, adjusts: [], saves: [], checks: 0 };
  g.io = {
    read: () => g.html,
    adjust: async (row, target) => {
      g.adjusts.push([row.key, row.current, target]);
      const lost = lostFirst.includes(row.key) && g.adjusts.filter(a => a[0] === row.key).length === 1;   // 1.13: the first press lost, as on 9 Nov
      if (!sticky.includes(row.key) && !lost) g.html = g.html.replace(new RegExp(`(name="${row.input.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}" value=")[^"]*"`), `$1${target.toLocaleString("en-US")}"`);
      if (reloadAfter && g.adjusts.length === reloadAfter) throw new Error("reloaded");
    },
    save: st => g.saves.push(plain(st)),
    check: async () => { g.checks++; return g.html; }
  };
  return g;
}
await check("each position below the average adjusted once, in the page's order, with exactly its target; the others never touched", async () => {
  const g = standIn(sample), st = { name: "Pan Am", pct: 5, tried: {} };
  const res = await S.runSalaries(st, g.io);
  assert.deepEqual(g.adjusts, [["Pilots", 9800, 10500], ["Ground staff", 1150, 1296], ["Administration", 3000, 3161]]);
  assert.equal(res.words, "Pan Am · salaries: 3 raised to 5% above the country average");
  assert.equal(res.raised, 3);
  assert.deepEqual(plain(st.tried), { Pilots: 10500, "Ground staff": 1296, Administration: 3161 });
  assert.equal(g.saves.length, 3, "the state is saved before each adjust, so a reload carries on");
  assert.equal(g.checks, 1, "the final count comes from the page fetched again");
  for (const [, cur, target] of g.adjusts) assert.ok(target > cur, "a salary was lowered");
  const after = plain(S.readSalaryPage(g.html)).rows;
  assert.deepEqual(after.map(r => r.current), [10500, 2100, 4620, 1296, 3161], "Flight attendants and Technicians changed");
});
await check("every position at or above the average: nothing pressed, \"all at or above the average\"", async () => {
  const g = standIn(sample.replace('value="9,800"', 'value="10,000"').replace('value="1,150"', 'value="1,300"').replace('value="3,000"', 'value="3,010"'));
  const res = await S.runSalaries({ name: "Virgin", pct: 5 }, g.io);
  assert.deepEqual(g.adjusts, []);
  assert.equal(res.words, "Virgin · salaries: all at or above the average");
  assert.equal(g.checks, 0, "nothing pressed, so no second fetch");
});
await check("a run carried on after a reload: the positions already adjusted aren't pressed again, and count", async () => {
  const g = standIn(sample, { reloadAfter: 1 }), st = { name: "Ryanair", pct: 5, tried: {} };
  await assert.rejects(S.runSalaries(st, g.io), /reloaded/);   // the page goes away after the first adjust
  const carried = g.saves[g.saves.length - 1];
  assert.deepEqual(carried.tried, { Pilots: 10500 });
  const g2 = standIn(g.html), res = await S.runSalaries(carried, g2.io);
  assert.deepEqual(g2.adjusts, [["Ground staff", 1150, 1296], ["Administration", 3000, 3161]]);
  assert.equal(res.words, "Ryanair · salaries: 3 raised to 5% above the country average");
});
await check("an adjust that never takes is pressed 3 times (SALARY_TRIES), named in the panel, and the rest still raised", async () => {
  const g = standIn(sample, { sticky: ["Ground staff"] });
  const res = await S.runSalaries({ name: "Kingfisher", pct: 5 }, g.io);
  assert.equal(S.SALARY_TRIES, 3);
  assert.deepEqual(g.adjusts.map(a => a[0]), ["Pilots", "Ground staff", "Ground staff", "Ground staff", "Administration"]);
  assert.equal(res.words, "Kingfisher · salaries: 2 raised to 5% above the country average; 1 still below after adjust (Ground staff): check them on the Employee overview page");
});
await check("1.13: a press lost while the page reloads (9 Nov) is pressed again and counts as raised", async () => {
  const g = standIn(sample, { lostFirst: ["Ground staff", "Administration"] }), st = { name: "Pan Am", pct: 5, tried: {} };
  const res = await S.runSalaries(st, g.io);
  assert.deepEqual(g.adjusts.map(a => a[0]), ["Pilots", "Ground staff", "Ground staff", "Administration", "Administration"]);
  assert.equal(res.words, "Pan Am · salaries: 3 raised to 5% above the country average");
  assert.deepEqual(plain(st.tries), { Pilots: 1, "Ground staff": 2, Administration: 2 });
});
await check("a page that doesn't read is said and skipped: nothing pressed", async () => {
  const g = standIn("<html><body><h2>Sign in</h2></body></html>");
  const res = await S.runSalaries({ name: "Malaysia", pct: 5 }, g.io);
  assert.deepEqual(g.adjusts, []);
  assert.equal(res.error, true);
  assert.match(res.words, /^Malaysia · salaries: the Employee overview page didn't read \(not the Employee overview page.*\); skipped$/);
});
await check("another percentage is the setting's: 10 gives the old script's figures for those below", async () => {
  const g = standIn(sample);
  const res = await S.runSalaries({ name: "China Eastern", pct: 10 }, g.io);
  assert.deepEqual(g.adjusts, [["Pilots", 9800, 11000], ["Ground staff", 1150, 1357], ["Administration", 3000, 3311]]);
  assert.equal(res.words, "China Eastern · salaries: 3 raised to 10% above the country average");
});

// ---------------------------------------------------------------- 4. the file
await check("the file: version 1.13, the setting from capture_airlines(), salaries after each airline's pages and fleets", () => {
  assert.match(source, /^\/\/ @version\s+1\.13$/m);
  assert.equal(S.VERSION, "1.13");
  assert.match(source, /salaryPct: salaryPctOf\(r\)/);
  assert.match(source, /await captureCurrent\(id, name\); \} catch \(e\) \{ log\(name \+ " · problem: " \+ e\.message\); failed\(\); \}\n\s*return salaries\(id, name\); \}/);
  assert.match(source, /send\(id, "loads"[^\n]*\n\s*await captureFleets\(id, name\);/, "the fleets aren't read after the loads page any more");
  assert.match(source, /if \(s\.phase === "salary"\) return salaryPage\(id, name\);/);
});
await check("salaries never count as a failed capture page and nothing about them goes to the database", () => {
  const part = source.slice(source.indexOf("// ---------------------------------------------------------------- in the game: salaries (1.12)"),
                            source.indexOf("// ---------------------------------------------------------------- in the game: the world scan (1.5)"));
  assert.ok(part.length > 1000, "the salaries part isn't in the file");
  const code = part.replace(/^\s*\/\/.*$/gm, "");
  assert.ok(!/failed\(\)/.test(code), "the salaries part calls failed()");
  assert.ok(!/\brpc\(|RPC|send\(|scanSend|marketSend/.test(code), "the salaries part sends something to the database");
  const posts = [...source.matchAll(/method: "POST"/g)].length;
  assert.equal(posts, 4, "a POST was added");
});
await check("the old salary script is gone", () => {
  assert.ok(!existsSync(new URL("../capture/salary_adjust.user.js", here)), "capture/salary_adjust.user.js is still there");
  assert.ok(!/salary_adjust\.user\.js\),? run by hand/.test(source));
});

console.log(failures ? `\n${failures} capture salary check(s) failed` : "\ncapture salary: all passed");
process.exit(failures ? 1 : 0);
