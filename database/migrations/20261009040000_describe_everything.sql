-- Descriptions on every table, view, function and the less obvious columns (decision #10).
-- They show in Supabase's table editor, travel with the backups, and docs/data.md is generated from them.

comment on table public.backup_runs is 'One row per run of the nightly backup (decision #6): when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied. Written by the backup job in equinox-backups. Read by the planner''s Capture board and the backup line on Home.';
comment on table public.capture_keys is 'Hashed keys that let the in-game capture send data. Only hashes are stored. Written by hand when a key is issued. Read by capture_ingest().';
comment on table public.game_balance is 'The balance-sheet page from the nightly capture: one row per airline, account and day. Account 2800 is cash. Written by parse_capture(). Read by the planner (Review: the group today, Cash next 14 days) and export_capture().';
comment on table public.game_capture_raw is 'Every page the capture sent, as rows of cells before parsing. Kept 14 days, while the parsed tables keep everything. Written by capture_ingest(). Read by parse_capture() and the planner''s Capture board (when each airline was last captured).';
comment on table public.game_events is 'Payments the game lists ahead on the events page: leases, the week-end closing (salaries) and deliveries. Written by parse_capture(). Read by the planner''s cash forecast (Review: Cash, next 14 days), which also takes each type''s lease from here.';
comment on table public.game_loads is 'Every captured flight, with passengers, seats and fares by class and cargo. Written by parse_capture() from the loads page. Read by the planner (Check: daily load report, growth signals; Review: fare changes), apply_loads_from_capture() and export_capture().';
comment on table public.game_pnl is 'The game''s income statement per airline and day, for the current, last and total periods. Written by parse_capture(). Not read by any screen yet; kept for reports.';
comment on table public.game_snapshot_airlines is 'World scan: every airline in Gander with its full schedule at the time of a scan. Written by ingest_snapshot(), from scripts/scanner/gscan.py. Read by export_for_report() for the weekly report and gander monthly.';
comment on table public.game_snapshot_airports is 'World scan: every airport''s details, the airlines stationed there and its news at the time of a scan. Written by ingest_snapshot(). Read by export_for_report().';
comment on table public.game_snapshots is 'One row per world scan: when it ran, the week, its status and a note. Written by ingest_snapshot(). Read by export_for_report().';
comment on table public.game_statement is 'Bank-statement lines from the capture: every income and cost, most of them tied to one flight. The source of route profit. Written by parse_capture(). Read by the views game_flight_pnl and game_ops_recent.';
comment on table public.ingest_secret is 'The shared secret that Claude''s scripts send to the export, ingest, script and site-admin functions. To be replaced by proper roles (decision #11).';
comment on table public.planner_data is 'The route research the planner is built on, in one row (key DATA): routes, airport coordinates, UTC offsets and countries. Written by planner_data_set(). Read by the planner when it opens, and by export_planner_data().';
comment on table public.planner_loads is 'Daily loads as the planner keeps them, one JSON document per month. Written by the planner and by apply_loads_from_capture() after each loads capture. Read by the planner and export_for_report().';
comment on table public.planner_meta is 'Settings kept as data. Holds growthRules, the thresholds for the growth signals as set on 5 Oct. Not read by the planner today: its rules are in its code.';
comment on table public.planner_scripts is 'Copies of Claude''s scripts from before the repository existed. The repository is now the source (decision #1). Written by save_script(). Read by export_repo_bootstrap().';
comment on table public.planner_state is 'The whole planner in one JSON row (id main): plan cards, to-dos, aircraft, frequencies, deliveries, the fare plan, interline and reference data. Written by the planner on every change, and by Claude for data-only changes. Read by the planner, site_public(), site_investor() and export_for_report(). To be split into proper tables at decision #13.';
comment on table public.planner_users is 'Email addresses allowed into the planner (staff). Read by is_planner_user() and auto_confirm_planner_user().';
comment on table public.report_access is 'The password hash for the investor page and investor reports. Read by site_investor() and site_report().';
comment on table public.site_content is 'Website content kept as data, one row per key: media (destination photos and airline logos), markets, and mct (minimum connection times, also used by the schedule optimiser). Written by site_admin() and the planner''s Photos screen. Read by site_public() and site_investor().';
comment on table public.site_posts is 'Newsroom posts on the website. Written by site_admin(). Read by site_public().';
comment on table public.site_reports is 'Investor reports and gander monthly issues, each with its status (upcoming or published) and its PDF. Written by site_admin(). Read by site_public() (the list), site_report() (investor PDFs, with the password) and site_newsletter() (published issues).';

comment on view public.game_flight_pnl is 'Each captured flight''s income and costs by type (fuel, handling, on-board services, landing, air traffic control, maintenance) and its profit, built from the bank statement. Read by the planner (Review: route profit, aircraft) and export_capture().';
comment on view public.game_ops_recent is 'Each airline''s last 24 hours of flying from the bank statement: flights, income, costs and block hours. Read by the planner (Review: the group today; the cash forecast''s flight profit) and export_capture().';

comment on column public.game_balance.account is 'Account number and name as the game shows them; 2800 is cash';
comment on column public.game_capture_raw.kind is 'statement, events, loads, pnl, balance or html';
comment on column public.game_capture_raw.rows is 'The page''s table rows, each a list of cell texts';
comment on column public.game_loads.eco is 'Economy load, percent (bus and fst likewise for business and first)';
comment on column public.game_loads.status is 'finished or inflight';
comment on column public.game_statement.side is 'D for a cost, C for income';
comment on column public.game_statement.blk is 'Groups the lines of one flight when several flights post in the same minute';
comment on column public.game_statement.occ is 'Tells apart identical lines posted in the same minute';
comment on column public.game_events.event_time is 'As the game''s events page shows it, at the airline''s home airport';
comment on column public.planner_state.json is 'The planner''s whole state as JSON text';
comment on column public.planner_state.saved_at is 'When it was last saved, in milliseconds since 1970 (UTC); the planner uses it to avoid overwriting newer copies';
comment on column public.planner_loads.month is 'YYYY-MM';
comment on column public.site_reports.pdf_b64 is 'The PDF, base64-encoded';
comment on column public.backup_runs.commit_sha is 'The equinox-backups commit holding that night''s copy';

comment on function public.apply_loads_from_capture(text) is 'Copies the last 3 days of captured loads for one airline into planner_loads. Called by capture_ingest() after each loads page.';
comment on function public.as_num(text) is 'Turns game text such as 1,234.5 AS$ into a number (null when there is none).';
comment on function public.auto_confirm_planner_user() is 'Trigger on sign-up: confirms the email straight away when it is on planner_users.';
comment on function public.capture_ingest(text, text, text, text, jsonb) is 'Entry point for the in-game capture. Checks the capture key, stores the page (raw pages kept 14 days), parses it with parse_capture(), and after a loads page updates planner_loads.';
comment on function public.export_capture(text, integer) is 'Exports recent capture data for Claude''s scripts. Needs the ingest secret.';
comment on function public.export_for_report(text, text, text) is 'Exports world-scan snapshots, airlines, airports and the planner for the weekly report and gander monthly. Needs the ingest secret.';
comment on function public.export_planner_data(text) is 'Exports planner_data for scripts. Needs the ingest secret.';
comment on function public.export_repo_bootstrap(text) is 'Exported the stored scripts when the repository was created (decision #1). Needs the ingest secret.';
comment on function public.ingest_snapshot(text, text, jsonb) is 'Receives the world scanner''s results (start, airlines, airports, finish) into the game_snapshot tables. Needs the ingest secret.';
comment on function public.is_planner_user() is 'True when the signed-in email is on planner_users. Used by the access rules, the planner and the Photos functions.';
comment on function public.parse_capture(bigint) is 'Parses one raw capture page into game_statement, game_events, game_loads, game_pnl or game_balance, depending on its kind.';
comment on function public.planner_data_set(text, text, jsonb) is 'Replaces one planner_data entry. Needs the ingest secret.';
comment on function public.save_script(text, text, text) is 'Stores a copy of a script in planner_scripts, from before the repository existed. Needs the ingest secret.';
comment on function public.site_admin(text, text, jsonb) is 'Publishes website content: newsroom posts, reports and site content. Needs the ingest secret.';
comment on function public.site_investor(text) is 'The investor page''s data, when the password matches report_access.';
comment on function public.site_newsletter(bigint) is 'A published gander monthly issue, with its PDF.';
comment on function public.site_public() is 'Everything the public website shows (hubs, schedules, posts, the reports list, photos and logos), built from planner_state, site_content, site_posts and site_reports.';
comment on function public.site_remove_airline_logo(text) is 'The planner''s Photos screen: goes back to the in-game logo for an airline. Staff only.';
comment on function public.site_remove_airport_photo(text) is 'The planner''s Photos screen: removes a destination photo. Staff only.';
comment on function public.site_report(bigint, text) is 'One investor report with its PDF, when the password matches report_access.';
comment on function public.site_set_airline_logo(text, text, text) is 'The planner''s Photos screen: sets an airline''s logo after the upload. Staff only.';
comment on function public.site_set_airport_photo(text, text, text, text) is 'The planner''s Photos screen: sets a destination photo and its credit after the upload. Staff only.';
comment on function public.touch_updated_at() is 'Trigger: sets updated_at on every update to planner_state and planner_loads.';
