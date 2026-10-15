"""The airline briefing and the map's guide on the rehearsal's copy (decision #24; spec
docs/specs/2026-10-15-airline-briefing.md). Run by database/rehearse.sh, not by run_all.sh: it needs the copy (a full
local Supabase restored from last night's backup, after the pull request's migrations) and the planning library built.

1. The briefing for every one of our airlines, as Claude runs it, through the copy's data API with the local keys: a home
   folder holding the copy's public key (~/.sb_anon) and a throwaway ingest secret (~/.ingest_secret, put in the copy's
   ingest_secret for this run and taken out after), $EQUINOX_API_URL the copy's address. Each run must succeed, print a
   short briefing (every heading, at most 60 lines) and write its JSON with every section filled from the copy: the
   card, cash and capture; the fleet holds every aircraft in service; every route is the airline's; the hubs; the
   deliveries, open to-dos and fare changes as many as the tables hold, every plan card with legs checked; the rivals
   from the latest finished scan.
2. The map's guide (docs/architecture.md, "Which call answers which question"): every call it names exists (a database
   function in public, a library command, the briefing), and every example answers on the copy exactly as written:
   SQL as postgres, the library's commands on rules.json made from the copy (and card.json, a plan card from the copy),
   the briefing with the local keys.

Only names, codes, ids, counts and timings are printed, never rows or keys. Exit code 1 if anything fails.
"""
import json, os, pathlib, re, shlex, subprocess, sys, tempfile, time
from urllib.parse import urlsplit

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from local_copy import local_env, psql  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
BRIEF = ROOT / "scripts" / "briefing" / "brief.py"
CLI = ROOT / "lib" / "rules" / "dist" / "cli.js"
MAP = ROOT / "docs" / "architecture.md"
HEADINGS = ("Money", "Fleet (", "Routes (", "Hubs", "Deliveries (", "To-dos (", "Fare plan:", "Rivals")
SECTIONS = ("airline", "card", "fleet", "routes", "hubs", "deliveries", "todos", "fare_plan", "rivals", "capture")
failures = []


def one(sql):
    """One value from the copy as JSON (a count, a list, a document; None when the query gives none)."""
    return json.loads(psql(f"select coalesce(to_json(({sql})), 'null'::json)").strip() or "null")


def check(ok, name, detail="", quiet=False):
    """Prints the check (a quiet one only when it fails) and keeps its failure."""
    if not ok or not quiet:
        print(("ok    " if ok else "FAIL  ") + name + ("" if ok or not detail else "\n      " + str(detail)[:600]), flush=True)
    if not ok:
        failures.append(name)
    return ok


def run_env(home, api):
    env = {k: v for k, v in os.environ.items() if k.lower() not in ("http_proxy", "https_proxy", "all_proxy")}
    env.update(HOME=str(home), EQUINOX_API_URL=api, NO_PROXY="127.0.0.1,localhost", no_proxy="127.0.0.1,localhost",
               EQUINOX_RULES_CLI=str(CLI))
    return env


def brief(code, home, api, out):
    t0 = time.monotonic()
    r = subprocess.run([sys.executable, str(BRIEF), code, "--out", str(out)], env=run_env(home, api), cwd=out,
                       capture_output=True, text=True, timeout=600)
    return r, time.monotonic() - t0


