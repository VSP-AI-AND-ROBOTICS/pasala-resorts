begin;
select plan(67);

-- Rows a statement changed, run as the current role (0 when RLS filters it).
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

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

-- B's guest reviewed their stay. author_name is set by the trigger from the
-- profile, whatever the insert supplies.
update public.profiles set full_name = 'Bina Guest' where id = 'c0000000-0000-0000-0000-00000000000b';
insert into public.reviews (reservation_id, customer_id, farmhouse_rating, cleanliness_rating,
  food_rating, service_rating, activities_rating, overall_rating, feedback, author_name) values
  ('bbbbbbbb-0000-4000-8000-000000000021','c0000000-0000-0000-0000-00000000000b',5,5,5,5,5,5,'Great','Spoofed');

-- Owner
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B reservations');
select is((select count(*)::int from public.payments where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B payments');
select is((select count(*)::int from public.expenses where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B expenses');
select is((select count(*)::int from public.tasks where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B tasks');
select is((select count(*)::int from public.profiles where id = 'c0000000-0000-0000-0000-00000000000b'), 0, 'A owner: cannot read B guest profile (even though that guest wrote a review)');
select is((select author_name from public.reviews where customer_id = 'c0000000-0000-0000-0000-00000000000b'), 'Bina Guest', 'A owner: B review shows author_name from the profile');
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
select throws_ok($$update public.tasks set property_id = 'bbbbbbbb-0000-4000-8000-000000000001'
  where assignee_id = 'a0000000-0000-0000-0000-00000000000c'$$,
  '42501', null, 'A staff: cannot move own assigned task to resort B');
select is((select property_id from public.tasks where assignee_id = 'a0000000-0000-0000-0000-00000000000c'),
  'aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'A staff: the task stays in resort A');

-- Accountant
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000d","role":"authenticated"}';
select is((select count(*)::int from public.expenses where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A accountant: no B expenses');
select is((select count(*)::int from public.expenses where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 1, 'A accountant: own expenses');

-- Guest of A
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 1, 'guest A: only own reservation');
select is((select count(*)::int from public.payments), 1, 'guest A: only own payment');

-- Resort status is platform-controlled.
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok($$update public.properties set status = 'suspended'
  where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'P0008', null, 'A owner: cannot change own resort status');
-- A platform admin who is also A's admin passes both RLS and the guard.
reset role;
update public.profiles set role = 'platform_admin' where id = 'a0000000-0000-0000-0000-00000000000b';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.properties set status = 'suspended'
  where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$),
  1, 'platform admin: can change resort status');
reset role;
update public.profiles set role = 'customer' where id = 'a0000000-0000-0000-0000-00000000000b';
-- `reset role` keeps the JWT claims; clear them so the next statements run
-- with no authenticated caller, as migrations and admin SQL do.
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'aaaaaaaa-0000-4000-8000-000000000001';

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
update public.profiles set role = 'platform_admin' where id = 'b0000000-0000-0000-0000-00000000000a';
delete from public.resort_members where user_id = 'b0000000-0000-0000-0000-00000000000a';
set local role authenticated;
set local request.jwt.claims to '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 0, 'platform admin: no reservation rows');

-- Booking, quote, coupon and refund functions (0045).
-- As A's admin (resort A active again). `reset role` keeps the JWT claims;
-- clear them so the status change runs with no authenticated caller.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
-- A hold of guest A's at resort B, for confirm_booking below.
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, hold_expires_at) values
  ('bbbbbbbb-0000-4000-8000-000000000022','bbbbbbbb-0000-4000-8000-000000000011',
   tstzrange('2027-05-01 14:00+05:30','2027-05-02 11:00+05:30','[)'),
   'booking','hold','c0000000-0000-0000-0000-00000000000a',2,
   '{"total": 1000}'::jsonb, now() + interval '15 minutes');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select throws_ok($$select public.block_dates('bbbbbbbb-0000-4000-8000-000000000011',
  array[daterange('2027-03-01','2027-03-02')], 'x')$$, 'P0020', null, 'A admin cannot block B dates');
select throws_ok($$select public.cancel_booking('bbbbbbbb-0000-4000-8000-000000000021','x')$$,
  'P0020', null, 'A admin cannot cancel B booking');
select throws_ok($$select public.compute_refund('bbbbbbbb-0000-4000-8000-000000000021')$$,
  'P0020', null, 'A admin cannot quote B refund');
-- Suspended resort: new holds refused.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'suspended' where id = 'bbbbbbbb-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok($$select public.create_hold('bbbbbbbb-0000-4000-8000-000000000011',
  '2027-04-01','2027-04-02',2)$$, 'P0022', null, 'cannot hold at suspended resort');
select throws_ok($$select public.get_quote('bbbbbbbb-0000-4000-8000-000000000011',
  tstzrange('2027-04-01 14:00+05:30','2027-04-02 11:00+05:30','[)'), 2)$$,
  'P0022', null, 'cannot quote at suspended resort');
select throws_ok($$select public.confirm_booking('bbbbbbbb-0000-4000-8000-000000000022','pay-1',1000)$$,
  'P0022', null, 'cannot confirm a hold at suspended resort');
select is((select count(*)::int from public.search_availability(
  'bbbbbbbb-0000-4000-8000-000000000001','2027-04-01','2027-04-02',2)), 0,
  'suspended resort absent from availability search');
-- Guests keep cancelling their own bookings at a suspended resort.
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is((select status from public.cancel_booking('bbbbbbbb-0000-4000-8000-000000000021','changed plans')),
  'cancelled'::public.reservation_status, 'guest cancels own booking at suspended resort');

-- Stay and guest-service functions (0045): check_in_booking, current_charges.
-- `reset role` keeps the JWT claims; clear them so the status change runs
-- with no authenticated caller.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'bbbbbbbb-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok($$select public.check_in_booking('bbbbbbbb-0000-4000-8000-000000000021')$$,
  'P0020', null, 'A staff cannot check in a B guest');
select throws_ok($$select public.current_charges('bbbbbbbb-0000-4000-8000-000000000021')$$,
  'P0020', null, 'A staff cannot read B charges');
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'suspended' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok($$select public.check_in_booking('aaaaaaaa-0000-4000-8000-000000000021')$$,
  'P0022', null, 'staff write at suspended resort raises P0022');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select lives_ok($$select public.cancel_booking('aaaaaaaa-0000-4000-8000-000000000021','changed plans')$$,
  'guest can still cancel at a suspended resort');

-- Reports, dashboard and staff listings (0045): p_property_id is now
-- required, and staff-or-above must hold that role AT the resort being
-- asked about -- not just anywhere. `reset role` keeps the JWT claims;
-- clear them so this status change runs with no authenticated caller.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'active' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000d","role":"authenticated"}';
select throws_ok($$select * from public.report_revenue('2027-01-01','2027-12-31','bbbbbbbb-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A accountant cannot read B revenue');
select throws_ok($$select public.dashboard_summary('bbbbbbbb-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A accountant cannot read B dashboard');
select throws_ok($$select * from public.report_expenses('2027-01-01','2027-12-31','bbbbbbbb-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A accountant cannot read B expenses report');

-- Staff-ops triggers, outbox, audit, iCal and maintenance photos (0045).
-- Fixtures as the superuser with no authenticated caller (`reset role`
-- keeps the JWT claims, so clear them).
reset role;
set local request.jwt.claims to '';
-- Each resort's own message template (distinct events: (event, channel)
-- is unique across all templates).
insert into public.outbox_templates (name, event, channel, body_template, property_id) values
  ('iso_a_note','iso_a_note','email','Hello from A','aaaaaaaa-0000-4000-8000-000000000001'),
  ('iso_b_note','iso_b_note','email','Hello from B','bbbbbbbb-0000-4000-8000-000000000001');
-- An inactive feed at B, so no poll ever fetches anything.
insert into public.ical_feeds (id, unit_id, url, is_active) values
  ('bbbbbbbb-0000-4000-8000-000000000031','bbbbbbbb-0000-4000-8000-000000000011',
   'https://example.com/b.ics', false);
-- Maintenance photos live at `{guest uid}/{file}` and are linked to an issue
-- through maintenance_issues.photo_url.
insert into storage.buckets (id, name) values ('maintenance-photos','maintenance-photos')
  on conflict (id) do nothing;
insert into storage.objects (bucket_id, name) values
  ('maintenance-photos','c0000000-0000-0000-0000-00000000000a/1_a.jpg'),
  ('maintenance-photos','c0000000-0000-0000-0000-00000000000b/1_b.jpg');
insert into public.maintenance_issues (reservation_id, category, photo_url) values
  ('aaaaaaaa-0000-4000-8000-000000000021','ac','c0000000-0000-0000-0000-00000000000a/1_a.jpg'),
  ('bbbbbbbb-0000-4000-8000-000000000021','ac','c0000000-0000-0000-0000-00000000000b/1_b.jpg');
insert into public.attendance_records (id, property_id, staff_id, work_date) values
  ('aaaaaaaa-0000-4000-8000-000000000041','aaaaaaaa-0000-4000-8000-000000000001',
   'a0000000-0000-0000-0000-00000000000c', (now() at time zone 'Asia/Kolkata')::date);

set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select throws_ok($$select public.rotate_ical_token('bbbbbbbb-0000-4000-8000-000000000011')$$,
  'P0020', null, 'A admin cannot rotate B iCal token');
select throws_ok($$select public.enqueue_outbox_message('bbbbbbbb-0000-4000-8000-000000000021','booking_confirmed')$$,
  'P0020', null, 'A admin cannot send B guest messages');
select throws_ok($$select public.ical_export('bbbbbbbb-0000-4000-8000-000000000011')$$,
  'P0020', null, 'A admin cannot export B unit calendar');
select throws_ok($$select public.ical_poll_feed('bbbbbbbb-0000-4000-8000-000000000031')$$,
  'P0020', null, 'A admin cannot poll B iCal feed');

set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select lives_ok($$select public.enqueue_outbox_message('aaaaaaaa-0000-4000-8000-000000000021','iso_a_note')$$,
  'A staff can queue a message from A''s template');
select lives_ok($$select public.enqueue_outbox_message('aaaaaaaa-0000-4000-8000-000000000021','iso_b_note')$$,
  'A staff asking for B''s template is a silent no-op');
select is((select count(*)::int from storage.objects
            where name = 'c0000000-0000-0000-0000-00000000000b/1_b.jpg'), 0,
  'A staff cannot read a maintenance photo from a B stay');
select is((select count(*)::int from storage.objects
            where name = 'c0000000-0000-0000-0000-00000000000a/1_a.jpg'), 1,
  'A staff can read a maintenance photo from an A stay');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from storage.objects
            where name = 'c0000000-0000-0000-0000-00000000000b/1_b.jpg'), 1,
  'guest B still reads own uploaded photo');

reset role;
set local request.jwt.claims to '';
select is((select count(*)::int from public.outbox where property_id is null), 0,
  'every outbox row carries a resort');
select is((select count(*)::int from public.audit_log a
             join public.reservations r on r.id = a.entity_id
            where a.property_id is distinct from r.property_id), 0,
  'audit rows for reservations carry the reservation''s resort');
select is((select count(*)::int from public.outbox
            where template = 'iso_a_note' and property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 1,
  'A template queued for the A booking, tagged with resort A');
select is((select count(*)::int from public.outbox where template = 'iso_b_note'), 0,
  'B template never used for an A booking');
select is((select count(*)::int from information_schema.columns
            where table_schema = 'public' and column_name = 'property_id' and is_nullable = 'YES'
              and table_name in ('coupons','outbox','staff_shifts','leave_requests',
                                 'attendance_records','tasks')), 0,
  'coupons, outbox and staff-ops rows always carry a resort');
select lives_ok($$insert into public.coupons (property_id, code, kind, value) values
  ('aaaaaaaa-0000-4000-8000-000000000001','SAME','fixed',100),
  ('bbbbbbbb-0000-4000-8000-000000000001','SAME','fixed',100)$$,
  'two resorts can each have coupon code SAME');
select throws_ok($$insert into public.coupons (property_id, code, kind, value)
  values ('aaaaaaaa-0000-4000-8000-000000000001','SAME','fixed',50)$$,
  '23505', null, 'a coupon code is still unique within one resort');

update public.properties set status = 'suspended'
 where id in ('aaaaaaaa-0000-4000-8000-000000000001','bbbbbbbb-0000-4000-8000-000000000001');
select is(public.ical_export_public((select token from public.ical_export_tokens
                                      where unit_id = 'bbbbbbbb-0000-4000-8000-000000000011')),
  null, 'public iCal export of a suspended resort returns nothing');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok($$select public.check_out_attendance('aaaaaaaa-0000-4000-8000-000000000041')$$,
  'P0022', null, 'staff cannot check out at a suspended resort');

-- Catalog guards: fail the suite when a future table, policy or security
-- definer function is added without resort scoping.
reset role;
select is(
  (select array_agg(c.relname::text order by c.relname)
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
      and exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = c.relname
                     and column_name = 'property_id')),
  null, 'every table with property_id has row security enabled');

-- No policy on a resort-owned table currently relies on a bare `true`, so
-- it is left out of the pattern; widen it only if a real need shows up.
select is(
  (select array_agg(tablename || '.' || policyname order by 1)
     from pg_policies
    where schemaname = 'public'
      and tablename in (select table_name from information_schema.columns
                         where table_schema = 'public' and column_name = 'property_id')
      and coalesce(qual,'') || coalesce(with_check,'') not similar to
          '%(has_resort_role|auth.uid\(\)|status = ''active'')%'),
  null, 'every policy on a resort-owned table checks the resort or the guest');

select is(
  (select array_agg(p.proname::text order by 1)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and p.proname <> all (array[
        'is_platform_admin','resort_role','has_resort_role','assert_resort_role',
        'fill_property_id','handle_new_user',
        'search_availability','get_quote','create_hold','resolve_coupon','confirm_booking',
        'compute_refund','cancel_booking','block_dates','release_expired_holds',
        'release_reservation_coupon','check_in_booking','checkout_booking','current_charges',
        'place_food_order','book_activity','create_service_request','report_maintenance_issue',
        'dashboard_summary','report_revenue','report_occupancy','report_food_sales',
        'report_expenses','staff_shifts_enforce_admin_write','leave_requests_enforce_admin_decision',
        'attendance_records_enforce_own_checkout','attendance_records_force_checkin_time',
        'check_out_attendance','tasks_enforce_write','service_requests_enforce_write',
        'maintenance_issues_enforce_write','enqueue_reservation_outbox','enqueue_outbox_message',
        'render_template','record_reservation_transition','sync_unit_calendar_event',
        'ical_provision_token','rotate_ical_token','ical_export','ical_build_document',
        'ical_export_public','ical_import_event','ical_poll_feed','ical_poll_all_feeds',
        'list_resort_members','add_resort_member','set_member_role','remove_resort_member',
        'platform_resorts','set_resort_status','create_resort',
        -- 0044: properties_guard_status checks is_platform_admin() directly
        -- before allowing a status change; reviews_set_author_name has no
        -- check of its own, but it only ever fires on a row the reviews_insert
        -- policy already restricted to customer_id = auth.uid(), so it just
        -- re-reads the inserting guest's own profile.
        'properties_guard_status','reviews_set_author_name'])),
  null, 'every security definer function is on the reviewed allow-list');

select * from finish();
rollback;
