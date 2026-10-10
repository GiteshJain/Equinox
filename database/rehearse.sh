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
# 3. Applies them in order, each in its own transaction, stopping at the first failure.
# 4. Prints the row count of every table that changed, plus any table added or removed.
# 5. Runs every test in database/tests/ on the copy, each in a transaction that is rolled back, and prints what each
#    passing test says it checked (its notices: counts, never rows).
# 6. Checks the descriptions (decision #10): every table, view and function has one, and docs/data.md matches the
#    database. With WRITE_DOCS=1 it rewrites docs/data.md instead (run that locally after changing a description).
# 7. Real saves (#17), only if 1 to 6 passed: the data API reloads its schema, then tests/real_saves_test.py opens the
#    pull request's planner, signs in as a test staff user and saves into the copy for real, and reads the tables back.
#    Needs Python with Playwright 1.56 (and its Chromium) and Node 22 (npm), as the workflow installs.
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
made="unknown date"
if [ -f "$backup/latest.json" ]; then
  ran_at=$(jq -r '.ran_at // empty' "$backup/latest.json" 2> /dev/null || true)
  key=$(jq -r '.key // empty' "$backup/latest.json" 2> /dev/null || true)
  if [ -n "$ran_at" ]; then made=$(date -u -d "$ran_at" +'%d %b %H:%M UTC' 2> /dev/null || echo "$ran_at"); fi
  if [ -n "$key" ]; then made="$made, $key"; fi
fi
echo "== restoring last night's backup ($made)"
cd "$work"
supabase init < /dev/null > /dev/null
sed -i 's/^major_version = .*/major_version = 17/' supabase/config.toml   # same Postgres version as the live database
# Only what the planner calls: the database, sign-in (gotrue), the data API (postgrest) and the gateway in front of them
# (kong). Everything else the CLI can start is left out; the list is read from the CLI so a new service stays out too.
services=$(supabase start --help 2> /dev/null | sed -n 's/.*--exclude.*\[\([a-z0-9,_-]*\)\].*/\1/p' | head -n 1)
[ -n "$services" ] || services="gotrue,realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"
leave_out=$(tr ',' '\n' <<< "$services" | grep -vxF -e gotrue -e postgrest -e kong | paste -sd, -)
# the CLI prints the local keys when it starts: they stay in start.log, and are taken out if it is ever shown
hide_keys() { sed -E 's/eyJ[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*/[key]/g; s/sb_(secret|publishable)_[A-Za-z0-9_-]+/[key]/g; s/((key|secret)[^:=]*[:=][[:space:]"]*)[^[:space:]",]+/\1[key]/Ig'; }
supabase start -x "$leave_out" > "$work/start.log" 2>&1 || { tail -n 20 "$work/start.log" | hide_keys; exit 1; }
trap 'supabase stop --no-backup --workdir "$work" > /dev/null 2>&1 || true' EXIT   # stop the copy however this ends
cd "$here"
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
count() { psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -v skip="$SECRET_TABLES" -f database/backup/counts.sql | sort; }
count > "$work/before.txt"
echo "restored: $(wc -l < "$work/before.txt") tables, $(awk '{s+=$2} END {print s+0}' "$work/before.txt") rows"

# what live already has, by version
psql "$LOCAL" -X -At -c "select version from supabase_migrations.schema_migrations" | sort > "$work/applied.txt"
pending=()
for f in database/migrations/*.sql; do
  v=$(basename "$f" | cut -d_ -f1)
  grep -qx "$v" "$work/applied.txt" || pending+=("$f")
done
# changes recorded on live that the repository doesn't have (made outside a pull request)
for f in database/migrations/*.sql; do basename "$f" | cut -d_ -f1; done | sort > "$work/in_repo.txt"
missing=$(comm -23 "$work/applied.txt" "$work/in_repo.txt" || true)
[ -n "$missing" ] && echo "warning: live has changes that aren't in the repository: $(echo $missing)"
# edits to a change that live already has do nothing there; the change needs a new migration instead
if git rev-parse --verify -q "origin/$base" > /dev/null; then
  edited=$(git diff --name-only --diff-filter=M "origin/$base"...HEAD -- database/migrations/ || true)
  [ -n "$edited" ] && echo "warning: these already-applied changes were edited, which won't change live: $(echo $edited)"
fi

status=0
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
for f in "${pending[@]}"; do
  start=$(date +%s%N)
  if out=$(psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 -f "$f" 2>&1); then
    echo "ok    $(basename "$f")  ($(( ($(date +%s%N) - start) / 1000000 )) ms)"
  else
    echo "FAIL  $(basename "$f")"
    echo "$out" | grep -E 'ERROR|DETAIL|HINT|CONTEXT|LINE' | sed 's/^/      /' | head -n 12
    status=1
    break
  fi
done

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
  echo "== descriptions and the table guide (decision #10)"
  flag=--check; [ "${WRITE_DOCS:-0}" = 1 ] && flag=
  psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -f database/describe.sql | python3 database/describe.py $flag || status=1
fi

# Real saves (#17): the pull request's planner saves into the copy. The local address and keys go to the test in a file
# only this user can read; they are never printed.
real_saves() {
  local env="$work/local.env" api anon code tries=0 rc=0
  (umask 077 && supabase status -o env --workdir "$work" > "$env" 2> /dev/null) \
    || { echo "FAIL  couldn't read the local copy's address and keys"; rm -f "$env"; return 1; }
  api=$(sed -n 's/^API_URL="\(.*\)"$/\1/p' "$env"); anon=$(sed -n 's/^ANON_KEY="\(.*\)"$/\1/p' "$env")
  # the data API read the database's tables when it started, before the restore: reload them, then wait until it serves
  # a restored table (any answer but "not found", "schema not loaded" or no answer at all)
  psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 -c "notify pgrst, 'reload schema'" > /dev/null
  while :; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $anon" "$api/rest/v1/planner_state?select=id&limit=1" || true)
    case "$code" in 200|401|403) break ;; esac
    tries=$((tries + 1))
    if [ $tries -ge 60 ]; then rc=1; break; fi
    sleep 1
  done
  if [ $rc -ne 0 ]; then
    echo "FAIL  the data API didn't answer within a minute of reloading (last answer: ${code:-none})"
  else
    echo "the data API reloaded and answers for the restored tables (after ${tries}s)"
    LOCAL_SUPABASE_ENV="$env" LOCAL_DB_URL="$LOCAL" SECRET_TABLES="$SECRET_TABLES" python3 tests/real_saves_test.py || rc=$?
  fi
  rm -f "$env"
  return $rc
}
if [ $status -eq 0 ]; then
  echo "== real saves: the pull request's planner, signed in as test staff, saving into the copy (#17)"
  real_saves || status=1
fi
exit $status
