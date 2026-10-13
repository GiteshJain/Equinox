"""The planning library side by side with the old planner on the rehearsal's copy (decision #19, build pull request 2,
spec §4): the library's figures on last night's data must equal the old planner's Tails and Hubs screens, except where
the manual and the old planner disagree (the known differences below, each with the manual's rule).

Run by database/rehearse.sh after the other steps, once the library is built (npm run build:rules). Like
tests/real_saves_test.py, whose helpers and request mapping it uses, it needs the copy, so it isn't part of
tests/run_all.sh, and nothing goes outside.

1. rules_input() on the copy (as postgres), saved to a file only this user can read, and run through the command
   (node lib/rules/dist/cli.js): aircraft (every aircraft's figures) and connections at every base.
2. The old planner, opened as real_saves_test.py opens it (its live address mapped to a local server, the live
   Supabase address answered by the copy, its Supabase library from npm), its clock frozen at one moment (the copy's
   latest change, to the minute), signed in as a test staff user. Opening it writes nothing. The library's Tails and
   Hubs figures don't depend on the moment; the moment is printed so a later screen's comparison can use the same one.
3. Tails: for every aircraft on the Tails screen (every airline's tab), legs a week, block hours a day (to one decimal,
   as the screen rounds), maintenance (a whole percent, "400+" above 400) and routes equal the library's; and every
   aircraft the library finds flying is on the screen.
4. Hubs: for every base in the Hubs screen's list, the connections board ("Connections at ..."): the city pairs linked,
   and for each bank row the airports arriving from, the airports leaving to, the city pairs and the examples (the
   tightest eight, each with its connection time) equal the library's.
5. Block times: for every leg with stored times, the library's estimate for its route and type (manual §4) against the
   stored block_min: how many are exact, within 2 minutes and further out. Information, not a pass or fail.

A figure that differs fails its step unless it's on the list of known differences; each one used is printed with how
often. Prints registrations, airport codes, counts and figures, never anything else from the rows, since the log is
posted on the pull request. Never prints the local keys or the test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL and SECRET_TABLES.
Usage: python3 tests/rules_library_test.py
"""
import asyncio, datetime, decimal, json, os, re, secrets, subprocess, sys, tempfile
from pathlib import Path
from harness import ROOT, go, serve, settle
from playwright.async_api import async_playwright
from real_saves_test import (Planner, count_changes, counts, is_planner_user, library, local_env, log_since, make_user, marks, planner_facts,
                             psql, token_for, why)

CLI = ROOT / "lib" / "rules" / "dist" / "cli.js"
INDEX = ROOT / "lib" / "rules" / "dist" / "index.js"
failures = []

# The known differences (spec §5): where the manual and the old planner disagree, the library follows the manual. Each
# is kept here with the manual's rule beside it, and counted each time it explains a figure that differs.
KNOWN = {
    "block estimates": {
        "rule": "manual §4: block time = block_allowance_min + distance ÷ the type's cruise_kmh. The old planner fits its estimate to "
                "the times typed in (calibration); the library follows the manual. Only legs without stored times use an estimate.",
        "used": 0, "where": []},
    "minimum connection time": {
        "rule": "manual §4: each airport's minimum connection time (world_airports.mct_min). The old planner uses its hub's figure, or 90 "
                "minutes elsewhere (mctAt), and a hub with no figure feeds no bank; the library uses 90 only where mct_min is empty.",
        "used": 0, "where": []},
}


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:16]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


def to_fixed(x, places=1):
    """JavaScript's Number.prototype.toFixed: the exact value of the double, halves rounded up."""
    q = decimal.Decimal(1).scaleb(-places)
    return str(decimal.Decimal(x).quantize(q, rounding=decimal.ROUND_HALF_UP))


def maint_text(ratio):
    """The Tails screen's maintenance pill (maintPill): Math.round(ratio × 100), "400+" above 400, "—" without a figure."""
    if ratio is None:
        return "—"
    p = int(decimal.Decimal(ratio * 100).to_integral_value(rounding=decimal.ROUND_HALF_UP))
    return "400+" if p > 400 else str(p)


