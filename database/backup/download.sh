#!/usr/bin/env bash
# Gets the latest nightly backup from Cloudflare R2 (decision #16): reads latest.json at the bucket's root, downloads
# the copy it names, checks its SHA-256 against latest.json and unpacks it into <folder> (db/, files/ and MANIFEST.md).
# It keeps latest.json there too, so database/rehearse.sh can say which night the copy is from.
# Usage: database/backup/download.sh <folder>   (the folder must be empty or not exist yet)
# Used by the database rehearsal (.github/workflows/database-rehearsal.yml), and to get a backup for
# tests/fixtures/make_sample.sh. Needs the AWS CLI, jq, and R2_ENDPOINT, AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
# (the R2 reader key, read-only). Prints R2 keys (object names) only, never the endpoint or keys.
set -euo pipefail

dest="${1:?usage: download.sh <folder>}"
BUCKET=equinox-backups
export AWS_PAGER=""   # the AWS CLI prints its answers instead of opening a pager
# newer AWS CLIs add checksums that R2 can refuse
export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
export AWS_RESPONSE_CHECKSUM_VALIDATION="${AWS_RESPONSE_CHECKSUM_VALIDATION:-when_required}"

stop() { echo "stopped: $*"; exit 1; }

echo "== getting last night's backup from R2"
missing=()
[ -n "${R2_ENDPOINT:-}" ] || missing+=(R2_ENDPOINT)
[ -n "${AWS_ACCESS_KEY_ID:-}" ] || missing+=(R2_READ_ACCESS_KEY_ID)
[ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || missing+=(R2_READ_SECRET_ACCESS_KEY)
if [ ${#missing[@]} -gt 0 ]; then
  list="${missing[*]}"
  stop "The R2 reader keys aren't set up yet (see the planner's To-do board). Missing secrets: ${list// /, }"
fi
if [ -e "$dest" ] && [ -n "$(ls -A "$dest")" ]; then stop "$dest isn't empty; give a new or empty folder"; fi

# Any error text from R2 has the endpoint (it names the Cloudflare account) and the keys taken out before it is shown,
# because the log is also posted on the pull request.
host="${R2_ENDPOINT#*://}"; host="${host%%/*}"
hide() {
  local s
  s=$(sed -E 's#(https?://)?[[:alnum:].-]*\.r2\.cloudflarestorage\.com#[R2]#g')
  s="${s//"$R2_ENDPOINT"/[R2]}"; s="${s//"$host"/[R2]}"
  s="${s//"$AWS_ACCESS_KEY_ID"/[key]}"; s="${s//"$AWS_SECRET_ACCESS_KEY"/[key]}"
  if [ -n "$s" ]; then printf '%s\n' "$s"; fi
}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
r2() {
  local rc=0
  aws --endpoint-url "$R2_ENDPOINT" --region auto "$@" 2> "$work/aws_err" || rc=$?
  hide < "$work/aws_err" >&2
  return "$rc"
}

# 1. latest.json says which copy is the latest: {key, sha256, bytes, ran_at, kind}
r2 s3 cp --only-show-errors "s3://$BUCKET/latest.json" "$work/latest.json" || stop "couldn't read latest.json from R2 (above)"
field() { jq -r --arg f "$1" '.[$f] // empty | tostring' "$work/latest.json" 2> /dev/null || true; }
key=$(field key); sha=$(field sha256); bytes=$(field bytes); ran_at=$(field ran_at)
[[ "$key" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*\.tar\.gz$ && "$key" != *..* ]] || stop "latest.json doesn't name a backup copy"
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || stop "latest.json has no SHA-256 for $key"
echo "latest: $key (made ${ran_at:-at an unknown time})"

# 2. Download it and check it is exactly the file that was uploaded
r2 s3 cp --only-show-errors "s3://$BUCKET/$key" "$work/copy.tar.gz" || stop "couldn't download $key (above)"
got=$(($(wc -c < "$work/copy.tar.gz")))
if [[ "$bytes" =~ ^[0-9]+$ ]] && [ "$got" != "$bytes" ]; then stop "$key is $got bytes, but latest.json says $bytes"; fi
[ "$(sha256sum < "$work/copy.tar.gz" | cut -d' ' -f1)" = "$sha" ] \
  || stop "$key doesn't match latest.json (SHA-256 differs), so it isn't used"
echo "checked: $key downloaded, $(awk -v b="$got" 'BEGIN { printf "%.1f MB", b / 1048576 }'), SHA-256 matches latest.json"

# 3. Unpack, and keep latest.json beside the copy
mkdir -p "$dest"
tar -xzf "$work/copy.tar.gz" -C "$dest" --no-same-owner || stop "couldn't unpack $key"
[ -f "$dest/db/schema.sql" ] || stop "$key has no db/schema.sql, so it isn't a backup copy"
cp "$work/latest.json" "$dest/latest.json"
echo "checked: unpacked into $dest, with latest.json beside it"
