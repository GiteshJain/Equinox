create or replace function public.auto_confirm_planner_user() returns trigger
language plpgsql security definer set search_path = public, auth as $$
begin
  if exists (select 1 from public.planner_users u where lower(u.email) = lower(new.email)) then
    new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  end if;
  return new;
end $$;
revoke execute on function public.auto_confirm_planner_user() from public, anon, authenticated;
drop trigger if exists planner_auto_confirm on auth.users;
create trigger planner_auto_confirm before insert or update of email on auth.users
  for each row execute function public.auto_confirm_planner_user();;
