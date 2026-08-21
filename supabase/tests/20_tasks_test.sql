-- tasks + RLS + tasks_enforce_write(), added in 0024_tasks.sql to back
-- the staff Assigned Work hub section and its admin tasks screen. See
-- that migration's header for the one-assignee-per-task and
-- no-transition-ordering design decisions.

begin;
select plan(23);

select has_table('public', 'tasks', 'tasks table exists');
select has_function('public', 'tasks_enforce_write',
  'the write-enforcement trigger function exists');

-- === insert: admin-only ======================================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$insert into public.tasks (id, assignee_id, title, description)
    values ('97111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003',
            'Restock minibar', 'Villa 2 is out of water bottles')$$,
  'admin can create a task assigned to a staff member');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$insert into public.tasks (assignee_id, title)
    values ('10000000-0000-0000-0000-000000000003', 'Self-assigned task')$$,
  '42501', null, 'a staff member cannot create their own task');

-- === select: own rows only for staff, everything for admin ==================

select is(
  (select count(*)::int from public.tasks),
  1,
  'a staff member sees only their own task via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select is(
  (select count(*)::int from public.tasks),
  0,
  'a different staff member sees none of someone else''s tasks');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$insert into public.tasks (id, assignee_id, title, description)
    values ('97222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004',
            'Reconcile petty cash', '')$$,
  'admin can create a second task for a different assignee');

select is(
  (select count(*)::int from public.tasks),
  2,
  'admin sees every task via direct select');

-- === update: assignee may change ONLY status on their own task ==============

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$update public.tasks set status = 'in_progress'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  'the assignee can move their own task to in_progress');

select lives_ok(
  $$update public.tasks set status = 'done'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  'the assignee can move their own task all the way to done');

select lives_ok(
  $$update public.tasks set status = 'todo'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  'the assignee can move a done task back to todo -- no transition ordering enforced');

select throws_ok(
  $$update public.tasks set title = 'Rewritten title'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'the assignee cannot change a task''s title -- only status may change');

select throws_ok(
  $$update public.tasks set description = 'Rewritten description'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'the assignee cannot change a task''s description either');

select throws_ok(
  $$update public.tasks set assignee_id = '10000000-0000-0000-0000-000000000004'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'the assignee cannot reassign their own task to someone else');

select throws_ok(
  $$update public.tasks set status = 'done'
    where id = '97222222-2222-2222-2222-222222222222'$$,
  '42501', null,
  'a staff member cannot update the status of someone else''s task '
  '(not visible to them, so RLS filters it out before the trigger ever runs)');

-- === update: admin may change anything, including reassignment ==============

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$update public.tasks
      set title = 'Reconcile petty cash (urgent)',
          description = 'Do this before end of day',
          assignee_id = '10000000-0000-0000-0000-000000000003'
    where id = '97222222-2222-2222-2222-222222222222'$$,
  'admin can edit title, description, and reassign a task');

reset role;
select is(
  (select assignee_id from public.tasks
    where id = '97222222-2222-2222-2222-222222222222'),
  '10000000-0000-0000-0000-000000000003'::uuid,
  'the reassignment is visible directly on the table');

select is(
  (select updated_at > created_at from public.tasks
    where id = '97222222-2222-2222-2222-222222222222'),
  true,
  'updated_at moves forward on a write');

-- === delete: admin-only, explicit error for anyone else ======================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$delete from public.tasks where id = '97111111-1111-1111-1111-111111111111'$$,
  '42501', null,
  'a staff member cannot delete their own task -- delete is admin-only');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$delete from public.tasks where id = '97111111-1111-1111-1111-111111111111'$$,
  'admin can delete a task');

reset role;
select is(
  (select count(*)::int from public.tasks),
  1,
  'the deleted task is actually gone');

-- === anon: no access at all ===================================================

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.tasks$$,
  '42501', null, 'anon cannot select tasks');

select throws_ok(
  $$insert into public.tasks (assignee_id, title)
    values ('10000000-0000-0000-0000-000000000003', 'x')$$,
  '42501', null, 'anon cannot insert into tasks');

select * from finish();
rollback;
