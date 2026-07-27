begin;
select plan(18);

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

-- role-change authority: admin vs super_admin
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

select throws_ok(
  $$update public.profiles set role = 'admin'
      where id = '44444444-4444-4444-4444-444444444444'$$,
  '42501',
  null,
  'admin cannot change another profile role'
);

set local request.jwt.claims to
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select lives_ok(
  $$update public.profiles set role = 'staff'
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'super_admin can change a role'
);

-- admin can delete a profile (policy reachable, not blocked at grant layer)
set local role postgres;
select is(
  (select count(*)::int from public.profiles),
  4,
  '4 profiles exist before delete');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select lives_ok(
  $$delete from public.profiles
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'admin can delete a profile');

set local role postgres;
select is(
  (select count(*)::int from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'admin delete removed the row');

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

-- profiles_admin_insert: an admin may create a customer profile, but only a
-- super_admin may create a privileged one.
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

select lives_ok(
  $$insert into public.profiles (id, full_name, role)
    values ('55555555-5555-5555-5555-555555555555','New Customer','customer')$$,
  'admin can insert a customer profile');

select throws_ok(
  $$insert into public.profiles (id, full_name, role)
    values ('66666666-6666-6666-6666-666666666666','Sneaky','super_admin')$$,
  '42501', null, 'admin cannot insert a super_admin profile');

select * from finish();
rollback;