def cli(*args):
    r = subprocess.run(["node", str(CLI), *map(str, args)], capture_output=True, text=True, timeout=300)
    if r.returncode:
        raise RuntimeError(f"the command {' '.join(map(str, args[:1]))} failed: " + (r.stderr.strip().splitlines() or ["no output"])[-1][:200])
    return json.loads(r.stdout)


def hm(m):
    return f"{m // 60}:{m % 60:02d}"


class FrozenPlanner(Planner):
    """real_saves_test.py's Planner, its clock frozen at one moment before the page's scripts run."""

    def __init__(self, *a, moment, **k):
        super().__init__(*a, **k)
        self.moment = moment

    async def page(self, host=None):
        from harness import LIVE_HOST
        self.pg = pg = await self.ctx.new_page()
        await pg.clock.set_fixed_time(self.moment)
        pg.on("pageerror", lambda e: self.errors.append("page error: " + str(e)[:200]))
        pg.on("console", lambda m: self.errors.append("console error: " + m.text[:200])
              if m.type == "error" and "Failed to load resource" not in m.text else None)
        pg.on("dialog", lambda d: (self.dialogs.append(d.message[:160]), asyncio.ensure_future(d.dismiss())))
        await pg.goto(f"http://{host or LIVE_HOST}:{self.port}/planner/")
        return pg


# ---------- 3. Tails ----------
TAILS_ROWS = """() => [...document.querySelectorAll('#view table.tbl tr[data-tail]')].map(tr => {
  const td = [...tr.querySelectorAll('td')].map(x => x.textContent.replace(/\\s+/g, ' ').trim());
  return { reg: tr.dataset.tail, legs: td[4], block: td[5], maint: td[6], routes: td[7] }; })"""


async def old_tails(pg):
    await go(pg, "tails")
    airlines = await pg.evaluate("[...document.querySelectorAll('.toolbar .seg button[data-al]')].map(b => b.dataset.al)")
    rows = {}
    for al in airlines:
        await pg.evaluate("a => [...document.querySelectorAll('.toolbar .seg button[data-al]')].find(b => b.dataset.al === a).click()", al)
        await settle(pg, 300)
        for r in await pg.evaluate(TAILS_ROWS):
            rows[r["reg"]] = dict(r, airline=al)
    return airlines, rows


def compare_tails(old, lib):
    """Problems (not on the known list) and the known differences used, comparing the Tails screen with the library."""
    by_reg = {a["registration"]: a for a in lib}
    problems = []
    for reg, o in sorted(old.items()):
        a = by_reg.get(reg)
        if not a:
            problems.append(f"{reg} ({o['airline']}) is on the Tails screen, but the library has no such aircraft")
            continue
        mine = {"legs": str(a["legs_week"]), "block": to_fixed(a["block_hours_day"]), "maint": maint_text(a["maintenance_ratio"]), "routes": str(a["routes"])}
        theirs = {"legs": o["legs"], "block": o["block"], "maint": o["maint"].replace("≈", "").replace("%", ""), "routes": o["routes"]}
        diff = [f"{k} {theirs[k]} on the screen, {mine[k]} in the library" for k in mine if mine[k] != theirs[k]]
        if not diff:
            continue
        if a.get("estimated_legs"):
            KNOWN["block estimates"]["used"] += 1
            KNOWN["block estimates"]["where"].append(f"{reg}: {'; '.join(diff)} ({a['estimated_legs']} departures a week estimated)")
        else:
            problems.append(f"{reg}: {'; '.join(diff)}")
    for a in lib:
        if a["legs_week"] and a["registration"] not in old:
            problems.append(f"{a['registration']} flies {a['legs_week']} legs a week in the library, but isn't on the Tails screen")
    return problems


