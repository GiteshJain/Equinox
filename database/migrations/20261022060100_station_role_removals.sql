-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1), AFTER the Building chat applies
-- 20261022060000_station_role.sql: it removes a rule, so it isn't applied from a chat. Paste the line below and press
-- Run; the Building chat then records it and checks it.
--
-- Stations (22 Oct 2026; spec docs/specs/2026-10-22-station-role.md): the old role rule on airline_bases allowed hub or
-- focus only, so no station could be saved. The main migration put in its place airline_bases_role_kinds (hub, focus or
-- station) and airline_bases_station_shape (a station has no banks, block or parent and isn't the main hub). Nothing is
-- dropped but the old rule, and no row changes.
alter table public.airline_bases drop constraint airline_bases_role_check;
