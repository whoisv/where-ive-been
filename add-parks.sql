-- Where I've Been: National parks
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
-- Safe for the live site: it only ADDS tables and functions (countries and states are unchanged).
--
-- Adds:
--   park_visits          one row per person per national park (codes like NP-YOSE)
--   park_regions         which region each of the 64 national parks is in
--   park_leaderboard()   ranked community members by parks visited (screen name, home, counts only)
--   my_park_stats()      your park rank and percentile (totals only)
--   'parks' as a choice for profiles.default_view

-- 1. Park visits ----------------------------------------------------------------
create table if not exists public.park_visits (
  user_id     uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  park_code   text        not null check (park_code ~ '^NP-[A-Z]{4}$'),
  visited     boolean     not null default false,
  trips       jsonb       not null default '[]'::jsonb check (jsonb_typeof(trips) = 'array'),
  notes       text        not null default '' check (char_length(notes) <= 5000),
  first_year  smallint    check (first_year is null or first_year between 1900 and 2100),
  updated_at  timestamptz not null default now(),
  primary key (user_id, park_code)
);
alter table public.park_visits enable row level security;
drop policy if exists "Read own park visits"   on public.park_visits;
drop policy if exists "Add own park visits"    on public.park_visits;
drop policy if exists "Change own park visits" on public.park_visits;
drop policy if exists "Remove own park visits" on public.park_visits;
create policy "Read own park visits"   on public.park_visits for select to authenticated using ((select auth.uid()) = user_id);
create policy "Add own park visits"    on public.park_visits for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Change own park visits" on public.park_visits for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Remove own park visits" on public.park_visits for delete to authenticated using ((select auth.uid()) = user_id);

-- 2. Park → region (the 64 parks designated "National Park") ----------------------
create table if not exists public.park_regions (
  code   text primary key,
  region text not null
);
alter table public.park_regions enable row level security;
drop policy if exists "Anyone signed in can read" on public.park_regions;
create policy "Anyone signed in can read" on public.park_regions for select to authenticated using (true);
insert into public.park_regions (code, region) values
  ('NP-ACAD','East'),
  ('NP-NPSA','Territories'),
  ('NP-ARCH','Mountain'),
  ('NP-BADL','Midwest'),
  ('NP-BIBE','South'),
  ('NP-BISC','South'),
  ('NP-BLCA','Mountain'),
  ('NP-BRCA','Mountain'),
  ('NP-CANY','Mountain'),
  ('NP-CARE','Mountain'),
  ('NP-CAVE','Mountain'),
  ('NP-CHIS','Pacific'),
  ('NP-CHIR','Mountain'),
  ('NP-CONG','East'),
  ('NP-CRLA','Pacific'),
  ('NP-CUVA','Midwest'),
  ('NP-DEVA','Pacific'),
  ('NP-DENA','Alaska'),
  ('NP-DRTO','South'),
  ('NP-EVER','South'),
  ('NP-GAAR','Alaska'),
  ('NP-JEFF','Midwest'),
  ('NP-GLAC','Mountain'),
  ('NP-GLBA','Alaska'),
  ('NP-GRCA','Mountain'),
  ('NP-GRTE','Mountain'),
  ('NP-GRBA','Mountain'),
  ('NP-GRSA','Mountain'),
  ('NP-GRSM','East'),
  ('NP-GUMO','South'),
  ('NP-HALE','Pacific'),
  ('NP-HAVO','Pacific'),
  ('NP-HOSP','South'),
  ('NP-INDU','Midwest'),
  ('NP-ISRO','Midwest'),
  ('NP-JOTR','Pacific'),
  ('NP-KATM','Alaska'),
  ('NP-KEFJ','Alaska'),
  ('NP-KICA','Pacific'),
  ('NP-KOVA','Alaska'),
  ('NP-LACL','Alaska'),
  ('NP-LAVO','Pacific'),
  ('NP-MACA','East'),
  ('NP-MEVE','Mountain'),
  ('NP-MORA','Pacific'),
  ('NP-NERI','East'),
  ('NP-NOCA','Pacific'),
  ('NP-OLYM','Pacific'),
  ('NP-PEFO','Mountain'),
  ('NP-PINN','Pacific'),
  ('NP-REDW','Pacific'),
  ('NP-ROMO','Mountain'),
  ('NP-SAGU','Mountain'),
  ('NP-SEQU','Pacific'),
  ('NP-SHEN','East'),
  ('NP-THRO','Midwest'),
  ('NP-VIIS','Territories'),
  ('NP-VOYA','Midwest'),
  ('NP-WHSA','Mountain'),
  ('NP-WICA','Midwest'),
  ('NP-WRST','Alaska'),
  ('NP-YELL','Mountain'),
  ('NP-YOSE','Pacific'),
  ('NP-ZION','Mountain')
