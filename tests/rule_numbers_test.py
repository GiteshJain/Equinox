"""The rule numbers, one source (design §11, choice 3; §3.7). The settings and world_rules tables are the source; the old
planner keeps its own copies in its code until #18. This check fails if the two ever differ, so a rule changed in the
tables can't silently leave the planner on the old number (or the other way round).

The planner's numbers, read from web/planner/index.html as the planner uses them:
  - CUSHION (0.5M kept in hand after an order) and LEASE_PCT (a never-leased type's weekly lease);
  - the hubs-first target (the Hubs screen's progress bars) and who is exempt (MAIN_HUB has no Ryanair);
  - the growth signals (routeProfit) and load patterns (patterns) thresholds;
  - ref.consts as the planner ends up with them: its defaults (defaultRef, and the "|| n" fallbacks where it reads
    them), with what planner_state_get() gives on top, as the planner merges them when it loads.
The tables' numbers: settings and world_rules, and planner_meta.growthRules (the hubs-first rules the scripts read),
  - with --db <url>, from that database (the rehearsal, on last night's copy after the new migrations);
  - otherwise from the test sample (tests/fixtures/sample_*.json.gz), which carries them since pull request 9.
Then it proves it would catch a change: the same comparison with one setting changed (order_cushion) must fail, naming
it. With --db the setting is changed in the database itself, inside a transaction that is rolled back.

Numbers the old planner doesn't have in its code (the fare launch, the second daily's gap, maintenance targets, the house
rules) are listed as such. Usage: python3 tests/rule_numbers_test.py [--db <url>]
"""
import json, re, subprocess, sys
from harness import WEB, sample

PLANNER = WEB / "planner" / "index.html"
failures = []


def check(ok, name, detail=""):
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok or not detail else "\n      " + detail.replace("\n", "\n      ")))
    if not ok:
        failures.append(name)


def num(x):
    return None if x is None else float(x)


# ---------- the planner's own numbers ----------
def planner_numbers(html, consts_given):
    """{(table, key, airline): value} as the old planner uses them, and the places they were read from."""
    def find(pattern, what, n=1):
        m = re.search(pattern, html)
        if not m:
            raise RuntimeError(f"not found in the planner's code: {what} ({pattern})")
        return [float(m[i]) for i in range(1, n + 1)] if n > 1 else float(m[1])
    out = {}
    out[("settings", "order_cushion", None)] = round(find(r"const CUSHION = ([\d.]+);", "CUSHION") * 1_000_000)
    out[("settings", "lease_estimate_pct", None)] = round(find(r"const LEASE_PCT = ([\d.]+);", "LEASE_PCT") * 100, 6)
    out[("settings", "hub_first_departures", None)] = round(find(r"x\.dep / ([\d.]+)\)", "the hubs-first bar (x.dep / ...)") * 100)
    bar = find(r"\} / (\d+) <span class=\"dim\">\$\{Math\.round\(x\.dep", "the hubs-first bar's label")
    hubs = re.search(r"const MAIN_HUB = \{([^}]*)\}", html)
    if not hubs:
        raise RuntimeError("not found in the planner's code: MAIN_HUB")
    out[("settings", "hub_first_exempt", "Ryanair")] = '"Ryanair"' not in hubs[1]
    days = find(r"function routeProfit\(al, days = (\d+)\)", "routeProfit's window")
    out[("settings", "growth_window_days", None)] = days
    out[("settings", "growth_losing_min_departures", None)] = find(r"r\.ppf < 0 && r\.n >= (\d+)", "losing money")
    share, n = find(r"r\.soldShare >= ([\d.]+) && r\.n >= (\d+)", "sold out", 2)
    out[("settings", "growth_sold_out_share", None)], out[("settings", "growth_sold_out_min_departures", None)] = share, n
    n, eco = find(r"else if \(r\.n >= (\d+) && r\.ecoA != null && r\.ecoA < (\d+)\)", "fix or reduce: economy", 2)
    out[("settings", "growth_fix_min_departures", None)], out[("settings", "growth_fix_economy_pct", None)] = n, eco
    routes, margin = find(r"pp\.length >= (\d+) && r\.ppf <= q25 && r\.margin != null && r\.margin < ([\d.]+)\)", "fix or reduce: margin", 2)
    out[("settings", "growth_fix_min_routes", None)], out[("settings", "growth_fix_margin", None)] = routes, margin
    n, b70, b85 = find(r"p\.n >= (\d+) && \(share\(p\.b70\) >= ([\d.]+) \|\| share\(under85\) >= ([\d.]+)\)", "patterns: cut", 3)
    out[("settings", "pattern_min_departures", None)] = n
    out[("settings", "pattern_cut_under70_share", None)], out[("settings", "pattern_cut_under85_share", None)] = b70, b85
    n2, w85 = find(r"else if \(p\.n >= (\d+) && share\(under85\) >= ([\d.]+)\)", "patterns: watch", 2)
    out[("settings", "pattern_watch_under85_share", None)] = w85
    n3, full = find(r"else if \(p\.n >= (\d+) && share\(p\.full\) >= ([\d.]+)\)", "patterns: add", 2)
    out[("settings", "pattern_add_min_departures", None)], out[("settings", "pattern_add_full_share", None)] = n3, full
    # Home's airport-cap warning (4,000 of the 5,000 cap) and the one-week check's week, settings since #18 build pull
    # request 5 (airport_cap_warning_pct, aircraft_check_after_days)
    warn, home_cap = find(r"if \(n >= (\d+)\) att\.push\(\{ cls: n >= (\d+) \? \"bad\"", "Home's airport-cap warning", 2)
    out[("settings", "airport_cap_warning_pct", None)] = round(warn / home_cap * 100, 6)
    out[("settings", "aircraft_check_after_days", None)] = find(r"const due = addDays\(last, (\d+)\);", "the one-week check's week (tailChecks)")

    # ref.consts as the planner merges them: defaultRef's, the fallbacks where it reads them, then what the getter gives
    m = re.search(r"consts: \{ ([^}]*) \}", html)
    if not m:
        raise RuntimeError("not found in the planner's code: defaultRef's consts")
    consts = {k: float(v) for k, v in re.findall(r"(\w+): ([\d.]+)", m[1])}
    for k, pat in (("leeway", r"consts\.leeway \|\| (\d+)"), ("lfWindow", r"consts\.lfWindow \|\| (\d+)"),
                   ("maintMinGround", r"consts\.maintMinGround \|\| (\d+)"), ("maxWait", r"consts\.maxWait \|\| (\d+)")):
        consts.setdefault(k, find(pat, f"the planner's fallback for ref.consts.{k}"))
    consts.update({k: float(v) for k, v in (consts_given or {}).items() if isinstance(v, (int, float)) and not isinstance(v, bool)})
    for k, key in (("buf", "bank_buffer_min"), ("ovh", "block_allowance_min"), ("arrwin", "bank_arrival_window_min"),
                   ("depwin", "bank_departure_window_min"), ("maxWait", "connection_max_wait_h"), ("legalGap", "legal_gap_h"),
                   ("turnMargin", "turn_margin_min"), ("maintMinGround", "maint_min_ground_min"), ("leeway", "load_leeway_days"),
                   ("lfWindow", "load_window_days")):
        out[("settings", key, None)] = consts.get(k)
    out[("world_rules", "departures_per_airport_week.value", None)] = consts.get("depCap")
    places = {"hub_first_departures (label)": bar, "patterns: watch needs": n2, "Home's airport cap": home_cap}
    return out, places


