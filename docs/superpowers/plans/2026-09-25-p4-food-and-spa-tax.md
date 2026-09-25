# Food and Spa Tax (P4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each resort sets a food & drink tax rate and a spa & activities tax rate (0–28%). Prices already include these taxes. Every food order, order item, activity booking and walk-in sale stores its tax when it is made. The Finance Ledger, the Today tab and the guest's bill show tax per category.

**Architecture:** Migration `0053_food_spa_tax.sql` adds `properties.fnb_tax_pct`/`spa_tax_pct` and `tax_pct`/`tax_amount` on four sale tables. One `immutable` helper, `inclusive_tax(amount, pct)`, does the maths. Four `before insert or update` triggers fill the tax columns, so `place_food_order`, `book_activity` and the walk-in form do not change, and a client never sets tax. A `properties` trigger raises P0035 for out-of-range rates. `current_charges`, `report_ledger` and `finance_summary` are re-created to report tax by category. On the app side, the models read the new keys (0 when missing). The Taxes screen edits both rates. The Ledger, the Today tab and CSV, the guest's Current Charges and Final Invoice, and the walk-in sales list show the tax.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`), Flutter 3.44 / Dart 3.10, Riverpod 3.3, intl.

**Spec:** `docs/superpowers/specs/2026-09-25-p4-food-and-spa-tax-design.md`

## Global Constraints

- Cut this plan's branch from `feat/gaps`. Other gap projects (P1 `0051`, P3 `0052`, P6 `0055`, …) may or may not have merged. This plan depends on none of them.
- One migration: `supabase/migrations/0053_food_spa_tax.sql`. Tasks 1–3 each edit it. After every edit, rebuild with `supabase db reset` (it re-runs every migration and `supabase/seed.sql`), then run pgTAP. Before the first reset, dump local data if you need it: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-p4.sql`.
- New pgTAP file: `supabase/tests/44_food_spa_tax_test.sql`. All fixtures are at the top (Task 1). Tasks 2 and 3 each append one section and bump `plan(...)`. Each section relies on the state the sections before it leave. Run one file with `supabase test db supabase/tests/44_food_spa_tax_test.sql` and the whole suite with `supabase test db`.
- Error code: **P0035** with the message `tax_rate_out_of_range`, raised by `properties_check_service_tax()`. No other new codes. The existing codes keep their meaning.
- Rates: `numeric(5,2)`, default 0, allowed range **0 to 28** (inclusive). The room rate `properties.tax_pct` keeps its 0–100 range and its meaning (tax added on top at booking).
- Tax inside a price: `round(amount * pct / (100 + pct), 2)` (`public.inclusive_tax`). 105 at 5% → 5.00; 200 at 18% → 30.51; 1 at 5% → 0.05.
- Rate fixing: on **insert**, the trigger reads the resort's current rate (food & drink for `food_orders`, `food_order_items` via their order, and `food` walk-in sales; spa & activities for `activity_bookings` and `activity` walk-in sales). On **update** it keeps `old.tax_pct`. The one exception: a walk-in sale whose `category` changes takes the current rate of its new category. `tax_amount` is always worked out again from the row's amount (`total`, `line_total` or `amount`).
- No new `security definer` functions. The trigger functions and `inclusive_tax` run with the caller's rights. `supabase/tests/37_tenancy_isolation_test.sql` does not change. Trigger functions: `set search_path = public, pg_temp`, `execute` revoked from `public, anon, authenticated`. `inclusive_tax`: revoked from `public, anon`, granted to `authenticated`.
- Copy a re-created function from its **latest** definition on your branch: `current_charges` from `0045_resort_functions.sql`, and `report_ledger` and `finance_summary` from `0048_finance_ledger.sql`. Task 3 Step 1 checks that nothing newer exists.
- No existing policy or table grant is widened.
- pgTAP conventions (from `37_tenancy_isolation_test.sql`): switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`. `pg_temp.rows_affected(sql)` returns the rows a statement changed as the current role (0 when RLS filters it).
- Dart: repositories wrap every call in `_guard` → `mapPostgrestError` (`lib/core/errors.dart`). Every new model field defaults to 0 when its key is missing. Widget tests never use a real `SupabaseClient`.
- Money: finance figures and tax lines keep their paise, with `formatMoney` from `lib/features/finance/finance_tables.dart` (`₹22.50`). Guest bill lines keep `formatInr` (`₹630`).
- UI copy, exact:
  - Taxes screen fields: `Room tax rate (%)` (helper `Added on top of the room price at booking time`), `Food & drink tax (%)` (helper `Already included in menu prices`), `Spa & activities tax (%)` (helper `Already included in activity prices`), `GSTIN` (helper `Optional`). Note: `Each order and sale keeps the rate it was made at. Changing a rate affects new sales only.`
  - Taxes screen errors: `Enter a room tax rate between 0 and 100.`, `Enter a food & drink tax rate between 0 and 28.`, `Enter a spa & activities tax rate between 0 and 28.`
  - P0035: `Food and spa tax rates must be between 0% and 28%.`
  - Owner Settings tile subtitle: `Room, food and spa tax rates, GSTIN`.
  - Ledger: tax columns `Room tax`, `F&B tax`, `Spa/Activities tax`, `Ancillary tax` (then `Tax`). Strip rates: `Room rate 12%`, `F&B rate 5%`, `Spa/Activities rate 18%`. Strip note: `Each booking and sale keeps the rate it was made at.`
  - Today cards: `F&B tax`, `Spa tax`. Today CSV lines: `F&B tax`, `Spa tax` after `Room tax`.
  - Owner export centre Ledger subtitle: `Revenue and tax by category`.
  - Guest bill and walk-in list: `Includes tax ₹22.50`.
- Commands: `flutter test <path>`, `flutter test`, `flutter analyze` (no new issues beyond the baseline recorded in Task 1 Step 1). Never run `dart format` over whole directories (the repo is not formatted with the current SDK). Format only the lines you write.
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (the commit commands below pass it as a second `-m`).

## Review Focus

1. **A rate typed as `NaN`, `18%`, `5,5` or left blank on the Taxes screen.** `num.tryParse('NaN')` returns a NaN that passes both `< 0` and `> 28` checks. The screen must refuse every one of these inline and save nothing. Owning test: Task 4 (`a rate that is not a number is refused`).
2. **Kitchen or desk staff sending `tax_pct`/`tax_amount` in a direct PostgREST update or insert** (the `food_orders_update` and `food_activity_sales_insert`/`_update` policies let them write whole rows). The stored tax must not change. Owning tests: Task 2 (`the tax cannot be changed by an update`, `the sale records the current food rate, not what was sent`, `a sale's tax cannot be changed by an update`).
3. **An admin corrects a walk-in sale's amount after the resort changed its rate.** The sale must keep the rate it was sold at and only its tax amount follows the new amount. Owning test: Task 2 (`the corrected sale keeps the 12% it was sold at`).
4. **A cancelled order or activity booking on the guest's bill.** Its tax must leave `food_tax`/`activity_tax`, just as its amount leaves the total. Owning tests: Task 3 (`a massage for one that was cancelled is not on the bill`, `a cancelled order's tax leaves the bill`).
5. **The app talking to a server without this migration** (or a cached old row). Missing `fnb_tax_pct`, `food_tax`, `tax_amount`… must read as 0, with no tax line shown, never a crash. Owning tests: Task 1 (`… without the … keys reads them as 0` in each model test) and Task 6 (`no tax line when there is no tax`).

## Execution tracks

After Task 1, the database track and the app track share no files and can run in parallel, for example in two worktrees branched from Task 1's commit and merged back before Task 8. App tasks never need a database: their tests use provider overrides and fakes.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | — | `0053` (columns, `inclusive_tax` stub), `44` (fixtures + contract), `property.dart`, `current_charges.dart`, `finance.dart`, `food_sale.dart`, `errors.dart`, `fake_finance_source.dart`, their tests |
| 2 Tax stored on every sale | DB | 1 | `0053`, `44` |
| 3 Bill, Ledger and summary by category | DB | 2 | `0053`, `44` |
| 4 Taxes screen | App | 1 | `tax_settings_screen.dart`, `owner_settings_screen.dart`, `tax_settings_screen_test.dart` |
| 5 Finance: tax per category | App | 1 | `finance_tables.dart`, `finance_ledger_tab.dart`, `finance_today_tab.dart`, `finance_csv.dart`, `owner_reports_screen.dart`, their tests |
| 6 Guest bill tax lines | App | 1 | `included_tax_line.dart`, `current_charges_screen.dart`, `final_invoice_screen.dart`, their tests |
| 7 Walk-in sale tax | App | 1 | `food_sales_screen.dart`, `food_sales_screen_test.dart` |
| 8 Integration | both | 2–7 | none (verification) |

- The database track is strictly sequential: Tasks 2 and 3 share one migration file, one test file and one local Postgres.
- The app tasks 4, 5, 6 and 7 touch disjoint files and can run in any order or in parallel.

---

## File Structure

**Database**
- Create `supabase/migrations/0053_food_spa_tax.sql`: the rate columns and checks, the four pairs of tax columns, `inclusive_tax`, the four tax triggers, the P0035 rate guard, and the re-created `current_charges`, `report_ledger`, `finance_summary`.
- Create `supabase/tests/44_food_spa_tax_test.sql`: fixtures, contract, stored tax, reports.

**App**
- Modify `lib/data/models/property.dart`: `fnbTaxPct`, `spaTaxPct`.
- Modify `lib/data/models/current_charges.dart`: `foodTax`, `activityTax`.
- Modify `lib/data/models/finance.dart`: `FinanceResort.fnbTaxPct`/`spaTaxPct`, `FinanceSummary.foodTax`/`spaTax`.
- Modify `lib/data/models/food_sale.dart`: `taxPct`, `taxAmount` (read-only).
- Modify `lib/core/errors.dart`: `TaxRateOutOfRange` (P0035).
- Modify `lib/features/owner/tax_settings_screen.dart` and `lib/features/owner/owner_settings_screen.dart`: the two new rates.
- Modify `lib/features/finance/finance_tables.dart`, `finance_ledger_tab.dart`, `finance_today_tab.dart`, `finance_csv.dart`, and `lib/features/owner/owner_reports_screen.dart`: tax per category.
- Create `lib/features/stay/included_tax_line.dart`. Modify `lib/features/stay/current_charges_screen.dart`, `lib/features/stay/final_invoice_screen.dart`: tax lines on the guest's bill.
- Modify `lib/features/owner/food_sales_screen.dart`: a sale's tax on its row.
- Modify `test/support/fake_finance_source.dart`: the new summary fields.
- Tests: create `test/data/current_charges_test.dart`, `test/features/owner/tax_settings_screen_test.dart`, `test/features/stay/current_charges_screen_test.dart`, `test/features/stay/final_invoice_screen_test.dart`. Modify `test/data/property_test.dart`, `test/data/finance_test.dart`, `test/data/food_sale_test.dart`, `test/core/errors_test.dart`, `test/features/finance/finance_tables_test.dart`, `test/features/finance/finance_screen_test.dart`, `test/features/finance/finance_csv_test.dart`, `test/features/owner/food_sales_screen_test.dart`.

---

## Phase 0: Interface

### Task 1: Interface contract (schema, helper signature, Dart models)

**Track:** both. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0053_food_spa_tax.sql`
- Create: `supabase/tests/44_food_spa_tax_test.sql`
- Modify: `lib/data/models/property.dart`, `lib/data/models/current_charges.dart`, `lib/data/models/finance.dart`, `lib/data/models/food_sale.dart`, `lib/core/errors.dart`, `test/support/fake_finance_source.dart`
- Test: `test/data/property_test.dart`, `test/data/current_charges_test.dart` (new), `test/data/finance_test.dart`, `test/data/food_sale_test.dart`, `test/core/errors_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - SQL columns: `properties.fnb_tax_pct numeric(5,2) not null default 0`, `properties.spa_tax_pct numeric(5,2) not null default 0` (checks `properties_fnb_tax_pct_range`, `properties_spa_tax_pct_range`: 0..28); on each of `food_orders`, `food_order_items`, `activity_bookings`, `food_activity_sales`: `tax_pct numeric(5,2) not null default 0` (0..28), `tax_amount numeric(12,2) not null default 0` (>= 0).
  - SQL function: `public.inclusive_tax(p_amount numeric, p_pct numeric) returns numeric`, `immutable`, not `security definer`, executable by `authenticated` only. A stub raising `0A000` until Task 2.
  - JSON keys the database tasks will return (the app reads them now, 0 when missing): `current_charges` → `food_tax`, `activity_tax`; `finance_summary` → `food_tax`, `spa_tax`, and `resort.fnb_tax_pct`, `resort.spa_tax_pct`; `properties` rows → `fnb_tax_pct`, `spa_tax_pct`; `food_activity_sales` rows → `tax_pct`, `tax_amount`.
  - Dart: `Property.fnbTaxPct`, `Property.spaTaxPct` (`num`, default 0); `CurrentCharges.foodTax`, `CurrentCharges.activityTax` (`double`, default 0); `FinanceResort.fnbTaxPct`, `FinanceResort.spaTaxPct` (`num`, default 0); `FinanceSummary.foodTax`, `FinanceSummary.spaTax` (`num`, default 0); `FoodSale.taxPct`, `FoodSale.taxAmount` (`num`, default 0, never in `toInsert()`); `class TaxRateOutOfRange extends BookingFailure` for `P0035`; test helpers `financeResort({…, num fnbTaxPct = 0, num spaTaxPct = 0})` and `financeSummary({…, num foodTax = 0, num spaTax = 0})`.

- [ ] **Step 1: Record the baseline**

```bash
git log --oneline -1
supabase status
flutter analyze 2>&1 | tail -1
```

Expected: `supabase status` shows the local stack running (start it with `supabase start` if not). Write down the issue count `flutter analyze` prints; later steps must not add to it.

- [ ] **Step 2: Write the failing contract test**

Create `supabase/tests/44_food_spa_tax_test.sql`:

```sql
-- Food and spa tax (P4), added in 0053_food_spa_tax.sql.
-- See docs/superpowers/specs/2026-09-25-p4-food-and-spa-tax-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Resort T (Asia/Kolkata, 12% room tax) has an owner (Olga), a staff
-- member (Sita) and an accountant (Anil). Gita is a guest: R1 is her stay
-- in Cottage 1, checked in since yesterday (a total-only quote of 5,000,
-- nothing paid); R2 is her booking of Cottage 2 arriving at 14:00 today
-- (2,000 of room at 12% = 240 tax, total 2,240).
begin;
select plan(20);

