-- Where I've Been: Photos for places
-- Paste into Supabase → SQL Editor → New query, then click Run. Safe to run more than once.
-- Safe for the live site: it only ADDS a storage bucket, a table, a column and functions.
--
-- Adds:
--   storage bucket "photos"   private; JPEGs up to 2 MB (the app shrinks photos before upload)
--   photos                    one row per photo: owner, place code (FR, US-CA, NP-YOSE), file path
--   at most 10 photos per person per place
--   profiles.share_photos     off by default; only counts if the person is in the traveler community
--   community_photos(place)   other travelers' shared photos of a place (screen name only)
--   delete_my_account()       now also removes photo rows

-- 1. Storage bucket -----------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg'];

-- 2. Sharing switch on the profile ---------------------------------------------------
alter table public.profiles add column if not exists share_photos boolean not null default false;

-- 3. Photos table ---------------------------------------------------------------------
create table if not exists public.photos (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  place_code  text        not null check (place_code ~ '^([A-Z]{2}|US-[A-Z]{2}|NP-[A-Z]{4})$'),
  path        text        not null unique,
  caption     text        not null default '' check (char_length(caption) <= 200),
  created_at  timestamptz not null default now(),
  check (split_part(path, '/', 1) = user_id::text)
);
create index if not exists photos_place_idx on public.photos (place_code, created_at);
create index if not exists photos_user_idx  on public.photos (user_id, place_code);

-- Is this person sharing photos? (community member + sharing switch on)
create or replace function public.shares_photos(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.user_id = uid and p.is_public and p.share_photos
      and coalesce(trim(p.screen_name), '') <> ''
  );
$$;
revoke all on function public.shares_photos(uuid) from public, anon;
grant execute on function public.shares_photos(uuid) to authenticated;

alter table public.photos enable row level security;
drop policy if exists "Read own or shared photos" on public.photos;
drop policy if exists "Add own photos"            on public.photos;
drop policy if exists "Change own photos"         on public.photos;
drop policy if exists "Remove own photos"         on public.photos;
create policy "Read own or shared photos" on public.photos for select to authenticated
  using ((select auth.uid()) = user_id or public.shares_photos(user_id));
create policy "Add own photos"    on public.photos for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Change own photos" on public.photos for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Remove own photos" on public.photos for delete to authenticated using ((select auth.uid()) = user_id);

-- 4. At most 10 photos per person per place --------------------------------------------
create or replace function public.photos_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.user_id::text || new.place_code));
  if (select count(*) from public.photos where user_id = new.user_id and place_code = new.place_code) >= 10 then
    raise exception 'You can add up to 10 photos per place';
  end if;
  return new;
end;
$$;
drop trigger if exists photos_limit on public.photos;
create trigger photos_limit before insert on public.photos
  for each row execute function public.photos_limit();

-- 5. Who can read the files ----------------------------------------------------------
-- Files live at photos/<user id>/<place code>/<random>.jpg, plus a small copy <random>_t.jpg for thumbnails
create or replace function public.photo_visible_to_me(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.photos ph
    where ph.path = regexp_replace(object_name, '_t\.jpg$', '.jpg')   -- the small copy (_t.jpg) follows its photo
      and public.shares_photos(ph.user_id)
  );
$$;
revoke all on function public.photo_visible_to_me(text) from public, anon;
grant execute on function public.photo_visible_to_me(text) to authenticated;

drop policy if exists "Photos: upload own"        on storage.objects;
drop policy if exists "Photos: read own or shared" on storage.objects;
drop policy if exists "Photos: delete own"        on storage.objects;
create policy "Photos: upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Photos: read own or shared" on storage.objects for select to authenticated
  using (bucket_id = 'photos' and ((storage.foldername(name))[1] = (select auth.uid())::text
                                   or public.photo_visible_to_me(name)));
create policy "Photos: delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- 6. Other travelers' shared photos of one place (newest first, never your own) ------------
create or replace function public.community_photos(place text, max_rows int default 24)
returns table (path text, caption text, screen_name text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select ph.path, ph.caption, p.screen_name, ph.created_at
  from public.photos ph
  join public.profiles p on p.user_id = ph.user_id
  where ph.place_code = place
    and ph.user_id <> auth.uid()
    and p.is_public and p.share_photos and coalesce(trim(p.screen_name), '') <> ''
  order by ph.created_at desc
  limit least(greatest(coalesce(max_rows, 24), 1), 60);
$$;
revoke all on function public.community_photos(text, int) from public, anon;
grant execute on function public.community_photos(text, int) to authenticated;

-- 7. Deleting an account also removes photo rows ---------------------------------------
-- (The app removes the photo files first; Supabase doesn't allow deleting files from SQL.)
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
