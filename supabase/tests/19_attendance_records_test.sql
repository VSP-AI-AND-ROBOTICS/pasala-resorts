-- attendance_records + RLS + attendance_records_enforce_own_checkout(),
-- added in 0023_attendance_records.sql to back the staff Daily Work
-- Status hub section and its read-only admin attendance screen. See
-- that migration's header for the "checkout is final, never corrected"
-- design decision.

begin;
select plan(19);

select has_table('public', 'attendance_records', 'attendance_records table exists');
select has_function('public', 'attendance_records_enforce_own_checkout',
  'the enforcement trigger function exists');
select has_function('public', 'check_out_attendance',
  'the checkout RPC exists');

-- === insert: staff can check themselves in today, nothing else ============

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (id, staff_id, work_date)
    values ('99111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003', current_date)$$,
  'staff can check themselves in today');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000004', current_date + 10)$$,
  '42501', null, 'staff cannot check in on behalf of someone else');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000003', current_date - 10)$$,
  '42501', null, 'staff cannot back-date a check-in to a different day');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date, check_out_at)
    values ('10000000-0000-0000-0000-000000000003', current_date + 11, now())$$,
  '42501', null, 'a check-in cannot arrive already checked out');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000003', current_date)$$,
  '23505', null, 'a second check-in the same day is rejected by the unique constraint');

-- === select: own rows only for staff, everything for admin =================

select is(
  (select count(*)::int from public.attendance_records),
  1,
  'a staff member sees only their own attendance record via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (id, staff_id, work_date)
    values ('99222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004', current_date)$$,
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

-- === anon: no access at all =================================================

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.attendance_records$$,
  '42501', null, 'anon cannot select attendance_records');

select throws_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000003', current_date)$$,
  '42501', null, 'anon cannot insert into attendance_records');

select * from finish();
rollback;
