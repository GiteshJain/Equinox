-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and compared
-- afterwards by database/tests/website_scripts_outputs_test.sql (#13 build, pull request 8; the clean-up, #18 build pull
-- request 14): what the website and the investor page get must be what they got before. Saves site_public(),
-- site_investor() and site_report() with a throwaway investor password. The password and report_access's row are made
-- for this and removed again (report_access is never in the backup); nothing is printed.
create table rehearsal_before.site_outputs (name text primary key, value jsonb);

do $$
declare pw text := 'rehearsal-' || gen_random_uuid(); r bigint;
begin
  create temporary table t_access on commit drop as select * from public.report_access;
  delete from public.report_access;
  insert into public.report_access (pass_hash) values (extensions.crypt(pw, extensions.gen_salt('bf')));
  select min(x.id) into r from public.site_reports x where x.status = 'published' and x.kind <> 'newsletter';
  insert into rehearsal_before.site_outputs (name, value) values
    ('password', to_jsonb(pw)),
    ('report id', to_jsonb(r)),
    ('site_public', public.site_public()),
    ('site_investor', public.site_investor(pw)),
    ('site_report', public.site_report(r, pw));
  delete from public.report_access;
  insert into public.report_access select * from t_access;
end
$$;
