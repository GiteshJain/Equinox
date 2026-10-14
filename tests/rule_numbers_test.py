"""The rule numbers, one source (design §11, choice 3; §3.7). The settings and world_rules tables are the source; the old
planner keeps its own copies in its code until #18. This check fails if the two ever differ, so a rule changed in the
tables can't silently leave the planner on the old number (or the other way round).

The planner's numbers, read from web/planner/index.html as the planner uses them:
  - CUSHION (0.5M kept in hand after an order) and LEASE_PCT (a never-leased type's weekly lease);
  - the hubs-first target (the Hubs screen's progress bars) and who is exempt (MAIN_HUB has no Ryanair);
  - the growth signals (routeProfit) and load patterns (patterns) thresholds;
  - the old Check's (#18 build pull request 9): the refit's cost (REFIT_M) and the share that pays, a big market's stars,
    ready for another flight from the load reports, and the order queues' grace and warning;
  - the old Review's (#18 build pull request 10): the economy fare rise "+ fare plan" plans;
  - the old Check's suggested aircraft sizes (suggestSize, bigSize, feedSize; #18 build pull request 12), as the setting
    suggested_size holds them, the world's and Ryanair's own; and the old Interline screen's lists (IL_YES, EUROPE_ZONE,
    IL_RIVAL, IL_COVER, IL_PARTNERS, Ryanair's group only), as the setting interline_rules holds them;
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
    # the old Tails' block-hours target among an aircraft's issues (tailIssues), a setting since #18 build pull request 7
    out[("settings", "aircraft_block_target_h", None)] = find(r"if \(tl\.blockDay < (\d+)\) out\.push", "Tails' block-hours target (tailIssues)")

    # the old Check's numbers, settings since #18 build pull request 9: the refit's cost and the share that pays (cabinsBoard),
    # a big market's stars and a feeder's (moveCandidates), ready for another flight from the load reports (moveCandidates
    # and growthBoard, the same in both), and the order queues' grace and warning (growthBoard)
    out[("settings", "cabin_refit_cost", None)] = round(find(r"const REFIT_M = ([\d.]+);", "REFIT_M") * 1_000_000)
    out[("settings", "cabin_refit_share_pct", None)] = find(r"const strong = L\.filter\(x => x\.share >= (\d+)\);", "Cabins' refits that pay (cabinsBoard)")
    out[("settings", "growth_big_min_stars", None)] = find(r"const big = open\.filter\(r => r\.stars >= (\d+)\)", "a big market's stars (moveCandidates)")
    feeder = find(r"const feeder = open\.filter\(r => r\.stars <= (\d+) ", "a feeder's stars (moveCandidates)")
    ready = re.findall(r"x\.a && x\.a\.days\.size >= (\d+) && x\.a\.full / x\.a\.n >= ([\d.]+)\)", html)
    if len(ready) != 2:
        raise RuntimeError(f"not found in the planner's code: ready for another flight from the load reports, twice (found {len(ready)})")
    out[("settings", "growth_ready_min_days", None)], out[("settings", "growth_ready_full_share", None)] = float(ready[0][0]), float(ready[0][1])
    out[("settings", "order_queue_grace_h", None)] = find(r"Date\.parse\(d\.utc\) > now - (\d+) \* 3600e3", "the order queues' grace (growthBoard)")
    out[("settings", "order_queue_warn_h", None)] = find(r"UTC \$\{hrs < (\d+) \?", "the order queues' warning (growthBoard)")
    # the old Review's, a setting since #18 build pull request 10: the economy fare rise "+ fare plan" plans
    out[("settings", "fare_plan_raise_pct", None)] = find(r'cls: "economy", pct: (\d+), from: Math\.round\(from\)', "the fare plan's rise (+ fare plan)")
    # the old Check's suggested sizes (suggestSize, bigSize, feedSize), a setting with Ryanair's own since #18 build pull
    # request 12 (suggested_size): each move's list, first match wins, as the setting holds it
    m = re.search(r'function suggestSize\(r\) \{ if \(r\.airline === "Ryanair"\) return r\.stars >= (\d+) \? "(\w+)" : "(\w+)"; '
                  r'return r\.stars >= (\d+) \? "(\w+)" : r\.stars >= (\d+) \? "(\w+)" : "(\w+)"; \}', html)
    if not m:
        raise RuntimeError("not found in the planner's code: suggestSize")
    fr4, t4, e4, s5, t5, s3, t3, e3 = m.groups()
    m = re.search(r'const bigSize = r => al === "Ryanair" \? "(\w+)" : r\.stars >= (\d+) \? "(\w+)" : "(\w+)", '
                  r'feedSize = r => al === "Ryanair" \? "(\w+)" : r\.stars >= (\d+) && r\.dist > (\d+) \? "(\w+)" : "(\w+)";', html)
    if not m:
        raise RuntimeError("not found in the planner's code: bigSize and feedSize (moveCandidates)")
    big_fr, big_s, big_t, big_e, feed_fr, feed_s, feed_km, feed_t, feed_e = m.groups()
    out[("settings", "suggested_size", None)] = {
        "big": [{"min_stars": int(big_s), "type": big_t}, {"type": big_e}],
        "freq": [{"min_stars": int(s5), "type": t5}, {"min_stars": int(s3), "type": t3}, {"type": e3}],
        "feeder": [{"min_stars": int(feed_s), "over_km": int(feed_km), "type": feed_t}, {"type": feed_e}]}
    out[("settings", "suggested_size", "Ryanair")] = {
        "big": [{"type": big_fr}], "freq": [{"min_stars": int(fr4), "type": t4}, {"type": e4}], "feeder": [{"type": feed_fr}]}
    out[("settings", "interline_rules", None)] = interline_rules(html)

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
    places = {"hub_first_departures (label)": bar, "patterns: watch needs": n2, "Home's airport cap": home_cap, "a feeder's stars": feeder,
              "ready, twice": ready}
    return out, places


def interline_rules(html):
    """The old Interline screen's lists (IL_YES, EUROPE_ZONE, IL_RIVAL, IL_COVER, IL_PARTNERS, and Ryanair's group only), as
    the setting interline_rules holds them (airlines by their code, CODE_AL; lists as sets, compared sorted)."""
    def grab(pattern, what):
        m = re.search(pattern, html, re.S)
        if not m:
            raise RuntimeError(f"not found in the planner's code: {what}")
        return m[1]
    codes = {v: k for k, v in re.findall(r'(\w\w): "([^"]+)"', grab(r"const CODE_AL = \{([^}]*)\}", "CODE_AL"))}
    yes = dict(re.findall(r"(\w\w): \"(\w+)\"", grab(r"const IL_YES = \{([^}]*)\}", "IL_YES")))
    cover = {}
    for al, s in re.findall(r'put\("([^"]+)", "([A-Z ]+)"\)', grab(r"const IL_COVER = \(\(\) => \{(.*?)return m; \}\)\(\);", "IL_COVER")):
        cover[codes[al]] = sorted(s.split())
    partners = {cc: [{"name": n, "game_id": int(i)} for n, i in re.findall(r'\["([^"]+)", (\d+)\]', lst)]
                for cc, lst in re.findall(r"(\w\w): (\[\[.*?\]\])", grab(r"const IL_PARTNERS = \{(.*?)\};\n", "IL_PARTNERS"))}
    group = grab(r'if \(airline === "([^"]+)"\) return \{ kind: "group"', "the group-only airline (ilClass)")
    return {"countries": yes, "europe_zone": sorted(grab(r'const EUROPE_ZONE = new Set\("([^"]+)"', "EUROPE_ZONE").split()),
            "rivals": sorted(grab(r'const IL_RIVAL = new Set\("([^"]+)"', "IL_RIVAL").split()),
            "covered": cover, "group_only": [codes[group]], "partners": partners}


def sorted_rules(v):
    """interline_rules with its lists sorted, as interline_rules() reads the old code."""
    if not isinstance(v, dict):
        return v
    out = dict(v)
    for k in ("europe_zone", "rivals"):
        out[k] = sorted(out.get(k) or [])
    out["covered"] = {a: sorted(c) for a, c in (out.get("covered") or {}).items()}
    return out


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
        out[("settings", s["key"], s.get("airline"))] = (v if isinstance(v, bool) else num(v) if isinstance(v, (int, float))
                                                       else sorted_rules(v) if s["key"] == "interline_rules" else v)
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
SINCE_SAMPLE = {"airport_cap_warning_pct": "13 Oct, #18 build pull request 5", "aircraft_check_after_days": "13 Oct, #18 build pull request 5",
                "aircraft_block_target_h": "13 Oct, #18 build pull request 7",
                **{k: "13 Oct, #18 build pull request 9" for k in ("cabin_refit_cost", "cabin_refit_share_pct", "growth_big_min_stars", "growth_ready_min_days",
                                                                 "growth_ready_full_share", "order_queue_grace_h", "order_queue_warn_h")},
                "fare_plan_raise_pct": "14 Oct, #18 build pull request 10", "suggested_size": "14 Oct, #18 build pull request 12",
                "interline_rules": "14 Oct, #18 build pull request 12"}
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
                after_sample.append(f"{label} ({SINCE_SAMPLE[k[1]]}; the planner's code has "
                                    f"{json.dumps(v, separators=(',', ':')) if isinstance(v, dict) else format(v, 'g')})")
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
        if places["a feeder's stars"] + 1 != code[("settings", "growth_big_min_stars", None)]:
            problems.append("the order rotation: a feeder's stars aren't the ones below a big market's")
        if len(set(places["ready, twice"])) != 1:
            problems.append(f"ready for another flight: moveCandidates and growthBoard use different numbers ({places['ready, twice']})")
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
