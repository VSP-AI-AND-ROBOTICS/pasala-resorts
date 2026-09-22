-- expenses + report_expenses, added in 0027_expenses.sql. Read access is
-- admin/accountant/super_admin only -- plain staff must not see this.

begin;
select plan(11);

select has_table('public', 'expenses', 'expenses table exists');
select has_function('public', 'report_expenses', 'report_expenses exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000023','P23','p23');

-- === insert/write: admin-only =================================================

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$insert into public.expenses (property_id, category, description, amount)
    values ('aaaaaaaa-0000-0000-0000-000000000023', 'utilities', 'Electricity bill', 5000)$$,
  '42501', null, 'plain staff cannot log an expense'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$insert into public.expenses (id, property_id, expense_date, category, description, amount)
    values ('99111111-1111-1111-1111-111111111111',
            'aaaaaaaa-0000-0000-0000-000000000023', current_date,
            'utilities', 'Electricity bill', 5000)$$,
  'admin can log an expense'
);

insert into public.expenses (property_id, expense_date, category, description, amount)
values ('aaaaaaaa-0000-0000-0000-000000000023', current_date, 'supplies', 'Cleaning supplies', 1200);

-- === read: admin/accountant/super_admin only, never plain staff =============

select is(
  (select count(*)::int from public.expenses
    where property_id = 'aaaaaaaa-0000-0000-0000-000000000023'),
  2,
  'admin sees every expense'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select is(
  (select count(*)::int from public.expenses
    where property_id = 'aaaaaaaa-0000-0000-0000-000000000023'),
  2,
  'accountant sees every expense too'
);

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  (select count(*)::int from public.expenses
    where property_id = 'aaaaaaaa-0000-0000-0000-000000000023'),
  0,
  'plain staff sees no expenses at all -- this is tighter than the sales log'
);

select throws_ok(
  $$select public.report_expenses(current_date, current_date)$$,
  'P0008', null, 'plain staff cannot call report_expenses'
);

-- === report_expenses aggregation ==============================================

set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';

select is(
  (select sum(total) from public.report_expenses(
    current_date, current_date, 'aaaaaaaa-0000-0000-0000-000000000023'))::numeric,
  6200::numeric,
  'report_expenses sums both logged expenses for the accountant'
);

reset role;

-- === anon: no access ==========================================================

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok(
  $$select * from public.expenses$$,
  '42501', null, 'anon cannot select expenses'
);

select throws_ok(
  $$select public.report_expenses(current_date, current_date)$$,
  '42501', null, 'anon cannot call report_expenses -- revoked at the grant layer'
);

reset role;
select * from finish();
rollback;
