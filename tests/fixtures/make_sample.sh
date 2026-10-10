#!/usr/bin/env bash
# Makes the frozen test sample (decision #9) from a nightly backup: what the planner and the website would read at one
# moment in time, saved as tests/fixtures/sample_<date>.json.gz. Small and dated; never keys or sign-in data (the backup
# leaves those out, and the secrets check runs over the result).
#
# Usage: tests/fixtures/make_sample.sh <unpacked backup folder> <moment, UTC, e.g. 2026-10-08T21:00:00Z>
# The folder holds db/ from a backup copy. The copies are in Cloudflare R2 (decision #16): get the latest with
# database/backup/download.sh <folder> and the R2 reader key, which downloads latest.json and the copy it names, checks
# the SHA-256 and unpacks it. tests/README.md has the steps, and how to get an older night.
# Since the switch-over (#13, pull request 9) the planner reads the tables through the adapter, so the sample is made the
# same way (tests/fixtures/sample.sql): the copy first gets every change in database/migrations/ the backup doesn't have
# yet, as the database rehearsal does, then the getters build the planner's document and loads. The rehearsal can make a
# sample too, from its own copy (tests/README.md).
# Needs Docker, the Supabase CLI and psql 17 (or 16). Run from the repository root.
set -euo pipefail
backup=$(cd "$1" && pwd); at=$2
LOCAL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
here=$(pwd); work=$(mktemp -d)
out="tests/fixtures/sample_${at:0:10}.json.gz"

cd "$work"; supabase init < /dev/null > /dev/null
sed -i 's/^major_version = .*/major_version = 17/' supabase/config.toml
supabase db start > "$work/start.log" 2>&1 || { tail -n 20 "$work/start.log"; exit 1; }
trap 'supabase stop --no-backup --workdir "$work" > /dev/null 2>&1 || true' EXIT
cd "$here"
grep -v 'cli_login_postgres' "$backup/db/roles.sql" > "$work/roles.sql" || true
psql "$LOCAL" -X -q -b -f "$work/roles.sql" > /dev/null 2>&1 || true
psql "$LOCAL" -X -q -v ON_ERROR_STOP=1 \
  -c "alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated, service_role" \
  -c "alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated, service_role" \
  -c "alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated, service_role" > /dev/null
psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 \
  -f "$backup/db/schema.sql" -c 'SET session_replication_role = replica' -f "$backup/db/data.sql" > /dev/null

# the changes the backup doesn't have yet (by version, as database/rehearse.sh finds them)
psql "$LOCAL" -X -At -c "select version from supabase_migrations.schema_migrations" | sort > "$work/applied.txt"
for f in database/migrations/*.sql; do
  v=$(basename "$f" | cut -d_ -f1)
  grep -qx "$v" "$work/applied.txt" && continue
  psql "$LOCAL" -X -q --single-transaction -v ON_ERROR_STOP=1 -f "$f" > /dev/null || { echo "couldn't apply $(basename "$f")"; exit 1; }
  echo "applied $(basename "$f")"
done

psql "$LOCAL" -X -At -v ON_ERROR_STOP=1 -v at="$at" -f tests/fixtures/sample.sql | gzip -9n > "$out"
echo "wrote $out ($(du -h "$out" | cut -f1))"
