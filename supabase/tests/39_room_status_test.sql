-- Room status grid (REQ-06), added in 0047_room_status.sql. See
-- docs/superpowers/specs/2026-09-25-room-status-grid-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures: resort R with an owner, an admin, two staff members (Indu the
-- Incharge, Hari the housekeeper) and an accountant; resort S with an owner
-- and one staff member (Sam); a guest (Gita) and an outsider with no
-- membership. R's units: Cottage 1 (Gita is checked in), Day Hut
-- (slot-only), Old Barn (inactive) and Cottage 4 (a confirmed arrival
-- today, Asia/Kolkata).
begin;
select plan(69);

-- Rows a statement changed, run as the current role (0 when RLS filters
-- it). Used by later sections.
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

insert into auth.users (id, email) values
  ('e0000000-0000-0000-0000-000000000001','r-owner@example.com'),
  ('e0000000-0000-0000-0000-000000000002','r-admin@example.com'),
  ('e0000000-0000-0000-0000-000000000003','r-incharge@example.com'),
  ('e0000000-0000-0000-0000-000000000004','r-housekeeper@example.com'),
  ('e0000000-0000-0000-0000-000000000005','r-accountant@example.com'),
  ('e0000000-0000-0000-0000-000000000006','s-owner@example.com'),
  ('e0000000-0000-0000-0000-000000000007','s-staff@example.com'),
  ('e0000000-0000-0000-0000-000000000008','guest@example.com'),
  ('e0000000-0000-0000-0000-000000000009','outsider@example.com');
update public.profiles set full_name = 'Indu Incharge'
  where id = 'e0000000-0000-0000-0000-000000000003';
update public.profiles set full_name = 'Hari Housekeeper'
  where id = 'e0000000-0000-0000-0000-000000000004';
update public.profiles set full_name = 'Sam Other'
  where id = 'e0000000-0000-0000-0000-000000000007';
update public.profiles set full_name = 'Gita Guest Rao'
  where id = 'e0000000-0000-0000-0000-000000000008';

insert into public.properties (id, name, slug) values
  ('eeeeeeee-0000-4000-8000-000000000001','Resort R','rooms-r'),
  ('eeeeeeee-0000-4000-8000-000000000002','Resort S','rooms-s');

insert into public.resort_members (property_id, user_id, role) values
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000001','owner'),
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000002','admin'),
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000003','staff'),
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000004','staff'),
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000005','accountant'),
  ('eeeeeeee-0000-4000-8000-000000000002','e0000000-0000-0000-0000-000000000006','owner'),
  ('eeeeeeee-0000-4000-8000-000000000002','e0000000-0000-0000-0000-000000000007','staff');

insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode, is_active) values
  ('eeeeeeee-0000-4000-8000-000000000011','eeeeeeee-0000-4000-8000-000000000001','Cottage 1',2,4,'nightly',true),
  ('eeeeeeee-0000-4000-8000-000000000012','eeeeeeee-0000-4000-8000-000000000001','Day Hut',2,4,'slot',true),
  ('eeeeeeee-0000-4000-8000-000000000013','eeeeeeee-0000-4000-8000-000000000001','Old Barn',2,4,'nightly',false),
  ('eeeeeeee-0000-4000-8000-000000000014','eeeeeeee-0000-4000-8000-000000000001','Cottage 4',2,4,'nightly',true);

