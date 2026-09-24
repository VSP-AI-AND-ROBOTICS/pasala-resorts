-- attendance_records + RLS + attendance_records_enforce_own_checkout(),
-- added in 0023_attendance_records.sql to back the staff Daily Work
-- Status hub section and its read-only admin attendance screen. See
-- that migration's header for the "checkout is final, never corrected"
-- design decision.

begin;
select plan(22);

select has_table('public', 'attendance_records', 'attendance_records table exists');
select has_function('public', 'attendance_records_enforce_own_checkout',
  'the enforcement trigger function exists');
select has_function('public', 'check_out_attendance',
  'the checkout RPC exists');

-- The two fresh check-in fixtures further down (users ...05 and ...06) need
-- a resort role to write attendance at the seed resort.
insert into public.resort_members (property_id, user_id, role) values
  ('a0000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000005','staff'),
  ('a0000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000006','staff');

-- === insert: staff can check themselves in today, nothing else ============

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (property_id, id, staff_id, work_date)
    values ('a0000000-0000-0000-0000-000000000001', '99111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003',
            (now() at time zone 'Asia/Kolkata')::date)$$,
  'staff can check themselves in today');

select throws_ok(
  $$insert into public.attendance_records (property_id, staff_id, work_date)
    values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000004', current_date + 10)$$,
  '42501', null, 'staff cannot check in on behalf of someone else');

select throws_ok(
  $$insert into public.attendance_records (property_id, staff_id, work_date)
    values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', current_date - 10)$$,
  '42501', null, 'staff cannot back-date a check-in to a different day');

select throws_ok(
  $$insert into public.attendance_records (property_id, staff_id, work_date, check_out_at)
    values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', current_date + 11, now())$$,
  '42501', null, 'a check-in cannot arrive already checked out');

select throws_ok(
  $$insert into public.attendance_records (property_id, staff_id, work_date)
    values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003',
            (now() at time zone 'Asia/Kolkata')::date)$$,
  '23505', null, 'a second check-in the same day is rejected by the unique constraint');

-- === select: own rows only for staff, everything for admin =================

select is(
  (select count(*)::int from public.attendance_records),
  1,
  'a staff member sees only their own attendance record via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (property_id, id, staff_id, work_date)
    values ('a0000000-0000-0000-0000-000000000001', '99222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004',
            (now() at time zone 'Asia/Kolkata')::date)$$,
  'an accountant can also check themselves in');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.attendance_records),
  2,
  'admin sees every attendance record via direct select');

-- === update: only the owning staff member can check themselves out, once ==

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$select public.check_out_attendance('99111111-1111-1111-1111-111111111111')$$,
  'a staff member can check themselves out');

reset role;
select is(
  (select check_out_at is not null from public.attendance_records
    where id = '99111111-1111-1111-1111-111111111111'),
  true,
  'the checkout is visible directly on the table');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select throws_ok(
  $$select public.check_out_attendance('99111111-1111-1111-1111-111111111111')$$,
  '42501', null, 'a different staff member cannot check someone else out');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$select public.check_out_attendance('99111111-1111-1111-1111-111111111111')$$,
  '42501', null, 'admin cannot check someone out either -- attendance is never admin-written');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$select public.check_out_attendance('99111111-1111-1111-1111-111111111111')$$,
  '42501', null, 'an already-checked-out record cannot be checked out again');

select throws_ok(
  $$update public.attendance_records set check_in_at = now()
    where id = '99111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'check_in_at cannot be changed through an update');

-- === insert: work_date is judged against the resort's own IST calendar =====
-- === day, not the database server's own configured timezone ===============

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (property_id, id, staff_id, work_date)
    values ('a0000000-0000-0000-0000-000000000001', '99555555-5555-5555-5555-555555555555',
            '10000000-0000-0000-0000-000000000005',
            (now() at time zone 'Asia/Kolkata')::date)$$,
  'staff can check in using the resort''s IST calendar date '
  '(the same expression the RLS check itself uses), not raw current_date');

-- === insert: check_in_at cannot be forged by the client ====================

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (property_id, id, staff_id, work_date, check_in_at)
    values ('a0000000-0000-0000-0000-000000000001', '99666666-6666-6666-6666-666666666666',
            '10000000-0000-0000-0000-000000000006',
            (now() at time zone 'Asia/Kolkata')::date,
            now() - interval '3 hours')$$,
  'a staff member can insert with an explicit check_in_at '
  '(accepted syntactically -- the trigger silently overwrites it below)');

reset role;
select is(
  (select check_in_at > now() - interval '1 minute' from public.attendance_records
    where id = '99666666-6666-6666-6666-666666666666'),
  true,
  'check_in_at is forced to the server clock, ignoring the client-forged value');

-- === anon: no access at all =================================================

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.attendance_records$$,
  '42501', null, 'anon cannot select attendance_records');

select throws_ok(
  $$insert into public.attendance_records (property_id, staff_id, work_date)
    values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', current_date)$$,
  '42501', null, 'anon cannot insert into attendance_records');

select * from finish();
rollback;
