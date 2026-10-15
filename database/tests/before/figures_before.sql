-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, for its "figures moved"
-- step (spec docs/specs/2026-10-15-small-fixes.md §1): every captured figure for every airline
-- (export_for_report('figures')'s document, private.fig_export()) at one moment, the copy's latest capture plus an hour
-- (the planner's frozen moment). After the changes and the database tests the step works them out again at the same
-- moment and writes every figure that moved, before and after, to the run's figures-moved artifact. Nothing is printed.
create table rehearsal_before.figures (name text primary key, value jsonb);
do $$
declare w bigint := (select x.id from public.worlds x where x.is_default);
  v_at timestamptz := date_trunc('minute', coalesce((select max(r.captured_at) from public.game_capture_raw r), now())) + interval '1 hour';
begin
  insert into rehearsal_before.figures (name, value) values
    ('world_id', to_jsonb(w)),
    ('as_of', to_jsonb(v_at)),
    ('figures', private.fig_export(w, v_at));
end
$$;
