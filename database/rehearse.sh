#!/usr/bin/env bash
# Rehearses database changes on a copy of last night's backup before they reach the live database (decision #8).
#
# Usage: database/rehearse.sh <folder holding an unpacked backup: db/, and latest.json if present> [base branch]
# Run by .github/workflows/database-rehearsal.yml on every pull request that touches database/migrations/ or the
# planner. The workflow gets the folder from Cloudflare R2 with database/backup/download.sh (decision #16).
#
# 1. Restores the backup into an empty local Supabase (Docker): the database, the data API and sign-in, with nothing
#    else started (#17). The database is restored the same way the nightly restore check does.
# 2. Finds the changes still to apply: migration files whose version isn't in the restored migration record, which is
#    the live database's record as of last night. Before applying them, runs database/tests/before/*.sql, which save
#    chosen outputs into the schema rehearsal_before, so a test can compare them afterwards.
# 3. Applies them in order, each in its own transaction, stopping at the first failure, then pauses any job they schedule
#    on the copy (pg_cron), so none runs during the tests. With SAMPLE_DIR set, then makes a test sample from the copy
#    (tests/fixtures/sample.sql, at the backup's moment) into that folder. With REPORT_SAMPLE_DIR set, also the weekly
#    report's sample (tests/fixtures/report_sample.sql, cut by tests/fixtures/report_sample.py, at the same moment). With
#    CAPTURE_SAMPLE_DIR set, also the capture's saved pages (tests/fixtures/capture_sample.sql: one airline's five pages
#    of one evening, what to expect of them and the rows they give; #21). With BRIEFING_SAMPLE_DIR set, also the airline
#    briefing's sample (tests/fixtures/briefing_sample.sql, cut by tests/fixtures/briefing_sample.py, at the backup's
#    moment; #24).
# 4. Prints the row count of every table that changed, plus any table added or removed.
# 5. Runs every test in database/tests/ on the copy, each in a transaction that is rolled back, and prints what each
#    passing test says it checked (its notices: counts, never rows).
# 6. Checks the descriptions (decision #10): every table, view and function has one, and docs/data.md matches the
#    database. With WRITE_DOCS=1 it rewrites docs/data.md instead (run that locally after changing a description); with
#    DOCS_DIR set, the guide as the copy gives it goes there either way (the run's data-guide artifact).
# 7. The planner (#18, design §10), only if 1 to 5 passed: its types are generated again from the copy (after every
#    pending change) with the local Supabase CLI and must equal app/planner/src/db/types.ts; the generated file is kept
#    in TYPES_DIR (the run's planner-types artifact) and any difference is printed. Then the planner is built (npm ci,
#    npm run build), and tests/planner_next_test.py opens it at its live address on the copy (/planner/), signs in, reads
#    and saves through planner_save(), opens every screen at a frozen moment at 1280 and 380 px (screenshots in
#    PLANNER_SCREENS_DIR, the run's planner-screens artifact) and checks the addresses web/_redirects gives.
#    Then the airline briefing (#24), read only: tests/briefing_copy_test.py runs scripts/briefing/brief.py for every one
#    of our airlines through the copy's data API with its local keys and a throwaway ingest secret, checks each section
#    against the copy's tables, and runs every example in the map's guide (docs/architecture.md, "Which call answers
#    which question") on the copy.
# 8. Every kind of save, only if 1 to 5 passed, last of the planner's steps because its saves change the copy:
#    tests/planner_saves_test.py saves through each screen's own controls and checks each against the rows recorded in
#    tests/fixtures/planner_saves.expected.json (the answers found go to SAVES_OUT_DIR, the run's planner-saves
#    artifact). Stopped after 10 minutes if it stops answering. Together, 7 and 8 replaced the side by sides with the
#    old planner (the clean-up, build pull request 14; tests/README.md).
# 9. The backup and its restore after the changes, only when there were changes to apply and 1 to 5 passed: the copy, as
#    the changes left it, is dumped the way the nightly backup dumps live (equinox-backups' scripts/backup.sh), the copy
#    is stopped, and the dump is restored into an empty database the way the nightly restore check does; every table
#    must come back with its rows, and who may use what (database/backup/permissions.sql) must match line for line.
# Only table names, counts, descriptions, ids and error messages are printed, never rows or keys. The copy, its keys and
# its test users exist only on the runner while this runs.
set -euo pipefail
export LC_ALL=C   # sort, join and comm agree on order
backup=$(cd "$1" && pwd)
base=${2:-main}
LOCAL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
here=$(pwd)
work=$(mktemp -d)
fresh=$(mktemp -d)   # the empty database the backup is restored into at step 9
source database/backup/config.sh   # SECRET_TABLES: never in the backup, so never counted

