alter table public.site_reports drop constraint if exists site_reports_kind_check;
alter table public.site_reports add constraint site_reports_kind_check check (kind in ('weekly','monthly','annual','newsletter'));
-- newsletters are public: no password, unlike the investor reports
create or replace function public.site_newsletter(p_id bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'title', title, 'pdf', pdf_b64) from public.site_reports where id = p_id and kind = 'newsletter' and status = 'published';
$$;
revoke all on function public.site_newsletter(bigint) from public;
grant execute on function public.site_newsletter(bigint) to anon, authenticated;;
