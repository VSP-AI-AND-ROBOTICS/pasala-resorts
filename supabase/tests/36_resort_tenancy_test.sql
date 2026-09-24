begin;
select plan(17);

select enum_has_labels('public','resort_role',
  array['owner','admin','staff','accountant']);
select enum_has_labels('public','platform_role',
  array['customer','platform_admin']);
select has_table('public','resort_members','resort_members exists');
select col_not_null('public','properties','status','properties.status is required');

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000001','owner-a@example.com'),
  ('a1000000-0000-0000-0000-000000000002','staff-a@example.com'),
  ('b1000000-0000-0000-0000-000000000001','owner-b@example.com');
insert into public.properties (id, name, slug) values
  ('aaaaaaaa-1111-0000-0000-000000000001','Resort A','resort-a'),
  ('bbbbbbbb-1111-0000-0000-000000000001','Resort B','resort-b');
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-1111-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','owner'),
  ('aaaaaaaa-1111-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','staff'),
  ('bbbbbbbb-1111-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','owner');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(public.resort_role('aaaaaaaa-1111-0000-0000-000000000001'::uuid),
          'staff'::public.resort_role, 'staff role at own resort');
select is(public.resort_role('bbbbbbbb-1111-0000-0000-000000000001'::uuid),
          null, 'no role at another resort');
select ok(public.has_resort_role('aaaaaaaa-1111-0000-0000-000000000001', true,
          'owner','admin','staff','accountant'), 'staff passes staff-or-above');
select ok(not public.has_resort_role('aaaaaaaa-1111-0000-0000-000000000001', true,
          'owner','admin'), 'staff fails admin check');
select ok(not public.is_platform_admin(), 'staff is not platform admin');

reset role;
update public.properties set status = 'suspended'
  where id = 'aaaaaaaa-1111-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated"}';

select ok(public.has_resort_role('aaaaaaaa-1111-0000-0000-000000000001', false,
          'owner','admin','staff','accountant'), 'suspended resort: reads allowed');
select ok(not public.has_resort_role('aaaaaaaa-1111-0000-0000-000000000001', true,
          'owner','admin','staff','accountant'), 'suspended resort: writes refused');
select throws_ok(
  $$select public.assert_resort_role('aaaaaaaa-1111-0000-0000-000000000001', true,
      'owner','admin','staff','accountant')$$,
  'P0022', null, 'assert on suspended write raises P0022');

reset role;
insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('aaaaaaaa-2222-0000-0000-000000000001','aaaaaaaa-1111-0000-0000-000000000001','UA',2,4),
  ('bbbbbbbb-2222-0000-0000-000000000001','bbbbbbbb-1111-0000-0000-000000000001','UB',2,4);
insert into public.reservations (id, unit_id, period, kind, status, guests, block_reason) values
  ('aaaaaaaa-3333-0000-0000-000000000001','aaaaaaaa-2222-0000-0000-000000000001',
   tstzrange('2027-01-03 14:00+05:30','2027-01-04 11:00+05:30','[)'),'block','confirmed',1,'maintenance');

select is((select property_id from public.reservations
            where id = 'aaaaaaaa-3333-0000-0000-000000000001'),
          'aaaaaaaa-1111-0000-0000-000000000001'::uuid,
          'reservation property_id filled from its unit');
select col_not_null('public','payments','property_id','payments.property_id required');
select col_is_null('public','audit_log','property_id','audit_log.property_id nullable');

select throws_ok(
  $$insert into public.payments (reservation_id, property_id, kind, amount, status)
    values ('aaaaaaaa-3333-0000-0000-000000000001',
            'bbbbbbbb-1111-0000-0000-000000000001','advance',100,'succeeded')$$,
  'P0021', null, 'payment cannot point at a different resort than its reservation');

select throws_ok(
  $$update public.reservations set unit_id = 'bbbbbbbb-2222-0000-0000-000000000001'
     where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  'P0021', null, 'moving a reservation to another resort''s unit is refused');

select * from finish();
rollback;
