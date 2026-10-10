-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and compared
-- afterwards by database/tests/website_scripts_test.sql (#13 build, pull request 8): once the website and the scripts
-- read the tables, what they get must be what they got before (site_public() apart from its new airlines key and
-- updated_at; the planner's documents and the investor page's cash with only the differences the side by side allows).
-- Saves site_public(), site_investor() and site_report() with a throwaway investor password, export_for_report('planner'),
-- export_planner_data(), and planner_state's last save. The password, the ingest secret and report_access's row are
-- made for this and removed again (report_access is never in the backup); nothing is printed.
create table rehearsal_before.site_outputs (name text primary key, value jsonb);

do $$
declare s text := 'rehearsal-' || gen_random_uuid(); pw text := 'rehearsal-' || gen_random_uuid(); r bigint;
begin
  insert into public.ingest_secret (secret) values (s);
  create temporary table t_access on commit drop as select * from public.report_access;
  delete from public.report_access;
  insert into public.report_access (pass_hash) values (extensions.crypt(pw, extensions.gen_salt('bf')));
  select min(x.id) into r from public.site_reports x where x.status = 'published' and x.kind <> 'newsletter';
  insert into rehearsal_before.site_outputs (name, value) values
    ('password', to_jsonb(pw)),
    ('report id', to_jsonb(r)),
    ('site_public', public.site_public()),
    ('site_investor', public.site_investor(pw)),
    ('site_report', public.site_report(r, pw)),
    ('export_for_report planner', public.export_for_report(s, 'planner')),
    ('export_planner_data', public.export_planner_data(s)),
    ('planner_state saved_at', (select to_jsonb(p.saved_at) from public.planner_state p where p.id = 'main'));
  delete from public.report_access;
  insert into public.report_access select * from t_access;
  delete from public.ingest_secret where secret = s;
end
$$;
