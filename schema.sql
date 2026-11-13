-- Where I've Been: database setup
-- Paste this whole file into Supabase → SQL Editor → New query, then click Run.

-- One row per person per country.
create table if not exists public.visits (
  user_id      uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  country_code text        not null check (country_code ~ '^[A-Z0-9_-]{2,6}$'),
  visited      boolean     not null default false,
  trips        jsonb       not null default '[]'::jsonb check (jsonb_typeof(trips) = 'array'),
  notes        text        not null default '' check (char_length(notes) <= 5000),
  updated_at   timestamptz not null default now(),
  primary key (user_id, country_code)
);

-- Row Level Security: the database itself refuses to show or change
-- anyone's rows except your own, no matter what the website sends.
alter table public.visits enable row level security;

drop policy if exists "Read own visits"   on public.visits;
drop policy if exists "Add own visits"    on public.visits;
drop policy if exists "Change own visits" on public.visits;
drop policy if exists "Remove own visits" on public.visits;

create policy "Read own visits"   on public.visits for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Add own visits"    on public.visits for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Change own visits" on public.visits for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Remove own visits" on public.visits for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Handy query for you later (run as admin in the SQL Editor):
-- how many people have signed up and how many countries they've marked.
-- select count(distinct user_id) as travelers, count(*) filter (where visited) as countries_marked from public.visits;

-- Rankings (also available on its own as stats.sql)
create or replace function public.my_travel_stats()
returns json
language sql
stable
security definer
set search_path = ''
as $$
  with counts as (
    select user_id, count(*) as n
    from public.visits
    where visited
    group by user_id
  ),
  me as (
    select coalesce((select n from counts where user_id = auth.uid()), 0) as n
  )
  select json_build_object(
    'travelers', (select count(*) from counts),
    'my_count',  (select n from me),
    'rank',      case when (select n from me) > 0
                   then (select count(*) from counts where n > (select n from me)) + 1
                 end,
    'average',   (select coalesce(round(avg(n), 1), 0) from counts),
    'top',       (select coalesce(max(n), 0) from counts)
  )
  where auth.uid() is not null;
$$;

-- Only signed-in users may call it.
revoke all on function public.my_travel_stats() from public, anon;
grant execute on function public.my_travel_stats() to authenticated;

-- Account deletion (also available on its own as delete-account.sql)
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
