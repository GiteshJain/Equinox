-- The weekly report's three biggest competitors, on the copy (migration 20261022040000_report_competitors.sql; spec
-- docs/specs/2026-10-21-report-three-competitors.md §1, Checks). Run by database/rehearse.sh on the copy of last night's
-- backup, after the new migrations, inside a transaction that is rolled back; it only reads (the throwaway ingest secret
-- goes with the rollback). The hand-made cases are in competition_test.sql (section 10).
--   1. export_for_report('figures') (what scripts/report/pull.py saves as figures.json) gives every airline its
--      competitors (at most three, biggest on its pairs first, none of ours), self and scans, exactly as competition()
--      gives them at the export's moment; how long the export took, and how much of it competition() was.
--   2. Each airline's three competitors and itself, for the pull request (names and counts only): on its pairs, how many
--      of its pairs, departures a week, airports, and the change against the week-before scan. Three notices, since the
--      rehearsal prints a passing test's first six.

do $test$
declare s text := 'report-competitors-test-' || gen_random_uuid()::text; t0 timestamptz; ms_export int; ms_comp int := 0; v jsonb; a jsonb; c jsonb;
  w bigint := (select id from public.worlds where is_default); at timestamptz; lines text[] := '{}'; bad text; n int := 0;
begin
  insert into public.ingest_secret (secret) values (s);
  t0 := clock_timestamp();
  v := public.export_for_report(s, 'figures', '{}');
  ms_export := round(extract(epoch from clock_timestamp() - t0) * 1000);
  assert ms_export < 30000, format('the figures took %s ms on the copy: over export_for_report()''s 30 s', ms_export);
  at := (v ->> 'as_of')::timestamptz;
  for a in select x from jsonb_array_elements(v -> 'airlines') x loop
    n := n + 1;
    assert a ? 'competitors' and a ? 'self' and a ? 'scans', format('%s: the export has no competitors, self or scans', a ->> 'code');
    t0 := clock_timestamp();
    c := private.fig_competition((a ->> 'airline_id')::bigint, at, 0);
    ms_comp := ms_comp + round(extract(epoch from clock_timestamp() - t0) * 1000);
    assert a -> 'competitors' = c -> 'competitors' and a -> 'self' = c -> 'self' and a -> 'scans' = c -> 'scans',
      format('%s: the export''s competitors, self or scans differ from competition()''s', a ->> 'code');
    assert jsonb_array_length(a -> 'competitors') <= 3, format('%s has more than three competitors', a ->> 'code');
    -- biggest on its pairs first, none of ours
    select string_agg(x ->> 'name', ', ') into bad
      from jsonb_array_elements(a -> 'competitors') with ordinality e(x, i)
      left join public.airlines ra on ra.id = (x ->> 'airline_id')::bigint
      left join public.groups g on g.id = ra.group_id
     where g.kind = 'ours'
        or (x ->> 'on_pairs')::int > case when i > 1 then (a #>> array['competitors', (i - 2)::text, 'on_pairs'])::int end;
    assert bad is null, format('%s: one of ours, or out of order: %s', a ->> 'code', bad);
    lines := lines || format('%s itself %s on %s of its %s pairs, %s a week at %s airports, %s (%s%%) | %s', a ->> 'code',
      coalesce(a #>> '{self,on_pairs}', '–'), coalesce(a #>> '{self,pairs}', '–'), coalesce(a #>> '{self,pairs_flown}', '–'),
      coalesce(a #>> '{self,weekly}', '–'), coalesce(a #>> '{self,airports}', '–'), coalesce(a #>> '{self,change}', 'no change known'),
      coalesce(a #>> '{self,change_pct}', '–'),
      coalesce((select string_agg(format('%s. %s %s on %s pairs, %s a week at %s airports, %s (%s%%)', x ->> 'rank', x ->> 'name', x ->> 'on_pairs',
                                         x ->> 'pairs', x ->> 'weekly', x ->> 'airports', coalesce(x ->> 'change', 'new'), coalesce(x ->> 'change_pct', '–')),
                                  '; ' order by (x ->> 'rank')::int)
                  from jsonb_array_elements(a -> 'competitors') x), 'no rival on its pairs'));
  end loop;
  assert n = (select count(*) from private.fig_airlines(w)), 'the export doesn''t list every one of our airlines';
  raise notice '%', format('on the copy: export_for_report(''figures'') gives each of the %s airlines its competitors, self and scans as competition() gives them; the export took %s ms, %s ms of it competition() (p_limit 0) for the %s airlines; the scans %s against %s',
    n, ms_export, ms_comp, n, coalesce(left(v #>> '{airlines,0,scans,latest,taken_at}', 16), 'none'), coalesce(left(v #>> '{airlines,0,scans,week_before,taken_at}', 16), 'none'));
  raise notice '%', 'on the copy, each airline and its three biggest competitors (departures a week on its pairs, how many of its pairs, its whole network a week, airports, the change against the week-before scan): '
    || array_to_string(lines[1:3], ' || ');
  raise notice '%', 'on the copy, continued: ' || coalesce(nullif(array_to_string(lines[4:], ' || '), ''), 'none');
end
$test$;
