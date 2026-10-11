-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and compared
-- afterwards by database/tests/history_scans_test.sql (#13 build, pull request 6): once the world scans live in
-- game_scans and its tables, export_for_report()'s scan kinds (the list of scans, and every scan's airlines and
-- airports), export_planner_data() and export_repo_bootstrap() must give what they gave before. Also the capture time of
-- each game_balance and game_pnl row, for the two-captures fix (history_two_captures_test.sql), and whether the daily
-- history was there already (history_backfill_test.sql). The ingest secret is a throwaway one, removed again; nothing
-- is printed.
create table rehearsal_before.scan_outputs (name text primary key, value jsonb);

do $$
declare s text := 'rehearsal-' || gen_random_uuid(); v_scans jsonb; e jsonb;
begin
  insert into public.ingest_secret (secret) values (s);
  v_scans := public.export_for_report(s, 'snapshots');
  insert into rehearsal_before.scan_outputs (name, value) values ('snapshots', v_scans);
  for e in select x from jsonb_array_elements(v_scans) x loop
    insert into rehearsal_before.scan_outputs (name, value) values
      ('airlines ' || (e ->> 'id'), public.export_for_report(s, 'airlines', e ->> 'id')),
      ('airports ' || (e ->> 'id'), public.export_for_report(s, 'airports', e ->> 'id'));
  end loop;
  insert into rehearsal_before.scan_outputs (name, value) values
    ('export_planner_data', public.export_planner_data(s)),
    ('export_repo_bootstrap', public.export_repo_bootstrap(s));
  delete from public.ingest_secret where secret = s;
end
$$;

create table rehearsal_before.game_balance_times as
  select airline, captured_on, account, amount, captured_at from public.game_balance;
create table rehearsal_before.game_pnl_times as
  select airline, captured_on, line, current_p, last_p, total_p, captured_at from public.game_pnl;

-- whether the daily history was there already, so the backfill test can tell the night it is filled back (its figures
-- checked exactly against what was known) from the nights after (kept by the snapshots since)
create table rehearsal_before.history_tables as
  select to_regclass('public.airline_days') is not null as existed;
