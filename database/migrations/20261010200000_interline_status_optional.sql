-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1), BEFORE the Building chat applies
-- 20261010210000_adapter_write_side.sql: it removes a rule (status's "not null"), so it isn't applied from a chat. Paste
-- the lines below and press Run; the Building chat then records it and checks it.
--
-- Decision #13, build pull request 5 (spec docs/specs/2026-10-10-adapter-write-side.md; the Building chat's call, 10 Oct).
-- What it removes and why: interline_agreements.status no longer has to hold a value. The old planner keeps an interline
-- record with no status while an airline hasn't contacted anyone yet ("not contacted", with a partner, a date or a note
-- typed). With a status required, the tables stored it as "to sign", the getter gave it back as "requested", and every
-- side-by-side comparison after one would fail. Empty now means "not contacted". The four statuses and their check stay.
-- Nothing is dropped and no row changes. Run it first: the write side's migration stores an empty status, and without
-- this it would stop (or, later, a side-by-side copy would fail) as soon as the planner holds a record with no status.
alter table public.interline_agreements alter column status drop not null;
comment on table public.interline_agreements is 'Interline status per airline and country: not contacted yet, to sign, signed, declined, or no partner there. Replaces the planner''s interline.';
comment on column public.interline_agreements.status is 'to_sign, signed, declined or nopartner; empty = not contacted yet (the planner''s record has no status)';
