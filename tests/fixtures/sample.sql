-- The test sample (decision #9): what the website reads at one moment, as one JSON document. Run with psql -v at=<moment,
-- UTC> on a copy of the database, by tests/fixtures/make_sample.sh or database/rehearse.sh. The website check
-- (tests/site_test.py) opens every page on its feed (site_public()) with the clock frozen at the moment. Until the
-- clean-up (#18 build pull request 14) it also carried the old planner's document, loads and route research, and the
-- tables its capture board read, for the old planner's checks, which went with it; the samples made then still hold them
-- (tests/report_test.py leaves the old document beside the weekly report, which must not read it). Never keys or
-- sign-in data.
select json_build_object(
  'frozen_at', :'at'::timestamptz,
  'made_from', 'nightly backup, read as of ' || :'at'::timestamptz || '; the website''s feed from site_public()',
  'site_public', (select public.site_public()));
