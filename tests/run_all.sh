#!/usr/bin/env bash
# Runs every automatic check (decision #9); GitHub runs this on every pull request and every change to main.
# Exit code 1 if any check fails. Needs Python with Playwright 1.61.0 (and its Chromium), reportlab, matplotlib and
# pypdf (the weekly report's test), the Liberation Sans fonts, and Node 22.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
status=0; summary=()
run() {
  local name=$1; shift
  echo "=== $name"
  if "$@"; then summary+=("passed  $name"); else summary+=("FAILED  $name"); status=1; fi
  echo
}
# The planner (#18, design §10) and the planning library (#19, lib/rules/): the same install and build Cloudflare runs,
# so a pull request that wouldn't build can't merge. It builds the planner into web/app/, which the website check then
# opens at /planner/, and the library into lib/rules/dist/ (whose command the screens' figures check, the optimiser
# check, the weekly report and the airline briefing run) and web/assets/rules.js (which the website check loads).
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
run "Fares userscript: the game's fares form and answer, on dated samples" node tests/fares_userscript_test.mjs
run "Aircraft evaluation userscript: the tool's saved pages read, whole runs against a stand-in for the game" node tests/aircraft_eval_userscript_test.mjs
run "Capture's world scan: the same rows as gscan.py from the same saved pages" node tests/capture_scan_test.mjs
run "Capture's fleet pages: a saved fleet page read as the database keeps it" node tests/capture_fleet_test.mjs
run "Planner and planning library: types, lint, unit tests and cases, build" new_planner
run "Planner: the screens' figures on the 12 Oct sample against saved answers" node tests/planner_figures.mjs
run "Planning library: the optimiser against plan.py's saved answer" python3 tests/optimiser_saved_answer_test.py
run "Planning library: the line optimiser against its saved answer on the A350 sample" python3 tests/line_saved_answer_test.py
run "Weekly report: end to end on the report sample, its money from the figures" python3 tests/report_test.py
run "Airline briefing: every airline on the briefing sample, each section its own" python3 tests/briefing_test.py
run "Market definitions: scan_markets.py and nl_analyze.py on the report sample" python3 tests/market_definitions_test.py
run "Website" python3 tests/site_test.py
echo "=== Summary"
printf '%s\n' "${summary[@]}"
exit $status
