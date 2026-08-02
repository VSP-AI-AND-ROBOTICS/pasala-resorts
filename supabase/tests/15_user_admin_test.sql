-- public.list_profiles() and public.set_user_role(), added in
-- 0019_user_admin.sql to back the admin user-management screen. See that
-- migration's header for why there is no "create user" function here.
--
-- Fixture roles used throughout, all seeded by supabase/seed.sql (loaded on
-- every `db reset`, so present before this transaction even starts):
--   10000000-0000-0000-0000-000000000001  super@pasala.test    super_admin
--   10000000-0000-0000-0000-000000000002  admin@pasala.test    admin
-- This file's own fixtures (a fresh customer to promote, and a second
-- super_admin so "demote one of two" has something to prove) are inserted
-- below with a distinct '91.../92...' id prefix so they can't collide with
-- the seed data or with any other test file's fixtures.

begin;
select plan(20);

select has_function('public','list_profiles','list_profiles() exists');
select has_function('public','set_user_role','set_user_role() exists');

-- A fresh customer, signed up like anyone else -- the only path this app
-- has for a new account to exist at all (see the migration header).
insert into auth.users (id, email, raw_user_meta_data)
values ('91111111-1111-1111-1111-111111111111', 'newstaff@example.com',
        '{"full_name":"New Staff"}'::jsonb);

-- === list_profiles: admin-gated =============================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"91111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$select * from public.list_profiles()$$,
  'P0008', null, 'a customer calling list_profiles gets P0008');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$select * from public.list_profiles()$$,
  'an admin can call list_profiles');

select is(
  (select count(*)::int from public.list_profiles()
    where id = '10000000-0000-0000-0000-000000000001'),
  1,
  'admin sees the super admin row via list_profiles');

select is(
  (select email from public.list_profiles()
    where id = '10000000-0000-0000-0000-000000000001'),
  'super@pasala.test',
  'list_profiles joins the email in from auth.users');

-- === set_user_role: super-admin-only, with the last-super-admin guard =====

-- A plain admin is refused, even for an ordinary promotion.
select throws_ok(
  $$select public.set_user_role(
      '91111111-1111-1111-1111-111111111111','staff')$$,
  'P0008', null, 'a plain admin calling set_user_role gets P0008');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.set_user_role(
      '91111111-1111-1111-1111-111111111111','staff')$$,
  'a super admin can promote a customer to staff');

reset role;

select is(
  (select role from public.profiles
    where id = '91111111-1111-1111-1111-111111111111'),
  'staff'::public.user_role,
  'the promotion is visible directly on profiles');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select role from public.list_profiles()
    where id = '91111111-1111-1111-1111-111111111111'),
  'staff'::public.user_role,
  'the promotion is visible via list_profiles too');

reset role;

select is(
  (select count(*)::int from public.audit_log
    where entity = 'profile'
      and entity_id = '91111111-1111-1111-1111-111111111111'
      and action = 'role:customer->staff'),
  1,
  'the role change wrote an audit_log row with the expected action string');

-- The seeded super@pasala.test is, at this point, the only super_admin in
-- the table -- demoting it (even by itself) must be refused.
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$select public.set_user_role(
      '10000000-0000-0000-0000-000000000001','admin')$$,
  'P0014', null,
  'demoting the only super_admin raises P0014');

reset role;

select is(
  (select role from public.profiles
    where id = '10000000-0000-0000-0000-000000000001'),
  'super_admin'::public.user_role,
  'the sole super_admin''s row is unchanged after the refused demotion');

-- With a second super_admin in play, demoting one of the two succeeds.
insert into auth.users (id, email)
values ('92222222-2222-2222-2222-222222222222', 'secondsuper@example.com');
update public.profiles set role = 'super_admin'
  where id = '92222222-2222-2222-2222-222222222222';

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.set_user_role(
      '92222222-2222-2222-2222-222222222222','admin')$$,
  'with two super_admins, demoting one succeeds');

reset role;

select is(
  (select count(*)::int from public.profiles where role = 'super_admin'),
  1,
  'exactly one super_admin remains after that demotion');

-- Setting a role to its current value is a no-op that succeeds.
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.set_user_role(
      '91111111-1111-1111-1111-111111111111','staff')$$,
  'setting a role to its current value succeeds');

reset role;

select is(
  (select role from public.profiles
    where id = '91111111-1111-1111-1111-111111111111'),
  'staff'::public.user_role,
  'the no-op left the role unchanged');

select is(
  (select count(*)::int from public.audit_log
    where entity = 'profile'
      and entity_id = '91111111-1111-1111-1111-111111111111'
      and action = 'role:staff->staff'),
  0,
  'the no-op wrote no audit_log row');

-- === anon: neither function is even reachable ==============================

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.list_profiles()$$,
  '42501', null, 'anon cannot call list_profiles');

select throws_ok(
  $$select public.set_user_role(
      '91111111-1111-1111-1111-111111111111','staff')$$,
  '42501', null, 'anon cannot call set_user_role');

select * from finish();
rollback;
