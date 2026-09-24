-- maintenance_issues + report_maintenance_issue + the maintenance-photos
-- storage policies, added in 0035_maintenance_issues.sql.

begin;
select plan(9);

-- Rows a statement changed, run as the current role: an RLS-filtered
-- write changes 0 rows without raising.
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

select has_table('public', 'maintenance_issues', 'maintenance_issues table exists');
select has_function('public', 'report_maintenance_issue', 'report_maintenance_issue exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000031','P31','p31');

-- The seed users' roles are memberships at the seed resort only; give them
-- the same roles at this file's property.
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000031','10000000-0000-0000-0000-000000000001','owner'),
  ('aaaaaaaa-0000-0000-0000-000000000031','10000000-0000-0000-0000-000000000002','admin'),
  ('aaaaaaaa-0000-0000-0000-000000000031','10000000-0000-0000-0000-000000000003','staff'),
  ('aaaaaaaa-0000-0000-0000-000000000031','10000000-0000-0000-0000-000000000004','accountant');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000031',
        'aaaaaaaa-0000-0000-0000-000000000031','U31', 4, 6);
insert into public.reservations (id, unit_id, period, kind, status, customer_id)
values ('97700000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000031',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000031', current_date+1, current_date+2),
   'booking', 'confirmed', '10000000-0000-0000-0000-000000000005');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select lives_ok(
  $$select public.report_maintenance_issue('97700000-0000-0000-0000-000000000001',
      'ac', 'AC not cooling', null, 'high')$$,
  'a confirmed guest can report a maintenance issue'
);

select is(
  (select status::text from public.maintenance_issues
    where reservation_id = '97700000-0000-0000-0000-000000000001'),
  'reported',
  'a new issue starts as reported with no assignee'
);

-- Since 0044 maintenance_issues_update is scoped to the resort's staff,
-- so RLS filters the customer's update: no error, no row changed.
select is(pg_temp.rows_affected(
  $$update public.maintenance_issues set priority = 'low'
    where reservation_id = '97700000-0000-0000-0000-000000000001'$$),
  0,
  'the reporting customer cannot edit their own issue'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$update public.maintenance_issues set assigned_staff_id = '10000000-0000-0000-0000-000000000003'
    where reservation_id = '97700000-0000-0000-0000-000000000001'$$,
  'staff can assign the issue to themselves'
);

select is(
  (select status::text from public.maintenance_issues
    where reservation_id = '97700000-0000-0000-0000-000000000001'),
  'assigned',
  'assigning bumps status to assigned automatically'
);

select lives_ok(
  $$update public.maintenance_issues set status = 'fixed'
    where reservation_id = '97700000-0000-0000-0000-000000000001'$$,
  'the assigned staff member can move the issue through its own statuses'
);

reset role;

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname in (
        'maintenance_photos_owner_upload',
        'maintenance_photos_owner_read',
        'maintenance_photos_staff_read'
      )),
  3,
  'all three maintenance-photos storage policies were created'
);

select * from finish();
rollback;
