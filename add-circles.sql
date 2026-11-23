-- Where I've Been: Circles
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
-- Run add-photos.sql first. Safe for the live site: it only ADDS tables and functions.
--
-- A circle is a private, invite-only group (family, friends, a travel club).
-- Everyone also has "Personal", which is just you; it needs nothing in the database.
--   circles, circle_members      who is in which circle, and who is an admin
--   Members see each other's screen name, home and counts, and who has been to a place.
--   Never email, trips or notes. Photos only if the member turns on sharing for that circle.
--   Limits: 10 circles per person, 50 members per circle.
-- The app reaches these tables only through the functions below.

create extension if not exists pgcrypto with schema extensions;

-- 1. Tables ---------------------------------------------------------------------------
create table if not exists public.circles (
  id          uuid        primary key default gen_random_uuid(),
  name        text        not null check (char_length(trim(name)) between 1 and 60),
  invite_code text        not null unique,
  created_by  uuid        references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);
create table if not exists public.circle_members (
  circle_id    uuid        not null references public.circles (id) on delete cascade,
  user_id      uuid        not null references auth.users (id) on delete cascade,
  role         text        not null default 'member' check (role in ('admin', 'member')),
  share_photos boolean     not null default true,
  joined_at    timestamptz not null default now(),
  primary key (circle_id, user_id)
);
create index if not exists circle_members_user_idx on public.circle_members (user_id);
alter table public.circles        enable row level security;   -- no policies: functions only
alter table public.circle_members enable row level security;

create or replace function public._circle_code()
returns text language sql volatile set search_path = '' as $$
  select translate(encode(extensions.gen_random_bytes(9), 'base64'), '+/=', '-_');
$$;
revoke all on function public._circle_code() from public, anon, authenticated;

create or replace function public._circle_role(c uuid)
returns text language sql stable security definer set search_path = '' as $$
  select role from public.circle_members where circle_id = c and user_id = auth.uid();
$$;
revoke all on function public._circle_role(uuid) from public, anon, authenticated;

