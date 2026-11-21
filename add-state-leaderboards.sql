-- Where I've Been: state leaderboards and state rank
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
-- Run add-states.sql first. Safe for the live site: country leaderboards are unchanged.
--
-- Adds:
--   state_regions        which Census region each state is in
--   state_leaderboard()  ranked community members by states visited (screen name, home, counts only)
--   my_state_stats()     your state rank and percentile among everyone (totals only)

-- 1. State → region -------------------------------------------------------------
create table if not exists public.state_regions (
  code   text primary key,
  region text not null
);
alter table public.state_regions enable row level security;
drop policy if exists "Anyone signed in can read" on public.state_regions;
create policy "Anyone signed in can read" on public.state_regions for select to authenticated using (true);

insert into public.state_regions (code, region) values
  ('US-IL','Midwest'),
  ('US-IN','Midwest'),
  ('US-MI','Midwest'),
  ('US-OH','Midwest'),
  ('US-WI','Midwest'),
  ('US-IA','Midwest'),
  ('US-KS','Midwest'),
  ('US-MN','Midwest'),
  ('US-MO','Midwest'),
  ('US-NE','Midwest'),
  ('US-ND','Midwest'),
  ('US-SD','Midwest'),
  ('US-CT','Northeast'),
  ('US-ME','Northeast'),
  ('US-MA','Northeast'),
  ('US-NH','Northeast'),
  ('US-RI','Northeast'),
  ('US-VT','Northeast'),
  ('US-NJ','Northeast'),
  ('US-NY','Northeast'),
  ('US-PA','Northeast'),
  ('US-DE','South'),
  ('US-FL','South'),
  ('US-GA','South'),
  ('US-MD','South'),
  ('US-NC','South'),
  ('US-SC','South'),
  ('US-VA','South'),
  ('US-WV','South'),
  ('US-AL','South'),
  ('US-KY','South'),
  ('US-MS','South'),
  ('US-TN','South'),
  ('US-AR','South'),
  ('US-LA','South'),
  ('US-OK','South'),
  ('US-TX','South'),
  ('US-AZ','West'),
  ('US-CO','West'),
  ('US-ID','West'),
  ('US-MT','West'),
  ('US-NV','West'),
  ('US-NM','West'),
  ('US-UT','West'),
  ('US-WY','West'),
  ('US-AK','West'),
  ('US-CA','West'),
  ('US-HI','West'),
  ('US-OR','West'),
  ('US-WA','West')
on conflict (code) do update set region = excluded.region;

-- 2. State leaderboard ----------------------------------------------------------
-- board: 'all' (most states), 'year' (most states visited this calendar year),
--        'region' (filter_value = region name), 'home' (filter_value = country code),
--        'state' (filter_value = 'US|California')
create or replace function public.state_leaderboard(board text default 'all', filter_value text default null, max_rows int default 50)
returns table (rank bigint, screen_name text, home text, score bigint, countries bigint, continents bigint, is_me boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with yr as (select to_char(now(), 'YYYY') as y),
  v as (
    select sv.user_id, sr.region,
           (sv.first_year::text = (select y from yr)
            or exists (
              select 1 from jsonb_array_elements(case when jsonb_typeof(sv.trips) = 'array' then sv.trips else '[]'::jsonb end) t
              where coalesce(t ->> 'from', '') like (select y from yr) || '%'
                 or coalesce(t ->> 'to', '')   like (select y from yr) || '%'
            )) as this_year
    from public.state_visits sv
    join public.state_regions sr on sr.code = sv.state_code   -- only the 50 states count
    where sv.visited
  ),
  agg as (
    select user_id,
           count(*) as states,
           count(distinct region) as regions,
           count(*) filter (where this_year) as year_count,
           count(*) filter (where region = filter_value) as region_count
    from v group by user_id
  ),
  scored as (
    select p.user_id,
           coalesce(nullif(trim(p.screen_name), ''), 'Traveler') as screen_name,
           concat_ws(', ', nullif(trim(p.home_state), ''), nullif(p.home_country_name, '')) as home,
           a.states, a.regions,
           case board when 'year' then a.year_count when 'region' then a.region_count else a.states end as score
    from agg a
    join public.profiles p on p.user_id = a.user_id
    where p.is_public
      and (board <> 'home'  or p.home_country = filter_value)
      and (board <> 'state' or (p.home_country = split_part(filter_value, '|', 1)
                                and lower(trim(p.home_state)) = lower(trim(split_part(filter_value, '|', 2)))))
  )
  select rank() over (order by s.score desc, s.states desc) as rank,
         s.screen_name, s.home, s.score, s.states, s.regions,
         s.user_id = auth.uid() as is_me
  from scored s
  where s.score > 0 and auth.uid() is not null
  order by 1, 2
  limit least(greatest(coalesce(max_rows, 50), 1), 100);
$$;
revoke all on function public.state_leaderboard(text, text, int) from public, anon;
grant execute on function public.state_leaderboard(text, text, int) to authenticated;

-- 3. Your state rank (totals only) ----------------------------------------------
create or replace function public.my_state_stats()
returns json
language sql
stable
security definer
set search_path = ''
as $$
  with counts as (
    select sv.user_id, count(*) as n
    from public.state_visits sv
    join public.state_regions sr on sr.code = sv.state_code
    where sv.visited
    group by sv.user_id
  ),
  me as (select coalesce((select n from counts where user_id = auth.uid()), 0) as n)
  select json_build_object(
    'travelers',  (select count(*) from counts),
    'my_count',   (select n from me),
    'rank',       case when (select n from me) > 0
                    then (select count(*) from counts where n > (select n from me)) + 1 end,
    'percentile', case when (select n from me) > 0 and (select count(*) from counts) > 1
                    then round(100.0 * (select count(*) from counts where n < (select n from me))
                               / ((select count(*) from counts) - 1)) end,
    'average',    (select coalesce(round(avg(n), 1), 0) from counts),
    'top',        (select coalesce(max(n), 0) from counts)
  )
  where auth.uid() is not null;
$$;
revoke all on function public.my_state_stats() from public, anon;
grant execute on function public.my_state_stats() to authenticated;
