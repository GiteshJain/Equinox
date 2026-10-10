-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1): it removes access, so it isn't applied
-- from a chat. Paste the lines below and press Run; the Building chat then records it and checks it.
--
-- Decision #13, build pull request 3 (design §5; spec docs/specs/2026-10-09-capture-data.md). What it removes and why:
--   1. Everything the signed-out role (anon) still holds on tables and views in public: the select (and more) that
--      Supabase's old defaults gave it on the 22 tables from before #13 (game_loads among them, now
--      game_loads_before_13). Row rules already kept anon from reading any row; now it has no grant at all, as the
--      design says. The website, the investor page, the capture and the scripts reach the database only through
--      functions (site_public, site_investor, site_report, site_newsletter, capture_ingest, capture_airlines, export_*,
--      ingest_snapshot, site_admin, planner_data_set), which keep working.
--   2. Writing to the views game_flight_pnl and game_ops_recent: signed-in accounts held every right on them, from the
--      same old defaults (a view that adds up can't be written anyway). They keep reading them, as staff.
--   3. public.parse_capture and public.apply_loads_from_capture: their work moved into the private schema
--      (private.capture_page, private.apply_loads_from_capture), which the data API doesn't expose. Any signed-in
--      account could still call them; after this, nobody but the database itself can. They aren't dropped, so a revert
--      of pull request 3 still works.
-- Nothing is dropped. It works before or after 20261009230000_capture_data.sql.
revoke all on all tables in schema public from anon;
revoke insert, update, delete, truncate, references, trigger on public.game_flight_pnl, public.game_ops_recent from authenticated;
revoke all on function public.parse_capture(bigint) from public, anon, authenticated;
revoke all on function public.apply_loads_from_capture(text) from public, anon, authenticated;
