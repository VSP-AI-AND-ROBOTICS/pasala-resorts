# Finance Ledger and Collections (REQ-07) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give owners, admins and accountants a Finance screen for one resort: money collected online and at the desk by method (cash basis), revenue earned by category with room tax (accrual basis), settled checkouts, and today's figures, all exportable as CSV. The front desk records the method and reference of every desk payment and walk-in sale.

**Architecture:** Migration `0048_finance_ledger.sql` adds `payments.method`, `payments.reference` and `payments.recorded_by`, turns `food_activity_sales.payment_method` into the same enum, and teaches `checkout_booking` a `p_method` argument. Four read-only `security definer` functions (`report_collections`, `report_ledger`, `report_settlements`, `finance_summary`) work every figure out from the source rows in the resort's timezone. No new tables and no triggers. On the app side, a `FinanceSource` seam sits behind Riverpod providers keyed by property id (or by `ReportFilter`), feeding a new `/finance` screen with four tabs, the owner export centre, desk checkout at reception, and the walk-in sales form.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`), Flutter 3.44 / Dart 3.10, Riverpod 3.3, go_router 17, intl.

**Spec:** `docs/superpowers/specs/2026-09-25-finance-ledger-design.md`

## Global Constraints

- **This plan starts after Project B (room status, `docs/superpowers/plans/2026-09-25-room-status-grid.md`) has merged into `feat/client-reqs`.** Cut this plan's branch from `feat/client-reqs` at or after that merge. Task 1 Step 1 checks it.
- One migration: `supabase/migrations/0048_finance_ledger.sql`. It runs after B's `0047_room_status.sql`. Tasks 1–5 each edit it. After every edit, rebuild with `supabase db reset` (this re-runs every migration and `supabase/seed.sql`), then run pgTAP. Before the first reset in this plan, dump local data if you need it: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-finance.sql`.
- New pgTAP file: `supabase/tests/40_finance_ledger_test.sql` (39 is Project B's). All fixtures are at its top (Task 1). Tasks 2–5 each append one section, and each section relies on the state the sections before it leave. Run one file with `supabase test db supabase/tests/40_finance_ledger_test.sql` and the whole suite with `supabase test db`.
- `checkout_booking`'s body is copied from its **latest** definition, which is B's `0047_room_status.sql` (it marks the room dirty). Copy it from the actual merged file, not from B's plan (Task 1 Step 5 shows how). Only the method handling is new.
- No new error codes. A guest recording a desk method raises the existing **P0009** with the message `desk payment methods are recorded by resort staff`. The existing codes keep their meaning: P0002 not found, P0008 authentication required, P0009 bad payment, P0020 not_a_member, P0022 resort_suspended.
- Every new `security definer` function has `set search_path = public, pg_temp`, is `stable` (the four reports), is revoked from `public` and `anon`, is granted to `authenticated`, and is on the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`.
- Role sets. Read any finance report: `owner, admin, accountant` at `p_property_id`, through `assert_resort_role(p_property_id, false, …)`. Record a desk method at checkout: `has_resort_role(<booking's resort>, true, 'owner','admin','staff','accountant')`.
- Every report takes a required `p_property_id uuid` (no default), works out days in `properties.timezone` of that resort, counts only `payments.status = 'succeeded'`, excludes cancelled food orders and cancelled activity bookings, and returns every amount rounded to 2 decimals.
- Suspended resort: reports readable, `checkout_booking` P0022. Archived resort: P0020.
- No existing policy on `payments`, `food_activity_sales` or `reservations` is widened.
- pgTAP conventions (from `37_tenancy_isolation_test.sql`): switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`. `reset role` does **not** clear the claims, so run `set local request.jwt.claims to '';` before any superuser change that a trigger checks against `auth.uid()` (resort status).
- Dart: repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`). Finance providers are `autoDispose` families keyed by property id or by `ReportFilter` (`lib/features/reports/providers.dart`), and screens read the id from `currentResortProvider`. Widget tests use `FakeFinanceSource` (`test/support/fake_finance_source.dart`) and never a real `SupabaseClient`.
- Money on the Finance screen keeps its paise: `formatMoney(1080)` is `₹1,080.00`. CSV amounts are plain `1080.00` (no symbol, no grouping). Checkout buttons keep `formatInr` (`₹2,000`).
- UI copy, exact:
  - Tabs: `Today`, `Collections`, `Ledger`, `Settlements`. Screen title `Finance`.
  - Method labels: `Online` (gateway), `Cash`, `Card`, `UPI`, `Bank transfer`, `Other`. Collections column for bank transfer: `Bank`.
  - Desk checkout: `Payment method`, `Reference (optional)`, helper `Receipt, card slip or UTR number`, button `Record ₹<balance> and check out` (`Check out` when nothing is due).
  - Export messages: `CSV exported.`, `CSV export isn't available on this platform yet.`, `Still loading -- try again in a moment.`, `This report didn't load, so there is nothing to export.`
  - CSV: line 1 `<resort name>,GSTIN <gstin>` (or `<resort name>,GSTIN not set`), line 2 `Period,<from>,<to>`, then the column header. File name `<slug>-<report>-<from>-<to>.csv`, dates `yyyy-MM-dd`.
- A non-zero outstanding balance is shown with an icon and text, never colour alone.
- Commands: `flutter test <path>`, `flutter test`, and `flutter analyze` (no new issues beyond the baseline recorded in Task 1 Step 1). Never run `dart format` over whole directories, because the repo is not formatted with the current SDK. Format only the lines you write.

## Review Focus

1. **A guest who is staff at a *different* resort passes a desk method for their own stay here.** The role that allows a desk method must be at the booking's resort, so they get P0009 and the booking stays checked in. Owning test: Task 2 (`a member of another resort cannot record a desk method here`).
2. **Reception retries a desk checkout after a timeout, possibly with a different method.** The first call already wrote the payment. The retry must return the booking without a second payment and without changing the first row's method or reference. Owning test: Task 2 (`the retry writes no second payment and changes nothing`).
3. **Editing an existing walk-in sale.** Today's form rebuilds the `FoodSale` without `paymentMethod`, so an edit would silently reset the method. The edit must keep the method the sale already had. Owning test: Task 12 (`editing a sale keeps its payment method`).
4. **Desk checkout of a booking with nothing left to pay.** There must be no "Record ₹0" button and no method to pick, and no payment row. Owning tests: Task 2 (`nothing left to pay writes no payment`) and Task 11 (`with nothing left to pay there is no method to pick`).
5. **Pressing Export before a tab has loaded, or after it failed.** The app must say so and must not deliver a header-only CSV as if it were the report. Owning tests: Task 7 (`Export before the report has loaded says so and writes nothing`, `Export after a failed load says so and writes nothing`).

## Plan decisions (where the spec is silent or leaves a choice)

- **`checkout_booking` in Task 1.** The contract task drops the three-argument function and creates the four-argument one with the body copied verbatim from 0047. `p_method` is accepted but unused until Task 2. This fixes the signature both sides build against, and keeps `33_stay_checkout_test.sql`, `35_customer_checkout_test.sql` and B's `39_room_status_test.sql` green throughout the database track (a stub raising `0A000` would break them).
- **Legacy walk-in text mapping lives in `public.payment_method_from_text(text)`**, an `immutable` SQL helper used in the `alter column … using` clause. pgTAP cannot insert legacy text after the column has changed type, so the helper is what the mapping tests call. It is not `security definer`, so it is not on the allow-list.
- **The method check sits before the idempotent early return** in `checkout_booking`: a guest passing a desk method gets P0009 even on an already checked-out booking. Nothing is written either way.
- **`finance_summary.refunds` is a positive amount** (money out). `net_collected = online_collected + desk_collected.total − refunds`. `desk_collected` includes walk-in sales, which are front-desk money. `finance_summary` works these out by calling `report_collections(today, today, …)`, so the Today tab and the Collections tab can never disagree.
- **`finance_summary.room_tax` is all of today's Ledger tax.** Tax exists only on bookings, and a booking's tax is split between its room line and its cleaning-fee line (spec). The two together are "room tax".
- **Settlement columns:** `room` is the room line's taxable amount (subtotal minus its share of the coupon), `cleaning_fee` is the cleaning line's taxable amount, `tax` is the quote's `tax_amount`, `tax_pct` is the quote's rate. So `room + cleaning_fee + tax + food + activities = total`. A total-only quote puts its whole total in `room`. `recorded_by_name` is the profile name on the booking's balance payment, whichever channel it came through. `desk_method` and `desk_reference` are null when the balance came through the gateway.
- **Collections view columns:** `Online` is online money that is not a refund. `Refunds` is a separate, negative column. The desk columns follow `PaymentMethod.desk`. **Ledger view columns** show each category's *taxable* amount, so `Room + F&B + Spa/Activities + Ancillary = Taxable` and `Taxable + Tax = Total`.
- **CSV values:** channel, source, category and method are written as their wire values (`front_desk`, `walk_in_sale`, `food_beverage`, `bank_transfer`). They are stable and sort cleanly in a spreadsheet.
- **The Today tab also exports** (spec: "each [tab] with … Export CSV"): one line per figure, dated by the resort's today.
- **Finance providers are `autoDispose`.** Opening the screen or a tab always queries afresh ("live query on open"). The owner export centre calls `FinanceSource` directly instead of reading `autoDispose` providers without a listener.
- **`csvDownloaderProvider`** wraps `downloadCsv` so widget tests can capture the file name and contents. The export centre's four existing reports switch to it too (one line each).
- **`FoodSale.paymentMethod` is a non-nullable `PaymentMethod` with the constructor default `PaymentMethod.cash`,** rather than a `required` named parameter. The database column is `not null default 'cash'`, the form always sends a value, and every existing `FoodSale(...)` in the tests still compiles.
- **Desk checkout with nothing due** sends `PaymentMethod.gateway` and no reference: no payment is written, so there is no method to record.
- **After checkout, desk mode goes to the same invoice screen as guest mode** (`/my-stay/invoice/<id>`), which is what reception's flow does today.
- **The range picker is hidden on the Today tab**, which always shows the resort's today.
- **Accountant bar** (controller ruling): Finance, Rooms, Dashboard, Reports. Today is dropped. Staff keep Today, Rooms, Dashboard, Reports.
- **`/finance` sits inside the signed-in `ShellRoute`.** The owner hub gets a Finance tile (after Business dashboard) and the admin More screen a Finance entry (after Financial Dashboard).

## Execution tracks

After Task 1, the database track and the app track share no files and can run in parallel, for example in two worktrees branched from Task 1's commit and merged back before Task 13. App tasks never need a database, because their tests use `FakeFinanceSource` and fakes of `StayRepository` / `FoodSaleRepository`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | B merged | `0048` (schema, stubs, `checkout_booking` signature), `40` (fixtures + contract), `37` (allow-list), `payment_method.dart`, `finance.dart`, `finance_repository.dart`, `features/finance/providers.dart`, `fake_finance_source.dart` |
| 2 `checkout_booking` records the method | DB | 1 | `0048`, `40` |
| 3 `report_collections` | DB | 2 | `0048`, `40` |
| 4 `report_ledger` | DB | 3 | `0048`, `40` |
| 5 `report_settlements`, `finance_summary`, tenancy | DB | 4 | `0048`, `40` |
| 6 Day tables and CSV | App | 1 | `finance_tables.dart`, `finance_csv.dart` |
| 7 Finance screen: Today and Collections | App | 6 | `finance_screen.dart`, `finance_today_tab.dart`, `finance_collections_tab.dart` |
| 8 Ledger and Settlements tabs | App | 7 | `finance_ledger_tab.dart`, `finance_settlements_tab.dart`, `finance_screen.dart` |
| 9 Navigation | App | 7 | `router.dart`, `app_shell.dart`, `owner_home_screen.dart`, `admin_more_screen.dart` |
| 10 Owner export centre | App | 6 | `owner_reports_screen.dart` |
| 11 Desk checkout | App | 9 | `stay_repository.dart`, `checkout_screen.dart`, `reception_checkout_screen.dart`, `router.dart` |
| 12 Walk-in sales method | App | 1 | `food_sale.dart`, `food_sales_screen.dart` |
| 13 Integration | both | 2–12 | none (verification) |

- The database track is strictly sequential: Tasks 2–5 share one migration file, one test file and one local Postgres.
- In the app track: 7 waits for 6; 8 and 9 wait for 7; 10 waits for 6; 11 waits for 9 (both edit `router.dart`); 12 needs only Task 1. So 10 and 12 can run alongside 7–9 and alongside each other.

---

## File Structure

**Database**
- Create `supabase/migrations/0048_finance_ledger.sql`: the `payment_method` enum, the new `payments` columns and index, the walk-in column conversion and its helper, `checkout_booking` with `p_method`, and the four report functions.
- Create `supabase/tests/40_finance_ledger_test.sql`: fixtures, contract, desk checkout, Collections, Ledger, Settlements, summary, tenancy and suspension.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: the definer allow-list.

**App**
- Create `lib/data/models/payment_method.dart`: `PaymentMethod` (wire value, label, icon, `desk`, `fromWire`).
- Create `lib/data/models/finance.dart`: `CollectionChannel`, `CollectionSource`, `LedgerCategory`, `CollectionRow`, `LedgerRow`, `SettlementRow`, `FinanceResort`, `FinanceSummary`.
- Create `lib/data/repositories/finance_repository.dart`: the `FinanceSource` seam, `FinanceRepository`, `financeRepositoryProvider`, `financeSourceProvider`.
- Create `lib/features/finance/providers.dart`: `financeSummaryProvider`, `collectionsProvider`, `ledgerProvider`, `settlementsProvider`, `invalidateFinance`, `CsvDownloader`, `csvDownloaderProvider`.
- Create `lib/features/finance/finance_tables.dart`: `formatMoney`, `isoDate`, `CollectionDay`/`collectionsByDay`/`collectionsTotal`, `LedgerDay`/`ledgerByDay`/`ledgerTotal`.
- Create `lib/features/finance/finance_csv.dart`: `csvMoney`, `gstinLabel`, `financeCsvHeader`, `financeCsvFileName`, `todayCsv`, `collectionsCsv`, `ledgerCsv`, `settlementsCsv`.
- Create `lib/features/finance/finance_screen.dart` (host: range, tabs, export), `finance_today_tab.dart`, `finance_collections_tab.dart`, `finance_ledger_tab.dart`, `finance_settlements_tab.dart`.
- Modify `lib/core/router.dart`: `/finance`, its role rule, the accountant landing, and `/my-stay/checkout` taking `DeskCheckoutArgs`.
- Modify `lib/features/shell/app_shell.dart`: the accountant bar.
- Modify `lib/features/owner/owner_home_screen.dart` and `lib/features/admin/admin_more_screen.dart`: Finance entries.
- Modify `lib/features/owner/owner_reports_screen.dart`: Collections, Ledger and Settlements exports.
- Modify `lib/data/repositories/stay_repository.dart`, `lib/features/stay/checkout_screen.dart`, `lib/features/admin/reception_checkout_screen.dart`: desk checkout.
- Modify `lib/data/models/food_sale.dart`, `lib/features/owner/food_sales_screen.dart`: the walk-in method.
- Create `test/support/fake_finance_source.dart`, `test/data/payment_method_test.dart`, `test/data/finance_test.dart`, `test/data/finance_provider_test.dart`, `test/data/food_sale_test.dart`, `test/features/finance/finance_tables_test.dart`, `test/features/finance/finance_csv_test.dart`, `test/features/finance/finance_screen_test.dart`, `test/features/owner/owner_reports_screen_test.dart`, `test/features/stay/checkout_screen_test.dart`. Modify the tests of every other file listed above.

---

## Phase 0: Interface

### Task 1: Interface contract (schema, function signatures, Dart API)

**Track:** both. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0048_finance_ledger.sql`
- Create: `supabase/tests/40_finance_ledger_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list)
- Create: `lib/data/models/payment_method.dart`
- Create: `lib/data/models/finance.dart`
- Create: `lib/data/repositories/finance_repository.dart`
- Create: `lib/features/finance/providers.dart`
- Create: `test/support/fake_finance_source.dart`
- Test: `test/data/payment_method_test.dart`, `test/data/finance_test.dart`, `test/data/finance_provider_test.dart`

**Interfaces:**
- Consumes: `public.assert_resort_role(uuid, boolean, variadic resort_role[])`, `public.has_resort_role(uuid, boolean, variadic resort_role[])` (0043), `public.current_charges(uuid)` (0045), `public.unit_room_status` (0047), B's `checkout_booking` (0047). `ReportFilter` (`lib/features/reports/providers.dart`), `downloadCsv` (`lib/features/reports/csv_download.dart`), `mapPostgrestError`, `supabaseProvider`.
- Produces (SQL; later tasks replace only function bodies):
  - `create type public.payment_method as enum ('gateway','cash','card','upi','bank_transfer','other')`.
  - `payments.method public.payment_method not null default 'gateway'`, `payments.reference text` (≤ 64), `payments.recorded_by uuid default auth.uid()`, index `payments_property_created_idx (property_id, created_at)`.
  - `food_activity_sales.payment_method public.payment_method not null default 'cash'`, constraint `food_activity_sales_not_gateway`.
  - `public.payment_method_from_text(p_text text) returns public.payment_method` (immutable).
  - `public.checkout_booking(p_reservation_id uuid, p_payment_ref text, p_amount numeric, p_method public.payment_method default 'gateway') returns public.reservations`.
  - `public.report_collections(p_from date, p_to date, p_property_id uuid) returns table (day date, channel text, source text, method public.payment_method, txn_count int, amount numeric)`. `channel` is `online|front_desk`; `source` is `booking_advance|checkout_balance|walk_in_sale|refund`.
  - `public.report_ledger(p_from date, p_to date, p_property_id uuid) returns table (day date, category text, source text, gross numeric, discount numeric, taxable numeric, tax numeric, net numeric)`. `category` is `room|food_beverage|spa_activities|ancillary`; `source` is `booking|cleaning_fee|cancellation_fee|in_stay_order|walk_in|activity_booking`.
  - `public.report_settlements(p_from date, p_to date, p_property_id uuid) returns table (reservation_id uuid, guest_name text, unit_name text, arrival date, departure date, room numeric, cleaning_fee numeric, tax_pct numeric, tax numeric, food numeric, activities numeric, total numeric, advance_paid numeric, balance_online numeric, balance_desk numeric, desk_method public.payment_method, desk_reference text, recorded_by_name text, outstanding numeric)`.
  - `public.finance_summary(p_property_id uuid) returns jsonb`, shaped `{resort: {name, slug, gstin, tax_pct, timezone, today}, online_collected, desk_collected: {total, cash, card, upi, bank_transfer, other}, refunds, net_collected, room_tax, in_house_count, in_house_balance}`.
- Produces (Dart):
  - `enum PaymentMethod { gateway, cash, card, upi, bankTransfer, other }` with `wire`, `label`, `icon`, `static const desk`, `static PaymentMethod fromWire(String?)` (unknown or null → `other`).
  - `enum CollectionChannel { online, frontDesk }`, `enum CollectionSource { bookingAdvance, checkoutBalance, walkInSale, refund }`, `enum LedgerCategory { room, foodBeverage, spaActivities, ancillary }`, each with `wire`, `label` and `fromWire(String)` (unknown → `ArgumentError`).
  - `CollectionRow { day, channel, source, method, txnCount, amount }`, `LedgerRow { day, category, source, gross, discount, taxable, tax, net }`, `SettlementRow { reservationId, guestName, unitName, arrival, departure, room, cleaningFee, taxPct, tax, food, activities, total, advancePaid, balanceOnline, balanceDesk, deskMethod, deskReference, recordedByName, outstanding }`, `FinanceResort { name, slug, gstin, taxPct, timezone, today }`, `FinanceSummary { resort, onlineCollected, deskCollected, deskByMethod, refunds, netCollected, roomTax, inHouseCount, inHouseBalance }`, each with `fromJson`.
  - `abstract class FinanceSource`:
    - `Future<FinanceSummary> summary(String propertyId)`
    - `Future<List<CollectionRow>> collections(DateTime from, DateTime to, String propertyId)`
    - `Future<List<LedgerRow>> ledger(DateTime from, DateTime to, String propertyId)`
    - `Future<List<SettlementRow>> settlements(DateTime from, DateTime to, String propertyId)`
  - Providers: `financeRepositoryProvider` (`Provider<FinanceRepository>`), `financeSourceProvider` (`Provider<FinanceSource>`), `financeSummaryProvider` (`FutureProvider.autoDispose.family<FinanceSummary, String>`), `collectionsProvider` / `ledgerProvider` / `settlementsProvider` (`FutureProvider.autoDispose.family<List<…>, ReportFilter>`), `void invalidateFinance(WidgetRef ref)`, `typedef CsvDownloader = bool Function(String filename, String csv)`, `csvDownloaderProvider` (`Provider<CsvDownloader>`).
  - Test support: `FakeFinanceSource` with the fields `summaryValue`, `collectionRows`, `ledgerRows`, `settlementRows`, `summaryError`, `collectionsError`, `ledgerError`, `settlementsError`, `hold` (a `Completer<void>?` every call waits on), and the call logs `summaryCalls` (`List<String>`), `collectionsCalls`, `ledgerCalls`, `settlementsCalls` (`List<ReportFilter>`). Builders `financeResort({...})`, `financeSummary({...})`, `collectionRow({...})`, `ledgerRow({...})`, `settlementRow({...})`.

- [ ] **Step 1: Check the starting point and record the baselines**

Run: `test -f supabase/migrations/0047_room_status.sql && grep -c "unit_room_status" supabase/migrations/0047_room_status.sql && grep -n "'/staff/rooms'" lib/core/router.dart lib/features/shell/app_shell.dart`
Expected: a non-zero count and a match in both Dart files. If any is missing, stop: Project B has not merged, and this plan builds on it.

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`
Expected: write down the pgTAP failure count and names (the tenancy ledger records 3 pre-existing time-of-day failures around the Asia/Kolkata midnight boundary), the analyzer issue count and the Flutter pass count. Later tasks compare against these numbers.

- [ ] **Step 2: Write the failing pgTAP fixtures and contract test**

Create `supabase/tests/40_finance_ledger_test.sql`:

```sql
-- Finance ledger and collections (REQ-07), added in 0048_finance_ledger.sql.
-- See docs/superpowers/specs/2026-09-25-finance-ledger-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Resort R (Asia/Kolkata, 12% tax, a GSTIN) has an owner (Olga), an admin
-- (Arun), a staff member (Sita) and an accountant (Anil). Resort S has an
-- accountant (Sara). Gita and Ravi are guests.
--
-- "Today" fixtures (C1-C6 checked in now, B8 cancelled now, B9 arriving
-- today, W4 sold today) feed the checkout, summary and settlements tests.
-- "August 2026" fixtures (B1-B7, SX, W1-W3) feed Collections and the
-- Ledger, with every amount worked out in the test that reads it.
begin;
select plan(18);

-- Before any fixture: every payment the seed already holds became gateway.
select is((select count(*)::int from public.payments where method <> 'gateway'), 0,
  'every payment that existed before 0048 is gateway');

insert into auth.users (id, email) values
  ('f0000000-0000-0000-0000-000000000001','fin-r-owner@example.com'),
  ('f0000000-0000-0000-0000-000000000002','fin-r-admin@example.com'),
  ('f0000000-0000-0000-0000-000000000003','fin-r-staff@example.com'),
  ('f0000000-0000-0000-0000-000000000004','fin-r-accountant@example.com'),
  ('f0000000-0000-0000-0000-000000000005','fin-s-accountant@example.com'),
  ('f0000000-0000-0000-0000-000000000006','fin-gita@example.com'),
  ('f0000000-0000-0000-0000-000000000007','fin-ravi@example.com');
update public.profiles set full_name = 'Sita Staff'  where id = 'f0000000-0000-0000-0000-000000000003';
update public.profiles set full_name = 'Anil Accounts' where id = 'f0000000-0000-0000-0000-000000000004';
update public.profiles set full_name = 'Sara Other'  where id = 'f0000000-0000-0000-0000-000000000005';
update public.profiles set full_name = 'Gita Guest'  where id = 'f0000000-0000-0000-0000-000000000006';
update public.profiles set full_name = 'Ravi Guest'  where id = 'f0000000-0000-0000-0000-000000000007';

insert into public.properties (id, name, slug, tax_pct, gstin) values
  ('ffffffff-0000-4000-8000-000000000001','Resort R','fin-r',12,'29ABCDE1234F1Z5'),
  ('ffffffff-0000-4000-8000-000000000002','Resort S','fin-s',0,null);

insert into public.resort_members (property_id, user_id, role) values
  ('ffffffff-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000001','owner'),
  ('ffffffff-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000002','admin'),
  ('ffffffff-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000003','staff'),
  ('ffffffff-0000-4000-8000-000000000001','f0000000-0000-0000-0000-000000000004','accountant'),
  ('ffffffff-0000-4000-8000-000000000002','f0000000-0000-0000-0000-000000000005','accountant');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('ffffffff-0000-4000-8000-000000000011','ffffffff-0000-4000-8000-000000000001','Cottage 1',2,4),
  ('ffffffff-0000-4000-8000-000000000012','ffffffff-0000-4000-8000-000000000001','Cottage 2',2,4),
  ('ffffffff-0000-4000-8000-000000000013','ffffffff-0000-4000-8000-000000000001','Cottage 3',2,4),
  ('ffffffff-0000-4000-8000-000000000014','ffffffff-0000-4000-8000-000000000001','Cottage 4',2,4),
  ('ffffffff-0000-4000-8000-000000000015','ffffffff-0000-4000-8000-000000000001','Cottage 5',2,4),
  ('ffffffff-0000-4000-8000-000000000016','ffffffff-0000-4000-8000-000000000001','Cottage 6',2,4),
  ('ffffffff-0000-4000-8000-000000000017','ffffffff-0000-4000-8000-000000000002','S Villa',2,4);

insert into public.activities (id, property_id, name, price_per_person, capacity_per_slot) values
  ('ffffffff-0000-4000-8000-000000000041','ffffffff-0000-4000-8000-000000000001','Kayak',600,10);