-- Rows a statement changed, run as the current role (0 when RLS filters it).
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

-- Before any fixture: every row that existed before 0053 carries no tax.
select is(
  (select count(*)::int from (
     select tax_pct, tax_amount from public.food_orders
     union all select tax_pct, tax_amount from public.food_order_items
     union all select tax_pct, tax_amount from public.activity_bookings
     union all select tax_pct, tax_amount from public.food_activity_sales) t
    where t.tax_pct <> 0 or t.tax_amount <> 0),
  0, 'every row that existed before 0053 has tax 0');

insert into auth.users (id, email) values
  ('44000000-0000-0000-0000-000000000001','tax-owner@example.com'),
  ('44000000-0000-0000-0000-000000000002','tax-staff@example.com'),
  ('44000000-0000-0000-0000-000000000003','tax-accountant@example.com'),
  ('44000000-0000-0000-0000-000000000004','tax-gita@example.com');

insert into public.properties (id, name, slug, tax_pct) values
  ('44444444-0000-4000-8000-000000000001','Resort T','tax-t',12);

insert into public.resort_members (property_id, user_id, role) values
  ('44444444-0000-4000-8000-000000000001','44000000-0000-0000-0000-000000000001','owner'),
  ('44444444-0000-4000-8000-000000000001','44000000-0000-0000-0000-000000000002','staff'),
  ('44444444-0000-4000-8000-000000000001','44000000-0000-0000-0000-000000000003','accountant');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('44444444-0000-4000-8000-000000000011','44444444-0000-4000-8000-000000000001','Cottage 1',2,4),
  ('44444444-0000-4000-8000-000000000012','44444444-0000-4000-8000-000000000001','Cottage 2',2,4);

insert into public.food_categories (id, property_id, name) values
  ('44444444-0000-4000-8000-000000000021','44444444-0000-4000-8000-000000000001','Mains');
insert into public.food_items (id, category_id, name, price) values
  ('44444444-0000-4000-8000-000000000031','44444444-0000-4000-8000-000000000021','Thali',210),
  ('44444444-0000-4000-8000-000000000032','44444444-0000-4000-8000-000000000021','Lassi',105);

insert into public.activities (id, property_id, name, price_per_person, capacity_per_slot) values
  ('44444444-0000-4000-8000-000000000041','44444444-0000-4000-8000-000000000001','Spa massage',1180,4);

insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, checked_in_at) values
  ('44444444-0000-4000-8000-000000000051','44444444-0000-4000-8000-000000000011',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','44000000-0000-0000-0000-000000000004',2,
   '{"total":5000}', now() - interval '1 day');
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote) values
  ('44444444-0000-4000-8000-000000000052','44444444-0000-4000-8000-000000000012',
   tstzrange(((now() at time zone 'Asia/Kolkata')::date + time '14:00') at time zone 'Asia/Kolkata',
             ((now() at time zone 'Asia/Kolkata')::date + 1 + time '11:00') at time zone 'Asia/Kolkata', '[)'),
   'booking','confirmed','44000000-0000-0000-0000-000000000004',2,
   '{"subtotal":2000,"cleaning_fee":0,"coupon":null,"tax_pct":12,"tax_amount":240,"total":2240}');

-- ---------------------------------------------------------------------
-- Task 1: the contract.

select col_type_is('public','properties','fnb_tax_pct','numeric(5,2)',
  'properties.fnb_tax_pct is numeric(5,2)');
select col_type_is('public','properties','spa_tax_pct','numeric(5,2)',
  'properties.spa_tax_pct is numeric(5,2)');
select col_has_check('public','properties','fnb_tax_pct',
  'properties.fnb_tax_pct has a range check');
select col_has_check('public','properties','spa_tax_pct',
  'properties.spa_tax_pct has a range check');
select is((select fnb_tax_pct + spa_tax_pct from public.properties
            where id = '44444444-0000-4000-8000-000000000001'),
  0::numeric, 'a resort starts with food and spa rates of 0');

select col_type_is('public','food_orders','tax_pct','numeric(5,2)','food_orders.tax_pct is numeric(5,2)');
select col_type_is('public','food_orders','tax_amount','numeric(12,2)','food_orders.tax_amount is numeric(12,2)');
select col_type_is('public','food_order_items','tax_pct','numeric(5,2)','food_order_items.tax_pct is numeric(5,2)');
select col_type_is('public','food_order_items','tax_amount','numeric(12,2)','food_order_items.tax_amount is numeric(12,2)');
select col_type_is('public','activity_bookings','tax_pct','numeric(5,2)','activity_bookings.tax_pct is numeric(5,2)');
select col_type_is('public','activity_bookings','tax_amount','numeric(12,2)','activity_bookings.tax_amount is numeric(12,2)');
select col_type_is('public','food_activity_sales','tax_pct','numeric(5,2)','food_activity_sales.tax_pct is numeric(5,2)');
select col_type_is('public','food_activity_sales','tax_amount','numeric(12,2)','food_activity_sales.tax_amount is numeric(12,2)');
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public'
      and table_name in ('food_orders','food_order_items','activity_bookings','food_activity_sales')
      and column_name in ('tax_pct','tax_amount')
      and is_nullable = 'NO' and column_default is not null),
  8, 'the eight tax columns are not null and have a default');

select has_function('public','inclusive_tax',array['numeric','numeric'],
  'inclusive_tax(numeric, numeric) exists');
select function_returns('public','inclusive_tax',array['numeric','numeric'],'numeric',
  'inclusive_tax returns numeric');
select isnt_definer('public','inclusive_tax',array['numeric','numeric'],
  'inclusive_tax is not security definer');
select ok(has_function_privilege('authenticated','public.inclusive_tax(numeric, numeric)','execute'),
  'authenticated may call inclusive_tax');
select ok(not has_function_privilege('anon','public.inclusive_tax(numeric, numeric)','execute'),
  'anon may not call inclusive_tax');

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to see it fail**

Run: `supabase test db supabase/tests/44_food_spa_tax_test.sql`
Expected: FAIL: `column "tax_pct" does not exist` at test 1.

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/0053_food_spa_tax.sql`:

```sql
-- Food and spa tax (P4): a food & drink rate and a spa & activities rate
-- per resort, and the tax inside every food order, order item, activity
-- booking and walk-in sale, stored on the row when it is made.
-- See docs/superpowers/specs/2026-09-25-p4-food-and-spa-tax-design.md.
--
-- Prices include tax: the tax inside a price is price * pct / (100 + pct),
-- rounded to paise (public.inclusive_tax). Triggers fill tax_pct and
-- tax_amount on every insert and update, so place_food_order,
-- book_activity and the walk-in sales form work unchanged, and a client
-- never sets tax. Rows that exist before this migration keep tax 0.
--
-- Error code raised: P0035 tax_rate_out_of_range.

-- ---------------------------------------------------------------------
-- Rates. 0 to 28, the highest GST slab. properties.tax_pct stays the
-- room rate, added on top at booking time (0025, get_quote).
alter table public.properties
  add column fnb_tax_pct numeric(5,2) not null default 0
    constraint properties_fnb_tax_pct_range check (fnb_tax_pct >= 0 and fnb_tax_pct <= 28),
  add column spa_tax_pct numeric(5,2) not null default 0
    constraint properties_spa_tax_pct_range check (spa_tax_pct >= 0 and spa_tax_pct <= 28);

-- ---------------------------------------------------------------------
-- The tax inside each sale, at the rate of the day it was made. Adding a
-- column with a default fills existing rows with 0 and fires no trigger.
alter table public.food_orders
  add column tax_pct numeric(5,2) not null default 0
    constraint food_orders_tax_pct_range check (tax_pct >= 0 and tax_pct <= 28),
  add column tax_amount numeric(12,2) not null default 0
    constraint food_orders_tax_amount_nonneg check (tax_amount >= 0);

alter table public.food_order_items
  add column tax_pct numeric(5,2) not null default 0
    constraint food_order_items_tax_pct_range check (tax_pct >= 0 and tax_pct <= 28),
  add column tax_amount numeric(12,2) not null default 0
    constraint food_order_items_tax_amount_nonneg check (tax_amount >= 0);

alter table public.activity_bookings
  add column tax_pct numeric(5,2) not null default 0
    constraint activity_bookings_tax_pct_range check (tax_pct >= 0 and tax_pct <= 28),
  add column tax_amount numeric(12,2) not null default 0
    constraint activity_bookings_tax_amount_nonneg check (tax_amount >= 0);

alter table public.food_activity_sales
  add column tax_pct numeric(5,2) not null default 0
    constraint food_activity_sales_tax_pct_range check (tax_pct >= 0 and tax_pct <= 28),
  add column tax_amount numeric(12,2) not null default 0
    constraint food_activity_sales_tax_amount_nonneg check (tax_amount >= 0);

-- ---------------------------------------------------------------------
-- The tax inside a tax-inclusive price. Not security definer: the
-- walk-in trigger runs as the staff member and calls it.
-- CONTRACT STUB: Task 2 replaces this body.
create function public.inclusive_tax(p_amount numeric, p_pct numeric)
returns numeric
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  raise exception 'inclusive_tax is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.inclusive_tax(numeric, numeric) from public, anon;
grant execute on function public.inclusive_tax(numeric, numeric) to authenticated;
```

- [ ] **Step 5: Rebuild and run the contract test**

Run: `supabase db reset && supabase test db supabase/tests/44_food_spa_tax_test.sql`
Expected: PASS, `1..20`, all ok.

- [ ] **Step 6: Run the whole database suite**

Run: `supabase test db`
Expected: PASS. Nothing calls `inclusive_tax` yet, and every existing suite sees the new columns only as extra columns.

- [ ] **Step 7: Write the failing Dart model tests**

Append to `test/data/property_test.dart`, inside `main()` after the existing `group(...)`:

```dart
  group('Property.fromJson tax rates', () {
    test('reads the food and spa rates', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala',
        'slug': 'pasala',
        'images': [],
        'amenities': [],
        'tax_pct': 12,
        'fnb_tax_pct': 5,
        'spa_tax_pct': 18.5,
      });

      expect(property.taxPct, 12);
      expect(property.fnbTaxPct, 5);
      expect(property.spaTaxPct, 18.5);
    });

    test('a row without the food and spa keys reads them as 0', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala',
        'slug': 'pasala',
        'images': [],
        'amenities': [],
      });

      expect(property.fnbTaxPct, 0);
      expect(property.spaTaxPct, 0);
    });
  });
```

Create `test/data/current_charges_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/current_charges.dart';

void main() {
  test('reads the tax inside food and activities', () {
    final charges = CurrentCharges.fromJson(const {
      'stay_amount': 5000,
      'food_amount': 630,
      'food_tax': 36.25,
      'activity_amount': 2360,
      'activity_tax': 360,
      'total': 7990,
      'paid': 0,
      'balance': 7990,
    });

    expect(charges.foodAmount, 630);
    expect(charges.foodTax, 36.25);
    expect(charges.activityAmount, 2360);
    expect(charges.activityTax, 360);
    expect(charges.total, 7990);
  });

  test('a server without the tax keys reads them as 0', () {
    final charges = CurrentCharges.fromJson(const {
      'stay_amount': 3000,
      'food_amount': 0,
      'activity_amount': 0,
      'total': 3000,
      'paid': 1000,
      'balance': 2000,
    });

    expect(charges.foodTax, 0);
    expect(charges.activityTax, 0);
  });
}
```

Append to `test/data/finance_test.dart`, as the last statements inside `main()`:

```dart
  test("reads the food and spa rates and today's food and spa tax", () {
    final s = FinanceSummary.fromJson(const {
      'resort': {
        'name': 'Resort T',
        'slug': 'tax-t',
        'gstin': null,
        'tax_pct': 12,
        'fnb_tax_pct': 12,
        'spa_tax_pct': 18,
        'timezone': 'Asia/Kolkata',
        'today': '2026-09-25',
      },
      'room_tax': 240,
      'food_tax': 72.25,
      'spa_tax': 468,
    });

    expect(s.resort.fnbTaxPct, 12);
    expect(s.resort.spaTaxPct, 18);
    expect(s.roomTax, 240);
    expect(s.foodTax, 72.25);
    expect(s.spaTax, 468);
  });

  test('a summary without the food and spa keys reads them as 0', () {
    final s = FinanceSummary.fromJson(const {
      'resort': {
        'name': 'Resort S',
        'slug': 'fin-s',
        'gstin': null,
        'tax_pct': 0,
        'timezone': 'Asia/Kolkata',
        'today': '2026-09-25',
      },
    });

    expect(s.resort.fnbTaxPct, 0);
    expect(s.resort.spaTaxPct, 0);
    expect(s.foodTax, 0);
    expect(s.spaTax, 0);
  });
```

Append to `test/data/food_sale_test.dart`, as the last statements inside `main()`:

```dart
  test('reads the tax the server stored on the sale', () {
    final sale = FoodSale.fromJson({..._row('cash'), 'tax_pct': 12, 'tax_amount': 22.5});

    expect(sale.taxPct, 12);
    expect(sale.taxAmount, 22.5);
  });

  test('a row without the tax keys reads them as 0, and tax is never sent', () {
    final sale = FoodSale.fromJson(_row('cash'));

    expect(sale.taxPct, 0);
    expect(sale.taxAmount, 0);
    expect(sale.toInsert().keys, isNot(contains('tax_pct')));
    expect(sale.toInsert().keys, isNot(contains('tax_amount')));
  });
