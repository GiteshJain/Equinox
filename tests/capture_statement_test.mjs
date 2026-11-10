// The whole bank statement, sent in parts (capture/capture_all.user.js 1.16; spec docs/specs/2026-11-10-whole-statement.md
// §1), with no browser and no game: the script's own file runs in Node, where (with no page) it only hands over its logic
// (eqScan), as tests/capture_scan_test.mjs runs it.
//   1. statementParts(rows, max): a minute is never split across two parts; every line is kept, in order; a minute bigger
//      than the limit stays whole in one part; one part when under the limit (and one empty part with no lines, so the
//      page is still sent and judged). On the saved evening's statement too (tests/fixtures/capture_pages_*.json.gz,
//      445 lines).
//   2. statementPage(run, k, n): /app/finance/accounting/2#run=<ISO>&part=<k>/<n>, which the migration's
//      private.statement_run() reads back.
//   3. The panel's words: "Ryanair · statement 2,412 lines, 24 pages, 5 parts", the first failed part's error, and the
//      safety stop's "stopped at 60 pages, 6,000 lines".
//   4. The file: version 1.16; the date stop at 26 hours and the safety stop at 60 pages (no 15-page stop); the run's time
//      taken once; each part sent in order with its page.
// Usage: node tests/capture_statement_test.mjs
import { readFileSync, readdirSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const read = p => readFileSync(new URL(p, here), "utf8");
const source = read("../capture/capture_all.user.js");

const sandbox = { URL };
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "capture/capture_all.user.js" });
const S = sandbox.eqScan;
const plain = v => JSON.parse(JSON.stringify(v));

let failures = 0;
const check = async (name, fn) => { try { await fn(); console.log("ok    " + name); } catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); } };

// statement lines as the capture reads them (rowsOf, filtered to a date and time first): newest first, `counts` lines in
// each minute, counting down from 10 Nov 18:59
const minuteLabel = i => { const d = new Date(Date.UTC(2026, 10, 10, 18, 59) - i * 60000); const p = n => String(n).padStart(2, "0");
  return `${p(d.getUTCDate())}.${p(d.getUTCMonth() + 1)}. ${p(d.getUTCHours())}:${p(d.getUTCMinutes())} UTC`; };
const linesOf = counts => counts.flatMap((c, i) => Array.from({ length: c }, (_, j) => [minuteLabel(i), `line ${i}.${j}`, `${100 + j} AS$ C`]));
const minute = row => row[0].slice(0, 12);
// every part's last minute differs from the next part's first: no minute in two parts
const minutesWhole = parts => new Set(parts.flatMap(p => [...new Set(p.map(minute))])).size === parts.reduce((n, p) => n + new Set(p.map(minute)).size, 0);

// ---------------------------------------------------------------- 1. the parts
await check("the script hands over the statement's logic in Node: the limit 500, the safety stop 60 pages, the date stop 26 hours", () => {
  for (const f of ["statementParts", "statementPage", "statementWords", "statementStopWords"]) assert.equal(typeof S[f], "function", f);
  assert.equal(S.STATEMENT_PART_LINES, 500);
  assert.equal(S.STATEMENT_MAX_PAGES, 60);
  assert.equal(S.STATEMENT_HOURS, 26);
  assert.equal(S.STATEMENT_URL, "/app/finance/accounting/2");
});
await check("a minute is never split: 2,412 lines (Ryanair's 10 Nov size) in parts of at most 500, each cut between two minutes", () => {
  const rows = linesOf(Array.from({ length: 400 }, (_, i) => [3, 7, 9, 4, 1, 8][i % 6])).slice(0, 2412);
  const parts = plain(S.statementParts(rows, 500));
  assert.ok(parts.length >= 5, "2,412 lines need at least 5 parts of 500, got " + parts.length);
  assert.ok(parts.every(p => p.length > 0 && p.length <= 500), "a part over 500 lines: " + parts.map(p => p.length).join(", "));
  assert.ok(minutesWhole(parts), "a minute is in two parts");
  // each cut is at the last minute boundary that fits: adding the next minute would pass 500
  for (let k = 0; k + 1 < parts.length; k++) {
    const next = parts[k + 1], first = minute(next[0]), size = next.filter(r => minute(r) === first).length;
    assert.ok(parts[k].length + size > 500, `part ${k + 1} (${parts[k].length} lines) could have taken the next minute (${size} lines)`);
  }
});
await check("every line is kept, in the game's order (newest first)", () => {
  const rows = linesOf(Array.from({ length: 300 }, (_, i) => 1 + (i * 7) % 11));
  for (const max of [1, 5, 50, 499, 500, 501, 5000]) assert.deepEqual(plain(S.statementParts(rows, max)).flat(), plain(rows), "with max " + max);
});
await check("a minute bigger than the limit stays whole, in a part of its own", () => {
  const rows = linesOf([200, 620, 30, 400, 40]);
  const parts = plain(S.statementParts(rows, 500));
  assert.deepEqual(parts.map(p => p.length), [200, 620, 470]);
  assert.equal(new Set(parts[1].map(minute)).size, 1, "the 620-line minute shares its part");
  assert.ok(minutesWhole(parts));
  assert.deepEqual(parts.flat(), plain(rows));
});
await check("one part when under the limit, and one empty part with no lines (the page is still sent and judged)", () => {
  const rows = linesOf([3, 4, 5]);
  assert.deepEqual(plain(S.statementParts(rows, 500)), [plain(rows)]);
  assert.deepEqual(plain(S.statementParts(rows)), [plain(rows)], "the default limit is 500");
  assert.deepEqual(plain(S.statementParts(linesOf([500]), 500)), [plain(linesOf([500]))], "exactly 500 lines is one part");
  assert.deepEqual(plain(S.statementParts([], 500)), [[]]);
  assert.deepEqual(plain(S.statementParts(null, 500)), [[]]);
});
await check("the saved evening's statement (445 lines): in parts of at most 150 cut between minutes, every line kept", () => {
  const f = readdirSync(new URL("fixtures/", here)).filter(n => /^capture_pages_.*\.json\.gz$/.test(n)).sort().pop();
  assert.ok(f, "no tests/fixtures/capture_pages_*.json.gz");
  const sample = JSON.parse(gunzipSync(readFileSync(new URL("fixtures/" + f, here))).toString("utf8"));
  const rows = sample.pages.find(p => p.kind === "statement").rows.filter(x => /^\d\d\.\d\d\. \d\d:\d\d/.test(x[0]));
  assert.equal(rows.length, 445);
  const parts = plain(S.statementParts(rows, 150));
  assert.ok(parts.length >= 3 && parts.every(p => p.length <= 150), parts.map(p => p.length).join(", "));
  assert.ok(minutesWhole(parts), "a minute is in two parts");
  assert.deepEqual(parts.flat(), plain(rows));
  assert.deepEqual(plain(S.statementParts(rows, 500)), [plain(rows)], "under 500 it is one part");
});

