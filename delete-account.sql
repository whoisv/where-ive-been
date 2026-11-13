-- Where I've Been: let users delete their own account
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
--
-- delete_my_account() removes the signed-in user's login. Their rows in visits and
-- profiles are removed with it automatically (on delete cascade). It can only ever
-- delete the account of the person calling it.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  delete from public.visits   where user_id = auth.uid();
  delete from public.profiles where user_id = auth.uid();
  delete from auth.users      where id      = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
