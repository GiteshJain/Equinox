-- The salary table (16 Nov 2026; to-do 245, spec docs/specs/2026-11-16-salary-table.md; decided by Gitesh 15 Nov, brief
-- docs/briefs/2026-11-15-salaries-unattended.md, Outcome, and 16 Nov, the spec's four choices).
--
-- Why: the evening capture sets salaries (manual §7: a position below its country average goes to the average plus
-- settings.salary_above_average_pct, 5%; never lowered) but stored nothing about them, so nobody could see where each
-- salary stood. From capture 1.18 each capture that reads salaries sends, per airline, the game's Employee overview page
-- (every position: staff, this week's salary, next week's, the page's country average, what the capture raised) and the
-- airline's country page (each position's average). This stores them, works out the salary table (next week's salary
-- against the target, the country page's average plus 5%) and flags a position more than settings.salary_flag_pct (1%)
-- under or over it. The capture never lowers a salary; Gitesh lowers by hand (to-do 246).
--
-- Adds one column, four tables, two settings and three functions, and replaces three functions (create or replace keeps
-- their grants). Drops, renames and deletes nothing, so it can be applied from the chat:
--   1. airlines.game_country_id: the game's country id, filled for our six airlines in Gander by the world's address and
--      each airline's game id (Pan Am 114 → USA 182, Kingfisher 113 → India 61, Ryanair 112 → Ireland 65, Virgin
--      Atlantic 203 → United Kingdom 54, China Eastern 208 → China 30, Malaysia Airlines 210 → Malaysia 97; the ids read
--      from the game's public country pages on 16 Nov; Ryanair's country Gitesh's answer, 16 Nov).
--   2. settings.salary_flag_pct (1, %) and unattended_salary_read (true), world rows in every world.
--   3. salary_reads, airline_salaries, country_salaries, salary_positions (seeded with Kingfisher's three pilot rows):
--      RLS on, no rule, no access for anon or staff: only the database's own functions read and write them; the planner
--      reads the stored salary_table answer (planner_figures).
--   4. private.capture_salaries(): stores one airline's salaries page (kind salaries) and judges it, ok, short or broken,
--      kept on the raw page and never in the airline's verdict, the day's completeness or the snapshot.
--   5. capture_ingest(): takes the kind salaries (by private.capture_salaries(), apart from the other kinds).
--   6. capture_airlines(): each airline's country_id, and salary_read (true for a press; the unattended key's from
--      unattended_salary_read). salary_above_average_pct is unchanged (null for the unattended key).
--   7. salary_table() (staff, GET) and its builder private.fig_salary_table().
--   8. private.figures_refresh(): stores salary_table with each world's figures.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261116100000_salary_table', true);

-- ============================================================ 1. each airline's country in the game
alter table public.airlines add column if not exists game_country_id integer;
comment on column public.airlines.game_country_id is 'The game''s id for the airline''s country, as in its public country page (/action/info/country?id=<id>), for our airlines: the salary table reads that page''s average salaries (spec docs/specs/2026-11-16-salary-table.md; since 16 Nov). Null for rivals. capture_airlines() gives it to the capture as country_id.';

update public.airlines a
   set game_country_id = x.country_id
  from public.worlds w,
       (values (114, 182), (113, 61), (112, 65), (203, 54), (208, 30), (210, 97)) as x(game_id, country_id)
 where w.id = a.world_id and w.game_host = 'gander.airlinesim.aero' and a.game_id = x.game_id
   and a.game_country_id is distinct from x.country_id;

-- ============================================================ 2. the settings
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, x.unit, x.description, date '2026-11-16', x.reason
  from public.worlds w
 cross join (values
   ('salary_flag_pct', '1'::jsonb, 'percent',
    'The salary table (manual §7; spec docs/specs/2026-11-16-salary-table.md) flags a position whose next week''s salary is more '
    'than this many per cent under or over its target, the country page''s average plus salary_above_average_pct. A position '
    'with no staff is never flagged. salary_table() reads it; Systems'' Salaries board and Today''s one item show the flags.',
    'Gitesh, 15 Nov (Main chat): "if numbers differ by more than 1% on either direction it shows in the planner"'),
   ('unattended_salary_read', 'true'::jsonb, null::text,
    'Whether the unattended capture (the GitHub job, twice a day) reads and stores salaries and the country page''s averages for '
    'the salary table: true. It never sets one (that is unattended_salaries, false). capture_airlines() answers salary_read with '
    'this for the unattended key; false also makes capture_ingest() refuse its salaries page.',
    'Gitesh, 16 Nov: choice 3, option B of docs/specs/2026-11-16-salary-table.md (reading changes nothing in the game)')
 ) as x(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 3. the tables
create table if not exists public.salary_reads (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null references public.airlines (id),
  raw_id bigint references public.game_capture_raw (id) on delete set null,
  read_at timestamptz not null,
  unattended boolean not null default false,
  version text,
  country_id integer,
  country_name text,
  country_code text,
  overview_ok boolean not null,
  country_ok boolean not null,
  overview_error text,
  country_error text,
  verdict text not null check (verdict in ('ok', 'short', 'broken')),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists salary_reads_airline_read_at on public.salary_reads (airline_id, read_at desc);
create index if not exists salary_reads_raw_id on public.salary_reads (raw_id);
create index if not exists salary_reads_world_id on public.salary_reads (world_id);

create table if not exists public.airline_salaries (
  read_id bigint not null references public.salary_reads (id) on delete cascade,
  n smallint not null,
  position text not null,
  crew_group text,
  employed integer,
  active integer,
  required integer,
  salary integer,
  salary_next integer,
  overview_avg integer,
  raised_to integer,
  primary key (read_id, n)
);

create table if not exists public.country_salaries (
  read_id bigint not null references public.salary_reads (id) on delete cascade,
  n smallint not null,
  country_id integer,
  position text not null,
  avg integer not null,
  primary key (read_id, n)
);

create table if not exists public.salary_positions (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  overview_name text not null,
  country_name text not null,
  note text,
  created_at timestamptz not null default now(),
  unique (world_id, overview_name)
);

alter table public.salary_reads enable row level security;
alter table public.airline_salaries enable row level security;
alter table public.country_salaries enable row level security;
alter table public.salary_positions enable row level security;
revoke all on table public.salary_reads, public.airline_salaries, public.country_salaries, public.salary_positions
  from public, anon, authenticated;

insert into public.salary_positions (world_id, overview_name, country_name, note)
select w.id, x.overview_name, x.country_name, x.note
  from public.worlds w
 cross join (values
   ('EMB-170 / -175 / -190 / -195', 'Regional Jet pilots', 'The E-jet family''s pilots (Kingfisher''s Employee overview, 9 Nov)'),
   ('A318 / A319 / A320 / A321', 'Narrow-body pilots', 'The A320 family''s pilots (Kingfisher''s Employee overview, 9 Nov)'),
   ('A330 / A340 / A350', 'Wide-body Pilots', 'The A330, A340 and A350 pilots (Kingfisher''s Employee overview, 9 Nov)')
 ) as x(overview_name, country_name, note)
on conflict (world_id, overview_name) do nothing;

comment on table public.salary_reads is 'One row per airline each time a capture reads its salaries (spec docs/specs/2026-11-16-salary-table.md; manual §7; since 16 Nov, Capture all airlines 1.18): when, by which key (unattended), the airline''s country page (id, name, ISO code), whether the Employee overview page and the country page read, and the read''s verdict (ok; short when the country page didn''t read or a position with staff has no country average; broken when the Employee overview page didn''t read) with its note. Its positions are airline_salaries and the country page''s averages country_salaries. Written only by capture_ingest() (private.capture_salaries()), which deletes an airline''s reads older than 90 days; read by salary_table(). No access for the website or staff: the planner reads the stored salary_table.';
comment on column public.salary_reads.raw_id is 'The capture page it came from (game_capture_raw, kind salaries); null once the 14-day clean-up has deleted it';
comment on column public.salary_reads.read_at is 'When the capture sent it';
comment on column public.salary_reads.unattended is 'True when the unattended capture''s key sent it (it reads, never sets)';
comment on column public.salary_reads.version is 'The capture''s version that read it';
comment on column public.salary_reads.country_id is 'The game''s country id whose page was read (airlines.game_country_id); null when the airline has none';
comment on column public.salary_reads.country_name is 'The country as its page names it, e.g. India';
comment on column public.salary_reads.country_code is 'The country''s ISO code as its page gives it, e.g. IN';
comment on column public.salary_reads.overview_ok is 'Whether the Employee overview page read';
comment on column public.salary_reads.country_ok is 'Whether the country page read';
comment on column public.salary_reads.overview_error is 'Why the Employee overview page didn''t read';
comment on column public.salary_reads.country_error is 'Why the country page didn''t read';
comment on column public.salary_reads.verdict is 'ok, short (the country page didn''t read, or a position with staff has no country average) or broken (the Employee overview page didn''t read)';
comment on column public.salary_reads.note is 'The verdict in words, as the capture''s panel shows it';
comment on table public.airline_salaries is 'Each position on an airline''s Employee overview page at one salary read (salary_reads), in the page''s order (spec docs/specs/2026-11-16-salary-table.md; since 16 Nov): staff employed, active and required, this week''s salary per employee, next week''s salary (the box the capture and Gitesh set), the page''s own country average and, when the capture raised it that run, what to. Written only by private.capture_salaries(); read by salary_table(). No access for the website or staff.';
comment on column public.airline_salaries.n is 'The position''s place on the page, 0 first';
comment on column public.airline_salaries.position is 'The position as the Employee overview names it (pilots by aircraft family, e.g. A318 / A319 / A320 / A321)';
comment on column public.airline_salaries.crew_group is 'Flight crew, Cabin crew or Ground crew, the heading above it on the page';
comment on column public.airline_salaries.employed is 'Staff employed in the position';
comment on column public.airline_salaries.active is 'Staff active';
comment on column public.airline_salaries.required is 'Staff the airline needs';
comment on column public.airline_salaries.salary is 'This week''s salary per employee, AS$';
comment on column public.airline_salaries.salary_next is 'Next week''s salary per employee, AS$: the box on the page, which the capture and Gitesh set; the salary table compares this one';
comment on column public.airline_salaries.overview_avg is 'The country average the Employee overview page shows beside it, AS$ (the capture sets salaries from this one)';
comment on column public.airline_salaries.raised_to is 'What the capture raised next week''s salary to on that run, AS$; null when it didn''t';
comment on table public.country_salaries is 'The average salary of each position on the airline''s country page at one salary read (salary_reads), in the page''s order (spec docs/specs/2026-11-16-salary-table.md; since 16 Nov). The salary table''s target is this average plus salary_above_average_pct. Written only by private.capture_salaries(); read by salary_table(). No access for the website or staff.';
comment on column public.country_salaries.n is 'The position''s place on the page, 0 first';
comment on column public.country_salaries.country_id is 'The game''s country id the page is of';
comment on column public.country_salaries.position is 'The position as the country page names it (pilots by class, e.g. Narrow-body pilots)';
comment on column public.country_salaries.avg is 'The country''s average salary for the position, AS$';
comment on table public.salary_positions is 'How a pilot position on the Employee overview page (named by aircraft family) is named on the country page (by class), per world (spec docs/specs/2026-11-16-salary-table.md; since 16 Nov). Every other position has the same name on both pages and needs no row. A position on neither this list nor the country page is shown unmapped, never guessed. Seeded with the three families on Kingfisher''s page of 9 Nov, which cover every type our airlines fly; a new family is a row added here. Read by private.capture_salaries() and salary_table(). No access for the website or staff.';
comment on column public.salary_positions.overview_name is 'The position as the Employee overview page names it';
comment on column public.salary_positions.country_name is 'The same position as the country page names it';
comment on column public.salary_positions.note is 'Where the pair was seen';

-- ============================================================ 4. a salaries page
-- The country page's name for an Employee overview position: its salary_positions row, else its own name
create or replace function private.salary_country_name(p_world_id bigint, p_position text)
returns text
language sql
stable
set search_path to ''
as $function$
  select coalesce((select m.country_name from public.salary_positions m
                    where m.world_id = p_world_id and lower(btrim(m.overview_name)) = lower(btrim(p_position))), btrim(p_position))
$function$;

-- A whole AS$ figure from what the capture sent: a number, or text like "1,190 AS$"; null when there's none
create or replace function private.salary_int(p jsonb)
returns integer
language sql
immutable
set search_path to ''
as $function$
  select case when jsonb_typeof(p) = 'number' then round((p #>> '{}')::numeric)::int
              when jsonb_typeof(p) = 'string' and regexp_replace(p #>> '{}', '[^0-9]', '', 'g') ~ '^[0-9]{1,9}$'
                then regexp_replace(p #>> '{}', '[^0-9]', '', 'g')::int end
$function$;

create or replace function private.capture_salaries(p_world_id bigint, p_airline text, p_page text, p_rows jsonb,
                                                    p_unattended boolean, p_at timestamptz)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare v_al bigint; v_name text; v_rid bigint; v_read bigint; v_doc jsonb; v_ov jsonb; v_co jsonb; v_ov_ok boolean;
  v_co_ok boolean; v_ov_err text; v_co_err text; v_verdict text; v_note text; v_missing text[]; v_n int := 0; v_off int := 0;
  v_flag numeric; v_above numeric; v_cid integer;
begin
  v_al := private.capture_find_airline(p_world_id, p_airline);
  if v_al is null then
    return jsonb_build_object('ok', false, 'error', 'not an airline of this capture key''s world: ' || coalesce(p_airline, '(none)'));
  end if;
  select coalesce(a.planner_name, a.public_name, a.game_name, a.game_id::text), a.game_country_id into v_name, v_cid
    from public.airlines a where a.id = v_al;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (p_world_id, v_al, v_name, 'salaries', p_page, coalesce(p_rows, '{}'::jsonb), p_at)
  returning id into v_rid;

  v_doc := case when jsonb_typeof(p_rows) = 'object' then p_rows else '{}'::jsonb end;
  v_ov := case when jsonb_typeof(v_doc -> 'overview') = 'object' then v_doc -> 'overview' else '{}'::jsonb end;
  v_co := case when jsonb_typeof(v_doc -> 'country') = 'object' then v_doc -> 'country' else '{}'::jsonb end;
  v_ov_err := case when nullif(btrim(v_ov ->> 'error'), '') is not null then left(v_ov ->> 'error', 300)
                   when jsonb_typeof(v_ov -> 'rows') <> 'array' or jsonb_array_length(v_ov -> 'rows') = 0 then 'no positions sent' end;
  v_co_err := case when nullif(btrim(v_co ->> 'error'), '') is not null then left(v_co ->> 'error', 300)
                   when jsonb_typeof(v_co -> 'averages') <> 'array' or jsonb_array_length(v_co -> 'averages') = 0 then 'no averages sent' end;
  v_ov_ok := v_ov_err is null; v_co_ok := v_co_err is null;

  insert into public.salary_reads (world_id, airline_id, raw_id, read_at, unattended, version, country_id, country_name, country_code,
                                   overview_ok, country_ok, overview_error, country_error, verdict, note)
  values (p_world_id, v_al, v_rid, p_at, coalesce(p_unattended, false), left(v_doc ->> 'version', 20),
          coalesce(private.salary_int(v_co -> 'id'), v_cid), left(v_co ->> 'name', 80), left(v_co ->> 'code', 8),
          v_ov_ok, v_co_ok, v_ov_err, v_co_err, 'broken', null)
  returning id into v_read;

  if v_ov_ok then
    insert into public.airline_salaries (read_id, n, position, crew_group, employed, active, required, salary, salary_next, overview_avg, raised_to)
    select v_read, (e.o - 1)::smallint, left(btrim(e.r ->> 'position'), 120), left(nullif(btrim(e.r ->> 'group'), ''), 40),
           private.salary_int(e.r -> 'employed'), private.salary_int(e.r -> 'active'), private.salary_int(e.r -> 'required'),
           private.salary_int(e.r -> 'salary'), private.salary_int(e.r -> 'salary_next'), private.salary_int(e.r -> 'avg'),
           private.salary_int(e.r -> 'raised_to')
      from jsonb_array_elements(v_ov -> 'rows') with ordinality as e(r, o)
     where jsonb_typeof(e.r) = 'object' and nullif(btrim(e.r ->> 'position'), '') is not null;
    get diagnostics v_n = row_count;
  end if;
  if v_co_ok then
    insert into public.country_salaries (read_id, n, country_id, position, avg)
    select v_read, (e.o - 1)::smallint, coalesce(private.salary_int(v_co -> 'id'), v_cid), left(btrim(e.r ->> 'position'), 120),
           private.salary_int(e.r -> 'avg')
      from jsonb_array_elements(v_co -> 'averages') with ordinality as e(r, o)
     where jsonb_typeof(e.r) = 'object' and nullif(btrim(e.r ->> 'position'), '') is not null and private.salary_int(e.r -> 'avg') is not null;
  end if;

  -- the positions with staff that have no average on the country page (unmapped, or not on the page)
  if v_ov_ok and v_co_ok then
    select coalesce(array_agg(s.position order by s.n), '{}') into v_missing
      from public.airline_salaries s
     where s.read_id = v_read and coalesce(s.employed, 0) > 0
       and not exists (select 1 from public.country_salaries c
                        where c.read_id = v_read and lower(btrim(c.position)) = lower(private.salary_country_name(p_world_id, s.position)));
  end if;

  -- off target, for the panel: as salary_table() counts it
  select coalesce((select (s.value #>> '{}')::numeric from public.settings s
                    where s.world_id = p_world_id and s.airline_id is null and s.key = 'salary_flag_pct'), 1),
         (select (s.value #>> '{}')::numeric from public.settings s
           where s.world_id = p_world_id and s.airline_id is null and s.key = 'salary_above_average_pct')
    into v_flag, v_above;
  if v_ov_ok and v_co_ok and v_above is not null then
    select count(*) into v_off
      from public.airline_salaries s
      join public.country_salaries c on c.read_id = s.read_id and lower(btrim(c.position)) = lower(private.salary_country_name(p_world_id, s.position))
     where s.read_id = v_read and coalesce(s.employed, 0) > 0 and s.salary_next is not null
       and abs(s.salary_next - round(c.avg * (1 + v_above / 100))) * 100 > v_flag * round(c.avg * (1 + v_above / 100));
  end if;

  v_verdict := case when not v_ov_ok then 'broken' when not v_co_ok or cardinality(v_missing) > 0 then 'short' else 'ok' end;
  v_note := case
    when not v_ov_ok then 'salaries: the Employee overview page didn''t read (' || left(v_ov_err, 160) || ')'
    when not v_co_ok then format('salaries: %s positions stored; the country page didn''t read (%s)', v_n, left(v_co_err, 160))
    when cardinality(v_missing) > 0 then format('salaries: %s positions stored; no country average for %s', v_n, array_to_string(v_missing, ', '))
    when v_above is null then format('salaries: %s positions stored', v_n)
    when v_off = 0 then format('salaries: %s positions stored, all within %s%% of target', v_n, v_flag)
    else format('salaries: %s positions stored, %s off target', v_n, v_off) end;
  update public.salary_reads r set verdict = v_verdict, note = v_note where r.id = v_read;
  update public.game_capture_raw x
     set verdict = v_verdict, verdict_note = v_note,
         verdict_facts = jsonb_build_object('read', v_n, 'off_target', v_off, 'missing', to_jsonb(coalesce(v_missing, '{}')),
                                            'overview_ok', v_ov_ok, 'country_ok', v_co_ok)
   where x.id = v_rid;

  -- an airline's reads are kept 90 days
  delete from public.salary_reads r where r.airline_id = v_al and r.read_at < p_at - interval '90 days';

  return jsonb_build_object('ok', true, 'kind', 'salaries', 'airline', v_name, 'rows', v_n, 'off_target', v_off, 'read_id', v_read,
                            'verdict', jsonb_build_object('kind', 'salaries', 'verdict', v_verdict, 'note', v_note, 'at', private.fig_ts(p_at)),
                            'words', v_note);
end
$function$;

-- ============================================================ 5. capture_ingest() takes it
create or replace function public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
set statement_timeout to '30s'
set plan_cache_mode to 'force_custom_plan'
as $function$
declare v_world bigint; v_res jsonb; v_unattended boolean;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'fleet', 'html', 'salaries') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', 'capture', true);
  -- an airline's salaries page (since 16 Nov, capture 1.18; spec docs/specs/2026-11-16-salary-table.md): stored and judged
  -- apart, never in the airline's verdict, the day's completeness or the snapshot
  if p_kind = 'salaries' then
    v_unattended := private.capture_key_unattended(p_key);
    if v_unattended and not private.capture_unattended_allows(v_world, 'salary_read') then
      return jsonb_build_object('ok', false, 'error', 'the unattended capture doesn''t read salaries (settings.unattended_salary_read)');
    end if;
    return private.capture_salaries(v_world, p_airline, p_page, p_rows, v_unattended, now());
  end if;
  v_res := private.capture_store(v_world, p_airline, p_kind, p_page, p_rows, now());
  -- the capture panel prints rows (or error) after "<airline> · loads ": after the loads page, the airline's verdict goes
  -- there (#21), so the userscript needs no change; the count stays under count
  if p_kind = 'loads' and v_res ? 'airline_verdict' then
    v_res := v_res || jsonb_build_object('count', coalesce(v_res -> 'rows', '0'::jsonb), 'rows', private.capture_panel_words(v_res));
  end if;
  return v_res;
end
$function$;

-- ============================================================ 6. capture_airlines(): the country and whether to read
create or replace function public.capture_airlines(p_key text)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare v_world bigint; v_unattended boolean; v_doc jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1)
  v_unattended := private.capture_key_unattended(p_key);
  v_doc := jsonb_build_object(
    'ok', true,
    'world', (select w.name from public.worlds w where w.id = v_world),
    -- since 16 Nov each airline's country_id: the game's country page the salary table reads (airlines.game_country_id)
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object('game_id', a.game_id, 'name', a.planner_name,
                                                               'game_name', a.game_name, 'code', a.iata_code,
                                                               'country_id', a.game_country_id)
                                           order by a.position nulls last, a.id), '[]'::jsonb)
                   from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where a.world_id = v_world and a.active and g.kind = 'ours'),
    -- salaries (since 5 Nov, manual §7): how far above the country average a salary below it is set; null: left alone
    -- (and null for the unattended key while unattended_salaries is false)
    'salary_above_average_pct', case when v_unattended and not private.capture_unattended_allows(v_world, 'salaries') then null
                                     else (select s.value from public.settings s
                                            where s.world_id = v_world and s.airline_id is null and s.key = 'salary_above_average_pct') end,
    -- whether the capture reads and stores salaries for the salary table (since 16 Nov, spec
    -- docs/specs/2026-11-16-salary-table.md): always for a press; for the unattended key as unattended_salary_read says
    'salary_read', case when v_unattended then private.capture_unattended_allows(v_world, 'salary_read') else true end)
    -- the world scan (spec docs/specs/2026-10-21-scan-in-capture.md): whether one is due, the open one and the airports
    || private.capture_scan_plan(v_world, now())
    -- the market pages (spec docs/specs/2026-10-30-market-pages.md): whether they're due, the open run and the pages
    || private.capture_market_plan(v_world, now());
  if v_unattended then
    -- the scan and the market pages: as for a normal key, unless the world's setting keeps them from the unattended key
    if not private.capture_unattended_allows(v_world, 'scan') then
      v_doc := v_doc || jsonb_build_object('scan_due', false, 'scan_open', null);
    end if;
    if not private.capture_unattended_allows(v_world, 'market') then
      v_doc := v_doc || jsonb_build_object('market_due', false, 'market_open', null, 'market_pages', '[]'::jsonb);
    end if;
    v_doc := v_doc || jsonb_build_object('unattended', true);
  end if;
  return v_doc;
end
$function$;

-- ============================================================ 7. the salary table
create or replace function private.fig_salary_table(p_world_id bigint, p_as_of timestamptz)
returns jsonb
language sql
stable
set search_path to ''
as $function$
  with cfg as (
    select coalesce((select (s.value #>> '{}')::numeric from public.settings s
                      where s.world_id = p_world_id and s.airline_id is null and s.key = 'salary_flag_pct'), 1) as flag_pct,
           (select (s.value #>> '{}')::numeric from public.settings s
             where s.world_id = p_world_id and s.airline_id is null and s.key = 'salary_above_average_pct') as above_pct),
  al as (
    select a.id, a.iata_code as code, coalesce(a.public_name, a.planner_name, a.game_name) as name, a.game_country_id,
           row_number() over (order by a.position nulls last, a.id) as pos
      from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  rd as (
    select distinct on (r.airline_id) r.*
      from public.salary_reads r join al on al.id = r.airline_id
     where r.read_at <= p_as_of
     order by r.airline_id, r.read_at desc, r.id desc),
  rows_ as (
    select s.read_id, s.n, s.position, s.crew_group, s.employed, s.salary, s.salary_next, s.overview_avg, s.raised_to,
           c.avg as country_avg,
           case when c.avg is not null and cfg.above_pct is not null then round(c.avg * (1 + cfg.above_pct / 100))::int end as target,
           cfg.flag_pct
      from rd join public.airline_salaries s on s.read_id = rd.id
      cross join cfg
      left join lateral (select c.avg from public.country_salaries c
                          where c.read_id = rd.id
                            and lower(btrim(c.position)) = lower(private.salary_country_name(p_world_id, s.position))
                          order by c.n limit 1) c on true),
  judged as (
    select x.*,
           case when x.target is not null and x.salary_next is not null then x.salary_next - x.target end as diff,
           case when x.target > 0 and x.salary_next is not null then round((x.salary_next - x.target) * 100.0 / x.target, 2) end as diff_pct,
           case when coalesce(x.employed, 0) = 0 then null
                when x.target is null then 'no_average'
                when x.salary_next is null then null
                when abs(x.salary_next - x.target) * 100 > x.flag_pct * x.target
                  then case when x.salary_next < x.target then 'under' else 'over' end end as flag,
           (x.overview_avg is not null and x.country_avg is not null
            and abs(x.overview_avg - x.country_avg) * 1000 > 5 * x.country_avg) as averages_differ
      from rows_ x)
  select jsonb_build_object(
    'as_of', private.fig_ts(p_as_of),
    'flag_pct', (select flag_pct from cfg),
    'above_pct', (select above_pct from cfg),
    'counts', jsonb_build_object(
       'flagged', (select count(*) from judged j where j.flag in ('under', 'over')),
       'under', (select count(*) from judged j where j.flag = 'under'),
       'over', (select count(*) from judged j where j.flag = 'over'),
       'no_average', (select count(*) from judged j where j.flag = 'no_average'),
       'airlines_flagged', (select count(distinct j.read_id) from judged j where j.flag in ('under', 'over')),
       'not_read', (select count(*) from al where not exists (select 1 from rd where rd.airline_id = al.id))),
    'airlines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'airline_id', al.id, 'code', al.code, 'name', al.name,
               'read_at', private.fig_ts(rd.read_at), 'unattended', rd.unattended, 'verdict', rd.verdict, 'note', rd.note,
               'country', case when rd.id is null then null
                               else jsonb_build_object('id', rd.country_id, 'name', rd.country_name, 'code', rd.country_code, 'ok', rd.country_ok) end,
               'counts', jsonb_build_object(
                  'positions', (select count(*) from judged j where j.read_id = rd.id),
                  'flagged', (select count(*) from judged j where j.read_id = rd.id and j.flag in ('under', 'over')),
                  'under', (select count(*) from judged j where j.read_id = rd.id and j.flag = 'under'),
                  'over', (select count(*) from judged j where j.read_id = rd.id and j.flag = 'over'),
                  'no_average', (select count(*) from judged j where j.read_id = rd.id and j.flag = 'no_average'),
                  'averages_differ', (select count(*) from judged j where j.read_id = rd.id and j.averages_differ)),
               'rows', coalesce((select jsonb_agg(jsonb_build_object(
                          'position', j.position, 'group', j.crew_group, 'employed', j.employed, 'salary', j.salary,
                          'salary_next', j.salary_next, 'overview_avg', j.overview_avg, 'country_avg', j.country_avg,
                          'target', j.target, 'diff', j.diff, 'diff_pct', j.diff_pct, 'flag', j.flag,
                          'averages_differ', j.averages_differ, 'raised_to', j.raised_to) order by j.n)
                                   from judged j where j.read_id = rd.id), '[]'::jsonb))
             order by al.pos)
        from al left join rd on rd.airline_id = al.id), '[]'::jsonb))
$function$;

create or replace function public.salary_table(p_world_id bigint default null, p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable security definer
set search_path to ''
set statement_timeout to '30s'
set plan_cache_mode to 'force_custom_plan'
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_salary_table(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$;

revoke all on function private.salary_country_name(bigint, text), private.salary_int(jsonb),
  private.capture_salaries(bigint, text, text, jsonb, boolean, timestamptz), private.fig_salary_table(bigint, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.salary_table(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.salary_table(bigint, timestamptz) to authenticated;

comment on function private.salary_country_name(bigint, text) is 'The salary table (spec docs/specs/2026-11-16-salary-table.md): the country page''s name for a position on the Employee overview page in a world: its salary_positions row (pilots, by aircraft family), else its own name.';
comment on function private.salary_int(jsonb) is 'The salary table: a whole AS$ figure from what the capture sent, a number or text such as "1,190 AS$"; null when there is none.';
comment on function private.capture_salaries(bigint, text, text, jsonb, boolean, timestamptz) is 'Stores one airline''s salaries page (capture_ingest() kind salaries, since 16 Nov, Capture all airlines 1.18; spec docs/specs/2026-11-16-salary-table.md): the raw page (game_capture_raw, kind salaries), a salary_reads row, each Employee overview position (airline_salaries) and the country page''s averages (country_salaries). Judges it, kept on the raw page and the read: ok; short when the country page didn''t read or a position with staff has no country average (unmapped, or not on the country page); broken when the Employee overview page didn''t read. Never part of the airline''s verdict, the day''s completeness or the snapshot. Deletes the airline''s reads older than 90 days. Answers ok, rows, off_target (positions with staff more than salary_flag_pct off target, as salary_table() counts them), the verdict and the panel''s words.';
comment on function private.fig_salary_table(bigint, timestamptz) is 'The captured figures (#19): builds salary_table()''s document with no check of its own. See salary_table().';
comment on function public.salary_table(bigint, timestamptz) is 'The salary table (manual §7; spec docs/specs/2026-11-16-salary-table.md; since 16 Nov), in a world (the default when null), as of p_as_of (now by default): for each of our active airlines, in their order, its latest salary read by the moment (read_at, unattended, verdict, note, country), and each position on its Employee overview page with its staff, this week''s salary, next week''s salary (salary_next), the page''s own average (overview_avg), the country page''s average (country_avg, through salary_positions for pilots), the target (the country average plus salary_above_average_pct, rounded as the capture rounds), the difference in AS$ and per cent of the target, and flag: under or over when next week''s salary is more than salary_flag_pct off the target, no_average when a position with staff has no country average, null otherwise and for every position with no staff; averages_differ when the two averages are more than 0.5% apart. counts per airline and in all (flagged, under, over, no_average, airlines_flagged, not_read). Stored after every capture (planner_figures, kind salary_table). Staff only, read with GET; runs as owner with its own 30 second limit, as the other figures.';

do $describe$
declare d text;
begin
  d := obj_description('public.capture_ingest(text, text, text, text, jsonb)'::regprocedure, 'pg_proc');
  if position('kind salaries' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_ingest(text, text, text, text, jsonb) is %L', coalesce(d, '')
      || ' Since 16 Nov (Capture all airlines 1.18, spec docs/specs/2026-11-16-salary-table.md) also kind salaries: one airline''s Employee overview positions and its country page''s averages, stored by private.capture_salaries() and judged apart (never in the airline''s verdict, the day''s completeness or the snapshot); refused for the unattended key while settings.unattended_salary_read is false.');
  end if;
  d := obj_description('public.capture_airlines(text)'::regprocedure, 'pg_proc');
  if position('salary_read' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_airlines(text) is %L', coalesce(d, '')
      || ' Since 16 Nov (spec docs/specs/2026-11-16-salary-table.md) each airline''s country_id (airlines.game_country_id), and salary_read: whether the capture reads and stores salaries for the salary table, true for a normal key and settings.unattended_salary_read for the unattended key (which still never sets one).');
  end if;
end
$describe$;
comment on column public.game_capture_raw.kind is 'statement, events, loads, pnl, balance, fleet (since 22 Oct: one fleet page), salaries (since 16 Nov: one airline''s Employee overview and country page, judged apart, never in the airline''s verdict) or html';

-- ============================================================ 8. stored after every capture
-- The job's list gains salary_table, each world's, beside its other figures (otherwise as 20261111020000).
CREATE OR REPLACE FUNCTION private.figures_refresh(p_world bigint DEFAULT NULL::bigint, p_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_fail text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET statement_timeout TO '5min'
AS $function$
declare
  v_at timestamptz := coalesce(p_at, now());
  w bigint; st public.planner_figures_state%rowtype; v_run jsonb; v_src jsonb; v_reason text; v_why text; v_moved text[];
  v_default boolean; v_gen bigint; v_keys text[]; v_failed jsonb; n_all int; n_ok int; n_done int; n_total int;
  f record; v_answer jsonb; t0 timestamptz; t1 timestamptz; v_routes_from text; v_err text; v_note text;
  v_main boolean := false; v_rest bigint[] := '{}'; v_out jsonb := '[]'::jsonb;
begin
  -- one run at a time: a run that finds another still under way skips (pg_cron starts one every minute)
  if not pg_try_advisory_xact_lock(20261111, 223) then
    return jsonb_build_object('skipped', 'another run of the stored figures is under way');
  end if;
  for w in select x.id from public.worlds x
            where (p_world is not null and x.id = p_world)
               or (p_world is null and exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                                 where a.world_id = x.id and a.active and g.kind = 'ours'))
            order by x.id loop
    -- 1. a capture running: nothing (planner_figures_status() says so)
    v_run := private.figures_capture_running(w, v_at);
    if (v_run ->> 'running')::boolean then
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'nothing', 'why', 'a capture is running (' || (v_run ->> 'what') || ')');
      continue;
    end if;

    -- 2. is a new set due? The capture, scan or market stamps moved, or only the planner tables did and the last save is
    --    more than a minute old
    v_src := private.figures_sources(w);
    select * into st from public.planner_figures_state s where s.world_id = w;
    v_reason := null; v_why := 'up to date';
    if st.world_id is null or st.generation = 0 then
      v_reason := 'first set';
    else
      v_moved := array_remove(array[
        case when v_src -> 'capture_at' is distinct from st.sources -> 'capture_at' then 'capture' end,
        case when v_src -> 'scan_id' is distinct from st.sources -> 'scan_id' then 'world scan' end,
        case when v_src -> 'market_id' is distinct from st.sources -> 'market_id' then 'market pages' end], null);
      if cardinality(v_moved) > 0 then
        v_reason := 'new ' || array_to_string(v_moved, ', ');
      elsif v_src -> 'change_id' is distinct from st.sources -> 'change_id' then
        if (v_src ->> 'change_at')::timestamptz <= v_at - interval '1 minute' then
          v_reason := 'planner saves';
        else
          v_why := 'a planner save under a minute old: waiting';
        end if;
      end if;
    end if;
    if v_reason is null then
      v_rest := v_rest || w;
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'nothing', 'why', v_why);
      continue;
    end if;

    -- 3. the whole set at one moment (v_at), each figure on its own; then generation, ready_at and sources together. All in
    --    this one transaction, so the planner never sees half a set
    t0 := clock_timestamp();
    perform pg_advisory_xact_lock(20261111, 224);   -- planner_figures_status() sees a refresh under way by this lock
    begin
      v_gen := coalesce(st.generation, 0) + 1;
      v_default := exists (select 1 from public.worlds x where x.id = w and x.is_default);
      v_keys := '{}'; v_failed := '[]'::jsonb; n_all := 0; n_ok := 0;
      for f in
        select x.kind, x.key, x.airline_id, x.days
          from (-- each world: its figures (salary_table since 16 Nov); cabin_charges() and market_service_checks() take no world (the default world's)
                select k.kind, ''::text as key, null::bigint as airline_id, null::integer as days, 0::bigint as a_pos, k.n as k_pos
                  from unnest(array['airline_cards', 'growth_signals', 'hub_progress', 'route_loads', 'fleet_checks', 'cash_log',
                                    'shared_pairs_status', 'salary_table']) with ordinality as k(kind, n)
                union all
                select k.kind, '', null, null, 0, 10 + k.n
                  from unnest(array['cabin_charges', 'market_service_checks']) with ordinality as k(kind, n)
                 where v_default
                union all
                -- each of our active airlines: its figures, then route and aircraft profit for 1, 3 and 7 days
                select k.kind, a.id::text, a.id, null, a.pos, 100 + k.n
                  from (select al.id, row_number() over (order by al.position nulls last, al.id) as pos
                          from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                         where al.world_id = w and al.active and g.kind = 'ours') a
                 cross join unnest(array['airline_profit', 'cash_forecast', 'fare_changes', 'fare_plan_status', 'fare_ladder',
                                         'fare_results', 'competition']) with ordinality as k(kind, n)
                union all
                select k.kind, a.id::text || ':' || d.d::text, a.id, d.d, a.pos, 200 + k.n * 10 + d.n
                  from (select al.id, row_number() over (order by al.position nulls last, al.id) as pos
                          from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                         where al.world_id = w and al.active and g.kind = 'ours') a
                 cross join unnest(array['route_profit', 'aircraft_profit']) with ordinality as k(kind, n)
                 cross join unnest(array[1, 3, 7]) with ordinality as d(d, n)) x
         order by x.a_pos, x.k_pos
      loop
        n_all := n_all + 1;
        v_keys := v_keys || (f.kind || '|' || f.key);
        begin
          t1 := clock_timestamp();
          if f.kind = p_fail then
            raise exception 'failed on purpose (p_fail, for the checks)';
          end if;
          -- each with the arguments the planner passes (spec §1, "What is stored")
          v_answer := case f.kind
            when 'airline_cards' then public.airline_cards(w, v_at)
            when 'growth_signals' then public.growth_signals(w, v_at)
            when 'hub_progress' then public.hub_progress(w, v_at)
            when 'route_loads' then public.route_loads(w, v_at)
            when 'fleet_checks' then public.fleet_checks(w, v_at)
            when 'cash_log' then public.cash_log(w, v_at)
            when 'shared_pairs_status' then public.shared_pairs_status(w, v_at)
            when 'salary_table' then public.salary_table(w, v_at)
            when 'cabin_charges' then public.cabin_charges(v_at)
            when 'market_service_checks' then public.market_service_checks(null::bigint, v_at)
            when 'airline_profit' then public.airline_profit(f.airline_id, v_at)
            when 'cash_forecast' then public.cash_forecast(f.airline_id, '[]'::jsonb, v_at)
            when 'fare_changes' then public.fare_changes(f.airline_id, v_at)
            when 'fare_plan_status' then public.fare_plan_status(f.airline_id, v_at)
            when 'fare_ladder' then public.fare_ladder(f.airline_id, v_at)
            when 'fare_results' then public.fare_results(f.airline_id, v_at)
            when 'competition' then public.competition(f.airline_id, v_at)
            when 'route_profit' then public.route_profit(f.airline_id, f.days, v_at)
            when 'aircraft_profit' then public.aircraft_profit(f.airline_id, f.days, v_at) end;
          if v_answer is null then
            raise exception '% gave no answer', f.kind;
          end if;
          insert into public.planner_figures as x (world_id, kind, key, answer, as_of, generation, worked_ms)
          values (w, f.kind, f.key, v_answer, v_at, v_gen, round(extract(epoch from clock_timestamp() - t1) * 1000)::int)
          on conflict (world_id, kind, key) do update
            set answer = excluded.answer, as_of = excluded.as_of, generation = excluded.generation, worked_ms = excluded.worked_ms;
          n_ok := n_ok + 1;
        exception when others then
          -- this figure keeps its previous answer; the rest go on
          v_failed := v_failed || jsonb_build_object('kind', f.kind, 'key', f.key, 'error', left(sqlerrm, 300));
        end;
      end loop;

      -- only the latest set is kept: an answer no longer in the list (an airline no longer active) goes
      delete from public.planner_figures x
       where x.world_id = w and x.kind <> 'route_story' and not ((x.kind || '|' || x.key) = any (v_keys));

      -- route pages worked out before this set are redone when a capture, scan or market run caused it (or it is the
      -- first); a save alone never redoes them
      v_routes_from := case when v_reason = 'planner saves' and st.sources ? 'routes_from' then st.sources ->> 'routes_from'
                            else private.fig_ts(v_at) end;
      select count(*), count(*) filter (where x.as_of >= v_routes_from::timestamptz) into n_total, n_done
        from public.routes ro
        left join public.planner_figures x on x.world_id = w and x.kind = 'route_story' and x.key = ro.id::text
       where ro.world_id = w and not ro.removed and exists (select 1 from public.rotations rt where rt.route_id = ro.id);

      v_err := case when jsonb_array_length(v_failed) > 0 then
                 left(format('%s of %s figures failed and kept their previous answer: %s', jsonb_array_length(v_failed), n_all,
                             (select string_agg((e ->> 'kind') || coalesce(' ' || nullif(e ->> 'key', ''), '') || ': ' || (e ->> 'error'), '; ' order by i)
                                from jsonb_array_elements(v_failed) with ordinality as x(e, i))), 2000) end;
      insert into public.planner_figures_state as s (world_id, generation, ready_at, sources, refreshing_since, routes_done, routes_total,
                                                     last_error, last_error_at)
      values (w, v_gen, clock_timestamp(), v_src || jsonb_build_object('as_of', private.fig_ts(v_at), 'routes_from', v_routes_from), t0,
              n_done, n_total, v_err, case when v_err is not null then clock_timestamp() end)
      on conflict (world_id) do update
        set generation = excluded.generation, ready_at = excluded.ready_at, sources = excluded.sources,
            refreshing_since = excluded.refreshing_since, routes_done = excluded.routes_done, routes_total = excluded.routes_total,
            last_error = excluded.last_error, last_error_at = excluded.last_error_at;

      v_note := format('generation %s (%s): %s of %s figures in %s s', v_gen, v_reason, n_ok, n_all,
                       round(extract(epoch from clock_timestamp() - t0)::numeric, 1))
                || case when v_err is not null then '; ' || v_err else '' end;
      perform private.job_run_add('figures', w, t0, case when v_err is null then 'ok' else 'failed' end, left(v_note, 2000),
                                  jsonb_build_object('reason', v_reason, 'as_of', private.fig_ts(v_at), 'generation', v_gen,
                                                     'figures', n_all, 'worked', n_ok, 'failed', v_failed,
                                                     'worked_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int));
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'set', 'reason', v_reason, 'generation', v_gen, 'figures', n_all,
                                           'worked', n_ok, 'failed', v_failed,
                                           'worked_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int);
    exception when others or query_canceled then
      -- the refresh failed as a whole: nothing of it is stored, the sources stay, and the next minute's run tries again
      v_err := left('the refresh failed: ' || sqlerrm, 2000);
      insert into public.planner_figures_state as s (world_id, last_error, last_error_at)
      values (w, v_err, clock_timestamp())
      on conflict (world_id) do update set last_error = excluded.last_error, last_error_at = excluded.last_error_at;
      perform private.job_run_add('figures', w, t0, 'failed', v_err,
                                  jsonb_build_object('reason', v_reason, 'as_of', private.fig_ts(v_at),
                                                     'worked_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int));
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'failed', 'reason', v_reason, 'error', v_err);
    end;
    v_main := true;
  end loop;

  -- 4. the route pages, never in a run that stored a set: that set is visible as soon as this run ends
  if not v_main then
    foreach w in array v_rest loop
      v_out := v_out || (private.figures_routes(w, v_at) -> 'worlds');
    end loop;
  end if;
  return jsonb_build_object('as_of', private.fig_ts(v_at), 'worlds', v_out);
end
$function$;

do $describe$
declare d text;
begin
  d := obj_description('public.planner_figures'::regclass, 'pg_class');
  if position('salary_table' in coalesce(d, '')) = 0 then
    execute format('comment on table public.planner_figures is %L', coalesce(d, '')
      || ' Since 16 Nov (spec docs/specs/2026-11-16-salary-table.md) also each world''s salary_table.');
  end if;
end
$describe$;
