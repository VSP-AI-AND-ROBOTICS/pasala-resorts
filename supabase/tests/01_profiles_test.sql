begin;
select plan(21);

select has_table('public','profiles','profiles table exists');
select has_function('public','is_platform_admin','is_platform_admin() exists');

-- signup trigger creates a customer profile
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'a@example.com',
        '{"full_name":"Aa"}'::jsonb);

select is(
  (select role from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'customer'::public.platform_role,
  'signup defaults to customer'
);

select is(
  (select full_name from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'Aa',
  'full_name copied from metadata'
);

-- a customer cannot escalate their own role
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$update public.profiles set role = 'platform_admin'
      where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501',
  null,
  'customer cannot make itself a platform admin'
);

select lives_ok(
  $$update public.profiles set full_name = 'Aa Renamed'
      where id = '11111111-1111-1111-1111-111111111111'$$,
  'customer can still edit own profile fields'
);

-- Role changes on other profiles are not direct table writes: resort roles
-- live in resort_members and are managed through functions, and the
-- platform role has no client write path. Direct updates by a platform
-- admin or a resort owner are RLS-filtered: no error, no row changed.
reset role;

insert into auth.users (id, email)
values ('22222222-2222-2222-2222-222222222222', 'platform@example.com'),
       ('33333333-3333-3333-3333-333333333333', 'owner@example.com'),
       ('44444444-4444-4444-4444-444444444444', 'victim@example.com');

update public.profiles set role = 'platform_admin'
  where id = '22222222-2222-2222-2222-222222222222';

-- 33333333 owns a resort where 44444444 works, so the owner can read the
-- victim's profile (profiles_read_colleague) but still not update it.
insert into public.properties (id, name, slug)
values ('aaaaaaaa-0101-0000-0000-000000000001','Profiles Resort','profiles-resort');
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0101-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','owner'),
  ('aaaaaaaa-0101-0000-0000-000000000001','44444444-4444-4444-4444-444444444444','staff');

-- 0046 retired the global business roles and their helpers.
select hasnt_function('public','current_role','current_role() is gone');
select hasnt_function('public','is_super_admin','is_super_admin() is gone');
select hasnt_type('public','user_role','user_role enum is gone');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select throws_ok(
  $$update public.profiles set role = 'customer'
      where id = '22222222-2222-2222-2222-222222222222'$$,
  '42501',
  null,
  'platform admin cannot change its own role directly either'
);

select lives_ok(
  $$update public.profiles set role = 'platform_admin'
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'platform admin role change on another profile raises no error (RLS-filtered)'
);

set local request.jwt.claims to
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select lives_ok(
  $$update public.profiles set role = 'platform_admin'
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'resort owner role change on a colleague''s profile raises no error (RLS-filtered)'
);

select is(
  (select count(*)::int from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'),
  1,
  'resort owner can read the colleague''s profile it could not update');

set local role postgres;
select is(
  (select role from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'),
  'customer'::public.platform_role,
  'neither platform admin nor resort owner changed another profile''s role directly');

-- Direct profile deletes are RLS-filtered for a platform admin too.
set local role postgres;
insert into auth.users (id, email)
values ('dddddddd-4444-4444-4444-444444444444','del-victim@example.com');

select is(
  (select count(*)::int from public.profiles
    where id in ('11111111-1111-1111-1111-111111111111',
                 '22222222-2222-2222-2222-222222222222',
                 '33333333-3333-3333-3333-333333333333',
                 'dddddddd-4444-4444-4444-444444444444')),
  4,
  '4 fixture profiles exist before delete');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select lives_ok(
  $$delete from public.profiles
      where id = 'dddddddd-4444-4444-4444-444444444444'$$,
  'platform admin delete of a customer profile raises no error (RLS-filtered)');

set local role postgres;
select is(
  (select count(*)::int from public.profiles
    where id = 'dddddddd-4444-4444-4444-444444444444'),
  1,
  'platform admin delete removed no rows -- no direct profile delete policy');

-- A customer's DELETE is filtered by RLS: no error, and no row removed.
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select lives_ok(
  $$delete from public.profiles
      where id = '33333333-3333-3333-3333-333333333333'$$,
  'customer delete raises no error');

set local role postgres;
select is(
  (select count(*)::int from public.profiles
    where id = '33333333-3333-3333-3333-333333333333'),
  1,
  'customer delete removed no rows — RLS filtered it');

-- There is no insert policy on profiles any more: profiles are created by
-- the signup trigger only.
set local role postgres;
insert into auth.users (id, email)
values ('55555555-5555-5555-5555-555555555555','newcust@example.com'),
       ('66666666-6666-6666-6666-666666666666','sneaky@example.com');

-- the signup trigger already made profiles for these; clear them so the
-- INSERT policy is what decides, not a duplicate-key error
delete from public.profiles
 where id in ('55555555-5555-5555-5555-555555555555',
              '66666666-6666-6666-6666-666666666666');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select throws_ok(
  $$insert into public.profiles (id, full_name, role)
    values ('55555555-5555-5555-5555-555555555555','New Customer','customer')$$,
  '42501', null, 'platform admin cannot insert a profile directly');

select throws_ok(
  $$insert into public.profiles (id, full_name, role)
    values ('66666666-6666-6666-6666-666666666666','Sneaky','platform_admin')$$,
  '42501', null, 'platform admin cannot insert a platform_admin profile');

select * from finish();
rollback;
