-- Where I've Been: invite people to a circle by email
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
-- Run add-circles.sql first. Works together with the "circle-invite" Edge Function (circle-invite.ts),
-- which creates accounts for new people and sends the invitation email through Resend.
--
--   circle_invites           pending invitations, by email address
--   Invited people choose Join or Decline when they sign in; nobody is added without saying yes.
--   Limits: 20 emails at a time, 50 invitations a day per person, the same email once an hour,
--   and members + pending invitations can't go over 50 per circle.

-- 1. Pending invitations ---------------------------------------------------------------
create table if not exists public.circle_invites (
  id          uuid        primary key default gen_random_uuid(),
  circle_id   uuid        not null references public.circles (id) on delete cascade,
  email       text        not null check (email = lower(email)),
  invited_by  uuid        references auth.users (id) on delete set null,
  sent_at     timestamptz not null default now(),
  unique (circle_id, email)
);
create index if not exists circle_invites_email_idx on public.circle_invites (email);
create index if not exists circle_invites_by_idx    on public.circle_invites (invited_by, sent_at);
alter table public.circle_invites enable row level security;   -- no policies: functions only

create or replace function public._my_email()
returns text language sql stable security definer set search_path = '' as $$
  select lower(email) from auth.users where id = auth.uid();
$$;
revoke all on function public._my_email() from public, anon, authenticated;

-- 2. An admin sends invitations: checks each address and records the ones to email ----------
-- Status per email: invite (send it), member (already in the circle), recent (invited in the last hour),
-- invalid, limit (50 a day reached) or full (circle has no room).
create or replace function public.circle_invite_prepare(circle uuid, emails text[])
returns json language plpgsql security definer set search_path = '' as $$
declare
  e text; st text; out jsonb := '[]'::jsonb;
  today int; slots int; had boolean;
  cname text; inviter text;
begin
  if public._circle_role(circle) is distinct from 'admin' then raise exception 'Only the circle''s admins can invite people'; end if;
  if coalesce(array_length(emails, 1), 0) = 0 then raise exception 'Add at least one email address'; end if;
  if array_length(emails, 1) > 20 then raise exception 'You can invite up to 20 people at a time'; end if;
  perform pg_advisory_xact_lock(hashtext(circle::text));
  select count(*) into today from public.circle_invites where invited_by = auth.uid() and sent_at > now() - interval '1 day';
  slots := 50 - (select count(*) from public.circle_members where circle_id = circle)
              - (select count(*) from public.circle_invites where circle_id = circle);
  for e in select distinct lower(trim(x)) from unnest(emails) x where trim(coalesce(x, '')) <> '' loop
    select exists (select 1 from public.circle_invites where circle_id = circle and email = e) into had;
    if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(e) > 254 then st := 'invalid';
    elsif exists (select 1 from public.circle_members m join auth.users u on u.id = m.user_id
                  where m.circle_id = circle and lower(u.email) = e) then st := 'member';
    elsif exists (select 1 from public.circle_invites where circle_id = circle and email = e and sent_at > now() - interval '1 hour') then st := 'recent';
    elsif today >= 50 then st := 'limit';
    elsif not had and slots <= 0 then st := 'full';
    else
      st := 'invite';
      insert into public.circle_invites (circle_id, email, invited_by) values (circle, e, auth.uid())
      on conflict (circle_id, email) do update set invited_by = excluded.invited_by, sent_at = now();
      today := today + 1;
      if not had then slots := slots - 1; end if;
    end if;
    out := out || jsonb_build_object('email', e, 'status', st);
  end loop;
  select name into cname from public.circles where id = circle;
  select coalesce(nullif(trim(screen_name), ''), 'A traveler') into inviter from public.profiles where user_id = auth.uid();
  return json_build_object('circle_name', cname, 'inviter', coalesce(inviter, 'A traveler'), 'results', out);
end;
$$;

-- Pending invitations for a circle (admins only), and cancelling one
create or replace function public.circle_pending_invites(circle uuid)
returns table (id uuid, email text, sent_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select i.id, i.email, i.sent_at from public.circle_invites i
  where i.circle_id = circle and public._circle_role(circle) = 'admin'
  order by i.sent_at desc;
$$;

create or replace function public.cancel_circle_invite(invite uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare c uuid;
begin
  select circle_id into c from public.circle_invites where id = invite;
  if c is null then return; end if;
  if public._circle_role(c) is distinct from 'admin' then raise exception 'Only the circle''s admins can do that'; end if;
  delete from public.circle_invites where id = invite;
end;
$$;

-- 3. The invited person: see invitations, then Join or Decline --------------------------------
create or replace function public.my_invites()
returns table (id uuid, circle_id uuid, circle_name text, invited_by text, members bigint)
language sql stable security definer set search_path = '' as $$
  select i.id, c.id, c.name,
         coalesce(nullif(trim(p.screen_name), ''), 'A traveler'),
         (select count(*) from public.circle_members x where x.circle_id = c.id)
  from public.circle_invites i
  join public.circles c on c.id = i.circle_id
  left join public.profiles p on p.user_id = i.invited_by
  where i.email = public._my_email()
    and not exists (select 1 from public.circle_members m where m.circle_id = c.id and m.user_id = auth.uid())
  order by i.sent_at;
$$;

create or replace function public.respond_invite(invite uuid, accept boolean, share boolean default true)
returns json language plpgsql security definer set search_path = '' as $$
declare i public.circle_invites; cname text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into i from public.circle_invites where id = invite and email = public._my_email();
  if i.id is null then raise exception 'That invitation is no longer open'; end if;
  select name into cname from public.circles where id = i.circle_id;
  if accept and not exists (select 1 from public.circle_members where circle_id = i.circle_id and user_id = auth.uid()) then
    if (select count(*) from public.circle_members where user_id = auth.uid()) >= 10 then raise exception 'You can be in up to 10 circles. Leave one first.'; end if;
    perform pg_advisory_xact_lock(hashtext(i.circle_id::text));
    if (select count(*) from public.circle_members where circle_id = i.circle_id) >= 50 then raise exception 'This circle is full (50 members)'; end if;
    insert into public.circle_members (circle_id, user_id, role, share_photos) values (i.circle_id, auth.uid(), 'member', coalesce(share, true));
  end if;
  delete from public.circle_invites where id = invite;
  return json_build_object('id', i.circle_id, 'name', cname, 'joined', accept);
end;
$$;

-- 4. Who may call what ------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'circle_invite_prepare(uuid, text[])', 'circle_pending_invites(uuid)', 'cancel_circle_invite(uuid)',
    'my_invites()', 'respond_invite(uuid, boolean, boolean)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
