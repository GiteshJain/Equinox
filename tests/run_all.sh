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
# The new planner (#18, design §10) and the planning library (#19, lib/rules/): the same install and build Cloudflare
# runs, so a pull request that wouldn't build can't merge. It builds the planner into web/app/, which the website check
# then opens at /planner/next/, and the library into lib/rules/dist/ (whose command the optimiser check and the weekly report
# run) and web/assets/rules.js (which the website check loads).
new_planner() {
  local step
  for step in "npm ci --no-audit --no-fund" "npm run typecheck" "npm run lint" "npm test" "npm run build"; do
    echo "--- $step"
    $step || { echo "FAIL  $step"; return 1; }
  done
  echo "ok    new planner and planning library: npm ci, typecheck, lint, test (the library's cases included) and build all passed"
}
run "No keys or passwords" python3 tests/check_secrets.py
run "Schedule check" node tests/schedule_test.mjs
run "New planner and planning library: types, lint, unit tests and cases, build" new_planner
run "Planning library: the optimiser against plan.py's saved answer" python3 tests/optimiser_saved_answer_test.py
run "Planner: screens, look-only previews, known answers" python3 tests/planner_test.py
run "Website" python3 tests/site_test.py
run "Rule numbers: the planner's code against settings and world_rules" python3 tests/rule_numbers_test.py
echo "=== Summary"
printf '%s\n' "${summary[@]}"
exit $status
