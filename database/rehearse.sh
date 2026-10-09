#!/usr/bin/env bash
# Rehearses database changes on a copy of last night's backup before they reach the live database (decision #8).
#
# Usage: database/rehearse.sh <folder holding the equinox-backups checkout> [base branch]
# Run by .github/workflows/database-rehearsal.yml on every pull request that touches database/migrations/.
#
# 1. Restores the backup into an empty local Supabase database (Docker), the same way the nightly restore check does.
# 2. Finds the changes still to apply: migration files whose version isn't in the restored migration record, which is
#    the live database's record as of last night.
# 3. Applies them in order, each in its own transaction, stopping at the first failure.
# 4. Prints the row count of every table that changed, plus any table added or removed.
# 5. Checks the descriptions (decision #10): every table, view and function has one, and docs/data.md matches the
#    database. With WRITE_DOCS=1 it rewrites docs/data.md instead (run that locally after changing a description).
# Only table names, counts, descriptions and error messages are printed. The copy exists only on the runner while this runs.
set -euo pipefail
export LC_ALL=C   # sort, join and comm agree on order
backup=$(cd "$1" && pwd)
base=${2:-main}
LOCAL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
here=$(pwd)
work=$(mktemp -d)
source "$backup/scripts/config.sh"   # SECRET_TABLES: never in the backup, so never counted

echo "== restoring last night's backup ($(git -C "$backup" log -1 --format='%s, %cd' --date=format:'%d %b %H:%M UTC'))"
cd "$work"
supabase init < /dev/null > /dev/null
sed -i 's/^major_version = .*/major_version = 17/' supabase/config.toml   # same Postgres version as the live database
supabase db start > "$work/start.log" 2>&1 || { tail -n 20 "$work/start.log"; exit 1; }
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
count() { psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -v skip="$SECRET_TABLES" -f "$backup/scripts/counts.sql" | sort; }
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
if [ ${#pending[@]} -eq 0 ]; then echo "== no new database changes: nothing to rehearse"
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
  echo "== descriptions and the table guide (decision #10)"
  flag=--check; [ "${WRITE_DOCS:-0}" = 1 ] && flag=
  psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -f database/describe.sql | python3 database/describe.py $flag || status=1
fi
exit $status
