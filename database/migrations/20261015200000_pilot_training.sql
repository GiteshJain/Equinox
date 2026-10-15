-- Pilot-training payments are an order's payment, not a flight's cost (spec docs/specs/2026-10-15-small-fixes.md §1).
--
-- The 14 Oct orders brought 34 "Pilot training" lines on the bank statements, each beside a cabin payment. The capture
-- sorts a statement line into a flight or a payment by its wording (private.payment_kind(), private.is_payment_line()),
-- and didn't know this one, so each was stored as an unnamed payment (game_payments kind other), which game_flight_pnl,
-- game_ops_recent and the captured figures count as a flight's costs (route_profit(), aircraft_profit(), the flight
-- profit a day in airline_cards() and cash_forecast(), growth_signals()). Flight profit was understated, as with the
-- salary label on 10 Oct (20261010180000). That fix taught the views to add back only kind other, with the classifier
-- naming the salary line; this one teaches the classifier the pilot-training line, so the views and figures leave it out
-- as they leave out the cabin beside it.
--
-- Kind cabin: a one-off payment that comes with an aircraft order, like the cabin payment it sits beside. game_payments.kind
-- keeps its list of kinds (a new one would mean dropping and adding the table's check, which can't be applied from the
-- chat); its description says what cabin now holds.
--
-- Replaces one function with the same arguments, re-sorts the lines already stored and updates three descriptions;
-- takes nothing away from anyone and changes no table's shape, so it can be applied from the chat:
--   private.payment_kind(text): a line naming training ("Pilot training ...") is kind cabin. Everything else as before.
--     private.is_payment_line() follows it, so the capture's fold (private.fold_statement()) makes such a line a
--     payment, never part of a flight.
--   The data step, logged as migration: every stored payment of kind other that the classifier now names takes its kind;
--   any statement line now a payment but still tied to a flight has its minutes folded again (private.fold_statement(),
--   the capture's own step); and the daily history (airline_days, route_days) of the days those lines fall on is worked
--   out again (private.history_flows(), as the evening snapshot does), so the purchases paid that day count them.
--   Profit a day from cash (airline_profit()) reads cash and spending_log, so it doesn't move.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261015200000_pilot_training', true);

-- ---------------------------------------------------------------- 1. the classifier
create or replace function private.payment_kind(p_descr text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select case
    when p_descr ilike 'Leasing rate%' then 'lease'
    when p_descr ilike 'Week-end closing%' or p_descr ilike '%salaries%' then 'salaries'
    when p_descr ilike '%deposit%' then 'deposit'
    when p_descr ilike '%purchase%' then 'purchase'
    when p_descr ilike '%configuration%' then 'refit'
    when p_descr ilike '%cabin%' then 'cabin'
    when p_descr ilike '%training%' then 'cabin'
    else 'other' end
$function$;

-- ---------------------------------------------------------------- 2. the lines already stored
do $data$
declare
  n_kind int := 0; n_minutes int := 0; n_days int := 0; r record; v_flows jsonb;
begin
  create temporary table t_resorted (world_id bigint, airline_id bigint, at timestamptz) on commit drop;

  -- payments stored as unnamed that the classifier now names (the pilot-training lines)
  with u as (
    update public.game_payments p set kind = private.payment_kind(p.descr)
     where p.kind = 'other' and private.payment_kind(p.descr) <> 'other'
    returning p.world_id, p.airline_id, p.paid_at)
  insert into t_resorted select * from u;
  get diagnostics n_kind = row_count;

  -- statement lines now payments but still tied to a flight: their minutes folded again, as the capture folds them
  for r in
    select s.airline_id, s.world_id, array_agg(distinct s.ts) as minutes
      from public.game_statement s
     where s.flight_id is not null and private.is_payment_line(s.descr, s.blk)
     group by s.airline_id, s.world_id
  loop
    perform private.fold_statement(r.airline_id, r.minutes);
    insert into t_resorted select r.world_id, r.airline_id, m from unnest(r.minutes) m;
    n_minutes := n_minutes + cardinality(r.minutes);
  end loop;

  -- the daily history of the days those lines fall on (UTC), as the evening snapshot works it out
  for r in
    select x.world_id, min((x.at at time zone 'UTC')::date) as d0, max((x.at at time zone 'UTC')::date) as d1
      from t_resorted x group by x.world_id
  loop
    v_flows := private.history_flows(r.world_id, r.d0, r.d1);
    n_days := n_days + coalesce((v_flows ->> 'airline_days')::int, 0);
  end loop;

  raise notice 'pilot training re-sorted: % stored payments named (kind other to their kind), % minutes folded again, % airline days of history worked out again',
    n_kind, n_minutes, n_days;
end
$data$;

-- ---------------------------------------------------------------- 3. descriptions (decision #10)
comment on function private.payment_kind(text) is 'The kind of a statement line that isn''t tied to a flight (game_payments.kind): lease, salaries ("Payment of employee salaries", the week-end closing), deposit, purchase, refit (a configuration), cabin (a cabin, and since 15 Oct the pilot training that comes with an order: "Pilot training", 20261015200000), or other.';
comment on function private.is_payment_line(text, integer) is 'True for a statement line that never belongs to a flight: a lease, salaries, a deposit, a purchase, a refit, a cabin or pilot training (private.payment_kind() names it), or a line the parser put in block 0.';
comment on column public.game_payments.kind is 'lease, salaries, purchase, deposit, cabin (a cabin, or the pilot training that comes with an order, since 15 Oct), refit or other';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
