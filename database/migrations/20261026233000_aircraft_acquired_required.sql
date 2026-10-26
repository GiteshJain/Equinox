-- An aircraft must say whether it came new or used (26 Oct, Gitesh): aircraft.acquired loses its default ('new'). It
-- decides the replacement age (manual §3: new at 3 years, used at 10), and on 23 Oct VT-ABE (DEL), bought used at
-- auction, was logged without it and so marked new. Now a row added without acquired is refused (the column stays not
-- null), wherever it comes from: the Scheduling chat's SQL, the planner's Add a tail, or Game check's new tail, which
-- both ask for it. Rows already there keep their value.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: acquired required', true);

alter table public.aircraft alter column acquired drop default;

comment on column public.aircraft.acquired is 'How the aircraft came: new (ordered from the factory) or used (bought on the used market). Decides its replacement age (manual §3: settings.replace_new_years, replace_used_years) and the fleet check''s looks-used cross-check. Since 26 Oct it has no default: every new row must say which.';
