-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1): it removes something, so it isn't
-- applied from a chat. Paste the three lines below and press Run; Claude then records it and checks it.
--
-- Decision #13 (design §5; spec docs/specs/2026-10-09-new-tables.md): today every new table, sequence and function in
-- public is given to anon and authenticated automatically. After this, nothing new is, so a forgotten grant fails
-- closed instead of open. Existing objects keep exactly the access they have; each new one gets its grants in its own
-- migration, as 20261009210000_planner_tables.sql does. Postgres itself still lets everyone (public) run a new
-- function, which is why every migration also revokes new functions from public, as they all do today.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated;