# ---------- 4. Hubs ----------
HUB_BOARD = """(code) => {
  const h = [...document.querySelectorAll('#view h3.rh')].find(x => x.textContent.trim().startsWith('Connections at ' + code + ' '));
  if (!h) return null;
  const board = h.closest('.board') || h.parentElement;
  const m = /(\\d+) city pairs linked/.exec(h.textContent);
  const rows = [...board.querySelectorAll('table.tbl tr')].filter(tr => tr.querySelector('td')).map(tr => {
    const td = [...tr.querySelectorAll('td')];
    const first = x => parseInt((x.firstChild ? x.firstChild.textContent : x.textContent).trim(), 10);
    return { label: td[0].textContent.trim(), a: first(td[1]), d: first(td[2]), p: parseInt(td[3].textContent.trim(), 10), ex: td[4].textContent.trim() };
  });
  return { pairs: m ? parseInt(m[1], 10) : null, empty: !!board.querySelector('.dim') && !board.querySelector('table.tbl'), rows };
}"""


async def old_hubs(pg):
    await go(pg, "hub")
    codes = await pg.evaluate("[...document.querySelectorAll('#h-hub option')].map(o => o.value)")
    out = {}
    for code in codes:
        await pg.select_option("#h-hub", code)
        await settle(pg, 250)
        out[code] = await pg.evaluate(HUB_BOARD, code)
    return codes, out


def parse_examples(text):
    out = []
    for part in text.replace("…", "").split(","):
        m = re.match(r"^\s*([A-Z0-9]{3})→([A-Z0-9]{3}) (\d+):(\d{2})\s*$", part)
        if m:
            out.append((m[1], m[2], int(m[3]) * 60 + int(m[4])))
    return out


def bank_of(label):
    m = re.match(r"^Bank (\d+)", label)
    return int(m[1]) if m else 0


def compare_hub(code, old, lib, estimated_here, mct_missing):
    if old is None:
        return [f"{code}: the Hubs screen shows no connections board"]
    problems = []
    if old["pairs"] != len(lib["city_pairs"]):
        problems.append(f"{code}: {old['pairs']} city pairs linked on the screen, {len(lib['city_pairs'])} in the library")
    if not old["rows"]:
        if lib["arrivals"] and lib["departures"] and lib["city_pairs"]:
            problems.append(f"{code}: the screen has no flights both arriving and leaving, the library has {lib['arrivals']} arrivals and {lib['departures']} departures")
    else:
        mine = {r["n"]: r for r in lib["by_bank"]}
        theirs = {bank_of(r["label"]): r for r in old["rows"]}
        if sorted(mine) != sorted(theirs):
            problems.append(f"{code}: bank rows {sorted(theirs)} on the screen, {sorted(mine)} in the library")
        for n in sorted(set(mine) & set(theirs)):
            m, t = mine[n], theirs[n]
            got = (len(m["arriving_from"]), len(m["leaving_to"]), m["city_pairs"])
            if got != (t["a"], t["d"], t["p"]):
                problems.append(f"{code} bank {n}: arriving from {t['a']}, leaving to {t['d']}, {t['p']} city pairs on the screen; "
                                f"{got[0]}, {got[1]}, {got[2]} in the library")
            ex = parse_examples(t["ex"])
            pairs = sorted((p for p in lib["city_pairs"] if p["bank"] == n), key=lambda p: p["gap_min"])
            have = {(p["from"], p["to"], p["gap_min"]) for p in pairs}
            if sorted(e[2] for e in ex) != [p["gap_min"] for p in pairs[:len(ex)]] or len(ex) != min(8, len(pairs)):
                shown = ", ".join(a + "→" + b + " " + hm(g) for a, b, g in ex)
                ours = ", ".join(p["from"] + "→" + p["to"] + " " + hm(p["gap_min"]) for p in pairs[:8])
                problems.append(f"{code} bank {n}: the tightest connections on the screen ({shown}) aren't the library's ({ours})")
            elif any(e not in have for e in ex):
                problems.append(f"{code} bank {n}: an example on the screen isn't one of the library's city pairs at that time")
    if problems and estimated_here:
        KNOWN["block estimates"]["used"] += 1
        KNOWN["block estimates"]["where"].append(f"{code}: " + "; ".join(problems) + f" ({estimated_here} legs here have an estimated block)")
        return []
    if problems and mct_missing:
        KNOWN["minimum connection time"]["used"] += 1
        KNOWN["minimum connection time"]["where"].append(f"{code} (no mct_min: the library uses 90): " + "; ".join(problems))
        return []
    return problems


