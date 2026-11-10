// Salaries in the capture (capture/capture_all.user.js 1.15; manual §7; brief docs/briefs/2026-11-04-salaries-in-capture.md,
// option A, Gitesh 4 Nov), with no browser and no game: the script's own file runs in Node, where (with no page) it only
// hands over its logic (eqScan), as tests/capture_scan_test.mjs runs it. The sample is the real Employee overview page
// (Kingfisher, 9 Nov, saved by Gitesh; tests/fixtures/employee_overview_KF_2026-11-09.html): every row's salary box is
// named "amount" and each row has its own form (action staffOverview: hidden action=salary and id, then amount).
//   1. The page: 16 positions, each with its form's id, next week's salary and its country average, in the page's order;
//      "adjust all" is not one; a page that isn't the Employee overview, or has no salary rows, gives an error.
//   2. The rule: below the average → the average × 1.05, rounded: A320 pilots 1,683 under 1,699 → 1,784; flight
//      attendants 462 under 473 → 497. At or above (E-jet pilots 1,250 over 1,190, pursers 590 over 589): left alone.
//   3. Whole runs against a stand-in for the game: one form per position below, each with its own id and exactly its
//      amount, nothing else sent (9 Nov: 1.12–1.14 found the first box for every position, because every box is named
//      "amount", and set the E-jet pilots' salary three times); the count from the page read again; a form the game
//      refuses is named; a page that doesn't read is said and skipped.
//   4. The file: version 1.16; no clicking, no page opened; nothing about salaries sent to the database; never failed().
// Usage: node tests/capture_salary_test.mjs
import { readFileSync, existsSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const read = p => readFileSync(new URL(p, here), "utf8");
const source = read("../capture/capture_all.user.js");
const sample = read("fixtures/employee_overview_KF_2026-11-09.html");

const sandbox = { URL };
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "capture/capture_all.user.js" });
const S = sandbox.eqScan;
const plain = v => JSON.parse(JSON.stringify(v));

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

// ---------------------------------------------------------------- 1. the page
await check("the script hands over salaries' logic in Node", () => {
  for (const f of ["salaryPctOf", "salaryTarget", "isSalaryPage", "salaryLinkOf", "readSalaryPage", "salariesBelow", "salaryWords", "runSalaries", "salaryFormBody", "salaryFormUrl"])
    assert.equal(typeof S[f], "function", f);
  assert.equal(S.SALARY_MAX_CHANGES, 40);
});
const pageRows = plain(S.readSalaryPage(sample));
await check("the real page: 16 positions, each with its own form id, next week's salary and its country average; \"adjust all\" isn't one", () => {
  assert.equal(pageRows.error, undefined);
  assert.equal(pageRows.rows.length, 16);
  const by = Object.fromEntries(pageRows.rows.map(r => [r.key, r]));
  assert.deepEqual([by["EMB-170 / -175 / -190 / -195"].id, by["EMB-170 / -175 / -190 / -195"].current, by["EMB-170 / -175 / -190 / -195"].avg], ["2431", 1250, 1190]);
  assert.deepEqual([by["A318 / A319 / A320 / A321"].id, by["A318 / A319 / A320 / A321"].current, by["A318 / A319 / A320 / A321"].avg], ["1991", 1683, 1699]);
  assert.deepEqual([by["Flight attendants"].id, by["Flight attendants"].current, by["Flight attendants"].avg], ["1138", 462, 473]);
  assert.deepEqual([by["Logistics"].id, by["Logistics"].current, by["Logistics"].avg], ["1148", 792, 720]);
  assert.ok(pageRows.rows.every(r => r.action === "staffOverview" && /^\d+$/.test(r.id)), "every row has its own form");
  assert.equal(new Set(pageRows.rows.map(r => r.id)).size, 16, "the ids are all different");
});
await check("a page that isn't the Employee overview, or has no salary rows, gives an error and no rows", () => {
  const notIt = plain(S.readSalaryPage("<html><body><h2>Dashboard</h2><table><tr><td>Cash</td><td>1,000 AS$</td></tr></table></body></html>"));
  assert.deepEqual(notIt.rows, []);
  assert.match(notIt.error, /not the Employee overview page/);
  const empty = plain(S.readSalaryPage("<h2>Employee overview</h2><p>Country average</p><table><tr><td>Pilots</td><td>10,000 AS$</td></tr></table>"));
  assert.match(empty.error, /no salary rows/);
});
await check("the link to the page, without the game's page version", () => {
  const menu = '<ul><li><a href="../enterprise/dashboard">Overview</a></li><li><a href="../enterprise/staffOverview?7">Employee overview</a></li></ul>';
  assert.equal(S.salaryLinkOf(menu, "https://gander.airlinesim.aero/app/com/loads"), "https://gander.airlinesim.aero/app/enterprise/staffOverview");
  assert.equal(S.salaryLinkOf('<a href="../enterprise/staffOverview">Personnel Management</a>', "https://gander.airlinesim.aero/app/com/loads"), "https://gander.airlinesim.aero/app/enterprise/staffOverview");
});

