-- Where I've Been: admin console
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
--
-- BEFORE YOU RUN: replace YOUR-EMAIL-HERE (near the bottom, step 4) with the email you sign in with.
-- (It's left as a placeholder so your email never ends up in this public repo.)
--
-- Adds:
--   admins            who may open the admin console (no one can read or change it from the website)
--   is_admin()        true/false for the signed-in user; the app uses it to show the "Admin" link
--   admin_overview()  every number and the user list for admin.html; refuses anyone not in admins
--
-- The admin page itself holds no secrets. All protection is here, inside the database:
-- a non-admin who opens admin.html gets an error back, not data.

-- 1. Admin list --------------------------------------------------------------
create table if not exists public.admins (
  user_id  uuid primary key references auth.users (id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table public.admins enable row level security;
-- No policies on purpose: the website can't read or write this table at all.
revoke all on public.admins from anon, authenticated;

-- 2. Am I an admin? ------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- 3. Everything the console shows ----------------------------------------------
create or replace function public.admin_overview()
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result json;
begin
  if auth.uid() is null or not exists (select 1 from public.admins where user_id = auth.uid()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  with
  u as (
    select au.id, au.email, au.created_at, au.email_confirmed_at, au.last_sign_in_at,
           coalesce(au.raw_app_meta_data ->> 'provider', 'email') as provider
    from auth.users au
    where au.deleted_at is null
  ),
  v as (
    select vi.user_id,
           count(*) filter (where vi.visited) as countries,
           count(distinct cc.continent) filter (where vi.visited) as continents,
           coalesce(sum(case when jsonb_typeof(vi.trips) = 'array' then jsonb_array_length(vi.trips) else 0 end), 0) as trips,
           count(*) filter (where char_length(vi.notes) > 0) as notes,
           max(vi.updated_at) as last_activity
    from public.visits vi
    left join public.country_continents cc on cc.code = vi.country_code
    group by vi.user_id
  ),
  rows as (
    select u.id, u.email, u.created_at, u.email_confirmed_at, u.last_sign_in_at, u.provider,
           coalesce(p.screen_name, '') as screen_name,
           concat_ws(', ', nullif(trim(p.home_state), ''), nullif(p.home_country_name, '')) as home,
           coalesce(p.home_country, '') as home_country,
           coalesce(p.is_public, false) as is_public,
           coalesce(v.countries, 0) as countries,
           coalesce(v.continents, 0) as continents,
           coalesce(v.trips, 0) as trips,
           coalesce(v.notes, 0) as notes,
           v.last_activity,
           exists (select 1 from public.admins a where a.user_id = u.id) as is_admin
    from u
    left join public.profiles p on p.user_id = u.id
    left join v on v.user_id = u.id
  ),
  days as (
    select d::date as day
    from generate_series(
      (select coalesce(min(created_at), now()) from u)::date,
      now()::date, interval '1 day') d
  )
  select json_build_object(
    'generated_at', now(),
    'totals', (select json_build_object(
        'users',            count(*),
        'confirmed',        count(*) filter (where email_confirmed_at is not null),
        'new_7d',           count(*) filter (where created_at > now() - interval '7 days'),
        'new_30d',          count(*) filter (where created_at > now() - interval '30 days'),
        'active_7d',        count(*) filter (where greatest(last_sign_in_at, last_activity) > now() - interval '7 days'),
        'active_30d',       count(*) filter (where greatest(last_sign_in_at, last_activity) > now() - interval '30 days'),
        'with_countries',   count(*) filter (where countries > 0),
        'community',        count(*) filter (where is_public),
        'google',           count(*) filter (where provider = 'google'),
        'countries_marked', coalesce(sum(countries), 0),
        'trips_logged',     coalesce(sum(trips), 0),
        'avg_countries',    coalesce(round(avg(countries) filter (where countries > 0), 1), 0)
      ) from rows),
    'signups_by_day', (select coalesce(json_agg(json_build_object('day', d.day, 'n',
        (select count(*) from u where u.created_at::date = d.day)) order by d.day), '[]'::json) from days d),
    'top_countries', (select coalesce(json_agg(t), '[]'::json) from (
        select country_code as code, count(*) as n
        from public.visits where visited
        group by country_code order by n desc, code limit 15) t),
    'home_countries', (select coalesce(json_agg(t), '[]'::json) from (
        select coalesce(nullif(home_country, ''), '—') as code, count(*) as n
        from rows group by 1 order by n desc, code limit 15) t),
    'users', (select coalesce(json_agg(r order by r.created_at desc), '[]'::json) from rows r)
  ) into result;

  return result;
end;
$$;
revoke all on function public.admin_overview() from public, anon;
grant execute on function public.admin_overview() to authenticated;

-- 4. Make yourself an admin ------------------------------------------------------
-- Replace the placeholder with the email you sign in with, then run.
-- To add someone else later, run this line again with their email.
insert into public.admins (user_id)
select id from auth.users where lower(email) = lower('YOUR-EMAIL-HERE')
on conflict do nothing;

-- Check: this should list your email.
select au.email from public.admins a join auth.users au on au.id = a.user_id;
