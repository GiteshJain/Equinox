-- The airline briefing's test sample (decision #24; tests/briefing_test.py, tests/README.md "The briefing sample"): what
-- scripts/briefing/brief.py reads, at one moment, for every one of our airlines, as one JSON document. Run with
-- psql -q -v at=<moment, UTC> on a copy of the database by database/rehearse.sh; tests/fixtures/briefing_sample.py cuts
-- it to what the briefing needs.
-- Everything comes through export_for_report(), exactly as brief.py gets it, with a throwaway ingest secret made for this
-- and rolled back: the captured figures as of the moment (kind figures), the planning library's input (kind rules), the
-- list of scans and the latest finished scan by then (its airlines with their schedules), and each airline's briefing
-- rows as of the moment (kind briefing). Never keys or sign-in data.
begin;
create temporary table t_briefing_secret on commit drop as select 'briefing-sample-' || gen_random_uuid()::text as s;
insert into public.ingest_secret (secret) select s from t_briefing_secret;
with k as (select s from t_briefing_secret),
scan as (select g.id, g.taken_at from public.game_scans g
          where g.status = 'done' and g.taken_at <= :'at'::timestamptz order by g.id desc limit 1)
select jsonb_build_object(
  'frozen_at', :'at',
  'made_from', 'nightly backup, read as of ' || :'at' || ' through export_for_report() (figures, rules, the latest finished scan, each airline''s briefing rows)',
  'figures', public.export_for_report(k.s, 'figures', jsonb_build_object('as_of', :'at')::text),
  'rules', public.export_for_report(k.s, 'rules', ''),
  'scan', (select jsonb_build_object('id', scan.id, 'taken_at', scan.taken_at,
                                     'airlines', public.export_for_report(k.s, 'airlines', scan.id::text)) from scan),
  'briefings', (select jsonb_object_agg(al.airline_id::text,
                         public.export_for_report(k.s, 'briefing', jsonb_build_object('airline', al.airline_id, 'as_of', :'at')::text))
                  from private.fig_airlines(private.fig_world(null)) al))
  from k;
rollback;
