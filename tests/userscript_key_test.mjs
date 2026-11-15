// The capture and fares userscripts' key and version (capture 1.17, fares 1.5; to-do 247, spec
// docs/specs/2026-11-15-self-updating-scripts.md §2 to §5), with no browser and no game: each file runs in Node, where
// (with no page) it only hands over its logic, with stand-ins for the userscript app's storage (GM), the prompt() box
// and the update address.
// Checks:
//   1. The shared block is the same in both files.
//   2. The key: the filled-in placeholder (the unattended run) is used and GM never touched, even with no GM at all; a
//      kept key is used; none kept is asked for once and kept; nothing typed keeps nothing; a "bad key" answer forgets a
//      kept or typed key and asks once more, never for the filled-in one.
//   3. The guard: on a device a newer version at the address stops the press before the key is read or anything is
//      called; the same or an older one goes on; an address that doesn't answer, or answers without a version, is a line
//      and the press goes on; the unattended run never asks the address. A run started by another version stops.
//   4. The files: the update and download addresses (the raw file on main, ending .user.js), the three @grant lines and
//      no @grant none, @name unchanged, the placeholder once (so the unattended run's fill-in finds it however it
//      replaces), the key never written to the page's storage, the console or a run's state, and each version raised
//      above main's when the file changed.
// Usage: node tests/userscript_key_test.mjs
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const FILES = {
  capture: { path: "capture/capture_all.user.js", name: "equinox. capture all airlines", lib: "eqScan" },
  fares: { path: "capture/fares_apply.user.js", name: "equinox. apply fare plan", lib: "eqFares" },
};
const RAW = "https://raw.githubusercontent.com/GiteshJain/Equinox/main/";
for (const f of Object.values(FILES)) {
  f.source = readFileSync(new URL("../" + f.path, here), "utf8");
  const sandbox = { setTimeout, clearTimeout }; vm.createContext(sandbox); vm.runInContext(f.source, sandbox, { filename: f.path });
  f.L = sandbox[f.lib];
}
const C = FILES.capture.L;
const plain = v => JSON.parse(JSON.stringify(v));

let failures = 0;
async function check(name, fn) {
  try { await fn(); console.log("ok    " + name); }
  catch (e) { failures++; console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); }
}

// a stand-in for the app's storage (GM.getValue, GM.setValue, GM.deleteValue), recording every call
function gm(start = {}) {
  const kept = { ...start }, calls = [];
  return { kept, calls,
    getValue: async (k, d) => { calls.push(["get", k]); return k in kept ? kept[k] : d; },
    setValue: async (k, v) => { calls.push(["set", k]); kept[k] = v; },
    deleteValue: async k => { calls.push(["delete", k]); delete kept[k]; } };
}
// a stand-in for the prompt() box: answers in turn, recording the words asked
function asker(...answers) { const asked = []; const fn = words => { asked.push(words); return answers.length ? answers.shift() : null; }; fn.asked = asked; return fn; }
// a stand-in for the update address: the file's text with this version, recording each fetch
function address(version) { const urls = []; const fn = async url => { urls.push(url); if (version instanceof Error) throw version; return version === null ? "no header here" : `// ==UserScript==\n// @version      ${version}\n// ==/UserScript==\n`; }; fn.urls = urls; return fn; }
const PLACEHOLDER = "__CAPTURE" + "_KEY__";   // written in two parts, so this file holds no copy of it either
const device = (extra = {}) => ({ name: "capture", own: "1.17", url: RAW + "capture/capture_all.user.js", baked: PLACEHOLDER, ...extra });

// ---------------------------------------------------------------- 1. the shared block
await check("the shared block (the key and the version) is the same in both files, and both hand it over", () => {
  const blockOf = s => { const a = s.indexOf("  // ---------------------------------------------------------------- the key and the version (shared block)"),
    b = s.indexOf("  // ---------------------------------------------------------------- end of the shared block"); assert.ok(a > 0 && b > a, "no shared block"); return s.slice(a, b); };
  assert.equal(blockOf(FILES.capture.source), blockOf(FILES.fares.source));
  for (const f of Object.values(FILES)) for (const fn of ["prepare", "withKey", "resumeKey", "keyOf", "versionCheck", "isNewer", "unfilled"]) assert.equal(typeof f.L[fn], "function", f.path + " " + fn);
});

