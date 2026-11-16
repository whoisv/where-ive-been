-- Where I've Been: "Give access" for the admin console
-- Paste into Supabase → SQL Editor → New query, then click Run. Run admin.sql first. Safe to run more than once.
--
-- Adds two functions only admins can use (anyone else gets "Not authorized"):
--   admin_lookup_email(email)  does this email have an account? confirmed? signed up when?
--   admin_give_access(email)   existing account: confirms it and sets a temporary password.
--                              no account yet:   creates a confirmed account with a temporary password.
--                              Either way returns the temporary password so the admin can send it.
-- The account is flagged must_change_password, so the app asks the person to choose their own
-- password right after they sign in with the temporary one.
--
-- Why not email it automatically? Supabase's built-in email only reaches the project's team.
-- Once a custom email service (SMTP) is set up, sign-up and reset emails will work on their own.

create extension if not exists pgcrypto with schema extensions;

-- Is there an account for this email? ------------------------------------------------
create or replace function public.admin_lookup_email(target_email text)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e text := lower(trim(target_email));
  result json;
begin
  if auth.uid() is null or not exists (select 1 from public.admins where user_id = auth.uid()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  select json_build_object(
           'exists', true,
           'email', au.email,
           'created_at', au.created_at,
           'confirmed', au.email_confirmed_at is not null,
           'last_sign_in_at', au.last_sign_in_at,
           'provider', coalesce(au.raw_app_meta_data ->> 'provider', 'email'),
           'screen_name', coalesce(p.screen_name, ''))
    into result
    from auth.users au
    left join public.profiles p on p.user_id = au.id
   where lower(au.email) = e and au.deleted_at is null
   limit 1;
  return coalesce(result, json_build_object('exists', false, 'email', e));
end;
$$;
revoke all on function public.admin_lookup_email(text) from public, anon;
grant execute on function public.admin_lookup_email(text) to authenticated;

-- Confirm or create the account, with a temporary password ---------------------------------
create or replace function public.admin_give_access(target_email text)
returns json
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  e text := lower(trim(target_email));
  words text[] := array['Atlas','Harbor','Lagoon','Canyon','Summit','Meadow','Island','Glacier','Prairie','Delta',
                        'Compass','Lantern','Voyage','Passport','Ferry','Orbit','Mesa','Fjord','Oasis','Bridge',
                        'Cedar','Coral','Falcon','Comet','Tundra','Harvest','Monsoon','Savanna','Reef','Valley'];
  b bytea := extensions.gen_random_bytes(4);
  pw text;
  uid uuid;
  status text;
begin
  if auth.uid() is null or not exists (select 1 from public.admins where user_id = auth.uid()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'That doesn''t look like an email address' using errcode = '22023';
  end if;

  -- e.g. "Harbor-Comet-4821": easy to read out or type on a phone
  pw := words[1 + get_byte(b, 0) % 30] || '-' || words[1 + get_byte(b, 1) % 30] || '-'
        || lpad(((get_byte(b, 2) * 256 + get_byte(b, 3)) % 10000)::text, 4, '0');

  select id into uid from auth.users where lower(email) = e and deleted_at is null limit 1;

  if uid is not null then
    update auth.users
       set encrypted_password = extensions.crypt(pw, extensions.gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"must_change_password": true}'::jsonb,
           updated_at = now()
     where id = uid;
    status := 'existing';
  else
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', e,
            extensions.crypt(pw, extensions.gen_salt('bf')), now(),
            '{"provider": "email", "providers": ["email"]}'::jsonb, '{"must_change_password": true}'::jsonb,
            now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid::text, uid, json_build_object('sub', uid::text, 'email', e, 'email_verified', true, 'phone_verified', false)::jsonb,
            'email', null, now(), now());
    status := 'created';
  end if;

  return json_build_object('status', status, 'email', e, 'temp_password', pw);
end;
$$;
revoke all on function public.admin_give_access(text) from public, anon;
grant execute on function public.admin_give_access(text) to authenticated;