def meta_numbers(growth):
    """planner_meta.growthRules (what the scripts read for hubs first), as the same keys."""
    hf, fr = (growth or {}).get("hubsFirst") or {}, (growth or {}).get("freedomRoutes") or {}
    return {("settings", "hub_first_departures", None): num(hf.get("hubTarget")),
            ("settings", "contested_rival_weekly", None): num((hf.get("contested") or {}).get("airportRivalWeekly")),
            ("settings", "contested_rival_daily", None): num((hf.get("contested") or {}).get("routeRivalPerDay")),
            ("settings", "hub_first_exempt", "Ryanair"): "Ryanair" in (hf.get("exempt") or []),
            ("world_rules", "freedom_routes_max", None): num(fr.get("maxPerAirline"))}


# ---------- the tables' numbers ----------
DB_READ = """select json_build_object(
  'settings', (select coalesce(json_agg(json_build_object('key', s.key, 'airline', al.planner_name, 'value', s.value) order by s.key), '[]')
                 from public.settings s left join public.airlines al on al.id = s.airline_id
                where s.world_id = (select id from public.worlds where is_default)),
  'world_rules', (select coalesce(json_agg(json_build_object('key', r.key, 'value', r.value) order by r.key), '[]')
                    from public.world_rules r where r.world_id = (select id from public.worlds where is_default)),
  'growth', (select value from public.planner_meta where key = 'growthRules'),
  'consts', (public.planner_state_get() ->> 'json')::json -> 'ref' -> 'consts')"""


