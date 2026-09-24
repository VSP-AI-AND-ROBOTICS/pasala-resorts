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
select plan(14);

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

select * from finish();
rollback;