// ---------------------------------------------------------------- 2. the key
await check("the placeholder: unfilled in the repository, filled by the unattended run", () => {
  assert.equal(C.unfilled(PLACEHOLDER), true);
  assert.equal(C.unfilled(""), true); assert.equal(C.unfilled(undefined), true);
  assert.equal(C.unfilled("3f9a0c7e2b1d4e5f6a7b8c9d0e1f2a3b"), false);
});
await check("the unattended run (placeholder filled, no GM at all): its key is used, the address never asked, nothing stored", async () => {
  const fetchText = address("9.9");
  for (const store of [null, gm()]) {
    const r = plain(await C.prepare(device({ baked: "the-job's-key", store, ask: asker("typed"), fetchText })));
    assert.deepEqual(r, { key: "the-job's-key", from: "text", lines: [] });
    if (store) assert.deepEqual(store.calls, []);
  }
  assert.deepEqual(fetchText.urls, [], "the unattended run asked the update address");
  // a bad key there is the database's answer, never a reason to ask: no prompt in a job
  const ask = asker("typed"), store = gm(), calls = [];
  const r = await C.withKey(device({ baked: "the-job's-key", store, ask }), { key: "the-job's-key", from: "text" }, async k => { calls.push(k); return { ok: false, error: "bad key" }; });
  assert.deepEqual(plain(calls), ["the-job's-key"]); assert.deepEqual(ask.asked, []); assert.deepEqual(store.calls, []);
  assert.equal(r.answer.error, "bad key");
});
await check("on the Mac, a key kept in the app's storage is used without asking", async () => {
  const store = gm({ capture_key: "kept-key" }), ask = asker("typed");
  const r = plain(await C.prepare(device({ store, ask, fetchText: address("1.17") })));
  assert.deepEqual(r, { key: "kept-key", from: "stored", lines: [] });
  assert.deepEqual(ask.asked, []);
});
await check("no key kept: the first press asks once in prompt() and keeps what was typed (trimmed)", async () => {
  const store = gm(), ask = asker("  typed-key \n");
  const r = plain(await C.prepare(device({ store, ask, fetchText: address("1.17") })));
  assert.deepEqual(r, { key: "typed-key", from: "asked", lines: [] });
  assert.equal(ask.asked.length, 1);
  assert.match(ask.asked[0], /paste the capture key once\. It is kept in this browser's userscript storage, not in the script or the page/);
  assert.deepEqual(store.kept, { capture_key: "typed-key" });
});
await check("nothing typed (Cancel or an empty box): the press stops and nothing is kept", async () => {
  for (const typed of [null, "", "   "]) {
    const store = gm();
    const r = plain(await C.prepare(device({ store, ask: asker(typed), fetchText: address("1.17") })));
    assert.match(r.stop, /no capture key \(no key typed\)\. Press again and paste the key when asked/);
    assert.deepEqual(store.kept, {});
  }
});
await check("no storage from the app (GM missing on a device): the press stops and says so", async () => {
  const r = plain(await C.prepare(device({ store: null, ask: asker("typed"), fetchText: address("1.17") })));
  assert.match(r.stop, /gives this script no storage \(GM\.getValue\)/);
});
await check("a kept key the database refuses (\"bad key\") is forgotten, asked for once more, and the new one kept", async () => {
  const store = gm({ capture_key: "old-key" }), ask = asker("new-key"), calls = [];
  const io = device({ store, ask });
  const r = await C.withKey(io, { key: "old-key", from: "stored" }, async k => { calls.push(k); return k === "new-key" ? { ok: true, airlines: [] } : { ok: false, error: "bad key" }; });
  assert.deepEqual(plain(calls), ["old-key", "new-key"]);
  assert.equal(r.key, "new-key"); assert.equal(r.answer.ok, true);
  assert.equal(ask.asked.length, 1); assert.match(ask.asked[0], /didn't accept the key kept in this browser/);
  assert.deepEqual(store.kept, { capture_key: "new-key" });
});
await check("a second refused key is forgotten too; nothing typed the second time gives the refusal back", async () => {
  const store = gm({ capture_key: "old-key" });
  const r = await C.withKey(device({ store, ask: asker("wrong-again") }), { key: "old-key", from: "stored" }, async () => ({ ok: false, error: "bad key" }));
  assert.equal(r.answer.error, "bad key"); assert.deepEqual(store.kept, {});
  const s2 = gm({ capture_key: "old-key" });
  const r2 = await C.withKey(device({ store: s2, ask: asker(null) }), { key: "old-key", from: "stored" }, async () => ({ ok: false, error: "bad key" }));
  assert.equal(r2.key, null); assert.equal(r2.answer.error, "bad key"); assert.deepEqual(s2.kept, {});
});
await check("any other answer (an error that isn't the key, or ok) keeps the key and asks nothing", async () => {
  const store = gm({ capture_key: "kept-key" }), ask = asker("typed");
  const r = await C.withKey(device({ store, ask }), { key: "kept-key", from: "stored" }, async () => ({ code: "57014", message: "timeout" }));
  assert.equal(r.key, "kept-key"); assert.deepEqual(ask.asked, []); assert.deepEqual(store.kept, { capture_key: "kept-key" });
});

// ---------------------------------------------------------------- 3. the guard
await check("versions compare number by number, as the apps compare them", () => {
  assert.equal(C.isNewer("1.9", "1.10"), true); assert.equal(C.isNewer("1.16", "1.17"), true); assert.equal(C.isNewer("1.17", "1.17"), false);
  assert.equal(C.isNewer("1.17", "1.16"), false); assert.equal(C.isNewer("1.5", "1.5.1"), true); assert.equal(C.isNewer("2.0", "1.99"), false);
  assert.equal(C.versionOf("// ==UserScript==\n// @name x\n// @version      1.18\n"), "1.18");
  assert.equal(C.versionOf("nothing"), null);
});
await check("the guard: a newer version at the address stops the press before the key is read, asked or used", async () => {
  const store = gm({ capture_key: "kept-key" }), ask = asker("typed"), fetchText = address("1.18");
  const r = plain(await C.prepare(device({ store, ask, fetchText })));
  assert.equal(r.stop, "equinox. capture: this is version 1.17, and 1.18 is out, so nothing was done. Update it (Tampermonkey's menu → Check for userscript updates; in the Userscripts app, its popup → Update), reload the page and press again.");
  assert.equal(r.key, undefined);
  assert.deepEqual(store.calls, [], "the key was read by an out-of-date script"); assert.deepEqual(ask.asked, []);
  assert.deepEqual(fetchText.urls, [RAW + "capture/capture_all.user.js"]);
});
await check("the guard: the same or an older version at the address goes on with no line", async () => {
  for (const v of ["1.17", "1.16"]) assert.deepEqual(plain(await C.prepare(device({ store: gm({ capture_key: "k" }), fetchText: address(v) }))).lines, []);
});
await check("the guard: an address that doesn't answer, or answers without a version, is a line and the press goes on", async () => {
  const a = plain(await C.prepare(device({ store: gm({ capture_key: "k" }), fetchText: address(new Error("HTTP 503")) })));
  assert.equal(a.key, "k"); assert.deepEqual(a.lines, ["couldn't check for a newer version (HTTP 503); going on with 1.17"]);
  const b = plain(await C.prepare(device({ store: gm({ capture_key: "k" }), fetchText: address(null) })));
  assert.deepEqual(b.lines, ["couldn't check for a newer version (no @version at the update address); going on with 1.17"]);
  assert.equal(C.GUARD_TIMEOUT_MS, 5000);
});
await check("the guard: an address that never answers gives up after its timeout and goes on", async () => {
  const sandbox = { setTimeout: fn => { fn(); return 0; }, clearTimeout: () => {} };   // the 5 s timer fires at once
  vm.createContext(sandbox); vm.runInContext(FILES.capture.source, sandbox);
  const r = plain(await sandbox.eqScan.versionCheck(() => new Promise(() => {}), "1.17", "u"));
  assert.deepEqual(r, { state: "unknown", why: "no answer in 5 s" });
});
await check("a run carried on after a page load: stopped when another version started it; else the kept key, never asking", async () => {
  const store = gm({ capture_key: "kept-key" });
  const stop = plain(await C.resumeKey(device({ store }), { version: "1.16" }));
  assert.match(stop.stop, /updated during the run \(started on 1\.16, now 1\.17\), so it stopped here\. What's done stays done: press again\./);
  assert.match(plain(await C.resumeKey(device({ store }), {})).stop, /started on an older version/);
  assert.deepEqual(plain(await C.resumeKey(device({ store }), { version: "1.17" })), { key: "kept-key", from: "stored" });
  assert.match(plain(await C.resumeKey(device({ store: gm() }), { version: "1.17" })).stop, /can't carry on \(no key kept in this browser\)/);
  // the unattended run: its own key, whatever the state's version
  assert.deepEqual(plain(await C.resumeKey(device({ baked: "job-key", store: null }), { version: "1.16" })), { key: "job-key", from: "text" });
});
await check("the pages use them: the capture's press and carried-on run, the fares script's press and carried-on run", () => {
  const cap = FILES.capture.source, far = FILES.fares.source;
  assert.match(cap, /prep = await prepare\(io\)[\s\S]{0,200}if \(prep\.stop\) \{ show\(prep\.stop\); b\.disabled = false; return; \}[\s\S]{0,200}withKey\(io, prep,/);
  assert.match(cap, /set\(\{ i: 0, phase: "switch", start, version: VERSION,/);
  assert.match(cap, /resumeKey\(io, s\)\.then\(r => \{ if \(r\.stop\)/);
  assert.match(far, /prep = await prepare\(io\)[\s\S]{0,200}if \(prep\.stop\) \{ btn\.disabled = false; return show\(prep\.stop/);
  assert.match(far, /const t = \{ phase: "switch", version: VERSION,/);
  assert.match(far, /else if \(unfilled\(KEY\) && s\.version !== VERSION\) finish\(s, midRunWords/);
  // the store is the app's GM only where the app gives it: the unattended run's page has none
  for (const s of [cap, far]) assert.match(s, /const store = typeof GM !== "undefined" && GM && typeof GM\.getValue === "function" \? GM : null;/);
});

// ---------------------------------------------------------------- 4. the files
for (const [kind, f] of Object.entries(FILES)) {
  await check(`${f.path}: the update and download addresses, the three @grant lines, @name unchanged`, () => {
    const header = f.source.slice(0, f.source.indexOf("// ==/UserScript=="));
    const url = RAW + f.path;
    assert.match(header, new RegExp("^// @name\\s+" + f.name.replace(/\./g, "\\.") + "$", "m"), "@name changed: the kept key would be lost");
    assert.equal((header.match(/^\/\/ @updateURL\s+(\S+)$/m) || [])[1], url);
    assert.equal((header.match(/^\/\/ @downloadURL\s+(\S+)$/m) || [])[1], url);
    assert.ok(url.endsWith(".user.js") && !/[?#]/.test(url));
    assert.deepEqual(header.match(/^\/\/ @grant\s+\S+$/gm).map(l => l.split(/\s+/)[2]).sort(), ["GM.deleteValue", "GM.getValue", "GM.setValue"]);
    assert.ok(!/@grant\s+none/.test(header), "@grant none is left");
    assert.match(f.source, new RegExp(`const UPDATE_URL = "${url.replace(/\./g, "\\.")}";`));
    assert.equal(f.L.VERSION, header.match(/^\/\/ @version\s+(\S+)$/m)[1], "VERSION isn't @version");
  });
  await check(`${f.path}: the placeholder once, as the unattended run fills it, and the key kept out of the page's storage, the console and the run's state`, () => {
    assert.equal(f.source.split(PLACEHOLDER).length, 2, "the placeholder isn't there exactly once");
    assert.ok(f.source.includes(`const KEY = "${PLACEHOLDER}"`));
    const code = f.source.replace(/^\s*\/\/.*$/gm, "");
    assert.ok(!/(?:sessionStorage|localStorage)\.setItem\([^)]*\bkey\b/.test(code), "the key written to the page's storage");
    assert.ok(!/console\.\w+\([^)]*\bkey\b/i.test(code), "the key written to the console");
    assert.ok(!/\bset\(\{[^}]*\bkey\b/.test(code), "the key put in a run's state");
    assert.ok(!/(?:show|log|note)\([^)]*\bkey\b\s*[),+]/.test(code), "the key shown in the panel");
    // the unattended run's way: the file with the placeholder filled in still loads its logic, and the key is used
    const filled = f.source.replace(PLACEHOLDER, "the-job's-key");
    const sb = { setTimeout, clearTimeout }; vm.createContext(sb); vm.runInContext(filled, sb);
    assert.equal(typeof sb[f.lib].prepare, "function");
  });
  await check(`${f.path}: its version is above main's when the file changed`, () => {
    let main = null;
    for (const ref of ["origin/main", "main"]) {
      try { main = execFileSync("git", ["show", `${ref}:${f.path}`], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], cwd: new URL("..", here) }); break; } catch (e) { /* not there */ }
    }
    if (main === null) { console.log("      (no main to compare with here: skipped)"); return; }
    if (main === f.source) return;
    const was = f.L.versionOf(main), now = f.L.versionOf(f.source);
    assert.ok(f.L.isNewer(was, now), `${f.path} changed but its version ${now} isn't above main's ${was}: the apps would never offer it`);
  });
}

console.log(failures ? `\n${failures} userscript key check(s) failed` : "\nuserscript key and version: all passed");
process.exit(failures ? 1 : 0);
