#!/usr/bin/env bash
# Runs every automatic check (decision #9); GitHub runs this on every pull request and every change to main.
# Exit code 1 if any check fails. Needs Python with Playwright (and its Chromium) and Node 22.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
status=0; summary=()
run() {
  local name=$1; shift
  echo "=== $name"
  if "$@"; then summary+=("passed  $name"); else summary+=("FAILED  $name"); status=1; fi
  echo
}
run "No keys or passwords" python3 tests/check_secrets.py
run "Schedule check" node tests/schedule_test.mjs
run "Planner: screens, look-only previews, known answers" python3 tests/planner_test.py
run "Website" python3 tests/site_test.py
run "Rule numbers: the planner's code against settings and world_rules" python3 tests/rule_numbers_test.py
echo "=== Summary"
printf '%s\n' "${summary[@]}"
exit $status