// ---------------------------------------------------------------- 2. the rule
await check("below the average → the average × 1.05, rounded; at or above → left alone; only the two below are changed", () => {
  assert.equal(S.salaryTarget(1699, 5), 1784, "1,783.95");
  assert.equal(S.salaryTarget(473, 5), 497, "496.65");
  assert.equal(S.salaryTarget(1190, 5), 1250);
  assert.deepEqual(plain(S.salariesBelow(pageRows.rows)).map(r => r.key), ["A318 / A319 / A320 / A321", "Flight attendants"]);
});
await check("the form the game's adjust button sends, to the form's action on the page's address", () => {
  const row = pageRows.rows.find(r => r.key === "Flight attendants");
  assert.equal(S.salaryFormBody(row, 497), "action=salary&id=1138&amount=497");
  assert.equal(S.salaryFormUrl(row, "https://gander.airlinesim.aero/app/enterprise/staffOverview"), "https://gander.airlinesim.aero/app/enterprise/staffOverview");
});
await check("the setting as capture_airlines() answers it: a number from 0 to 50, else null (salaries left alone)", () => {
  assert.equal(S.salaryPctOf({ salary_above_average_pct: 5 }), 5);
  assert.equal(S.salaryPctOf({ salary_above_average_pct: 0 }), 0);
  for (const bad of [{}, { salary_above_average_pct: null }, { salary_above_average_pct: -1 }, { salary_above_average_pct: 80 }, null])
    assert.equal(S.salaryPctOf(bad), null, JSON.stringify(bad));
});

// ---------------------------------------------------------------- 3. whole runs against a stand-in for the game
// The stand-in keeps the page; a form sets the box of the row with that id (as the game does) and the page is served again.
function game(html, { refuse = [] } = {}) {
  const g = { html, posts: [], reads: 0 };
  g.io = {
    read: async () => { g.reads++; return g.html; },
    post: async (row, amount) => {
      g.posts.push(S.salaryFormBody(row, amount));
      if (refuse.includes(row.id)) throw new Error("the game answered 500");
      const re = new RegExp(`(name="id" value="${row.id}"/>[\\s\\S]*?name="amount"[^>]*value=")\\d+"`);
      assert.ok(re.test(g.html), "no row with id " + row.id);
      g.html = g.html.replace(re, `$1${amount}"`);
    }
  };
  return g;
}
await check("9 Nov's page: one form each for A320 pilots and flight attendants, with their own ids; E-jet pilots untouched", async () => {
  const g = game(sample);
  const res = await S.runSalaries({ name: "Kingfisher", pct: 5 }, g.io);
  assert.deepEqual(g.posts, ["action=salary&id=1991&amount=1784", "action=salary&id=1138&amount=497"]);
  assert.equal(res.words, "Kingfisher · salaries: 2 raised to 5% above the country average");
  const after = Object.fromEntries(plain(S.readSalaryPage(g.html)).rows.map(r => [r.key, r.current]));
  assert.equal(after["EMB-170 / -175 / -190 / -195"], 1250, "the E-jet pilots were changed");
  assert.equal(after["A318 / A319 / A320 / A321"], 1784);
  assert.equal(after["Flight attendants"], 497);
  assert.equal(g.reads, 2, "read once, then again for the count");
});
await check("a second run the same evening sends nothing: all at or above the average", async () => {
  const g = game(sample);
  await S.runSalaries({ name: "Kingfisher", pct: 5 }, g.io);
  const g2 = game(g.html);
  const res = await S.runSalaries({ name: "Kingfisher", pct: 5 }, g2.io);
  assert.deepEqual(g2.posts, []);
  assert.equal(res.words, "Kingfisher · salaries: all at or above the average");
});
await check("a form the game refuses is named; the other still raised", async () => {
  const g = game(sample, { refuse: ["1138"] });
  const res = await S.runSalaries({ name: "Kingfisher", pct: 5 }, g.io);
  assert.equal(g.posts.length, 2);
  assert.equal(res.words, "Kingfisher · salaries: 1 raised to 5% above the country average; 1 still below (Flight attendants (the game answered 500)): check them on the Employee overview page");
});
await check("a page that doesn't read is said and skipped: nothing sent", async () => {
  const g = game("<html><body>Please log in</body></html>");
  const res = await S.runSalaries({ name: "Pan Am", pct: 5 }, g.io);
  assert.deepEqual(g.posts, []);
  assert.equal(res.error, true);
  assert.match(res.words, /^Pan Am · salaries: the Employee overview page didn't read \(not the Employee overview page/);
});

// ---------------------------------------------------------------- 4. the file
await check("the file: version 1.16, the setting from capture_airlines(), salaries after each airline's pages and fleets", () => {
  assert.match(source, /^\/\/ @version\s+1\.16$/m);
  assert.equal(S.VERSION, "1.16");
  assert.match(source, /salaryPct: salaryPctOf\(r\)/);
  assert.match(source, /await captureCurrent\(id, name\); \} catch \(e\) \{ log\(name \+ " · problem: " \+ e\.message\); failed\(\); \}\n\s*return salaries\(id, name\); \}/);
});
await check("salaries click nothing and open no page, never count as a failed page, and send nothing to the database", () => {
  const part = source.slice(source.indexOf("// ---------------------------------------------------------------- in the game: salaries (1.12, 1.15)"),
                            source.indexOf("// ---------------------------------------------------------------- in the game: the world scan (1.5)"));
  assert.ok(part.length > 500, "the salaries part isn't in the file");
  const code = part.replace(/^\s*\/\/.*$/gm, "");
  assert.ok(!/\.click\(|location\.href\s*=/.test(code), "the salaries part clicks or opens a page");
  assert.ok(!/failed\(\)/.test(code), "the salaries part calls failed()");
  assert.ok(!/\brpc\(|send\(|scanSend|marketSend/.test(code), "the salaries part sends something to the database");
  assert.match(code, /method: "POST"/, "the form isn't sent");
});
await check("the old salary script is gone", () => {
  assert.ok(!existsSync(new URL("../capture/salary_adjust.user.js", here)));
});

console.log(failures ? `\n${failures} capture salary check(s) failed` : "\ncapture salary: all passed");
process.exit(failures ? 1 : 0);
