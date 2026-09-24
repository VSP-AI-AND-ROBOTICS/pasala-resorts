-- dashboard_summary()'s three additive keys, added in
-- 0030_owner_dashboard_summary.sql. `food_activity_sales`/`expenses` have
-- no seed data at all, so before this file's own insert both figures are
-- exactly zero -- safe to assert exact numbers, not just "at least".

begin;
select plan(6);

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000026','P26','p26');

-- The seed users' roles are memberships at the seed resort only; give them
-- the same roles at this file's property.
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000026','10000000-0000-0000-0000-000000000001','owner'),
  ('aaaaaaaa-0000-0000-0000-000000000026','10000000-0000-0000-0000-000000000002','admin'),
  ('aaaaaaaa-0000-0000-0000-000000000026','10000000-0000-0000-0000-000000000003','staff'),
  ('aaaaaaaa-0000-0000-0000-000000000026','10000000-0000-0000-0000-000000000004','accountant');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ->> 'food_sales_today')::numeric,
  0::numeric,
  'food_sales_today is zero with no sales logged yet'
);

select is(
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ->> 'expenses_month_total')::numeric,
  0::numeric,
  'expenses_month_total is zero with no expenses logged yet'
);

insert into public.food_activity_sales
  (property_id, sale_date, category, item_name, quantity, unit_price, amount)
values ('aaaaaaaa-0000-0000-0000-000000000026', current_date, 'food', 'Dinner', 1, 800, 800);

reset role;
insert into public.expenses (property_id, expense_date, category, description, amount)
values ('aaaaaaaa-0000-0000-0000-000000000026', current_date, 'supplies', 'Ice', 200);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ->> 'food_sales_today')::numeric,
  800::numeric,
  'food_sales_today reflects the sale just logged'
);

select is(
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ->> 'expenses_month_total')::numeric,
  200::numeric,
  'expenses_month_total reflects the expense just logged, even called by plain staff'
);

select is(
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ->> 'net_profit_month')::numeric,
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ->> 'month_revenue')::numeric - 200,
  'net_profit_month is month_revenue minus expenses_month_total'
);

-- Every existing key is untouched -- the extension is purely additive.
select ok(
  (public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ? 'today_revenue'
    and (public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ? 'occupancy_pct'
    and (public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000026')) ? 'active_holds',
  'every pre-existing dashboard_summary key is still present'
);

reset role;
select * from finish();
rollback;