def briefings(home, api, work):
    w = "private.fig_world(null)"
    airlines = one(f"select json_agg(json_build_object('id', al.airline_id, 'code', al.iata_code) order by al.ord) from private.fig_airlines({w}) al") or []
    check(bool(airlines), "the copy has our airlines", "private.fig_airlines() gave none")
    latest_scan = one("select max(id) from public.game_scans where status = 'done'")
    for a in airlines:
        aid, code = a["id"], a["code"]
        before = len(failures)
        out = work / f"brief_{code}"
        out.mkdir()
        r, secs = brief(code, home, api, out)
        if not check(r.returncode == 0, f"{code}: the briefing runs ({secs:.1f} s)", (r.stderr or r.stdout).strip()[-600:], quiet=True):
            continue
        lines = r.stdout.strip().splitlines()
        missing = [h for h in HEADINGS if not any(l.startswith(h) for l in lines)]
        check(not missing and len(lines) <= 60, f"{code}: it prints a short briefing ({len(lines)} lines, every heading)", f"missing {missing}", quiet=True)
        files = list(out.glob("briefing_*.json"))
        if not check(len(files) == 1, f"{code}: it writes its JSON beside it", [f.name for f in files], quiet=True):
            continue
        b = json.loads(files[0].read_text())
        if not check(all(k in b for k in SECTIONS) and b["airline"]["id"] == aid, f"{code}: every section, for this airline",
                     [k for k in SECTIONS if k not in b], quiet=True):
            continue
        # the card, cash and capture
        check((b["card"].get("card") or {}).get("airline_id") == aid and b["card"].get("cash") is not None,
              f"{code}: card and cash forecast (airline_cards(), cash_forecast())", quiet=True)
        captured = one(f"select count(*) from public.game_capture_raw r where r.airline_id = {aid}")
        check(b.get("capture") is not None and (not captured or b["capture"].get("last_at")),
              f"{code}: the capture's state ({captured} raw pages kept)", b.get("capture"), quiet=True)
        # the fleet: every aircraft in service, from the library
        active = set(one(f"select coalesce(json_agg(a.registration), '[]') from public.aircraft a where a.airline_id = {aid} and a.status = 'active'"))
        regs = {x["registration"] for x in b["fleet"]}
        check(active <= regs, f"{code}: the fleet holds its {len(active)} aircraft in service ({len(regs)} in the briefing)",
              sorted(active - regs)[:5], quiet=True)
        # the routes: every one the airline's, and some when it flies
        theirs = set(one(f"select coalesce(json_agg(r.id), '[]') from public.routes r where r.airline_id = {aid}"))
        ids = [x["route_id"] for x in b["routes"]["routes"]]
        legs = one(f"select count(*) from public.flight_legs l where l.airline_id = {aid}")
        check(set(ids) <= theirs and (bool(ids) or not legs), f"{code}: {len(ids)} routes, every one the airline's",
              f"not the airline's: {sorted(set(ids) - theirs)[:8]}", quiet=True)
        check(b.get("hubs") is not None and b["hubs"].get("airline_id") == aid, f"{code}: hubs first (hub_progress())", quiet=True)
        # deliveries, to-dos and the fare plan, as many as the tables hold
        n_del = one(f"select count(*) from public.aircraft a where a.airline_id = {aid} and a.status in ('on_order', 'delivered')")
        cards = [c for d in b["deliveries"] for c in d["plan_cards"]]
        check(len(b["deliveries"]) == n_del and all(c.get("check") is not None for c in cards if c.get("legs")),
              f"{code}: {n_del} deliveries, each plan card with legs checked", len(b["deliveries"]), quiet=True)
        n_todo = one(f"select count(*) from public.todos t where t.world_id = {w} and not t.done and (t.airline_id = {aid} or t.airline_id is null)")
        check(len(b["todos"]) == n_todo, f"{code}: {n_todo} open to-dos (the airline's and the group's)", len(b["todos"]), quiet=True)
        n_fare = one(f"select count(*) from public.fare_plan f where f.airline_id = {aid} and f.status <> 'dropped'")
        check(len((b["fare_plan"] or {}).get("plan") or []) == n_fare and (b["fare_plan"] or {}).get("airline_id") == aid,
              f"{code}: {n_fare} fare changes planned (fare_plan_status())", quiet=True)
        rv = b["rivals"]
        shared = sum(1 for x in rv.get("routes") or [] if x["rivals_weekly"])
        check(rv.get("scan_id") == latest_scan, f"{code}: rivals from the latest finished scan ({latest_scan})", rv.get("scan_id"), quiet=True)
        if len(failures) == before:
            print(f"ok    {code}: briefing in {secs:.1f} s, {len(lines)} lines; fleet {len(regs)}, routes {len(ids)}, deliveries {n_del} "
                  f"({len(cards)} plan cards, {sum(1 for c in cards if (c.get('check') or {}).get('ok'))} checked ok), to-dos {n_todo}, "
                  f"fare changes {n_fare}, scan {rv.get('scan_id')} ({shared} of {len(rv.get('routes') or [])} routes shared), "
                  f"capture {(b.get('capture') or {}).get('verdict') or 'not checked'}", flush=True)


