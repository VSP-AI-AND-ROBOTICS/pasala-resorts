-- leave_requests + RLS + leave_requests_enforce_admin_decision(), added
-- in 0022_leave_requests.sql to back the staff Leave Management hub
-- section and its admin approve/reject screen. See that migration's
-- header for the decision-finality and no-shift-interaction design
-- decisions.

begin;
select plan(25);

select has_table('public', 'leave_requests', 'leave_requests table exists');
select has_function('public', 'leave_requests_enforce_admin_decision',
  'the enforcement trigger function exists');

-- === insert: staff can request their own leave, nothing else ==============

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$insert into public.leave_requests (id, staff_id, start_date, end_date, reason)
    values ('98111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003','2026-09-10','2026-09-12',
            'Family trip')$$,
  'staff can insert their own pending leave request');

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date)
    values ('10000000-0000-0000-0000-000000000004','2026-09-15','2026-09-16')$$,
  '42501', null, 'staff cannot insert a leave request for someone else');

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date, status)
    values ('10000000-0000-0000-0000-000000000003','2026-09-20','2026-09-21',
            'approved')$$,
  '42501', null, 'staff cannot insert a request that is already approved');

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date, decided_by)
    values ('10000000-0000-0000-0000-000000000003','2026-09-25','2026-09-26',
            '10000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'staff cannot insert with decided_by set on a pending request');

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date, decided_at)
    values ('10000000-0000-0000-0000-000000000003','2026-10-01','2026-10-02',
            now())$$,
  '42501', null, 'staff cannot insert with decided_at set on a pending request');

-- === insert: a customer is not staff-or-above, and cannot insert at all ====

reset role;
insert into auth.users (id, email)
values ('98333333-3333-3333-3333-333333333333','customer@example.com');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"98333333-3333-3333-3333-333333333333","role":"authenticated"}';

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date)
    values ('98333333-3333-3333-3333-333333333333','2026-09-10','2026-09-12')$$,
  '42501', null,
  'a customer cannot insert a leave request for themselves -- not staff-or-above');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

-- === the date-order check constraint =======================================

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date)
    values ('10000000-0000-0000-0000-000000000003','2026-09-20','2026-09-10')$$,
  '23514', null, 'end_date before start_date is rejected');

-- === select: own rows only for staff, everything for admin =================

select is(
  (select count(*)::int from public.leave_requests),
  1,
  'a staff member sees only their own leave request via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select lives_ok(
  $$insert into public.leave_requests (id, staff_id, start_date, end_date)
    values ('98222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004','2026-09-18','2026-09-18')$$,
  'an accountant can also insert their own pending leave request');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.leave_requests),
  2,
  'admin sees every leave request via direct select');

-- === update: admin-only, decision fields only ==============================

select lives_ok(
  $$update public.leave_requests
      set status = 'approved', decided_by = '10000000-0000-0000-0000-000000000002',
          decided_at = now()
    where id = '98111111-1111-1111-1111-111111111111'$$,
  'admin can approve a pending request');

reset role;
select is(
  (select status from public.leave_requests
    where id = '98111111-1111-1111-1111-111111111111'),
  'approved'::public.leave_status,
  'the approval is visible directly on the table');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$update public.leave_requests set reason = 'rewritten'
    where id = '98222222-2222-2222-2222-222222222222'$$,
  '42501', null,
  'admin cannot change a request''s content (reason) through an update -- '
  'only status/decided_by/decided_at may change');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$update public.leave_requests set status = 'approved'
    where id = '98111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'a staff member cannot approve their own request');

-- === decision finality: no reversals or re-decisions =======================
-- Switch back to admin role for these tests

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$update public.leave_requests
      set status = 'rejected'
    where id = '98111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'admin cannot flip an approved request to rejected -- decision is final');

select throws_ok(
  $$update public.leave_requests
      set status = 'approved'
    where id = '98111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'admin cannot re-approve an already approved request -- decision is final');

select throws_ok(
  $$update public.leave_requests
      set status = 'pending'
    where id = '98111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'admin cannot reset an approved request back to pending -- decision is final');

select lives_ok(
  $$update public.leave_requests
      set status = 'rejected', decided_by = '10000000-0000-0000-0000-000000000002',
          decided_at = now()
    where id = '98222222-2222-2222-2222-222222222222'$$,
  'admin can reject a pending request');

select throws_ok(
  $$update public.leave_requests
      set status = 'approved'
    where id = '98222222-2222-2222-2222-222222222222'$$,
  '42501', null,
  'admin cannot flip a rejected request to approved -- decision is final');

select throws_ok(
  $$update public.leave_requests
      set status = 'pending'
    where id = '98222222-2222-2222-2222-222222222222'$$,
  '42501', null,
  'admin cannot reset a rejected request back to pending -- decision is final');

-- === delete: nobody, not even admin =========================================

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$delete from public.leave_requests where id = '98222222-2222-2222-2222-222222222222'$$,
  '42501', null, 'not even admin can delete a leave request -- no delete grant exists');

-- === anon: no access at all =================================================

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.leave_requests$$,
  '42501', null, 'anon cannot select leave_requests');

select throws_ok(
  $$insert into public.leave_requests (staff_id, start_date, end_date)
    values ('10000000-0000-0000-0000-000000000003','2026-10-01','2026-10-02')$$,
  '42501', null, 'anon cannot insert into leave_requests');

select * from finish();
rollback;