# which night the copy is from: latest.json, saved beside the copy when it was downloaded from R2
made="unknown date"; ran_at=""
if [ -f "$backup/latest.json" ]; then
  ran_at=$(jq -r '.ran_at // empty' "$backup/latest.json" 2> /dev/null || true)
  key=$(jq -r '.key // empty' "$backup/latest.json" 2> /dev/null || true)
  if [ -n "$ran_at" ]; then made=$(date -u -d "$ran_at" +'%d %b %H:%M UTC' 2> /dev/null || echo "$ran_at"); fi
  if [ -n "$key" ]; then made="$made, $key"; fi
fi
for d in "$work" "$fresh"; do
  cd "$d"
  supabase init < /dev/null > /dev/null
  sed -i 's/^major_version = .*/major_version = 17/' supabase/config.toml   # same Postgres version as the live database
done
cd "$here"
# Only what the planner calls: the database, sign-in (gotrue), the data API (postgrest) and the gateway in front of them
# (kong). Everything else the CLI can start is left out; the list is read from the CLI so a new service stays out too.
services=$(supabase start --help 2> /dev/null | sed -n 's/.*--exclude.*\[\([a-z0-9,_-]*\)\].*/\1/p' | head -n 1)
[ -n "$services" ] || services="gotrue,realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"
leave_out=$(tr ',' '\n' <<< "$services" | grep -vxF -e gotrue -e postgrest -e kong | paste -sd, -)
# the CLI prints the local keys when it starts: they stay in start.log, and are taken out if it is ever shown
hide_keys() { sed -E 's/eyJ[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*/[key]/g; s/sb_(secret|publishable)_[A-Za-z0-9_-]+/[key]/g; s/((key|secret)[^:=]*[:=][[:space:]"]*)[^[:space:]",]+/\1[key]/Ig'; }
# stop both databases however this ends
trap 'supabase stop --no-backup --workdir "$work" > /dev/null 2>&1 || true; supabase stop --no-backup --workdir "$fresh" > /dev/null 2>&1 || true' EXIT

# Run on an empty database before a restore: the empty local database gives new tables and functions to anon and
# authenticated by default, and the backup only lists what live grants on top of the usual defaults; without this the
# copy would be more open than live (equinox-backups' scripts/restore_defaults.sql).
restore_defaults() {
  psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 \
    -c "alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated, service_role" \
    -c "alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated, service_role" \
    -c "alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated, service_role" > /dev/null
}

# 1. a fresh local Supabase with last night's backup restored into it
restore_copy() {
  supabase stop --no-backup --workdir "$work" > /dev/null 2>&1 || true
  (cd "$work" && supabase start -x "$leave_out" > "$work/start.log" 2>&1) || { tail -n 20 "$work/start.log" | hide_keys; return 1; }
  grep -v 'cli_login_postgres' "$backup/db/roles.sql" > "$work/roles.sql" || true   # the CLI makes this role itself
  psql "$LOCAL" -X -q -b -f "$work/roles.sql" > /dev/null 2>&1 || true            # per-role settings need a superuser
  restore_defaults
  psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 \
    -f "$backup/db/schema.sql" -c 'SET session_replication_role = replica' -f "$backup/db/data.sql" > /dev/null
  psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 \
    -f "$backup/db/history_schema.sql" -f "$backup/db/history_data.sql" > /dev/null
}
count() { psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -v skip="$SECRET_TABLES" -f database/backup/counts.sql | sort; }