```

Append to `test/core/errors_test.dart`, after the `P0031` test:

```dart
  test('P0035 maps to TaxRateOutOfRange with readable copy', () {
    final failure = map('P0035', 'tax_rate_out_of_range');
    expect(failure, isA<TaxRateOutOfRange>());
    expect(failure.message, 'Food and spa tax rates must be between 0% and 28%.');
  });
```

- [ ] **Step 8: Run them to see them fail**

Run: `flutter test test/data/property_test.dart test/data/current_charges_test.dart test/data/finance_test.dart test/data/food_sale_test.dart test/core/errors_test.dart`
Expected: FAIL to compile: `The getter 'fnbTaxPct' isn't defined for the type 'Property'` (and the same for `foodTax`, `taxPct`, `TaxRateOutOfRange`).

- [ ] **Step 9: Add the fields**

In `lib/data/models/property.dart`:

Constructor, after `this.gatewayDisplayName,`:

```dart
    this.fnbTaxPct = 0,
    this.spaTaxPct = 0,
```

Fields, after `final String? gatewayDisplayName;`:

```dart

  /// Food & drink and spa & activities GST rates (`0053_food_spa_tax.sql`),
  /// 0 to 28. Unlike [taxPct], which is added on top of the room price,
  /// these are already inside menu and activity prices; each order and sale
  /// stores the rate it was made at. Written by the Taxes screen through
  /// `CatalogRepository.updateSettings`.
  final num fnbTaxPct;
  final num spaTaxPct;
```

`fromJson`, after the `gatewayDisplayName:` line:

```dart
        fnbTaxPct: (json['fnb_tax_pct'] as num?) ?? 0,
        spaTaxPct: (json['spa_tax_pct'] as num?) ?? 0,
```

Replace `lib/data/models/current_charges.dart` with:

```dart
/// The live running bill for a stay, from the `current_charges` RPC --
/// computed fresh server-side on every call, never stored client-side
/// beyond the lifetime of one screen.
class CurrentCharges {
  const CurrentCharges({
    required this.stayAmount,
    required this.foodAmount,
    required this.activityAmount,
    required this.total,
    required this.paid,
    required this.balance,
    this.foodTax = 0,
    this.activityTax = 0,
  });

  final double stayAmount;
  final double foodAmount;
  final double activityAmount;
  final double total;
  final double paid;
  final double balance;

  /// The tax already inside [foodAmount] / [activityAmount]
  /// (`0053_food_spa_tax.sql`): each order and booking stores the tax of
  /// the rate it was made at. Not added to [total] -- it is part of it.
  /// 0 from a server without the keys.
  final double foodTax;
  final double activityTax;

  factory CurrentCharges.fromJson(Map<String, dynamic> json) => CurrentCharges(
        stayAmount: (json['stay_amount'] as num).toDouble(),
        foodAmount: (json['food_amount'] as num).toDouble(),
        activityAmount: (json['activity_amount'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
        paid: (json['paid'] as num).toDouble(),
        balance: (json['balance'] as num).toDouble(),
        foodTax: (json['food_tax'] as num?)?.toDouble() ?? 0,
        activityTax: (json['activity_tax'] as num?)?.toDouble() ?? 0,
      );
}
```

In `lib/data/models/finance.dart`, `FinanceResort`:

Constructor, after `required this.taxPct,`:

```dart
    this.fnbTaxPct = 0,
    this.spaTaxPct = 0,
```

`fromJson`, after `taxPct: _money(json['tax_pct']),`:

```dart
    fnbTaxPct: _money(json['fnb_tax_pct']),
    spaTaxPct: _money(json['spa_tax_pct']),
```

Fields, after `final num taxPct;`:

```dart

  /// The resort's current food & drink and spa & activities rates; each
  /// order and sale keeps its own rate.
  final num fnbTaxPct;
  final num spaTaxPct;
```

In `FinanceSummary`:

Constructor, after `required this.roomTax,`:

```dart
    this.foodTax = 0,
    this.spaTax = 0,
```

`fromJson`, after `roomTax: _money(json['room_tax']),`:

```dart
      foodTax: _money(json['food_tax']),
      spaTax: _money(json['spa_tax']),
```

Replace the `roomTax` doc comment and field:

```dart
  /// Today's tax on bookings (room and cleaning-fee lines together).
  final num roomTax;
```

with:

```dart
  /// Today's tax on bookings (room and cleaning-fee lines together).
  final num roomTax;

  /// Today's tax inside food & drink (in-stay orders and walk-ins) and
  /// inside spa & activities (bookings and walk-ins).
  final num foodTax;
  final num spaTax;
```

In `lib/data/models/food_sale.dart`, `FoodSale`:

Constructor, after `this.notes,`:

```dart
    this.taxPct = 0,
    this.taxAmount = 0,
```

Fields, after `final String? notes;`:

```dart

  /// The tax inside [amount] and its rate, set by the server when the sale
  /// is logged (`0053_food_spa_tax.sql`). Read-only: never in [toInsert].
  final num taxPct;
  final num taxAmount;
```

`fromJson`, after `notes: json['notes'] as String?,`:

```dart
        taxPct: (json['tax_pct'] as num?) ?? 0,
        taxAmount: (json['tax_amount'] as num?) ?? 0,
```

In `lib/core/errors.dart`, after the `AlreadyDispatched` class:

```dart

/// P0035 -- `properties_check_service_tax` refused a food or spa rate
/// outside 0..28. The Taxes screen checks the range first, so this is a
/// backstop.
class TaxRateOutOfRange extends BookingFailure {
  const TaxRateOutOfRange()
      : super('Food and spa tax rates must be between 0% and 28%.');
}
```

and in `mapPostgrestError`, after `'P0031' => const AlreadyDispatched(),`:

```dart
    // P0035: food and spa tax rates (0053). Bare code word from the server.
    'P0035' => const TaxRateOutOfRange(),
```

In `test/support/fake_finance_source.dart`, replace `financeResort`:

```dart
/// Resort R of the pgTAP file: slug `fin-r`, 12% tax, a GSTIN, today
/// 25 Sep 2026.
FinanceResort financeResort({
  String name = 'Resort R',
  String slug = 'fin-r',
  String? gstin = '29ABCDE1234F1Z5',
  num taxPct = 12,
  num fnbTaxPct = 0,
  num spaTaxPct = 0,
  String timezone = 'Asia/Kolkata',
  DateTime? today,
}) => FinanceResort(
  name: name,
  slug: slug,
  gstin: gstin,
  taxPct: taxPct,
  fnbTaxPct: fnbTaxPct,
  spaTaxPct: spaTaxPct,
  timezone: timezone,
  today: today ?? DateTime(2026, 9, 25),
);
```

and in `financeSummary`, add the parameters after `num roomTax = 0,`:

```dart
  num foodTax = 0,
  num spaTax = 0,
```

and the arguments after `roomTax: roomTax,`:

```dart
    foodTax: foodTax,
    spaTax: spaTax,
```

- [ ] **Step 10: Run the model tests and the analyzer**

Run: `flutter test test/data test/core/errors_test.dart && flutter analyze 2>&1 | tail -1`
Expected: PASS; the analyzer count equals the Step 1 baseline.

- [ ] **Step 11: Commit**

```bash
git add supabase/migrations/0053_food_spa_tax.sql supabase/tests/44_food_spa_tax_test.sql \
  lib/data/models/property.dart lib/data/models/current_charges.dart lib/data/models/finance.dart \
  lib/data/models/food_sale.dart lib/core/errors.dart test/support/fake_finance_source.dart \
  test/data/property_test.dart test/data/current_charges_test.dart test/data/finance_test.dart \
  test/data/food_sale_test.dart test/core/errors_test.dart
git commit -m "feat(tax): contract for food and spa tax (columns, inclusive_tax, models)" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase 1: Database track (Tasks 2 → 3, sequential)

### Task 2: Tax stored on every sale

**Track:** DB. Depends on Task 1.

**Files:**
- Modify: `supabase/migrations/0053_food_spa_tax.sql`
- Test: `supabase/tests/44_food_spa_tax_test.sql`

**Interfaces:**
- Consumes: the Task 1 columns and the `inclusive_tax(numeric, numeric)` signature.
- Produces: `inclusive_tax` returns `round(amount * pct / (100 + pct), 2)`; triggers `food_orders_set_tax`, `food_order_items_set_tax`, `activity_bookings_set_tax`, `food_activity_sales_set_tax` (all `before insert or update`) and `properties_check_service_tax` (`before insert or update of fnb_tax_pct, spa_tax_pct`, raises `P0035` / `tax_rate_out_of_range`). After this task every new row carries its tax. Task 3 reads `tax_amount` from these rows.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/44_food_spa_tax_test.sql`, change `select plan(20);` to `select plan(55);`, and insert this section just before `select * from finish();`:

```sql
-- ---------------------------------------------------------------------
-- Task 2: rates, inclusive_tax, and tax stored on every sale.
--
-- Rates over the section: fnb 5 -> (orders O1) -> 12 -> (O2, walk-ins)
-- -> 5 while W1 is corrected -> 12; spa 18 throughout.

set local role authenticated;

-- Olga (owner) sets food & drink to 5% and spa & activities to 18%.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.properties set fnb_tax_pct = 5, spa_tax_pct = 18
  where id = '44444444-0000-4000-8000-000000000001'$$), 1,
  'the owner sets the food and spa rates');

-- Sita (staff) cannot.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.properties set fnb_tax_pct = 0
  where id = '44444444-0000-4000-8000-000000000001'$$), 0,
  'staff cannot change the rates');
select is((select fnb_tax_pct::text || '/' || spa_tax_pct::text from public.properties
            where id = '44444444-0000-4000-8000-000000000001'),
  '5.00/18.00', 'the rates are 5% and 18%');

set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$update public.properties set fnb_tax_pct = 28.01
  where id = '44444444-0000-4000-8000-000000000001'$$,
  'P0035', 'tax_rate_out_of_range', 'a food rate above 28 is refused');
select throws_ok($$update public.properties set spa_tax_pct = -1
  where id = '44444444-0000-4000-8000-000000000001'$$,
  'P0035', 'tax_rate_out_of_range', 'a negative spa rate is refused');
select lives_ok($$update public.properties set fnb_tax_pct = 28
  where id = '44444444-0000-4000-8000-000000000001'$$, 'a rate of exactly 28 is allowed');
update public.properties set fnb_tax_pct = 5 where id = '44444444-0000-4000-8000-000000000001';

select is(public.inclusive_tax(105, 5), 5.00, '105 at 5% includes 5.00 of tax');
select is(public.inclusive_tax(200, 18), 30.51, '200 at 18% includes 30.51 (30.508 rounded)');
select is(public.inclusive_tax(1, 5), 0.05, '1 at 5% includes 0.05 (0.0476 rounded)');
select is(public.inclusive_tax(999, 0), 0.00, 'a 0% rate means no tax');

-- O1: Gita orders two thalis and a lassi, 525 at 5%.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok($$select public.place_food_order('44444444-0000-4000-8000-000000000051',
  '[{"food_item_id":"44444444-0000-4000-8000-000000000031","quantity":2},
    {"food_item_id":"44444444-0000-4000-8000-000000000032","quantity":1}]'::jsonb)$$,
  'Gita orders two thalis and a lassi (525)');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_orders
            where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 525),
  '5.00/25.00', 'the order records 5% and 25.00 of tax');
select is((select string_agg(i.tax_pct::text || '/' || i.tax_amount::text, ',' order by i.line_total)
             from public.food_order_items i
             join public.food_orders o on o.id = i.order_id
            where o.reservation_id = '44444444-0000-4000-8000-000000000051' and o.total = 525),
  '5.00/5.00,5.00/20.00', 'each item records its tax at the order''s rate');

-- The kitchen (Sita) accepts O1 and tries to zero its tax.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.food_orders
     set status = 'accepted', tax_pct = 0, tax_amount = 0
   where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 525$$), 1,
  'the kitchen accepts the order, sending tax 0');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_orders
            where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 525),
  '5.00/25.00', 'the tax cannot be changed by an update');

-- Olga raises the food rate to 12%.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
update public.properties set fnb_tax_pct = 12 where id = '44444444-0000-4000-8000-000000000001';
select is((select tax_pct::text || '/' || tax_amount::text from public.food_orders
            where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 525),
  '5.00/25.00', 'raising the food rate leaves the earlier order at 5%');

-- O2: one more lassi, 105 at 12%.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok($$select public.place_food_order('44444444-0000-4000-8000-000000000051',
  '[{"food_item_id":"44444444-0000-4000-8000-000000000032","quantity":1}]'::jsonb)$$,
  'Gita orders one more lassi (105)');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_orders
            where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 105),
  '12.00/11.25', 'the new order records 12% and 11.25 of tax');

-- A1: a massage for two (2,360) today; A2: a massage for one (1,180),
-- which Gita cancels.
select lives_ok($$select public.book_activity('44444444-0000-4000-8000-000000000051',
  '44444444-0000-4000-8000-000000000041', (now() at time zone 'Asia/Kolkata')::date, '10:00', 2)$$,
  'Gita books a massage for two (2,360)');
select is((select tax_pct::text || '/' || tax_amount::text from public.activity_bookings
            where reservation_id = '44444444-0000-4000-8000-000000000051' and people = 2),
  '18.00/360.00', 'the activity booking records 18% and 360.00 of tax');
select lives_ok($$select public.book_activity('44444444-0000-4000-8000-000000000051',
  '44444444-0000-4000-8000-000000000041', (now() at time zone 'Asia/Kolkata')::date, '10:00', 1)$$,
  'Gita books a massage for one (1,180)');
select is(pg_temp.rows_affected($$update public.activity_bookings set status = 'cancelled'
   where reservation_id = '44444444-0000-4000-8000-000000000051' and people = 1$$), 1,
  'Gita cancels the massage for one');
select is((select status::text || ' ' || tax_pct::text || '/' || tax_amount::text
             from public.activity_bookings
            where reservation_id = '44444444-0000-4000-8000-000000000051' and people = 1),
  'cancelled 18.00/180.00', 'a cancelled booking keeps its tax');

-- Walk-ins logged by Sita today.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$insert into public.food_activity_sales
    (property_id, category, item_name, unit_price, amount, payment_method, tax_pct, tax_amount)
  values ('44444444-0000-4000-8000-000000000001','food','Walk-in thali',210,210,'cash',0,0)$$,
  'Sita logs a walk-in thali (210), sending tax 0');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in thali'),
  '12.00/22.50', 'the sale records the current food rate, not what was sent');
select lives_ok($$insert into public.food_activity_sales
    (property_id, category, item_name, unit_price, amount, payment_method)
  values ('44444444-0000-4000-8000-000000000001','activity','Walk-in yoga',590,590,'upi')$$,
  'Sita logs a walk-in yoga session (590)');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in yoga'),
  '18.00/90.00', 'an activity sale records the spa rate');

-- Olga lowers the food rate to 5% and then corrects the thali to 336.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
update public.properties set fnb_tax_pct = 5 where id = '44444444-0000-4000-8000-000000000001';
select is(pg_temp.rows_affected($$update public.food_activity_sales
     set amount = 336, unit_price = 336
   where item_name = 'Walk-in thali'$$), 1,
  'the owner corrects the thali sale to 336 while the food rate is 5%');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in thali'),
  '12.00/36.00', 'the corrected sale keeps the 12% it was sold at');
update public.properties set fnb_tax_pct = 12 where id = '44444444-0000-4000-8000-000000000001';

-- A snack logged as food, then moved to activities as a sauna session.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$insert into public.food_activity_sales
    (property_id, category, item_name, unit_price, amount, payment_method)
  values ('44444444-0000-4000-8000-000000000001','food','Walk-in snack',118,118,'cash')$$,
  'Sita logs a walk-in snack (118) as food');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in snack'),
  '12.00/12.64', 'the snack records 12% and 12.64 of tax');
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(pg_temp.rows_affected($$update public.food_activity_sales
     set category = 'activity', item_name = 'Walk-in sauna'
   where item_name = 'Walk-in snack'$$), 1,
  'the owner moves it to activities as a sauna session');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in sauna'),
  '18.00/18.00', 'a changed category takes the new category''s current rate');
select is(pg_temp.rows_affected($$update public.food_activity_sales
     set tax_pct = 0, tax_amount = 0
   where item_name = 'Walk-in sauna'$$), 1,
  'the owner tries to zero a sale''s tax');
select is((select tax_pct::text || '/' || tax_amount::text from public.food_activity_sales
            where item_name = 'Walk-in sauna'),
  '18.00/18.00', 'a sale''s tax cannot be changed by an update');
```

