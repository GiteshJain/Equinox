#!/usr/bin/env bash
# Rehearses database changes on a copy of last night's backup before they reach the live database (decision #8).
#
# Usage: database/rehearse.sh <folder holding an unpacked backup: db/, and latest.json if present> [base branch]
# Run by .github/workflows/database-rehearsal.yml on every pull request that touches database/migrations/ or the
# planner. The workflow gets the folder from Cloudflare R2 with database/backup/download.sh (decision #16).
#
# 0. Before this pull request's own database changes (#13, pull request 9): Cloudflare publishes the planner when a pull
#    request is merged, and its database changes are applied afterwards, so when a pull request both changes the planner
#    and adds migrations, its planner must also save into the database as live has it now. The copy is restored (as in
#    1), given only the changes live already has, and the real saves (7) run there with REAL_SAVES_PHASE=before (since
#    the switch-over that copy has the old rows frozen, as live does, and the saves are judged so). Then the copy is
#    thrown away and everything below runs on a fresh one.
# 1. Restores the backup into an empty local Supabase (Docker): the database, the data API and sign-in, with nothing
#    else started (#17). The database is restored the same way the nightly restore check does.
# 2. Finds the changes still to apply: migration files whose version isn't in the restored migration record, which is
#    the live database's record as of last night. Before applying them, runs database/tests/before/*.sql, which save
#    chosen outputs into the schema rehearsal_before, so a test can compare them afterwards.
# 3. Applies them in order, each in its own transaction, stopping at the first failure, then pauses any job they schedule
#    on the copy (pg_cron), so none runs during the tests (passes 0 and 3). With SAMPLE_DIR set, then makes
#    a test sample from the copy (tests/fixtures/sample.sql, at the backup's moment) into that folder.
# 4. Prints the row count of every table that changed, plus any table added or removed.
# 5. Runs every test in database/tests/ on the copy, each in a transaction that is rolled back, and prints what each
#    passing test says it checked (its notices: counts, never rows). Then the rule numbers check on the copy (design
#    §11, choice 3: tests/rule_numbers_test.py --db).
# 6. Checks the descriptions (decision #10): every table, view and function has one, and docs/data.md matches the
#    database. With WRITE_DOCS=1 it rewrites docs/data.md instead (run that locally after changing a description).
# 7. Real saves (#17), only if 1 to 6 passed: the data API reloads its schema, then tests/real_saves_test.py opens the
#    pull request's planner, signs in as a test staff user and saves into the copy for real, and reads the tables back.
#    Needs Python with Playwright 1.56 (and its Chromium) and Node 22 (npm), as the workflow installs.
# 8. The new planner (#18, design §10), only if 1 to 6 passed: its types are generated again from the copy (after every
#    pending change) with the local Supabase CLI and must equal app/planner/src/db/types.ts; the generated file is kept
#    in TYPES_DIR (the run's planner-types artifact) and any difference is printed. Then the new planner is built
#    (npm ci, npm run build), and tests/planner_next_test.py opens it at its live address on the copy, signs in, reads
#    and saves through planner_save(). Runs before the real saves, whose last step (the rollback) changes the copy.
# Only table names, counts, descriptions, ids and error messages are printed, never rows or keys. The copy, its keys and
# its test users exist only on the runner while this runs.
set -euo pipefail
export LC_ALL=C   # sort, join and comm agree on order
backup=$(cd "$1" && pwd)
base=${2:-main}
LOCAL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
here=$(pwd)
work=$(mktemp -d)
source database/backup/config.sh   # SECRET_TABLES: never in the backup, so never counted

# which night the copy is from: latest.json, saved beside the copy when it was downloaded from R2
made="unknown date"; ran_at=""
if [ -f "$backup/latest.json" ]; then
  ran_at=$(jq -r '.ran_at // empty' "$backup/latest.json" 2> /dev/null || true)
  key=$(jq -r '.key // empty' "$backup/latest.json" 2> /dev/null || true)
  if [ -n "$ran_at" ]; then made=$(date -u -d "$ran_at" +'%d %b %H:%M UTC' 2> /dev/null || echo "$ran_at"); fi
  if [ -n "$key" ]; then made="$made, $key"; fi
