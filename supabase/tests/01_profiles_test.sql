begin;
select plan(5);

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

select * from finish();
rollback;
