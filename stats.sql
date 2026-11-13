-- Where I've Been: traveler rankings
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
--
-- Everyone's rows are private, so the app can't count other people's countries itself.
-- This function runs inside the database and hands back totals only:
-- your rank, how many travelers there are, the average and the top count.
-- It never returns anyone's countries, names or emails.

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
