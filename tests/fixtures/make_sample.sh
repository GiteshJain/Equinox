#!/usr/bin/env bash
# Makes the frozen test sample (decision #9) from a nightly backup: what the planner and the website would read at one
# moment in time, saved as tests/fixtures/sample_<date>.json.gz. Small and dated; never keys or sign-in data (the backup
# leaves those out, and the secrets check runs over the result).
#
# Usage: tests/fixtures/make_sample.sh <equinox-backups checkout> <moment, UTC, e.g. 2026-10-08T21:00:00Z>
# Needs Docker, the Supabase CLI and psql 17 (or 16). Run from the repository root.
set -euo pipefail
backup=$(cd "$1" && pwd); at=$2
LOCAL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
here=$(pwd); work=$(mktemp -d)
out="tests/fixtures/sample_${at:0:10}.json.gz"

cd "$work"; supabase init < /dev/null > /dev/null
sed -i 's/^major_version = .*/major_version = 17/' supabase/config.toml
supabase db start > "$work/start.log" 2>&1 || { tail -n 20 "$work/start.log"; exit 1; }
cd "$here"
grep -v 'cli_login_postgres' "$backup/db/roles.sql" > "$work/roles.sql" || true
psql "$LOCAL" -X -q -b -f "$work/roles.sql" > /dev/null 2>&1 || true
psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 \
  -f "$backup/db/schema.sql" -c 'SET session_replication_role = replica' -f "$backup/db/data.sql" > /dev/null

# the same reads the planner makes (web/planner/index.html, capture board) with "today" = the chosen moment
psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -v at="$at" <<'SQL' | gzip -9 > "$out"
with t as (select :'at'::timestamptz as at, (:'at'::timestamptz at time zone 'utc')::date as d),
bal as (select airline, captured_on, amount, captured_at from game_balance, t
        where account like '2800%' and captured_on >= t.d - 7 order by captured_at desc)
select json_build_object(
  'frozen_at', (select at from t),
  'made_from', 'nightly backup, read as of ' || (select at from t),
  'planner_state', (select json::json from planner_state where id = 'main'),
  'planner_loads', (select coalesce(json_agg(json_build_object('month', month, 'json', json, 'saved_at', saved_at)), '[]') from planner_loads),
  'planner_data', (select value from planner_data where key = 'DATA'),
  'site_public', (select public.site_public()),
  'tables', json_build_object(
    'game_capture_raw', (select coalesce(json_agg(r order by r.captured_at desc), '[]') from (select airline, kind, captured_at from game_capture_raw, t where captured_at >= (t.d - 2)::timestamptz) r),
    'game_loads', (select coalesce(json_agg(r), '[]') from (select airline,flight_date,code,tail,origin,dest,dep_time,arr_time,eco,bus,fst,cargo,eco_pax,eco_seats,bus_pax,bus_seats,fst_pax,fst_seats,eco_fare,bus_fare from game_loads, t where flight_date >= t.d - 9) r),
    'game_flight_pnl', (select coalesce(json_agg(r), '[]') from (select airline,ts,blk,route,routes_n,pax,tail,pax_income,cargo_income,fuel,onboard,handling,landing,atc,maintenance,profit from game_flight_pnl, t where ts >= (t.d - 8)::timestamptz) r),
    'game_balance', (select coalesce(json_agg(bal), '[]') from bal),
    'game_events', (select coalesce(json_agg(r), '[]') from (select airline,event_date,event_time,debit,descr from game_events, t
        where event_date >= coalesce((select min(captured_on) from bal), t.d - 7) and event_date <= t.d + 16) r),
    'game_ops_recent', (select coalesce(json_agg(r), '[]') from (select airline,flights,income,costs,hours,last_ts from game_ops_recent) r),
    'backup_runs', (select coalesce(json_agg(r order by r.ran_at desc), '[]') from (select ran_at,kind,ok,tables,rows,files,bytes,note from backup_runs order by ran_at desc limit 10) r)
  ));
SQL
supabase stop --no-backup --workdir "$work" > /dev/null 2>&1 || true
echo "wrote $out ($(du -h "$out" | cut -f1))"