-- Gita is in Cottage 1 now; Cottage 4 has a confirmed arrival at 14:00
-- today, Asia/Kolkata (the same "today" room_status_board uses).
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, checked_in_at) values
  ('eeeeeeee-0000-4000-8000-000000000031','eeeeeeee-0000-4000-8000-000000000011',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','e0000000-0000-0000-0000-000000000008',2, now() - interval '1 day'),
  ('eeeeeeee-0000-4000-8000-000000000032','eeeeeeee-0000-4000-8000-000000000014',
   tstzrange(((now() at time zone 'Asia/Kolkata')::date + time '14:00') at time zone 'Asia/Kolkata',
             ((now() at time zone 'Asia/Kolkata')::date + 1 + time '11:00') at time zone 'Asia/Kolkata', '[)'),
   'booking','confirmed','e0000000-0000-0000-0000-000000000008',2, null);

-- === Task 1: the contract ===================================================

select has_table('public', 'unit_room_status', 'unit_room_status exists');
select enum_has_labels('public', 'room_state', array['ready','dirty','out_of_order'],
  'room_state is ready, dirty, out_of_order');
select enum_has_labels('public', 'task_kind', array['general','housekeeping'],
  'task_kind is general, housekeeping');
select is((select array_agg(column_name::text order by column_name)
             from information_schema.columns
            where table_schema = 'public' and table_name = 'tasks'
              and column_name in ('kind','unit_id','started_at')),
  array['kind','started_at','unit_id'], 'tasks gains kind, unit_id and started_at');
select is((select column_default from information_schema.columns
            where table_schema = 'public' and table_name = 'properties'
              and column_name = 'housekeeping_sla_minutes'),
  '60', 'the cleaning SLA defaults to 60 minutes');
select throws_ok($$insert into public.unit_room_status (unit_id, state)
  values ('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order')$$,
  '23514', null, 'an out-of-order row without a reason is refused by the table itself');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'room_status_board'
              and p.parameter_mode = 'OUT'),
  array['unit_id','name','booking_mode','effective_status','state','reason',
        'occupied_reservation_id','guest_first_name','arriving_today',
        'housekeeping_task_id','housekeeper_name','housekeeping_status',
        'housekeeping_dispatched_at','overdue'],
  'room_status_board returns the columns RoomBoardEntry.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'list_dispatchable_staff'
              and p.parameter_mode = 'OUT'),
  array['user_id','full_name'], 'list_dispatchable_staff returns user_id and full_name');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.room_status_board(uuid)',
               'public.set_room_status(uuid, public.room_state, text)',
               'public.dispatch_housekeeping(uuid, uuid, text)',
               'public.list_dispatchable_staff(uuid)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the room functions');
select is((select count(*)::int
             from unnest(array[
               'public.room_status_board(uuid)',
               'public.set_room_status(uuid, public.room_state, text)',
               'public.dispatch_housekeeping(uuid, uuid, text)',
               'public.list_dispatchable_staff(uuid)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  4, 'authenticated can execute all four room functions');

-- Reads: the resort's own members only; no direct writes for anyone. The
-- row goes on the inactive Old Barn so it never shows on the board.
insert into public.unit_room_status (unit_id, state)
  values ('eeeeeeee-0000-4000-8000-000000000013', 'dirty');
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.unit_room_status), 1,
  'staff read their resort''s room rows');
select throws_ok($$insert into public.unit_room_status (unit_id, state)
  values ('eeeeeeee-0000-4000-8000-000000000012', 'dirty')$$,
  '42501', null, 'staff cannot write room rows directly');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select is((select count(*)::int from public.unit_room_status), 0,
  'staff of another resort read none of them');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000008","role":"authenticated"}';
select is((select count(*)::int from public.unit_room_status), 0,
  'a guest reads none of them');
reset role;
set local request.jwt.claims to '';

-- === Task 2: room_status_board and set_room_status =========================

set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select array_agg(name order by name)
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')),
  array['Cottage 1','Cottage 4','Day Hut'],
  'the board lists every active unit and no inactive one');
select is((select effective_status || '|' || guest_first_name || '|'
                  || (occupied_reservation_id = 'eeeeeeee-0000-4000-8000-000000000031')::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000011'),
  'occupied|Gita|true', 'a checked-in unit is Occupied, with the guest''s first name only');
select is((select booking_mode::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'slot', 'a slot-only unit comes back as slot (Day use)');
select is((select effective_status || '|' || arriving_today::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'available|true', 'a unit with a confirmed arrival today is Available and flagged');
select is((select state::text || '|' || overdue::text || '|' || coalesce(housekeeping_task_id::text, '-')
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'ready|false|-', 'a unit with no stored row is ready, with no housekeeping');

-- Role matrix.
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')),
  3, 'an accountant reads the board');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'dirty')$$,
  'P0020', null, 'an accountant cannot change a room');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000008","role":"authenticated"}';
select throws_ok($$select * from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')$$,
  'P0020', null, 'a guest cannot read the board');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'dirty')$$,
  'P0020', null, 'a guest cannot change a room');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select throws_ok($$select * from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')$$,
  'P0020', null, 'staff of another resort cannot read the board');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'dirty')$$,
  'P0020', null, 'staff of another resort cannot change a room');
