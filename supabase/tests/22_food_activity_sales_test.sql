-- food_activity_sales + report_food_sales, added in
-- 0026_food_activity_sales.sql.

begin;
select plan(12);

select has_table('public', 'food_activity_sales', 'food_activity_sales table exists');
select has_function('public', 'report_food_sales', 'report_food_sales exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000022','P22','p22');

-- The seed users' roles are memberships at the seed resort only; give them
-- the same roles at this file's property.
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000001','owner'),
  ('aaaaaaaa-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000002','admin'),
  ('aaaaaaaa-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000003','staff'),
  ('aaaaaaaa-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000004','accountant');

-- === insert: staff-or-above ==================================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$insert into public.food_activity_sales
      (id, property_id, sale_date, category, item_name, quantity, unit_price, amount)
    values ('98111111-1111-1111-1111-111111111111',
            'aaaaaaaa-0000-0000-0000-000000000022', current_date, 'food',
            'Breakfast platter', 2, 300, 600)$$,
  'staff can log a food sale'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select throws_ok(
  $$insert into public.food_activity_sales
      (property_id, sale_date, category, item_name, quantity, unit_price, amount)
    values ('aaaaaaaa-0000-0000-0000-000000000022', current_date, 'activity',
            'Kayaking', 1, 500, 500)$$,
  '42501', null, 'a customer cannot log a sale'
);

-- === update/delete: admin-only ===============================================
--
-- Both policies are a plain `using (is_admin())` (not the `using (true)` +
-- enforcement-trigger pattern `tasks_admin_delete` uses), so a non-admin's
-- attempt matches zero rows rather than throwing -- same "silently affects
-- zero rows, not insecure" shape `20_tasks_test.sql` proves for the
-- analogous case.

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

with attempted as (
  update public.food_activity_sales set amount = 700
  where id = '98111111-1111-1111-1111-111111111111'
  returning 1
)
select is(
  (select count(*)::int from attempted),
  0,
  'staff cannot correct a sale they logged -- admin-only, matches zero rows'
);

with attempted as (
  delete from public.food_activity_sales
  where id = '98111111-1111-1111-1111-111111111111'
  returning 1
)
select is(
  (select count(*)::int from attempted),
  0,
  'staff cannot delete a sale -- admin-only, matches zero rows'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$update public.food_activity_sales set amount = 650
    where id = '98111111-1111-1111-1111-111111111111'$$,
  'admin can correct a sale'
);

-- === report_food_sales aggregation ===========================================

insert into public.food_activity_sales
  (property_id, sale_date, category, item_name, quantity, unit_price, amount)
values
  ('aaaaaaaa-0000-0000-0000-000000000022', current_date, 'food', 'Lunch thali', 3, 250, 750);

select is(
  (select sum(items_sold) from public.report_food_sales(
    current_date, current_date, 'aaaaaaaa-0000-0000-0000-000000000022'))::int,
  5,
  'report_food_sales sums quantity across matching rows'
);

select is(
  (select sum(gross) from public.report_food_sales(
    current_date, current_date, 'aaaaaaaa-0000-0000-0000-000000000022'))::numeric,
  1400::numeric,
  'report_food_sales sums the corrected + new sale amounts'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';

select throws_ok(
  $$select public.report_food_sales(current_date, current_date)$$,
  'P0008', null, 'a customer cannot call report_food_sales'
);

reset role;

-- === anon: no access ==========================================================

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.food_activity_sales$$,
  '42501', null, 'anon cannot select food_activity_sales'
);

select throws_ok(
  $$select public.report_food_sales(current_date, current_date)$$,
  '42501', null, 'anon cannot call report_food_sales -- revoked at the grant layer'
);

reset role;
select * from finish();
rollback;