on conflict (code) do update set region = excluded.region;

-- 3. Park leaderboard -----------------------------------------------------------
-- board: 'all', 'year', 'region' (filter_value = region name), 'home' (country code), 'state' ('US|California')
create or replace function public.park_leaderboard(board text default 'all', filter_value text default null, max_rows int default 50)
returns table (rank bigint, screen_name text, home text, score bigint, countries bigint, continents bigint, is_me boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with yr as (select to_char(now(), 'YYYY') as y),
  v as (
    select pv.user_id, pr.region,
           (pv.first_year::text = (select y from yr)
            or exists (
              select 1 from jsonb_array_elements(case when jsonb_typeof(pv.trips) = 'array' then pv.trips else '[]'::jsonb end) t
              where coalesce(t ->> 'from', '') like (select y from yr) || '%'
                 or coalesce(t ->> 'to', '')   like (select y from yr) || '%'
            )) as this_year
    from public.park_visits pv
    join public.park_regions pr on pr.code = pv.park_code
    where pv.visited
  ),
  agg as (
    select user_id, count(*) as parks, count(distinct region) as regions,
           count(*) filter (where this_year) as year_count,
           count(*) filter (where region = filter_value) as region_count
    from v group by user_id
  ),
  scored as (
    select p.user_id,
           coalesce(nullif(trim(p.screen_name), ''), 'Traveler') as screen_name,
           concat_ws(', ', nullif(trim(p.home_state), ''), nullif(p.home_country_name, '')) as home,
           a.parks, a.regions,
           case board when 'year' then a.year_count when 'region' then a.region_count else a.parks end as score
    from agg a
    join public.profiles p on p.user_id = a.user_id
    where p.is_public
      and (board <> 'home'  or p.home_country = filter_value)
      and (board <> 'state' or (p.home_country = split_part(filter_value, '|', 1)
                                and lower(trim(p.home_state)) = lower(trim(split_part(filter_value, '|', 2)))))
  )
  select rank() over (order by s.score desc, s.parks desc) as rank,
         s.screen_name, s.home, s.score, s.parks, s.regions, s.user_id = auth.uid() as is_me
  from scored s
  where s.score > 0 and auth.uid() is not null
  order by 1, 2
  limit least(greatest(coalesce(max_rows, 50), 1), 100);
$$;
revoke all on function public.park_leaderboard(text, text, int) from public, anon;
grant execute on function public.park_leaderboard(text, text, int) to authenticated;

-- 4. Your park rank (totals only) -----------------------------------------------
create or replace function public.my_park_stats()
returns json
language sql
stable
security definer
set search_path = ''
as $$
  with counts as (
    select pv.user_id, count(*) as n
    from public.park_visits pv
    join public.park_regions pr on pr.code = pv.park_code
    where pv.visited
    group by pv.user_id
  ),
  me as (select coalesce((select n from counts where user_id = auth.uid()), 0) as n)
  select json_build_object(
    'travelers',  (select count(*) from counts),
    'my_count',   (select n from me),
    'rank',       case when (select n from me) > 0 then (select count(*) from counts where n > (select n from me)) + 1 end,
    'percentile', case when (select n from me) > 0 and (select count(*) from counts) > 1
                    then round(100.0 * (select count(*) from counts where n < (select n from me)) / ((select count(*) from counts) - 1)) end,
    'average',    (select coalesce(round(avg(n), 1), 0) from counts),
    'top',        (select coalesce(max(n), 0) from counts)
  )
  where auth.uid() is not null;
$$;
revoke all on function public.my_park_stats() from public, anon;
grant execute on function public.my_park_stats() to authenticated;

-- 5. "Parks" as a default view ----------------------------------------------------
alter table public.profiles drop constraint if exists profiles_default_view_check;
alter table public.profiles add constraint profiles_default_view_check check (default_view in ('countries', 'states', 'parks'));

-- 6. Account deletion also removes park visits ------------------------------------
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
  delete from public.park_visits  where user_id = auth.uid();
  delete from public.profiles     where user_id = auth.uid();
  delete from auth.users          where id      = auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