set local role anon;
select throws_ok($$select * from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')$$,
  '42501', null, 'anon cannot call the board');

-- Setting states.
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order')$$,
  'P0030', 'reason_required', 'Maintenance without a reason is refused');
select throws_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order', '   ')$$,
  'P0030', 'reason_required', 'a blank reason is refused');
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'out_of_order', ' AC broken ')$$,
  'staff marks a room out of order with a reason');
select is((select effective_status || '|' || reason
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'maintenance|AC broken', 'the board shows Maintenance with the trimmed reason');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000011', 'dirty')$$,
  'admin marks an occupied room as needing cleaning');
select is((select effective_status || '|' || state::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000011'),
  'occupied|dirty', 'an occupied room stays Occupied and keeps its needs-cleaning state');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'ready')$$,
  'owner returns a room to Available');
select is((select effective_status || '|' || coalesce(reason, '-')
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'available|-', 'Available clears the maintenance reason');

-- Housekeeping columns and the SLA, with a task inserted directly
-- (dispatching arrives in Task 3). `reset role` keeps the claims; clear them.
reset role;
set local request.jwt.claims to '';
insert into public.tasks (property_id, assignee_id, title, kind, unit_id, created_by, created_at) values
  ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000004','Clean Day Hut',
   'housekeeping','eeeeeeee-0000-4000-8000-000000000012','e0000000-0000-0000-0000-000000000003',
   now() - interval '61 minutes');
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select housekeeper_name || '|' || housekeeping_status::text || '|' || overdue::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'Hari Housekeeper|todo|true', 'an open task older than the 60-minute SLA is Overdue, with its housekeeper');
reset role;
set local request.jwt.claims to '';
update public.properties set housekeeping_sla_minutes = 120
 where id = 'eeeeeeee-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select overdue
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  false, 'the same task is on time under a 120-minute SLA');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000012', 'ready')$$,
  'owner marks the day hut Available');
reset role;
set local request.jwt.claims to '';
select is((select status::text from public.tasks
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'done', 'marking a room Available closes its open housekeeping task');

-- === Task 3: dispatching housekeeping and the task rules ===================

set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select array_agg(full_name order by full_name)
             from public.list_dispatchable_staff('eeeeeeee-0000-4000-8000-000000000001')),
  array['Hari Housekeeper','Indu Incharge'], 'only the resort''s staff members can be dispatched');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select * from public.list_dispatchable_staff('eeeeeeee-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an accountant cannot list housekeepers');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004')$$, 'P0020', null, 'an accountant cannot dispatch');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000007')$$, 'P0020', null, 'staff of another resort cannot dispatch');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000007')$$, 'P0020', null, 'an assignee from another resort is refused');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000005')$$, 'P0020', null, 'a member who is not staff cannot be dispatched');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000009')$$, 'P0020', null, 'someone with no membership cannot be dispatched');
select lives_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004', ' Deep clean ')$$, 'the Incharge dispatches housekeeping');
select is((select effective_status || '|' || housekeeper_name || '|' || housekeeping_status::text || '|' || overdue::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'cleaning|Hari Housekeeper|todo|false', 'the room shows Cleaning with the housekeeper and a fresh task');
select throws_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004')$$, 'P0031', 'already_dispatched',
  'a second dispatch while one is open is refused');
reset role;
set local request.jwt.claims to '';
select is((select title || '|' || description || '|' || kind::text || '|' || assignee_id::text
                  || '|' || property_id::text || '|' || created_by::text
             from public.tasks where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'Clean Cottage 4|Deep clean|housekeeping|e0000000-0000-0000-0000-000000000004|'
  || 'eeeeeeee-0000-4000-8000-000000000001|e0000000-0000-0000-0000-000000000003',
  'the task names the room, carries the note and records who dispatched it');

-- The housekeeper's side: Assigned Work, status only.
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.tasks where kind = 'housekeeping' and status <> 'done'),
  1, 'the housekeeper sees the open task');
select throws_ok($$update public.tasks set unit_id = 'eeeeeeee-0000-4000-8000-000000000011'
  where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'$$,
  '42501', null, 'the assignee cannot move the task to another room');
select throws_ok($$update public.tasks set kind = 'general'
  where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'$$,
  '42501', null, 'the assignee cannot change the task kind');