def guide_rows():
    text = MAP.read_text()
    m = re.search(r"(?ms)^## Which call answers which question\n(.*?)(?=^## )", text)
    if not check(m is not None, "the map has its guide (docs/architecture.md, Which call answers which question)", quiet=True):
        return []
    rows = []
    for line in m.group(1).splitlines():
        if not line.startswith("| ") or line.startswith("| Question") or line.startswith("|---"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
        if len(cells) != 3:
            check(False, "a guide row has three cells", line[:120])
            continue
        ex = re.fullmatch(r"`(.+)`", cells[2])
        rows.append({"question": cells[0], "call": cells[1], "example": ex.group(1) if ex else None})
    return rows


def card_file(path):
    """A plan card from the copy for check-card: the newest card with legs, else an aircraft in service's legs."""
    c = one("""select json_build_object('aircraft', c.aircraft_id, 'legs', (select json_agg(json_build_object(
                 'flight_no', l.flight_no, 'origin_code', l.origin_code, 'dest_code', l.dest_code, 'days_utc', l.days_utc,
                 'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min, 'service_code', l.service_code) order by l.position)
                 from public.plan_card_legs l where l.plan_card_id = c.id))
               from public.plan_cards c where exists (select 1 from public.plan_card_legs l where l.plan_card_id = c.id)
              order by c.id desc limit 1""")
    if not c:
        c = one("""select json_build_object('aircraft', a.registration, 'legs', json_agg(json_build_object(
                     'flight_no', l.flight_no, 'origin_code', l.origin_code, 'dest_code', l.dest_code, 'days_utc', l.days_utc,
                     'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min) order by l.rotation_id, l.leg_no))
                   from public.aircraft a join public.flight_legs l on l.aircraft_id = a.id
                  where a.status = 'active' group by a.id, a.registration order by a.id limit 1""")
    path.write_text(json.dumps(c))


def guide(home, api, work):
    before, start, answered = len(failures), time.monotonic(), 0
    rows = guide_rows()
    check(len(rows) >= 20, f"the guide lists {len(rows)} questions", quiet=True)
    folder = work / "guide"
    folder.mkdir()
    (folder / "rules.json").write_text(json.dumps(one("select public.rules_input()")))
    card_file(folder / "card.json")
    commands = set(re.findall(r"^  (\w[\w-]*) ", subprocess.run(["node", str(CLI)], capture_output=True, text=True).stderr, re.M))
    for row in rows:
        q, call, ex = row["question"], row["call"], row["example"]
        if not check(ex is not None, f"guide: '{q[:60]}' has an example", quiet=True):
            continue
        # the call it names exists
        for fn in re.findall(r"`(\w+)\(\)`", call):
            check(one(f"select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = '{fn}'") > 0,
                  f"guide: {fn}() exists in the database", quiet=True)
        lib = re.match(r"library `([\w-]+)`", call)
        if lib:
            check(lib.group(1) in commands, f"guide: the library has the command {lib.group(1)}", sorted(commands), quiet=True)
        t0 = time.monotonic()
        if ex.lower().startswith("select "):
            try:
                got = psql(ex).strip()
                ok, why = bool(got) and got != "null", "no answer" if not got or got == "null" else ""
            except Exception as e:   # noqa: BLE001
                ok, why = False, str(e)
        elif ex.startswith("node lib/rules/dist/cli.js "):
            r = subprocess.run(["node", str(CLI), *shlex.split(ex)[2:]], cwd=folder, capture_output=True, text=True, timeout=600)
            ok, why = r.returncode == 0 and r.stdout.lstrip()[:1] in ("{", "["), (r.stderr or r.stdout).strip()[-300:]
        elif ex.startswith("python3 scripts/briefing/brief.py "):
            r = subprocess.run([sys.executable, str(BRIEF), *shlex.split(ex)[2:], "--out", str(folder)], cwd=folder,
                               env=run_env(home, api), capture_output=True, text=True, timeout=600)
            ok, why = r.returncode == 0, (r.stderr or r.stdout).strip()[-300:]
        else:
            ok, why = False, "an example the test can't run (SQL, the library's command or the briefing)"
        check(ok, f"guide: {call} answers ({time.monotonic() - t0:.1f} s): {ex[:90]}", why, quiet=True)
        answered += ok
    if len(failures) == before:
        print(f"ok    the guide: {len(rows)} questions, every call it names exists and all {answered} examples answer on the copy "
              f"({time.monotonic() - start:.1f} s)", flush=True)


def main():
    env = local_env()
    api = env["API_URL"]
    check(urlsplit(api).hostname in ("127.0.0.1", "localhost"), "the briefing talks to the local copy only")
    if not CLI.is_file():
        check(False, "the planning library is built (lib/rules/dist/cli.js)")
        sys.exit(1)
    secret = "briefing-copy-" + os.urandom(12).hex()
    psql("insert into public.ingest_secret (secret) values (:'s')", s=secret)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            work = pathlib.Path(tmp)
            home = work / "home"
            home.mkdir(mode=0o700)
            for name, value in ((".sb_anon", env["ANON_KEY"]), (".ingest_secret", secret)):
                (home / name).write_text(value)
                (home / name).chmod(0o600)
            print("== the airline briefing for every one of our airlines, on the copy with the local keys", flush=True)
            briefings(home, api, work)
            print("== the map's guide: every call named exists and every example answers on the copy", flush=True)
            guide(home, api, work)
    finally:
        psql("delete from public.ingest_secret where secret = :'s'", s=secret)
    print(f"{'all passed' if not failures else str(len(failures)) + ' failed'}", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
