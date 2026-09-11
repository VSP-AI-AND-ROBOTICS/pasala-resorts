-- tasks.completed_at + staff_performance_summary, added in
-- 0029_staff_performance.sql. Uses the seeded staff@pasala.test
-- ('...003') and admin@pasala.test ('...002') accounts directly -- this
-- file inserts no tasks/attendance/leave for them anywhere else, so a
-- p_from/p_to spanning "around today" captures exactly this file's fixture
-- and nothing from seed.sql (which has none of these three tables).

begin;
select plan(11);

select has_function('public', 'staff_performance_summary',
  'staff_performance_summary exists');

-- === fixture: three tasks, two completed ====================================
--
-- Inserted as admin (not the default superuser role) so `created_by
-- default auth.uid()` actually resolves to a real profile -- `auth.uid()`
-- is null outside an authenticated session, which `tasks.created_by`'s
-- `not null` would otherwise reject.

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

insert into public.tasks (id, assignee_id, title, status) values
  ('97300000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000003', 'Task A', 'todo'),
  ('97300000-0000-0000-0000-000000000002',
   '10000000-0000-0000-0000-000000000003', 'Task B', 'todo'),
  ('97300000-0000-0000-0000-000000000003',
   '10000000-0000-0000-0000-000000000003', 'Task C', 'todo');

update public.tasks set status = 'done'
  where id in ('97300000-0000-0000-0000-000000000001',
               '97300000-0000-0000-0000-000000000002');

select is(
  (select count(*)::int from public.tasks
    where assignee_id = '10000000-0000-0000-0000-000000000003'
      and completed_at is not null),
  2,
  'completed_at is set for both tasks moved to done'
);

-- === fixture: one attendance record for today (own insert, real RLS) ========

reset role;
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$insert into public.attendance_records (staff_id, work_date)
    values ('10000000-0000-0000-0000-000000000003',
            (now() at time zone 'Asia/Kolkata')::date)$$,
  'staff checks themselves in for today'
);

-- === fixture: a staff_shift starting well before "now", so the check-in ===
-- === delay average is comfortably positive ===================================

reset role;
insert into public.staff_shifts (staff_id, shift_date, start_time, end_time)
values ('10000000-0000-0000-0000-000000000003',
        (now() at time zone 'Asia/Kolkata')::date, '00:00', '23:59');

-- === fixture: a 3-day approved leave request, fully inside the window ======

insert into public.leave_requests
  (staff_id, start_date, end_date, status, decided_by, decided_at)
values ('10000000-0000-0000-0000-000000000003',
        current_date, current_date + 2, 'approved',
        '10000000-0000-0000-0000-000000000002', now());

-- === the summary itself, called as admin ====================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select tasks_assigned from public.staff_performance_summary(
    '10000000-0000-0000-0000-000000000003', current_date - 1, current_date + 1)),
  3,
  'tasks_assigned counts all three tasks'
);

select is(
  (select tasks_completed from public.staff_performance_summary(
    '10000000-0000-0000-0000-000000000003', current_date - 1, current_date + 1)),
  2,
  'tasks_completed counts the two moved to done'
);

select is(
  (select completion_rate_pct from public.staff_performance_summary(
    '10000000-0000-0000-0000-000000000003', current_date - 1, current_date + 1)),
  66.7::numeric,
  'completion_rate_pct is 2/3 rounded to one decimal'
);

select ok(
  (select avg_completion_hours from public.staff_performance_summary(
    '10000000-0000-0000-0000-000000000003', current_date - 1, current_date + 1)) >= 0,
  'avg_completion_hours is a non-negative number'
);

select is(
  (select days_present from public.staff_performance_summary(
    '10000000-0000-0000-0000-000000000003', current_date - 1, current_date + 1)),
  1,
  'days_present counts today''s check-in'
);

select ok(
  (select avg_checkin_delay_minutes from public.staff_performance_summary(
    '10000000-0000-0000-0000-000000000003', current_date - 1, current_date + 1)) > 0,
  'avg_checkin_delay_minutes is positive against a midnight-start shift'
);

select is(
  (select leave_days_approved from public.staff_performance_summary(
    '10000000-0000-0000-0000-000000000003', current_date - 1, current_date + 1)),
  3,
  'leave_days_approved counts the 3-day approved request'
);

-- === access control ===========================================================

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$select public.staff_performance_summary()$$,
  'P0008', null, 'a plain staff member cannot call staff_performance_summary'
);

reset role;
select * from finish();
rollback;