fi
cd "$work"
supabase init < /dev/null > /dev/null
sed -i 's/^major_version = .*/major_version = 17/' supabase/config.toml   # same Postgres version as the live database
cd "$here"
# Only what the planner calls: the database, sign-in (gotrue), the data API (postgrest) and the gateway in front of them
# (kong). Everything else the CLI can start is left out; the list is read from the CLI so a new service stays out too.
services=$(supabase start --help 2> /dev/null | sed -n 's/.*--exclude.*\[\([a-z0-9,_-]*\)\].*/\1/p' | head -n 1)
[ -n "$services" ] || services="gotrue,realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"
leave_out=$(tr ',' '\n' <<< "$services" | grep -vxF -e gotrue -e postgrest -e kong | paste -sd, -)
# the CLI prints the local keys when it starts: they stay in start.log, and are taken out if it is ever shown
hide_keys() { sed -E 's/eyJ[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*/[key]/g; s/sb_(secret|publishable)_[A-Za-z0-9_-]+/[key]/g; s/((key|secret)[^:=]*[:=][[:space:]"]*)[^[:space:]",]+/\1[key]/Ig'; }
trap 'supabase stop --no-backup --workdir "$work" > /dev/null 2>&1 || true' EXIT   # stop the copy however this ends

# 1. a fresh local Supabase with last night's backup restored into it
restore_copy() {
  supabase stop --no-backup --workdir "$work" > /dev/null 2>&1 || true
  (cd "$work" && supabase start -x "$leave_out" > "$work/start.log" 2>&1) || { tail -n 20 "$work/start.log" | hide_keys; return 1; }
  grep -v 'cli_login_postgres' "$backup/db/roles.sql" > "$work/roles.sql" || true   # the CLI makes this role itself
  psql "$LOCAL" -X -q -b -f "$work/roles.sql" > /dev/null 2>&1 || true            # per-role settings need a superuser
  # The empty local database gives new tables and functions to anon and authenticated by default, and the backup only
  # lists what live grants on top of the usual defaults; without this the copy would be more open than live.
  psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 \
    -c "alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated, service_role" \
    -c "alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated, service_role" \
    -c "alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated, service_role" > /dev/null
  psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 \
    -f "$backup/db/schema.sql" -c 'SET session_replication_role = replica' -f "$backup/db/data.sql" > /dev/null
  psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 \
    -f "$backup/db/history_schema.sql" -f "$backup/db/history_data.sql" > /dev/null
}
count() { psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -v skip="$SECRET_TABLES" -f database/backup/counts.sql | sort; }

