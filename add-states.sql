-- Where I've Been: States
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
-- Safe for the live site: it only ADDS a table and a column. Existing data, the country
-- leaderboards, rankings and the admin console keep counting countries only.
--
-- Adds:
--   state_visits            one row per person per US state or territory (codes like US-CA, US-PR)
--   profiles.default_view   which map the app opens on: 'countries' (default) or 'states'

-- 1. State visits -------------------------------------------------------------
create table if not exists public.state_visits (
  user_id     uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  state_code  text        not null check (state_code ~ '^US-[A-Z]{2}$'),
  visited     boolean     not null default false,
  trips       jsonb       not null default '[]'::jsonb check (jsonb_typeof(trips) = 'array'),
  notes       text        not null default '' check (char_length(notes) <= 5000),
  first_year  smallint    check (first_year is null or first_year between 1900 and 2100),
  updated_at  timestamptz not null default now(),
  primary key (user_id, state_code)
);

-- Each person can only read and change their own rows.
alter table public.state_visits enable row level security;

drop policy if exists "Read own state visits"   on public.state_visits;
drop policy if exists "Add own state visits"    on public.state_visits;
drop policy if exists "Change own state visits" on public.state_visits;
drop policy if exists "Remove own state visits" on public.state_visits;

create policy "Read own state visits"   on public.state_visits for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Add own state visits"    on public.state_visits for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Change own state visits" on public.state_visits for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Remove own state visits" on public.state_visits for delete to authenticated
  using ((select auth.uid()) = user_id);

-- 2. Default view -------------------------------------------------------------
alter table public.profiles
  add column if not exists default_view text not null default 'countries'
  check (default_view in ('countries', 'states'));

-- 3. Account deletion also removes state visits -------------------------------
-- (They're removed automatically when the login is deleted; this keeps the function explicit.)
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
  delete from public.visits       where user_id = auth.uid();
  delete from public.state_visits where user_id = auth.uid();
  delete from public.profiles     where user_id = auth.uid();
  delete from auth.users          where id      = auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
