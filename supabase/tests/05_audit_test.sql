begin;
select plan(6);

select has_table('public','payments','payments exists');
select has_table('public','audit_log','audit_log exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);
insert into auth.users (id, email)
values ('11111111-1111-1111-1111-111111111111','customer@example.com');
insert into public.reservations (id, unit_id, period, kind, status, block_reason)
values ('cccccccc-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
        'block','confirmed','maintenance');

update public.reservations set status = 'cancelled'
where id = 'cccccccc-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.audit_log
    where entity = 'reservation'
      and entity_id = 'cccccccc-0000-0000-0000-000000000001'
      and action = 'status:confirmed->cancelled'),
  1,
  'status transition is recorded once');

-- the insert branch of the trigger fires too, not only transitions
select is(
  (select count(*)::int from public.audit_log
    where entity_id = 'cccccccc-0000-0000-0000-000000000001'
      and action = 'created:confirmed'),
  1,
  'insert is recorded as created:<status>');

-- an update that does not change status writes no audit row
update public.reservations set block_reason = 'still maintenance'
where id = 'cccccccc-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.audit_log
    where entity_id = 'cccccccc-0000-0000-0000-000000000001'),
  2,
  'a non-status update writes no audit row');

-- audit_log is staff-only
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select count(*)::int from public.audit_log),
  0,
  'a customer sees no audit rows');

reset role;

select * from finish();
rollback;
