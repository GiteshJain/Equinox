-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1), AFTER the Building chat has applied
-- 20261011120000_history.sql: it removes a column and takes away access, so it isn't applied from a chat. Paste the
-- lines below and press Run; the Building chat then records it and checks it.
--
-- Decision #13, build pull request 6 (design §3.9, §5). No row changes.
--   1. Signed-in accounts can no longer write the three renamed world-scan tables (game_scans, game_scan_airlines,
--      game_scan_airports). Supabase's old defaults gave them every right; their row rules already refused every write,
--      so nothing that works stops working. They keep reading them, as staff.
--   2. game_scan_airlines.flights goes: each airline's schedule moved to game_scan_schedules (the main migration copied
--      every scan's), and nothing reads or writes the old copy any more.
-- It needs the main migration first (before it, the tables still have their old names and the schedules no other copy).
revoke insert, update, delete, truncate, references, trigger on public.game_scans, public.game_scan_airlines, public.game_scan_airports from authenticated;
alter table public.game_scan_airlines drop column if exists flights;
