-- The weekly report's test sample (decision #9; tests/report_test.py, tests/README.md "The report sample"): what the
-- report's scripts read, at one moment, as one JSON document. Run with psql -q -v at=<moment, UTC> on a copy of the
-- database by database/rehearse.sh; tests/fixtures/report_sample.py cuts it to what the report needs.
-- Everything comes through export_for_report(), exactly as scripts/report/pull.py gets it, with a throwaway ingest
-- secret made for this and rolled back: the captured figures as of the moment (kind figures), the planning library's
-- input (kind rules), and the latest finished world scan by then (its airlines with their schedules, and its airports).
-- Also the website's airlines (site_public().airlines), for the names' colours. Never keys or sign-in data.
begin;
create temporary table t_report_secret on commit drop as select 'report-sample-' || gen_random_uuid()::text as s;
insert into public.ingest_secret (secret) select s from t_report_secret;
with k as (select s from t_report_secret),
scan as (select g.id, g.taken_at from public.game_scans g
          where g.status = 'done' and g.taken_at <= :'at'::timestamptz order by g.id desc limit 1)
select jsonb_build_object(
  'frozen_at', :'at',
  'made_from', 'nightly backup, read as of ' || :'at' || ' through export_for_report() (figures, rules, the latest finished scan)',
  'figures', public.export_for_report(k.s, 'figures', jsonb_build_object('as_of', :'at')::text),
  'rules', public.export_for_report(k.s, 'rules', ''),
  'scan', jsonb_build_object('id', (select id from scan), 'taken_at', (select taken_at from scan),
                             'airlines', public.export_for_report(k.s, 'airlines', (select id from scan)::text),
                             'airports', public.export_for_report(k.s, 'airports', (select id from scan)::text)),
  'site_airlines', public.site_public() -> 'airlines')
  from k;
rollback;
