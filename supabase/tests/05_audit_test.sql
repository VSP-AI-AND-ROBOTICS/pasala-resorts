begin;
select plan(3);

select has_table('public','payments','payments exists');
select has_table('public','audit_log','audit_log exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);
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

select * from finish();
rollback;