// ---------------------------------------------------------------- 2. the page names
await check("each part's page: /app/finance/accounting/2#run=<ISO>&part=<k>/<n>, as private.statement_run() reads it", () => {
  const run = "2026-11-10T19:02:03.123Z";
  assert.equal(S.statementPage(run, 1, 5), "/app/finance/accounting/2#run=2026-11-10T19:02:03.123Z&part=1/5");
  assert.equal(S.statementPage(run, 5, 5), "/app/finance/accounting/2#run=2026-11-10T19:02:03.123Z&part=5/5");
  // the migration's own pattern reads the run and part back
  const dir = new URL("../database/migrations/", here);
  const mig = readdirSync(dir).filter(n => /_whole_statement\.sql$/.test(n)).sort().pop();
  assert.ok(mig, "no migration *_whole_statement.sql");
  const pat = readFileSync(new URL(mig, dir), "utf8").match(/regexp_match\(coalesce\(p_page, ''\), '([^']+)'\)/);
  assert.ok(pat, "the migration's statement_run() pattern isn't found");
  const m = S.statementPage(run, 3, 5).match(new RegExp(pat[1]));
  assert.deepEqual(m && [m[1], m[2], m[3]], [run, "3", "5"]);
  assert.equal("/app/finance/accounting/2".match(new RegExp(pat[1])), null, "a page without a run names one");
});

// ---------------------------------------------------------------- 3. the panel
await check("the panel: \"Ryanair · statement 2,412 lines, 24 pages, 5 parts\", or the first failed part's error", () => {
  const ok = n => ({ ok: true, rows: n });
  assert.equal(S.statementWords("Ryanair", [ok(500), ok(498), ok(500), ok(497), ok(417)], 24), "Ryanair · statement 2,412 lines, 24 pages, 5 parts");
  assert.equal(S.statementWords("Pan Am", [ok(812)], 9), "Pan Am · statement 812 lines, 9 pages, 1 part");
  assert.equal(S.statementWords("Pan Am", [ok(1)], 1), "Pan Am · statement 1 line, 1 page, 1 part");
  assert.equal(S.statementWords("Virgin", [ok(500), { ok: false, error: "canceling statement due to statement timeout" }, { ok: false, error: "later" }, ok(300)], 19),
    "Virgin · statement part 2 of 4 not stored (canceling statement due to statement timeout), 19 pages, 4 parts");
  assert.equal(S.statementWords("Virgin", [ok(500), null], 12), "Virgin · statement part 2 of 2 not stored (no answer), 12 pages, 2 parts");
  assert.equal(S.statementStopWords("Ryanair", 60, 6000), "Ryanair · statement: stopped at 60 pages, 6,000 lines");
});

// ---------------------------------------------------------------- 4. the file
await check("the file: version 1.16; every page to the date stop (26 hours) or the safety stop (60 pages), no 15-page stop; the run's time once; each part in order with its page", () => {
  assert.match(source, /^\/\/ @version\s+1\.16$/m);
  assert.equal(S.VERSION, "1.16");
  const body = source.slice(source.indexOf("async function captureCurrent("), source.indexOf("// 1.6 (spec docs/specs/2026-10-22-fleet-capture.md §1): the airline's fleet list"));
  assert.ok(!/pages < 15|3 \* 864e5/.test(body), "the old 15-page or 3-day stop is still there");
  assert.match(body, /const run = new Date\(\)\.toISOString\(\), since = Date\.now\(\) - STATEMENT_HOURS \* 36e5;/);
  assert.match(body, /if \(pages >= STATEMENT_MAX_PAGES\) \{ capped = true; break; \}/);
  assert.match(body, /if \(capped\) log\(statementStopWords\(name, pages, all\.length\)\);/);
  assert.match(body, /const parts = statementParts\(all, STATEMENT_PART_LINES\)/);
  assert.match(body, /for \(let k = 1; k <= parts\.length; k\+\+\) \{[\s\S]*?send\(id, "statement", parts\[k - 1\], statementPage\(run, k, parts\.length\)\)/);
  assert.match(body, /log\(statementWords\(name, replies, pages\)\)/);
  assert.equal((body.match(/new Date\(\)\.toISOString\(\)/g) || []).length, 1, "the run's time is taken more than once");
  // the other pages are sent as before
  for (const k of ["events", "pnl", "balance", "loads"]) assert.match(body, new RegExp(`send\\(id, "${k}", `), k);
});

console.log(failures ? `\n${failures} capture statement check(s) failed` : "\ncapture statement: all passed");
process.exit(failures ? 1 : 0);