- [ ] **Step 2: Run them to see them fail**

Run: `supabase test db supabase/tests/44_food_spa_tax_test.sql`
Expected: FAIL. Tests 24 and 25 (`a food rate above 28 is refused`, `a negative spa rate is refused`) fail because the update raises SQLSTATE `23514` (the check constraint), not `P0035`. Then the run aborts at test 27 with `inclusive_tax is not implemented yet` (SQLSTATE `0A000`).

- [ ] **Step 3: Implement**

In `supabase/migrations/0053_food_spa_tax.sql`, replace the whole stub block, from the comment `-- The tax inside a tax-inclusive price. Not security definer: the` down to and including the `$$;` that closes the stub, with:

```sql
-- The tax inside a tax-inclusive price, rounded to paise: 105 at 5%
-- holds 5.00; 200 at 18% holds 30.51. Not security definer: the walk-in
-- trigger runs as the staff member and calls it.
create function public.inclusive_tax(p_amount numeric, p_pct numeric)
returns numeric
language sql
immutable
set search_path = public, pg_temp
as $$
  select round(coalesce(p_amount, 0) * coalesce(p_pct, 0) / (100 + coalesce(p_pct, 0)), 2);
$$;
```

(Leave the `revoke`/`grant` lines after it as they are.) Then append to the end of the file:

```sql

-- ---------------------------------------------------------------------
-- Tax stored on the row. Each trigger fixes tax_pct on insert from the
-- resort's current rate -- read through the row's own parent, never from
-- what the client sent -- keeps it on update, and works tax_amount out
-- again from the row's amount every time. So a client can neither set nor
-- clear tax, and a later rate change never rewrites an old sale.
--
-- They run with the caller's rights: inside place_food_order and
-- book_activity (security definer) that is the function owner; for a
-- walk-in sale it is the staff member, who can read their own resort's
-- properties row. None is security definer, so the allow-list in
-- 37_tenancy_isolation_test.sql does not change.

create function public.food_orders_set_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    -- Through the reservation, not new.property_id, so this does not
    -- depend on food_orders_fill_property having run first.
    new.tax_pct := coalesce((select p.fnb_tax_pct
                               from public.reservations r
                               join public.properties p on p.id = r.property_id
                              where r.id = new.reservation_id), 0);
  else
    new.tax_pct := old.tax_pct;
  end if;
  -- place_food_order inserts the order with total 0 and sets the total
  -- afterwards; that update recomputes the tax at the fixed rate.
  new.tax_amount := public.inclusive_tax(new.total, new.tax_pct);
  return new;
end;
$$;
revoke execute on function public.food_orders_set_tax() from public, anon, authenticated;

create trigger food_orders_set_tax
  before insert or update on public.food_orders
  for each row execute function public.food_orders_set_tax();

-- An item takes its order's rate. Item taxes are per line and can differ
-- from the order's own tax (worked out on the order total) by a paisa of
-- rounding; the order's figure is the one reports and bills add up.
create function public.food_order_items_set_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.tax_pct := coalesce((select o.tax_pct from public.food_orders o
                              where o.id = new.order_id), 0);
  else
    new.tax_pct := old.tax_pct;
  end if;
  new.tax_amount := public.inclusive_tax(new.line_total, new.tax_pct);
  return new;
end;
$$;
revoke execute on function public.food_order_items_set_tax() from public, anon, authenticated;

create trigger food_order_items_set_tax
  before insert or update on public.food_order_items
  for each row execute function public.food_order_items_set_tax();

create function public.activity_bookings_set_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.tax_pct := coalesce((select p.spa_tax_pct
                               from public.reservations r
                               join public.properties p on p.id = r.property_id
                              where r.id = new.reservation_id), 0);
  else
    new.tax_pct := old.tax_pct;
  end if;
  new.tax_amount := public.inclusive_tax(new.amount, new.tax_pct);
  return new;
end;
$$;
revoke execute on function public.activity_bookings_set_tax() from public, anon, authenticated;

create trigger activity_bookings_set_tax
  before insert or update on public.activity_bookings
  for each row execute function public.activity_bookings_set_tax();

-- A walk-in sale takes the rate of its category. Correcting its amount
-- keeps the rate it was sold at; moving it to the other category takes
-- that category's current rate. (OLD is null on insert, so old.category
-- reads as null there.)
create function public.food_activity_sales_set_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' or new.category is distinct from old.category then
    new.tax_pct := coalesce((select case new.category
                                      when 'food' then p.fnb_tax_pct
                                      else p.spa_tax_pct
                                    end
                               from public.properties p
                              where p.id = new.property_id), 0);
  else
    new.tax_pct := old.tax_pct;
  end if;
  new.tax_amount := public.inclusive_tax(new.amount, new.tax_pct);
  return new;
end;
$$;
revoke execute on function public.food_activity_sales_set_tax() from public, anon, authenticated;

create trigger food_activity_sales_set_tax
  before insert or update on public.food_activity_sales
  for each row execute function public.food_activity_sales_set_tax();

-- ---------------------------------------------------------------------
-- Rates outside 0..28 get a readable code before the check constraints
-- (which stay as the backstop) would refuse them with a bare 23514.
create function public.properties_check_service_tax()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.fnb_tax_pct is null or new.fnb_tax_pct < 0 or new.fnb_tax_pct > 28
     or new.spa_tax_pct is null or new.spa_tax_pct < 0 or new.spa_tax_pct > 28 then
    raise exception using errcode = 'P0035', message = 'tax_rate_out_of_range';
  end if;
  return new;
end;
$$;
revoke execute on function public.properties_check_service_tax() from public, anon, authenticated;

create trigger properties_check_service_tax
  before insert or update of fnb_tax_pct, spa_tax_pct on public.properties
  for each row execute function public.properties_check_service_tax();
```

- [ ] **Step 4: Rebuild and run the file**

Run: `supabase db reset && supabase test db supabase/tests/44_food_spa_tax_test.sql`
Expected: PASS, `1..55`, all ok.

- [ ] **Step 5: Run the whole database suite**

Run: `supabase test db`
Expected: PASS. Every other suite's resorts have food and spa rates of 0, so every trigger stores tax 0 there: `22_food_activity_sales`, `28_food_ordering`, `29_activity_booking` and `40_finance_ledger` keep their figures. `37_tenancy_isolation` passes: no new security definer function, table or policy.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0053_food_spa_tax.sql supabase/tests/44_food_spa_tax_test.sql
git commit -m "feat(tax): store food and spa tax on every order, booking and walk-in sale" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The bill, the Ledger and today's summary by category

**Track:** DB. Depends on Task 2.

**Files:**
- Modify: `supabase/migrations/0053_food_spa_tax.sql`
- Test: `supabase/tests/44_food_spa_tax_test.sql`

**Interfaces:**
- Consumes: `tax_amount` on `food_orders`, `activity_bookings`, `food_activity_sales` (Task 2); `properties.fnb_tax_pct`/`spa_tax_pct` (Task 1).
- Produces (the JSON keys the app already reads since Task 1):
  - `current_charges(p_reservation_id uuid) returns jsonb` gains `food_tax` and `activity_tax`. Other keys, access and `total`/`balance` are unchanged.
  - `report_ledger(p_from date, p_to date, p_property_id uuid)`: same signature and columns. `in_stay_order`, `walk_in` and `activity_booking` lines now have `gross = amount − tax_amount`, `tax = tax_amount`, `net = amount`.
  - `finance_summary(p_property_id uuid) returns jsonb`: `room_tax` = the `room` + `ancillary` Ledger tax; new `food_tax` (`food_beverage`), `spa_tax` (`spa_activities`); `resort.fnb_tax_pct`, `resort.spa_tax_pct`.

- [ ] **Step 1: Check the latest definitions**

Run:

```bash
grep -ln "function public.current_charges\|function public.report_ledger\|function public.finance_summary" supabase/migrations/*.sql
```

Expected: `0037_stay_checkout.sql`, `0045_resort_functions.sql`, `0048_finance_ledger.sql` (and `0053` after this task). If a migration numbered between `0048` and `0053` also lists one of them (another gap project merged first), copy that function from it instead of the bodies below, and add only the lines marked `-- 0053`.

- [ ] **Step 2: Write the failing tests**

In `supabase/tests/44_food_spa_tax_test.sql`, change `select plan(55);` to `select plan(67);`, and insert this section just before `select * from finish();`:

```sql
-- ---------------------------------------------------------------------
-- Task 3: the bill, the Ledger and today's summary.
--
-- R1 now has O1 (525, tax 25.00), O2 (105, tax 11.25), A1 (2,360, tax
-- 360.00) and the cancelled A2. Today's walk-ins: the thali (336, tax
-- 36.00), yoga (590, tax 90.00) and the sauna (118, tax 18.00). R2
-- arrives today: 2,000 of room with 240 of tax.

set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'food_amount')::numeric,
  630::numeric, 'the bill has 630 of food (525 + 105)');
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'food_tax')::numeric,
  36.25, 'which includes 36.25 of tax (25.00 + 11.25)');
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'activity_amount')::numeric,
  2360::numeric, 'a massage for one that was cancelled is not on the bill');
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'activity_tax')::numeric,
  360.00, 'the activities include 360.00 of tax');
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'total')::numeric,
  7990::numeric, 'tax is inside the amounts, so the total is 5,000 + 630 + 2,360');

-- Anil (accountant) reads today's Ledger and summary.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is(
  (select string_agg(l.category || '/' || l.source || '/' || l.gross || '/' || l.tax || '/' || l.net,
                     '; ' order by l.category, l.source)
     from public.report_ledger((now() at time zone 'Asia/Kolkata')::date,
                               (now() at time zone 'Asia/Kolkata')::date,
                               '44444444-0000-4000-8000-000000000001') l),
  'food_beverage/in_stay_order/593.75/36.25/630.00; '
  'food_beverage/walk_in/300.00/36.00/336.00; '
  'room/booking/2000.00/240.00/2240.00; '
  'spa_activities/activity_booking/2000.00/360.00/2360.00; '
  'spa_activities/walk_in/600.00/108.00/708.00',
  'the Ledger splits food, activities and walk-ins into pre-tax and tax');
select is(
  (select count(*)::int
     from public.report_ledger((now() at time zone 'Asia/Kolkata')::date,
                               (now() at time zone 'Asia/Kolkata')::date,
                               '44444444-0000-4000-8000-000000000001') l
    where l.taxable + l.tax <> l.net),
  0, 'every Ledger line has taxable + tax = net');
select is((public.finance_summary('44444444-0000-4000-8000-000000000001') ->> 'room_tax')::numeric,
  240.00, 'room tax is the booking''s tax only');
select is((public.finance_summary('44444444-0000-4000-8000-000000000001') ->> 'food_tax')::numeric,
  72.25, 'food tax is today''s orders and food walk-ins (36.25 + 36.00)');
select is((public.finance_summary('44444444-0000-4000-8000-000000000001') ->> 'spa_tax')::numeric,
  468.00, 'spa tax is today''s bookings and activity walk-ins (360.00 + 108.00)');
select is(
  (select (s -> 'resort' ->> 'fnb_tax_pct') || '/' || (s -> 'resort' ->> 'spa_tax_pct')
     from public.finance_summary('44444444-0000-4000-8000-000000000001') s),
  '12.00/18.00', 'the summary carries the resort''s food and spa rates');

-- The kitchen cancels O2; its tax leaves Gita's bill.
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000002","role":"authenticated"}';
update public.food_orders set status = 'cancelled'
 where reservation_id = '44444444-0000-4000-8000-000000000051' and total = 105;
set local request.jwt.claims to '{"sub":"44000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((public.current_charges('44444444-0000-4000-8000-000000000051') ->> 'food_tax')::numeric,
  25.00, 'a cancelled order''s tax leaves the bill');
```