-- Today. C1-C6 are checked in now; their advances were paid two days ago.
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, checked_in_at) values
  ('ffffffff-0000-4000-8000-000000000021','ffffffff-0000-4000-8000-000000000011',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000006',2, '{"total":3000}', now() - interval '1 day'),
  ('ffffffff-0000-4000-8000-000000000022','ffffffff-0000-4000-8000-000000000012',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000007',2, '{"total":1500}', now() - interval '1 day'),
  ('ffffffff-0000-4000-8000-000000000023','ffffffff-0000-4000-8000-000000000017',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000006',2, '{"total":2000}', now() - interval '1 day'),
  ('ffffffff-0000-4000-8000-000000000024','ffffffff-0000-4000-8000-000000000013',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000007',2, '{"total":1000}', now() - interval '1 day'),
  -- Sita (staff at R) staying at her own resort.
  ('ffffffff-0000-4000-8000-000000000025','ffffffff-0000-4000-8000-000000000014',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000003',2, '{"total":800}', now() - interval '1 day'),
  -- Sara (accountant at S) staying at R as a guest.
  ('ffffffff-0000-4000-8000-000000000026','ffffffff-0000-4000-8000-000000000015',
   tstzrange(now() - interval '1 day', now() + interval '1 day', '[)'),
   'booking','checked_in','f0000000-0000-0000-0000-000000000005',2, '{"total":1200}', now() - interval '1 day');

-- B9 arrives at 14:00 today (resort time): 2,000 of room at 12% = 240 tax.
-- B8 was cancelled just now with 600 paid and 600 refunded.
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote, cancelled_at, refund_amount) values
  ('ffffffff-0000-4000-8000-000000000027','ffffffff-0000-4000-8000-000000000016',
   tstzrange(((now() at time zone 'Asia/Kolkata')::date + time '14:00') at time zone 'Asia/Kolkata',
             ((now() at time zone 'Asia/Kolkata')::date + 1 + time '11:00') at time zone 'Asia/Kolkata', '[)'),
   'booking','confirmed','f0000000-0000-0000-0000-000000000007',2,
   '{"subtotal":2000,"cleaning_fee":0,"coupon":null,"tax_pct":12,"tax_amount":240,"total":2240}', null, null),
  ('ffffffff-0000-4000-8000-000000000028','ffffffff-0000-4000-8000-000000000016',
   tstzrange('2026-12-01 14:00+05:30','2026-12-02 11:00+05:30','[)'),
   'booking','cancelled','f0000000-0000-0000-0000-000000000006',2, '{"total":1000}', now(), 600);

insert into public.payments (reservation_id, amount, kind, status, gateway_ref, created_at) values
  ('ffffffff-0000-4000-8000-000000000021',1000,'advance','succeeded','fin-c1-adv', now() - interval '2 days'),
  ('ffffffff-0000-4000-8000-000000000022', 500,'advance','succeeded','fin-c2-adv', now() - interval '2 days'),
  ('ffffffff-0000-4000-8000-000000000023',1000,'advance','succeeded','fin-c3-adv', now() - interval '2 days'),
  ('ffffffff-0000-4000-8000-000000000024',1000,'advance','succeeded','fin-c4-adv', now() - interval '2 days'),
  ('ffffffff-0000-4000-8000-000000000028', 600,'advance','succeeded','fin-b8-adv', now() - interval '2 days');

-- August 2026.
-- B1: two nights of 4,000 + 1,000 extra guest = 10,000 subtotal; cleaning
-- 500; coupon 1,000; tax 12% of 9,500 = 1,140; total 10,640. Paid 5,000
-- online on 1 Aug and 7,540 in cash at the desk on checkout (10,640 +
-- 700 food + 1,200 kayak - 5,000).
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests, quote,
                                 checked_in_at, checked_out_at, cancelled_at, refund_amount) values
  ('ffffffff-0000-4000-8000-000000000031','ffffffff-0000-4000-8000-000000000011',
   tstzrange('2026-08-10 14:00+05:30','2026-08-12 11:00+05:30','[)'),
   'booking','checked_out','f0000000-0000-0000-0000-000000000006',3,
   jsonb_build_object(
     'subtotal',10000,'cleaning_fee',500,
     'coupon',jsonb_build_object('code','AUG10','kind','fixed','value',1000,'discount',1000),
     'tax_pct',12,'tax_amount',1140,'total',10640,
     'lines',jsonb_build_array(
       jsonb_build_object('date','2026-08-10','amount',4000,'extra_guests',1,'extra_guest_amount',1000),
       jsonb_build_object('date','2026-08-11','amount',4000,'extra_guests',1,'extra_guest_amount',1000))),
   '2026-08-10 14:05+05:30','2026-08-12 10:30+05:30', null, null),
  -- B2: the coupon (1,200) is bigger than the subtotal (1,000); 200 spills
  -- onto the cleaning fee, which carries all 36 of tax.
  ('ffffffff-0000-4000-8000-000000000032','ffffffff-0000-4000-8000-000000000012',
   tstzrange('2026-08-13 14:00+05:30','2026-08-14 11:00+05:30','[)'),
   'booking','confirmed','f0000000-0000-0000-0000-000000000007',2,
   jsonb_build_object(
     'subtotal',1000,'cleaning_fee',500,
     'coupon',jsonb_build_object('code','BIG','kind','fixed','value',1200,'discount',1200),
     'tax_pct',12,'tax_amount',36,'total',336),
   null, null, null, null),
  -- B3: a hand-made quote with only a total.
  ('ffffffff-0000-4000-8000-000000000033','ffffffff-0000-4000-8000-000000000013',
   tstzrange('2026-08-14 14:00+05:30','2026-08-15 11:00+05:30','[)'),
   'booking','confirmed','f0000000-0000-0000-0000-000000000007',2, '{"total":2000}',
   null, null, null, null),
  -- B4: paid 2,000, cancelled on 5 Aug with 1,500 refunded; 500 kept.
  ('ffffffff-0000-4000-8000-000000000034','ffffffff-0000-4000-8000-000000000014',
   tstzrange('2026-08-20 14:00+05:30','2026-08-21 11:00+05:30','[)'),
   'booking','cancelled','f0000000-0000-0000-0000-000000000006',2, '{"total":4000}',
   null, null, '2026-08-05 12:00+05:30', 1500),
  -- B5: an unpaid hold cancelled on 6 Aug; its 800 "refund" was never paid.
  ('ffffffff-0000-4000-8000-000000000035','ffffffff-0000-4000-8000-000000000014',
   tstzrange('2026-08-22 14:00+05:30','2026-08-23 11:00+05:30','[)'),
   'booking','cancelled','f0000000-0000-0000-0000-000000000007',2, '{"total":3000}',
   null, null, '2026-08-06 12:00+05:30', 800),
  -- B6: paid 1,000, cancelled on 7 Aug with a 3,000 refund on the books.
  ('ffffffff-0000-4000-8000-000000000036','ffffffff-0000-4000-8000-000000000013',
   tstzrange('2026-08-24 14:00+05:30','2026-08-25 11:00+05:30','[)'),
   'booking','cancelled','f0000000-0000-0000-0000-000000000006',2, '{"total":6000}',
   null, null, '2026-08-07 12:00+05:30', 3000),
  -- B7: 1,000 advance, 2,000 balance paid online at self-checkout.
  ('ffffffff-0000-4000-8000-000000000037','ffffffff-0000-4000-8000-000000000012',
   tstzrange('2026-08-20 14:00+05:30','2026-08-21 11:00+05:30','[)'),
   'booking','checked_out','f0000000-0000-0000-0000-000000000006',2, '{"total":3000}',
   '2026-08-20 14:10+05:30','2026-08-21 10:00+05:30', null, null),
  -- SX: resort S's booking; none of it may show up at R.
  ('ffffffff-0000-4000-8000-000000000038','ffffffff-0000-4000-8000-000000000017',
   tstzrange('2026-08-10 14:00+05:30','2026-08-11 11:00+05:30','[)'),
   'booking','confirmed','f0000000-0000-0000-0000-000000000007',2, '{"total":9999}',
   null, null, null, null);

insert into public.payments (reservation_id, amount, kind, status, gateway, gateway_ref, method, reference, recorded_by, created_at) values
  ('ffffffff-0000-4000-8000-000000000031',5000,'advance','succeeded','mock','fin-b1-adv','gateway',null,null,'2026-08-01 10:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000031',7540,'balance','succeeded','desk','desk-ffffffff-0000-4000-8000-000000000031','cash','R-101',
   'f0000000-0000-0000-0000-000000000003','2026-08-12 10:30+05:30'),
  ('ffffffff-0000-4000-8000-000000000032', 336,'advance','succeeded','mock','fin-b2-adv','gateway',null,null,'2026-08-02 09:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000032', 999,'advance','failed',   'mock','fin-b2-failed','gateway',null,null,'2026-08-02 09:05+05:30'),
  -- B3 is paid in two halves either side of midnight, resort time: 23:30
  -- on 24 Aug, and 00:15 on 25 Aug (still 24 Aug in UTC).
  ('ffffffff-0000-4000-8000-000000000033', 500,'advance','succeeded','mock','fin-b3-late','gateway',null,null,'2026-08-24 23:30+05:30'),
  ('ffffffff-0000-4000-8000-000000000033', 500,'advance','succeeded','mock','fin-b3-early','gateway',null,null,'2026-08-25 00:15+05:30'),
  ('ffffffff-0000-4000-8000-000000000034',2000,'advance','succeeded','mock','fin-b4-adv','gateway',null,null,'2026-08-03 11:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000036',1000,'advance','succeeded','mock','fin-b6-adv','gateway',null,null,'2026-08-04 11:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000037',1000,'advance','succeeded','mock','fin-b7-adv','gateway',null,null,'2026-08-15 11:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000037',2000,'balance','succeeded','mock','fin-b7-bal','gateway',null,null,'2026-08-21 10:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000038',9999,'advance','succeeded','mock','fin-sx-adv','gateway',null,null,'2026-08-01 10:00+05:30');

-- B1's stay: 700 of food and a 1,200 kayak count; the cancelled order
-- and the cancelled kayak do not.
insert into public.food_orders (reservation_id, status, total, created_at) values
  ('ffffffff-0000-4000-8000-000000000031','delivered',700,'2026-08-11 20:00+05:30'),
  ('ffffffff-0000-4000-8000-000000000031','cancelled',300,'2026-08-11 21:00+05:30');
insert into public.activity_bookings (reservation_id, activity_id, booking_date, start_time, people, amount, status) values
  ('ffffffff-0000-4000-8000-000000000031','ffffffff-0000-4000-8000-000000000041','2026-08-11','10:00',2,1200,'booked'),
  ('ffffffff-0000-4000-8000-000000000031','ffffffff-0000-4000-8000-000000000041','2026-08-11','16:00',1,600,'cancelled');

-- Walk-in sales. W3 ("Tea") gives no method, so it takes the default.
insert into public.food_activity_sales (property_id, sale_date, category, item_name, quantity, unit_price, amount, payment_method, recorded_by) values
  ('ffffffff-0000-4000-8000-000000000001','2026-08-10','food','Thali',2,250,500,'cash','f0000000-0000-0000-0000-000000000003'),
  ('ffffffff-0000-4000-8000-000000000001','2026-08-10','activity','Pool pass',1,300,300,'upi','f0000000-0000-0000-0000-000000000003'),
  ('ffffffff-0000-4000-8000-000000000001',(now() at time zone 'Asia/Kolkata')::date,'food','Coffee',1,120,120,'card','f0000000-0000-0000-0000-000000000003'),
  ('ffffffff-0000-4000-8000-000000000002','2026-08-10','food','S snack',1,100,100,'cash','f0000000-0000-0000-0000-000000000005');
insert into public.food_activity_sales (property_id, sale_date, category, item_name, quantity, unit_price, amount, recorded_by) values
  ('ffffffff-0000-4000-8000-000000000001','2026-08-10','food','Tea',1,50,50,'f0000000-0000-0000-0000-000000000003');

-- === Task 1: the contract ===================================================

select enum_has_labels('public', 'payment_method',
  array['gateway','cash','card','upi','bank_transfer','other'],
  'payment_method is gateway, cash, card, upi, bank_transfer, other');
select is((select array_agg(column_name::text order by column_name)
             from information_schema.columns
            where table_schema = 'public' and table_name = 'payments'
              and column_name in ('method','reference','recorded_by')),
  array['method','recorded_by','reference'], 'payments gains method, reference and recorded_by');

-- A probe row on S's booking. It is `failed`, so no report counts it.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into public.payments (reservation_id, amount, kind, status, gateway_ref, created_at)
  values ('ffffffff-0000-4000-8000-000000000023', 1, 'advance', 'failed', 'fin-probe', '2025-01-01 10:00+05:30');
set local request.jwt.claims to '';
select is((select method::text || '|' || (recorded_by = 'f0000000-0000-0000-0000-000000000005')::text
             from public.payments where gateway_ref = 'fin-probe'),
  'gateway|true', 'a payment written without a method is gateway and records who wrote it');
select throws_ok($$insert into public.payments (reservation_id, amount, kind, status, gateway_ref, reference)
  values ('ffffffff-0000-4000-8000-000000000023', 1, 'advance', 'failed', 'fin-probe-2', repeat('x', 65))$$,
  '23514', null, 'a reference longer than 64 characters is refused');
select has_index('public', 'payments', 'payments_property_created_idx',
  'payments are indexed by resort and date for the reports');

select is((select payment_method::text from public.food_activity_sales where item_name = 'Tea'),
  'cash', 'a walk-in sale without a method is cash');
select throws_ok($$insert into public.food_activity_sales (property_id, category, item_name, unit_price, amount, payment_method, recorded_by)
  values ('ffffffff-0000-4000-8000-000000000001', 'food', 'Probe', 10, 10, 'gateway', 'f0000000-0000-0000-0000-000000000003')$$,
  '23514', null, 'a walk-in sale can never be gateway');
select throws_ok($$insert into public.food_activity_sales (property_id, category, item_name, unit_price, amount, payment_method, recorded_by)
  values ('ffffffff-0000-4000-8000-000000000001', 'food', 'Probe', 10, 10, null, 'f0000000-0000-0000-0000-000000000003')$$,
  '23502', null, 'a walk-in sale always has a method');
select is(array[public.payment_method_from_text('Cash'),
                public.payment_method_from_text('  NEFT '),
                public.payment_method_from_text('Bank Transfer'),
                public.payment_method_from_text('bank_transfer'),
                public.payment_method_from_text('IMPS'),
                public.payment_method_from_text('upi'),
                public.payment_method_from_text('CARD'),
                public.payment_method_from_text('xyz'),
                public.payment_method_from_text(null),
                public.payment_method_from_text('gateway')]::text[],
  array['cash','bank_transfer','bank_transfer','bank_transfer','bank_transfer','upi','card','other','other','other'],
  'legacy walk-in text maps onto the method list');

select ok(to_regprocedure('public.checkout_booking(uuid, text, numeric, public.payment_method)') is not null,
  'checkout_booking takes a payment method');
select ok(to_regprocedure('public.checkout_booking(uuid, text, numeric)') is null,
  'the three-argument checkout_booking is gone');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'report_collections'
              and p.parameter_mode = 'OUT'),
  array['day','channel','source','method','txn_count','amount'],
  'report_collections returns the columns CollectionRow.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'report_ledger'
              and p.parameter_mode = 'OUT'),
  array['day','category','source','gross','discount','taxable','tax','net'],
  'report_ledger returns the columns LedgerRow.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'report_settlements'
              and p.parameter_mode = 'OUT'),
  array['reservation_id','guest_name','unit_name','arrival','departure','room','cleaning_fee',
        'tax_pct','tax','food','activities','total','advance_paid','balance_online',
        'balance_desk','desk_method','desk_reference','recorded_by_name','outstanding'],
  'report_settlements returns the columns SettlementRow.fromJson reads');
select is((select data_type::text from information_schema.routines
            where routine_schema = 'public' and routine_name = 'finance_summary'),
  'jsonb', 'finance_summary returns jsonb');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.report_collections(date, date, uuid)',
               'public.report_ledger(date, date, uuid)',
               'public.report_settlements(date, date, uuid)',
               'public.finance_summary(uuid)',
               'public.checkout_booking(uuid, text, numeric, public.payment_method)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the finance functions');
