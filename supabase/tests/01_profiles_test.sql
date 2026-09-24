begin;
select plan(21);

select has_table('public','profiles','profiles table exists');
select has_function('public','current_role','current_role() exists');

-- signup trigger creates a customer profile
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'a@example.com',
        '{"full_name":"Aa"}'::jsonb);

select is(
  (select role from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'customer'::public.user_role,
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
  $$update public.profiles set role = 'admin'
      where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501',
  null,
  'customer cannot escalate own role'
);

select throws_ok(
  $$update public.profiles set platform_role = 'platform_admin'
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

-- Role changes on other profiles are no longer direct table writes (the
-- global admin policies were dropped in 0044; resort roles live in
-- resort_members and are managed through functions). Direct updates by an
-- admin or super_admin are RLS-filtered: no error, no row changed.
reset role;

insert into auth.users (id, email)
values ('22222222-2222-2222-2222-222222222222', 'admin@example.com'),
       ('33333333-3333-3333-3333-333333333333', 'super@example.com'),
       ('44444444-4444-4444-4444-444444444444', 'victim@example.com');

update public.profiles set role = 'admin'
  where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set role = 'super_admin'
  where id = '33333333-3333-3333-3333-333333333333';

select has_function('public','is_admin','is_admin() exists');
select has_function('public','is_staff_or_above','is_staff_or_above() exists');
select has_function('public','is_super_admin','is_super_admin() exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select throws_ok(
  $$update public.profiles set role = 'super_admin'
      where id = '22222222-2222-2222-2222-222222222222'$$,
  '42501',
  null,
  'admin cannot promote itself to super_admin'
);

select lives_ok(
  $$update public.profiles set role = 'admin'
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'admin role change on another profile raises no error (RLS-filtered)'
);

set local request.jwt.claims to
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select lives_ok(
  $$update public.profiles set role = 'staff'
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'super_admin role change on another profile raises no error (RLS-filtered)'
);

set local role postgres;
select is(
  (select role from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'),
  'customer'::public.user_role,
  'neither admin nor super_admin changed another profile''s role directly');

-- Direct profile deletes are RLS-filtered for an admin too.
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
  'admin delete of a customer profile raises no error (RLS-filtered)');

set local role postgres;
select is(
  (select count(*)::int from public.profiles
    where id = 'dddddddd-4444-4444-4444-444444444444'),
  1,
  'admin delete removed no rows -- no direct profile delete policy');

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
  '42501', null, 'admin cannot insert a profile directly');

select throws_ok(
  $$insert into public.profiles (id, full_name, role)
    values ('66666666-6666-6666-6666-666666666666','Sneaky','super_admin')$$,
  '42501', null, 'admin cannot insert a super_admin profile');

select * from finish();
rollback;