- [ ] **Step 3: Run them to see them fail**

Run: `supabase test db supabase/tests/44_food_spa_tax_test.sql`
Expected: FAIL at test 57 (`which includes 36.25 of tax`): `current_charges` has no `food_tax` key yet, so the value is NULL.

- [ ] **Step 4: Implement**

Append to the end of `supabase/migrations/0053_food_spa_tax.sql`:

```sql

-- ---------------------------------------------------------------------
-- The guest's bill gains the tax inside its food and activities. Body
-- copied from 0045_resort_functions.sql; the 0053 lines are marked.
-- total and balance do not change: the tax is already inside the amounts.
create or replace function public.current_charges(
  p_reservation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid          uuid := auth.uid();
  v_res          public.reservations;
  v_stay         numeric(12,2);
  v_food         numeric(12,2);
  v_food_tax     numeric(12,2);   -- 0053
  v_activity     numeric(12,2);
  v_activity_tax numeric(12,2);   -- 0053
  v_paid         numeric(12,2);
  v_total        numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_res.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_res.property_id, false,
      'owner','admin','staff','accountant');
  end if;

  v_stay := coalesce((v_res.quote ->> 'total')::numeric, 0);

  select coalesce(sum(total), 0), coalesce(sum(tax_amount), 0)   -- 0053
    into v_food, v_food_tax
  from public.food_orders
  where reservation_id = p_reservation_id and status <> 'cancelled';

  select coalesce(sum(amount), 0), coalesce(sum(tax_amount), 0)  -- 0053
    into v_activity, v_activity_tax
  from public.activity_bookings
  where reservation_id = p_reservation_id and status <> 'cancelled';

  select coalesce(sum(amount), 0) into v_paid
  from public.payments
  where reservation_id = p_reservation_id and status = 'succeeded';

  v_total := v_stay + v_food + v_activity;

  return jsonb_build_object(
    'stay_amount', v_stay,
    'food_amount', v_food,
    'food_tax', v_food_tax,                -- 0053
    'activity_amount', v_activity,
    'activity_tax', v_activity_tax,        -- 0053
    'total', v_total,
    'paid', v_paid,
    'balance', greatest(v_total - v_paid, 0)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- The Ledger splits tax-inclusive lines into pre-tax and tax. Body copied
-- from 0048_finance_ledger.sql; only the three 0053 lines change.
create or replace function public.report_ledger(p_from date, p_to date, p_property_id uuid)
returns table (
  day      date,
  category text,
  source   text,
  gross    numeric,
  discount numeric,
  taxable  numeric,
  tax      numeric,
  net      numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text;
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','accountant');

  select p.timezone into v_tz from public.properties p where p.id = p_property_id;

  -- Accrual basis: revenue earned, by category. Room revenue falls on the
  -- arrival date (as in report_revenue). Room tax is exactly as fixed in
  -- each booking's quote (get_quote taxes subtotal + cleaning_fee -
  -- discount); it is split between the room line and the cleaning-fee
  -- line so the two add up to the quote's tax_amount and total. Food,
  -- activity and walk-in prices include their tax (0053): gross is the
  -- amount without the tax stored on the row, so net is still the amount.
  return query
  with bk as (
    select (lower(r.period) at time zone v_tz)::date as b_day,
           coalesce(r.quote ? 'subtotal', false) as b_itemised,
           coalesce((r.quote ->> 'subtotal')::numeric, (r.quote ->> 'total')::numeric, 0) as b_sub,
           coalesce((r.quote ->> 'cleaning_fee')::numeric, 0) as b_clean,
           coalesce((r.quote -> 'coupon' ->> 'discount')::numeric, 0) as b_disc,
           coalesce((r.quote ->> 'tax_pct')::numeric, 0) as b_pct,
           coalesce((r.quote ->> 'tax_amount')::numeric, 0) as b_tax
      from public.reservations r
     where r.property_id = p_property_id
       and r.kind = 'booking'
       and r.quote is not null
       and r.status in ('confirmed', 'checked_in', 'checked_out')
       and (lower(r.period) at time zone v_tz)::date between p_from and p_to
  ),
  bk2 as (
    select b.*,
           case when b.b_itemised then least(b.b_disc, b.b_sub) else 0 end as room_disc
      from bk b
  ),
  bk3 as (
    select b.*,
           case when b.b_itemised
                then round((b.b_sub - b.room_disc) * b.b_pct / 100, 2) else 0 end as room_tax,
           case when b.b_itemised
                then least(b.b_disc - b.room_disc, b.b_clean) else 0 end as clean_disc
      from bk2 b
  ),
  paid as (
    select pm.reservation_id as res_id, sum(pm.amount) as paid_total
      from public.payments pm
     where pm.property_id = p_property_id and pm.status = 'succeeded'
     group by pm.reservation_id
  ),
  lines as (
    select b.b_day as l_day, 'room' as l_cat, 'booking' as l_src,
           b.b_sub as l_gross, b.room_disc as l_disc, b.room_tax as l_tax
      from bk3 b
    union all
    select b.b_day, 'ancillary', 'cleaning_fee',
           b.b_clean, b.clean_disc, b.b_tax - b.room_tax
      from bk3 b
     where b.b_itemised and (b.b_clean > 0 or b.b_tax - b.room_tax <> 0)
    union all
    select (r.cancelled_at at time zone v_tz)::date, 'ancillary', 'cancellation_fee',
           coalesce(pd.paid_total, 0) - least(coalesce(r.refund_amount, 0), coalesce(pd.paid_total, 0)),
           0, 0
      from public.reservations r
      left join paid pd on pd.res_id = r.id
     where r.property_id = p_property_id
       and r.status = 'cancelled'
       and r.cancelled_at >= (p_from::timestamp at time zone v_tz)
       and r.cancelled_at <  ((p_to + 1)::timestamp at time zone v_tz)
       and coalesce(pd.paid_total, 0)
           - least(coalesce(r.refund_amount, 0), coalesce(pd.paid_total, 0)) > 0
    union all
    select (fo.created_at at time zone v_tz)::date, 'food_beverage', 'in_stay_order',
           fo.total - fo.tax_amount, 0, fo.tax_amount                         -- 0053
      from public.food_orders fo
     where fo.property_id = p_property_id
       and fo.status <> 'cancelled'
       and fo.created_at >= (p_from::timestamp at time zone v_tz)
       and fo.created_at <  ((p_to + 1)::timestamp at time zone v_tz)
    union all
    select s.sale_date,
           case s.category when 'food' then 'food_beverage' else 'spa_activities' end,
           'walk_in', s.amount - s.tax_amount, 0, s.tax_amount                -- 0053
      from public.food_activity_sales s
     where s.property_id = p_property_id
       and s.sale_date between p_from and p_to
    union all
    select ab.booking_date, 'spa_activities', 'activity_booking',
           ab.amount - ab.tax_amount, 0, ab.tax_amount                        -- 0053
      from public.activity_bookings ab
     where ab.property_id = p_property_id
       and ab.status = 'booked'
       and ab.booking_date between p_from and p_to
  )
  select l.l_day, l.l_cat, l.l_src,
         round(sum(l.l_gross), 2),
         round(sum(l.l_disc), 2),
         round(sum(l.l_gross - l.l_disc), 2),
         round(sum(l.l_tax), 2),
         round(sum(l.l_gross - l.l_disc + l.l_tax), 2)
    from lines l
   group by l.l_day, l.l_cat, l.l_src
   order by l.l_day, l.l_cat, l.l_src;
end;
$$;

-- ---------------------------------------------------------------------
-- Today's summary reports tax by category and the resort's two new
-- rates. Body copied from 0048_finance_ledger.sql; the 0053 lines are
-- marked.
create or replace function public.finance_summary(p_property_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_prop       public.properties;
  v_today      date;
  v_online     numeric;
  v_desk       numeric;
  v_cash       numeric;
  v_card       numeric;
  v_upi        numeric;
  v_bank       numeric;
  v_other      numeric;
  v_refunds    numeric;
  v_room_tax   numeric;
  v_food_tax   numeric;   -- 0053
  v_spa_tax    numeric;   -- 0053
  v_in_count   int;
  v_in_balance numeric;
begin
  perform public.assert_resort_role(p_property_id, false, 'owner','admin','accountant');

  select * into v_prop from public.properties where id = p_property_id;
  v_today := (now() at time zone v_prop.timezone)::date;

  -- From today's Collections, so the Today tab and the Collections tab
  -- can never disagree. Refunds are reported as a positive amount.
  select coalesce(sum(c.amount) filter (where c.channel = 'online' and c.source <> 'refund'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'cash'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'card'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'upi'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'bank_transfer'), 0),
         coalesce(sum(c.amount) filter (where c.channel = 'front_desk' and c.method = 'other'), 0),
         coalesce(-sum(c.amount) filter (where c.source = 'refund'), 0)
    into v_online, v_desk, v_cash, v_card, v_upi, v_bank, v_other, v_refunds
    from public.report_collections(v_today, v_today, p_property_id) c;

  -- 0053: today's Ledger tax by category. Room tax is the room and
  -- cleaning-fee (ancillary) lines of bookings; food and spa tax are the
  -- tax inside their prices.
  select coalesce(sum(l.tax) filter (where l.category in ('room', 'ancillary')), 0),
         coalesce(sum(l.tax) filter (where l.category = 'food_beverage'), 0),
         coalesce(sum(l.tax) filter (where l.category = 'spa_activities'), 0)
    into v_room_tax, v_food_tax, v_spa_tax
    from public.report_ledger(v_today, v_today, p_property_id) l;

  -- Checked-in guests and what they still owe, worked out as
  -- current_charges does, but in one query rather than one call each.
  select count(*)::int,
         coalesce(sum(greatest(coalesce((r.quote ->> 'total')::numeric, 0)
                               + coalesce(fo.t, 0) + coalesce(ab.t, 0) - coalesce(pm.t, 0), 0)), 0)
    into v_in_count, v_in_balance
    from public.reservations r
    left join (select o.reservation_id, sum(o.total) as t
                 from public.food_orders o
                where o.property_id = p_property_id and o.status <> 'cancelled'
                group by o.reservation_id) fo on fo.reservation_id = r.id
    left join (select b.reservation_id, sum(b.amount) as t
                 from public.activity_bookings b
                where b.property_id = p_property_id and b.status <> 'cancelled'
                group by b.reservation_id) ab on ab.reservation_id = r.id
    left join (select p.reservation_id, sum(p.amount) as t
                 from public.payments p
                where p.property_id = p_property_id and p.status = 'succeeded'
                group by p.reservation_id) pm on pm.reservation_id = r.id
   where r.property_id = p_property_id
     and r.kind = 'booking'
     and r.status = 'checked_in';

  return jsonb_build_object(
    'resort', jsonb_build_object(
      'name',        v_prop.name,
      'slug',        v_prop.slug,
      'gstin',       v_prop.gstin,
      'tax_pct',     v_prop.tax_pct,
      'fnb_tax_pct', v_prop.fnb_tax_pct,   -- 0053
      'spa_tax_pct', v_prop.spa_tax_pct,   -- 0053
      'timezone',    v_prop.timezone,
      'today',       to_char(v_today, 'YYYY-MM-DD')),
    'online_collected', round(v_online, 2),
    'desk_collected', jsonb_build_object(
      'total',         round(v_desk, 2),
      'cash',          round(v_cash, 2),
      'card',          round(v_card, 2),
      'upi',           round(v_upi, 2),
      'bank_transfer', round(v_bank, 2),
      'other',         round(v_other, 2)),
    'refunds',          round(v_refunds, 2),
    'net_collected',    round(v_online + v_desk - v_refunds, 2),
    'room_tax',         round(v_room_tax, 2),
    'food_tax',         round(v_food_tax, 2),   -- 0053
    'spa_tax',          round(v_spa_tax, 2),    -- 0053
    'in_house_count',   v_in_count,
    'in_house_balance', round(v_in_balance, 2)
  );
end;
$$;
```

`create or replace` keeps each function's existing grants (revoked from `public`/`anon`, granted to `authenticated`), so no grant lines are needed.

- [ ] **Step 5: Rebuild and run the file**

Run: `supabase db reset && supabase test db supabase/tests/44_food_spa_tax_test.sql`
Expected: PASS, `1..67`, all ok.

- [ ] **Step 6: Run the whole database suite**

Run: `supabase test db`
Expected: PASS. `40_finance_ledger_test.sql` keeps its figures (its resorts have food and spa rates of 0, so every food and activity line has tax 0 and gross = amount, and `room_tax` is unchanged). `33_stay_checkout` and `35_customer_checkout` pass: `checkout_booking` reads only `balance` from `current_charges`.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/0053_food_spa_tax.sql supabase/tests/44_food_spa_tax_test.sql
git commit -m "feat(tax): bill, ledger and finance summary report food and spa tax" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase 2: App track (after Task 1; Tasks 4, 5, 6, 7 are independent)