select throws_ok($$update public.tasks set started_at = now() - interval '1 day'
  where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'$$,
  '42501', null, 'the assignee cannot backdate the start');
update public.tasks set status = 'in_progress'
 where unit_id = 'eeeeeeee-0000-4000-8000-000000000014';
select isnt((select started_at from public.tasks
              where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  null, 'moving to In Progress records the start time');
update public.tasks set status = 'done'
 where unit_id = 'eeeeeeee-0000-4000-8000-000000000014';
select is((select effective_status || '|' || coalesce(housekeeping_task_id::text, '-')
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014'),
  'available|-', 'a finished housekeeping task returns the room to Available');

-- Review Focus 1: housekeeping never clears Maintenance.
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000012', 'out_of_order', 'Roof leak')$$,
  'the Incharge marks the day hut out of order');
select lives_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000012',
  'e0000000-0000-0000-0000-000000000004')$$, 'housekeeping can still be sent to an out-of-order room');
select is((select state::text
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'out_of_order', 'dispatching does not clear the maintenance flag');
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000004","role":"authenticated"}';
update public.tasks set status = 'done'
 where unit_id = 'eeeeeeee-0000-4000-8000-000000000012' and status <> 'done';
select is((select effective_status
             from public.room_status_board('eeeeeeee-0000-4000-8000-000000000001')
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000012'),
  'maintenance', 'finishing housekeeping leaves an out-of-order room in Maintenance');

-- Review Focus 3: a Staff / Incharge who is not the assignee.
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004')$$, 'a room can be dispatched again once its last task is done');
select lives_ok($$select public.set_room_status('eeeeeeee-0000-4000-8000-000000000014', 'ready')$$,
  'the Incharge (not the assignee) marks the room Available');
reset role;
set local request.jwt.claims to '';
select is((select count(*)::int from public.tasks
            where unit_id = 'eeeeeeee-0000-4000-8000-000000000014' and status <> 'done'),
  0, 'marking Available closes the open task even for a non-admin caller');
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.dispatch_housekeeping('eeeeeeee-0000-4000-8000-000000000014',
  'e0000000-0000-0000-0000-000000000004')$$, 'housekeeping is sent to Cottage 4 again');
select is(pg_temp.rows_affected($$update public.tasks set status = 'done'
  where unit_id = 'eeeeeeee-0000-4000-8000-000000000014' and status <> 'done'$$),
  0, 'a staff member who is not the assignee still cannot update the task directly');

-- Task rules, as the superuser with no authenticated caller.
reset role;
set local request.jwt.claims to '';
-- Review Focus 2: the index behind P0031 when two dispatches race.
select throws_ok($$insert into public.tasks (property_id, assignee_id, title, kind, unit_id, created_by)
  values ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000003',
          'Clean Cottage 4','housekeeping','eeeeeeee-0000-4000-8000-000000000014',
          'e0000000-0000-0000-0000-000000000002')$$,
  '23505', null, 'a unit can have only one open housekeeping task');
select throws_ok($$insert into public.tasks (property_id, assignee_id, title, kind, unit_id, created_by)
  values ('eeeeeeee-0000-4000-8000-000000000002','e0000000-0000-0000-0000-000000000007',
          'Clean','housekeeping','eeeeeeee-0000-4000-8000-000000000012',
          'e0000000-0000-0000-0000-000000000006')$$,
  'P0021', null, 'a task cannot point at another resort''s room');
select throws_ok($$insert into public.tasks (property_id, assignee_id, title, kind, unit_id, created_by)
  values ('eeeeeeee-0000-4000-8000-000000000001','e0000000-0000-0000-0000-000000000004',
          'Fix tap','general','eeeeeeee-0000-4000-8000-000000000012',
          'e0000000-0000-0000-0000-000000000003')$$,
  '23514', null, 'a general task cannot carry a room');

-- Review Focus 5: deleting a unit with housekeeping history.
set local role authenticated;
set local request.jwt.claims to '{"sub":"e0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$delete from public.units where id = 'eeeeeeee-0000-4000-8000-000000000012'$$,
  'an admin can still delete a unit with housekeeping history');
reset role;
set local request.jwt.claims to '';
select is((select count(*)::int from public.tasks
            where title = 'Clean Day Hut' and unit_id is null),
  2, 'its housekeeping tasks are kept, unlinked from the room');

select * from finish();
rollback;
