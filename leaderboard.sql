-- Where I've Been: leaderboards
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
--
-- Adds:
--   profiles            one row per user: screen name, home, and whether they appear on leaderboards (off by default)
--   country_continents  which continent each country is on (for continent boards)
--   leaderboard()       returns ranked, opted-in travelers: screen name, home and counts only, never emails, trips or notes
--   my_travel_stats()   updated to also return your percentile

-- 1. Profiles -------------------------------------------------------------
create table if not exists public.profiles (
  user_id           uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  screen_name       text not null default '' check (char_length(screen_name) <= 30),
  home_country      text not null default '' check (char_length(home_country) <= 6),
  home_country_name text not null default '' check (char_length(home_country_name) <= 80),
  home_state        text not null default '' check (char_length(home_state) <= 60),
  home_continent    text not null default '' check (char_length(home_continent) <= 40),
  is_public         boolean not null default false,
  updated_at        timestamptz not null default now()
);
alter table public.profiles enable row level security;

drop policy if exists "Read own profile"   on public.profiles;
drop policy if exists "Add own profile"    on public.profiles;
drop policy if exists "Change own profile" on public.profiles;
create policy "Read own profile"   on public.profiles for select to authenticated using ((select auth.uid()) = user_id);
create policy "Add own profile"    on public.profiles for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Change own profile" on public.profiles for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- 2. Country → continent ---------------------------------------------------
create table if not exists public.country_continents (
  code      text primary key,
  continent text not null
);
alter table public.country_continents enable row level security;
drop policy if exists "Anyone signed in can read" on public.country_continents;
create policy "Anyone signed in can read" on public.country_continents for select to authenticated using (true);