### Task 4: The Taxes screen edits the food and spa rates

**Track:** App. Depends on Task 1.

**Files:**
- Modify: `lib/features/owner/tax_settings_screen.dart` (whole file)
- Modify: `lib/features/owner/owner_settings_screen.dart:81`
- Test: `test/features/owner/tax_settings_screen_test.dart` (new)

**Interfaces:**
- Consumes: `Property.taxPct`, `Property.fnbTaxPct`, `Property.spaTaxPct`, `Property.gstin`; `CatalogRepository.updateSettings(String propertyId, Map<String, dynamic> fields)` (`lib/data/repositories/catalog_repository.dart`), `catalogRepositoryProvider`; `TaxRateOutOfRange` (Task 1); `formatPct` (`lib/core/format.dart`).
- Produces: `TaxSettingsScreen({required Property property})` (unchanged constructor). One save sends `{'tax_pct': num, 'fnb_tax_pct': num, 'spa_tax_pct': num, 'gstin': String?}`. Field keys: `tax-pct-field`, `tax-fnb-field`, `tax-spa-field`, `tax-gstin-field`; note key `tax-inclusive-note`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/owner/tax_settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/catalog_repository.dart';
import 'package:pasala/features/owner/tax_settings_screen.dart';

/// Records every `updateSettings` call; everything else is unused here.
class _FakeCatalog implements CatalogRepository {
  final saved = <(String, Map<String, dynamic>)>[];
  Object? failWith;

  @override
  Future<void> updateSettings(String propertyId, Map<String, dynamic> fields) async {
    final failure = failWith;
    if (failure != null) throw failure;
    saved.add((propertyId, fields));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _property = Property(
  id: 'p1',
  name: 'Pasala Farm House',
  slug: 'pasala-farm-house',
  description: null,
  address: null,
  images: [],
  amenities: [],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
  taxPct: 12,
  fnbTaxPct: 5,
  spaTaxPct: 18,
  gstin: '29ABCDE1234F1Z5',
);

/// Pushes the screen over a home page, as Owner Settings does, so Save can
/// pop it. Tall enough that every field is built.
Future<void> _open(WidgetTester tester, _FakeCatalog catalog) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [catalogRepositoryProvider.overrideWithValue(catalog)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const TaxSettingsScreen(property: _property),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<void> _enter(WidgetTester tester, String key, String text) =>
    tester.enterText(find.byKey(Key(key)), text);

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the room, food and spa rates of the resort', (tester) async {
    await _open(tester, _FakeCatalog());

    expect(_text(tester, 'tax-pct-field'), '12');
    expect(_text(tester, 'tax-fnb-field'), '5');
    expect(_text(tester, 'tax-spa-field'), '18');
    expect(_text(tester, 'tax-gstin-field'), '29ABCDE1234F1Z5');
    expect(find.text('Room tax rate (%)'), findsOneWidget);
    expect(find.text('Food & drink tax (%)'), findsOneWidget);
    expect(find.text('Spa & activities tax (%)'), findsOneWidget);
    expect(find.text('Already included in menu prices'), findsOneWidget);
    expect(find.text('Already included in activity prices'), findsOneWidget);
    expect(
        find.text('Each order and sale keeps the rate it was made at. '
            'Changing a rate affects new sales only.'),
        findsOneWidget);
  });