# the changes still to apply: every migration file whose version live doesn't have yet
pending_files() {
  psql "$LOCAL" -X -At -c "select version from supabase_migrations.schema_migrations" | sort > "$work/applied.txt"
  local f v
  for f in database/migrations/*.sql; do
    v=$(basename "$f" | cut -d_ -f1)
    grep -qx "$v" "$work/applied.txt" && continue
    echo "$f"
  done
}
apply_files() {
  local f start out
  for f in "$@"; do
    start=$(date +%s%N)
    if out=$(psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 -f "$f" 2>&1); then
      echo "ok    $(basename "$f")  ($(( ($(date +%s%N) - start) / 1000000 )) ms)"
      # what a change says about itself as it runs (its notices: counts, never rows)
      echo "$out" | sed -n 's/^.*NOTICE:  \(.*\)$/      \1/p' | head -n 4 || true
    else
      echo "FAIL  $(basename "$f")"
      echo "$out" | grep -E 'ERROR|DETAIL|HINT|CONTEXT|LINE' | sed 's/^/      /' | head -n 12
      return 1
    fi
  done
}

# The copy is a test, so jobs that the changes schedule on it (pg_cron, #13 pull request 7) are paused: none may run in
# the middle of the tests or the saves. A backup carries pg_cron but never its schedules, so only a copy that gets the
# jobs' migration here has any. Their state as the changes left them is kept in rehearsal_before.cron_jobs, where
# database/tests/jobs_test.sql reads it.
pause_jobs() {
  local n
  n=$(psql "$LOCAL" -X -At -c "select count(*) from cron.job" 2> /dev/null) || return 0
  [ "${n:-0}" -gt 0 ] || return 0
  psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 -c "create schema if not exists rehearsal_before" \
    -c "drop table if exists rehearsal_before.cron_jobs" \
    -c "create table rehearsal_before.cron_jobs as select jobname, schedule, command, username, database, active from cron.job" \
    -c "select cron.alter_job(jobid, active := false) from cron.job" > /dev/null || return 1
  echo "the copy's scheduled jobs are paused for the tests: $(psql "$LOCAL" -X -At -c "select string_agg(jobname || ' (' || schedule || ')', ', ' order by jobname) from rehearsal_before.cron_jobs")"
}

# The data API read the database's tables when it started, before the restore and the changes: reload them, then wait
# until it serves a restored table (any answer but "not found", "schema not loaded" or no answer at all). $1: the env
# file from `supabase status -o env`.
reload_api() {
  local api anon code tries=0
  api=$(sed -n 's/^API_URL="\(.*\)"$/\1/p' "$1"); anon=$(sed -n 's/^ANON_KEY="\(.*\)"$/\1/p' "$1")
  psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 -c "notify pgrst, 'reload schema'" > /dev/null
  while :; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $anon" "$api/rest/v1/worlds?select=id&limit=1" || true)
    case "$code" in 200|401|403) break ;; esac
    tries=$((tries + 1))
    if [ $tries -ge 60 ]; then echo "FAIL  the data API didn't answer within a minute of reloading (last answer: ${code:-none})"; return 1; fi
    sleep 1
  done
  echo "the data API reloaded and answers for the restored tables (after ${tries}s)"
}

# 7. The planner (#18): its types from the copy, then the planner built and opened on the copy. The local address and
# keys go to the test in a file only this user can read; they are never printed.
TYPES_FILE=app/planner/src/db/types.ts
new_planner() {
  local env="$work/local.env" gen="$work/types.ts" rc=0
  echo "== the planner's types, generated from the copy (design §5)"
  if ! supabase gen types typescript --local --schema public --workdir "$work" > "$gen" 2> "$work/gen.log"; then
    echo "FAIL  supabase gen types couldn't read the copy"
    tail -n 5 "$work/gen.log" | hide_keys | sed 's/^/      /'
    return 1
  fi
  if [ -n "${TYPES_DIR:-}" ]; then mkdir -p "$TYPES_DIR" && cp "$gen" "$TYPES_DIR/types.ts"; fi
  if cmp -s "$gen" "$TYPES_FILE"; then
    echo "ok    $TYPES_FILE matches the copy ($(wc -l < "$gen") lines)"
  else
    echo "FAIL  $TYPES_FILE doesn't match the types generated from the copy; commit the generated file (the run's planner-types artifact)"
    diff -u "$TYPES_FILE" "$gen" | sed -n '3,40p' | sed 's/^/      /'
    rc=1
  fi
  echo "== the planner, built and opened on the copy: every screen at a frozen moment, its saves and its addresses (#18)"
  if ! (npm ci --no-audit --no-fund > "$work/npm.log" 2>&1 && npm run build >> "$work/npm.log" 2>&1); then
    echo "FAIL  the planner didn't build"
    tail -n 15 "$work/npm.log" | sed 's/^/      /'
    return 1
  fi
  echo "built: web/app/ ($(find web/app -type f | wc -l) files)"
  (umask 077 && supabase status -o env --workdir "$work" > "$env" 2> /dev/null) \
    || { echo "FAIL  couldn't read the local copy's address and keys"; rm -f "$env"; return 1; }
  if reload_api "$env"; then
    LOCAL_SUPABASE_ENV="$env" LOCAL_DB_URL="$LOCAL" SECRET_TABLES="$SECRET_TABLES" PLANNER_SCREENS_DIR="${PLANNER_SCREENS_DIR:-}" \
      python3 tests/planner_next_test.py || rc=1
  else
    rc=1
  fi
  rm -f "$env"
  return $rc
}

# 7b. The airline briefing and the map's guide on the copy (#24), read only: needs the planning library built (step 7
# builds it). The local address and keys as for 7; never printed.
briefing_copy() {
  local env="$work/local.env" rc=0
  echo "== the airline briefing for every airline, and the map's guide, on the copy (#24)"
  if [ ! -f lib/rules/dist/cli.js ] && ! (npm ci --no-audit --no-fund > "$work/npm.log" 2>&1 && npm run build >> "$work/npm.log" 2>&1); then
    echo "FAIL  the planning library didn't build"
    tail -n 15 "$work/npm.log" | sed 's/^/      /'
    return 1
  fi
  (umask 077 && supabase status -o env --workdir "$work" > "$env" 2> /dev/null) \
    || { echo "FAIL  couldn't read the local copy's address and keys"; rm -f "$env"; return 1; }
  if reload_api "$env"; then
    LOCAL_SUPABASE_ENV="$env" LOCAL_DB_URL="$LOCAL" SECRET_TABLES="$SECRET_TABLES" python3 tests/briefing_copy_test.py || rc=1
  else
    rc=1
  fi
  rm -f "$env"
  return $rc
}

# 8. Every kind of save the planner makes, through its own controls, against the rows recorded for it
# (tests/planner_saves_test.py, build pull request 14). The answers found go to SAVES_OUT_DIR (the run's planner-saves
# artifact). Stopped after 10 minutes if it stops answering. The local address and keys as for 7; never printed.
planner_saves() {
  local env="$work/local.env" rc=0
  echo "== every kind of save in the planner, against the rows recorded for it (#18 build pull request 14)"
  (umask 077 && supabase status -o env --workdir "$work" > "$env" 2> /dev/null) \
    || { echo "FAIL  couldn't read the local copy's address and keys"; rm -f "$env"; return 1; }
  if reload_api "$env"; then
    LOCAL_SUPABASE_ENV="$env" LOCAL_DB_URL="$LOCAL" SECRET_TABLES="$SECRET_TABLES" SAVES_OUT_DIR="${SAVES_OUT_DIR:-}" RECORD_SAVES="${RECORD_SAVES:-}" \
      timeout -s INT 600 python3 tests/planner_saves_test.py || rc=$?
    if [ $rc -eq 124 ] || [ $rc -eq 130 ]; then echo "FAIL  the saves didn't finish within 10 minutes"; fi
    [ $rc -eq 0 ] || rc=1
  else
    rc=1
  fi
  rm -f "$env"
  return $rc
}

# 9. The backup and its restore check, after the changes (the clean-up, build pull request 14: the backups must still run
# and restore without what a change removes). The dump is made as equinox-backups' scripts/backup.sh makes it from live
# (roles, schema, data of public and storage without the secret tables, the migration record), then the copy is stopped
# and an empty database (only the database, as the restore check starts one) takes the dump as its scripts/restore_check.sh
# restores it. Every table must come back with the same rows, and who may use what must be the same, line for line.
backup_restore() {
  local dump="$work/dump" excl=() t secret
  echo "== the backup and its restore check, after the changes: the copy dumped as the nightly backup dumps live, and restored into an empty database"
  mkdir -p "$dump"
  IFS=',' read -ra secret <<< "$SECRET_TABLES"
  for t in "${secret[@]}" storage.buckets_vectors storage.vector_indexes; do excl+=(-x "$t"); done
  count > "$dump/counts.txt"
  psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -f database/backup/permissions.sql > "$dump/permissions.txt"
  if ! { supabase db dump --local --workdir "$work" -f "$dump/roles.sql" --role-only \
         && supabase db dump --local --workdir "$work" -f "$dump/schema.sql" \
         && supabase db dump --local --workdir "$work" -f "$dump/data.sql" --use-copy --data-only --schema public,storage "${excl[@]}" \
         && supabase db dump --local --workdir "$work" -f "$dump/history_schema.sql" --schema supabase_migrations \
         && supabase db dump --local --workdir "$work" -f "$dump/history_data.sql" --use-copy --data-only --schema supabase_migrations; } > "$work/dump.log" 2>&1; then
    echo "FAIL  the copy couldn't be dumped as the nightly backup dumps live"
    tail -n 8 "$work/dump.log" | hide_keys | sed 's/^/      /'
    return 1
  fi
  echo "dumped: $(du -sh "$dump" | cut -f1), $(wc -l < "$dump/counts.txt") tables, $(awk '{s+=$2} END {print s+0}' "$dump/counts.txt") rows"
  supabase stop --no-backup --workdir "$work" > /dev/null 2>&1 || true
  if ! (cd "$fresh" && supabase db start > "$fresh/start.log" 2>&1); then
    echo "FAIL  the empty database didn't start"
    tail -n 10 "$fresh/start.log" | hide_keys | sed 's/^/      /'
    return 1
  fi
  grep -v 'cli_login_postgres' "$dump/roles.sql" > "$fresh/roles.sql" || true
  psql "$LOCAL" -X -q -b -f "$fresh/roles.sql" > /dev/null 2>&1 || true
  restore_defaults
  if ! psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 \
         -f "$dump/schema.sql" -c 'SET session_replication_role = replica' -f "$dump/data.sql" > "$fresh/restore.log" 2>&1 \
     || ! psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 \
         -f "$dump/history_schema.sql" -f "$dump/history_data.sql" >> "$fresh/restore.log" 2>&1; then
    echo "FAIL  the dump didn't restore"
    grep -E 'ERROR|DETAIL' "$fresh/restore.log" | sed 's/^/      /' | head -n 8
    return 1
  fi
  count > "$fresh/counts.txt"
  psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -f database/backup/permissions.sql > "$fresh/permissions.txt"
  if ! diff -u --label "the copy" --label "restored" "$dump/counts.txt" "$fresh/counts.txt" > "$fresh/counts.diff"; then
    echo "FAIL  the restore didn't give back every table with its rows"
    sed -n '3,20p' "$fresh/counts.diff" | sed 's/^/      /'
    return 1
  fi
  if ! diff -u --label "the copy" --label "restored" "$dump/permissions.txt" "$fresh/permissions.txt" > "$fresh/permissions.diff"; then
    echo "FAIL  the restored copy's permissions differ from the copy's"
    sed -n '3,20p' "$fresh/permissions.diff" | sed 's/^/      /'
    return 1
  fi
  echo "ok    restore check: $(wc -l < "$fresh/counts.txt") tables and $(awk '{s+=$2} END {print s+0}' "$fresh/counts.txt") rows restored, $(wc -l < "$fresh/permissions.txt") permission lines the same"
}

status=0
echo "== restoring last night's backup ($made)"
restore_copy || exit 1
count > "$work/before.txt"
echo "restored: $(wc -l < "$work/before.txt") tables, $(awk '{s+=$2} END {print s+0}' "$work/before.txt") rows"

mapfile -t pending < <(pending_files)
# changes recorded on live that the repository doesn't have (made outside a pull request)
for f in database/migrations/*.sql; do basename "$f" | cut -d_ -f1; done | sort > "$work/in_repo.txt"
missing=$(comm -23 "$work/applied.txt" "$work/in_repo.txt" || true)
[ -n "$missing" ] && echo "warning: live has changes that aren't in the repository: $(echo $missing)"
# edits to a change that live already has do nothing there; the change needs a new migration instead
if git rev-parse --verify -q "origin/$base" > /dev/null; then
  edited=$(git diff --name-only --diff-filter=M "origin/$base"...HEAD -- database/migrations/ || true)
  [ -n "$edited" ] && echo "warning: these already-applied changes were edited, which won't change live: $(echo $edited)"
fi

# Outputs saved before the changes (database/tests/before/*.sql), so a test can compare them afterwards: for example, a
# view rebuilt on new tables must return the same rows as before. Each file runs in its own transaction and writes only
# into the schema rehearsal_before, which the data API, the row counts and the table guide don't look at.
saved=(database/tests/before/*.sql)
if [ -e "${saved[0]}" ]; then
  echo "== saving outputs before the changes (into rehearsal_before)"
  psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 -c 'drop schema if exists rehearsal_before cascade' \
    -c 'create schema rehearsal_before' > /dev/null
  for f in "${saved[@]}"; do
    if out=$(psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 -f "$f" 2>&1); then
      echo "ok    $(basename "$f")"
    else
      echo "FAIL  $(basename "$f")"
      echo "$out" | grep -E 'ERROR|DETAIL|CONTEXT' | sed 's/^/      /' | head -n 6
      status=1
    fi
  done
fi

if [ $status -ne 0 ]; then pending=(); echo "== the outputs couldn't be saved, so the changes weren't tried"
elif [ ${#pending[@]} -eq 0 ]; then echo "== no new database changes: nothing to rehearse"
else echo "== applying ${#pending[@]} new change(s) to the copy"; fi
if [ $status -eq 0 ] && [ ${#pending[@]} -gt 0 ]; then apply_files "${pending[@]}" && pause_jobs || status=1; fi

if [ $status -eq 0 ] && [ ${#pending[@]} -gt 0 ]; then
  count > "$work/after.txt"
  echo "== row counts that changed (table: before -> after)"
  join -a1 -a2 -e '-' -o '0,1.2,2.2' "$work/before.txt" "$work/after.txt" \
    | awk '$2 != $3 { printf "%s: %s -> %s\n", $1, ($2 == "-" ? "new table" : $2), ($3 == "-" ? "removed" : $3); n++ }
           END { if (!n) print "none: every table has the same rows as before" }'
  echo "== rehearsal passed: the change(s) apply cleanly to last night's data"
elif [ $status -ne 0 ]; then
  echo "== rehearsal FAILED: fix the change before it goes to live"
fi

# a test sample from the copy (tests/README.md, "The sample"), at the backup's moment, before any test or save touches it
if [ $status -eq 0 ] && [ -n "${SAMPLE_DIR:-}" ]; then
  at=$(date -u -d "${ran_at:-now}" +'%Y-%m-%dT%H:%M:00Z')
  mkdir -p "$SAMPLE_DIR"
  if psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -v at="$at" -f tests/fixtures/sample.sql | gzip -9n > "$SAMPLE_DIR/sample_${at:0:10}.json.gz"; then
    echo "== test sample made from the copy: sample_${at:0:10}.json.gz, as of $at ($(du -h "$SAMPLE_DIR/sample_${at:0:10}.json.gz" | cut -f1))"
  else
    echo "FAIL  the test sample couldn't be made"; status=1
  fi
fi

# the weekly report's sample (tests/README.md, "The report sample"): the figures, the planning library's input and the
# latest scan through export_for_report(), at the backup's moment, before any test or save touches the copy
if [ $status -eq 0 ] && [ -n "${REPORT_SAMPLE_DIR:-}" ]; then
  at=$(date -u -d "${ran_at:-now}" +'%Y-%m-%dT%H:%M:00Z')
  mkdir -p "$REPORT_SAMPLE_DIR"
  if psql "$LOCAL" -X -q -At -v ON_ERROR_STOP=1 -v at="$at" -f tests/fixtures/report_sample.sql \
       | python3 tests/fixtures/report_sample.py "$REPORT_SAMPLE_DIR/report_${at:0:10}.json.gz"; then
    echo "== report sample made from the copy: report_${at:0:10}.json.gz, as of $at ($(du -h "$REPORT_SAMPLE_DIR/report_${at:0:10}.json.gz" | cut -f1))"
  else
    echo "FAIL  the report sample couldn't be made"; status=1
  fi
fi

# the airline briefing's sample (tests/README.md, "The briefing sample"; #24): what scripts/briefing/brief.py reads for
# every one of our airlines through export_for_report(), at the backup's moment, before any test or save touches the copy
if [ $status -eq 0 ] && [ -n "${BRIEFING_SAMPLE_DIR:-}" ]; then
  at=$(date -u -d "${ran_at:-now}" +'%Y-%m-%dT%H:%M:00Z')
  mkdir -p "$BRIEFING_SAMPLE_DIR"
  if psql "$LOCAL" -X -q -At -v ON_ERROR_STOP=1 -v at="$at" -f tests/fixtures/briefing_sample.sql \
       | python3 tests/fixtures/briefing_sample.py "$BRIEFING_SAMPLE_DIR/briefing_${at:0:10}.json.gz"; then
    echo "== briefing sample made from the copy: briefing_${at:0:10}.json.gz, as of $at ($(du -h "$BRIEFING_SAMPLE_DIR/briefing_${at:0:10}.json.gz" | cut -f1))"
  else
    echo "FAIL  the briefing sample couldn't be made"; status=1
  fi
fi

# the capture's saved pages (tests/README.md, "The capture sample"; #21): one airline's five pages of its newest complete
# evening, with what to expect of them and the rows they give, before any test or save touches the copy
if [ $status -eq 0 ] && [ -n "${CAPTURE_SAMPLE_DIR:-}" ]; then
  mkdir -p "$CAPTURE_SAMPLE_DIR"
  if psql "$LOCAL" -X -q -At -v ON_ERROR_STOP=1 -f tests/fixtures/capture_sample.sql > "$work/capture_sample.json" \
     && day=$(jq -r '.capture_day' "$work/capture_sample.json") && [ -n "$day" ] && [ "$day" != null ]; then
    gzip -9n < "$work/capture_sample.json" > "$CAPTURE_SAMPLE_DIR/capture_pages_${day}.json.gz"
    echo "== capture sample made from the copy: capture_pages_${day}.json.gz ($(du -h "$CAPTURE_SAMPLE_DIR/capture_pages_${day}.json.gz" | cut -f1))"
  else
    echo "FAIL  the capture sample couldn't be made"; status=1
  fi
  rm -f "$work/capture_sample.json"
fi

if [ $status -eq 0 ]; then
  tests=(database/tests/*.sql)
  if [ -e "${tests[0]}" ]; then echo "== database tests (each rolled back afterwards)"; fi
  for t in "${tests[@]}"; do
    [ -e "$t" ] || continue
    if out=$(psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 -c 'begin' -f "$t" -c 'rollback' 2>&1); then
      echo "ok    $(basename "$t")"
      # what the test says it checked (counts only, never rows), for the pull request
      echo "$out" | sed -n 's/^.*NOTICE:  \(.*\)$/      \1/p' | grep -v 'all checks passed' | head -n 6 || true
    else
      echo "FAIL  $(basename "$t")"
      echo "$out" | grep -E 'ERROR|DETAIL|CONTEXT' | sed 's/^/      /' | head -n 6
      status=1
    fi
  done
fi

# From here on a failure fails the run but doesn't stop the steps after it, as long as the copy itself is sound (1 to 5
# passed): a guide or types file that only needs committing from the run's artifact shouldn't hide what the planner does.
copy_ok=$([ $status -eq 0 ] && echo yes || echo no)

if [ "$copy_ok" = yes ]; then
  echo "== descriptions and the table guide (decision #10)"
  flag=--check; [ "${WRITE_DOCS:-0}" = 1 ] && flag=
  out_flag=(); if [ -n "${DOCS_DIR:-}" ]; then mkdir -p "$DOCS_DIR" && out_flag=(--out "$DOCS_DIR/data.md"); fi
  psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -f database/describe.sql | python3 database/describe.py $flag "${out_flag[@]}" || status=1
fi

if [ "$copy_ok" = yes ]; then
  new_planner || status=1
fi

if [ "$copy_ok" = yes ]; then
  briefing_copy || status=1   # read only: before the saves, which change the copy
fi

if [ "$copy_ok" = yes ]; then
  planner_saves || status=1   # last on the copy: its saves change it
fi

if [ "$copy_ok" = yes ] && [ ${#pending[@]} -gt 0 ]; then
  backup_restore || status=1   # stops the copy
fi
exit $status