insert into public.country_continents (code, continent) values
  ('DZ','Africa'),
  ('AO','Africa'),
  ('BJ','Africa'),
  ('BW','Africa'),
  ('BF','Africa'),
  ('BI','Africa'),
  ('CV','Africa'),
  ('CM','Africa'),
  ('CF','Africa'),
  ('TD','Africa'),
  ('KM','Africa'),
  ('CD','Africa'),
  ('CG','Africa'),
  ('CI','Africa'),
  ('DJ','Africa'),
  ('EG','Africa'),
  ('GQ','Africa'),
  ('ER','Africa'),
  ('SZ','Africa'),
  ('ET','Africa'),
  ('GA','Africa'),
  ('GM','Africa'),
  ('GH','Africa'),
  ('GN','Africa'),
  ('GW','Africa'),
  ('KE','Africa'),
  ('LS','Africa'),
  ('LR','Africa'),
  ('LY','Africa'),
  ('MG','Africa'),
  ('MW','Africa'),
  ('ML','Africa'),
  ('MR','Africa'),
  ('MU','Africa'),
  ('YT','Africa'),
  ('MA','Africa'),
  ('MZ','Africa'),
  ('NA','Africa'),
  ('NE','Africa'),
  ('NG','Africa'),
  ('RE','Africa'),
  ('RW','Africa'),
  ('SH','Africa'),
  ('ST','Africa'),
  ('SN','Africa'),
  ('SC','Africa'),
  ('SL','Africa'),
  ('SO','Africa'),
  ('ZA','Africa'),
  ('SS','Africa'),
  ('SD','Africa'),
  ('TZ','Africa'),
  ('TG','Africa'),
  ('TN','Africa'),
  ('UG','Africa'),
  ('EH','Africa'),
  ('ZM','Africa'),
  ('ZW','Africa'),
  ('IO','Africa'),
  ('AF','Asia'),
  ('AM','Asia'),
  ('AZ','Asia'),
  ('BH','Asia'),
  ('BD','Asia'),
  ('BT','Asia'),
  ('BN','Asia'),
  ('KH','Asia'),
  ('CN','Asia'),
  ('CY','Asia'),
  ('GE','Asia'),
  ('HK','Asia'),
  ('IN','Asia'),
  ('ID','Asia'),
  ('IR','Asia'),
  ('IQ','Asia'),
  ('IL','Asia'),
  ('JP','Asia'),
  ('JO','Asia'),
  ('KZ','Asia'),
  ('KW','Asia'),
  ('KG','Asia'),
  ('LA','Asia'),
  ('LB','Asia'),
  ('MO','Asia'),
  ('MY','Asia'),
  ('MV','Asia'),
  ('MN','Asia'),
  ('MM','Asia'),
  ('NP','Asia'),
  ('KP','Asia'),
  ('OM','Asia'),
  ('PK','Asia'),
  ('PH','Asia'),
  ('QA','Asia'),
  ('SA','Asia'),
  ('SG','Asia'),
  ('KR','Asia'),
  ('LK','Asia'),
  ('SY','Asia'),
  ('TW','Asia'),
  ('TJ','Asia'),
  ('TH','Asia'),
  ('TL','Asia'),
  ('TR','Asia'),
  ('TM','Asia'),
  ('AE','Asia'),
  ('UZ','Asia'),
  ('VN','Asia'),
  ('YE','Asia'),
  ('CX','Asia'),
  ('CC','Asia'),
  ('AL','Europe'),
  ('AD','Europe'),
  ('AT','Europe'),
  ('BY','Europe'),
  ('BE','Europe'),
  ('BA','Europe'),
  ('BG','Europe'),
  ('HR','Europe'),
  ('CZ','Europe'),
  ('DK','Europe'),
  ('EE','Europe'),
  ('FO','Europe'),
  ('FI','Europe'),
  ('FR','Europe'),
  ('DE','Europe'),
  ('GI','Europe'),
  ('GR','Europe'),
  ('GG','Europe'),
  ('HU','Europe'),
  ('IS','Europe'),
  ('IE','Europe'),
  ('IM','Europe'),
  ('IT','Europe'),
  ('JE','Europe'),
  ('XK','Europe'),
  ('LV','Europe'),
  ('LI','Europe'),
  ('LT','Europe'),
  ('LU','Europe'),
  ('MT','Europe'),
  ('MD','Europe'),
  ('MC','Europe'),
  ('ME','Europe'),
  ('NL','Europe'),
  ('MK','Europe'),
  ('NO','Europe'),
  ('PL','Europe'),
  ('PT','Europe'),
  ('RO','Europe'),
  ('RU','Europe'),
  ('SM','Europe'),
  ('RS','Europe'),
  ('SK','Europe'),
  ('SI','Europe'),
  ('ES','Europe'),
  ('SJ','Europe'),
  ('SE','Europe'),
  ('CH','Europe'),
  ('UA','Europe'),
  ('GB','Europe'),
  ('VA','Europe'),
  ('AX','Europe'),
  ('AI','North America'),
  ('AG','North America'),
  ('AW','North America'),
  ('BS','North America'),
  ('BB','North America'),
  ('BZ','North America'),
  ('BM','North America'),
  ('BQ','North America'),
  ('VG','North America'),
  ('CA','North America'),
  ('KY','North America'),
  ('CR','North America'),
  ('CU','North America'),
  ('CW','North America'),
  ('DM','North America'),
  ('DO','North America'),
  ('SV','North America'),
  ('GL','North America'),
  ('GD','North America'),
  ('GP','North America'),
  ('GT','North America'),
  ('HT','North America'),
  ('HN','North America'),
  ('JM','North America'),
  ('MQ','North America'),
  ('MX','North America'),
  ('MS','North America'),
  ('NI','North America'),
  ('PA','North America'),
  ('PR','North America'),
  ('BL','North America'),
  ('KN','North America'),
  ('LC','North America'),
  ('MF','North America'),
  ('PM','North America'),
  ('VC','North America'),
  ('SX','North America'),
  ('TT','North America'),
  ('TC','North America'),
  ('US','North America'),
  ('VI','North America'),
  ('UM','North America'),
  ('AR','South America'),
  ('BO','South America'),
  ('BR','South America'),
  ('CL','South America'),
  ('CO','South America'),
  ('EC','South America'),
  ('FK','South America'),
  ('GF','South America'),
  ('GY','South America'),
  ('PY','South America'),
  ('PE','South America'),
  ('SR','South America'),
  ('UY','South America'),
  ('VE','South America'),
  ('GS','South America'),
  ('AS','Oceania'),
  ('AU','Oceania'),
  ('CK','Oceania'),
  ('FJ','Oceania'),
  ('PF','Oceania'),
  ('GU','Oceania'),
  ('KI','Oceania'),
  ('MH','Oceania'),
  ('FM','Oceania'),
  ('NR','Oceania'),
  ('NC','Oceania'),
  ('NZ','Oceania'),
  ('NU','Oceania'),
  ('NF','Oceania'),
  ('MP','Oceania'),
  ('PW','Oceania'),
  ('PG','Oceania'),
  ('PN','Oceania'),
  ('WS','Oceania'),
  ('SB','Oceania'),
  ('TK','Oceania'),
  ('TO','Oceania'),
  ('TV','Oceania'),
  ('VU','Oceania'),
  ('WF','Oceania'),
  ('AQ','Antarctica'),
  ('TF','Antarctica'),
  ('HM','Antarctica'),
  ('BV','Antarctica')
on conflict (code) do update set continent = excluded.continent;

-- 3. Leaderboard -----------------------------------------------------------
-- board: 'all' (most countries), 'year' (most countries visited this calendar year),
--        'continent' (filter_value = continent name), 'home' (filter_value = country code),
--        'state' (filter_value = 'US|California')
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
           exists (
             select 1 from jsonb_array_elements(case when jsonb_typeof(vi.trips) = 'array' then vi.trips else '[]'::jsonb end) t
             where coalesce(t ->> 'from', '') like (select y from yr) || '%'
                or coalesce(t ->> 'to', '')   like (select y from yr) || '%'
           ) as this_year
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

-- 4. Your stats, now with percentile ---------------------------------------
create or replace function public.my_travel_stats()
returns json
language sql
stable
security definer
set search_path = ''
as $$
  with counts as (
    select user_id, count(*) as n from public.visits where visited group by user_id
  ),
  me as (
    select coalesce((select n from counts where user_id = auth.uid()), 0) as n
  )
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
revoke all on function public.my_travel_stats() from public, anon;
grant execute on function public.my_travel_stats() to authenticated;
