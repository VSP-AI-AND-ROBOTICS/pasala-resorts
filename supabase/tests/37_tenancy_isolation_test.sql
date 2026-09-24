begin;
select plan(26);

-- Users: A's owner/admin/staff/accountant, B's owner, one guest per resort.
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-00000000000a','a-owner@example.com'),
  ('a0000000-0000-0000-0000-00000000000b','a-admin@example.com'),
  ('a0000000-0000-0000-0000-00000000000c','a-staff@example.com'),
  ('a0000000-0000-0000-0000-00000000000d','a-acct@example.com'),
  ('b0000000-0000-0000-0000-00000000000a','b-owner@example.com'),
  ('c0000000-0000-0000-0000-00000000000a','guest-a@example.com'),
  ('c0000000-0000-0000-0000-00000000000b','guest-b@example.com');

insert into public.properties (id, name, slug) values
  ('aaaaaaaa-0000-4000-8000-000000000001','Resort A','iso-a'),
  ('bbbbbbbb-0000-4000-8000-000000000001','Resort B','iso-b');

insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-4000-8000-000000000001','a0000000-0000-0000-0000-00000000000a','owner'),
  ('aaaaaaaa-0000-4000-8000-000000000001','a0000000-0000-0000-0000-00000000000b','admin'),
  ('aaaaaaaa-0000-4000-8000-000000000001','a0000000-0000-0000-0000-00000000000c','staff'),
  ('aaaaaaaa-0000-4000-8000-000000000001','a0000000-0000-0000-0000-00000000000d','accountant'),
  ('bbbbbbbb-0000-4000-8000-000000000001','b0000000-0000-0000-0000-00000000000a','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('aaaaaaaa-0000-4000-8000-000000000011','aaaaaaaa-0000-4000-8000-000000000001','UA',2,4),
  ('bbbbbbbb-0000-4000-8000-000000000011','bbbbbbbb-0000-4000-8000-000000000001','UB',2,4);

insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests) values
  ('aaaaaaaa-0000-4000-8000-000000000021','aaaaaaaa-0000-4000-8000-000000000011',
   tstzrange('2027-02-01 14:00+05:30','2027-02-02 11:00+05:30','[)'),
   'booking','confirmed','c0000000-0000-0000-0000-00000000000a',2),
  ('bbbbbbbb-0000-4000-8000-000000000021','bbbbbbbb-0000-4000-8000-000000000011',
   tstzrange('2027-02-01 14:00+05:30','2027-02-02 11:00+05:30','[)'),
   'booking','confirmed','c0000000-0000-0000-0000-00000000000b',2);

insert into public.payments (reservation_id, kind, amount, status) values
  ('aaaaaaaa-0000-4000-8000-000000000021','advance',1000,'succeeded'),
  ('bbbbbbbb-0000-4000-8000-000000000021','advance',1000,'succeeded');

insert into public.expenses (property_id, category, amount, expense_date, recorded_by) values
  ('aaaaaaaa-0000-4000-8000-000000000001','supplies',10,'2027-02-01','a0000000-0000-0000-0000-00000000000a'),
  ('bbbbbbbb-0000-4000-8000-000000000001','supplies',10,'2027-02-01','b0000000-0000-0000-0000-00000000000a');

insert into public.tasks (property_id, title, assignee_id, created_by) values
  ('aaaaaaaa-0000-4000-8000-000000000001','Clean pool','a0000000-0000-0000-0000-00000000000c','a0000000-0000-0000-0000-00000000000b'),
  ('bbbbbbbb-0000-4000-8000-000000000001','Fix gate','b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000a');

-- Owner
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B reservations');
select is((select count(*)::int from public.payments where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B payments');
select is((select count(*)::int from public.expenses where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B expenses');
select is((select count(*)::int from public.tasks where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B tasks');
select is((select count(*)::int from public.profiles where id = 'c0000000-0000-0000-0000-00000000000b'), 0, 'A owner: cannot read B guest profile');
select is((select count(*)::int from public.profiles where id = 'c0000000-0000-0000-0000-00000000000a'), 1, 'A owner: can read own guest profile');
select is((select count(*)::int from public.expenses where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 1, 'A owner: sees own expenses');
select throws_ok($$insert into public.expenses (property_id, category, amount, expense_date, recorded_by)
  values ('bbbbbbbb-0000-4000-8000-000000000001','supplies',5,'2027-02-01','a0000000-0000-0000-0000-00000000000a')$$,
  '42501', null, 'A owner: cannot insert B expense');
update public.units set name = 'hacked' where id = 'bbbbbbbb-0000-4000-8000-000000000011';
reset role;
select is((select name from public.units where id = 'bbbbbbbb-0000-4000-8000-000000000011'), 'UB', 'A owner: B unit update affected nothing');

-- Admin
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A admin: no B reservations');
select is((select count(*)::int from public.tasks where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A admin: no B tasks');
select is((select count(*)::int from public.resort_members where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A admin: no B members');

-- Staff
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A staff: no B reservations');
select is((select count(*)::int from public.payments where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A staff: no B payments');
select is((select count(*)::int from public.expenses), 0, 'A staff: no expenses at all (not an expense reader)');
select is((select count(*)::int from public.tasks), 1, 'A staff: only own assigned task');

-- Accountant
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000d","role":"authenticated"}';
select is((select count(*)::int from public.expenses where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A accountant: no B expenses');
select is((select count(*)::int from public.expenses where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 1, 'A accountant: own expenses');

-- Guest of A
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 1, 'guest A: only own reservation');
select is((select count(*)::int from public.payments), 1, 'guest A: only own payment');

-- Suspended resort A
reset role;
update public.properties set status = 'suspended' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
set local role anon;
select is((select count(*)::int from public.properties where id = 'aaaaaaaa-0000-4000-8000-000000000001'), 0, 'suspended resort hidden from anon');
select is((select count(*)::int from public.units where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 0, 'suspended resort units hidden from anon');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 1, 'suspended: admin still reads');
select throws_ok($$insert into public.expenses (property_id, category, amount, expense_date, recorded_by)
  values ('aaaaaaaa-0000-4000-8000-000000000001','supplies',5,'2027-02-01','a0000000-0000-0000-0000-00000000000b')$$,
  '42501', null, 'suspended: admin direct write refused');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 1, 'suspended: guest still sees own booking');

-- Platform admin sees no resort rows.
reset role;
update public.profiles set platform_role = 'platform_admin' where id = 'b0000000-0000-0000-0000-00000000000a';
delete from public.resort_members where user_id = 'b0000000-0000-0000-0000-00000000000a';
set local role authenticated;
set local request.jwt.claims to '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 0, 'platform admin: no reservation rows');

select * from finish();
rollback;
