# shellcheck shell=bash
# shellcheck disable=SC2034  # sourced by the other scripts
# Shared settings for the backup scripts. Copied on 9 Oct 2026 from scripts/config.sh in GiteshJain/equinox-backups,
# which keeps its own copy for the nightly job. Used here by database/rehearse.sh. Keep the two the same.
PROJECT_REF=ulecwsyedvwcxgdzmhoq
# Data that never leaves the database: keys and password hashes (re-issue them after a restore; see README).
SECRET_TABLES="public.ingest_secret,public.capture_keys,public.report_access"
