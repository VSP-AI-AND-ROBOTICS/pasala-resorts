-- service_requests + create_service_request, added in
-- 0034_service_requests.sql.

begin;
select plan(10);

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

select has_table('public', 'service_requests', 'service_requests table exists');
select has_function('public', 'create_service_request', 'create_service_request exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000030','P30','p30');

-- The seed users' roles are memberships at the seed resort only; give them
-- the same roles at this file's property.
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000030','10000000-0000-0000-0000-000000000001','owner'),
  ('aaaaaaaa-0000-0000-0000-000000000030','10000000-0000-0000-0000-000000000002','admin'),
  ('aaaaaaaa-0000-0000-0000-000000000030','10000000-0000-0000-0000-000000000003','staff'),
  ('aaaaaaaa-0000-0000-0000-000000000030','10000000-0000-0000-0000-000000000004','accountant');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000030',
        'aaaaaaaa-0000-0000-0000-000000000030','U30', 4, 6);
insert into public.reservations (id, unit_id, period, kind, status, customer_id)
values ('97600000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000030',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000030', current_date+1, current_date+2),
   'booking', 'confirmed', '10000000-0000-0000-0000-000000000005');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select lives_ok(
  $$select public.create_service_request('97600000-0000-0000-0000-000000000001',
      'cleaning', 'please clean before 5pm')$$,
  'a confirmed guest can create a service request'
);

select is(
  (select status::text from public.service_requests
    where reservation_id = '97600000-0000-0000-0000-000000000001'),
  'requested',
  'a new request starts as requested with no assignee'
);

-- The customer cannot self-assign or edit their own request. Since 0044
-- service_requests_update is scoped to the resort's staff, so RLS filters
-- the customer's update: no error, no row changed.
select is(pg_temp.rows_affected(
  $$update public.service_requests set description = 'changed'
    where reservation_id = '97600000-0000-0000-0000-000000000001'$$),
  0,
  'the requesting customer cannot edit their own request'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$update public.service_requests set assigned_staff_id = '10000000-0000-0000-0000-000000000003'
    where reservation_id = '97600000-0000-0000-0000-000000000001'$$,
  'staff can assign the request to themselves'
);

select is(
  (select status::text from public.service_requests
    where reservation_id = '97600000-0000-0000-0000-000000000001'),
  'assigned',
  'assigning bumps status to assigned automatically'
);

select lives_ok(
  $$update public.service_requests set status = 'in_progress'
    where reservation_id = '97600000-0000-0000-0000-000000000001'$$,
  'the assigned staff member can move the request through its own statuses'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

with attempted as (
  update public.service_requests set status = 'completed'
  where reservation_id = '97600000-0000-0000-0000-000000000001'
  returning 1
)
select is(
  (select count(*)::int from attempted), 1,
  'admin (staff-or-above) can update a request assigned to someone else'
);

select is(
  (select count(*)::int from public.service_requests
    where reservation_id = '97600000-0000-0000-0000-000000000001'),
  1,
  'exactly one request exists for the reservation'
);

reset role;
select * from finish();
rollback;