# ---------- 5. block times ----------
BLOCKS_JS = """
import { readFileSync } from "node:fs";
const [input, dist] = process.argv.slice(1);
const lib = await import(dist);
const rules = lib.buildRules(JSON.parse(readFileSync(input, "utf8")));
const out = [];
for (const l of rules.legs) {
  if (l.block_min == null) continue;
  let est = null, why = null;
  if (!lib.typeOfAircraft(rules, l.aircraft_id)) why = "no aircraft type";
  else { try { est = lib.block.legBlock(rules, { ...l, block_min: null })?.minutes ?? null; if (est == null) why = "no distance"; } catch (e) { why = e.message; } }
  out.push({ id: l.id, origin: l.origin_code, dest: l.dest_code, stored: l.block_min, estimate: est, why });
}
console.log(JSON.stringify(out));
"""


def block_counts(path):
    r = subprocess.run(["node", "--input-type=module", "-e", BLOCKS_JS, str(path), INDEX.as_uri()], capture_output=True, text=True, timeout=300)
    if r.returncode:
        raise RuntimeError((r.stderr.strip().splitlines() or ["no output"])[-1][:200])
    rows = json.loads(r.stdout)
    est = [x for x in rows if x["estimate"] is not None]
    diffs = [abs(x["estimate"] - x["stored"]) for x in est]
    far = sorted((x for x in est if abs(x["estimate"] - x["stored"]) > 2), key=lambda x: -abs(x["estimate"] - x["stored"]))
    return {"legs": len(rows), "exact": diffs.count(0), "within2": sum(1 for d in diffs if 0 < d <= 2), "further": len(far),
            "worst": max(diffs) if diffs else 0, "none": len(rows) - len(est),
            "far": [f"{x['origin']}–{x['dest']} {x['stored']} stored, {x['estimate']} estimated" for x in far[:6]]}


