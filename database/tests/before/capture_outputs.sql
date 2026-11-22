-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and compared
-- afterwards by database/tests/capture_data_compat_test.sql (#13 build, pull request 3): once the capture data lives in
-- game_flights and game_payments, the three capture views must come out exactly as they did before. (export_capture()
-- was saved here too until to-do 248 removed it; export_for_report('planner') and site_public() are saved by
-- website_scripts_before.sql since #13's pull request 8, which made them read the tables.)
create table rehearsal_before.game_loads as select * from public.game_loads;
create table rehearsal_before.game_flight_pnl as select * from public.game_flight_pnl;
create table rehearsal_before.game_ops_recent as select * from public.game_ops_recent;
