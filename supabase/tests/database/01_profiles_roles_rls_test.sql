begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

-- ============================================================
-- FIXED TEST IDENTITIES
-- ============================================================

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '11111111-1111-1111-1111-111111111111',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'rls-user-a@comicsadvisor.local',
    crypt('TestPassword123!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"RLS User A"}'::jsonb,
    now(),
    now()
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'rls-user-b@comicsadvisor.local',
    crypt('TestPassword123!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"RLS User B"}'::jsonb,
    now(),
    now()
  );

-- The signup trigger must have created both public profiles.

select results_eq(
  $$
    select count(*)
    from public.profiles
    where auth_user_id in (
      '11111111-1111-1111-1111-111111111111'::uuid,
      '22222222-2222-2222-2222-222222222222'::uuid
    )
  $$,
  array[2::bigint],
  'Fixture setup created both application profiles'
);

-- ============================================================
-- AUTHENTICATE AS USER A
-- ============================================================

set local role authenticated;

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '11111111-1111-1111-1111-111111111111',
    'role', 'authenticated'
  )::text,
  true
);

-- User A can read only their own profile.

select results_eq(
  $$
    select count(*)
    from public.profiles
  $$,
  array[1::bigint],
  'User A sees exactly one profile'
);

select results_eq(
  $$
    select display_name
    from public.profiles
  $$,
  array['RLS User A'::text],
  'User A sees their own profile, not User B profile'
);

-- Updating User B must affect no rows.

select results_eq(
  $$
    update public.profiles
    set display_name = 'Unauthorized change'
    where auth_user_id =
      '22222222-2222-2222-2222-222222222222'::uuid
    returning auth_user_id
  $$,
  array[]::uuid[],
  'User A cannot update User B profile'
);

-- User A may assign themselves a normal application role.

select lives_ok(
  $$
    insert into public.user_roles (
      profile_id,
      role,
      verification_status
    )
    select
      id,
      'visitor',
      'self_declared'
    from public.profiles
    where auth_user_id =
      '11111111-1111-1111-1111-111111111111'::uuid
  $$,
  'User A can assign themselves the visitor role'
);

-- User A must not be able to assign themselves an admin role.

select throws_ok(
  $$
    insert into public.user_roles (
      profile_id,
      role,
      verification_status
    )
    select
      id,
      'admin',
      'verified'
    from public.profiles
    where auth_user_id =
      '11111111-1111-1111-1111-111111111111'::uuid
  $$,
  '42501',
  'new row violates row-level security policy for table "user_roles"',
  'User A cannot assign themselves the admin role'
);

-- User A sees only their own role.

select results_eq(
  $$
    select role::text
    from public.user_roles
    order by role
  $$,
  array['visitor'::text],
  'User A sees only their own roles'
);

-- ============================================================
-- SWITCH TO USER B
-- ============================================================

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '22222222-2222-2222-2222-222222222222',
    'role', 'authenticated'
  )::text,
  true
);

select results_eq(
  $$
    select count(*)
    from public.user_roles
  $$,
  array[0::bigint],
  'User B cannot read User A roles'
);

select * from finish();

rollback;