# what live already has, by version, and the changes still to apply (all of them, or only those live has: "ours" are
# the migrations this pull request adds, which pass 0 leaves out)
pending_files() {
  psql "$LOCAL" -X -At -c "select version from supabase_migrations.schema_migrations" | sort > "$work/applied.txt"
  local f v
  for f in database/migrations/*.sql; do
    v=$(basename "$f" | cut -d_ -f1)
    grep -qx "$v" "$work/applied.txt" && continue
    if [ "${1:-all}" = "without ours" ] && grep -qxF "$f" "$work/ours.txt"; then continue; fi
    echo "$f"
  done
}
apply_files() {
  local f start out
  for f in "$@"; do
    start=$(date +%s%N)
    if out=$(psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 -f "$f" 2>&1); then
      echo "ok    $(basename "$f")  ($(( ($(date +%s%N) - start) / 1000000 )) ms)"
    else
      echo "FAIL  $(basename "$f")"
      echo "$out" | grep -E 'ERROR|DETAIL|HINT|CONTEXT|LINE' | sed 's/^/      /' | head -n 12
      return 1
    fi
  done
}

# The copy is a test, so jobs that the changes schedule on it (pg_cron, #13 pull request 7) are paused: none may run in
# the middle of the tests or the real saves. A backup carries pg_cron but never its schedules, so only a copy that gets
# the jobs' migration here has any. Their state as the changes left them is kept in rehearsal_before.cron_jobs, where
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

# Real saves (#17): the pull request's planner saves into the copy. The local address and keys go to the test in a file
# only this user can read; they are never printed. $1: the phase (before or after this pull request's own changes).
# The data API read the database's tables when it started, before the restore and the changes: reload them, then wait
# until it serves a restored table (any answer but "not found", "schema not loaded" or no answer at all). $1: the env
# file from `supabase status -o env`.
reload_api() {
  local api anon code tries=0
  api=$(sed -n 's/^API_URL="\(.*\)"$/\1/p' "$1"); anon=$(sed -n 's/^ANON_KEY="\(.*\)"$/\1/p' "$1")
  psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 -c "notify pgrst, 'reload schema'" > /dev/null
  while :; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $anon" "$api/rest/v1/planner_state?select=id&limit=1" || true)
    case "$code" in 200|401|403) break ;; esac
    tries=$((tries + 1))
    if [ $tries -ge 60 ]; then echo "FAIL  the data API didn't answer within a minute of reloading (last answer: ${code:-none})"; return 1; fi
    sleep 1
  done
  echo "the data API reloaded and answers for the restored tables (after ${tries}s)"
}

real_saves() {
  local env="$work/local.env" rc=0
  (umask 077 && supabase status -o env --workdir "$work" > "$env" 2> /dev/null) \
    || { echo "FAIL  couldn't read the local copy's address and keys"; rm -f "$env"; return 1; }
  if reload_api "$env"; then
    LOCAL_SUPABASE_ENV="$env" LOCAL_DB_URL="$LOCAL" SECRET_TABLES="$SECRET_TABLES" REAL_SAVES_PHASE="$1" \
      python3 tests/real_saves_test.py || rc=$?
  else
    rc=1
  fi
  rm -f "$env"
  return $rc
}

# The new planner (#18): its types from the copy, then the planner built and opened on the copy. The local address and
# keys go to the test in a file only this user can read, as for the real saves; they are never printed.
TYPES_FILE=app/planner/src/db/types.ts
new_planner() {
  local env="$work/local.env" gen="$work/types.ts" rc=0
  echo "== the new planner's types, generated from the copy (design §5)"
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
  echo "== the new planner, built and opened on the copy (#18)"
  if ! (npm ci --no-audit --no-fund > "$work/npm.log" 2>&1 && npm run build >> "$work/npm.log" 2>&1); then
    echo "FAIL  the new planner didn't build"
    tail -n 15 "$work/npm.log" | sed 's/^/      /'
    return 1
  fi
  echo "built: web/app/ ($(find web/app -type f | wc -l) files)"
  (umask 077 && supabase status -o env --workdir "$work" > "$env" 2> /dev/null) \
    || { echo "FAIL  couldn't read the local copy's address and keys"; rm -f "$env"; return 1; }
  if reload_api "$env"; then
    LOCAL_SUPABASE_ENV="$env" LOCAL_DB_URL="$LOCAL" SECRET_TABLES="$SECRET_TABLES" python3 tests/planner_next_test.py || rc=1
  else
    rc=1
  fi
  rm -f "$env"
  return $rc
}

# the migrations this pull request adds, and whether it changes the planner (or the real saves themselves)
: > "$work/ours.txt"; planner_changed=""
if git rev-parse --verify -q "origin/$base" > /dev/null; then
  git diff --name-only --diff-filter=A "origin/$base"...HEAD -- database/migrations/ > "$work/ours.txt" || true
  planner_changed=$(git diff --name-only "origin/$base"...HEAD -- web/planner/ tests/real_saves_test.py || true)
fi

status=0
# 0. this pull request's planner on the database as live has it now
if [ -s "$work/ours.txt" ] && [ -n "$planner_changed" ]; then
  echo "== real saves before this pull request's database changes: its planner on the database as live has it now"
  echo "restoring last night's backup ($made)"
  if ! restore_copy; then
    status=1
  else
    mapfile -t before_files < <(pending_files "without ours")
    [ ${#before_files[@]} -eq 0 ] || echo "applying the ${#before_files[@]} change(s) live already has"
    if apply_files "${before_files[@]}" && pause_jobs; then
      real_saves before || status=1
    else
      status=1
    fi
  fi
  if [ $status -ne 0 ]; then echo "== rehearsal FAILED before this pull request's changes: fix the planner (or the copy) first"; exit $status; fi
  echo
fi

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

if [ $status -eq 0 ]; then
  tests=(database/tests/*.sql)
  if [ -e "${tests[0]}" ]; then echo "== database tests (each rolled back afterwards)"; fi
  for t in "${tests[@]}"; do
    [ -e "$t" ] || continue
    if out=$(psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 -c 'begin' -f "$t" -c 'rollback' 2>&1); then
      echo "ok    $(basename "$t")"
      # what the test says it checked (counts only, never rows), for the pull request
      echo "$out" | sed -n 's/^.*NOTICE:  \(.*\)$/      \1/p' | grep -v 'all checks passed' | head -n 4 || true
    else
      echo "FAIL  $(basename "$t")"
      echo "$out" | grep -E 'ERROR|DETAIL|CONTEXT' | sed 's/^/      /' | head -n 6
      status=1
    fi
  done
fi

if [ $status -eq 0 ]; then
  echo "== rule numbers: the old planner's code against settings and world_rules (design §11, choice 3)"
  python3 tests/rule_numbers_test.py --db "$LOCAL" | grep -v '^$' || status=1
fi

if [ $status -eq 0 ]; then
  echo "== descriptions and the table guide (decision #10)"
  flag=--check; [ "${WRITE_DOCS:-0}" = 1 ] && flag=
  psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -f database/describe.sql | python3 database/describe.py $flag || status=1
fi

if [ $status -eq 0 ]; then
  new_planner || status=1
fi

if [ $status -eq 0 ]; then
  echo "== real saves: the pull request's planner, signed in as test staff, saving into the copy (#17)"
  real_saves after || status=1
fi
exit $status
