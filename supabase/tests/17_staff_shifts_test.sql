-- staff_shifts + list_staff_shifts(), added in 0021_staff_shifts.sql to
-- back the admin shift-assignment screen and the staff Work
-- Schedules/Time Slots views. See that migration's header for the
-- no-overlap-restriction and no-overnight-shift decisions.

begin;
select plan(20);

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

select has_table('public', 'staff_shifts', 'staff_shifts table exists');
select has_function('public', 'list_staff_shifts', 'list_staff_shifts() exists');

-- === writes: admin-only =====================================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$insert into public.staff_shifts
      (property_id, staff_id, shift_date, start_time, end_time, created_by)
    values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003','2026-09-01','09:00','17:00',
            '10000000-0000-0000-0000-000000000003')$$,
  '42501', null, 'a staff member cannot insert their own shift');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$insert into public.staff_shifts
      (property_id, id, staff_id, shift_date, start_time, end_time, created_by)
    values ('a0000000-0000-0000-0000-000000000001', '97111111-1111-1111-1111-111111111111',
            '10000000-0000-0000-0000-000000000003','2026-09-01','09:00','17:00',
            '10000000-0000-0000-0000-000000000002')$$,
  'admin can insert a shift for a staff member');

select lives_ok(
  $$insert into public.staff_shifts
      (property_id, id, staff_id, shift_date, start_time, end_time, created_by)
    values ('a0000000-0000-0000-0000-000000000001', '97222222-2222-2222-2222-222222222222',
            '10000000-0000-0000-0000-000000000004','2026-09-02','10:00','18:00',
            '10000000-0000-0000-0000-000000000002')$$,
  'admin can insert a shift for an accountant');

select lives_ok(
  $$update public.staff_shifts set notes = 'cover shift'
    where id = '97111111-1111-1111-1111-111111111111'$$,
  'admin can update any shift');

reset role;
select is(
  (select notes from public.staff_shifts
    where id = '97111111-1111-1111-1111-111111111111'),
  'cover shift',
  'the update is visible directly on the table');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

-- RLS (staff_shifts_update/_delete are admin-only) filters these: no
-- error, no row changed.
select is(pg_temp.rows_affected(
  $$update public.staff_shifts set notes = 'nope'
    where id = '97111111-1111-1111-1111-111111111111'$$),
  0, 'a staff member cannot update their own shift row');

select is(pg_temp.rows_affected(
  $$delete from public.staff_shifts
    where id = '97111111-1111-1111-1111-111111111111'$$),
  0, 'a staff member cannot delete their own shift row');

-- === the time-order check constraint ========================================

reset role;
select throws_like(
  $$insert into public.staff_shifts
      (property_id, staff_id, shift_date, start_time, end_time, created_by)
    values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003','2026-09-03','17:00','09:00',
            '10000000-0000-0000-0000-000000000002')$$,
  '%staff_shifts_time_order%',
  'a shift with end_time before start_time is rejected');

-- === reads: own-row only for staff/accountant, everything for admin ========

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  (select count(*)::int from public.staff_shifts),
  1,
  'a staff member sees only their own shift row via direct select');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.staff_shifts),
  2,
  'admin sees every shift row via direct select');

-- === list_staff_shifts(): same visibility rules, plus filtering ============

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  (select count(*)::int from public.list_staff_shifts()),
  1,
  'a staff member calling list_staff_shifts() with no filter sees only '
  'their own shift');

select is(
  (select count(*)::int from public.list_staff_shifts(
    p_staff_id => '10000000-0000-0000-0000-000000000004')),
  0,
  'passing another staff member''s id does not leak their shift -- RLS, '
  'not the function''s own filter, decides visibility');

select is(
  (select staff_name from public.list_staff_shifts()
    where id = '97111111-1111-1111-1111-111111111111'),
  'Sita Staff',
  'list_staff_shifts joins in the staff member''s full_name from profiles');

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.list_staff_shifts(
    p_staff_id => '10000000-0000-0000-0000-000000000004')),
  1,
  'admin filtering by staff_id sees exactly that staff member''s shift');

select is(
  (select count(*)::int from public.list_staff_shifts(p_from => '2026-09-02')),
  1,
  'admin filtering by p_from excludes earlier shifts');

-- === created_by defaults to the inserting admin (matches exactly what the ===
-- === real Dart repository sends: no id, no created_by) ======================
--
-- Still authenticated as the admin (10000000-...-0002) from above. staff_id
-- must reference a seeded profile (FK), so it can't itself be the fresh
-- fixture id -- the fresh id (97333333...) is instead embedded in `notes`
-- purely so this row can be picked back out unambiguously, the same role
-- the explicit `id` plays in the insert tests above. This block runs after
-- all the row-count assertions above so the extra row doesn't perturb them.

select lives_ok(
  $$insert into public.staff_shifts
      (property_id, staff_id, shift_date, start_time, end_time, notes)
    values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003','2026-09-04','09:00','17:00',
            'fixture-97333333-3333-3333-3333-333333333333')$$,
  'admin can insert a shift omitting id and created_by, matching the real '
  'payload the Dart repository sends');

select is(
  (select created_by from public.staff_shifts
    where notes = 'fixture-97333333-3333-3333-3333-333333333333'),
  '10000000-0000-0000-0000-000000000002'::uuid,
  'created_by defaults to auth.uid(), i.e. the inserting admin, when the '
  'client omits it entirely');

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.list_staff_shifts()$$,
  '42501', null, 'anon cannot call list_staff_shifts');

select * from finish();
rollback;
