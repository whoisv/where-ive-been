-- Where I've Been: "Year first visited"
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
-- Run this BEFORE shipping v1.15.
--
-- Adds an optional first_year to each saved country, and updates the
-- "Most countries visited this year" leaderboard to count it.

alter table public.visits
  add column if not exists first_year smallint
  check (first_year is null or first_year between 1900 and 2100);

create or replace function public.leaderboard(board text default 'all', filter_value text default null, max_rows int default 50)
returns table (rank bigint, screen_name text, home text, score bigint, countries bigint, continents bigint, is_me boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with yr as (select to_char(now(), 'YYYY') as y),
  v as (
    select vi.user_id, vi.country_code, coalesce(cc.continent, '') as continent,
           (vi.first_year::text = (select y from yr)
            or exists (
             select 1 from jsonb_array_elements(case when jsonb_typeof(vi.trips) = 'array' then vi.trips else '[]'::jsonb end) t
             where coalesce(t ->> 'from', '') like (select y from yr) || '%'
                or coalesce(t ->> 'to', '')   like (select y from yr) || '%'
           )) as this_year
    from public.visits vi
    left join public.country_continents cc on cc.code = vi.country_code
    where vi.visited
  ),
  agg as (
    select user_id,
           count(*) as countries,
           count(distinct nullif(continent, '')) as continents,
           count(*) filter (where this_year) as year_count,
           count(*) filter (where continent = filter_value) as cont_count
    from v group by user_id
  ),
  scored as (
    select p.user_id,
           coalesce(nullif(trim(p.screen_name), ''), 'Traveler') as screen_name,
           concat_ws(', ', nullif(trim(p.home_state), ''), nullif(p.home_country_name, '')) as home,
           a.countries, a.continents,
           case board when 'year' then a.year_count when 'continent' then a.cont_count else a.countries end as score
    from agg a
    join public.profiles p on p.user_id = a.user_id
    where p.is_public
      and (board <> 'home'  or p.home_country = filter_value)
      and (board <> 'state' or (p.home_country = split_part(filter_value, '|', 1)
                                and lower(trim(p.home_state)) = lower(trim(split_part(filter_value, '|', 2)))))
  )
  select rank() over (order by s.score desc, s.countries desc) as rank,
         s.screen_name, s.home, s.score, s.countries, s.continents,
         s.user_id = auth.uid() as is_me
  from scored s
  where s.score > 0 and auth.uid() is not null
  order by 1, 2
  limit least(greatest(coalesce(max_rows, 50), 1), 100);
$$;
revoke all on function public.leaderboard(text, text, int) from public, anon;
grant execute on function public.leaderboard(text, text, int) to authenticated;
