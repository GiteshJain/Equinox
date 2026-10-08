create extension if not exists pgcrypto with schema extensions;
create table if not exists public.report_access (pass_hash text not null);
alter table public.report_access enable row level security;
delete from public.report_access;
insert into public.report_access(pass_hash) values (extensions.crypt('__INVESTOR_PASSWORD__', extensions.gen_salt('bf')));
drop function if exists public.site_report(bigint);
-- reports are only handed out with the investor password (separate from staff login)
create or replace function public.site_report(p_id bigint, p_password text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare h text;
begin
  select pass_hash into h from public.report_access limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then
    return jsonb_build_object('ok', false, 'error', 'wrong_password');
  end if;
  return (select jsonb_build_object('ok', true, 'title', title, 'pdf', pdf_b64) from public.site_reports where id = p_id and status = 'published');
end $$;
revoke all on function public.site_report(bigint, text) from public;
grant execute on function public.site_report(bigint, text) to anon, authenticated;;
