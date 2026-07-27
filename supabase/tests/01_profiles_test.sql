begin;
select plan(13);

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
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select lives_ok(
  $$delete from public.profiles
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'admin can delete a profile');

-- a customer cannot delete anyone
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$delete from public.profiles
      where id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null, 'customer cannot delete a profile');

select * from finish();
rollback;
