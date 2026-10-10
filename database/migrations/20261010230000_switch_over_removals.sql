-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1), BEFORE the Building chat applies
-- 20261010231000_switch_over.sql: it removes triggers and takes away write access, so it isn't applied from a chat.
-- Paste the lines below and press Run; the Building chat then records it and checks it.
--
-- Decision #13, build pull request 9, the switch-over (design §8 "At the switch-over"). No row changes.
--   1-2. The side by side ends: saves of the old rows are no longer copied into the tables and compared. The two
--        functions behind it stay, so a rollback (private.unfreeze_planner_state()) can put the triggers back.
--   3. Signed-in and signed-out browsers can no longer write the old rows: an old planner tab gets "permission denied"
--      instead of saving into planner_state. The main migration then freezes both rows for everyone else too.
drop trigger if exists adapter_mirror on public.planner_state;
drop trigger if exists adapter_mirror on public.planner_loads;
revoke insert, update, delete, truncate on table public.planner_state, public.planner_loads from anon, authenticated;