async def main():
    facts = planner_facts()
    if not facts:
        step(False, "the old planner names its Supabase address, public key and library", ["not found in web/planner/index.html"])
        sys.exit(1)
    if not CLI.is_file():
        step(False, "the planning library is built", ["lib/rules/dist/cli.js is missing: run npm run build:rules first"])
        sys.exit(1)
    try:
        env = local_env()
        lib_js = library(facts["lib_version"])
    except Exception as e:
        step(False, "set up: the copy's address and the old planner's Supabase library from npm", [why(e)])
        sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="rules-library-"))
    os.chmod(work, 0o700)
    path = work / "rules_input.json"
    # ---------- 1. rules_input() through the command
    try:
        doc = psql("select public.rules_input()::text").strip()
        path.write_text(doc)
        os.chmod(path, 0o600)
        data = json.loads(doc)
        aircraft = cli("aircraft", path)
        bases = sorted({b["airport_code"] for b in data["airline_bases"]})
        conns = {code: cli("connections", path, code) for code in bases}
        estimated = [l for l in data["flight_legs"] if l["block_min"] is None and l["dep_utc_min"] is not None]
        problems = []
    except Exception as e:
        problems, data, aircraft, conns, bases, estimated = [why(e)], None, [], {}, [], []
    step(not problems, (f"rules_input() on the copy ({len(data['flight_legs'])} legs, {len(data['aircraft'])} aircraft, {len(bases)} bases, "
                        f"{len(data['airports'])} airports; {len(estimated)} legs without stored times), run through the command: aircraft, and "
                        f"connections at each base" if data else "rules_input() on the copy, run through the command"), problems)
    if problems:
        sys.exit(1)
    mct = {a["code"]: a.get("mct_min") for a in data["airports"]}

    # ---------- 2. the old planner at a frozen moment
    moment = psql("select to_char(date_trunc('minute', coalesce(max(changed_at), now())) at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:00\"Z\"') from public.change_log").strip()
    tag = secrets.token_hex(4)
    staff = (f"rules-library-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    with serve() as port:
        async with async_playwright() as p:
            pl = FrozenPlanner(p, port, env, facts, lib_js, moment=moment)
            try:
                n0, mark = counts(), marks()
                await pl.open()
                await pl.sign_in(*staff)
                problems = list(pl.errors)
                if log_since(mark):
                    problems.append("opening the old planner changed the tables")
                problems += count_changes(n0, counts())
                now_shown = await pl.pg.evaluate("Date.now()")
                if abs(now_shown - datetime.datetime.fromisoformat(moment.replace("Z", "+00:00")).timestamp() * 1000) > 1000:
                    problems.append("the old planner's clock isn't frozen at the moment")
                opened = not problems
            except Exception as e:
                problems, opened = [why(e)] + pl.errors[:3], False
            step(opened, f"the old planner opened as real_saves_test.py opens it, signed in as test staff, its clock frozen at {moment}; opening it wrote nothing", problems)

            # ---------- 3. Tails
            if opened:
                try:
                    airlines, rows = await old_tails(pl.pg)
                    problems = compare_tails(rows, aircraft) + pl.errors
                    label = (f"Tails: legs a week, block hours a day, maintenance and routes equal the old planner's for all {len(rows)} aircraft "
                             f"({len(airlines)} airlines)")
                except Exception as e:
                    problems, label = [why(e)], "Tails"
                step(not problems, label, problems)

                # ---------- 4. Hubs
                try:
                    codes, boards = await old_hubs(pl.pg)
                    problems = []
                    for code in codes:
                        lib = conns.get(code) or cli("connections", path, code)
                        here = sum(1 for l in estimated if code in (l["origin_code"], l["dest_code"]))
                        problems += compare_hub(code, boards.get(code), lib, here, mct.get(code) is None)
                    problems += pl.errors
                    total = sum(len((conns.get(c) or {}).get("city_pairs", [])) for c in codes)
                    label = (f"Hubs: the connections and city pairs at each of the {len(codes)} bases equal the old planner's Hubs screen "
                             f"({total} city pairs in all, each bank's arrivals, departures and tightest connections)")
                except Exception as e:
                    problems, label = [why(e)], "Hubs"
                step(not problems, label, problems)
            await pl.close()

    # ---------- 5. block times (information)
    try:
        c = block_counts(path)
        step(True, f"block times: of {c['legs']} legs with stored times, {c['exact']} exact, {c['within2']} within 2 minutes, {c['further']} further out "
                   f"(worst {c['worst']} minutes{': ' + '; '.join(c['far']) if c['far'] else ''}); {c['none']} without an estimate (no type or distance). "
                   "The library's estimate is 25 minutes + distance ÷ speed (manual §4); information, not a pass or fail")
    except Exception as e:
        step(False, "block times", [why(e)])

    # ---------- known differences used
    base_codes = set(bases)
    differ = sorted((code, m) for code, m in mct.items() if code not in base_codes and m is not None and m != 90)
    missing = sorted(code for code in base_codes if mct.get(code) is None)
    for key, k in KNOWN.items():
        print(f"known difference \"{key}\": used {k['used']} time(s). {k['rule']}", flush=True)
        for w in k["where"][:12]:
            print("      " + w, flush=True)
    print(f"      minimum connection time: {len(differ)} airport(s) that aren't bases have their own figure, where the old planner's mctAt uses 90"
          + (": " + ", ".join(f"{c} {m}" for c, m in differ[:60]) + (" …" if len(differ) > 60 else "") if differ else "")
          + (f"; bases with no figure: {', '.join(missing)}" if missing else "; every base has its own figure"), flush=True)
    outside = sorted(set(pl.outside))
    step(not outside and pl.copy > 0, f"nothing went outside ({pl.copy} requests answered by the copy, {pl.local} from the local server)",
         (["reached: " + ", ".join(outside)] if outside else []) + ([] if pl.copy else ["the old planner never reached the copy"]))
    for f in work.iterdir():
        f.unlink()
    work.rmdir()
    print(f"\n{len(failures)} planning-library step(s) failed" if failures else "\nplanning library on the copy: all passed", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
