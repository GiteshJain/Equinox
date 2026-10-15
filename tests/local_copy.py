"""Helpers for the checks that run on the rehearsal's copy (database/rehearse.sh): a full local Supabase restored from
last night's backup. Its address and keys come in a file only this user can read (LOCAL_SUPABASE_ENV, the output of
`supabase status -o env`); they are never printed. Used by tests/planner_next_test.py and tests/planner_saves_test.py.

- local_env(): the copy's data API address and its keys (refuses anything that isn't local);
- psql(): runs SQL on the copy as postgres and returns the output;
- set_check_days() and put_back_check_days(): the one-week checks' setting set by the test (7 on, 0 off), then put back;
- counts(): every table's row count (database/backup/counts.sql, the key tables left out);
- make_user(), token_for(), is_planner_user(): test users through the copy's sign-in;
- marks() and log_since(): where the change log and job_runs stand, and the change-log rows written since (table, op,
  key, the names of the fields an update changed, actor and detail), never their values;
- moment(): the copy's latest capture plus one hour, to the millisecond: the frozen moment the screens open at.
"""
import asyncio, datetime, json, os, re, subprocess, time, urllib.error, urllib.request
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
COUNTS = ROOT / "database" / "backup" / "counts.sql"
DB = os.environ.get("LOCAL_DB_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
SKIP = os.environ.get("SECRET_TABLES", "public.ingest_secret,public.capture_keys,public.report_access")
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"


def why(e):
    return f"{type(e).__name__}: {(str(e).strip().splitlines() or [''])[0][:240]}"


def local_env():
    env = {}
    for line in Path(os.environ["LOCAL_SUPABASE_ENV"]).read_text().splitlines():
        m = re.match(r'^([A-Z_]+)="(.*)"$', line)
        if m:
            env[m[1]] = m[2]
    if urlsplit(env.get("API_URL", "")).hostname not in ("127.0.0.1", "localhost"):
        raise RuntimeError("the copy's data API address is missing or isn't local")
    if not env.get("ANON_KEY") or not env.get("SERVICE_ROLE_KEY"):
        raise RuntimeError("the copy's keys are missing")
    env["API_URL"] = env["API_URL"].rstrip("/")
    return env


def psql(sql, **var):
    args = ["psql", DB, "-X", "-At", "-q", "-v", "ON_ERROR_STOP=1"] + [a for k, v in var.items() for a in ("-v", f"{k}={v}")]
    r = subprocess.run(args, input=sql, capture_output=True, text=True, timeout=120)
    if r.returncode:
        raise RuntimeError("psql: " + (r.stderr.strip().splitlines() or ["failed"])[0][:200])
    return r.stdout


def one(sql, **var):
    """One JSON value from the copy (null when the query gives none)."""
    return json.loads(psql(f"select coalesce(({sql})::json, 'null'::json)", **var).strip() or "null")


def set_check_days(days):
    """Sets the one-week checks' setting on the copy (aircraft_check_after_days, the world's and any airline's own) to
    days, outside the change log (postgres only), so a test of the checks doesn't hang on the value last night's backup
    holds: 7 on, 0 off (spec docs/specs/2026-10-15-aircraft-checks-off.md). Gives the rows as they were, for
    put_back_check_days()."""
    was = one("select json_agg(json_build_object('id', s.id, 'value', s.value)) from public.settings s where s.key = 'aircraft_check_after_days'")
    psql("set equinox.change_log = 'off';\nupdate public.settings set value = to_jsonb(:'days'::int) where key = 'aircraft_check_after_days';", days=int(days))
    return was or []


def put_back_check_days(was):
    """The setting's rows as set_check_days() found them, outside the change log."""
    if was:
        psql("set equinox.change_log = 'off';\nupdate public.settings s set value = x.value from json_to_recordset(:'was'::json) as x(id bigint, value jsonb)"
             " where s.id = x.id;", was=json.dumps(was))


def counts():
    r = subprocess.run(["psql", DB, "-X", "-At", "-v", "ON_ERROR_STOP=1", "-v", f"skip={SKIP}", "-f", str(COUNTS)],
                       capture_output=True, text=True, timeout=120)
    if r.returncode:
        raise RuntimeError("counting rows failed")
    return dict(line.rsplit(" ", 1) for line in r.stdout.splitlines() if line.strip())


def count_changes(before, after, allow=()):
    return [f"row count changed: {t}: {before.get(t, 'none')} -> {after.get(t, 'none')}"
            for t in sorted(set(before) | set(after)) if before.get(t) != after.get(t) and t not in allow]


_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # straight to the copy, never through a proxy


def http(env, method, path, body=None, token=None, key=None, prefer=None):
    key = key or env["ANON_KEY"]
    h = {"apikey": key, "authorization": "Bearer " + (token or key), "content-type": "application/json"}
    if prefer:
        h["prefer"] = prefer
    req = urllib.request.Request(env["API_URL"] + path, method=method, headers=h,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        with _opener.open(req, timeout=30) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def make_user(env, email, password):
    code, _ = http(env, "POST", "/auth/v1/admin/users", {"email": email, "password": password, "email_confirm": True},
                   key=env["SERVICE_ROLE_KEY"])
    if code != 200:
        raise RuntimeError(f"the sign-in admin API answered {code} when making a test user")


def token_for(env, email, password):
    code, body = http(env, "POST", "/auth/v1/token?grant_type=password", {"email": email, "password": password})
    if code != 200:
        raise RuntimeError(f"signing in a test user answered {code}")
    return json.loads(body)["access_token"]


def is_planner_user(env, token):
    code, body = http(env, "POST", "/rest/v1/rpc/is_planner_user", {}, token=token)
    return code == 200 and json.loads(body) is True


def staff_user(env, email, password):
    """A test staff user: made through the copy's sign-in and put on planner_users. Returns the problems."""
    make_user(env, email, password)
    psql("insert into public.planner_users (email) values (:'email')", email=email)
    return [] if is_planner_user(env, token_for(env, email, password)) else ["public.is_planner_user() isn't true for the staff user"]


def marks():
    """Where the change log and job_runs stand, so a save's own rows can be told apart."""
    return json.loads(psql("select json_build_object('log', coalesce((select max(id) from public.change_log), 0), "
                           "'job', coalesce((select max(id) from public.job_runs), 0))").strip())


def log_since(mark):
    """The change-log rows since the mark: table, op, id, the names of the fields an update changed, actor and detail."""
    return json.loads(psql(f"""select coalesce(json_agg(json_build_object('table', l.table_name, 'op', l.op, 'id', l.row_key ->> 'id',
                                  'fields', (select coalesce(json_agg(k order by k), '[]') from jsonb_object_keys(
                                               case when l.op = 'update' then l.new_values else '{{}}'::jsonb end) k),
                                  'actor', l.actor, 'detail', l.actor_detail) order by l.id), '[]')
                                 from public.change_log l where l.id > {int(mark['log'])}""").strip())


def jobs_since(mark):
    return json.loads(psql(f"""select coalesce(json_agg(json_build_object('job', job, 'status', status, 'note', note) order by id), '[]')
                                 from public.job_runs where id > {int(mark['job'])}""").strip())


async def wait_for(read, moved, seconds=20):
    """Reads until moved(what it read), or gives up; returns the last read."""
    end = time.monotonic() + seconds
    while True:
        got = read()
        if moved(got) or time.monotonic() > end:
            return got
        await asyncio.sleep(0.25)


def moment():
    """The copy's latest capture plus one hour, to the millisecond (UTC, ISO): the moment the screens open at."""
    return psql("select to_char((max(captured_at) + interval '1 hour') at time zone 'UTC', "
                "'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') from public.game_capture_raw").strip()


def ms(iso):
    """An ISO moment in milliseconds since 1970."""
    return int(datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() * 1000)