select is((select count(*)::int
             from unnest(array[
               'public.report_collections(date, date, uuid)',
               'public.report_ledger(date, date, uuid)',
               'public.report_settlements(date, date, uuid)',
               'public.finance_summary(uuid)',
               'public.checkout_booking(uuid, text, numeric, public.payment_method)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  5, 'authenticated can execute all five finance functions');

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/40_finance_ledger_test.sql`
Expected: FAIL at the first statement that names `method` (`column "method" does not exist`), because 0048 does not exist yet.

- [ ] **Step 4: Write the migration's schema and report stubs**

Create `supabase/migrations/0048_finance_ledger.sql`:

```sql
-- Finance ledger and collections (REQ-07): how every payment was taken
-- and by whom, and four read-only reports over one resort's money.
-- See docs/superpowers/specs/2026-09-25-finance-ledger-design.md.
--
-- No new tables and no triggers: the reports work every figure out from
-- payments, reservations, food_orders, activity_bookings and
-- food_activity_sales. Error codes raised: P0008, P0002, P0009 (a guest
-- recording a desk method, a wrong amount), P0020 not_a_member, P0022
-- resort_suspended.

create type public.payment_method as enum
  ('gateway', 'cash', 'card', 'upi', 'bank_transfer', 'other');

-- ---------------------------------------------------------------------
-- payments: every payment so far went through the (mock) gateway, so the
-- default is also the right backfill. `reference` is the receipt,
-- card-slip or UTR number typed at the desk; it is not unique, because
-- two resorts (or two bookings) can both issue receipt 001.
-- `recorded_by` defaults to the caller, which for a gateway payment is
-- the guest who paid. auth.uid() is null while this migration runs, so
-- existing rows stay null (unknown).
alter table public.payments
  add column method public.payment_method not null default 'gateway',
  add column reference text
    constraint payments_reference_length check (reference is null or length(reference) <= 64),
  add column recorded_by uuid default auth.uid()
    references public.profiles(id) on delete set null;

create index payments_property_created_idx on public.payments (property_id, created_at);

-- ---------------------------------------------------------------------
-- food_activity_sales.payment_method: free text (no screen ever set it)
-- becomes the enum. Walk-in sales are front-desk money, so never gateway.
create function public.payment_method_from_text(p_text text)
returns public.payment_method
language sql
immutable
set search_path = public, pg_temp
as $$
  select (case lower(btrim(p_text))
    when 'cash'          then 'cash'
    when 'card'          then 'card'
    when 'upi'           then 'upi'
    when 'bank transfer' then 'bank_transfer'
    when 'bank_transfer' then 'bank_transfer'
    when 'neft'          then 'bank_transfer'
    when 'imps'          then 'bank_transfer'
    else 'other'
  end)::public.payment_method;
$$;
revoke execute on function public.payment_method_from_text(text) from public, anon;
grant execute on function public.payment_method_from_text(text) to authenticated;

alter table public.food_activity_sales
  alter column payment_method type public.payment_method
    using public.payment_method_from_text(payment_method);
alter table public.food_activity_sales
  alter column payment_method set default 'cash',
  alter column payment_method set not null,
  add constraint food_activity_sales_not_gateway check (payment_method <> 'gateway');

-- CHECKOUT_BOOKING (Step 5 pastes it here)

-- ---------------------------------------------------------------------
-- Reports. Owner, admin and accountant of p_property_id only; read-only,
-- so a suspended resort can still read them. The signatures are the
-- contract the app is built against; Tasks 3-5 replace the stub bodies.

create function public.report_collections(p_from date, p_to date, p_property_id uuid)
returns table (
  day       date,
  channel   text,
  source    text,
  method    public.payment_method,
  txn_count int,
  amount    numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'report_collections is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.report_ledger(p_from date, p_to date, p_property_id uuid)
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
begin
  raise exception 'report_ledger is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.report_settlements(p_from date, p_to date, p_property_id uuid)
returns table (
  reservation_id   uuid,
  guest_name       text,
  unit_name        text,
  arrival          date,
  departure        date,
  room             numeric,
  cleaning_fee     numeric,
  tax_pct          numeric,
  tax              numeric,
  food             numeric,
  activities       numeric,
  total            numeric,
  advance_paid     numeric,
  balance_online   numeric,
  balance_desk     numeric,
  desk_method      public.payment_method,
  desk_reference   text,
  recorded_by_name text,
  outstanding      numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'report_settlements is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.finance_summary(p_property_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'finance_summary is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.report_collections(date, date, uuid) from public, anon;
revoke execute on function public.report_ledger(date, date, uuid) from public, anon;
revoke execute on function public.report_settlements(date, date, uuid) from public, anon;
revoke execute on function public.finance_summary(uuid) from public, anon;
grant execute on function public.report_collections(date, date, uuid) to authenticated;
grant execute on function public.report_ledger(date, date, uuid) to authenticated;
grant execute on function public.report_settlements(date, date, uuid) to authenticated;
grant execute on function public.finance_summary(uuid) to authenticated;
```

- [ ] **Step 5: Paste `checkout_booking` with its new signature**

First print the definition B merged:

Run: `awk '/create or replace function public.checkout_booking\(/,/^\$\$;/' supabase/migrations/0047_room_status.sql`
Expected: B's `checkout_booking`: the body of `0045_resort_functions.sql` plus a final step that upserts `unit_room_status` to `dirty` unless the unit is `out_of_order`. B's plan (Task 4 Step 4) shows the expected text; the block below is that text.

In `0048_finance_ledger.sql`, replace the line `-- CHECKOUT_BOOKING (Step 5 pastes it here)` with the block below. **If the 0047 body you printed differs from the body below in anything other than whitespace and comments, the printed 0047 body wins:** paste it in place of the body below, keeping only this block's header comment, its four-parameter signature and its grants.

```sql
-- ---------------------------------------------------------------------
-- checkout_booking gains p_method. Postgres cannot add a parameter with
-- CREATE OR REPLACE, so the three-argument function is dropped and the
-- four-argument one created and re-granted, as 0045 did for the report
-- functions. Existing three-argument callers (the app, pgTAP) resolve to
-- it through the default. The body is copied from its latest definition,
-- 0047_room_status.sql (it marks the room dirty); the method handling is
-- added by Task 2 of the finance plan.
drop function if exists public.checkout_booking(uuid, text, numeric);

create function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric,
  p_method         public.payment_method default 'gateway'
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.reservations;
  v_charges jsonb;
  v_balance numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, true, 'owner','admin','staff','accountant');
  end if;

  if v_row.status = 'checked_out' then
    return v_row;   -- idempotent: a retried checkout must not double-charge
  end if;

  if v_row.status <> 'checked_in' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  v_charges := public.current_charges(p_reservation_id);
  v_balance := (v_charges ->> 'balance')::numeric;

  if v_balance > 0 and (p_amount is null or p_amount is distinct from v_balance) then
    raise exception 'payment amount % does not match balance due %',
      p_amount, v_balance
      using errcode = 'P0009';
  end if;

  if v_balance > 0 then
    insert into public.payments
      (reservation_id, amount, kind, status, gateway, gateway_ref)
    values (p_reservation_id, v_balance, 'balance', 'succeeded', 'mock', p_payment_ref);
  end if;

  update public.reservations
     set status = 'checked_out', checked_out_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  -- 0047: the room needs cleaning now.
  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (v_row.unit_id, v_row.property_id, 'dirty', null, v_uid, now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_row;
end;
$$;

revoke execute on function public.checkout_booking(uuid, text, numeric, public.payment_method) from public, anon;
grant execute on function public.checkout_booking(uuid, text, numeric, public.payment_method) to authenticated;
```

- [ ] **Step 6: Add the four reports to the definer allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, replace:

```sql
        'list_dispatchable_staff',
```

with:

```sql
        'list_dispatchable_staff',
        -- 0048: finance reports. Each asserts owner/admin/accountant at the
        -- resort it is given. (checkout_booking is already listed above.)
        'report_collections','report_ledger','report_settlements','finance_summary',
```

If B's merged allow-list does not end its 0047 entries with `'list_dispatchable_staff',`, put the two new lines immediately after the last 0047 entry, before the `-- 0044:` comment. The plan count of 37 does not change.

- [ ] **Step 7: Run the database tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/40_finance_ledger_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/33_stay_checkout_test.sql supabase/tests/35_customer_checkout_test.sql supabase/tests/39_room_status_test.sql`
Expected: PASS. 40 reports 18/18. 37, 33, 35 and 39 pass at their current counts (checkout still behaves exactly as in 0047).

- [ ] **Step 8: Write the failing Dart model and provider tests**

Create `test/data/payment_method_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/payment_method.dart';

void main() {
  test('wire values match the Postgres enum, in order', () {
    expect(PaymentMethod.values.map((m) => m.wire).toList(),
        ['gateway', 'cash', 'card', 'upi', 'bank_transfer', 'other']);
  });

  test('fromWire round-trips every value', () {
    for (final m in PaymentMethod.values) {
      expect(PaymentMethod.fromWire(m.wire), m);
    }
  });

  test('unknown or missing text is Other', () {
    expect(PaymentMethod.fromWire('cheque'), PaymentMethod.other);
    expect(PaymentMethod.fromWire(null), PaymentMethod.other);
  });

  test('desk is every method but gateway, Cash first', () {
    expect(PaymentMethod.desk, [
      PaymentMethod.cash,
      PaymentMethod.card,
      PaymentMethod.upi,
      PaymentMethod.bankTransfer,
      PaymentMethod.other,
    ]);
  });

  test('every method has its own label and icon', () {
    expect(PaymentMethod.values.map((m) => m.label).toList(),
        ['Online', 'Cash', 'Card', 'UPI', 'Bank transfer', 'Other']);
    expect(PaymentMethod.values.map((m) => m.icon).toSet(), hasLength(6));
  });
}
```

Create `test/data/finance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';

void main() {
  test('CollectionRow.fromJson parses a report_collections row', () {
    final row = CollectionRow.fromJson(const {
      'day': '2026-08-10',
      'channel': 'front_desk',
      'source': 'walk_in_sale',
      'method': 'upi',
      'txn_count': 2,
      'amount': 550.5,
    });

    expect(row.day, DateTime(2026, 8, 10));
    expect(row.channel, CollectionChannel.frontDesk);
    expect(row.source, CollectionSource.walkInSale);
    expect(row.method, PaymentMethod.upi);
    expect(row.txnCount, 2);
    expect(row.amount, 550.5);
  });

  test('a refund line keeps its negative amount', () {
    final row = CollectionRow.fromJson(const {
      'day': '2026-08-05',
      'channel': 'online',
      'source': 'refund',
      'method': 'gateway',
      'txn_count': 1,
      'amount': -1500,
    });

    expect(row.source, CollectionSource.refund);
    expect(row.amount, -1500);
  });

  test('an unknown channel, source or category is rejected, not defaulted', () {
    expect(() => CollectionChannel.fromWire('pigeon'), throwsArgumentError);
    expect(() => CollectionSource.fromWire('lottery'), throwsArgumentError);
    expect(() => LedgerCategory.fromWire('casino'), throwsArgumentError);
  });

  test('LedgerRow.fromJson parses a report_ledger row', () {
    final row = LedgerRow.fromJson(const {
      'day': '2026-08-10',
      'category': 'room',
      'source': 'booking',
      'gross': 10000,
      'discount': 1000,
      'taxable': 9000,
      'tax': 1080,
      'net': 10080,
    });

    expect(row.day, DateTime(2026, 8, 10));
    expect(row.category, LedgerCategory.room);
    expect(row.source, 'booking');
    expect([row.gross, row.discount, row.taxable, row.tax, row.net],
        [10000, 1000, 9000, 1080, 10080]);
  });

  test('ledger categories have their own labels', () {
    expect(LedgerCategory.values.map((c) => c.label).toList(),
        ['Room', 'F&B', 'Spa/Activities', 'Ancillary']);
  });

  test('SettlementRow.fromJson parses a desk settlement', () {
    final row = SettlementRow.fromJson(const {
      'reservation_id': 'r1',
      'guest_name': 'Gita Guest',
      'unit_name': 'Cottage 1',
      'arrival': '2026-08-10',
      'departure': '2026-08-12',
      'room': 9000,
      'cleaning_fee': 500,
      'tax_pct': 12,
      'tax': 1140,
      'food': 700,
      'activities': 1200,
      'total': 12540,
      'advance_paid': 5000,
      'balance_online': 0,
      'balance_desk': 7540,
      'desk_method': 'cash',
      'desk_reference': 'R-101',
      'recorded_by_name': 'Sita Staff',
      'outstanding': 0,
    });

    expect(row.reservationId, 'r1');
    expect(row.guestName, 'Gita Guest');
    expect(row.unitName, 'Cottage 1');
    expect(row.arrival, DateTime(2026, 8, 10));
    expect(row.departure, DateTime(2026, 8, 12));
    expect(row.total, 12540);
    expect(row.balanceDesk, 7540);
    expect(row.deskMethod, PaymentMethod.cash);
    expect(row.deskReference, 'R-101');
    expect(row.recordedByName, 'Sita Staff');
    expect(row.outstanding, 0);
  });

  test('an online settlement has no desk method', () {
    final row = SettlementRow.fromJson(const {
      'reservation_id': 'r2',
      'guest_name': 'Ravi Guest',
      'unit_name': 'Cottage 2',
      'arrival': '2026-08-20',
      'departure': '2026-08-21',
      'room': 3000,
      'cleaning_fee': 0,
      'tax_pct': 0,
      'tax': 0,
      'food': 0,
      'activities': 0,
      'total': 3000,
      'advance_paid': 1000,
      'balance_online': 2000,
      'balance_desk': 0,
      'desk_method': null,
      'desk_reference': null,
      'recorded_by_name': null,
      'outstanding': 0,
    });

    expect(row.deskMethod, isNull);
    expect(row.deskReference, isNull);
    expect(row.recordedByName, isNull);
    expect(row.balanceOnline, 2000);
  });

  test('FinanceSummary.fromJson parses finance_summary', () {
    final s = FinanceSummary.fromJson(const {
      'resort': {
        'name': 'Resort R',
        'slug': 'fin-r',
        'gstin': '29ABCDE1234F1Z5',
        'tax_pct': 12,
        'timezone': 'Asia/Kolkata',
        'today': '2026-09-25',
      },
      'online_collected': 1000,
      'desk_collected': {
        'total': 2920,
        'cash': 2800,
        'card': 120,
        'upi': 0,
        'bank_transfer': 0,
        'other': 0,
      },
      'refunds': 600,
      'net_collected': 3320,
      'room_tax': 240,
      'in_house_count': 1,
      'in_house_balance': 1200,
    });

    expect(s.resort.name, 'Resort R');
    expect(s.resort.slug, 'fin-r');
    expect(s.resort.gstin, '29ABCDE1234F1Z5');
    expect(s.resort.taxPct, 12);
    expect(s.resort.timezone, 'Asia/Kolkata');
    expect(s.resort.today, DateTime(2026, 9, 25));
    expect(s.onlineCollected, 1000);
    expect(s.deskCollected, 2920);
    expect(s.deskByMethod[PaymentMethod.cash], 2800);
    expect(s.deskByMethod[PaymentMethod.card], 120);
    expect(s.deskByMethod.keys, PaymentMethod.desk);
    expect(s.refunds, 600);
    expect(s.netCollected, 3320);
    expect(s.roomTax, 240);
    expect(s.inHouseCount, 1);
    expect(s.inHouseBalance, 1200);
  });

  test('a resort with no GSTIN and missing figures parse as null and zero', () {
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

    expect(s.resort.gstin, isNull);
    expect(s.onlineCollected, 0);
    expect(s.deskCollected, 0);
    expect(s.deskByMethod.values, everyElement(0));
    expect(s.inHouseCount, 0);
  });
}
```

Create `test/data/finance_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/providers.dart';

import '../support/fake_finance_source.dart';

void main() {
  test('every finance provider reads the resort it is keyed by', () async {
    final source = FakeFinanceSource();
    final container = ProviderContainer(
        overrides: [financeSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);
    final filter =
        (from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31), propertyId: 'p1');
    final subs = <ProviderSubscription<Object?>>[
      container.listen(financeSummaryProvider('p1'), (_, _) {}),
      container.listen(collectionsProvider(filter), (_, _) {}),
      container.listen(ledgerProvider(filter), (_, _) {}),
      container.listen(settlementsProvider(filter), (_, _) {}),
    ];
    addTearDown(() {
      for (final s in subs) {
        s.close();
      }
    });

    await container.read(financeSummaryProvider('p1').future);
    await container.read(collectionsProvider(filter).future);
    await container.read(ledgerProvider(filter).future);
    await container.read(settlementsProvider(filter).future);

    expect(source.summaryCalls, ['p1']);
    expect(source.collectionsCalls, [filter]);
    expect(source.ledgerCalls, [filter]);
    expect(source.settlementsCalls, [filter]);
  });

  test('switching resort asks for the other resort, not a cached one',
      () async {
    final source = FakeFinanceSource();
    final container = ProviderContainer(
        overrides: [financeSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);
    final a = container.listen(financeSummaryProvider('p1'), (_, _) {});
    final b = container.listen(financeSummaryProvider('p2'), (_, _) {});
    addTearDown(a.close);
    addTearDown(b.close);

    await container.read(financeSummaryProvider('p1').future);
    await container.read(financeSummaryProvider('p2').future);

    expect(source.summaryCalls, ['p1', 'p2']);
  });
}
```

- [ ] **Step 9: Run them to verify they fail**

Run: `flutter test test/data/payment_method_test.dart test/data/finance_test.dart test/data/finance_provider_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/data/models/payment_method.dart'".

- [ ] **Step 10: Write the models**

Create `lib/data/models/payment_method.dart`:

```dart
import 'package:flutter/material.dart';

/// How money reached the resort -- `public.payment_method`
/// (0048_finance_ledger.sql). [gateway] is every payment taken online (and
/// the default of every payment written before 0048); the other five are
/// desk methods, recorded by resort staff at checkout or on a walk-in sale.
enum PaymentMethod {
  gateway('gateway', 'Online', Icons.language),
  cash('cash', 'Cash', Icons.payments_outlined),
  card('card', 'Card', Icons.credit_card),
  upi('upi', 'UPI', Icons.qr_code_2),
  bankTransfer('bank_transfer', 'Bank transfer', Icons.account_balance_outlined),
  other('other', 'Other', Icons.more_horiz);

  const PaymentMethod(this.wire, this.label, this.icon);

  /// The Postgres enum label.
  final String wire;
  final String label;
  final IconData icon;

  /// Every method a person records at the desk, in chip order: all but
  /// [gateway].
  static const desk = [cash, card, upi, bankTransfer, other];

  /// Unknown or missing text parses as [other]: a money row must still show
  /// up in a report even if a later migration adds a method this build does
  /// not know yet.
  static PaymentMethod fromWire(String? raw) {
    for (final m in values) {
      if (m.wire == raw) return m;
    }
    return other;
  }
}
```

Create `lib/data/models/finance.dart`:

```dart
import 'payment_method.dart';

DateTime _day(Object? raw) => DateTime.parse(raw as String);
num _money(Object? raw) => (raw as num?) ?? 0;

/// `report_collections.channel`. [online] is money that came through the
/// payment gateway (refunds go back the same way); [frontDesk] is money
/// taken at the desk, including walk-in sales.
enum CollectionChannel {
  online('online', 'Online'),
  frontDesk('front_desk', 'Front desk');

  const CollectionChannel(this.wire, this.label);
  final String wire;
  final String label;

  /// Unknown text is rejected, not defaulted: a silent fallback would hide a
  /// server/app mismatch in money figures.
  static CollectionChannel fromWire(String raw) => values.firstWhere(
        (c) => c.wire == raw,
        orElse: () => throw ArgumentError('Unknown collection channel: $raw'),
      );
}

/// `report_collections.source`: what the money was for.
enum CollectionSource {
  bookingAdvance('booking_advance', 'Booking advance'),
  checkoutBalance('checkout_balance', 'Checkout balance'),
  walkInSale('walk_in_sale', 'Walk-in sale'),
  refund('refund', 'Refund');

  const CollectionSource(this.wire, this.label);
  final String wire;
  final String label;

  static CollectionSource fromWire(String raw) => values.firstWhere(
        (s) => s.wire == raw,
        orElse: () => throw ArgumentError('Unknown collection source: $raw'),
      );
}

/// `report_ledger.category`: the revenue ledger a line belongs to.
enum LedgerCategory {
  room('room', 'Room'),
  foodBeverage('food_beverage', 'F&B'),
  spaActivities('spa_activities', 'Spa/Activities'),
  ancillary('ancillary', 'Ancillary');

  const LedgerCategory(this.wire, this.label);
  final String wire;
  final String label;

  static LedgerCategory fromWire(String raw) => values.firstWhere(
        (c) => c.wire == raw,
        orElse: () => throw ArgumentError('Unknown ledger category: $raw'),
      );
}

/// One row of `report_collections`: the money of one day, channel, source
/// and method (cash basis).
class CollectionRow {
  const CollectionRow({
    required this.day,
    required this.channel,
    required this.source,
    required this.method,
    required this.txnCount,
    required this.amount,
  });

  factory CollectionRow.fromJson(Map<String, dynamic> json) => CollectionRow(
        day: _day(json['day']),
        channel: CollectionChannel.fromWire(json['channel'] as String),
        source: CollectionSource.fromWire(json['source'] as String),
        method: PaymentMethod.fromWire(json['method'] as String?),
        txnCount: (json['txn_count'] as num?)?.toInt() ?? 0,
        amount: _money(json['amount']),
      );

  final DateTime day;
  final CollectionChannel channel;
  final CollectionSource source;
  final PaymentMethod method;
  final int txnCount;

  /// Negative for a refund.
  final num amount;
}

/// One row of `report_ledger`: revenue earned on one day, in one category,
/// from one source (accrual basis). `taxable = gross - discount` and
/// `net = taxable + tax`, both worked out server-side.
class LedgerRow {
  const LedgerRow({
    required this.day,
    required this.category,
    required this.source,
    required this.gross,
    required this.discount,
    required this.taxable,
    required this.tax,
    required this.net,
  });

  factory LedgerRow.fromJson(Map<String, dynamic> json) => LedgerRow(
        day: _day(json['day']),
        category: LedgerCategory.fromWire(json['category'] as String),
        source: json['source'] as String,
        gross: _money(json['gross']),
        discount: _money(json['discount']),
        taxable: _money(json['taxable']),
        tax: _money(json['tax']),
        net: _money(json['net']),
      );

  final DateTime day;
  final LedgerCategory category;

  /// `booking`, `cleaning_fee`, `cancellation_fee`, `in_stay_order`,
  /// `walk_in` or `activity_booking`. Shown only in the CSV.
  final String source;
  final num gross;
  final num discount;
  final num taxable;
  final num tax;
  final num net;
}

/// One row of `report_settlements`: a booking checked out in the range.
/// `room + cleaningFee + tax + food + activities == total`, and
/// `outstanding` is `total` minus every succeeded payment (0 after a normal
/// checkout).
class SettlementRow {
  const SettlementRow({
    required this.reservationId,
    required this.guestName,
    required this.unitName,
    required this.arrival,
    required this.departure,
    required this.room,
    required this.cleaningFee,
    required this.taxPct,
    required this.tax,
    required this.food,
    required this.activities,
    required this.total,
    required this.advancePaid,
    required this.balanceOnline,
    required this.balanceDesk,
    this.deskMethod,
    this.deskReference,
    this.recordedByName,
    required this.outstanding,
  });

  factory SettlementRow.fromJson(Map<String, dynamic> json) => SettlementRow(
        reservationId: json['reservation_id'] as String,
        guestName: json['guest_name'] as String,
        unitName: json['unit_name'] as String,
        arrival: _day(json['arrival']),
        departure: _day(json['departure']),
        room: _money(json['room']),
        cleaningFee: _money(json['cleaning_fee']),
        taxPct: _money(json['tax_pct']),
        tax: _money(json['tax']),
        food: _money(json['food']),
        activities: _money(json['activities']),
        total: _money(json['total']),
        advancePaid: _money(json['advance_paid']),
        balanceOnline: _money(json['balance_online']),
        balanceDesk: _money(json['balance_desk']),
        deskMethod: json['desk_method'] == null
            ? null
            : PaymentMethod.fromWire(json['desk_method'] as String),
        deskReference: json['desk_reference'] as String?,
        recordedByName: json['recorded_by_name'] as String?,
        outstanding: _money(json['outstanding']),
      );

  final String reservationId;
  final String guestName;
  final String unitName;
  final DateTime arrival;
  final DateTime departure;
  final num room;
  final num cleaningFee;
  final num taxPct;
  final num tax;
  final num food;
  final num activities;
  final num total;
  final num advancePaid;
  final num balanceOnline;
  final num balanceDesk;

  /// Null when the balance was paid online, or nothing was due.
  final PaymentMethod? deskMethod;
  final String? deskReference;

  /// Who recorded the balance payment.
  final String? recordedByName;
  final num outstanding;
}

/// The `resort` block of `finance_summary`: the export header and "today"
/// in the resort's own timezone.
class FinanceResort {
  const FinanceResort({
    required this.name,
    required this.slug,
    this.gstin,
    required this.taxPct,
    required this.timezone,
    required this.today,
  });

  factory FinanceResort.fromJson(Map<String, dynamic> json) => FinanceResort(
        name: json['name'] as String,
        slug: json['slug'] as String,
        gstin: json['gstin'] as String?,
        taxPct: _money(json['tax_pct']),
        timezone: json['timezone'] as String,
        today: _day(json['today']),
      );

  final String name;
  final String slug;
  final String? gstin;

  /// The resort's current rate; each booking's own rate is in its quote.
  final num taxPct;
  final String timezone;
  final DateTime today;
}

/// `finance_summary(p_property_id)`: today's money at one resort. Every
/// figure is worked out server-side; this class only parses. [refunds] is a
/// positive amount, and `netCollected = onlineCollected + deskCollected -
/// refunds`.
class FinanceSummary {
  const FinanceSummary({
    required this.resort,
    required this.onlineCollected,
    required this.deskCollected,
    required this.deskByMethod,
    required this.refunds,
    required this.netCollected,
    required this.roomTax,
    required this.inHouseCount,
    required this.inHouseBalance,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    final desk =
        (json['desk_collected'] as Map<String, dynamic>?) ?? const {};
    return FinanceSummary(
      resort: FinanceResort.fromJson(json['resort'] as Map<String, dynamic>),
      onlineCollected: _money(json['online_collected']),
      deskCollected: _money(desk['total']),
      deskByMethod: {
        for (final m in PaymentMethod.desk) m: _money(desk[m.wire]),
      },
      refunds: _money(json['refunds']),
      netCollected: _money(json['net_collected']),
      roomTax: _money(json['room_tax']),
      inHouseCount: (json['in_house_count'] as num?)?.toInt() ?? 0,
      inHouseBalance: _money(json['in_house_balance']),
    );
  }

  final FinanceResort resort;
  final num onlineCollected;

  /// Checkout balances taken at the desk plus walk-in sales.
  final num deskCollected;

  /// One entry per [PaymentMethod.desk] value, zero when none.
  final Map<PaymentMethod, num> deskByMethod;
  final num refunds;
  final num netCollected;

  /// Today's tax on bookings (room and cleaning-fee lines together).
  final num roomTax;
  final int inHouseCount;

  /// What the checked-in guests still owe, worked out as `current_charges`.
  final num inHouseBalance;
}
```

- [ ] **Step 11: Write the repository, seam and providers**

Create `lib/data/repositories/finance_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/finance.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The slice of [FinanceRepository] the Finance screen and the owner export
/// centre need. Tests override [financeSourceProvider] with
/// `FakeFinanceSource` (test/support/fake_finance_source.dart) instead of a
/// real client.
abstract class FinanceSource {
  Future<FinanceSummary> summary(String propertyId);
  Future<List<CollectionRow>> collections(
      DateTime from, DateTime to, String propertyId);
  Future<List<LedgerRow>> ledger(DateTime from, DateTime to, String propertyId);
  Future<List<SettlementRow>> settlements(
      DateTime from, DateTime to, String propertyId);
}

/// Backs the Finance screen through the four report functions in
/// 0048_finance_ledger.sql. Each asserts owner/admin/accountant at
/// `p_property_id` server-side, so this repository checks nothing itself;
/// refusals arrive as P0020 through [mapPostgrestError].
class FinanceRepository implements FinanceSource {
  FinanceRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Map<String, dynamic> _range(DateTime from, DateTime to, String propertyId) =>
      {'p_from': _d(from), 'p_to': _d(to), 'p_property_id': propertyId};

  @override
  Future<FinanceSummary> summary(String propertyId) => _guard(() async {
        final json = await _db.rpc('finance_summary', params: {
          'p_property_id': propertyId,
        });
        return FinanceSummary.fromJson(json as Map<String, dynamic>);
      });

  @override
  Future<List<CollectionRow>> collections(
          DateTime from, DateTime to, String propertyId) =>
      _guard(() async {
        final rows = await _db.rpc('report_collections',
            params: _range(from, to, propertyId)) as List<dynamic>;
        return rows
            .map((e) => CollectionRow.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<List<LedgerRow>> ledger(
          DateTime from, DateTime to, String propertyId) =>
      _guard(() async {
        final rows = await _db.rpc('report_ledger',
            params: _range(from, to, propertyId)) as List<dynamic>;
        return rows
            .map((e) => LedgerRow.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<List<SettlementRow>> settlements(
          DateTime from, DateTime to, String propertyId) =>
      _guard(() async {
        final rows = await _db.rpc('report_settlements',
            params: _range(from, to, propertyId)) as List<dynamic>;
        return rows
            .map((e) => SettlementRow.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(supabaseProvider)),
);

/// The [FinanceSource] seam every screen calls through.
final financeSourceProvider = Provider<FinanceSource>(
  (ref) => ref.watch(financeRepositoryProvider),
);
```

Create `lib/features/finance/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/finance.dart';
import '../../data/repositories/finance_repository.dart';
import '../reports/csv_download.dart';
import '../reports/providers.dart' show ReportFilter;

/// Today's figures and the export header of one resort, keyed by property
/// id so switching resort never shows another resort's money. Every finance
/// provider is `autoDispose`: opening the screen or a tab always queries
/// afresh.
final financeSummaryProvider =
    FutureProvider.autoDispose.family<FinanceSummary, String>(
  (ref, propertyId) => ref.watch(financeSourceProvider).summary(propertyId),
);

final collectionsProvider =
    FutureProvider.autoDispose.family<List<CollectionRow>, ReportFilter>(
  (ref, f) =>
      ref.watch(financeSourceProvider).collections(f.from, f.to, f.propertyId),
);

final ledgerProvider =
    FutureProvider.autoDispose.family<List<LedgerRow>, ReportFilter>(
  (ref, f) =>
      ref.watch(financeSourceProvider).ledger(f.from, f.to, f.propertyId),
);

final settlementsProvider =
    FutureProvider.autoDispose.family<List<SettlementRow>, ReportFilter>(
  (ref, f) =>
      ref.watch(financeSourceProvider).settlements(f.from, f.to, f.propertyId),
);

/// Call after anything that moves money (a checkout, a walk-in sale), so an
/// open Finance screen refetches every resort's figures.
void invalidateFinance(WidgetRef ref) {
  ref
    ..invalidate(financeSummaryProvider)
    ..invalidate(collectionsProvider)
    ..invalidate(ledgerProvider)
    ..invalidate(settlementsProvider);
}

/// Hands a CSV to the user; false where the platform cannot (see
/// `csv_download.dart`). A provider so widget tests can capture the file.
typedef CsvDownloader = bool Function(String filename, String csv);

final csvDownloaderProvider = Provider<CsvDownloader>((ref) => downloadCsv);
```

- [ ] **Step 12: Write the test fake**

Create `test/support/fake_finance_source.dart`:

```dart
import 'dart:async';

import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/reports/providers.dart' show ReportFilter;

/// In-memory [FinanceSource]. Set the `...Value`/`...Rows` fields for what
/// the server would return, an `...Error` to make that call throw, [hold]
/// to keep every call loading, and read the call logs to assert what a
/// screen asked for.
class FakeFinanceSource implements FinanceSource {
  FinanceSummary summaryValue = financeSummary();
  List<CollectionRow> collectionRows = [];
  List<LedgerRow> ledgerRows = [];
  List<SettlementRow> settlementRows = [];
  Object? summaryError;
  Object? collectionsError;
  Object? ledgerError;
  Object? settlementsError;

  /// When set, every call waits for it to complete.
  Completer<void>? hold;

  final List<String> summaryCalls = [];
  final List<ReportFilter> collectionsCalls = [];
  final List<ReportFilter> ledgerCalls = [];
  final List<ReportFilter> settlementsCalls = [];

  Future<void> _wait() async {
    if (hold != null) await hold!.future;
  }

  @override
  Future<FinanceSummary> summary(String propertyId) async {
    summaryCalls.add(propertyId);
    await _wait();
    if (summaryError != null) throw summaryError!;
    return summaryValue;
  }

  @override
  Future<List<CollectionRow>> collections(
      DateTime from, DateTime to, String propertyId) async {
    collectionsCalls.add((from: from, to: to, propertyId: propertyId));
    await _wait();
    if (collectionsError != null) throw collectionsError!;
    return collectionRows;
  }

  @override
  Future<List<LedgerRow>> ledger(
      DateTime from, DateTime to, String propertyId) async {
    ledgerCalls.add((from: from, to: to, propertyId: propertyId));
    await _wait();
    if (ledgerError != null) throw ledgerError!;
    return ledgerRows;
  }

  @override
  Future<List<SettlementRow>> settlements(
      DateTime from, DateTime to, String propertyId) async {
    settlementsCalls.add((from: from, to: to, propertyId: propertyId));
    await _wait();
    if (settlementsError != null) throw settlementsError!;
    return settlementRows;
  }
}

/// Resort R of the pgTAP file: slug `fin-r`, 12% tax, a GSTIN, today
/// 25 Sep 2026.
FinanceResort financeResort({
  String name = 'Resort R',
  String slug = 'fin-r',
  String? gstin = '29ABCDE1234F1Z5',
  num taxPct = 12,
  String timezone = 'Asia/Kolkata',
  DateTime? today,
}) =>
    FinanceResort(
      name: name,
      slug: slug,
      gstin: gstin,
      taxPct: taxPct,
      timezone: timezone,
      today: today ?? DateTime(2026, 9, 25),
    );

/// A summary whose desk total and net are worked out from its parts.
FinanceSummary financeSummary({
  FinanceResort? resort,
  num online = 0,
  Map<PaymentMethod, num> desk = const {},
  num refunds = 0,
  num roomTax = 0,
  int inHouseCount = 0,
  num inHouseBalance = 0,
}) {
  final deskTotal = desk.values.fold<num>(0, (a, b) => a + b);
  return FinanceSummary(
    resort: resort ?? financeResort(),
    onlineCollected: online,
    deskCollected: deskTotal,
    deskByMethod: {for (final m in PaymentMethod.desk) m: desk[m] ?? 0},
    refunds: refunds,
    netCollected: online + deskTotal - refunds,
    roomTax: roomTax,
    inHouseCount: inHouseCount,
    inHouseBalance: inHouseBalance,
  );
}

/// Defaults to one online booking advance; override what a test is about.
CollectionRow collectionRow({
  DateTime? day,
  CollectionChannel channel = CollectionChannel.online,
  CollectionSource source = CollectionSource.bookingAdvance,
  PaymentMethod method = PaymentMethod.gateway,
  int txnCount = 1,
  num amount = 0,
}) =>
    CollectionRow(
      day: day ?? DateTime(2026, 8, 1),
      channel: channel,
      source: source,
      method: method,
      txnCount: txnCount,
      amount: amount,
    );

/// A ledger line whose taxable and net amounts follow from its parts.
LedgerRow ledgerRow({
  DateTime? day,
  LedgerCategory category = LedgerCategory.room,
  String source = 'booking',
  num gross = 0,
  num discount = 0,
  num tax = 0,
}) =>
    LedgerRow(
      day: day ?? DateTime(2026, 8, 10),
      category: category,
      source: source,
      gross: gross,
      discount: discount,
      taxable: gross - discount,
      tax: tax,
      net: gross - discount + tax,
    );

/// A settlement whose total defaults to the sum of its parts.
SettlementRow settlementRow({
  String reservationId = 'r1',
  String guestName = 'Gita Guest',
  String unitName = 'Cottage 1',
  DateTime? arrival,
  DateTime? departure,
  num room = 0,
  num cleaningFee = 0,
  num taxPct = 0,
  num tax = 0,
  num food = 0,
  num activities = 0,
  num? total,
  num advancePaid = 0,
  num balanceOnline = 0,
  num balanceDesk = 0,
  PaymentMethod? deskMethod,
  String? deskReference,
  String? recordedByName,
  num outstanding = 0,
}) =>
    SettlementRow(
      reservationId: reservationId,
      guestName: guestName,
      unitName: unitName,
      arrival: arrival ?? DateTime(2026, 8, 10),
      departure: departure ?? DateTime(2026, 8, 12),
      room: room,
      cleaningFee: cleaningFee,
      taxPct: taxPct,
      tax: tax,
      food: food,
      activities: activities,
      total: total ?? room + cleaningFee + tax + food + activities,
      advancePaid: advancePaid,
      balanceOnline: balanceOnline,
      balanceDesk: balanceDesk,
      deskMethod: deskMethod,
      deskReference: deskReference,
      recordedByName: recordedByName,
      outstanding: outstanding,
    );
```

- [ ] **Step 13: Run the Dart tests to verify they pass**

Run: `flutter test test/data/payment_method_test.dart test/data/finance_test.dart test/data/finance_provider_test.dart && flutter analyze`
Expected: all tests PASS. The analyzer shows no issues beyond the Step 1 baseline.

- [ ] **Step 14: Commit**

```bash
git add supabase/migrations/0048_finance_ledger.sql supabase/tests/40_finance_ledger_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql lib/data/models/payment_method.dart \
  lib/data/models/finance.dart lib/data/repositories/finance_repository.dart \
  lib/features/finance/providers.dart test/support/fake_finance_source.dart \
  test/data/payment_method_test.dart test/data/finance_test.dart test/data/finance_provider_test.dart
git commit -m "feat(finance): fix the finance contract (schema, function signatures, Dart API)"
```

---

## Phase 1: Database track (Tasks 2 → 3 → 4 → 5, sequential)

### Task 2: `checkout_booking` records the payment method

**Track:** DB. **Depends on:** Task 1.

**Files:**
- Modify: `supabase/migrations/0048_finance_ledger.sql` (replace the `checkout_booking` body)
- Test: `supabase/tests/40_finance_ledger_test.sql` (append a section)

**Interfaces:**
- Consumes: the Task 1 signature and fixtures, `public.has_resort_role(uuid, boolean, variadic resort_role[])`.
- Produces: `checkout_booking(…, p_method)` behaving as the spec says:
  - `coalesce(p_method, 'gateway')`.
  - A method other than `gateway` needs `has_resort_role(<booking's resort>, true, 'owner','admin','staff','accountant')`, else P0009 `desk payment methods are recorded by resort staff`. The check runs before the idempotent early return.
  - Desk row: `gateway = 'desk'`, `gateway_ref = 'desk-' || p_reservation_id`, `method = p_method`, `reference = nullif(btrim(p_payment_ref), '')`, `recorded_by = auth.uid()`.
  - Gateway row: `gateway = 'mock'`, `gateway_ref = p_payment_ref`, `method = 'gateway'`, `recorded_by = auth.uid()`.
  - Unchanged: retry on `checked_out` returns the row, amount must equal the balance (P0009), a zero balance writes no payment, the room is marked dirty (0047).
- State left for Task 3:
  - C1 (Cottage 1) is checked out with a 2,000 desk cash payment, reference `R-555`, by Sita.
  - C2 is checked out with a 1,000 online balance (`fin-c2-bal`) by Ravi.
  - C3 (resort S) is checked out with a 1,000 card payment, reference `R-555`, by Sara.
  - C4 is checked out with no balance payment.
  - C5 is checked out with an 800 desk cash payment and no reference, by Sita.
  - C6 is still checked in, owing 1,200.
  - The file ends with `reset role` and empty claims.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/40_finance_ledger_test.sql`, change `select plan(18);` to `select plan(34);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 2: checkout_booking records the payment method =================

set local role authenticated;
-- A guest cannot record a desk method, even for the exact balance.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select throws_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000022', 'x', 1000, 'cash')$$,
  'P0009', 'desk payment methods are recorded by resort staff',
  'a guest passing a desk method is refused');
-- Review Focus 1: Sara is an accountant, but at resort S, not here.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000026', null, 1200, 'cash')$$,
  'P0009', 'desk payment methods are recorded by resort staff',
  'a member of another resort cannot record a desk method here');

-- Reception takes cash with a receipt number (typed with stray spaces).
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000021', ' R-555 ', 2000, 'cash')$$,
  'staff record a cash balance with a receipt number');
select is((select gateway || '|' || gateway_ref || '|' || method::text || '|' || reference || '|'
                  || amount::text || '|' || (recorded_by = 'f0000000-0000-0000-0000-000000000003')::text
             from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000021' and kind = 'balance'),
  'desk|desk-ffffffff-0000-4000-8000-000000000021|cash|R-555|2000.00|true',
  'the desk row: gateway desk, one ref per booking, the method, the trimmed reference, who recorded it');

-- Review Focus 2: a retry, even with another method, changes nothing.
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000021', 'R-999', 2000, 'card')$$,
  'a retried checkout returns the booking');
select is((select count(*)::text || '|' || min(method::text) || '|' || min(reference)
             from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000021' and kind = 'balance'),
  '1|cash|R-555', 'the retry writes no second payment and changes nothing');
select is((select state::text from public.unit_room_status
            where unit_id = 'ffffffff-0000-4000-8000-000000000011'),
  'dirty', 'checkout still marks the room for cleaning (0047)');

-- Guest self-checkout is unchanged, and still takes three arguments.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000007","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000022', 'fin-c2-bal', 1000)$$,
  'a guest''s own checkout still works with three arguments');
select is((select gateway || '|' || gateway_ref || '|' || method::text || '|' || coalesce(reference, '-') || '|'
                  || amount::text || '|' || (recorded_by = 'f0000000-0000-0000-0000-000000000007')::text
             from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000022' and kind = 'balance'),
  'mock|fin-c2-bal|gateway|-|1000.00|true', 'guest self-checkout is an online gateway payment');

-- Another resort may issue the same receipt number.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000023', 'R-555', 1000, 'card')$$,
  'resort S''s accountant records a card payment with the same receipt number');
reset role;
set local request.jwt.claims to '';
select is((select count(*)::text || '|' || count(distinct property_id)::text
             from public.payments where reference = 'R-555'),
  '2|2', 'two resorts using the same reference both succeed');
set local role authenticated;

-- Review Focus 4: nothing left to pay writes nothing.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000024', null, 0, 'upi')$$,
  'a fully paid booking checks out at the desk');
select is((select count(*)::int from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000024' and kind = 'balance'),
  0, 'nothing left to pay writes no payment');

-- A staff member checking out their own stay may still use a desk method.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000025', '   ', 800, 'cash')$$,
  'a staff member checking out their own stay may record cash');
select is((select method::text || '|' || coalesce(reference, '-') || '|' || amount::text
             from public.payments
            where reservation_id = 'ffffffff-0000-4000-8000-000000000025' and kind = 'balance'),
  'cash|-|800.00', 'a blank reference is stored as none');
select is((select status::text from public.reservations
            where id = 'ffffffff-0000-4000-8000-000000000026'),
  'checked_in', 'the refused desk checkout left the booking checked in');

reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/40_finance_ledger_test.sql`
Expected: FAIL at test 19 (`a guest passing a desk method is refused`: "threw no exception"), because the Task 1 body ignores `p_method`. Later tests in the section fail or cascade from it.

- [ ] **Step 3: Replace the `checkout_booking` body**

In `0048_finance_ledger.sql`, replace the whole block from `create function public.checkout_booking(` through its closing `$$;` (keep the `drop function` above it and the `revoke`/`grant` below it) with the block below. As in Task 1 Step 5: if the 0047 body you printed there differs from this one in anything other than whitespace, comments and the lines marked `0048`, keep 0047's version of those lines.

```sql
create function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric,
  p_method         public.payment_method default 'gateway'
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.reservations;
  v_charges jsonb;
  v_balance numeric(12,2);
  v_method  public.payment_method := coalesce(p_method, 'gateway');   -- 0048
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, true, 'owner','admin','staff','accountant');
  end if;

  -- 0048: only resort staff record a desk method, and only at the
  -- booking's own resort. A guest's own checkout (the branch above
  -- skipped) can only be gateway; a staff member checking out their own
  -- stay passes this check. Before the early return, so a guest never
  -- gets a desk method accepted, even as a no-op.
  if v_method <> 'gateway'
     and not public.has_resort_role(v_row.property_id, true,
                                    'owner','admin','staff','accountant') then
    raise exception 'desk payment methods are recorded by resort staff'
      using errcode = 'P0009';
  end if;

  if v_row.status = 'checked_out' then
    return v_row;   -- idempotent: a retried checkout must not double-charge
  end if;

  if v_row.status <> 'checked_in' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  v_charges := public.current_charges(p_reservation_id);
  v_balance := (v_charges ->> 'balance')::numeric;

  if v_balance > 0 and (p_amount is null or p_amount is distinct from v_balance) then
    raise exception 'payment amount % does not match balance due %',
      p_amount, v_balance
      using errcode = 'P0009';
  end if;

  if v_balance > 0 then
    if v_method = 'gateway' then
      insert into public.payments
        (reservation_id, amount, kind, status, gateway, gateway_ref, method, recorded_by)
      values (p_reservation_id, v_balance, 'balance', 'succeeded', 'mock', p_payment_ref,
              'gateway', v_uid);
    else
      -- 0048: one balance payment per booking, so 'desk-<id>' stays unique
      -- under unique (gateway, gateway_ref) and doubles as a retry guard.
      -- The receipt/UTR number goes in `reference`, which is not unique.
      insert into public.payments
        (reservation_id, amount, kind, status, gateway, gateway_ref, method, reference, recorded_by)
      values (p_reservation_id, v_balance, 'balance', 'succeeded', 'desk',
              'desk-' || p_reservation_id, v_method,
              nullif(btrim(p_payment_ref), ''), v_uid);
    end if;
  end if;

  update public.reservations
     set status = 'checked_out', checked_out_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  -- 0047: the room needs cleaning now.
  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (v_row.unit_id, v_row.property_id, 'dirty', null, v_uid, now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_row;
end;
$$;
```

Also change the Task 1 header comment line `-- added by Task 2 of the finance plan.` to `-- is marked 0048.`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/40_finance_ledger_test.sql supabase/tests/33_stay_checkout_test.sql supabase/tests/35_customer_checkout_test.sql supabase/tests/39_room_status_test.sql`
Expected: 40 at 34/34; 33, 35 and 39 unchanged.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0048_finance_ledger.sql supabase/tests/40_finance_ledger_test.sql
git commit -m "feat(db): checkout_booking records the payment method; desk methods for resort staff only"
```

---

### Task 3: `report_collections`

**Track:** DB. **Depends on:** Task 2.

**Files:**
- Modify: `supabase/migrations/0048_finance_ledger.sql` (replace the `report_collections` stub)
- Test: `supabase/tests/40_finance_ledger_test.sql` (append a section)

**Interfaces:**
- Consumes: the Task 1 signature, `public.assert_resort_role`, the August fixtures and Task 2's checkouts.
- Produces: `report_collections(p_from, p_to, p_property_id)`: one row per day × channel × source × method, ordered by those columns, where:
  - `booking_advance` / `checkout_balance` rows come from succeeded `payments` of the resort, dated by `created_at` in the resort's timezone; channel `online` when `method = 'gateway'`, else `front_desk`;
  - `walk_in_sale` rows come from `food_activity_sales`, dated by `sale_date`, channel `front_desk`;
  - `refund` rows come from cancelled bookings dated by `cancelled_at`, amount `−least(coalesce(refund_amount, 0), paid)`, method `gateway`, channel `online`; zero rows are left out.
  Task 5's `finance_summary` calls it for today.
- State left for Task 4: unchanged fixtures; the file ends with `reset role` and empty claims.

Worked figures (resort R, August 2026), which the tests below pin:

| Day | Channel | Source | Method | Count | Amount | From |
|---|---|---|---|---|---|---|
| 08-01 | online | booking_advance | gateway | 1 | 5000.00 | B1 (S's 9,999 excluded) |
| 08-02 | online | booking_advance | gateway | 1 | 336.00 | B2 (the failed 999 excluded) |
| 08-03 | online | booking_advance | gateway | 1 | 2000.00 | B4 |
| 08-04 | online | booking_advance | gateway | 1 | 1000.00 | B6 |
| 08-05 | online | refund | gateway | 1 | -1500.00 | B4 |
| 08-07 | online | refund | gateway | 1 | -1000.00 | B6, capped at the 1,000 paid |
| 08-10 | front_desk | walk_in_sale | cash | 2 | 550.00 | Thali + Tea (S's snack excluded) |
| 08-10 | front_desk | walk_in_sale | upi | 1 | 300.00 | Pool pass |
| 08-12 | front_desk | checkout_balance | cash | 1 | 7540.00 | B1 |
| 08-15 | online | booking_advance | gateway | 1 | 1000.00 | B7 |
| 08-21 | online | checkout_balance | gateway | 1 | 2000.00 | B7 |
| 08-24 | online | booking_advance | gateway | 1 | 500.00 | B3 at 23:30 |
| 08-25 | online | booking_advance | gateway | 1 | 500.00 | B3 at 00:15 |

13 rows, summing to 18,226.00. Nothing on 08-06 (B5 was never paid).

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/40_finance_ledger_test.sql`, change `select plan(34);` to `select plan(47);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 3: report_collections =============================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')),
  13, 'August has 13 collection lines');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount,
                             ';' order by c.channel, c.source, c.method)
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-01'),
  'online|booking_advance|gateway|1|5000.00',
  'an online advance is dated by its payment, and resort S''s payment stays out');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-02'),
  'online|booking_advance|gateway|1|336.00', 'a failed payment is not a collection');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-05'),
  'online|refund|gateway|1|-1500.00', 'a refund is negative, online, on the cancel date');
select is((select count(*)::int
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-06'),
  0, 'a cancelled unpaid hold shows no refund');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-07'),
  'online|refund|gateway|1|-1000.00', 'a refund larger than the amount paid is capped at what was paid');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount,
                             ';' order by c.method)
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-10'),
  'front_desk|walk_in_sale|cash|2|550.00;front_desk|walk_in_sale|upi|1|300.00',
  'walk-in sales are front-desk money, by method');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-12'),
  'front_desk|checkout_balance|cash|1|7540.00', 'a desk balance is front-desk money by its method');
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c
            where c.day = '2026-08-21'),
  'online|checkout_balance|gateway|1|2000.00', 'a self-checkout balance is online money');
select is((select array_agg(c.day order by c.day)
             from public.report_collections('2026-08-24', '2026-08-25', 'ffffffff-0000-4000-8000-000000000001') c),
  array['2026-08-24', '2026-08-25']::date[],
  'payments at 23:30 and 00:15 resort time fall on their resort-local days');
select is((select count(*)::int
             from public.report_collections('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001')),
  2, 'a one-day range returns that day only');
select is((select sum(c.amount)
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') c),
  18226.00::numeric, 'August nets to 18,226.00');
-- Today, after Task 2: C1 and C5 were paid in cash at the desk.
select is((select c.method::text || '|' || c.txn_count || '|' || c.amount
             from public.report_collections((now() at time zone 'Asia/Kolkata')::date,
                                            (now() at time zone 'Asia/Kolkata')::date,
                                            'ffffffff-0000-4000-8000-000000000001') c
            where c.channel = 'front_desk' and c.source = 'checkout_balance'),
  'cash|2|2800.00', 'today''s desk checkouts are collected under cash');

reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/40_finance_ledger_test.sql`
Expected: FAIL at test 35 with `report_collections is not implemented yet` (SQLSTATE 0A000).

- [ ] **Step 3: Replace the stub**

In `0048_finance_ledger.sql`, replace the whole `create function public.report_collections(` … `$$;` block with:

```sql
create function public.report_collections(p_from date, p_to date, p_property_id uuid)
returns table (
  day       date,
  channel   text,
  source    text,
  method    public.payment_method,
  txn_count int,
  amount    numeric
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

  -- Cash basis: money in (payments, walk-in sales) and out (refunds) on
  -- the resort-local day it moved. Column names are prefixed (l_*) so
  -- they never collide with this function's OUT parameters.
  return query
  with paid as (
    select pm.reservation_id as res_id, sum(pm.amount) as paid_total
      from public.payments pm
     where pm.property_id = p_property_id and pm.status = 'succeeded'
     group by pm.reservation_id
  ),
  lines as (
    select (pm.created_at at time zone v_tz)::date as l_day,
           case when pm.method = 'gateway' then 'online' else 'front_desk' end as l_channel,
           case pm.kind when 'advance' then 'booking_advance' else 'checkout_balance' end as l_source,
           pm.method as l_method,
           pm.amount as l_amount
      from public.payments pm
     where pm.property_id = p_property_id
       and pm.status = 'succeeded'
       and pm.created_at >= (p_from::timestamp at time zone v_tz)
       and pm.created_at <  ((p_to + 1)::timestamp at time zone v_tz)
    union all
    select s.sale_date, 'front_desk', 'walk_in_sale', s.payment_method, s.amount
      from public.food_activity_sales s
     where s.property_id = p_property_id
       and s.sale_date between p_from and p_to
    union all
    -- A refund goes back the way the advance came in, and never exceeds
    -- what the booking actually paid (compute_refund works on the quote
    -- total, not on the money received).
    select (r.cancelled_at at time zone v_tz)::date, 'online', 'refund',
           'gateway'::public.payment_method,
           -least(coalesce(r.refund_amount, 0), coalesce(pd.paid_total, 0))
      from public.reservations r
      left join paid pd on pd.res_id = r.id
     where r.property_id = p_property_id
       and r.status = 'cancelled'
       and r.cancelled_at >= (p_from::timestamp at time zone v_tz)
       and r.cancelled_at <  ((p_to + 1)::timestamp at time zone v_tz)
       and least(coalesce(r.refund_amount, 0), coalesce(pd.paid_total, 0)) > 0
  )
  select l.l_day, l.l_channel, l.l_source, l.l_method,
         count(*)::int, round(sum(l.l_amount), 2)
    from lines l
   group by l.l_day, l.l_channel, l.l_source, l.l_method
   order by l.l_day, l.l_channel, l.l_source, l.l_method;
end;
$$;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/40_finance_ledger_test.sql`
Expected: PASS, 47/47.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0048_finance_ledger.sql supabase/tests/40_finance_ledger_test.sql
git commit -m "feat(db): report_collections -- money in and out by day, channel, source and method"
```

---

### Task 4: `report_ledger`

**Track:** DB. **Depends on:** Task 3.

**Files:**
- Modify: `supabase/migrations/0048_finance_ledger.sql` (replace the `report_ledger` stub)
- Test: `supabase/tests/40_finance_ledger_test.sql` (append a section)

**Interfaces:**
- Consumes: the Task 1 signature, `public.assert_resort_role`, the fixtures.
- Produces: `report_ledger(p_from, p_to, p_property_id)`: one row per day × category × source, ordered by those columns, with `taxable = gross − discount` and `net = taxable + tax`:
  - `room` / `booking`: bookings (`kind = 'booking'`, quote not null, status `confirmed`, `checked_in` or `checked_out`) on their arrival date. `gross` = quote `subtotal`; `discount` = `least(coupon discount, subtotal)`; `tax` = `round(taxable × tax_pct / 100, 2)`. A quote without `subtotal` puts its whole `total` in `gross`, with no discount and no tax.
  - `ancillary` / `cleaning_fee`: the same bookings and day, only for itemised quotes with a cleaning fee (or leftover tax). `gross` = `cleaning_fee`; `discount` = `least(coupon discount − room discount, cleaning_fee)`; `tax` = quote `tax_amount` − the room tax. So room + cleaning tax = `tax_amount`, and room + cleaning net = `total`.
  - `ancillary` / `cancellation_fee`: cancelled bookings on the `cancelled_at` day; `gross` = paid − the capped refund, when above 0.
  - `food_beverage` / `in_stay_order` (food orders not cancelled, by `created_at`), `food_beverage` / `walk_in` (walk-in `food`), `spa_activities` / `activity_booking` (activity bookings `booked`, by `booking_date`), `spa_activities` / `walk_in` (walk-in `activity`). No tax.
  Task 5's `finance_summary` sums today's `tax` as `room_tax`.
- State left for Task 5: unchanged; the file ends with `reset role` and empty claims.

Worked figures (resort R, August 2026, ordered by day, category, source):

| Day | Category / source | Gross | Discount | Taxable | Tax | Net |
|---|---|---|---|---|---|---|
| 08-05 | ancillary / cancellation_fee | 500 | 0 | 500 | 0 | 500 (B4: 2,000 − 1,500) |
| 08-10 | ancillary / cleaning_fee | 500 | 0 | 500 | 60 | 560 (B1) |
| 08-10 | food_beverage / walk_in | 550 | 0 | 550 | 0 | 550 |
| 08-10 | room / booking | 10000 | 1000 | 9000 | 1080 | 10080 (B1) |
| 08-10 | spa_activities / walk_in | 300 | 0 | 300 | 0 | 300 |
| 08-11 | food_beverage / in_stay_order | 700 | 0 | 700 | 0 | 700 (cancelled 300 out) |
| 08-11 | spa_activities / activity_booking | 1200 | 0 | 1200 | 0 | 1200 (cancelled 600 out) |
| 08-13 | ancillary / cleaning_fee | 500 | 200 | 300 | 36 | 336 (B2) |
| 08-13 | room / booking | 1000 | 1000 | 0 | 0 | 0 (B2) |
| 08-14 | room / booking | 2000 | 0 | 2000 | 0 | 2000 (B3, total only) |
| 08-20 | room / booking | 3000 | 0 | 3000 | 0 | 3000 (B7; cancelled B4 out) |

11 rows. B5 (never paid) and B6 (refund ate the whole payment) keep no cancellation fee.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/40_finance_ledger_test.sql`, change `select plan(47);` to `select plan(63);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 4: report_ledger ==================================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int
             from public.report_ledger('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')),
  11, 'August has 11 ledger lines');
select is((select l.gross || '|' || l.discount || '|' || l.taxable || '|' || l.tax || '|' || l.net
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'room'),
  '10000.00|1000.00|9000.00|1080.00|10080.00',
  'nightly rates and extra guests are room gross; the coupon is its discount; tax is on what is left');
select is((select l.gross || '|' || l.discount || '|' || l.taxable || '|' || l.tax || '|' || l.net
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source = 'cleaning_fee'),
  '500.00|0.00|500.00|60.00|560.00', 'the cleaning fee is ancillary revenue with its share of the tax');
select is((select sum(l.tax)
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source in ('booking', 'cleaning_fee')),
  1140.00::numeric, 'room + cleaning tax equals the quote''s tax_amount (1,140)');
select is((select sum(l.net)
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source in ('booking', 'cleaning_fee')),
  10640.00::numeric, 'room + cleaning net equals the quote total (10,640)');
select is((select l.gross || '|' || l.discount || '|' || l.taxable || '|' || l.tax || '|' || l.net
             from public.report_ledger('2026-08-13', '2026-08-13', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'room'),
  '1000.00|1000.00|0.00|0.00|0.00', 'a coupon larger than the subtotal takes the whole room line');
select is((select l.gross || '|' || l.discount || '|' || l.taxable || '|' || l.tax || '|' || l.net
             from public.report_ledger('2026-08-13', '2026-08-13', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source = 'cleaning_fee'),
  '500.00|200.00|300.00|36.00|336.00', 'the rest of the coupon spills onto the cleaning fee, which carries the tax');
select is((select string_agg(l.category || '|' || l.source || '|' || l.gross || '|' || l.discount || '|'
                             || l.taxable || '|' || l.tax || '|' || l.net, ';')
             from public.report_ledger('2026-08-14', '2026-08-14', 'ffffffff-0000-4000-8000-000000000001') l),
  'room|booking|2000.00|0.00|2000.00|0.00|2000.00', 'a total-only quote is all room gross, untaxed');
select is((select l.gross
             from public.report_ledger('2026-08-11', '2026-08-11', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'food_beverage' and l.source = 'in_stay_order'),
  700.00::numeric, 'in-stay food orders are F&B; a cancelled order is not');
select is((select l.gross
             from public.report_ledger('2026-08-11', '2026-08-11', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'spa_activities' and l.source = 'activity_booking'),
  1200.00::numeric, 'activity bookings are Spa/Activities; a cancelled one is not');
select is((select string_agg(l.category || '|' || l.gross, ';' order by l.category)
             from public.report_ledger('2026-08-10', '2026-08-10', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source = 'walk_in'),
  'food_beverage|550.00;spa_activities|300.00', 'walk-in food is F&B and walk-in activities are Spa/Activities');
select is((select l.gross
             from public.report_ledger('2026-08-05', '2026-08-05', 'ffffffff-0000-4000-8000-000000000001') l
            where l.source = 'cancellation_fee'),
  500.00::numeric, 'the part of a paid booking kept on cancellation is an ancillary fee');
select is((select count(*)::int
             from public.report_ledger('2026-08-06', '2026-08-07', 'ffffffff-0000-4000-8000-000000000001')),
  0, 'no fee is kept from an unpaid hold or from a refund that took everything paid');
select is((select l.gross
             from public.report_ledger('2026-08-20', '2026-08-20', 'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'room'),
  3000.00::numeric, 'a cancelled booking is not room revenue');
select is((select bool_and(l.taxable = l.gross - l.discount and l.net = l.taxable + l.tax)
             from public.report_ledger('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') l),
  true, 'every line has taxable = gross - discount and net = taxable + tax');
-- Today: B9 arrives with 2,000 of room at 12%.
select is((select l.tax
             from public.report_ledger((now() at time zone 'Asia/Kolkata')::date,
                                       (now() at time zone 'Asia/Kolkata')::date,
                                       'ffffffff-0000-4000-8000-000000000001') l
            where l.category = 'room'),
  240.00::numeric, 'today''s arrival carries its room tax on today');

reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/40_finance_ledger_test.sql`
Expected: FAIL at test 48 with `report_ledger is not implemented yet` (SQLSTATE 0A000).

- [ ] **Step 3: Replace the stub**

In `0048_finance_ledger.sql`, replace the whole `create function public.report_ledger(` … `$$;` block with:

```sql
create function public.report_ledger(p_from date, p_to date, p_property_id uuid)
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
  -- arrival date (as in report_revenue). Tax is room tax only, exactly as
  -- fixed in each booking's quote (get_quote taxes subtotal + cleaning_fee
  -- - discount); it is split between the room line and the cleaning-fee
  -- line so the two add up to the quote's tax_amount and total.
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
           fo.total, 0, 0
      from public.food_orders fo
     where fo.property_id = p_property_id
       and fo.status <> 'cancelled'
       and fo.created_at >= (p_from::timestamp at time zone v_tz)
       and fo.created_at <  ((p_to + 1)::timestamp at time zone v_tz)
    union all
    select s.sale_date,
           case s.category when 'food' then 'food_beverage' else 'spa_activities' end,
           'walk_in', s.amount, 0, 0
      from public.food_activity_sales s
     where s.property_id = p_property_id
       and s.sale_date between p_from and p_to
    union all
    select ab.booking_date, 'spa_activities', 'activity_booking', ab.amount, 0, 0
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/40_finance_ledger_test.sql`
Expected: PASS, 63/63.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0048_finance_ledger.sql supabase/tests/40_finance_ledger_test.sql
git commit -m "feat(db): report_ledger -- revenue by category with room tax split from each quote"
```

---

### Task 5: `report_settlements`, `finance_summary`, and who may read them

**Track:** DB. **Depends on:** Task 4.

**Files:**
- Modify: `supabase/migrations/0048_finance_ledger.sql` (replace the last two stubs)
- Test: `supabase/tests/40_finance_ledger_test.sql` (append a section)

**Interfaces:**
- Consumes: `report_collections` (Task 3), `report_ledger` (Task 4), the fixtures and Task 2's checkouts.
- Produces:
  - `report_settlements(p_from, p_to, p_property_id)`: one row per booking whose `checked_out_at` falls in the range (resort-local), ordered by `checked_out_at`. `total` = quote total + non-cancelled food orders + non-cancelled activity bookings (as `current_charges`); `outstanding` = `total` − succeeded payments. See Plan decisions for `room`, `cleaning_fee`, `tax`, `desk_method` and `recorded_by_name`.
  - `finance_summary(p_property_id)`: the jsonb shape fixed in Task 1, for the resort's today.
- Final state of the file: plan 91.

Worked figures for today at resort R: online 1,000 (C2's balance); desk 2,920 = cash 2,800 (C1 2,000 + C5 800) + card 120 (Coffee); refunds 600 (B8); net 3,320; room tax 240 (B9); in house 1 (C6) owing 1,200.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/40_finance_ledger_test.sql`, change `select plan(63);` to `select plan(91);`. Then insert this section immediately before the final `select * from finish();`:

```sql
-- === Task 5: settlements, the day's summary, and who may read them ==========

set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int
             from public.report_settlements('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')),
  2, 'two bookings were checked out in August');
select is((select s.guest_name || '|' || s.unit_name || '|' || s.arrival || '|' || s.departure || '|'
                  || s.room || '|' || s.cleaning_fee || '|' || s.tax_pct || '|' || s.tax || '|'
                  || s.food || '|' || s.activities || '|' || s.total || '|' || s.advance_paid || '|'
                  || s.balance_online || '|' || s.balance_desk || '|' || coalesce(s.desk_method::text, '-') || '|'
                  || coalesce(s.desk_reference, '-') || '|' || coalesce(s.recorded_by_name, '-') || '|' || s.outstanding
             from public.report_settlements('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') s
            where s.reservation_id = 'ffffffff-0000-4000-8000-000000000031'),
  'Gita Guest|Cottage 1|2026-08-10|2026-08-12|9000.00|500.00|12.00|1140.00|700.00|1200.00|12540.00|5000.00|0.00|7540.00|cash|R-101|Sita Staff|0.00',
  'a desk settlement: its parts add up to the total, with the method, reference and who took it');
select is((select s.room || '|' || s.cleaning_fee || '|' || s.tax_pct || '|' || s.tax || '|' || s.total || '|'
                  || s.advance_paid || '|' || s.balance_online || '|' || s.balance_desk || '|'
                  || coalesce(s.desk_method::text, '-') || '|' || s.outstanding
             from public.report_settlements('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001') s
            where s.reservation_id = 'ffffffff-0000-4000-8000-000000000037'),
  '3000.00|0.00|0.00|0.00|3000.00|1000.00|2000.00|0.00|-|0.00',
  'an online settlement has no desk method');
select is((select count(*)::int
             from public.report_settlements((now() at time zone 'Asia/Kolkata')::date,
                                            (now() at time zone 'Asia/Kolkata')::date,
                                            'ffffffff-0000-4000-8000-000000000001')),
  4, 'today''s four checkouts at R are settled today');
select is((select coalesce(s.desk_method::text, '-') || '|' || coalesce(s.desk_reference, '-') || '|'
                  || s.advance_paid || '|' || s.balance_desk || '|' || coalesce(s.recorded_by_name, '-') || '|' || s.outstanding
             from public.report_settlements((now() at time zone 'Asia/Kolkata')::date,
                                            (now() at time zone 'Asia/Kolkata')::date,
                                            'ffffffff-0000-4000-8000-000000000001') s
            where s.reservation_id = 'ffffffff-0000-4000-8000-000000000021'),
  'cash|R-555|1000.00|2000.00|Sita Staff|0.00', 'the desk method and reference show on the settlement');
select is((select bool_and(s.outstanding = 0)
             from public.report_settlements((now() at time zone 'Asia/Kolkata')::date,
                                            (now() at time zone 'Asia/Kolkata')::date,
                                            'ffffffff-0000-4000-8000-000000000001') s),
  true, 'nothing is outstanding after a normal checkout');

select is((select (x.s -> 'resort' ->> 'name') || '|' || (x.s -> 'resort' ->> 'slug') || '|'
                  || (x.s -> 'resort' ->> 'gstin') || '|' || (x.s -> 'resort' ->> 'tax_pct') || '|'
                  || (x.s -> 'resort' ->> 'timezone')
             from (select public.finance_summary('ffffffff-0000-4000-8000-000000000001') as s) x),
  'Resort R|fin-r|29ABCDE1234F1Z5|12.00|Asia/Kolkata', 'the summary carries the export header');
select is((select (public.finance_summary('ffffffff-0000-4000-8000-000000000001') -> 'resort' ->> 'today')::date),
  (now() at time zone 'Asia/Kolkata')::date, 'today is the resort''s own date');
select is((select (x.s ->> 'online_collected') || '|' || (x.s -> 'desk_collected' ->> 'total') || '|'
                  || (x.s ->> 'refunds') || '|' || (x.s ->> 'net_collected')
             from (select public.finance_summary('ffffffff-0000-4000-8000-000000000001') as s) x),
  '1000.00|2920.00|600.00|3320.00', 'online, desk, refunds and net for today');
select is((select (x.s -> 'desk_collected' ->> 'cash') || '|' || (x.s -> 'desk_collected' ->> 'card') || '|'
                  || (x.s -> 'desk_collected' ->> 'upi') || '|' || (x.s -> 'desk_collected' ->> 'bank_transfer') || '|'
                  || (x.s -> 'desk_collected' ->> 'other')
             from (select public.finance_summary('ffffffff-0000-4000-8000-000000000001') as s) x),
  '2800.00|120.00|0.00|0.00|0.00', 'desk money by method, zero where none');
select is((select public.finance_summary('ffffffff-0000-4000-8000-000000000001') ->> 'room_tax'),
  '240.00', 'today''s room tax');
select is((select (x.s ->> 'in_house_count') || '|' || (x.s ->> 'in_house_balance')
             from (select public.finance_summary('ffffffff-0000-4000-8000-000000000001') as s) x),
  '1|1200.00', 'one guest in house, owing 1,200');

-- Who may read. Owner and admin as well as the accountant.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select * from public.report_ledger('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')$$,
  'the owner reads the ledger');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok($$select * from public.report_settlements('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')$$,
  'an admin reads settlements');
-- Plain staff keep their revenue and occupancy view, but no finance.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select * from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')$$,
  'P0020', null, 'plain staff cannot read collections');
select throws_ok($$select * from public.report_ledger('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')$$,
  'P0020', null, 'plain staff cannot read the ledger');
select throws_ok($$select * from public.report_settlements('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')$$,
  'P0020', null, 'plain staff cannot read settlements');
select throws_ok($$select public.finance_summary('ffffffff-0000-4000-8000-000000000001')$$,
  'P0020', null, 'plain staff cannot read the summary');
-- Other resorts, guests, no resort, anon.
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select * from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')$$,
  'P0020', null, 'resort S''s accountant cannot read resort R');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select public.finance_summary('ffffffff-0000-4000-8000-000000000002')$$,
  'P0020', null, 'resort R''s accountant cannot read resort S');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000006","role":"authenticated"}';
select throws_ok($$select * from public.report_ledger('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')$$,
  'P0020', null, 'a guest cannot read the ledger');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select * from public.report_collections('2026-08-01', '2026-08-31', null)$$,
  'P0020', null, 'no resort id, no report');
set local role anon;
select throws_ok($$select public.finance_summary('ffffffff-0000-4000-8000-000000000001')$$,
  '42501', null, 'anon cannot call the finance functions');
set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select string_agg(c.channel || '|' || c.source || '|' || c.method::text || '|' || c.txn_count || '|' || c.amount, ';')
             from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000002') c
            where c.day = '2026-08-01'),
  'online|booking_advance|gateway|1|9999.00', 'resort S''s accountant sees resort S''s money, and only it');

-- Suspended: reads work, checkout does not. `reset role` keeps the
-- claims; clear them so the status change runs with no caller.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'suspended'
 where id = 'ffffffff-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int
             from public.report_ledger('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')),
  11, 'a suspended resort''s ledger is still readable');
select lives_ok($$select public.finance_summary('ffffffff-0000-4000-8000-000000000001')$$,
  'a suspended resort''s summary is still readable');
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.checkout_booking('ffffffff-0000-4000-8000-000000000026', null, 1200, 'cash')$$,
  'P0022', null, 'no desk checkout at a suspended resort');

-- Archived: closed.
reset role;
set local request.jwt.claims to '';
update public.properties set status = 'archived'
 where id = 'ffffffff-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select * from public.report_collections('2026-08-01', '2026-08-31', 'ffffffff-0000-4000-8000-000000000001')$$,
  'P0020', null, 'an archived resort''s finance is closed');

reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/40_finance_ledger_test.sql`
Expected: FAIL at test 64 with `report_settlements is not implemented yet` (SQLSTATE 0A000).

- [ ] **Step 3: Replace the `report_settlements` stub**

In `0048_finance_ledger.sql`, replace the whole `create function public.report_settlements(` … `$$;` block with:

```sql
create function public.report_settlements(p_from date, p_to date, p_property_id uuid)
returns table (
  reservation_id   uuid,
  guest_name       text,
  unit_name        text,
  arrival          date,
  departure        date,
  room             numeric,
  cleaning_fee     numeric,
  tax_pct          numeric,
  tax              numeric,
  food             numeric,
  activities       numeric,
  total            numeric,
  advance_paid     numeric,
  balance_online   numeric,
  balance_desk     numeric,
  desk_method      public.payment_method,
  desk_reference   text,
  recorded_by_name text,
  outstanding      numeric
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

  -- One row per booking checked out in the range. room + cleaning_fee +
  -- tax + food + activities = total, where total is what current_charges
  -- bills (quote total + food + activities), and outstanding is total
  -- minus every succeeded payment.
  return query
  select r.id,
         coalesce(nullif(btrim(pr.full_name), ''), 'Guest'),
         u.name,
         (lower(r.period) at time zone v_tz)::date,
         (upper(r.period) at time zone v_tz)::date,
         round(q.q_room, 2),
         round(q.q_clean, 2),
         round(q.q_pct, 2),
         round(q.q_tax, 2),
         round(f.f_total, 2),
         round(a.a_total, 2),
         round(q.q_total + f.f_total + a.a_total, 2),
         round(pay.adv, 2),
         round(pay.bal_online, 2),
         round(pay.bal_desk, 2),
         case when bal.b_method <> 'gateway' then bal.b_method end,
         case when bal.b_method <> 'gateway' then bal.b_reference end,
         rb.full_name,
         round(q.q_total + f.f_total + a.a_total - pay.paid_all, 2)
    from public.reservations r
    join public.units u on u.id = r.unit_id
    left join public.profiles pr on pr.id = r.customer_id
    cross join lateral (
      select case when v.it then v.sub - least(v.disc, v.sub) else v.tot end as q_room,
             case when v.it then v.clean - least(v.disc - least(v.disc, v.sub), v.clean) else 0 end as q_clean,
             case when v.it then v.pct else 0 end as q_pct,
             case when v.it then v.taxamt else 0 end as q_tax,
             v.tot as q_total
        from (select coalesce(r.quote ? 'subtotal', false) as it,
                     coalesce((r.quote ->> 'subtotal')::numeric, 0) as sub,
                     coalesce((r.quote ->> 'cleaning_fee')::numeric, 0) as clean,
                     coalesce((r.quote -> 'coupon' ->> 'discount')::numeric, 0) as disc,
                     coalesce((r.quote ->> 'tax_pct')::numeric, 0) as pct,
                     coalesce((r.quote ->> 'tax_amount')::numeric, 0) as taxamt,
                     coalesce((r.quote ->> 'total')::numeric, 0) as tot) v
    ) q
    cross join lateral (
      select coalesce(sum(fo.total), 0) as f_total
        from public.food_orders fo
       where fo.reservation_id = r.id and fo.status <> 'cancelled'
    ) f
    cross join lateral (
      select coalesce(sum(ab.amount), 0) as a_total
        from public.activity_bookings ab
       where ab.reservation_id = r.id and ab.status <> 'cancelled'
    ) a
    cross join lateral (
      select coalesce(sum(pm.amount) filter (where pm.kind = 'advance'), 0) as adv,
             coalesce(sum(pm.amount) filter (where pm.kind = 'balance' and pm.method = 'gateway'), 0) as bal_online,
             coalesce(sum(pm.amount) filter (where pm.kind = 'balance' and pm.method <> 'gateway'), 0) as bal_desk,
             coalesce(sum(pm.amount), 0) as paid_all
        from public.payments pm
       where pm.reservation_id = r.id and pm.status = 'succeeded'
    ) pay
    left join lateral (
      select pm.method as b_method, pm.reference as b_reference, pm.recorded_by as b_by
        from public.payments pm
       where pm.reservation_id = r.id and pm.status = 'succeeded' and pm.kind = 'balance'
       order by pm.created_at desc
       limit 1
    ) bal on true
    left join public.profiles rb on rb.id = bal.b_by
   where r.property_id = p_property_id
     and r.kind = 'booking'
     and r.checked_out_at >= (p_from::timestamp at time zone v_tz)
     and r.checked_out_at <  ((p_to + 1)::timestamp at time zone v_tz)
   order by r.checked_out_at, r.id;
end;
$$;
```

- [ ] **Step 4: Replace the `finance_summary` stub**

In `0048_finance_ledger.sql`, replace the whole `create function public.finance_summary(` … `$$;` block with:

```sql
create function public.finance_summary(p_property_id uuid)
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

  -- Tax exists only on bookings: the room and cleaning-fee lines together.
  select coalesce(sum(l.tax), 0) into v_room_tax
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
      'name',     v_prop.name,
      'slug',     v_prop.slug,
      'gstin',    v_prop.gstin,
      'tax_pct',  v_prop.tax_pct,
      'timezone', v_prop.timezone,
      'today',    to_char(v_today, 'YYYY-MM-DD')),
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
    'in_house_count',   v_in_count,
    'in_house_balance', round(v_in_balance, 2)
  );
end;
$$;
```

- [ ] **Step 5: Run the whole database suite to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: 40 at 91/91; 37 at its post-B count with the allow-list guard passing; 33, 35 and 39 unchanged. The only failures are the baseline failures recorded in Task 1 Step 1.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0048_finance_ledger.sql supabase/tests/40_finance_ledger_test.sql
git commit -m "feat(db): report_settlements and finance_summary; finance tenancy and suspension tests"
```

---

## Phase 2: App track (after Task 1; 6 → 7 → 8, 7 → 9 → 11, 6 → 10; 12 independent)

### Task 6: Day tables and CSV for the finance reports

**Track:** App. **Depends on:** Task 1.

**Files:**
- Create: `lib/features/finance/finance_tables.dart`
- Create: `lib/features/finance/finance_csv.dart`
- Test: `test/features/finance/finance_tables_test.dart`, `test/features/finance/finance_csv_test.dart`

**Interfaces:**
- Consumes: `CollectionRow`, `LedgerRow`, `SettlementRow`, `FinanceResort`, `FinanceSummary`, `CollectionChannel`, `CollectionSource`, `LedgerCategory`, `PaymentMethod` (Task 1); `formatPct` (`lib/core/format.dart`); builders from `test/support/fake_finance_source.dart`.
- Produces (pure functions, no widgets):
  - `String formatMoney(num amount)` (`₹1,080.00`), `String isoDate(DateTime d)` (`2026-08-01`).
  - `class CollectionDay { DateTime? day; num online; Map<PaymentMethod, num> desk; num refunds; num deskFor(PaymentMethod); num get net; }` (`day` null on the totals row), `List<CollectionDay> collectionsByDay(List<CollectionRow>)` (oldest first), `CollectionDay collectionsTotal(List<CollectionDay>)`.
  - `class LedgerDay { DateTime? day; Map<LedgerCategory, num> byCategory; num tax; num categoryTotal(LedgerCategory); num get taxable; num get total; }`, `List<LedgerDay> ledgerByDay(List<LedgerRow>)`, `LedgerDay ledgerTotal(List<LedgerDay>)`. Category amounts are taxable amounts.
  - `String csvMoney(num)` (`1080.00`), `String gstinLabel(FinanceResort)` (`GSTIN <x>` or `GSTIN not set`), `List<List<String>> financeCsvHeader(FinanceResort, DateTime from, DateTime to)`, `String financeCsvFileName(String slug, String report, DateTime from, DateTime to)`, `List<List<String>> todayCsv(FinanceSummary)`, `collectionsCsv(FinanceResort, DateTime, DateTime, List<CollectionRow>)`, `ledgerCsv(FinanceResort, DateTime, DateTime, List<LedgerRow>)`, `settlementsCsv(FinanceResort, DateTime, DateTime, List<SettlementRow>)`, each returning `List<List<String>>` for `toCsv`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/finance/finance_tables_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/features/finance/finance_tables.dart';

import '../../support/fake_finance_source.dart';

void main() {
  group('collectionsByDay', () {
    final rows = [
      collectionRow(
          day: DateTime(2026, 8, 12),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.checkoutBalance,
          method: PaymentMethod.cash,
          amount: 7540),
      collectionRow(day: DateTime(2026, 8, 1), amount: 5000),
      collectionRow(
          day: DateTime(2026, 8, 5),
          source: CollectionSource.refund,
          amount: -1500),
      collectionRow(
          day: DateTime(2026, 8, 10),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.walkInSale,
          method: PaymentMethod.cash,
          txnCount: 2,
          amount: 550),
      collectionRow(
          day: DateTime(2026, 8, 10),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.walkInSale,
          method: PaymentMethod.upi,
          amount: 300),
    ];

    test('one entry per day, oldest first', () {
      expect(collectionsByDay(rows).map((d) => d.day), [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 5),
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 12),
      ]);
    });

    test('online, each desk method and refunds land in their own columns', () {
      final days = collectionsByDay(rows);

      expect(days[0].online, 5000);
      expect(days[1].refunds, -1500);
      expect(days[1].online, 0);
      expect(days[2].deskFor(PaymentMethod.cash), 550);
      expect(days[2].deskFor(PaymentMethod.upi), 300);
      expect(days[2].deskFor(PaymentMethod.card), 0);
      expect(days[2].net, 850);
      expect(days[3].deskFor(PaymentMethod.cash), 7540);
    });

    test('the totals row adds every column', () {
      final total = collectionsTotal(collectionsByDay(rows));

      expect(total.day, isNull);
      expect(total.online, 5000);
      expect(total.deskFor(PaymentMethod.cash), 8090);
      expect(total.deskFor(PaymentMethod.upi), 300);
      expect(total.deskFor(PaymentMethod.card), 0);
      expect(total.refunds, -1500);
      expect(total.net, 11890);
    });

    test('no rows give no days and a zero total', () {
      expect(collectionsByDay(const []), isEmpty);
      expect(collectionsTotal(const []).net, 0);
    });
  });

  group('ledgerByDay', () {
    final rows = [
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.room,
          gross: 10000,
          discount: 1000,
          tax: 1080),
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.ancillary,
          source: 'cleaning_fee',
          gross: 500,
          tax: 60),
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.foodBeverage,
          source: 'walk_in',
          gross: 550),
      ledgerRow(
          day: DateTime(2026, 8, 5),
          category: LedgerCategory.ancillary,
          source: 'cancellation_fee',
          gross: 500),
    ];

    test('category columns hold taxable amounts; taxable + tax = total', () {
      final days = ledgerByDay(rows);

      expect(days.map((d) => d.day), [DateTime(2026, 8, 5), DateTime(2026, 8, 10)]);
      final aug10 = days[1];
      expect(aug10.categoryTotal(LedgerCategory.room), 9000);
      expect(aug10.categoryTotal(LedgerCategory.ancillary), 500);
      expect(aug10.categoryTotal(LedgerCategory.foodBeverage), 550);
      expect(aug10.categoryTotal(LedgerCategory.spaActivities), 0);
      expect(aug10.taxable, 10050);
      expect(aug10.tax, 1140);
      expect(aug10.total, 11190);
    });

    test('the totals row adds every day', () {
      final total = ledgerTotal(ledgerByDay(rows));

      expect(total.day, isNull);
      expect(total.categoryTotal(LedgerCategory.ancillary), 1000);
      expect(total.taxable, 10550);
      expect(total.tax, 1140);
      expect(total.total, 11690);
    });
  });

  test('formatMoney keeps paise and Indian grouping', () {
    expect(formatMoney(1080), '₹1,080.00');
    expect(formatMoney(120000), '₹1,20,000.00');
    expect(formatMoney(36.5), '₹36.50');
  });

  test('isoDate is yyyy-MM-dd', () {
    expect(isoDate(DateTime(2026, 8, 1)), '2026-08-01');
  });
}
```

Create `test/features/finance/finance_csv_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/features/finance/finance_csv.dart';
import 'package:pasala/features/reports/csv_export.dart';

import '../../support/fake_finance_source.dart';

void main() {
  final resort = financeResort();
  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 8, 31);

  test('every file opens with the resort, its GSTIN and the period', () {
    expect(financeCsvHeader(resort, from, to), [
      ['Resort R', 'GSTIN 29ABCDE1234F1Z5'],
      ['Period', '2026-08-01', '2026-08-31'],
    ]);
  });

  test('a resort without a GSTIN says so', () {
    expect(gstinLabel(financeResort(gstin: null)), 'GSTIN not set');
    expect(gstinLabel(financeResort(gstin: '   ')), 'GSTIN not set');
  });

  test('collections keep channel, source and method per line', () {
    final rows = collectionsCsv(resort, from, to, [
      collectionRow(
          day: DateTime(2026, 8, 5),
          source: CollectionSource.refund,
          amount: -1500),
      collectionRow(
          day: DateTime(2026, 8, 10),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.walkInSale,
          method: PaymentMethod.bankTransfer,
          txnCount: 2,
          amount: 550),
    ]);

    expect(rows.take(2), financeCsvHeader(resort, from, to));
    expect(rows[2], ['Date', 'Channel', 'Source', 'Method', 'Transactions', 'Amount']);
    expect(rows[3], ['2026-08-05', 'online', 'refund', 'gateway', '1', '-1500.00']);
    expect(rows[4], ['2026-08-10', 'front_desk', 'walk_in_sale', 'bank_transfer', '2', '550.00']);
  });

  test('ledger lines carry category, source and every amount', () {
    final rows = ledgerCsv(resort, from, to, [
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.room,
          gross: 10000,
          discount: 1000,
          tax: 1080),
    ]);

    expect(rows[2],
        ['Date', 'Category', 'Source', 'Gross', 'Discount', 'Taxable', 'Tax', 'Net']);
    expect(rows[3],
        ['2026-08-10', 'room', 'booking', '10000.00', '1000.00', '9000.00', '1080.00', '10080.00']);
  });

  test('settlement lines carry the whole bill and how it was paid', () {
    final rows = settlementsCsv(resort, from, to, [
      settlementRow(
        room: 9000,
        cleaningFee: 500,
        taxPct: 12,
        tax: 1140,
        food: 700,
        activities: 1200,
        advancePaid: 5000,
        balanceDesk: 7540,
        deskMethod: PaymentMethod.cash,
        deskReference: 'R-101',
        recordedByName: 'Sita Staff',
      ),
      settlementRow(reservationId: 'r2', room: 3000, balanceOnline: 2000, advancePaid: 1000),
    ]);

    expect(rows[2], [
      'Reservation', 'Guest', 'Unit', 'Arrival', 'Departure', 'Room', 'Cleaning fee',
      'Tax %', 'Tax', 'Food', 'Activities', 'Total', 'Advance paid', 'Balance online',
      'Balance desk', 'Desk method', 'Desk reference', 'Recorded by', 'Outstanding',
    ]);
    expect(rows[3], [
      'r1', 'Gita Guest', 'Cottage 1', '2026-08-10', '2026-08-12', '9000.00', '500.00',
      '12', '1140.00', '700.00', '1200.00', '12540.00', '5000.00', '0.00',
      '7540.00', 'cash', 'R-101', 'Sita Staff', '0.00',
    ]);
    expect(rows[4].sublist(15, 18), ['', '', '']);
  });

  test("today's file lists every figure for the resort's today", () {
    final rows = todayCsv(financeSummary(
      online: 1000,
      desk: {PaymentMethod.cash: 2800, PaymentMethod.card: 120},
      refunds: 600,
      roomTax: 240,
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
      ['In-house guests', '1'],
      ['In-house unpaid balance', '1200.00'],
    ]);
  });

  test('the file name is <slug>-<report>-<from>-<to>.csv', () {
    expect(
        financeCsvFileName('pasala', 'collections', DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
        'pasala-collections-2026-09-01-2026-09-30.csv');
  });

  test('a resort name with a comma is quoted in the file', () {
    final csv = toCsv(financeCsvHeader(financeResort(name: 'Pasala, Riverside'), from, to));

    expect(csv, startsWith('"Pasala, Riverside",GSTIN 29ABCDE1234F1Z5\r\n'));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/finance/finance_tables_test.dart test/features/finance/finance_csv_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/features/finance/finance_tables.dart'".

- [ ] **Step 3: Write the day tables**

Create `lib/features/finance/finance_tables.dart`:

```dart
import 'package:intl/intl.dart';

import '../../data/models/finance.dart';
import '../../data/models/payment_method.dart';

final _money =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Finance figures keep their paise (`1080` -> `₹1,080.00`), unlike
/// `formatInr`, which rounds to whole rupees for guests.
String formatMoney(num amount) => _money.format(amount);

/// `yyyy-MM-dd`: the date format of every finance CSV and file name.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

num _sum(Iterable<num> values) => values.fold<num>(0, (a, b) => a + b);

/// One day of the Collections view: online money, desk money by method,
/// and refunds (zero or negative). [day] is null on the totals row.
class CollectionDay {
  const CollectionDay({
    this.day,
    this.online = 0,
    this.desk = const {},
    this.refunds = 0,
  });

  final DateTime? day;

  /// Online money that is not a refund.
  final num online;
  final Map<PaymentMethod, num> desk;
  final num refunds;

  num deskFor(PaymentMethod method) => desk[method] ?? 0;
  num get net => online + _sum(desk.values) + refunds;
}

/// Pivots `report_collections` lines into one [CollectionDay] per day,
/// oldest first.
List<CollectionDay> collectionsByDay(List<CollectionRow> rows) {
  final days = <DateTime>{};
  final online = <DateTime, num>{};
  final refunds = <DateTime, num>{};
  final desk = <DateTime, Map<PaymentMethod, num>>{};
  for (final r in rows) {
    days.add(r.day);
    if (r.source == CollectionSource.refund) {
      refunds[r.day] = (refunds[r.day] ?? 0) + r.amount;
    } else if (r.channel == CollectionChannel.online) {
      online[r.day] = (online[r.day] ?? 0) + r.amount;
    } else {
      final byMethod = desk.putIfAbsent(r.day, () => {});
      byMethod[r.method] = (byMethod[r.method] ?? 0) + r.amount;
    }
  }
  return [
    for (final d in days.toList()..sort())
      CollectionDay(
        day: d,
        online: online[d] ?? 0,
        desk: desk[d] ?? const {},
        refunds: refunds[d] ?? 0,
      ),
  ];
}

/// The totals row of [days].
CollectionDay collectionsTotal(List<CollectionDay> days) => CollectionDay(
      online: _sum(days.map((d) => d.online)),
      desk: {
        for (final m in PaymentMethod.desk) m: _sum(days.map((d) => d.deskFor(m))),
      },
      refunds: _sum(days.map((d) => d.refunds)),
    );

/// One day of the Ledger view: each category's taxable amount, and the
/// day's tax. [day] is null on the totals row.
class LedgerDay {
  const LedgerDay({this.day, this.byCategory = const {}, this.tax = 0});

  final DateTime? day;
  final Map<LedgerCategory, num> byCategory;
  final num tax;

  num categoryTotal(LedgerCategory category) => byCategory[category] ?? 0;
  num get taxable => _sum(byCategory.values);
  num get total => taxable + tax;
}

/// Pivots `report_ledger` lines into one [LedgerDay] per day, oldest first.
List<LedgerDay> ledgerByDay(List<LedgerRow> rows) {
  final byDay = <DateTime, Map<LedgerCategory, num>>{};
  final tax = <DateTime, num>{};
  for (final r in rows) {
    final categories = byDay.putIfAbsent(r.day, () => {});
    categories[r.category] = (categories[r.category] ?? 0) + r.taxable;
    tax[r.day] = (tax[r.day] ?? 0) + r.tax;
  }
  return [
    for (final d in byDay.keys.toList()..sort())
      LedgerDay(day: d, byCategory: byDay[d]!, tax: tax[d] ?? 0),
  ];
}

/// The totals row of [days].
LedgerDay ledgerTotal(List<LedgerDay> days) => LedgerDay(
      byCategory: {
        for (final c in LedgerCategory.values)
          c: _sum(days.map((d) => d.categoryTotal(c))),
      },
      tax: _sum(days.map((d) => d.tax)),
    );
```

- [ ] **Step 4: Write the CSV builders**

Create `lib/features/finance/finance_csv.dart`:

```dart
import '../../core/format.dart';
import '../../data/models/finance.dart';
import '../../data/models/payment_method.dart';
import 'finance_tables.dart';

/// Plain two-decimal amounts for spreadsheets: `1080.00`, `-1500.00`.
String csvMoney(num amount) => amount.toStringAsFixed(2);

/// `GSTIN 29ABCDE1234F1Z5`, or `GSTIN not set` for a resort without one.
String gstinLabel(FinanceResort resort) {
  final gstin = resort.gstin?.trim() ?? '';
  return gstin.isEmpty ? 'GSTIN not set' : 'GSTIN $gstin';
}

/// The two lines every finance file starts with: resort and GSTIN, then
/// the period.
List<List<String>> financeCsvHeader(
        FinanceResort resort, DateTime from, DateTime to) =>
    [
      [resort.name, gstinLabel(resort)],
      ['Period', isoDate(from), isoDate(to)],
    ];

/// `<slug>-<report>-<from>-<to>.csv`, e.g.
/// `pasala-collections-2026-09-01-2026-09-30.csv`.
String financeCsvFileName(
        String slug, String report, DateTime from, DateTime to) =>
    '$slug-$report-${isoDate(from)}-${isoDate(to)}.csv';

List<List<String>> todayCsv(FinanceSummary s) => [
      ...financeCsvHeader(s.resort, s.resort.today, s.resort.today),
      ['Figure', 'Amount'],
      ['Online collected', csvMoney(s.onlineCollected)],
      ['Desk collected', csvMoney(s.deskCollected)],
      for (final m in PaymentMethod.desk)
        ['Desk: ${m.label}', csvMoney(s.deskByMethod[m] ?? 0)],
      ['Refunds', csvMoney(s.refunds)],
      ['Net collected', csvMoney(s.netCollected)],
      ['Room tax', csvMoney(s.roomTax)],
      ['In-house guests', '${s.inHouseCount}'],
      ['In-house unpaid balance', csvMoney(s.inHouseBalance)],
    ];

List<List<String>> collectionsCsv(FinanceResort resort, DateTime from,
        DateTime to, List<CollectionRow> rows) =>
    [
      ...financeCsvHeader(resort, from, to),
      ['Date', 'Channel', 'Source', 'Method', 'Transactions', 'Amount'],
      for (final r in rows)
        [
          isoDate(r.day),
          r.channel.wire,
          r.source.wire,
          r.method.wire,
          '${r.txnCount}',
          csvMoney(r.amount),
        ],
    ];

List<List<String>> ledgerCsv(FinanceResort resort, DateTime from, DateTime to,
        List<LedgerRow> rows) =>
    [
      ...financeCsvHeader(resort, from, to),
      ['Date', 'Category', 'Source', 'Gross', 'Discount', 'Taxable', 'Tax', 'Net'],
      for (final r in rows)
        [
          isoDate(r.day),
          r.category.wire,
          r.source,
          csvMoney(r.gross),
          csvMoney(r.discount),
          csvMoney(r.taxable),
          csvMoney(r.tax),
          csvMoney(r.net),
        ],
    ];

List<List<String>> settlementsCsv(FinanceResort resort, DateTime from,
        DateTime to, List<SettlementRow> rows) =>
    [
      ...financeCsvHeader(resort, from, to),
      [
        'Reservation', 'Guest', 'Unit', 'Arrival', 'Departure', 'Room',
        'Cleaning fee', 'Tax %', 'Tax', 'Food', 'Activities', 'Total',
        'Advance paid', 'Balance online', 'Balance desk', 'Desk method',
        'Desk reference', 'Recorded by', 'Outstanding',
      ],
      for (final r in rows)
        [
          r.reservationId,
          r.guestName,
          r.unitName,
          isoDate(r.arrival),
          isoDate(r.departure),
          csvMoney(r.room),
          csvMoney(r.cleaningFee),
          formatPct(r.taxPct),
          csvMoney(r.tax),
          csvMoney(r.food),
          csvMoney(r.activities),
          csvMoney(r.total),
          csvMoney(r.advancePaid),
          csvMoney(r.balanceOnline),
          csvMoney(r.balanceDesk),
          r.deskMethod?.wire ?? '',
          r.deskReference ?? '',
          r.recordedByName ?? '',
          csvMoney(r.outstanding),
        ],
    ];
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/finance/finance_tables_test.dart test/features/finance/finance_csv_test.dart && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/finance/finance_tables.dart lib/features/finance/finance_csv.dart \
  test/features/finance/finance_tables_test.dart test/features/finance/finance_csv_test.dart
git commit -m "feat(finance): day pivots and CSV builders for the finance reports"
```

---

### Task 7: The Finance screen, with the Today and Collections tabs

**Track:** App. **Depends on:** Task 6.

**Files:**
- Create: `lib/features/finance/finance_screen.dart`
- Create: `lib/features/finance/finance_today_tab.dart`
- Create: `lib/features/finance/finance_collections_tab.dart`
- Test: `test/features/finance/finance_screen_test.dart`

**Interfaces:**
- Consumes: `financeSummaryProvider`, `collectionsProvider`, `csvDownloaderProvider`, `CsvDownloader`, `financeSourceProvider` (Task 1); `formatMoney`, `isoDate`, `collectionsByDay`, `collectionsTotal`, `todayCsv`, `collectionsCsv`, `financeCsvFileName` (Task 6); `currentResortProvider`, `AsyncView`, `EmptyState`, `toCsv`, `formatDate`, `PasalaTokens.wideBreakpoint`.
- Produces:
  - `class FinanceScreen extends ConsumerStatefulWidget { const FinanceScreen({Key? key, DateTimeRange? initialRange}); }` (Task 9 routes `/finance` to it). Inside, `_tabs` (label + report name per tab), `_rowsFor(int tab, FinanceSummary, ReportFilter)` and the `TabBarView` children are what Task 8 extends.
  - `FinanceTodayTab({required String propertyId})`, `FinanceCollectionsTab({required ReportFilter filter})`.
  - Keys: `finance-export`, `finance-range`; `today-online`, `today-desk`, `today-refunds`, `today-net`, `today-room-tax`, `today-in-house`; `collections-<yyyy-MM-dd>` and `collections-total` (phone cards), `collections-table` (wide).

- [ ] **Step 1: Write the failing tests**

Create `test/features/finance/finance_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/finance_collections_tab.dart';
import 'package:pasala/features/finance/finance_screen.dart';
import 'package:pasala/features/finance/providers.dart';

import '../../support/fake_finance_source.dart';

const _resort = ResortMembership(
    propertyId: 'p1', resortName: 'Resort R', role: ResortRole.accountant);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

final _august =
    DateTimeRange(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31));
final _augustFilter =
    (from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31), propertyId: 'p1');

/// Records every file handed to the downloader; answers [delivers].
class _Downloads {
  _Downloads({this.delivers = true});
  final bool delivers;
  final files = <(String, String)>[];

  bool download(String filename, String csv) {
    files.add((filename, csv));
    return delivers;
  }
}

/// A phone is 420 wide (below the 840 breakpoint); both sizes are tall
/// enough that every card of a list is built.
Future<void> _pump(
  WidgetTester tester,
  FakeFinanceSource source, {
  bool wide = false,
  _Downloads? downloads,
  bool settle = true,
}) async {
  tester.view.physicalSize = wide ? const Size(1400, 1400) : const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      financeSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(_FixedResort.new),
      csvDownloaderProvider.overrideWithValue((downloads ?? _Downloads()).download),
    ],
    child: MaterialApp(home: FinanceScreen(initialRange: _august)),
  ));
  if (settle) await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

Finder _inKey(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

final _augustRows = [
  collectionRow(day: DateTime(2026, 8, 1), amount: 5000),
  collectionRow(day: DateTime(2026, 8, 5), source: CollectionSource.refund, amount: -1500),
  collectionRow(
      day: DateTime(2026, 8, 10),
      channel: CollectionChannel.frontDesk,
      source: CollectionSource.walkInSale,
      method: PaymentMethod.cash,
      txnCount: 2,
      amount: 550),
  collectionRow(
      day: DateTime(2026, 8, 10),
      channel: CollectionChannel.frontDesk,
      source: CollectionSource.walkInSale,
      method: PaymentMethod.upi,
      amount: 300),
  collectionRow(
      day: DateTime(2026, 8, 12),
      channel: CollectionChannel.frontDesk,
      source: CollectionSource.checkoutBalance,
      method: PaymentMethod.cash,
      amount: 7540),
];

void main() {
  group('Today', () {
    testWidgets("shows the day's figures of the current resort", (tester) async {
      final source = FakeFinanceSource()
        ..summaryValue = financeSummary(
          online: 1000,
          desk: {PaymentMethod.cash: 2800, PaymentMethod.card: 120},
          refunds: 600,
          roomTax: 240,
          inHouseCount: 1,
          inHouseBalance: 1200,
        );
      await _pump(tester, source);

      expect(find.text('Today, 25 Sep 2026'), findsOneWidget);
      expect(_inKey('today-online', '₹1,000.00'), findsOneWidget);
      expect(_inKey('today-desk', '₹2,920.00'), findsOneWidget);
      expect(_inKey('today-desk', 'Cash ₹2,800.00'), findsOneWidget);
      expect(_inKey('today-desk', 'Card ₹120.00'), findsOneWidget);
      expect(_inKey('today-refunds', '₹600.00'), findsOneWidget);
      expect(_inKey('today-net', '₹3,320.00'), findsOneWidget);
      expect(_inKey('today-room-tax', '₹240.00'), findsOneWidget);
      expect(_inKey('today-in-house', '1'), findsOneWidget);
      expect(_inKey('today-in-house', 'Unpaid balance ₹1,200.00'), findsOneWidget);
      expect(source.summaryCalls, isNotEmpty);
      expect(source.summaryCalls, everyElement('p1'));
      // Today is always the resort's today: no range to pick.
      expect(find.byKey(const Key('finance-range')), findsNothing);
    });

    testWidgets('a failed load goes through FailureView', (tester) async {
      await _pump(tester, FakeFinanceSource()..summaryError = const NetworkFailure());

      expect(find.text('Cannot reach the server. Check your connection.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('pull to refresh fetches the summary again', (tester) async {
      final source = FakeFinanceSource();
      await _pump(tester, source);
      final before = source.summaryCalls.length;

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(source.summaryCalls.length, greaterThan(before));
    });
  });

  group('Collections', () {
    testWidgets('asks for the chosen range of the current resort', (tester) async {
      final source = FakeFinanceSource();
      await _pump(tester, source);
      await _openTab(tester, 'Collections');

      expect(source.collectionsCalls, isNotEmpty);
      expect(source.collectionsCalls, everyElement(_augustFilter));
      expect(find.text('1 Aug 2026 – 31 Aug 2026'), findsOneWidget);
    });

    testWidgets('a phone shows one card per day and a totals card', (tester) async {
      await _pump(tester, FakeFinanceSource()..collectionRows = _augustRows);
      await _openTab(tester, 'Collections');

      expect(_inKey('collections-2026-08-01', 'Online ₹5,000.00'), findsOneWidget);
      expect(_inKey('collections-2026-08-10', 'Cash ₹550.00'), findsOneWidget);
      expect(_inKey('collections-2026-08-10', 'UPI ₹300.00'), findsOneWidget);
      expect(_inKey('collections-2026-08-10', 'Net ₹850.00'), findsOneWidget);
      expect(_inKey('collections-total', 'Online ₹5,000.00'), findsOneWidget);
      expect(_inKey('collections-total', 'Cash ₹8,090.00'), findsOneWidget);
      expect(_inKey('collections-total', 'Net ₹11,890.00'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('collections-2026-08-05')),
              matching: find.textContaining(RegExp(r'^Refunds .*1,500\.00$'))),
          findsOneWidget);
    });

    testWidgets('a wide screen shows a table with a Total row', (tester) async {
      await _pump(tester, FakeFinanceSource()..collectionRows = _augustRows, wide: true);
      await _openTab(tester, 'Collections');

      expect(find.byKey(const Key('collections-table')), findsOneWidget);
      for (final header in ['Date', 'Online', 'Cash', 'Card', 'UPI', 'Bank', 'Other', 'Refunds', 'Net']) {
        expect(find.text(header), findsWidgets, reason: header);
      }
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₹11,890.00'), findsOneWidget);
    });

    testWidgets('no collections shows an empty state', (tester) async {
      await _pump(tester, FakeFinanceSource());
      await _openTab(tester, 'Collections');

      expect(find.text('No collections in this period'), findsOneWidget);
    });

    testWidgets('pull to refresh fetches collections again', (tester) async {
      final source = FakeFinanceSource()..collectionRows = _augustRows;
      await _pump(tester, source);
      await _openTab(tester, 'Collections');
      final before = source.collectionsCalls.length;

      await tester.fling(
          find.descendant(
              of: find.byType(FinanceCollectionsTab), matching: find.byType(ListView)),
          const Offset(0, 400),
          1000);
      await tester.pumpAndSettle();

      expect(source.collectionsCalls.length, greaterThan(before));
    });
  });

  group('Export', () {
    testWidgets('Collections exports the resort header, then one line per row',
        (tester) async {
      final downloads = _Downloads();
      await _pump(
          tester, FakeFinanceSource()..collectionRows = [collectionRow(amount: 5000)],
          downloads: downloads);
      await _openTab(tester, 'Collections');

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      final (name, csv) = downloads.files.single;
      expect(name, 'fin-r-collections-2026-08-01-2026-08-31.csv');
      expect(
          csv,
          'Resort R,GSTIN 29ABCDE1234F1Z5\r\n'
          'Period,2026-08-01,2026-08-31\r\n'
          'Date,Channel,Source,Method,Transactions,Amount\r\n'
          '2026-08-01,online,booking_advance,gateway,1,5000.00\r\n');
      expect(find.text('CSV exported.'), findsOneWidget);
    });

    testWidgets("Today exports under the resort's today", (tester) async {
      final downloads = _Downloads();
      await _pump(tester, FakeFinanceSource(), downloads: downloads);

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      final (name, csv) = downloads.files.single;
      expect(name, 'fin-r-today-2026-09-25-2026-09-25.csv');
      expect(csv, startsWith('Resort R,GSTIN 29ABCDE1234F1Z5\r\nPeriod,2026-09-25,2026-09-25\r\n'));
      expect(csv, contains('Net collected,0.00\r\n'));
    });

    testWidgets('a platform without downloads says so', (tester) async {
      await _pump(tester, FakeFinanceSource(), downloads: _Downloads(delivers: false));

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      expect(find.text("CSV export isn't available on this platform yet."), findsOneWidget);
    });

    // Review Focus 5.
    testWidgets('Export before the report has loaded says so and writes nothing',
        (tester) async {
      final source = FakeFinanceSource()..hold = Completer<void>();
      final downloads = _Downloads();
      await _pump(tester, source, downloads: downloads, settle: false);
      await tester.pump();

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      expect(find.text('Still loading -- try again in a moment.'), findsOneWidget);
      expect(downloads.files, isEmpty);
      source.hold!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Export after a failed load says so and writes nothing',
        (tester) async {
      final downloads = _Downloads();
      await _pump(tester, FakeFinanceSource()..collectionsError = const NetworkFailure(),
          downloads: downloads);
      await _openTab(tester, 'Collections');

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      expect(find.text("This report didn't load, so there is nothing to export."), findsOneWidget);
      expect(downloads.files, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/finance/finance_screen_test.dart`
Expected: FAIL to compile with "Target of URI doesn't exist: 'package:pasala/features/finance/finance_collections_tab.dart'".

- [ ] **Step 3: Write the Today tab**

Create `lib/features/finance/finance_today_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models/payment_method.dart';
import 'finance_tables.dart';
import 'providers.dart';

/// The Today tab: money in and out today in the resort's own timezone,
/// room tax, and what the guests in house still owe. Everything comes from
/// one `finance_summary` call.
class FinanceTodayTab extends ConsumerWidget {
  const FinanceTodayTab({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(financeSummaryProvider(propertyId));
    Future<void> refresh() => ref.refresh(financeSummaryProvider(propertyId).future);

    return AsyncView(
      value: summaryAsync,
      onRetry: () => ref.invalidate(financeSummaryProvider(propertyId)),
      data: (s) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Text('Today, ${formatDate(s.resort.today)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.md,
              children: [
                _FigureCard(
                  key: const Key('today-online'),
                  icon: PaymentMethod.gateway.icon,
                  label: 'Online collected',
                  value: formatMoney(s.onlineCollected),
                ),
                _FigureCard(
                  key: const Key('today-desk'),
                  icon: Icons.point_of_sale_outlined,
                  label: 'Desk collected',
                  value: formatMoney(s.deskCollected),
                  lines: [
                    for (final m in PaymentMethod.desk)
                      '${m.label} ${formatMoney(s.deskByMethod[m] ?? 0)}',
                  ],
                ),
                _FigureCard(
                  key: const Key('today-refunds'),
                  icon: Icons.undo_outlined,
                  label: 'Refunds',
                  value: formatMoney(s.refunds),
                ),
                _FigureCard(
                  key: const Key('today-net'),
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Net collected',
                  value: formatMoney(s.netCollected),
                ),
                _FigureCard(
                  key: const Key('today-room-tax'),
                  icon: Icons.receipt_long_outlined,
                  label: 'Room tax',
                  value: formatMoney(s.roomTax),
                ),
                _FigureCard(
                  key: const Key('today-in-house'),
                  icon: Icons.hotel_outlined,
                  label: 'In-house guests',
                  value: '${s.inHouseCount}',
                  lines: ['Unpaid balance ${formatMoney(s.inHouseBalance)}'],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.lines = const [],
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 280,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(child: Text(label, style: textTheme.labelLarge)),
              ]),
              const SizedBox(height: Spacing.sm),
              Text(value,
                  style: textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(line, style: textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the Collections tab**

Create `lib/features/finance/finance_collections_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/payment_method.dart';
import '../reports/providers.dart' show ReportFilter;
import 'finance_tables.dart';
import 'providers.dart';

/// One money column of the Collections view: its label on a card, its
/// (shorter) table header, and how to read it off a day.
typedef _Column = ({String label, String header, num Function(CollectionDay) value});

final List<_Column> _columns = [
  (label: 'Online', header: 'Online', value: (d) => d.online),
  for (final m in PaymentMethod.desk)
    (
      label: m.label,
      header: m == PaymentMethod.bankTransfer ? 'Bank' : m.label,
      value: (d) => d.deskFor(m),
    ),
  (label: 'Refunds', header: 'Refunds', value: (d) => d.refunds),
];

String _dayLabel(CollectionDay d) => d.day == null ? 'Total' : formatDate(d.day!);

/// The Collections tab: money in and out per day, online versus desk by
/// method, with refunds and a net. A table on wide screens, one card per
/// day on phones, and a totals row either way.
class FinanceCollectionsTab extends ConsumerWidget {
  const FinanceCollectionsTab({super.key, required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(collectionsProvider(filter));
    Future<void> refresh() => ref.refresh(collectionsProvider(filter).future);
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return AsyncView(
      value: rowsAsync,
      onRetry: () => ref.invalidate(collectionsProvider(filter)),
      empty: () => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            EmptyState(
              icon: Icons.payments_outlined,
              title: 'No collections in this period',
              message: 'Try a wider date range.',
            ),
          ],
        ),
      ),
      data: (rows) {
        final days = collectionsByDay(rows);
        final total = collectionsTotal(days);
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: wide
                ? [_CollectionsTable(days: days, total: total)]
                : [
                    for (final d in days)
                      _CollectionsCard(key: Key('collections-${isoDate(d.day!)}'), day: d),
                    _CollectionsCard(key: const Key('collections-total'), day: total),
                  ],
          ),
        );
      },
    );
  }
}

class _CollectionsTable extends StatelessWidget {
  const _CollectionsTable({required this.days, required this.total});

  final List<CollectionDay> days;
  final CollectionDay total;

  DataRow _row(CollectionDay d, {bool isTotal = false}) {
    final style = isTotal ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return DataRow(cells: [
      DataCell(Text(_dayLabel(d), style: style)),
      for (final c in _columns) DataCell(Text(formatMoney(c.value(d)), style: style)),
      DataCell(Text(formatMoney(d.net), style: style)),
    ]);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('collections-table'),
          columns: [
            const DataColumn(label: Text('Date')),
            for (final c in _columns) DataColumn(label: Text(c.header), numeric: true),
            const DataColumn(label: Text('Net'), numeric: true),
          ],
          rows: [for (final d in days) _row(d), _row(total, isTotal: true)],
        ),
      );
}

class _CollectionsCard extends StatelessWidget {
  const _CollectionsCard({super.key, required this.day});

  final CollectionDay day;

  @override
  Widget build(BuildContext context) {
    final isTotal = day.day == null;
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_dayLabel(day), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            for (final c in _columns)
              if (isTotal || c.value(day) != 0)
                Text('${c.label} ${formatMoney(c.value(day))}'),
            Text('Net ${formatMoney(day.net)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write the screen**

Create `lib/features/finance/finance_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/finance.dart';
import '../reports/csv_export.dart';
import '../reports/providers.dart' show ReportFilter;
import 'finance_collections_tab.dart';
import 'finance_csv.dart';
import 'finance_today_tab.dart';
import 'providers.dart';

DateTimeRange _currentMonth() {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 0),
  );
}

const _loading = 'Still loading -- try again in a moment.';
const _failed = "This report didn't load, so there is nothing to export.";

/// `/finance` -- the current resort's money, for owners, admins and
/// accountants (the router refuses everyone else; the report functions in
/// 0048_finance_ledger.sql refuse them too). Today, Collections (cash
/// basis), Ledger (accrual basis, with room tax) and Settlements, each
/// with pull-to-refresh, and an Export CSV action for the tab on screen.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key, this.initialRange});

  /// The range the dated tabs open on; this month when null.
  final DateTimeRange? initialRange;

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SingleTickerProviderStateMixin {
  /// One entry per tab, in order: its label and the report name used in
  /// the CSV file name.
  static const _tabs = [
    (label: 'Today', report: 'today'),
    (label: 'Collections', report: 'collections'),
  ];

  late final TabController _tabController =
      TabController(length: _tabs.length, vsync: this)..addListener(_onTabChanged);
  late DateTimeRange _range = widget.initialRange ?? _currentMonth();

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  ReportFilter _filterFor(String propertyId) =>
      (from: _range.start, to: _range.end, propertyId: propertyId);

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The CSV rows of [tab], built from what its provider already holds
  /// (never a second fetch): loading or failed while the tab is.
  AsyncValue<List<List<String>>> _rowsFor(
          int tab, FinanceSummary summary, ReportFilter filter) =>
      switch (tab) {
        0 => AsyncData(todayCsv(summary)),
        1 => ref.read(collectionsProvider(filter)).whenData(
            (rows) => collectionsCsv(summary.resort, filter.from, filter.to, rows)),
        _ => throw StateError('Finance has no tab $tab'),
      };

  /// Exports the tab on screen. The resort's name, slug and GSTIN come from
  /// the summary, so nothing is written until both it and the tab's report
  /// have loaded (Review Focus 5).
  void _export(String propertyId) {
    final summaryAsync = ref.read(financeSummaryProvider(propertyId));
    final summary = summaryAsync.value;
    if (summary == null) {
      _show(summaryAsync.hasError ? _failed : _loading);
      return;
    }
    final tab = _tabController.index;
    final filter = _filterFor(propertyId);
    final rowsAsync = _rowsFor(tab, summary, filter);
    final rows = rowsAsync.value;
    if (rows == null) {
      _show(rowsAsync.hasError ? _failed : _loading);
      return;
    }
    final today = summary.resort.today;
    final (from, to) = tab == 0 ? (today, today) : (filter.from, filter.to);
    final filename =
        financeCsvFileName(summary.resort.slug, _tabs[tab].report, from, to);
    final delivered = ref.read(csvDownloaderProvider)(filename, toCsv(rows));
    _show(delivered ? 'CSV exported.' : "CSV export isn't available on this platform yet.");
  }

  @override
  Widget build(BuildContext context) {
    final resort = ref.watch(currentResortProvider);
    if (resort == null) {
      // Only for the moment after sign-out, before the redirect fires.
      return const Scaffold(body: SizedBox.shrink());
    }
    final propertyId = resort.propertyId;
    final filter = _filterFor(propertyId);
    // Keeps the export header (name, slug, GSTIN) loaded on every tab.
    ref.watch(financeSummaryProvider(propertyId));
    final onToday = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          IconButton(
            key: const Key('finance-export'),
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _export(propertyId),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [for (final t in _tabs) Tab(text: t.label)],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!onToday)
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('finance-range'),
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text('${formatDate(_range.start)} – ${formatDate(_range.end)}'),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                FinanceTodayTab(propertyId: propertyId),
                FinanceCollectionsTab(filter: filter),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/finance/finance_screen_test.dart && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/finance/finance_screen.dart lib/features/finance/finance_today_tab.dart \
  lib/features/finance/finance_collections_tab.dart test/features/finance/finance_screen_test.dart
git commit -m "feat(finance): Finance screen with the Today and Collections tabs and CSV export"
```

---

### Task 8: The Ledger and Settlements tabs

**Track:** App. **Depends on:** Task 7.

**Files:**
- Create: `lib/features/finance/finance_ledger_tab.dart`
- Create: `lib/features/finance/finance_settlements_tab.dart`
- Modify: `lib/features/finance/finance_screen.dart` (two more tabs)
- Test: `test/features/finance/finance_screen_test.dart` (append two groups)

**Interfaces:**
- Consumes: `ledgerProvider`, `settlementsProvider`, `financeSummaryProvider` (Task 1); `ledgerByDay`, `ledgerTotal`, `formatMoney`, `isoDate`, `ledgerCsv`, `settlementsCsv`, `gstinLabel` (Task 6); the Task 7 screen and test helpers (`_pump`, `_openTab`, `_inKey`, `_Downloads`, `_augustFilter`).
- Produces: `FinanceLedgerTab({required ReportFilter filter})`, `FinanceSettlementsTab({required ReportFilter filter})`; keys `ledger-tax-strip`, `ledger-<yyyy-MM-dd>`, `ledger-total`, `ledger-table`, `settlement-<reservationId>`, `outstanding-<reservationId>`, `settlements-table`. The screen has four tabs: Today, Collections, Ledger, Settlements.

- [ ] **Step 1: Write the failing tests**

In `test/features/finance/finance_screen_test.dart`, append these two groups at the end of `main()`:

```dart
  group('Ledger', () {
    final rows = [
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.room,
          gross: 10000,
          discount: 1000,
          tax: 1080),
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.ancillary,
          source: 'cleaning_fee',
          gross: 500,
          tax: 60),
      ledgerRow(
          day: DateTime(2026, 8, 11),
          category: LedgerCategory.foodBeverage,
          source: 'in_stay_order',
          gross: 700),
    ];

    testWidgets('asks for the chosen range of the current resort', (tester) async {
      final source = FakeFinanceSource();
      await _pump(tester, source);
      await _openTab(tester, 'Ledger');

      expect(source.ledgerCalls, isNotEmpty);
      expect(source.ledgerCalls, everyElement(_augustFilter));
    });

    testWidgets('a phone shows one card per day and a totals card', (tester) async {
      await _pump(tester, FakeFinanceSource()..ledgerRows = rows);
      await _openTab(tester, 'Ledger');

      expect(_inKey('ledger-2026-08-10', 'Room ₹9,000.00'), findsOneWidget);
      expect(_inKey('ledger-2026-08-10', 'Ancillary ₹500.00'), findsOneWidget);
      expect(_inKey('ledger-2026-08-10', 'Tax ₹1,140.00'), findsOneWidget);
      expect(_inKey('ledger-2026-08-10', 'Total ₹10,640.00'), findsOneWidget);
      expect(_inKey('ledger-2026-08-11', 'F&B ₹700.00'), findsOneWidget);
      expect(_inKey('ledger-total', 'Taxable ₹10,200.00'), findsOneWidget);
      expect(_inKey('ledger-total', 'Total ₹11,340.00'), findsOneWidget);
    });

    testWidgets('the tax strip shows taxable, tax, the rate and the GSTIN', (tester) async {
      await _pump(tester, FakeFinanceSource()..ledgerRows = rows);
      await _openTab(tester, 'Ledger');

      expect(_inKey('ledger-tax-strip', 'Taxable ₹10,200.00'), findsOneWidget);
      expect(_inKey('ledger-tax-strip', 'Tax ₹1,140.00'), findsOneWidget);
      expect(_inKey('ledger-tax-strip', 'Current rate 12%'), findsOneWidget);
      expect(_inKey('ledger-tax-strip', 'GSTIN 29ABCDE1234F1Z5'), findsOneWidget);
    });

    testWidgets('a resort without a GSTIN says so on the strip', (tester) async {
      await _pump(
          tester,
          FakeFinanceSource()
            ..ledgerRows = rows
            ..summaryValue = financeSummary(resort: financeResort(gstin: null)));
      await _openTab(tester, 'Ledger');

      expect(_inKey('ledger-tax-strip', 'GSTIN not set'), findsOneWidget);
    });

    testWidgets('a wide screen shows a table with a Total row', (tester) async {
      await _pump(tester, FakeFinanceSource()..ledgerRows = rows, wide: true);
      await _openTab(tester, 'Ledger');

      expect(find.byKey(const Key('ledger-table')), findsOneWidget);
      for (final header in ['Room', 'F&B', 'Spa/Activities', 'Ancillary', 'Taxable', 'Tax', 'Total']) {
        expect(find.text(header), findsWidgets, reason: header);
      }
      expect(find.text('₹11,340.00'), findsOneWidget);
    });

    testWidgets('no revenue shows an empty state', (tester) async {
      await _pump(tester, FakeFinanceSource());
      await _openTab(tester, 'Ledger');

      expect(find.text('No revenue in this period'), findsOneWidget);
    });

    testWidgets('exports the ledger lines under the resort header', (tester) async {
      final downloads = _Downloads();
      await _pump(tester, FakeFinanceSource()..ledgerRows = rows, downloads: downloads);
      await _openTab(tester, 'Ledger');

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      final (name, csv) = downloads.files.single;
      expect(name, 'fin-r-ledger-2026-08-01-2026-08-31.csv');
      expect(csv, contains('Date,Category,Source,Gross,Discount,Taxable,Tax,Net\r\n'));
      expect(csv, contains('2026-08-10,room,booking,10000.00,1000.00,9000.00,1080.00,10080.00\r\n'));
    });
  });

  group('Settlements', () {
    final rows = [
      settlementRow(
        reservationId: 'r1',
        room: 9000,
        cleaningFee: 500,
        taxPct: 12,
        tax: 1140,
        food: 700,
        activities: 1200,
        advancePaid: 5000,
        balanceDesk: 7040,
        deskMethod: PaymentMethod.cash,
        deskReference: 'R-101',
        recordedByName: 'Sita Staff',
        outstanding: 500,
      ),
      settlementRow(
        reservationId: 'r2',
        guestName: 'Ravi Guest',
        unitName: 'Cottage 2',
        room: 3000,
        advancePaid: 1000,
        balanceOnline: 2000,
      ),
    ];

    testWidgets('asks for the chosen range of the current resort', (tester) async {
      final source = FakeFinanceSource();
      await _pump(tester, source);
      await _openTab(tester, 'Settlements');

      expect(source.settlementsCalls, isNotEmpty);
      expect(source.settlementsCalls, everyElement(_augustFilter));
    });

    testWidgets('one card per checkout, with how the balance was paid', (tester) async {
      await _pump(tester, FakeFinanceSource()..settlementRows = rows);
      await _openTab(tester, 'Settlements');

      expect(_inKey('settlement-r1', 'Gita Guest · Cottage 1'), findsOneWidget);
      expect(_inKey('settlement-r1', 'Total ₹12,540.00'), findsOneWidget);
      expect(_inKey('settlement-r1', 'Balance at desk ₹7,040.00 (Cash · R-101)'), findsOneWidget);
      expect(_inKey('settlement-r1', 'Recorded by Sita Staff'), findsOneWidget);
      expect(_inKey('settlement-r2', 'Balance online ₹2,000.00'), findsOneWidget);
    });

    testWidgets('a non-zero outstanding is flagged with an icon and text, not colour alone',
        (tester) async {
      await _pump(tester, FakeFinanceSource()..settlementRows = rows);
      await _openTab(tester, 'Settlements');

      final flag = find.byKey(const Key('outstanding-r1'));
      expect(flag, findsOneWidget);
      expect(find.descendant(of: flag, matching: find.byIcon(Icons.warning_amber_outlined)),
          findsOneWidget);
      expect(find.descendant(of: flag, matching: find.text('Outstanding ₹500.00')),
          findsOneWidget);
      expect(find.byKey(const Key('outstanding-r2')), findsNothing);
      expect(_inKey('settlement-r2', 'Settled'), findsOneWidget);
    });

    testWidgets('a wide screen shows a table, still flagging the outstanding one',
        (tester) async {
      await _pump(tester, FakeFinanceSource()..settlementRows = rows, wide: true);
      await _openTab(tester, 'Settlements');

      expect(find.byKey(const Key('settlements-table')), findsOneWidget);
      expect(find.byKey(const Key('outstanding-r1')), findsOneWidget);
      expect(find.byKey(const Key('outstanding-r2')), findsNothing);
    });

    testWidgets('no checkouts shows an empty state', (tester) async {
      await _pump(tester, FakeFinanceSource());
      await _openTab(tester, 'Settlements');

      expect(find.text('No checkouts in this period'), findsOneWidget);
    });

    testWidgets('exports one line per checkout', (tester) async {
      final downloads = _Downloads();
      await _pump(tester, FakeFinanceSource()..settlementRows = rows, downloads: downloads);
      await _openTab(tester, 'Settlements');

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      final (name, csv) = downloads.files.single;
      expect(name, 'fin-r-settlements-2026-08-01-2026-08-31.csv');
      expect(csv, contains('\r\nr1,Gita Guest,Cottage 1,2026-08-10,2026-08-12,'));
      expect(csv, contains(',cash,R-101,Sita Staff,500.00\r\n'));
    });
  });
```

`LedgerCategory` and `PaymentMethod` come from imports the file already has.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/finance/finance_screen_test.dart`
Expected: the Ledger and Settlements tests FAIL with "The finder "widget with type "Tab" that has text "Ledger"" … could not find", because the screen has only two tabs. The Task 7 tests still PASS.

- [ ] **Step 3: Write the Ledger tab**

Create `lib/features/finance/finance_ledger_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/finance.dart';
import '../reports/providers.dart' show ReportFilter;
import 'finance_csv.dart';
import 'finance_tables.dart';
import 'providers.dart';

typedef _Column = ({String label, num Function(LedgerDay) value});

/// Category columns hold taxable amounts, so they add up to Taxable, and
/// Taxable + Tax = Total.
final List<_Column> _columns = [
  for (final c in LedgerCategory.values) (label: c.label, value: (d) => d.categoryTotal(c)),
  (label: 'Taxable', value: (d) => d.taxable),
  (label: 'Tax', value: (d) => d.tax),
];

String _dayLabel(LedgerDay d) => d.day == null ? 'Total' : formatDate(d.day!);

/// The Ledger tab: revenue earned per day by category (accrual basis),
/// with room tax as fixed in each booking's quote, a totals row and a tax
/// strip.
class FinanceLedgerTab extends ConsumerWidget {
  const FinanceLedgerTab({super.key, required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(ledgerProvider(filter));
    final resort = ref.watch(financeSummaryProvider(filter.propertyId)).value?.resort;
    Future<void> refresh() => ref.refresh(ledgerProvider(filter).future);
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return AsyncView(
      value: rowsAsync,
      onRetry: () => ref.invalidate(ledgerProvider(filter)),
      empty: () => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            EmptyState(
              icon: Icons.account_balance_outlined,
              title: 'No revenue in this period',
              message: 'Try a wider date range.',
            ),
          ],
        ),
      ),
      data: (rows) {
        final days = ledgerByDay(rows);
        final total = ledgerTotal(days);
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _TaxStrip(total: total, resort: resort),
              const SizedBox(height: Spacing.md),
              if (wide)
                _LedgerTable(days: days, total: total)
              else ...[
                for (final d in days)
                  _LedgerCard(key: Key('ledger-${isoDate(d.day!)}'), day: d),
                _LedgerCard(key: const Key('ledger-total'), day: total),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TaxStrip extends StatelessWidget {
  const _TaxStrip({required this.total, required this.resort});

  final LedgerDay total;
  final FinanceResort? resort;

  @override
  Widget build(BuildContext context) {
    final r = resort;
    return Card(
      key: const Key('ledger-tax-strip'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Wrap(
          spacing: Spacing.lg,
          runSpacing: Spacing.xs,
          children: [
            Text('Taxable ${formatMoney(total.taxable)}'),
            Text('Tax ${formatMoney(total.tax)}'),
            if (r != null) Text('Current rate ${formatPct(r.taxPct)}%'),
            if (r != null) Text(gstinLabel(r)),
            Text("Each booking's own rate is in Settlements.",
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.days, required this.total});

  final List<LedgerDay> days;
  final LedgerDay total;

  DataRow _row(LedgerDay d, {bool isTotal = false}) {
    final style = isTotal ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return DataRow(cells: [
      DataCell(Text(_dayLabel(d), style: style)),
      for (final c in _columns) DataCell(Text(formatMoney(c.value(d)), style: style)),
      DataCell(Text(formatMoney(d.total), style: style)),
    ]);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('ledger-table'),
          columns: [
            const DataColumn(label: Text('Date')),
            for (final c in _columns) DataColumn(label: Text(c.label), numeric: true),
            const DataColumn(label: Text('Total'), numeric: true),
          ],
          rows: [for (final d in days) _row(d), _row(total, isTotal: true)],
        ),
      );
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({super.key, required this.day});

  final LedgerDay day;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: Spacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_dayLabel(day), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Spacing.xs),
              for (final c in LedgerCategory.values)
                if (day.categoryTotal(c) != 0)
                  Text('${c.label} ${formatMoney(day.categoryTotal(c))}'),
              Text('Taxable ${formatMoney(day.taxable)}'),
              Text('Tax ${formatMoney(day.tax)}'),
              Text('Total ${formatMoney(day.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}
```

Note: in the wide table the Total column header and the totals row label are both `Total`, and the table repeats the `Tax` and `Taxable` headers; the wide test only asserts `findsWidgets` for headers and a single `₹11,340.00`.

- [ ] **Step 4: Write the Settlements tab**

Create `lib/features/finance/finance_settlements_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/finance.dart';
import '../reports/providers.dart' show ReportFilter;
import 'finance_tables.dart';
import 'providers.dart';

/// `Cash · R-101`: how the desk balance was taken.
String _deskLine(SettlementRow r) =>
    [r.deskMethod?.label, r.deskReference].whereType<String>().join(' · ');

/// The Settlements tab: one row per booking checked out in the range, with
/// its whole bill and how it was paid. A non-zero outstanding carries an
/// icon and text, never colour alone.
class FinanceSettlementsTab extends ConsumerWidget {
  const FinanceSettlementsTab({super.key, required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(settlementsProvider(filter));
    Future<void> refresh() => ref.refresh(settlementsProvider(filter).future);
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return AsyncView(
      value: rowsAsync,
      onRetry: () => ref.invalidate(settlementsProvider(filter)),
      empty: () => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No checkouts in this period',
              message: 'Bookings checked out in this range show up here.',
            ),
          ],
        ),
      ),
      data: (rows) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: wide
              ? [_SettlementsTable(rows: rows)]
              : [for (final r in rows) _SettlementCard(key: Key('settlement-${r.reservationId}'), row: r)],
        ),
      ),
    );
  }
}

class _OutstandingFlag extends StatelessWidget {
  const _OutstandingFlag({required this.row});

  final SettlementRow row;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Row(
      key: Key('outstanding-${row.reservationId}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_outlined, size: 18, color: color),
        const SizedBox(width: Spacing.xs),
        Text('Outstanding ${formatMoney(row.outstanding)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({super.key, required this.row});

  final SettlementRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.guestName} · ${r.unitName}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('${formatDate(r.arrival)} → ${formatDate(r.departure)}'),
            const SizedBox(height: Spacing.xs),
            Text('Total ${formatMoney(r.total)}'),
            Text('Advance ${formatMoney(r.advancePaid)}'),
            if (r.balanceOnline != 0) Text('Balance online ${formatMoney(r.balanceOnline)}'),
            if (r.balanceDesk != 0)
              Text('Balance at desk ${formatMoney(r.balanceDesk)} (${_deskLine(r)})'),
            if (r.recordedByName != null) Text('Recorded by ${r.recordedByName}'),
            const SizedBox(height: Spacing.xs),
            if (r.outstanding != 0) _OutstandingFlag(row: r) else const Text('Settled'),
          ],
        ),
      ),
    );
  }
}

class _SettlementsTable extends StatelessWidget {
  const _SettlementsTable({required this.rows});

  final List<SettlementRow> rows;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('settlements-table'),
          columns: const [
            DataColumn(label: Text('Guest')),
            DataColumn(label: Text('Unit')),
            DataColumn(label: Text('Arrival')),
            DataColumn(label: Text('Departure')),
            DataColumn(label: Text('Room'), numeric: true),
            DataColumn(label: Text('Cleaning'), numeric: true),
            DataColumn(label: Text('Tax'), numeric: true),
            DataColumn(label: Text('Food'), numeric: true),
            DataColumn(label: Text('Activities'), numeric: true),
            DataColumn(label: Text('Total'), numeric: true),
            DataColumn(label: Text('Advance'), numeric: true),
            DataColumn(label: Text('Online'), numeric: true),
            DataColumn(label: Text('Desk'), numeric: true),
            DataColumn(label: Text('Method')),
            DataColumn(label: Text('Reference')),
            DataColumn(label: Text('Outstanding')),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(Text(r.guestName)),
                DataCell(Text(r.unitName)),
                DataCell(Text(formatDate(r.arrival))),
                DataCell(Text(formatDate(r.departure))),
                DataCell(Text(formatMoney(r.room))),
                DataCell(Text(formatMoney(r.cleaningFee))),
                DataCell(Text('${formatMoney(r.tax)} (${formatPct(r.taxPct)}%)')),
                DataCell(Text(formatMoney(r.food))),
                DataCell(Text(formatMoney(r.activities))),
                DataCell(Text(formatMoney(r.total))),
                DataCell(Text(formatMoney(r.advancePaid))),
                DataCell(Text(formatMoney(r.balanceOnline))),
                DataCell(Text(formatMoney(r.balanceDesk))),
                DataCell(Text(r.deskMethod?.label ?? '')),
                DataCell(Text(r.deskReference ?? '')),
                DataCell(r.outstanding != 0
                    ? _OutstandingFlag(row: r)
                    : Text(formatMoney(0))),
              ]),
          ],
        ),
      );
}
```

- [ ] **Step 5: Add the two tabs to the screen**

In `lib/features/finance/finance_screen.dart`, add these imports next to the other `finance_*` imports:

```dart
import 'finance_ledger_tab.dart';
import 'finance_settlements_tab.dart';
```

Replace:

```dart
  static const _tabs = [
    (label: 'Today', report: 'today'),
    (label: 'Collections', report: 'collections'),
  ];
```

with:

```dart
  static const _tabs = [
    (label: 'Today', report: 'today'),
    (label: 'Collections', report: 'collections'),
    (label: 'Ledger', report: 'ledger'),
    (label: 'Settlements', report: 'settlements'),
  ];
```

Replace:

```dart
        _ => throw StateError('Finance has no tab $tab'),
```

with:

```dart
        2 => ref.read(ledgerProvider(filter)).whenData(
            (rows) => ledgerCsv(summary.resort, filter.from, filter.to, rows)),
        3 => ref.read(settlementsProvider(filter)).whenData(
            (rows) => settlementsCsv(summary.resort, filter.from, filter.to, rows)),
        _ => throw StateError('Finance has no tab $tab'),
```

Replace:

```dart
                FinanceCollectionsTab(filter: filter),
              ],
```

with:

```dart
                FinanceCollectionsTab(filter: filter),
                FinanceLedgerTab(filter: filter),
                FinanceSettlementsTab(filter: filter),
              ],
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/finance/ && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/finance/finance_ledger_tab.dart lib/features/finance/finance_settlements_tab.dart \
  lib/features/finance/finance_screen.dart test/features/finance/finance_screen_test.dart
git commit -m "feat(finance): Ledger tab with the tax strip and Settlements tab with outstanding flags"
```

---

### Task 9: Navigation to Finance

**Track:** App. **Depends on:** Task 7.

**Files:**
- Modify: `lib/core/router.dart`
- Modify: `lib/features/shell/app_shell.dart`
- Modify: `lib/features/owner/owner_home_screen.dart`
- Modify: `lib/features/admin/admin_more_screen.dart`
- Test: `test/core/router_test.dart`, `test/features/shell/app_shell_test.dart`, `test/features/owner/owner_home_screen_test.dart`, `test/features/admin/admin_more_screen_test.dart`

**Interfaces:**
- Consumes: `FinanceScreen` (Task 7), `redirectFor`, `landingPathFor`, `routerProvider`; in `router_test.dart`, the helpers `_paths` and `_NoResort` that Project B's Task 7 added.
- Produces: the route `/finance` inside the signed-in shell, open to owner, admin and accountant at the current resort (`/404` for everyone else, `/choose-resort` first for a user with 2+ memberships and no pick). Accountants land on `/finance`. The accountant bar is Finance, Rooms, Dashboard, Reports; staff keep Today, Rooms, Dashboard, Reports. The owner hub gets a Finance tile and the admin More screen a Finance entry.

- [ ] **Step 1: Write the failing tests**

In `test/core/router_test.dart`, make three replacements. Replace:

```dart
    test('accountant lands on /staff/dashboard', () {
      expect(landingPathFor(_accountant, _accountantM), '/staff/dashboard');
    });
```

with:

```dart
    test('accountant lands on /finance', () {
      expect(landingPathFor(_accountant, _accountantM), '/finance');
    });
```

Replace:

```dart
        (ResortRole.accountant, '/staff/dashboard'),
```

with:

```dart
        (ResortRole.accountant, '/finance'),
```

Replace:

```dart
    test('accountant -> /staff/dashboard', () {
      expect(loginRedirect(_accountant, _accountantM), '/staff/dashboard');
    });
```

with:

```dart
    test('accountant -> /finance', () {
      expect(loginRedirect(_accountant, _accountantM), '/finance');
    });
```

Also change the test name `'owner lands on /owner, staff on /staff, accountant on dashboard'` to `'owner lands on /owner, staff on /staff, accountant on /finance'`.

Then append this group at the end of `main()`. It uses `_paths` and `_NoResort`, which Project B added to this file; if they are missing, add them after `_to` exactly as B's plan shows (Task 7 Step 1), with B's imports of `flutter_riverpod`, `go_router`, `current_resort.dart` and `auth_repository.dart`.

```dart
  group('finance', () {
    test('owner, admin and accountant open /finance', () {
      expect(_to(_superAdmin, _ownerM, '/finance'), null);
      expect(_to(_admin, _adminM, '/finance'), null);
      expect(_to(_accountant, _accountantM, '/finance'), null);
    });

    test('staff and customers are refused /finance', () {
      expect(_to(_staff, _staffM, '/finance'), '/404');
      expect(_to(_customer, null, '/finance'), '/404');
    });

    test('two memberships and no pick go to /choose-resort first', () {
      const u = AppUser(id: 'u', email: 'e', memberships: [
        ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.accountant),
        ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff),
      ]);
      expect(_to(u, null, '/finance'), '/choose-resort');
    });

    test('an accountant who picked a resort they are only staff at is refused', () {
      const u = AppUser(id: 'u', email: 'e', memberships: [
        ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.accountant),
        ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff),
      ]);
      expect(_to(u, u.memberships.last, '/finance'), '/404');
      expect(_to(u, u.memberships.first, '/finance'), null);
    });

    test('the app router registers /finance', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      expect(_paths(router.configuration.routes), contains('/finance'));
    });
  });
```

In `test/features/shell/app_shell_test.dart`, add a route to `_appFor`'s router, after the `/admin/more` route:

```dart
          GoRoute(path: '/finance', builder: (_, _) => const SizedBox()),
```

Then append these tests at the end of `main()`:

```dart
  testWidgets("an accountant's destinations are Finance, Rooms, Dashboard, "
      'Reports, in that order, with no Today', (tester) async {
    await tester.pumpWidget(_appFor(_accountant));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsNothing);
    final xs = [
      for (final label in ['Finance', 'Rooms', 'Dashboard', 'Reports'])
        tester.getCenter(find.text(label)).dx,
    ];
    expect(xs, [...xs]..sort());
  });

  testWidgets("an accountant's Finance destination opens /finance", (tester) async {
    await tester.pumpWidget(_appFor(_accountant));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();

    final router = GoRouter.of(tester.element(find.text('Finance')));
    expect(router.routerDelegate.currentConfiguration.uri.path, '/finance');
  });

  testWidgets('staff keep Today and get no Finance', (tester) async {
    await tester.pumpWidget(_appFor(_staff));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Finance'), findsNothing);
  });
```

In `test/features/owner/owner_home_screen_test.dart`, add a route to `_appFor`'s router, after the `/admin/bookings` route:

```dart
      GoRoute(path: '/finance', builder: (_, _) => const Text('Finance screen')),
```

In the test `'shows a tile for every step of the Owner flow'`, add `'Finance',` after `'Business dashboard',` in the title list. Then append:

```dart
  testWidgets('the Finance tile opens the Finance screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    final financeTile = find.text('Finance');
    await tester.ensureVisible(financeTile);
    await tester.pumpAndSettle();
    await tester.tap(financeTile);
    await tester.pumpAndSettle();

    expect(find.text('Finance screen'), findsOneWidget);
  });
```

In `test/features/admin/admin_more_screen_test.dart`, add `'Finance',` after `'Financial Dashboard',` in the title list, add the import `import 'package:go_router/go_router.dart';`, and append inside `main()`:

```dart
  testWidgets('the Finance entry opens /finance', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/admin/more',
      routes: [
        GoRoute(path: '/admin/more', builder: (_, _) => const AdminMoreScreen()),
        GoRoute(path: '/finance', builder: (_, _) => const Text('Finance screen')),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();

    expect(find.text('Finance screen'), findsOneWidget);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/router_test.dart test/features/shell/app_shell_test.dart test/features/owner/owner_home_screen_test.dart test/features/admin/admin_more_screen_test.dart`
Expected: FAIL on the three accountant landing tests (got `/staff/dashboard`), `staff and customers are refused /finance` (staff get `null`), `two memberships and no pick …` (got `null`), `an accountant who picked …`, `the app router registers /finance`, both accountant bar tests (no `Finance` text), and the Finance tile/entry tests. `owner, admin and accountant open /finance` already PASSES (no rule refuses an unknown path yet) and pins that behaviour.

- [ ] **Step 3: Route `/finance` and set the accountant landing**

In `lib/core/router.dart`, add the import after `import '../features/booking/confirmation_screen.dart';`:

```dart
import '../features/finance/finance_screen.dart';
```

Replace:

```dart
  if ((path.startsWith('/admin') ||
          path.startsWith('/staff') ||
          path.startsWith('/owner')) &&
```

with:

```dart
  if ((path.startsWith('/admin') ||
          path.startsWith('/staff') ||
          path.startsWith('/owner') ||
          path.startsWith('/finance')) &&
```

Replace:

```dart
  if (path.startsWith('/staff') && resort == null) return '/404';
```

with:

```dart
  if (path.startsWith('/staff') && resort == null) return '/404';
  // Finance (REQ-07): owner, admin and accountant at the current resort.
  // report_collections, report_ledger, report_settlements and
  // finance_summary assert the same roles in Postgres; plain staff keep
  // their `/admin/reports` view and get /404 here.
  if (path.startsWith('/finance') &&
      !const {ResortRole.owner, ResortRole.admin, ResortRole.accountant}
          .contains(resort?.role)) {
    return '/404';
  }
```

Replace:

```dart
    // Lands on the staff-operations hub, not `/admin/dashboard` (the
    // financial summary `AdminHomeScreen` still links to for admin) --
    // that route is no longer reachable from either role's own nav (see
    // `AppShell._staffDestinations`), so landing there would strand them
    // one tap short of the tabs they actually have.
    ResortRole.accountant => '/staff/dashboard',
```

with:

```dart
    // Finance (REQ-07) is the accountant's own screen -- collections,
    // ledger, tax and settlements -- and the first tab of their bar (see
    // `AppShell._accountantDestinations`).
    ResortRole.accountant => '/finance',
```

Replace:

```dart
          GoRoute(
            path: '/owner/team',
            builder: (_, _) => const TeamScreen(),
          ),
```

with:

```dart
          GoRoute(
            path: '/owner/team',
            builder: (_, _) => const TeamScreen(),
          ),
          // Finance (REQ-07). Owner, admin and accountant only (see
          // redirectFor); the report functions enforce the same in Postgres.
          GoRoute(
            path: '/finance',
            builder: (_, _) => const FinanceScreen(),
          ),
```

- [ ] **Step 4: Give accountants their own bar**

In `lib/features/shell/app_shell.dart`, replace:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final resort = ref.watch(currentResortProvider);
    final destinations = switch (resort?.role) {
      ResortRole.owner => _ownerDestinations,
      ResortRole.admin => _adminDestinations,
      ResortRole.staff || ResortRole.accountant => _staffDestinations,
```

with:

```dart
  // Accountants land on Finance (REQ-07) and keep Rooms (read-only),
  // Dashboard and Reports. No Today: they have no shift tasks.
  static const _accountantDestinations = [
    (path: '/finance', icon: Icons.account_balance_outlined, label: 'Finance'),
    (path: '/staff/rooms', icon: Icons.meeting_room_outlined, label: 'Rooms'),
    (
      path: '/staff/dashboard',
      icon: Icons.dashboard_outlined,
      label: 'Dashboard',
    ),
    (
      path: '/admin/reports',
      icon: Icons.summarize_outlined,
      label: 'Reports',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final resort = ref.watch(currentResortProvider);
    final destinations = switch (resort?.role) {
      ResortRole.owner => _ownerDestinations,
      ResortRole.admin => _adminDestinations,
      ResortRole.staff => _staffDestinations,
      ResortRole.accountant => _accountantDestinations,
```

- [ ] **Step 5: Add Finance to the owner hub and the admin More screen**

In `lib/features/owner/owner_home_screen.dart`, replace:

```dart
      subtitle: 'Revenue, occupancy, sales and expenses at a glance',
      path: '/owner/dashboard',
    ),
```

with:

```dart
      subtitle: 'Revenue, occupancy, sales and expenses at a glance',
      path: '/owner/dashboard',
    ),
    (
      icon: Icons.account_balance_outlined,
      title: 'Finance',
      subtitle: 'Collections, ledger, tax and settlements',
      path: '/finance',
    ),
```

In `lib/features/admin/admin_more_screen.dart`, replace:

```dart
      subtitle: 'Revenue, occupancy and the business at a glance',
      path: '/admin/dashboard',
    ),
```

with:

```dart
      subtitle: 'Revenue, occupancy and the business at a glance',
      path: '/admin/dashboard',
    ),
    (
      icon: Icons.account_balance_outlined,
      title: 'Finance',
      subtitle: 'Collections, ledger, tax and settlements',
      path: '/finance',
    ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/core/router_test.dart test/features/shell/app_shell_test.dart test/features/owner/owner_home_screen_test.dart test/features/admin/admin_more_screen_test.dart && flutter analyze`
Expected: all PASS, including B's `an accountant also gets the Rooms destination`. No new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add lib/core/router.dart lib/features/shell/app_shell.dart lib/features/owner/owner_home_screen.dart \
  lib/features/admin/admin_more_screen.dart test/core/router_test.dart test/features/shell/app_shell_test.dart \
  test/features/owner/owner_home_screen_test.dart test/features/admin/admin_more_screen_test.dart
git commit -m "feat(finance): /finance for owner, admin and accountant; accountants land there"
```

---

### Task 10: Finance reports in the owner export centre

**Track:** App. **Depends on:** Task 6.

**Files:**
- Modify: `lib/features/owner/owner_reports_screen.dart` (full replacement)
- Test: `test/features/owner/owner_reports_screen_test.dart` (new)

**Interfaces:**
- Consumes: `financeSourceProvider`, `csvDownloaderProvider` (Task 1); `collectionsCsv`, `ledgerCsv`, `settlementsCsv`, `financeCsvFileName` (Task 6); the existing `revenueReportProvider`, `occupancyReportProvider`, `foodSalesReportProvider`, `expensesReportProvider`.
- Produces: `/owner/reports` exports Collections, Ledger and Settlements (named `<slug>-<report>-<from>-<to>.csv`, with the resort header) next to its four existing reports. Every export goes through `csvDownloaderProvider`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/owner/owner_reports_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/finance_tables.dart';
import 'package:pasala/features/finance/providers.dart';
import 'package:pasala/features/owner/owner_reports_screen.dart';

import '../../support/fake_finance_source.dart';

const _ownerM =
    ResortMembership(propertyId: 'p1', resortName: 'Resort R', role: ResortRole.owner);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _ownerM;
}

/// The screen opens on this month; the file names follow it.
String _month() {
  final now = DateTime.now();
  return '${isoDate(DateTime(now.year, now.month, 1))}-'
      '${isoDate(DateTime(now.year, now.month + 1, 0))}';
}

Future<List<(String, String)>> _pump(WidgetTester tester, FakeFinanceSource source) async {
  final files = <(String, String)>[];
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      financeSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(_FixedResort.new),
      csvDownloaderProvider.overrideWithValue((name, csv) {
        files.add((name, csv));
        return true;
      }),
    ],
    child: const MaterialApp(home: OwnerReportsScreen()),
  ));
  await tester.pumpAndSettle();
  return files;
}

Future<void> _export(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, title), matching: find.byTooltip('Export CSV')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the finance reports next to the existing four', (tester) async {
    await _pump(tester, FakeFinanceSource());

    for (final title in [
      'Revenue',
      'Occupancy',
      'Food & activity sales',
      'Expenses',
      'Collections',
      'Ledger',
      'Settlements',
    ]) {
      expect(find.widgetWithText(ListTile, title), findsOneWidget, reason: title);
    }
  });

  testWidgets('Collections exports this month of the current resort with its header',
      (tester) async {
    final source = FakeFinanceSource()
      ..collectionRows = [
        collectionRow(day: DateTime(2026, 8, 5), source: CollectionSource.refund, amount: -1500),
      ];
    final files = await _pump(tester, source);

    await _export(tester, 'Collections');

    final (name, csv) = files.single;
    expect(name, 'fin-r-collections-${_month()}.csv');
    expect(csv, startsWith('Resort R,GSTIN 29ABCDE1234F1Z5\r\nPeriod,'));
    expect(csv, contains('2026-08-05,online,refund,gateway,1,-1500.00\r\n'));
    expect(source.collectionsCalls.single.propertyId, 'p1');
    expect(source.summaryCalls, ['p1']);
    expect(find.text('CSV exported.'), findsOneWidget);
  });

  testWidgets('Ledger and Settlements export under their own names', (tester) async {
    final source = FakeFinanceSource()
      ..ledgerRows = [ledgerRow(gross: 3000)]
      ..settlementRows = [settlementRow(room: 3000)];
    final files = await _pump(tester, source);

    await _export(tester, 'Ledger');
    await _export(tester, 'Settlements');

    expect(files.map((f) => f.$1), [
      'fin-r-ledger-${_month()}.csv',
      'fin-r-settlements-${_month()}.csv',
    ]);
    expect(files[0].$2, contains('Date,Category,Source,Gross,Discount,Taxable,Tax,Net\r\n'));
    expect(files[1].$2, contains('\r\nr1,Gita Guest,Cottage 1,'));
  });

  testWidgets('a failed finance export says why and writes nothing', (tester) async {
    final files =
        await _pump(tester, FakeFinanceSource()..collectionsError = const NetworkFailure());

    await _export(tester, 'Collections');

    expect(files, isEmpty);
    expect(find.text('Cannot reach the server. Check your connection.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/owner/owner_reports_screen_test.dart`
Expected: FAIL: `lists the finance reports …` cannot find `Collections`, and the export tests find no tile to tap.

- [ ] **Step 3: Rewrite the export centre**

Replace `lib/features/owner/owner_reports_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/finance_repository.dart';
import '../finance/finance_csv.dart';
import '../finance/providers.dart';
import '../reports/csv_export.dart';
import '../reports/providers.dart';
import 'providers.dart';

DateTimeRange _currentMonth() {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 0),
  );
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

enum _OwnerReportKind {
  revenue,
  occupancy,
  foodSales,
  expenses,
  collections,
  ledger,
  settlements,
}

/// `/owner/reports` -- the consolidated export center: Revenue, Occupancy,
/// Food & Activity Sales, Expenses, and the three finance reports
/// (Collections, Ledger, Settlements, from 0048_finance_ledger.sql), all
/// exportable as CSV through `csv_export.dart` and [csvDownloaderProvider].
/// Deliberately separate from `ReportsScreen` (which the Owner hub's
/// Revenue/Occupancy tiles link to directly for a live day-by-day view) and
/// from `/finance` (which shows the finance reports on screen) -- this
/// screen's job is bulk export across every report this app has.
class OwnerReportsScreen extends ConsumerStatefulWidget {
  const OwnerReportsScreen({super.key});

  @override
  ConsumerState<OwnerReportsScreen> createState() => _OwnerReportsScreenState();
}

class _OwnerReportsScreenState extends ConsumerState<OwnerReportsScreen> {
  DateTimeRange _range = _currentMonth();

  ReportFilter _reportFilter(String propertyId) =>
      (from: _range.start, to: _range.end, propertyId: propertyId);
  FoodSalesReportFilter _foodFilter(String propertyId) =>
      (from: _range.start, to: _range.end, propertyId: propertyId);
  ExpensesReportFilter _expensesFilter(String propertyId) =>
      (from: _range.start, to: _range.end, propertyId: propertyId);

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _deliver(String filename, List<List<String>> rows) {
    final delivered = ref.read(csvDownloaderProvider)(filename, toCsv(rows));
    _showMessage(
      delivered ? 'CSV exported.' : "CSV export isn't available on this platform yet.",
    );
  }

  Future<void> _export(_OwnerReportKind kind, String propertyId, String resortName) async {
    if (kind == _OwnerReportKind.collections ||
        kind == _OwnerReportKind.ledger ||
        kind == _OwnerReportKind.settlements) {
      return _exportFinance(kind, propertyId);
    }

    final List<List<String>> rows;
    final String label;

    switch (kind) {
      case _OwnerReportKind.revenue:
        final data =
            await ref.read(revenueReportProvider(_reportFilter(propertyId)).future);
        label = 'revenue';
        rows = [
          ['Day', 'Property', 'Bookings', 'Gross', 'Refunded', 'Net'],
          for (final r in data)
            [
              formatDate(r.day),
              resortName,
              '${r.bookings}',
              formatInr(r.gross),
              formatInr(r.refunded),
              formatInr(r.net),
            ],
        ];
      case _OwnerReportKind.occupancy:
        final data =
            await ref.read(occupancyReportProvider(_reportFilter(propertyId)).future);
        label = 'occupancy';
        rows = [
          ['Unit', 'Nights available', 'Nights booked', 'Occupancy %'],
          for (final r in data)
            [r.unitName, '${r.nightsAvailable}', '${r.nightsBooked}', '${r.occupancyPct}'],
        ];
      case _OwnerReportKind.foodSales:
        final data =
            await ref.read(foodSalesReportProvider(_foodFilter(propertyId)).future);
        label = 'food-activity-sales';
        rows = [
          ['Day', 'Category', 'Items sold', 'Gross'],
          for (final r in data)
            [formatDate(r.day), r.category.name, '${r.itemsSold}', formatInr(r.gross)],
        ];
      case _OwnerReportKind.expenses:
        final data =
            await ref.read(expensesReportProvider(_expensesFilter(propertyId)).future);
        label = 'expenses';
        rows = [
          ['Day', 'Category', 'Total'],
          for (final r in data) [formatDate(r.day), r.category, formatInr(r.total)],
        ];
      case _OwnerReportKind.collections:
      case _OwnerReportKind.ledger:
      case _OwnerReportKind.settlements:
        return;
    }

    if (!mounted) return;
    _deliver('pasala-$label-${_isoDate(_range.start)}-${_isoDate(_range.end)}.csv', rows);
  }

  /// The finance reports read [financeSourceProvider] directly -- a fresh
  /// query per export -- and take the resort's name, slug and GSTIN from
  /// `finance_summary` for the header and file name.
  Future<void> _exportFinance(_OwnerReportKind kind, String propertyId) async {
    final source = ref.read(financeSourceProvider);
    final from = _range.start;
    final to = _range.end;
    try {
      final resort = (await source.summary(propertyId)).resort;
      final (String report, List<List<String>> rows) = switch (kind) {
        _OwnerReportKind.collections => (
            'collections',
            collectionsCsv(resort, from, to, await source.collections(from, to, propertyId)),
          ),
        _OwnerReportKind.ledger => (
            'ledger',
            ledgerCsv(resort, from, to, await source.ledger(from, to, propertyId)),
          ),
        _ => (
            'settlements',
            settlementsCsv(resort, from, to, await source.settlements(from, to, propertyId)),
          ),
      };
      if (!mounted) return;
      _deliver(financeCsvFileName(resort.slug, report, from, to), rows);
    } on BookingFailure catch (e) {
      if (mounted) _showMessage(FailureView.messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final resort = ref.watch(currentResortProvider)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    void export(_OwnerReportKind kind) =>
        _export(kind, resort.propertyId, resort.resortName);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Text('DATE RANGE',
              style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  '${formatDate(_range.start)} – ${formatDate(_range.end)}',
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text('EXPORT AS CSV',
              style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: Spacing.sm),
          _ReportTile(
            icon: Icons.trending_up_outlined,
            title: 'Revenue',
            subtitle: 'Bookings, gross and net revenue by day',
            color: scheme.primary,
            onExport: () => export(_OwnerReportKind.revenue),
          ),
          _ReportTile(
            icon: Icons.pie_chart_outline,
            title: 'Occupancy',
            subtitle: 'Nights booked vs. available, by unit',
            color: scheme.tertiary,
            onExport: () => export(_OwnerReportKind.occupancy),
          ),
          _ReportTile(
            icon: Icons.restaurant_outlined,
            title: 'Food & activity sales',
            subtitle: 'Items sold and gross, by day and category',
            color: scheme.primary,
            onExport: () => export(_OwnerReportKind.foodSales),
          ),
          _ReportTile(
            icon: Icons.receipt_long_outlined,
            title: 'Expenses',
            subtitle: 'Totals by day and category',
            color: scheme.onSurfaceVariant,
            onExport: () => export(_OwnerReportKind.expenses),
          ),
          _ReportTile(
            icon: Icons.payments_outlined,
            title: 'Collections',
            subtitle: 'Money in and out by day, online and desk, by method',
            color: scheme.primary,
            onExport: () => export(_OwnerReportKind.collections),
          ),
          _ReportTile(
            icon: Icons.account_balance_outlined,
            title: 'Ledger',
            subtitle: 'Revenue by category with room tax',
            color: scheme.tertiary,
            onExport: () => export(_OwnerReportKind.ledger),
          ),
          _ReportTile(
            icon: Icons.fact_check_outlined,
            title: 'Settlements',
            subtitle: 'Checked-out bookings and how they were paid',
            color: scheme.onSurfaceVariant,
            onExport: () => export(_OwnerReportKind.settlements),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onExport,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
        trailing: IconButton(
          tooltip: 'Export CSV',
          icon: const Icon(Icons.download_outlined),
          onPressed: onExport,
        ),
      ),
    );
  }
}
```

The four existing reports keep their `pasala-<label>-…` file names; renaming them is out of scope (controller ruling).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/owner/ && flutter analyze`
Expected: all PASS. No new analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/owner/owner_reports_screen.dart test/features/owner/owner_reports_screen_test.dart
git commit -m "feat(finance): export Collections, Ledger and Settlements from the owner export centre"
```

---

### Task 11: Desk checkout at reception

**Track:** App. **Depends on:** Task 9 (both edit `lib/core/router.dart`).

**Files:**
- Modify: `lib/data/repositories/stay_repository.dart` (`checkout` gains `method`)
- Modify: `lib/features/stay/checkout_screen.dart` (full replacement)
- Modify: `lib/features/admin/reception_checkout_screen.dart`
- Modify: `lib/core/router.dart` (`/my-stay/checkout` builder)
- Test: `test/features/stay/checkout_screen_test.dart` (new), `test/features/admin/reception_checkout_screen_test.dart`

**Interfaces:**
- Consumes: `PaymentMethod` (Task 1), `invalidateFinance`, `financeSummaryProvider`, `financeSourceProvider`, `FakeFinanceSource` (Task 1); `paymentGatewayProvider`, `PaymentGateway`, `PaymentResult`, `currentChargesProvider`, `currentStayProvider`, `CurrentCharges`.
- Produces:
  - `StayRepository.checkout({required String reservationId, String? paymentRef, required num amount, PaymentMethod method = PaymentMethod.gateway})`, sending `p_method: method.wire`.
  - `class DeskCheckoutArgs { const DeskCheckoutArgs(String reservationId); final String reservationId; }` and `Widget checkoutScreenFor(Object? extra)` in `checkout_screen.dart`; `CheckoutScreen({required String reservationId, bool desk = false})`.
  - Keys `desk-method-<wire>` (one `ChoiceChip` per `PaymentMethod.desk`), `desk-reference`.
  - Reception's Check Out pushes `/my-stay/checkout` with `extra: DeskCheckoutArgs(id)`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/stay/checkout_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/booking/payment_gateway.dart';
import 'package:pasala/features/finance/providers.dart';
import 'package:pasala/features/stay/checkout_screen.dart';

import '../../support/fake_finance_source.dart';

typedef _Checkout = ({
  String reservationId,
  String? paymentRef,
  num amount,
  PaymentMethod method,
});

/// Only [checkout] is reached from this screen.
class _FakeStayRepository implements StayRepository {
  final checkouts = <_Checkout>[];
  Object? checkoutError;

  @override
  Future<Reservation> checkout({
    required String reservationId,
    String? paymentRef,
    required num amount,
    PaymentMethod method = PaymentMethod.gateway,
  }) async {
    checkouts.add((
      reservationId: reservationId,
      paymentRef: paymentRef,
      amount: amount,
      method: method,
    ));
    if (checkoutError != null) throw checkoutError!;
    return Reservation(
      id: reservationId,
      unitId: 'u1',
      start: DateTime(2026, 9, 24),
      end: DateTime(2026, 9, 26),
      kind: ReservationKind.booking,
      status: ReservationStatus.checkedOut,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGateway implements PaymentGateway {
  final charges = <num>[];

  @override
  Future<PaymentResult> charge({required String reservationId, required num amount}) async {
    charges.add(amount);
    return PaymentResult.success('mock_$reservationId');
  }
}

CurrentCharges _charges(double balance) => CurrentCharges(
      stayAmount: 3000,
      foodAmount: 0,
      activityAmount: 0,
      total: 3000,
      paid: 3000 - balance,
      balance: balance,
    );

Future<void> _pump(
  WidgetTester tester, {
  required Object extra,
  required _FakeStayRepository stay,
  _FakeGateway? gateway,
  double balance = 2000,
  FakeFinanceSource? finance,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/my-stay/checkout',
    initialExtra: extra,
    routes: [
      GoRoute(path: '/my-stay/checkout', builder: (_, state) => checkoutScreenFor(state.extra)),
      GoRoute(
          path: '/my-stay/invoice/:id',
          builder: (_, state) => Text('INVOICE ${state.pathParameters['id']}')),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      stayRepositoryProvider.overrideWithValue(stay),
      currentChargesProvider.overrideWith((ref, id) async => _charges(balance)),
      paymentGatewayProvider.overrideWithValue(gateway ?? _FakeGateway()),
      financeSourceProvider.overrideWithValue(finance ?? FakeFinanceSource()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      // Stands in for an open Finance screen, which keeps its summary alive.
      builder: (context, child) => Stack(children: [
        child!,
        Consumer(builder: (_, ref, _) {
          ref.watch(financeSummaryProvider('p1'));
          return const SizedBox.shrink();
        }),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('desk checkout', () {
    testWidgets('offers the five desk methods, Cash selected, and a reference field',
        (tester) async {
      await _pump(tester, extra: const DeskCheckoutArgs('r1'), stay: _FakeStayRepository());

      for (final m in PaymentMethod.desk) {
        expect(find.byKey(Key('desk-method-${m.wire}')), findsOneWidget, reason: m.label);
      }
      expect(find.byKey(const Key('desk-method-gateway')), findsNothing);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('desk-method-cash'))).selected, isTrue);
      expect(find.byKey(const Key('desk-reference')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'), findsOneWidget);
    });

    testWidgets('records the chosen method and the trimmed reference, and never calls the gateway',
        (tester) async {
      final stay = _FakeStayRepository();
      final gateway = _FakeGateway();
      await _pump(tester, extra: const DeskCheckoutArgs('r1'), stay: stay, gateway: gateway);

      await tester.tap(find.byKey(const Key('desk-method-upi')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('desk-reference')), '  UTR123  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(stay.checkouts, [
        (reservationId: 'r1', paymentRef: 'UTR123', amount: 2000, method: PaymentMethod.upi),
      ]);
      expect(gateway.charges, isEmpty);
      expect(find.text('INVOICE r1'), findsOneWidget);
    });

    testWidgets('a blank reference is sent as none', (tester) async {
      final stay = _FakeStayRepository();
      await _pump(tester, extra: const DeskCheckoutArgs('r1'), stay: stay);

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(stay.checkouts.single.paymentRef, isNull);
      expect(stay.checkouts.single.method, PaymentMethod.cash);
    });

    testWidgets('the reference stops at 64 characters', (tester) async {
      await _pump(tester, extra: const DeskCheckoutArgs('r1'), stay: _FakeStayRepository());

      await tester.enterText(find.byKey(const Key('desk-reference')), 'x' * 70);
      await tester.pump();

      final field = tester.widget<TextField>(find.byKey(const Key('desk-reference')));
      expect(field.controller!.text, hasLength(64));
    });

    // Review Focus 4.
    testWidgets('with nothing left to pay there is no method to pick', (tester) async {
      final stay = _FakeStayRepository();
      await _pump(tester, extra: const DeskCheckoutArgs('r1'), stay: stay, balance: 0);

      expect(find.byKey(const Key('desk-method-cash')), findsNothing);
      expect(find.byKey(const Key('desk-reference')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Check out'));
      await tester.pumpAndSettle();

      expect(stay.checkouts, [
        (reservationId: 'r1', paymentRef: null, amount: 0, method: PaymentMethod.gateway),
      ]);
    });

    testWidgets('a refusal is shown and the screen stays', (tester) async {
      final stay = _FakeStayRepository()
        ..checkoutError = const InvalidState('desk payment methods are recorded by resort staff');
      await _pump(tester, extra: const DeskCheckoutArgs('r1'), stay: stay);

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(find.text('desk payment methods are recorded by resort staff'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'), findsOneWidget);
    });

    testWidgets('a desk checkout refetches the finance figures', (tester) async {
      final finance = FakeFinanceSource();
      await _pump(tester,
          extra: const DeskCheckoutArgs('r1'), stay: _FakeStayRepository(), finance: finance);
      final before = finance.summaryCalls.length;

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(finance.summaryCalls.length, greaterThan(before));
    });
  });

  group('guest checkout', () {
    testWidgets('is unchanged: no methods, and the gateway takes the balance', (tester) async {
      final stay = _FakeStayRepository();
      final gateway = _FakeGateway();
      await _pump(tester, extra: 'r1', stay: stay, gateway: gateway);

      expect(find.byKey(const Key('desk-method-cash')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Pay ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(gateway.charges, [2000]);
      expect(stay.checkouts, [
        (reservationId: 'r1', paymentRef: 'mock_r1', amount: 2000, method: PaymentMethod.gateway),
      ]);
      expect(find.text('INVOICE r1'), findsOneWidget);
    });

    testWidgets('with nothing to pay it sends no-balance-due', (tester) async {
      final stay = _FakeStayRepository();
      await _pump(tester, extra: 'r1', stay: stay, balance: 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Check out'));
      await tester.pumpAndSettle();

      expect(stay.checkouts.single.paymentRef, 'no-balance-due');
      expect(stay.checkouts.single.method, PaymentMethod.gateway);
    });
  });

  group('checkoutScreenFor', () {
    test("a reservation id is the guest's own checkout", () {
      final screen = checkoutScreenFor('r1') as CheckoutScreen;
      expect(screen.reservationId, 'r1');
      expect(screen.desk, isFalse);
    });

    test('DeskCheckoutArgs is the desk checkout', () {
      final screen = checkoutScreenFor(const DeskCheckoutArgs('r1')) as CheckoutScreen;
      expect(screen.reservationId, 'r1');
      expect(screen.desk, isTrue);
    });

    test('anything else is refused', () {
      expect(() => checkoutScreenFor(null), throwsArgumentError);
    });
  });
}
```

In `test/features/admin/reception_checkout_screen_test.dart`, add the import:

```dart
import 'package:pasala/features/stay/checkout_screen.dart';
```

Then append inside `main()`:

```dart
  testWidgets('Check Out opens the desk checkout for that booking', (tester) async {
    Object? extra;
    final router = GoRouter(
      initialLocation: '/admin/check-out',
      routes: [
        GoRoute(
            path: '/admin/check-out',
            builder: (_, _) => const ReceptionCheckoutScreen()),
        GoRoute(
            path: '/my-stay/checkout',
            builder: (_, state) {
              extra = state.extra;
              return const Text('CHECKOUT SCREEN');
            }),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        checkedInProvider.overrideWith(
            (ref, propertyId) async => [_checkedIn('r1', customerName: 'Ravi Kumar')]),
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Check Out'));
    await tester.pumpAndSettle();

    expect(extra, isA<DeskCheckoutArgs>().having((a) => a.reservationId, 'reservationId', 'r1'));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/stay/checkout_screen_test.dart test/features/admin/reception_checkout_screen_test.dart`
Expected: FAIL to compile with "Undefined name 'checkoutScreenFor'" / "The method 'DeskCheckoutArgs' isn't defined", and `_FakeStayRepository.checkout` not matching `StayRepository.checkout`.

- [ ] **Step 3: Send the method from `StayRepository.checkout`**

In `lib/data/repositories/stay_repository.dart`, add the import:

```dart
import '../models/payment_method.dart';
```

Replace:

```dart
  Future<Reservation> checkout({
    required String reservationId,
    required String paymentRef,
    required num amount,
  }) =>
      _guard(() async {
        final row = await _db.rpc('checkout_booking', params: {
          'p_reservation_id': reservationId,
          'p_payment_ref': paymentRef,
          'p_amount': amount,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });
```

with:

```dart
  /// Settles the balance and checks out. [method] is how the balance was
  /// taken: [PaymentMethod.gateway] for a guest's own online payment (with
  /// the gateway's reference in [paymentRef]), or a desk method recorded by
  /// resort staff (with an optional receipt/UTR number in [paymentRef]).
  /// A guest passing a desk method gets P0009 from `checkout_booking`.
  Future<Reservation> checkout({
    required String reservationId,
    String? paymentRef,
    required num amount,
    PaymentMethod method = PaymentMethod.gateway,
  }) =>
      _guard(() async {
        final row = await _db.rpc('checkout_booking', params: {
          'p_reservation_id': reservationId,
          'p_payment_ref': paymentRef,
          'p_amount': amount,
          'p_method': method.wire,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });
```

- [ ] **Step 4: Rewrite the checkout screen**

Replace `lib/features/stay/checkout_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/payment_method.dart';
import '../../data/repositories/stay_repository.dart';
import '../booking/payment_gateway.dart';
import '../finance/providers.dart';

/// The `extra` reception passes to `/my-stay/checkout` to settle a guest's
/// bill at the desk. A guest's own checkout passes the plain reservation id.
class DeskCheckoutArgs {
  const DeskCheckoutArgs(this.reservationId);

  final String reservationId;
}

/// Builds `/my-stay/checkout` from its route `extra`: a reservation id is
/// the guest's own checkout, [DeskCheckoutArgs] is reception's.
Widget checkoutScreenFor(Object? extra) => switch (extra) {
      DeskCheckoutArgs(:final reservationId) =>
        CheckoutScreen(reservationId: reservationId, desk: true),
      final String reservationId => CheckoutScreen(reservationId: reservationId),
      _ => throw ArgumentError.value(extra, 'extra', 'checkout needs a reservation id'),
    };

/// The final bill. A guest settles it through the same mock
/// [PaymentGateway] seam `booking_screen.dart`'s own `_pay` uses. At the
/// desk ([desk]) reception records how the guest paid -- the method and an
/// optional receipt or UTR number -- and the gateway is never called.
/// `checkout_booking` never trusts a client-supplied amount, and refuses a
/// desk method from anyone who is not staff at the booking's resort.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.reservationId, this.desk = false});

  final String reservationId;

  /// Reception's desk checkout rather than the guest's own.
  final bool desk;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _busy = false;
  PaymentMethod _method = PaymentMethod.cash;
  final _reference = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _checkout(double balance) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final stay = ref.read(stayRepositoryProvider);
      if (widget.desk) {
        final reference = _reference.text.trim();
        await stay.checkout(
          reservationId: widget.reservationId,
          paymentRef: balance > 0 && reference.isNotEmpty ? reference : null,
          amount: balance,
          // Nothing due writes no payment, so there is no method to record.
          method: balance > 0 ? _method : PaymentMethod.gateway,
        );
      } else {
        String? paymentRef;
        if (balance > 0) {
          final payment = await ref
              .read(paymentGatewayProvider)
              .charge(reservationId: widget.reservationId, amount: balance);
          if (!payment.succeeded) {
            throw InvalidState(payment.failureMessage ?? 'Payment failed');
          }
          paymentRef = payment.reference;
        }
        await stay.checkout(
          reservationId: widget.reservationId,
          paymentRef: paymentRef ?? 'no-balance-due',
          amount: balance,
        );
      }
      if (!mounted) return;
      ref.invalidate(currentStayProvider);
      // The final invoice re-reads current_charges for this exact
      // reservation id -- without invalidating it here, it would show the
      // cached pre-payment figures (paid ₹0, balance still due) instead of
      // the balance payment `checkout_booking` just recorded.
      ref.invalidate(currentChargesProvider(widget.reservationId));
      // Collections, settlements and today's figures include this payment.
      invalidateFinance(ref);
      context.go('/my-stay/invoice/${widget.reservationId}');
    } on BookingFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _buttonLabel(double balance) {
    if (_busy) return 'Processing…';
    if (balance <= 0) return 'Check out';
    return widget.desk
        ? 'Record ${formatInr(balance)} and check out'
        : 'Pay ${formatInr(balance)} and check out';
  }

  Widget _deskPayment(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Payment method', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final m in PaymentMethod.desk)
                    ChoiceChip(
                      key: Key('desk-method-${m.wire}'),
                      avatar: Icon(m.icon, size: 18),
                      label: Text(m.label),
                      selected: _method == m,
                      onSelected: _busy ? null : (_) => setState(() => _method = m),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: const Key('desk-reference'),
                controller: _reference,
                enabled: !_busy,
                maxLength: 64,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                  helperText: 'Receipt, card slip or UTR number',
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final chargesAsync = ref.watch(currentChargesProvider(widget.reservationId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: AsyncView(
        value: chargesAsync,
        onRetry: () => ref.invalidate(currentChargesProvider(widget.reservationId)),
        data: (charges) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Final bill', style: textTheme.titleMedium),
                    const SizedBox(height: Spacing.md),
                    Row(children: [
                      const Expanded(child: Text('Total charges')),
                      Text(formatInr(charges.total)),
                    ]),
                    const SizedBox(height: Spacing.xs),
                    Row(children: [
                      const Expanded(child: Text('Paid so far')),
                      Text(formatInr(charges.paid)),
                    ]),
                    const Divider(),
                    Row(children: [
                      Expanded(child: Text('Balance to pay', style: textTheme.titleLarge)),
                      Text(
                        formatInr(charges.balance),
                        style: textTheme.titleLarge?.copyWith(color: scheme.primary),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            if (widget.desk && charges.balance > 0) ...[
              const SizedBox(height: Spacing.md),
              _deskPayment(context),
            ],
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _busy ? null : () => _checkout(charges.balance),
              child: Text(_buttonLabel(charges.balance)),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Open the desk checkout from reception**

In `lib/features/admin/reception_checkout_screen.dart`, add after `import '../staff/providers.dart' show allBookingsProvider;`:

```dart
import '../stay/checkout_screen.dart' show DeskCheckoutArgs;
```

Replace:

```dart
                    await context.push('/my-stay/checkout', extra: g.id);
```

with:

```dart
                    // Desk checkout: reception records the method and
                    // reference instead of charging the guest's gateway.
                    await context.push('/my-stay/checkout',
                        extra: DeskCheckoutArgs(g.id));
```

In `lib/core/router.dart`, replace:

```dart
              CheckoutScreen(reservationId: state.extra! as String),
```

with:

```dart
              checkoutScreenFor(state.extra),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/stay/ test/features/admin/reception_checkout_screen_test.dart test/core/router_test.dart && flutter analyze`
Expected: all PASS, including B's `returning from checkout refetches the room board`. No new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add lib/data/repositories/stay_repository.dart lib/features/stay/checkout_screen.dart \
  lib/features/admin/reception_checkout_screen.dart lib/core/router.dart \
  test/features/stay/checkout_screen_test.dart test/features/admin/reception_checkout_screen_test.dart
git commit -m "feat(finance): desk checkout records the payment method and reference"
```

---

### Task 12: The walk-in sale records its payment method

**Track:** App. **Depends on:** Task 1.

**Files:**
- Modify: `lib/data/models/food_sale.dart`
- Modify: `lib/features/owner/food_sales_screen.dart`
- Test: `test/data/food_sale_test.dart` (new), `test/features/owner/food_sales_screen_test.dart`

**Interfaces:**
- Consumes: `PaymentMethod` (Task 1), `invalidateFinance`, `financeSummaryProvider`, `financeSourceProvider`, `FakeFinanceSource` (Task 1).
- Produces: `FoodSale.paymentMethod` is a `PaymentMethod` (default `PaymentMethod.cash`), parsed with `PaymentMethod.fromWire` and written as its wire value. The sale form has a `Payment method` dropdown (key `sale-form-method`) offering `PaymentMethod.desk` only; the list shows each sale's method. Saving or deleting a sale invalidates the finance providers.

- [ ] **Step 1: Write the failing tests**

Create `test/data/food_sale_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/food_sale.dart';
import 'package:pasala/data/models/payment_method.dart';

Map<String, dynamic> _row(Object? method) => {
      'id': 's1',
      'property_id': 'p1',
      'sale_date': '2026-08-10',
      'category': 'food',
      'item_name': 'Thali',
      'quantity': 2,
      'unit_price': 250,
      'amount': 500,
      'payment_method': method,
      'notes': null,
    };

void main() {
  test('reads the payment method from its wire value', () {
    expect(FoodSale.fromJson(_row('upi')).paymentMethod, PaymentMethod.upi);
    expect(FoodSale.fromJson(_row('bank_transfer')).paymentMethod, PaymentMethod.bankTransfer);
  });

  test('a missing or unknown method reads as Other', () {
    expect(FoodSale.fromJson(_row(null)).paymentMethod, PaymentMethod.other);
    expect(FoodSale.fromJson(_row('cheque')).paymentMethod, PaymentMethod.other);
  });

  test('a new sale defaults to Cash and is written as its wire value', () {
    final sale = FoodSale(
      id: '',
      propertyId: 'p1',
      saleDate: DateTime(2026, 8, 10),
      category: SaleCategory.food,
      itemName: 'Tea',
      quantity: 1,
      unitPrice: 50,
      amount: 50,
    );

    expect(sale.paymentMethod, PaymentMethod.cash);
    expect(sale.toInsert()['payment_method'], 'cash');
  });
}
```

In `test/features/owner/food_sales_screen_test.dart`, add these imports:

```dart
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/providers.dart';

import '../../support/fake_finance_source.dart';
```

Replace the `_appFor` function with:

```dart
Widget _appFor(
  FakeFoodSaleRepository repo, {
  AppUser user = _admin,
  ResortMembership? resort,
  FakeFinanceSource? finance,
}) =>
    ProviderScope(
      overrides: [
        foodSaleRepositoryProvider.overrideWithValue(repo),
        currentResortProvider.overrideWith(
            () => _FixedResort(resort ?? user.memberships.first)),
        financeSourceProvider.overrideWithValue(finance ?? FakeFinanceSource()),
      ],
      child: MaterialApp(
        home: const FoodSalesScreen(),
        // Stands in for an open Finance screen, which keeps its summary alive.
        builder: (context, child) => Stack(children: [
          child!,
          Consumer(builder: (_, ref, _) {
            ref.watch(financeSummaryProvider('p1'));
            return const SizedBox.shrink();
          }),
        ]),
      ),
    );
```

Add this helper after `_appFor`:

```dart
Future<void> _fillNewSale(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('sale-form-item-name')), 'Breakfast platter');
  await tester.enterText(find.byKey(const Key('sale-form-quantity')), '2');
  await tester.enterText(find.byKey(const Key('sale-form-unit-price')), '300');
}
```

Then append inside `main()`:

```dart
  group('payment method', () {
    testWidgets('a new sale is Cash unless another method is picked', (tester) async {
      final repo = FakeFoodSaleRepository();
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await _fillNewSale(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.store.single.paymentMethod, PaymentMethod.cash);
    });

    testWidgets('the form records the method picked', (tester) async {
      final repo = FakeFoodSaleRepository();
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await _fillNewSale(tester);
      await tester.tap(find.byKey(const Key('sale-form-method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.store.single.paymentMethod, PaymentMethod.upi);
    });

    testWidgets('the method list offers the five desk methods and never Online',
        (tester) async {
      await tester.pumpWidget(_appFor(FakeFoodSaleRepository()));
      await tester.pumpAndSettle();

      await _fillNewSale(tester);
      await tester.tap(find.byKey(const Key('sale-form-method')));
      await tester.pumpAndSettle();

      for (final m in PaymentMethod.desk) {
        expect(find.text(m.label), findsWidgets, reason: m.label);
      }
      expect(find.text('Online'), findsNothing);
    });

    testWidgets('each sale shows its method in the list', (tester) async {
      final repo = FakeFoodSaleRepository()
        ..store.add(FoodSale(
          id: 's1',
          propertyId: 'p1',
          saleDate: DateTime.now(),
          category: SaleCategory.activity,
          itemName: 'Pool pass',
          quantity: 1,
          unitPrice: 300,
          amount: 300,
          paymentMethod: PaymentMethod.upi,
        ));
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('Activity · UPI · '), findsOneWidget);
    });

    // Review Focus 3.
    testWidgets('editing a sale keeps its payment method', (tester) async {
      final repo = FakeFoodSaleRepository()
        ..store.add(FoodSale(
          id: 's1',
          propertyId: 'p1',
          saleDate: DateTime.now(),
          category: SaleCategory.food,
          itemName: 'Breakfast platter',
          quantity: 2,
          unitPrice: 300,
          amount: 600,
          paymentMethod: PaymentMethod.bankTransfer,
        ));
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('sale-form-quantity')), '3');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.store.single.quantity, 3);
      expect(repo.store.single.paymentMethod, PaymentMethod.bankTransfer);
    });

    testWidgets('saving a sale refetches the finance figures', (tester) async {
      final finance = FakeFinanceSource();
      await tester.pumpWidget(_appFor(FakeFoodSaleRepository(), finance: finance));
      await tester.pumpAndSettle();
      final before = finance.summaryCalls.length;

      await _fillNewSale(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(finance.summaryCalls.length, greaterThan(before));
    });
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/food_sale_test.dart test/features/owner/food_sales_screen_test.dart`
Expected: FAIL to compile with "The argument type 'PaymentMethod' can't be assigned to the parameter type 'String?'" (the fake and the new tests pass a `PaymentMethod`).

- [ ] **Step 3: Type the model's method**

In `lib/data/models/food_sale.dart`, add at the top:

```dart
import 'payment_method.dart';
```

Replace:

```dart
    this.paymentMethod,
    this.notes,
  });
```

with:

```dart
    this.paymentMethod = PaymentMethod.cash,
    this.notes,
  });
```

Replace:

```dart
  final String? paymentMethod;
```

with:

```dart
  /// How the guest paid at the desk. Never [PaymentMethod.gateway]:
  /// `food_activity_sales_not_gateway` (0048) refuses it, and the form
  /// offers [PaymentMethod.desk] only.
  final PaymentMethod paymentMethod;
```

Replace:

```dart
        paymentMethod: json['payment_method'] as String?,
```

with:

```dart
        paymentMethod: PaymentMethod.fromWire(json['payment_method'] as String?),
```

Replace:

```dart
        'payment_method': paymentMethod,
```

with:

```dart
        'payment_method': paymentMethod.wire,
```

- [ ] **Step 4: Add the method to the form and the list**

In `lib/features/owner/food_sales_screen.dart`, add the imports:

```dart
import '../../data/models/payment_method.dart';
import '../finance/providers.dart';
```

Replace:

```dart
                            '${_categoryLabel(sale.category)} · '
                            '${formatDate(sale.saleDate)} · '
```

with:

```dart
                            '${_categoryLabel(sale.category)} · '
                            '${sale.paymentMethod.label} · '
                            '${formatDate(sale.saleDate)} · '
```

Replace:

```dart
      ref.invalidate(foodSalesProvider(filter));
```

with:

```dart
      ref.invalidate(foodSalesProvider(filter));
      invalidateFinance(ref);
```

Replace:

```dart
  late SaleCategory _category;
```

with:

```dart
  late SaleCategory _category;
  late PaymentMethod _method;
```

Replace:

```dart
    _category = existing?.category ?? SaleCategory.food;
```

with:

```dart
    _category = existing?.category ?? SaleCategory.food;
    // An edit keeps the method the sale already has (Review Focus 3).
    _method = existing?.paymentMethod ?? PaymentMethod.cash;
```

Replace:

```dart
        amount: unitPrice * quantity,
```

with:

```dart
        amount: unitPrice * quantity,
        paymentMethod: _method,
```

Replace:

```dart
      ref.invalidate(foodSalesProvider);
```

with:

```dart
      ref.invalidate(foodSalesProvider);
      invalidateFinance(ref);
```

Replace the category dropdown:

```dart
                        DropdownButtonFormField<SaleCategory>(
                          key: const Key('sale-form-category'),
                          initialValue: _category,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: [
                            for (final c in SaleCategory.values)
                              DropdownMenuItem(value: c, child: Text(_categoryLabel(c))),
                          ],
                          onChanged: (value) =>
                              setState(() => _category = value ?? SaleCategory.food),
                        ),
```

with the category and the method side by side (one row, so the form keeps its height and Save stays on screen):

```dart
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<SaleCategory>(
                                key: const Key('sale-form-category'),
                                initialValue: _category,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Category'),
                                items: [
                                  for (final c in SaleCategory.values)
                                    DropdownMenuItem(value: c, child: Text(_categoryLabel(c))),
                                ],
                                onChanged: (value) =>
                                    setState(() => _category = value ?? SaleCategory.food),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: DropdownButtonFormField<PaymentMethod>(
                                key: const Key('sale-form-method'),
                                initialValue: _method,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Payment method'),
                                items: [
                                  for (final m in PaymentMethod.desk)
                                    DropdownMenuItem(value: m, child: Text(m.label)),
                                ],
                                onChanged: (value) =>
                                    setState(() => _method = value ?? PaymentMethod.cash),
                              ),
                            ),
                          ],
                        ),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/data/food_sale_test.dart test/features/owner/food_sales_screen_test.dart && flutter analyze`
Expected: all PASS, including the file's existing tests. No new analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/food_sale.dart lib/features/owner/food_sales_screen.dart \
  test/data/food_sale_test.dart test/features/owner/food_sales_screen_test.dart
git commit -m "feat(finance): walk-in sales record a desk payment method"
```

---

## Phase 3: Integration

### Task 13: Merge the tracks and verify end to end

**Track:** both. **Depends on:** Tasks 2–12.

**Files:**
- None created. This task only verifies; a fix belongs to the task that owns the file, and gets its own commit.

**Interfaces:**
- Consumes: everything above.
- Produces: a branch where the database and the app agree on names and shapes, with both suites green.

- [ ] **Step 1: Merge**

If the tracks ran in separate worktrees, merge the database branch and the app branch into this plan's branch. The tracks own disjoint files, so no conflicts are expected. If one appears, keep both sides' additions.

- [ ] **Step 2: Check the contract by name**

Run: `grep -n "rpc('\|'p_" lib/data/repositories/finance_repository.dart lib/data/repositories/stay_repository.dart`
Expected: the RPC names `finance_summary`, `report_collections`, `report_ledger`, `report_settlements` and `checkout_booking`, with the parameters `p_property_id`, `p_from`, `p_to`, `p_reservation_id`, `p_payment_ref`, `p_amount` and `p_method`. Each must match a signature in 0048, listed by `grep -n "create function public\.\(report_collections\|report_ledger\|report_settlements\|finance_summary\|checkout_booking\)" -A5 supabase/migrations/0048_finance_ledger.sql`.

Run: `grep -n "json\['" lib/data/models/finance.dart | sed "s/.*json\['\([a-z_]*\)'\].*/\1/" | sort -u`
Expected: every key is one of the OUT columns pinned in 40's contract section or a `finance_summary` key (`resort`, `name`, `slug`, `gstin`, `tax_pct`, `timezone`, `today`, `online_collected`, `desk_collected`, `total`, `refunds`, `net_collected`, `room_tax`, `in_house_count`, `in_house_balance`).

- [ ] **Step 3: Run the full suites**

Run: `supabase db reset && supabase test db`, then `flutter test`, then `flutter analyze`
Expected:
- pgTAP: 40 at 91/91, 37 with the allow-list guard passing, and every other file as in the Task 1 Step 1 baseline.
- Flutter: all tests pass, with the count equal to the baseline plus the tests this plan added.
- Analyzer: no issues beyond the baseline.

- [ ] **Step 4: Manual smoke test against the local stack**

Run: `make run-web`, then:
1. Sign in as a seeded accountant. You land on Finance, and the bar reads Finance, Rooms, Dashboard, Reports.
2. Today shows the resort's date; Collections, Ledger and Settlements load for this month; Export CSV downloads `<slug>-collections-<from>-<to>.csv`, which opens with the resort name and GSTIN (or `GSTIN not set`) and the period.
3. Sign in as a staff member of the same resort: `/finance` shows the not-found page, and `/admin/reports` still works.
4. As staff, open Check-Out, check a guest out with UPI and a reference. The button reads `Record ₹<balance> and check out`, and no payment gateway runs.
5. As the accountant, pull to refresh: Today's desk UPI figure and Collections' UPI column include that payment, and Settlements shows the booking with `UPI · <reference>`.
6. As staff, log a walk-in sale by card. Collections shows it under front desk, card, and the Ledger under F&B or Spa/Activities.
7. As the owner, open the owner hub: the Finance tile opens Finance, and Reports exports Collections, Ledger and Settlements.

- [ ] **Step 5: Commit any fixes**

For each fix, run `git add <the fixed files>` and then `git commit -m "fix(finance): <what was wrong>"`. If nothing needed fixing, there is nothing to commit.

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Enum `payment_method`; `payments.method` (default gateway, backfill), `reference` (≤ 64), `recorded_by`; index `(property_id, created_at)` | 1 |
| `food_activity_sales.payment_method` enum, default cash, not gateway, legacy text mapping | 1 |
| `expenses.payment_method` left alone; no new tables or triggers | 1 (nothing added) |
| `checkout_booking` gains `p_method`: drop/recreate/re-grant, body from 0047, coalesce, P0009 for non-staff, desk row shape, gateway row, retry, amount check, zero balance, room dirty | 1 (signature), 2 |
| Report functions: required `p_property_id`, owner/admin/accountant, resort timezone, succeeded only, rounded, `stable` | 1 (signatures), 3–5 |
| `report_collections`: channels, sources, refunds capped and dated by `cancelled_at`, zero refunds left out | 3 |
| `report_ledger`: room/booking, cleaning split, total-only quote, cancellation fee, F&B, Spa/Activities, cancelled excluded | 4 |
| `report_settlements`: every column, total as `current_charges`, outstanding | 5 |
| `finance_summary`: resort block, online, desk by method, refunds, net, room tax, in-house count and balance (set-based) | 5 |
| Allow-list in 37 | 1 |
| Rules: staff denied, guests never desk, walk-ins never gateway, no policy widened, suspended readable / archived closed, checkout P0022 | 2, 5, 1 |
| `PaymentMethod` enum, `desk`, unknown → other | 1 |
| `CollectionRow`, `LedgerRow`, `SettlementRow`, `FinanceSummary` with `fromJson` | 1 |
| `FinanceRepository` (4 calls, `yyyy-MM-dd`, `_guard`), providers keyed by property id / `ReportFilter` | 1 |
| `finance_csv.dart`: header lines, GSTIN fallback, file name | 6 |
| `/finance` screen: current resort, range (default this month), four tabs, pull-to-refresh, Export CSV with the "not available" message, tables vs cards, totals rows, tax strip, outstanding with icon and text, `AsyncView` states | 7, 8 |
| Navigation: `/finance` in the shell, `redirectFor` (choose-resort, roles, 404), accountant landing, accountant bar, owner tile, admin More entry | 9 |
| `/owner/reports` adds Collections, Ledger, Settlements | 10 |
| Desk checkout: `StayRepository.checkout` method + nullable ref, `CheckoutScreen.desk`, `DeskCheckoutArgs`, chips/reference/button, no gateway, finance invalidated | 11 |
| Walk-in sales: method on the form (desk only, default cash) and in the list; finance invalidated | 12 |
| pgTAP list in the spec's Testing section | 1–5 |
| Flutter list in the spec's Testing section | 1, 6–12 |

**2. Placeholder scan:** no "TBD", "TODO" or "similar to Task N". Every code step shows its code; every SQL test uses literal ids and worked figures. The one conditional instruction (copy `checkout_booking` from the merged 0047 if it differs) names the command to print it and the exact lines to keep.

**3. Type consistency:**
- `FinanceSource.collections/ledger/settlements(DateTime from, DateTime to, String propertyId)` is the same in the repository, the fake, the providers and the export centre; the fake logs `ReportFilter` records built from those three arguments.
- `financeSummaryProvider` is `autoDispose.family<FinanceSummary, String>` and the three report providers `autoDispose.family<List<…>, ReportFilter>` in every override and watcher.
- `StayRepository.checkout({required String reservationId, String? paymentRef, required num amount, PaymentMethod method})` matches the fake in `checkout_screen_test.dart`; the existing `_FakeStayRepository` in B's reception check-in test uses `noSuchMethod` for it.
- The OUT columns pinned in 40's contract section match the `fromJson` keys; `desk_collected` keys are `PaymentMethod.wire` values.
- Keys used in tests (`finance-export`, `finance-range`, `today-*`, `collections-*`, `ledger-*`, `settlement-*`, `outstanding-*`, `desk-method-*`, `desk-reference`, `sale-form-method`) are the ones the widgets set.

**4. Review Focus:** each of the five lines has a test in its owning task: 1 in Task 2, 2 in Task 2, 3 in Task 12, 4 in Tasks 2 and 11, 5 in Task 7. Inputs the spec implies that are covered elsewhere:
- A reference longer than 64 characters: Task 1 (the table refuses it) and Task 11 (the field stops at 64).
- A blank or whitespace-only reference: Tasks 2 and 11.
- Payments either side of resort midnight: Task 3.
- A coupon larger than the subtotal, and a total-only quote: Task 4.
- A null resort id, another resort's accountant, plain staff, anon: Task 5.