-- Leaving: keeps at least one admin (the longest-standing member takes over); an empty circle is deleted.
create or replace function public._leave_circle(c uuid, u uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.circle_members where circle_id = c and user_id = u;
  if not exists (select 1 from public.circle_members where circle_id = c) then
    delete from public.circles where id = c;
  elsif not exists (select 1 from public.circle_members where circle_id = c and role = 'admin') then
    update public.circle_members set role = 'admin'
    where circle_id = c and user_id = (select user_id from public.circle_members where circle_id = c order by joined_at limit 1);
  end if;
end;
$$;
revoke all on function public._leave_circle(uuid, uuid) from public, anon, authenticated;

-- 2. Create, list, join -------------------------------------------------------------------
create or replace function public.create_circle(circle_name text)
returns json language plpgsql security definer set search_path = '' as $$
declare cid uuid; code text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if char_length(trim(coalesce(circle_name, ''))) not between 1 and 60 then raise exception 'Give the circle a name (up to 60 characters)'; end if;
  if (select count(*) from public.circle_members where user_id = auth.uid()) >= 10 then raise exception 'You can be in up to 10 circles'; end if;
  code := public._circle_code();
  insert into public.circles (name, invite_code, created_by) values (trim(circle_name), code, auth.uid()) returning id into cid;
  insert into public.circle_members (circle_id, user_id, role) values (cid, auth.uid(), 'admin');
  return json_build_object('id', cid, 'name', trim(circle_name), 'invite_code', code);
end;
$$;

create or replace function public.my_circles()
returns table (id uuid, name text, role text, members bigint, share_photos boolean, invite_code text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name, m.role,
         (select count(*) from public.circle_members x where x.circle_id = c.id),
         m.share_photos,
         case when m.role = 'admin' then c.invite_code end,
         c.created_at
  from public.circle_members m join public.circles c on c.id = m.circle_id
  where m.user_id = auth.uid()
  order by c.name;
$$;

create or replace function public.circle_preview(code text)
returns table (id uuid, name text, members bigint, already boolean)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name,
         (select count(*) from public.circle_members x where x.circle_id = c.id),
         exists (select 1 from public.circle_members x where x.circle_id = c.id and x.user_id = auth.uid())
  from public.circles c
  where c.invite_code = code and auth.uid() is not null;
$$;

create or replace function public.join_circle(code text, share boolean default true)
returns json language plpgsql security definer set search_path = '' as $$
declare c public.circles;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into c from public.circles where invite_code = code;
  if c.id is null then raise exception 'That invite link is no longer valid. Ask the circle''s admin for a new one.'; end if;
  if exists (select 1 from public.circle_members where circle_id = c.id and user_id = auth.uid()) then
    return json_build_object('id', c.id, 'name', c.name, 'already', true);
  end if;
  if (select count(*) from public.circle_members where user_id = auth.uid()) >= 10 then raise exception 'You can be in up to 10 circles'; end if;
  perform pg_advisory_xact_lock(hashtext(c.id::text));
  if (select count(*) from public.circle_members where circle_id = c.id) >= 50 then raise exception 'This circle is full (50 members)'; end if;
  insert into public.circle_members (circle_id, user_id, role, share_photos) values (c.id, auth.uid(), 'member', coalesce(share, true));
  return json_build_object('id', c.id, 'name', c.name, 'already', false);
end;
$$;

-- 3. Members and leaderboards (kind: countries, states or parks) -----------------------------
create or replace function public.circle_board(circle uuid, kind text default 'countries')
returns table (rank bigint, screen_name text, home text, score bigint, countries bigint, continents bigint,
               is_me boolean, member_id uuid, role text)
language sql stable security definer set search_path = '' as $$
  with m as (
    select cm.user_id, cm.role, cm.joined_at from public.circle_members cm
    where cm.circle_id = circle
      and exists (select 1 from public.circle_members me where me.circle_id = circle and me.user_id = auth.uid())
  ),
  s as (
    select m.user_id, m.role, m.joined_at,
      case kind
        when 'states' then (select count(*) from public.state_visits v join public.state_regions r on r.code = v.state_code where v.user_id = m.user_id and v.visited)
        when 'parks'  then (select count(*) from public.park_visits  v join public.park_regions  r on r.code = v.park_code  where v.user_id = m.user_id and v.visited)
        else (select count(*) from public.visits v where v.user_id = m.user_id and v.visited)
      end as score,
      case kind
        when 'states' then (select count(distinct r.region) from public.state_visits v join public.state_regions r on r.code = v.state_code where v.user_id = m.user_id and v.visited)
        when 'parks'  then (select count(distinct r.region) from public.park_visits  v join public.park_regions  r on r.code = v.park_code  where v.user_id = m.user_id and v.visited)
        else (select count(distinct cc.continent) from public.visits v join public.country_continents cc on cc.code = v.country_code where v.user_id = m.user_id and v.visited)
      end as groups
    from m
  )
  select rank() over (order by s.score desc),
         coalesce(nullif(trim(p.screen_name), ''), 'Traveler'),
         concat_ws(', ', nullif(trim(p.home_state), ''), nullif(p.home_country_name, '')),
         s.score, s.score, s.groups,
         s.user_id = auth.uid(), s.user_id, s.role
  from s left join public.profiles p on p.user_id = s.user_id
  order by 1, 2;
$$;

-- Everywhere the circle has been together
create or replace function public.circle_together(circle uuid)
returns json language sql stable security definer set search_path = '' as $$
  with m as (
    select user_id from public.circle_members
    where circle_id = circle
      and exists (select 1 from public.circle_members me where me.circle_id = circle and me.user_id = auth.uid())
  )
  select json_build_object(
    'countries', (select count(distinct v.country_code) from public.visits v join m using (user_id) where v.visited),
    'states',    (select count(distinct v.state_code) from public.state_visits v join m using (user_id) join public.state_regions r on r.code = v.state_code where v.visited),
    'parks',     (select count(distinct v.park_code) from public.park_visits v join m using (user_id) join public.park_regions r on r.code = v.park_code where v.visited));
$$;

-- Who in your circles has been to this place (country, US-XX state or NP-XXXX park)
create or replace function public.circle_place_visitors(place text)
returns table (screen_name text, first_year smallint)
language sql stable security definer set search_path = '' as $$
  with mates as (
    select distinct o.user_id from public.circle_members me
    join public.circle_members o on o.circle_id = me.circle_id
    where me.user_id = auth.uid() and o.user_id <> auth.uid()
  ),
  hits as (
    select v.user_id, v.first_year from public.visits v join mates using (user_id)
      where place ~ '^[A-Z]{2}$' and v.country_code = place and v.visited
    union all
    select v.user_id, v.first_year from public.state_visits v join mates using (user_id)
      where place like 'US-%' and v.state_code = place and v.visited
    union all
    select v.user_id, v.first_year from public.park_visits v join mates using (user_id)
      where place like 'NP-%' and v.park_code = place and v.visited
  )
  select coalesce(nullif(trim(p.screen_name), ''), 'Traveler'), h.first_year
  from hits h left join public.profiles p on p.user_id = h.user_id
  order by h.first_year nulls last, 1
  limit 50;
$$;

-- 4. Admin actions ---------------------------------------------------------------------------
-- action: 'admin' (make admin), 'member' (remove admin rights) or 'remove' (take out of the circle)
create or replace function public.circle_member_action(circle uuid, member uuid, action text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public._circle_role(circle) is distinct from 'admin' then raise exception 'Only the circle''s admins can do that'; end if;
  if not exists (select 1 from public.circle_members where circle_id = circle and user_id = member) then raise exception 'Not a member'; end if;
  if action in ('admin', 'member') then
    if action = 'member' and (select count(*) from public.circle_members where circle_id = circle and role = 'admin') <= 1
       and (select role from public.circle_members where circle_id = circle and user_id = member) = 'admin' then
      raise exception 'A circle needs at least one admin. Make someone else an admin first.';
    end if;
    update public.circle_members set role = action where circle_id = circle and user_id = member;
  elsif action = 'remove' then
    perform public._leave_circle(circle, member);
  else
    raise exception 'Unknown action';
  end if;
end;
$$;

create or replace function public.rename_circle(circle uuid, circle_name text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public._circle_role(circle) is distinct from 'admin' then raise exception 'Only the circle''s admins can do that'; end if;
  if char_length(trim(coalesce(circle_name, ''))) not between 1 and 60 then raise exception 'Give the circle a name (up to 60 characters)'; end if;
  update public.circles set name = trim(circle_name) where id = circle;
end;
$$;

create or replace function public.reset_circle_invite(circle uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare code text;
begin
  if public._circle_role(circle) is distinct from 'admin' then raise exception 'Only the circle''s admins can do that'; end if;
  code := public._circle_code();
  update public.circles set invite_code = code where id = circle;
  return code;
end;
$$;

create or replace function public.delete_circle(circle uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public._circle_role(circle) is distinct from 'admin' then raise exception 'Only the circle''s admins can do that'; end if;
  delete from public.circles where id = circle;
end;
$$;

create or replace function public.leave_circle(circle uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  perform public._leave_circle(circle, auth.uid());
end;
$$;

create or replace function public.set_circle_photo_share(circle uuid, share boolean)
returns void language sql security definer set search_path = '' as $$
  update public.circle_members set share_photos = coalesce(share, false)
  where circle_id = circle and user_id = auth.uid();
$$;

-- 5. Photos: shared with the community OR with a circle you're both in -------------------------
create or replace function public.photo_shared_with_me(owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.shares_photos(owner) or exists (
    select 1 from public.circle_members o
    join public.circle_members me on me.circle_id = o.circle_id and me.user_id = auth.uid()
    where o.user_id = owner and o.share_photos and owner <> auth.uid());
$$;

create or replace function public.photo_visible_to_me(object_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.photos ph
    where ph.path = regexp_replace(object_name, '_t\.jpg$', '.jpg')
      and public.photo_shared_with_me(ph.user_id));
$$;

drop policy if exists "Read own or shared photos" on public.photos;
create policy "Read own or shared photos" on public.photos for select to authenticated
  using ((select auth.uid()) = user_id or public.photo_shared_with_me(user_id));

-- Other people's photos of a place you may see: your circles first, then the community
create or replace function public.place_photos(place text, max_rows int default 30)
returns table (path text, caption text, screen_name text, created_at timestamptz, via text)
language sql stable security definer set search_path = '' as $$
  with circ as (
    select o.user_id, min(c.name) as circle_name
    from public.circle_members me
    join public.circle_members o on o.circle_id = me.circle_id and o.user_id <> me.user_id and o.share_photos
    join public.circles c on c.id = me.circle_id
    where me.user_id = auth.uid()
    group by o.user_id
  )
  select ph.path, ph.caption, coalesce(nullif(trim(p.screen_name), ''), 'Traveler'), ph.created_at,
         coalesce(circ.circle_name, 'community')
  from public.photos ph
  left join circ on circ.user_id = ph.user_id
  left join public.profiles p on p.user_id = ph.user_id
  where ph.place_code = place
    and ph.user_id <> auth.uid()
    and (circ.user_id is not null
         or (p.is_public and p.share_photos and coalesce(trim(p.screen_name), '') <> ''))
  order by (circ.user_id is null), ph.created_at desc
  limit least(greatest(coalesce(max_rows, 30), 1), 60);
$$;

-- 6. Who may call what ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'create_circle(text)', 'my_circles()', 'circle_preview(text)', 'join_circle(text, boolean)',
    'circle_board(uuid, text)', 'circle_together(uuid)', 'circle_place_visitors(text)',
    'circle_member_action(uuid, uuid, text)', 'rename_circle(uuid, text)', 'reset_circle_invite(uuid)',
    'delete_circle(uuid)', 'leave_circle(uuid)', 'set_circle_photo_share(uuid, boolean)',
    'photo_shared_with_me(uuid)', 'photo_visible_to_me(text)', 'place_photos(text, int)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- 7. Deleting an account hands each circle on to someone else first --------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare c uuid;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  for c in select circle_id from public.circle_members where user_id = auth.uid() loop
    perform public._leave_circle(c, auth.uid());
  end loop;
  delete from public.photos       where user_id = auth.uid();
  delete from public.visits       where user_id = auth.uid();
  delete from public.state_visits where user_id = auth.uid();
  delete from public.park_visits  where user_id = auth.uid();
  delete from public.profiles     where user_id = auth.uid();
  delete from auth.users          where id      = auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