  testWidgets('Save sends all four settings in one update and closes', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    await _enter(tester, 'tax-fnb-field', '12');
    await _enter(tester, 'tax-spa-field', '18.5');
    await _save(tester);

    expect(catalog.saved, hasLength(1));
    expect(catalog.saved.single.$1, 'p1');
    expect(catalog.saved.single.$2, {
      'tax_pct': 12,
      'fnb_tax_pct': 12,
      'spa_tax_pct': 18.5,
      'gstin': '29ABCDE1234F1Z5',
    });
    expect(find.byType(TaxSettingsScreen), findsNothing);
  });

  testWidgets('28% and a blank GSTIN are saved as 28 and null', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    await _enter(tester, 'tax-fnb-field', '28');
    await _enter(tester, 'tax-gstin-field', '  ');
    await _save(tester);

    expect(catalog.saved.single.$2['fnb_tax_pct'], 28);
    expect(catalog.saved.single.$2['gstin'], isNull);
  });

  testWidgets('a food rate above 28 is refused before saving', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    await _enter(tester, 'tax-fnb-field', '28.5');
    await _save(tester);

    expect(find.text('Enter a food & drink tax rate between 0 and 28.'), findsOneWidget);
    expect(catalog.saved, isEmpty);
    expect(find.byType(TaxSettingsScreen), findsOneWidget);
  });

  testWidgets('a rate that is not a number is refused', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    for (final typed in ['18%', 'NaN', '5,5', '']) {
      await _enter(tester, 'tax-spa-field', typed);
      await _save(tester);
      expect(find.text('Enter a spa & activities tax rate between 0 and 28.'), findsOneWidget,
          reason: typed);
    }
    expect(catalog.saved, isEmpty);
  });

  testWidgets('the room rate keeps its 0 to 100 range', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    await _enter(tester, 'tax-pct-field', '101');
    await _save(tester);

    expect(find.text('Enter a room tax rate between 0 and 100.'), findsOneWidget);
    expect(catalog.saved, isEmpty);
  });

  testWidgets('a server refusal shows its message and keeps the screen open', (tester) async {
    final catalog = _FakeCatalog()..failWith = const TaxRateOutOfRange();
    await _open(tester, catalog);

    await _save(tester);

    expect(find.text('Food and spa tax rates must be between 0% and 28%.'), findsOneWidget);
    expect(find.byType(TaxSettingsScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/owner/tax_settings_screen_test.dart`
Expected: FAIL: `Bad state: No element` from `find.byKey(Key('tax-fnb-field'))` in the first test (the field does not exist yet), and the save tests fail on the payload.

- [ ] **Step 3: Implement the screen**

Replace `lib/features/owner/tax_settings_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/providers.dart';

/// Taxes -- the room rate and GSTIN (`0025_property_settings.sql`) and the
/// food & drink and spa & activities rates (`0053_food_spa_tax.sql`).
///
/// The room rate changes real pricing: `get_quote` adds it on top of the
/// room subtotal, so a booking made after a nonzero rate is saved costs
/// more. The food and spa rates change no price -- menu and activity prices
/// already include them -- they decide how much of each new order or sale
/// is recorded as tax. Every order and sale keeps the rate it was made at.
class TaxSettingsScreen extends ConsumerStatefulWidget {
  const TaxSettingsScreen({super.key, required this.property});

  final Property property;

  @override
  ConsumerState<TaxSettingsScreen> createState() => _TaxSettingsScreenState();
}

class _TaxSettingsScreenState extends ConsumerState<TaxSettingsScreen> {
  late final TextEditingController _taxPct;
  late final TextEditingController _fnbPct;
  late final TextEditingController _spaPct;
  late final TextEditingController _gstin;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _taxPct = TextEditingController(text: formatPct(widget.property.taxPct));
    _fnbPct = TextEditingController(text: formatPct(widget.property.fnbTaxPct));
    _spaPct = TextEditingController(text: formatPct(widget.property.spaTaxPct));
    _gstin = TextEditingController(text: widget.property.gstin ?? '');
  }

  @override
  void dispose() {
    _taxPct.dispose();
    _fnbPct.dispose();
    _spaPct.dispose();
    _gstin.dispose();
    super.dispose();
  }

  /// The rate typed into [controller], or null (with [message] shown) when
  /// it is not a finite number from 0 to [max]. `num.tryParse` accepts
  /// `NaN`, which passes both range comparisons, hence `isFinite`.
  num? _rate(TextEditingController controller, num max, String message) {
    final value = num.tryParse(controller.text.trim());
    if (value == null || !value.isFinite || value < 0 || value > max) {
      setState(() => _error = message);
      return null;
    }
    return value;
  }

  Future<void> _save() async {
    final taxPct = _rate(_taxPct, 100, 'Enter a room tax rate between 0 and 100.');
    if (taxPct == null) return;
    final fnbPct = _rate(_fnbPct, 28, 'Enter a food & drink tax rate between 0 and 28.');
    if (fnbPct == null) return;
    final spaPct = _rate(_spaPct, 28, 'Enter a spa & activities tax rate between 0 and 28.');
    if (spaPct == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final gstin = _gstin.text.trim();
      await ref.read(catalogRepositoryProvider).updateSettings(widget.property.id, {
        'tax_pct': taxPct,
        'fnb_tax_pct': fnbPct,
        'spa_tax_pct': spaPct,
        'gstin': gstin.isEmpty ? null : gstin,
      });
      ref.invalidate(propertiesProvider);
      ref.invalidate(propertyProvider(widget.property.id));
      if (mounted) Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _rateField(String key, TextEditingController controller, String label,
          String helper) =>
      TextField(
        key: Key(key),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, helperText: helper),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Taxes')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                _rateField('tax-pct-field', _taxPct, 'Room tax rate (%)',
                    'Added on top of the room price at booking time'),
                const SizedBox(height: Spacing.sm),
                _rateField('tax-fnb-field', _fnbPct, 'Food & drink tax (%)',
                    'Already included in menu prices'),
                const SizedBox(height: Spacing.sm),
                _rateField('tax-spa-field', _spaPct, 'Spa & activities tax (%)',
                    'Already included in activity prices'),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('tax-gstin-field'),
                  controller: _gstin,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN',
                    helperText: 'Optional',
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Each order and sale keeps the rate it was made at. '
                  'Changing a rate affects new sales only.',
                  key: const Key('tax-inclusive-note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      );
}
```

In `lib/features/owner/owner_settings_screen.dart`, in the `Taxes` tile, replace:

```dart
                subtitle: 'Tax rate and GSTIN',
```

with:

```dart
                subtitle: 'Room, food and spa tax rates, GSTIN',
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/owner/tax_settings_screen_test.dart test/features/owner/owner_settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `flutter analyze 2>&1 | tail -1`
Expected: the Task 1 baseline count.

- [ ] **Step 6: Commit**

```bash
git add lib/features/owner/tax_settings_screen.dart lib/features/owner/owner_settings_screen.dart \
  test/features/owner/tax_settings_screen_test.dart
git commit -m "feat(tax): owner Taxes screen edits the food and spa rates" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Finance shows tax per category

**Track:** App. Depends on Task 1.

**Files:**
- Modify: `lib/features/finance/finance_tables.dart` (`LedgerDay`, `ledgerByDay`, `ledgerTotal`)
- Modify: `lib/features/finance/finance_ledger_tab.dart` (`_columns`, `_TaxStrip`, `_LedgerCard`, doc comment)
- Modify: `lib/features/finance/finance_today_tab.dart` (two cards, doc comment)
- Modify: `lib/features/finance/finance_csv.dart` (`todayCsv`)
- Modify: `lib/features/owner/owner_reports_screen.dart:253`
- Test: `test/features/finance/finance_tables_test.dart`, `test/features/finance/finance_screen_test.dart`, `test/features/finance/finance_csv_test.dart`

**Interfaces:**
- Consumes: `LedgerRow.category`/`.taxable`/`.tax`, `LedgerCategory` (`lib/data/models/finance.dart`); `FinanceSummary.foodTax`/`.spaTax`, `FinanceResort.taxPct`/`.fnbTaxPct`/`.spaTaxPct` (Task 1); test helpers `ledgerRow`, `financeSummary({…, foodTax, spaTax})`, `financeResort({…, fnbTaxPct, spaTaxPct})`.
- Produces: `LedgerDay({DateTime? day, Map<LedgerCategory, num> byCategory = const {}, Map<LedgerCategory, num> taxByCategory = const {}})` with `num taxFor(LedgerCategory)`, `num get tax` (sum of `taxByCategory`), `taxable`, `total`, `categoryTotal` as before. (The `tax:` constructor parameter is replaced by `taxByCategory:`. Only `finance_tables.dart` constructs `LedgerDay`.) Today card keys `today-food-tax`, `today-spa-tax`.

- [ ] **Step 1: Write the failing tests**

In `test/features/finance/finance_tables_test.dart`, add inside `group('ledgerByDay', () { … })`, after the test `'the totals row adds every day'`:

```dart
    test("tax is kept per category and adds up to the day's tax", () {
      final days = ledgerByDay([
        ledgerRow(day: DateTime(2026, 8, 10), category: LedgerCategory.room, gross: 2000, tax: 240),
        ledgerRow(
            day: DateTime(2026, 8, 10),
            category: LedgerCategory.foodBeverage,
            source: 'in_stay_order',
            gross: 500,
            tax: 25),
        ledgerRow(
            day: DateTime(2026, 8, 10),
            category: LedgerCategory.foodBeverage,
            source: 'walk_in',
            gross: 300,
            tax: 36),
        ledgerRow(
            day: DateTime(2026, 8, 11),
            category: LedgerCategory.spaActivities,
            source: 'activity_booking',
            gross: 2000,
            tax: 360),
      ]);

      expect(days[0].taxFor(LedgerCategory.room), 240);
      expect(days[0].taxFor(LedgerCategory.foodBeverage), 61);
      expect(days[0].taxFor(LedgerCategory.spaActivities), 0);
      expect(days[0].tax, 301);
      expect(days[0].total, 2800 + 301);
      final total = ledgerTotal(days);
      expect(total.taxFor(LedgerCategory.spaActivities), 360);
      expect(total.taxFor(LedgerCategory.foodBeverage), 61);
      expect(total.tax, 661);
    });
```

In `test/features/finance/finance_csv_test.dart`, replace the whole test `"today's file lists every figure for the resort's today"` with:

```dart
  test("today's file lists every figure for the resort's today", () {
    final rows = todayCsv(financeSummary(
      online: 1000,
      desk: {PaymentMethod.cash: 2800, PaymentMethod.card: 120},
      refunds: 600,
      roomTax: 240,
      foodTax: 72.25,
      spaTax: 468,
      inHouseCount: 1,
      inHouseBalance: 1200,
    ));

    expect(rows[1], ['Period', '2026-09-25', '2026-09-25']);
    expect(rows.skip(2).toList(), [
      ['Figure', 'Amount'],
      ['Online collected', '1000.00'],
      ['Desk collected', '2920.00'],
      ['Desk: Cash', '2800.00'],
      ['Desk: Card', '120.00'],
      ['Desk: UPI', '0.00'],
      ['Desk: Bank transfer', '0.00'],
      ['Desk: Other', '0.00'],
      ['Refunds', '600.00'],
      ['Net collected', '3320.00'],
      ['Room tax', '240.00'],
      ['F&B tax', '72.25'],
      ['Spa tax', '468.00'],
      ['In-house guests', '1'],
      ['In-house unpaid balance', '1200.00'],
    ]);
  });
```

In `test/features/finance/finance_screen_test.dart`:

1. In the `Today` test `"shows the day's figures of the current resort"`, add `foodTax: 72.25,` and `spaTax: 468,` after `roomTax: 240,` in the `financeSummary(...)` call, and after the line `expect(_inKey('today-room-tax', '₹240.00'), findsOneWidget);` add:

```dart
      expect(_inKey('today-food-tax', '₹72.25'), findsOneWidget);
      expect(_inKey('today-spa-tax', '₹468.00'), findsOneWidget);
```

2. In `'the tax strip shows taxable, tax, the rate and the GSTIN'`, replace:

```dart
      expect(_inKey('ledger-tax-strip', 'Current rate 12%'), findsOneWidget);
```

with:

```dart
      expect(_inKey('ledger-tax-strip', 'Room rate 12%'), findsOneWidget);
```

3. In `'a wide screen shows a table with a Total row'`, replace the header list:

```dart
      for (final header in ['Room', 'F&B', 'Spa/Activities', 'Ancillary', 'Taxable', 'Tax', 'Total']) {
```

with:

```dart
      for (final header in [
        'Room', 'F&B', 'Spa/Activities', 'Ancillary', 'Taxable',
        'Room tax', 'F&B tax', 'Spa/Activities tax', 'Ancillary tax', 'Tax', 'Total',
      ]) {
```

4. Add these tests at the end of `group('Ledger', () { … })`:

```dart
    final withSpa = [
      ...rows,
      ledgerRow(
          day: DateTime(2026, 8, 11),
          category: LedgerCategory.spaActivities,
          source: 'activity_booking',
          gross: 2000,
          tax: 360),
    ];

    testWidgets('the tax strip lists the tax of each category and every rate', (tester) async {
      await _pump(
          tester,
          FakeFinanceSource()
            ..ledgerRows = withSpa
            ..summaryValue = financeSummary(resort: financeResort(fnbTaxPct: 5, spaTaxPct: 18)));
      await _openTab(tester, 'Ledger');

      expect(_inKey('ledger-tax-strip', 'Room tax ₹1,080.00'), findsOneWidget);
      expect(_inKey('ledger-tax-strip', 'Ancillary tax ₹60.00'), findsOneWidget);
      expect(_inKey('ledger-tax-strip', 'Spa/Activities tax ₹360.00'), findsOneWidget);
      // No F&B tax in the period: no line for it.
      expect(_inKey('ledger-tax-strip', 'F&B tax ₹0.00'), findsNothing);
      expect(_inKey('ledger-tax-strip', 'Tax ₹1,500.00'), findsOneWidget);
      expect(_inKey('ledger-tax-strip', 'Room rate 12%'), findsOneWidget);
      expect(_inKey('ledger-tax-strip', 'F&B rate 5%'), findsOneWidget);
      expect(_inKey('ledger-tax-strip', 'Spa/Activities rate 18%'), findsOneWidget);
    });

    testWidgets("a phone card lists each category's tax under Tax", (tester) async {
      await _pump(tester, FakeFinanceSource()..ledgerRows = withSpa);
      await _openTab(tester, 'Ledger');

      expect(_inKey('ledger-2026-08-10', 'Room tax ₹1,080.00'), findsOneWidget);
      expect(_inKey('ledger-2026-08-10', 'Ancillary tax ₹60.00'), findsOneWidget);
      expect(_inKey('ledger-2026-08-11', 'Tax ₹360.00'), findsOneWidget);
      expect(_inKey('ledger-2026-08-11', 'Spa/Activities tax ₹360.00'), findsOneWidget);
      expect(_inKey('ledger-2026-08-11', 'F&B tax ₹0.00'), findsNothing);
    });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/finance`
Expected: FAIL: `The method 'taxFor' isn't defined for the type 'LedgerDay'` (compile error in `finance_tables_test.dart`); the CSV test is missing the `F&B tax` line; the screen tests miss `today-food-tax` and `Room rate 12%`.

- [ ] **Step 3: Implement**

In `lib/features/finance/finance_tables.dart`, replace everything from the doc comment `/// One day of the Ledger view: each category's taxable amount, and the` down to the end of `ledgerTotal` with:

```dart
/// One day of the Ledger view: each category's taxable amount and each
/// category's tax. [day] is null on the totals row.
class LedgerDay {
  const LedgerDay({
    this.day,
    this.byCategory = const {},
    this.taxByCategory = const {},
  });

  final DateTime? day;
  final Map<LedgerCategory, num> byCategory;
  final Map<LedgerCategory, num> taxByCategory;

  num categoryTotal(LedgerCategory category) => byCategory[category] ?? 0;
  num taxFor(LedgerCategory category) => taxByCategory[category] ?? 0;
  num get taxable => _sum(byCategory.values);
  num get tax => _sum(taxByCategory.values);
  num get total => taxable + tax;
}

/// Pivots `report_ledger` lines into one [LedgerDay] per day, oldest first.
List<LedgerDay> ledgerByDay(List<LedgerRow> rows) {
  final byDay = <DateTime, Map<LedgerCategory, num>>{};
  final taxByDay = <DateTime, Map<LedgerCategory, num>>{};
  for (final r in rows) {
    final categories = byDay.putIfAbsent(r.day, () => {});
    categories[r.category] = (categories[r.category] ?? 0) + r.taxable;
    final taxes = taxByDay.putIfAbsent(r.day, () => {});
    taxes[r.category] = (taxes[r.category] ?? 0) + r.tax;
  }
  return [
    for (final d in byDay.keys.toList()..sort())
      LedgerDay(day: d, byCategory: byDay[d]!, taxByCategory: taxByDay[d]!),
  ];
}

/// The totals row of [days].
LedgerDay ledgerTotal(List<LedgerDay> days) => LedgerDay(
      byCategory: {
        for (final c in LedgerCategory.values)
          c: _sum(days.map((d) => d.categoryTotal(c))),
      },
      taxByCategory: {
        for (final c in LedgerCategory.values)
          c: _sum(days.map((d) => d.taxFor(c))),
      },
    );
```

In `lib/features/finance/finance_ledger_tab.dart`:

Replace the `_columns` block and its doc comment:

```dart
/// Category columns hold taxable amounts, so they add up to Taxable, and
/// Taxable + Tax = Total.
final List<_Column> _columns = [
  for (final c in LedgerCategory.values) (label: c.label, value: (d) => d.categoryTotal(c)),
  (label: 'Taxable', value: (d) => d.taxable),
  (label: 'Tax', value: (d) => d.tax),
];
```

with:

```dart
/// Category columns hold taxable amounts, so they add up to Taxable; the
/// category tax columns add up to Tax; and Taxable + Tax = Total.
final List<_Column> _columns = [
  for (final c in LedgerCategory.values) (label: c.label, value: (d) => d.categoryTotal(c)),
  (label: 'Taxable', value: (d) => d.taxable),
  for (final c in LedgerCategory.values) (label: '${c.label} tax', value: (d) => d.taxFor(c)),
  (label: 'Tax', value: (d) => d.tax),
];
```

Replace the `FinanceLedgerTab` doc comment:

```dart
/// The Ledger tab: revenue earned per day by category (accrual basis),
/// with room tax as fixed in each booking's quote, a totals row and a tax
/// strip.
```

with:

```dart
/// The Ledger tab: revenue earned per day by category (accrual basis),
/// with tax per category -- room tax as fixed in each booking's quote,
/// food and spa tax as stored on each order and sale -- a totals row and a
/// tax strip.
```

In `_TaxStrip.build`, replace the `children:` list:

```dart
          children: [
            Text('Taxable ${formatMoney(total.taxable)}'),
            Text('Tax ${formatMoney(total.tax)}'),
            if (r != null) Text('Current rate ${formatPct(r.taxPct)}%'),
            if (r != null) Text(gstinLabel(r)),
            Text("Each booking's own rate is in Settlements.",
                style: Theme.of(context).textTheme.bodySmall),
          ],
```

with:

```dart
          children: [
            Text('Taxable ${formatMoney(total.taxable)}'),
            Text('Tax ${formatMoney(total.tax)}'),
            for (final c in LedgerCategory.values)
              if (total.taxFor(c) != 0)
                Text('${c.label} tax ${formatMoney(total.taxFor(c))}'),
            if (r != null) Text('Room rate ${formatPct(r.taxPct)}%'),
            if (r != null) Text('F&B rate ${formatPct(r.fnbTaxPct)}%'),
            if (r != null) Text('Spa/Activities rate ${formatPct(r.spaTaxPct)}%'),
            if (r != null) Text(gstinLabel(r)),
            Text('Each booking and sale keeps the rate it was made at.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
```

In `_LedgerCard.build`, replace:

```dart
              Text('Tax ${formatMoney(day.tax)}'),
```

with:

```dart
              Text('Tax ${formatMoney(day.tax)}'),
              for (final c in LedgerCategory.values)
                if (day.taxFor(c) != 0)
                  Text('${c.label} tax ${formatMoney(day.taxFor(c))}',
                      style: Theme.of(context).textTheme.bodySmall),
```

In `lib/features/finance/finance_today_tab.dart`, replace the doc comment:

```dart
/// The Today tab: money in and out today in the resort's own timezone,
/// room tax, and what the guests in house still owe. Everything comes from
/// one `finance_summary` call.
```

with:

```dart
/// The Today tab: money in and out today in the resort's own timezone,
/// room, food & drink and spa tax, and what the guests in house still owe.
/// Everything comes from one `finance_summary` call.
```

and after the `today-room-tax` card:

```dart
                _FigureCard(
                  key: const Key('today-room-tax'),
                  icon: Icons.receipt_long_outlined,
                  label: 'Room tax',
                  value: formatMoney(s.roomTax),
                ),
```

insert:

```dart
                _FigureCard(
                  key: const Key('today-food-tax'),
                  icon: Icons.restaurant_outlined,
                  label: 'F&B tax',
                  value: formatMoney(s.foodTax),
                ),
                _FigureCard(
                  key: const Key('today-spa-tax'),
                  icon: Icons.spa_outlined,
                  label: 'Spa tax',
                  value: formatMoney(s.spaTax),
                ),
```

In `lib/features/finance/finance_csv.dart`, in `todayCsv`, after:

```dart
      ['Room tax', csvMoney(s.roomTax)],
```

insert:

```dart
      ['F&B tax', csvMoney(s.foodTax)],
      ['Spa tax', csvMoney(s.spaTax)],
```

In `lib/features/owner/owner_reports_screen.dart`, in the `Ledger` `_ReportTile`, replace:

```dart
            subtitle: 'Revenue by category with room tax',
```

with:

```dart
            subtitle: 'Revenue and tax by category',
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/finance test/features/owner/owner_reports_screen_test.dart test/data/finance_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `flutter analyze 2>&1 | tail -1`
Expected: the Task 1 baseline count.

- [ ] **Step 6: Commit**

```bash
git add lib/features/finance/finance_tables.dart lib/features/finance/finance_ledger_tab.dart \
  lib/features/finance/finance_today_tab.dart lib/features/finance/finance_csv.dart \
  lib/features/owner/owner_reports_screen.dart test/features/finance/finance_tables_test.dart \
  test/features/finance/finance_screen_test.dart test/features/finance/finance_csv_test.dart
git commit -m "feat(tax): finance ledger, today tab and CSV show tax per category" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 6: The guest's bill shows the tax inside food and activities

**Track:** App. Depends on Task 1.

**Files:**
- Create: `lib/features/stay/included_tax_line.dart`
- Modify: `lib/features/stay/current_charges_screen.dart`, `lib/features/stay/final_invoice_screen.dart`
- Test: `test/features/stay/current_charges_screen_test.dart` (new), `test/features/stay/final_invoice_screen_test.dart` (new)

**Interfaces:**
- Consumes: `CurrentCharges.foodTax`/`.activityTax` (Task 1); `currentChargesProvider` (`lib/data/repositories/stay_repository.dart`, `FutureProvider.family<CurrentCharges, String>`); `reservationProvider` (`lib/features/booking/providers.dart`, `FutureProvider.family<Reservation, String>`); `formatMoney` (`lib/features/finance/finance_tables.dart`).
- Produces: `IncludedTaxLine({Key? key, required num amount})` rendering `Includes tax ₹x.xx`. Keys `charges-food-tax`, `charges-activity-tax` (Current Charges) and `invoice-food-tax`, `invoice-activity-tax` (Final Invoice), present only when that tax is above 0.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/stay/current_charges_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/stay/current_charges_screen.dart';

Future<void> _pump(WidgetTester tester, CurrentCharges charges) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [currentChargesProvider.overrideWith((ref, id) async => charges)],
    child: const MaterialApp(home: CurrentChargesScreen(reservationId: 'r1')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the tax inside food and inside activities', (tester) async {
    await _pump(
        tester,
        const CurrentCharges(
          stayAmount: 5000,
          foodAmount: 630,
          foodTax: 36.25,
          activityAmount: 2360,
          activityTax: 360,
          total: 7990,
          paid: 0,
          balance: 7990,
        ));

    expect(find.text('₹630'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('charges-food-tax')),
            matching: find.text('Includes tax ₹36.25')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('charges-activity-tax')),
            matching: find.text('Includes tax ₹360.00')),
        findsOneWidget);
  });

  testWidgets('no tax line when there is no tax', (tester) async {
    await _pump(
        tester,
        const CurrentCharges(
          stayAmount: 3000,
          foodAmount: 200,
          activityAmount: 0,
          total: 3200,
          paid: 1000,
          balance: 2200,
        ));

    expect(find.textContaining('Includes tax'), findsNothing);
  });
}
```

Create `test/features/stay/final_invoice_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/booking/providers.dart';
import 'package:pasala/features/stay/final_invoice_screen.dart';

final _reservation = Reservation.fromJson(const {
  'id': '44444444-0000-4000-8000-000000000051',
  'unit_id': 'u1',
  'period': '["2026-08-03 08:30:00+00","2026-08-04 05:30:00+00")',
  'kind': 'booking',
  'status': 'checked_out',
});

Future<void> _pump(WidgetTester tester, CurrentCharges charges) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      reservationProvider.overrideWith((ref, id) async => _reservation),
      currentChargesProvider.overrideWith((ref, id) async => charges),
    ],
    child: MaterialApp(home: FinalInvoiceScreen(reservationId: _reservation.id)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the tax inside food and inside activities', (tester) async {
    await _pump(
        tester,
        const CurrentCharges(
          stayAmount: 5000,
          foodAmount: 525,
          foodTax: 25,
          activityAmount: 2360,
          activityTax: 360,
          total: 7885,
          paid: 7885,
          balance: 0,
        ));

    expect(
        find.descendant(
            of: find.byKey(const Key('invoice-food-tax')),
            matching: find.text('Includes tax ₹25.00')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('invoice-activity-tax')),
            matching: find.text('Includes tax ₹360.00')),
        findsOneWidget);
    expect(find.text('₹7,885'), findsNWidgets(2)); // Final amount and Paid
  });

  testWidgets('no tax line when there is no tax', (tester) async {
    await _pump(
        tester,
        const CurrentCharges(
          stayAmount: 3000,
          foodAmount: 0,
          activityAmount: 0,
          total: 3000,
          paid: 3000,
          balance: 0,
        ));

    expect(find.textContaining('Includes tax'), findsNothing);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/stay/current_charges_screen_test.dart test/features/stay/final_invoice_screen_test.dart`
Expected: FAIL: no widget with key `charges-food-tax` / `invoice-food-tax`. The "no tax line" tests already pass.

- [ ] **Step 3: Implement**

Create `lib/features/stay/included_tax_line.dart`:

```dart
import 'package:flutter/material.dart';

import '../finance/finance_tables.dart' show formatMoney;

/// "Includes tax ₹25.00" under a tax-inclusive bill line (food, activities):
/// the amount above it already contains this tax, stored on each order and
/// booking when it was made (`0053_food_spa_tax.sql`). Paise are kept,
/// unlike the whole-rupee `formatInr` lines around it, because tax is
/// rarely a round figure.
class IncludedTaxLine extends StatelessWidget {
  const IncludedTaxLine({super.key, required this.amount});

  final num amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'Includes tax ${formatMoney(amount)}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
```

In `lib/features/stay/current_charges_screen.dart`, add the import after `import '../../data/repositories/stay_repository.dart';`:

```dart
import 'included_tax_line.dart';
```

and replace:

```dart
                    Row(children: [
                      const Expanded(child: Text('Food')),
                      Text(formatInr(charges.foodAmount)),
                    ]),
                    const SizedBox(height: Spacing.xs),
                    Row(children: [
                      const Expanded(child: Text('Activities')),
                      Text(formatInr(charges.activityAmount)),
                    ]),
```

with:

```dart
                    Row(children: [
                      const Expanded(child: Text('Food')),
                      Text(formatInr(charges.foodAmount)),
                    ]),
                    if (charges.foodTax > 0)
                      IncludedTaxLine(
                          key: const Key('charges-food-tax'), amount: charges.foodTax),
                    const SizedBox(height: Spacing.xs),
                    Row(children: [
                      const Expanded(child: Text('Activities')),
                      Text(formatInr(charges.activityAmount)),
                    ]),
                    if (charges.activityTax > 0)
                      IncludedTaxLine(
                          key: const Key('charges-activity-tax'),
                          amount: charges.activityTax),
```

In `lib/features/stay/final_invoice_screen.dart`, add the import after `import '../booking/providers.dart' show reservationProvider;`:

```dart
import 'included_tax_line.dart';
```

and replace:

```dart
                      Row(children: [
                        const Expanded(child: Text('Food')),
                        Text(formatInr(charges.foodAmount)),
                      ]),
                      const SizedBox(height: Spacing.xs),
                      Row(children: [
                        const Expanded(child: Text('Activities')),
                        Text(formatInr(charges.activityAmount)),
                      ]),
```

with:

```dart
                      Row(children: [
                        const Expanded(child: Text('Food')),
                        Text(formatInr(charges.foodAmount)),
                      ]),
                      if (charges.foodTax > 0)
                        IncludedTaxLine(
                            key: const Key('invoice-food-tax'), amount: charges.foodTax),
                      const SizedBox(height: Spacing.xs),
                      Row(children: [
                        const Expanded(child: Text('Activities')),
                        Text(formatInr(charges.activityAmount)),
                      ]),
                      if (charges.activityTax > 0)
                        IncludedTaxLine(
                            key: const Key('invoice-activity-tax'),
                            amount: charges.activityTax),
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/stay test/core/router_test.dart`
Expected: PASS (`router_test.dart` builds `CurrentCharges` without the new fields, which default to 0).

- [ ] **Step 5: Analyze**

Run: `flutter analyze 2>&1 | tail -1`
Expected: the Task 1 baseline count.

- [ ] **Step 6: Commit**

```bash
git add lib/features/stay/included_tax_line.dart lib/features/stay/current_charges_screen.dart \
  lib/features/stay/final_invoice_screen.dart test/features/stay/current_charges_screen_test.dart \
  test/features/stay/final_invoice_screen_test.dart
git commit -m "feat(tax): guest bill shows the tax inside food and activities" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: A walk-in sale shows the tax it includes

**Track:** App. Depends on Task 1.

**Files:**
- Modify: `lib/features/owner/food_sales_screen.dart` (imports; the row `subtitle`)
- Test: `test/features/owner/food_sales_screen_test.dart`

**Interfaces:**
- Consumes: `FoodSale.taxAmount` (Task 1); `formatMoney` (`lib/features/finance/finance_tables.dart`).
- Produces: nothing other tasks use.

- [ ] **Step 1: Write the failing test**

In `test/features/owner/food_sales_screen_test.dart`, add inside `main()`, after the test `'shows an empty state when no sales exist yet'`:

```dart
  testWidgets('a sale shows the tax it includes', (tester) async {
    final repo = FakeFoodSaleRepository()
      ..store.add(FoodSale(
        id: 's1',
        propertyId: 'p1',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Walk-in thali',
        quantity: 1,
        unitPrice: 210,
        amount: 210,
        taxPct: 12,
        taxAmount: 22.5,
      ))
      ..store.add(FoodSale(
        id: 's2',
        propertyId: 'p1',
        saleDate: DateTime.now(),
        category: SaleCategory.food,
        itemName: 'Tea',
        quantity: 1,
        unitPrice: 20,
        amount: 20,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byKey(const Key('sale-row-s1')),
            matching: find.textContaining('Includes tax ₹22.50')),
        findsOneWidget);
    // A sale without tax (logged at 0%, or before 0053) says nothing.
    expect(
        find.descendant(
            of: find.byKey(const Key('sale-row-s2')),
            matching: find.textContaining('Includes tax')),
        findsNothing);
  });
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/features/owner/food_sales_screen_test.dart --plain-name 'a sale shows the tax it includes'`
Expected: FAIL: `Expected: exactly one matching candidate` for `Includes tax ₹22.50`.

- [ ] **Step 3: Implement**

In `lib/features/owner/food_sales_screen.dart`, add after `import '../finance/providers.dart';`:

```dart
import '../finance/finance_tables.dart' show formatMoney;
```

and replace the row subtitle:

```dart
                          subtitle: Text(
                            '${_categoryLabel(sale.category)} · '
                            '${sale.paymentMethod.label} · '
                            '${formatDate(sale.saleDate)} · '
                            '${sale.quantity} × ${formatInr(sale.unitPrice)}',
                          ),
```

with:

```dart
                          subtitle: Text(
                            '${_categoryLabel(sale.category)} · '
                            '${sale.paymentMethod.label} · '
                            '${formatDate(sale.saleDate)} · '
                            '${sale.quantity} × ${formatInr(sale.unitPrice)}'
                            // The tax inside the amount, stored by the
                            // server when the sale was logged (0053).
                            '${sale.taxAmount > 0 ? ' · Includes tax ${formatMoney(sale.taxAmount)}' : ''}',
                          ),
```

- [ ] **Step 4: Run the file**

Run: `flutter test test/features/owner/food_sales_screen_test.dart`
Expected: PASS (every earlier test too: their sales have tax 0 and no tax text).

- [ ] **Step 5: Analyze**

Run: `flutter analyze 2>&1 | tail -1`
Expected: the Task 1 baseline count.

- [ ] **Step 6: Commit**

```bash
git add lib/features/owner/food_sales_screen.dart test/features/owner/food_sales_screen_test.dart
git commit -m "feat(tax): walk-in sales list shows the tax each sale includes" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 3: Integration

### Task 8: Merge the tracks and verify end to end

**Track:** both. Depends on Tasks 2–7.

**Files:** none (verification only; fix forward in the task that owns a failing file).

**Interfaces:**
- Consumes: everything above.
- Produces: a branch where the database suite, the Flutter suite and the analyzer all pass together.

- [ ] **Step 1: Bring both tracks onto one branch**

If the tracks ran in separate worktrees, merge the database track branch and the app track branch into this plan's branch (they touch disjoint files, so no conflicts are expected):

```bash
git merge --no-ff <db-track-branch> -m "Merge P4 database track" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git merge --no-ff <app-track-branch> -m "Merge P4 app track" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Rebuild the database and run every pgTAP suite**

Run: `supabase db reset && supabase test db`
Expected: PASS, including `44_food_spa_tax_test.sql` (`1..67`), `37_tenancy_isolation_test.sql` and `40_finance_ledger_test.sql`.

- [ ] **Step 3: Run the whole Flutter suite and the analyzer**

Run: `flutter test && flutter analyze 2>&1 | tail -1`
Expected: all tests pass; the analyzer count equals the Task 1 baseline.

- [ ] **Step 4: Check the contract end to end against the local database**

With the local stack from Step 2 running, confirm the JSON the app parses now has the keys it reads (seed data, rates 0):

```bash
psql "$(supabase status -o env | grep '^DB_URL=' | cut -d= -f2- | tr -d '"')" -c \
  "select column_name from information_schema.columns where table_schema='public' and table_name='properties' and column_name in ('fnb_tax_pct','spa_tax_pct') order by 1;"
```

Expected: two rows, `fnb_tax_pct` and `spa_tax_pct`.

- [ ] **Step 5: Spec coverage check**

Walk the spec's Decisions 1–18 and its App section. Each is implemented by: 1 → Task 1; 2, 3, 7, 8, 9, 10, 16 → Task 2; 4, 12 → Task 4; 5, 13, 14 → Tasks 3 and 5; 6 → Task 1 (test 1); 11 → Tasks 1 (Dart) and 2 (SQL); 15 → Tasks 3 and 6; 17 → Task 7; 18 → no change (Settlements untouched). Fix anything missing in the owning task's files and re-run Steps 2–3.

- [ ] **Step 6: Commit (only if Steps 1–5 changed anything)**

```bash
git status --short
git commit -am "chore(tax): integration fixes for food and spa tax" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage.** Rates and range (Task 1 columns, Task 2 P0035 trigger, Task 4 screen). Tax-inclusive formula (Task 2 `inclusive_tax`). Tax stored at sale/order time on all four tables and never rewritten (Task 2 triggers and tests 31–55). Existing rows 0 (Task 1 test 1). Owner Taxes screen (Task 4). Ledger per category (Task 3 `report_ledger`, Task 5 UI). Invoices per category (Task 3 `current_charges`, Task 6 Current Charges and Final Invoice). `finance_summary` room/food/spa tax and rates (Task 3, Task 5 Today). Walk-in list (Task 7). No gaps found.
- **Placeholder scan.** Every code step shows its code. Task 3 Step 1 says what to do if another project redefined a function first. Task 8 Step 1's `<db-track-branch>`/`<app-track-branch>` are the executor's own branch names.
- **Type consistency.** `inclusive_tax(numeric, numeric)` in Tasks 1–3. JSON keys `food_tax`/`activity_tax` (`current_charges`) and `food_tax`/`spa_tax`/`fnb_tax_pct`/`spa_tax_pct` (`finance_summary`) match `CurrentCharges.fromJson` and `FinanceSummary`/`FinanceResort.fromJson` in Task 1. Dart names used in Tasks 4–7 (`fnbTaxPct`, `spaTaxPct`, `foodTax`, `activityTax`, `spaTax`, `taxAmount`, `taxFor`, `taxByCategory`, `TaxRateOutOfRange`, `IncludedTaxLine`) are the ones defined in Tasks 1, 5 and 6.
- **Review Focus.** Items 1–5 each have their test in the owning task: Task 4 (`a rate that is not a number is refused`), Task 2 (tests 34–35, 44–45, 54–55; and 48–49), Task 3 (tests 58 and 67), Task 1 model tests plus Task 6 (`no tax line when there is no tax`).