def read_db(url, change=""):
    sql = "begin;\n" + change + "\nselect (" + DB_READ + ")::text;\nrollback;\n"
    r = subprocess.run(["psql", url, "-X", "-At", "-q", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True, timeout=120)
    if r.returncode:
        raise RuntimeError("psql: " + (r.stderr.strip().splitlines() or ["failed"])[0][:200])
    return json.loads([x for x in r.stdout.splitlines() if x.strip()][-1])


def read_sample():
    S = sample()
    if "settings" not in S or "world_rules" not in S:
        raise RuntimeError("the sample has no settings or world_rules (samples carry them since #13, pull request 9)")
    return {"from": "sample", "settings": S["settings"], "world_rules": S["world_rules"], "growth": (S.get("planner_meta") or {}).get("growthRules"),
            "consts": ((S.get("planner_state") or {}).get("ref") or {}).get("consts")}


def table_numbers(d):
    out = {}
    for s in d["settings"]:
        v = s["value"]
        out[("settings", s["key"], s.get("airline"))] = v if isinstance(v, bool) else num(v) if isinstance(v, (int, float)) else v
    for r in d["world_rules"]:
        v = r["value"]
        if isinstance(v, dict):
            for k, x in v.items():
                out[("world_rules", f"{r['key']}.{k}", None)] = num(x) if isinstance(x, (int, float)) and not isinstance(x, bool) else x
        else:
            out[("world_rules", r["key"], None)] = num(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else v
    return out


# Settings added after the test sample was made (tests/fixtures/sample_2026-10-10.json.gz): without --db they can't be
# in the sample's tables, so they're listed rather than failed; with --db (the rehearsal) they're compared as the rest.
SINCE_SAMPLE = {"airport_cap_warning_pct": "13 Oct, #18 build pull request 5", "aircraft_check_after_days": "13 Oct, #18 build pull request 5"}
after_sample = []


def compare(d, html):
    """The differences, as lines; and how many numbers were compared."""
    code, _ = planner_numbers(html, d.get("consts"))
    tables = table_numbers(d)
    problems, n = [], 0
    for source, theirs in (("the planner's code", code), ("planner_meta.growthRules", meta_numbers(d.get("growth")))):
        for k, v in theirs.items():
            label = f"{k[0]}.{k[1]}" + (f" ({k[2]})" if k[2] else "")
            if k not in tables and d.get("from") == "sample" and k[1] in SINCE_SAMPLE:
                after_sample.append(f"{label} ({SINCE_SAMPLE[k[1]]}; the planner's code has {v:g})")
                continue
            n += 1
            if k not in tables:
                problems.append(f"{label}: not in the tables ({source} has {v})")
            elif tables[k] != v:
                problems.append(f"{label}: the tables say {tables[k]}, {source} {v}")
    return problems, n


def main():
    html = PLANNER.read_text()
    db = sys.argv[sys.argv.index("--db") + 1] if "--db" in sys.argv else None
    where = "last night's copy" if db else "the test sample"
    d = {"settings": [], "world_rules": []}
    try:
        d = read_db(db) if db else read_sample()
        problems, n = compare(d, html)
        code, places = planner_numbers(html, d.get("consts"))
        # the planner's own copies of one number agree with each other
        if places["hub_first_departures (label)"] != code[("settings", "hub_first_departures", None)]:
            problems.append(f"the Hubs screen says {places['hub_first_departures (label)']:g} but its bars use "
                            f"{code[('settings', 'hub_first_departures', None)]:g}")
        home_cap, cap = places["Home's airport cap"], code[("world_rules", "departures_per_airport_week.value", None)]
        if home_cap != cap:
            problems.append(f"Home warns against a cap of {home_cap:g}, but the planner's cap is {cap}")
        if places["patterns: watch needs"] != code[("settings", "pattern_min_departures", None)]:
            problems.append("load patterns: cut and watch need different numbers of departures")
    except Exception as e:
        problems, n = [f"{type(e).__name__}: {e}"], 0
    check(not problems, f"rule numbers: the old planner's {n} built-in numbers equal settings and world_rules ({where})", "\n".join(problems))
    if after_sample:
        print("      (settings newer than the test sample, so compared only on a database: " + "; ".join(sorted(set(after_sample))) + ")")

    # it would catch a change: one setting changed
    try:
        if db:
            d2 = read_db(db, "update public.settings set value = to_jsonb((value #>> '{}')::numeric + 1) "
                             "where key = 'order_cushion' and airline_id is null and world_id = (select id from public.worlds where is_default);")
        else:
            d2 = json.loads(json.dumps(d))
            for s in d2["settings"]:
                if s["key"] == "order_cushion" and not s.get("airline"):
                    s["value"] = float(s["value"]) + 1
        p2, _ = compare(d2, html)
        ok = len(p2) == 1 and p2[0].startswith("settings.order_cushion:")
        detail = "; ".join(p2) or "no difference found"
    except Exception as e:
        ok, detail = False, f"{type(e).__name__}: {e}"
    check(ok, "rule numbers: with one setting changed (order_cushion + 1), the check fails and names it", detail)
    try:
        compared = set(planner_numbers(html, None)[0]) | set(meta_numbers(None))
        rest = sorted({k[1] for k in table_numbers(d) if k[0] == "settings" and k not in compared})
        print(f"      (in settings but not in the old planner's code, so nothing to compare: {', '.join(rest) or 'none'})")
    except Exception:
        pass
    print(f"\n{len(failures)} rule-number check(s) failed" if failures else "\nrule numbers: all passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
