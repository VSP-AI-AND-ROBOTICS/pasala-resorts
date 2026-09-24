# Finance Ledger and Collections (REQ-07) — Design

## Why

The client's requirement REQ-07 (`docs/requirements/ResortHub_Requirements_For_Manager.pdf`)
asks for a live view of advance payments taken online versus cash and card
taken at the front desk, daily revenue and tax summaries, revenue sorted
automatically into Room, Food & Beverage, Spa and Ancillary ledgers, and
exportable reports. The accountant "audits split payments" and "exports tax
and P&L reports".

Today the money is recorded, but not in a form an accountant can use:
- `payments` (`0006_payments_audit.sql`, `property_id` from 0043) has `kind`
  (`advance`/`balance`), `status`, `gateway` and `gateway_ref`, but no payment
  method and no record of who took the payment. Every row is `gateway = 'mock'`.
- `checkout_booking` (0045) writes one `balance` row for room, food and
  activities together, always `'mock'`. Reception checkout
  (`reception_checkout_screen.dart`) pushes the guest's own `CheckoutScreen`,
  which charges the mock `PaymentGateway`, so desk cash is indistinguishable
  from an online payment.
- `cancel_booking` sets `reservations.refund_pct`/`refund_amount` only. No
  money movement is recorded. `compute_refund` works the refund out on the
  quote **total**, not on what was paid, so a cancelled unpaid hold or a
  part-paid booking carries a refund larger than the money received.
- Walk-in sales (`food_activity_sales`, 0026) have a free-text
  `payment_method` that no screen sets.
- Room tax is fixed in each booking's `quote` (`get_quote`: `subtotal`,
  `cleaning_fee`, `coupon.discount`, `tax_pct`, `tax_amount`, `total`; tax is
  charged on `subtotal + cleaning_fee − discount`). Food orders, activity
  bookings and walk-in sales carry no tax.
- `report_revenue` (0045) is accrual only: quote totals by arrival date, minus
  refunds. No report reads `payments`.
- `/owner/reports` (the CSV export centre) is owner-only; accountants land on
  `/staff/dashboard` and reach only `/admin/reports` (revenue, occupancy) and
  `/owner/expenses`.

## Decisions (agreed 2026-09-25)

1. **Both bases.** A cash-basis **Collections** report (money in and out by
   payment date, online versus desk, by method) and an accrual-basis
   **Ledger** report (revenue earned, by category).
2. **Fixed method list**: Cash, Card, UPI, Bank transfer, Other. Online
   payments are recorded as `gateway`.
3. **One method per checkout**, with an optional receipt or UTR reference.
   Split tenders and a running bill come later.
4. **Collections are split by channel and method only.** Categories exist only
   in the Ledger; a checkout payment is never allocated across categories.
5. **Categories**: Room = nightly rate + extra guests − coupon;
   F&B = in-stay food orders + walk-in food; Spa/Activities = activity
   bookings + walk-in activities; Ancillary = cleaning fee + cancellation fees
   kept.
6. **Tax**: room tax only, exactly as fixed in each booking's quote; GSTIN on
   the export. F&B and Spa are shown untaxed. Per-category rates are a
   follow-up once the accountant confirms them.
7. **Refunds** come from `reservations.refund_amount`, dated by
   `cancelled_at`, as negative Collections lines. No schema change to
   `cancel_booking`.
8. **Room revenue falls on the arrival date**, as in `report_revenue`.
9. **Owner, admin and accountant** see Finance; the accountant lands on
   `/finance`. Staff keep their current revenue and occupancy view.
10. **CSV only**, through the existing `csv_export.dart` / `csv_download*.dart`.
11. **Refresh**: live query on open, pull-to-refresh, and a refetch after any
    payment action. Realtime is a later follow-up.

Implementation choices made while checking the draft against the code:
- A desk reference goes in a new `payments.reference` column, not in
  `gateway_ref`. `unique (gateway, gateway_ref)` is global, so two resorts
  (or two bookings) using receipt number `001` would collide.
- A refund in Collections is capped at the succeeded payments of that
  booking, and a booking with no payment shows no refund line (see the
  `compute_refund` note above).
- `confirm_booking` is not redefined: the new column default (`gateway`) is
  what it needs.
- A guest recording a desk method raises the existing **P0009**. No new error
  codes are needed (P0032+ stay free).

## Data model — `supabase/migrations/0048_finance_ledger.sql`

- Enum `public.payment_method`: `gateway`, `cash`, `card`, `upi`,
  `bank_transfer`, `other`.
- `payments` gains:
  - `method public.payment_method not null default 'gateway'`. Existing rows
    become `gateway`, which is correct: every payment so far went through the
    mock gateway.
  - `reference text check (reference is null or length(reference) <= 64)` —
    the receipt, card-slip or UTR number typed at the desk.
  - `recorded_by uuid default auth.uid() references profiles(id) on delete set null`.
    Existing rows stay null (unknown). For a gateway payment it is the guest
    who paid.
  - index `payments (property_id, created_at)` for the date-range reports.
- `food_activity_sales.payment_method` becomes `public.payment_method not null
  default 'cash'`, with `check (payment_method <> 'gateway')`. Existing text is
  mapped by `lower(trim(...))`: `cash`, `card`, `upi` as is; `bank transfer`,
  `bank_transfer`, `neft`, `imps` → `bank_transfer`; anything else, including
  null, → `other`.
- `expenses.payment_method` is left alone (money out, not a collection).
- No new tables and no triggers. Categories are worked out by the report
  functions from the source rows.

## Functions (security definer, `search_path = public, pg_temp`, revoked from public and anon, granted to authenticated)

- `checkout_booking(p_reservation_id uuid, p_payment_ref text, p_amount numeric,
  p_method public.payment_method default 'gateway')` — the old three-argument
  signature is dropped and the function recreated and re-granted, as 0045 did
  for the report functions. The body is copied from its **latest** definition,
  which is Project B's `0047_room_status.sql` (it marks the room dirty); only
  the method handling is added:
  - `coalesce(p_method, 'gateway')`.
  - A method other than `gateway` needs a role at the booking's resort:
    `has_resort_role(property_id, true, 'owner','admin','staff','accountant')`,
    else **P0009** `desk payment methods are recorded by resort staff`. So the
    guest's own self-checkout can only be `gateway`; a staff member checking
    out their own stay can still use a desk method.
  - Desk row: `gateway = 'desk'`, `gateway_ref = 'desk-' || p_reservation_id`
    (one balance payment per booking, so it stays unique and doubles as a
    retry guard), `method = p_method`, `reference = nullif(trim(p_payment_ref), '')`.
  - Gateway row: unchanged (`'mock'`, `gateway_ref = p_payment_ref`),
    `method = 'gateway'`.
  - Unchanged: a retry on a `checked_out` booking returns the row without a
    second payment; the amount must equal the balance (P0009); a zero balance
    writes no payment.
- Every report function below:
  - takes a required `p_property_id uuid` (no default) and calls
    `assert_resort_role(p_property_id, false, 'owner','admin','accountant')`
    first — plain staff get P0020, as do members of another resort; a
    suspended resort can still read, an archived one cannot;
  - works days out in that resort's `properties.timezone`;
  - counts only `payments.status = 'succeeded'`;
  - returns amounts rounded to 2 decimals;
  - is `stable`.
- `report_collections(p_from date, p_to date, p_property_id uuid)` returns
  `(day date, channel text, source text, method public.payment_method,
  txn_count int, amount numeric)`, one row per day × channel × source × method.
  - `channel`: `online` when `method = 'gateway'`, otherwise `front_desk`.
  - `source`:
    - `booking_advance` — `payments.kind = 'advance'`, dated by `created_at`;
    - `checkout_balance` — `payments.kind = 'balance'`, dated by `created_at`;
    - `walk_in_sale` — `food_activity_sales`, dated by `sale_date`;
    - `refund` — cancelled bookings dated by `cancelled_at`, amount
      `−least(coalesce(refund_amount, 0), paid)` where `paid` is the booking's
      succeeded payments; rows of 0 are left out. Method `gateway`, channel
      `online` (refunds go back the way the advance came in).
- `report_ledger(p_from date, p_to date, p_property_id uuid)` returns
  `(day date, category text, source text, gross numeric, discount numeric,
  taxable numeric, tax numeric, net numeric)`, one row per day × category ×
  source, where `taxable = gross − discount` and `net = taxable + tax`.
  - `room` / `booking`: bookings (`kind = 'booking'`, quote not null) with
    status `confirmed`, `checked_in` or `checked_out`, on the arrival date.
    `gross` = quote `subtotal` (nightly rates + extra guests);
    `discount` = `least(coupon discount, subtotal)`;
    `tax` = `round(taxable × quote tax_pct / 100, 2)`.
  - `ancillary` / `cleaning_fee`: the same bookings and date. `gross` = quote
    `cleaning_fee`; `discount` = the rest of the coupon discount;
    `tax` = quote `tax_amount` − the room tax, so the two rows add up to the
    quote's `tax_amount` exactly and room + cleaning `net` = quote `total`.
  - A quote with no `subtotal` (older or hand-made rows) counts its whole
    `total` as room gross with no tax.
  - `ancillary` / `cancellation_fee`: cancelled bookings, on the
    `cancelled_at` date; `gross` = paid − the capped refund, when above 0; no
    tax.
  - `food_beverage` / `in_stay_order`: `food_orders` with status not
    `cancelled`, dated by `created_at`; `food_beverage` / `walk_in`:
    `food_activity_sales` with category `food`, by `sale_date`. No tax.
  - `spa_activities` / `activity_booking`: `activity_bookings` with status
    `booked`, by `booking_date`; `spa_activities` / `walk_in`: walk-in
    `activity` sales. No tax.
- `report_settlements(p_from date, p_to date, p_property_id uuid)` returns one
  row per booking whose `checked_out_at` falls in the range:
  `reservation_id, guest_name, unit_name, arrival, departure, room, cleaning_fee,
  tax_pct, tax, food, activities, total, advance_paid, balance_online,
  balance_desk, desk_method, desk_reference, recorded_by_name, outstanding`.
  `total` uses the same formula as `current_charges` (quote total + non-cancelled
  food orders + non-cancelled activity bookings); `outstanding` = `total` −
  succeeded payments, which is 0 after a normal checkout.
- `finance_summary(p_property_id uuid)` returns jsonb for "today" in the
  resort's timezone:
  `resort` (`name`, `slug`, `gstin`, `tax_pct`, `timezone`, `today`),
  `online_collected`, `desk_collected` (`total` and one key per method),
  `refunds`, `net_collected`, `room_tax` (today's Ledger tax), and
  `in_house_count` / `in_house_balance` (checked-in bookings, balance worked
  out as in `current_charges`, set-based rather than one call per booking).
  The `resort` block feeds the export header.
- The definer allow-list in `37_tenancy_isolation_test.sql` gains
  `report_collections`, `report_ledger`, `report_settlements` and
  `finance_summary`.

## App

- `lib/data/models/payment_method.dart`: `PaymentMethod` enum (`gateway`, `cash`,
  `card`, `upi`, `bankTransfer`, `other`) with wire value, label and icon, and
  `PaymentMethod.desk` (every value but `gateway`). Unknown wire values parse
  as `other`.
- `lib/data/models/finance.dart`: `CollectionRow`, `LedgerRow`,
  `SettlementRow`, `FinanceSummary`, each with `fromJson`.
- `lib/data/repositories/finance_repository.dart`: `summary(propertyId)`,
  `collections(from, to, propertyId)`, `ledger(...)`, `settlements(...)`,
  dates sent as `yyyy-MM-dd` like `ReportRepository`, errors through
  `_guard` / `mapPostgrestError`. `financeRepositoryProvider`.
- `lib/features/finance/providers.dart`: `financeSummaryProvider.family`
  keyed by property id; `collectionsProvider`, `ledgerProvider` and
  `settlementsProvider` as `FutureProvider.family` keyed by the existing
  `ReportFilter` record.
- `lib/features/finance/finance_csv.dart`: pure functions turning each report
  into `List<List<String>>` for `toCsv`. Every file starts with two lines —
  resort name and GSTIN (or "GSTIN not set"), and the date range — then the
  column header. File name: `<slug>-<report>-<from>-<to>.csv`
  (e.g. `pasala-collections-2026-09-01-2026-09-30.csv`).
- `lib/features/finance/finance_screen.dart` at `/finance`:
  - current resort only (`currentResortProvider`); date range picker,
    default this month; four tabs, each with pull-to-refresh and Export CSV
    (the same "not available on this platform yet" message as
    `ReportsScreen` when `downloadCsv` returns false):
    - **Today**: cards for online collected, desk collected (with a
      per-method breakdown), refunds, net collected, room tax, and in-house
      guests with their unpaid balance.
    - **Collections**: one row per day with Online, Cash, Card, UPI, Bank,
      Other, Refunds and Net columns, plus a totals row. The CSV keeps
      `channel`/`source`/`method` per line.
    - **Ledger**: one row per day with Room, F&B, Spa/Activities,
      Ancillary, Taxable, Tax and Total, plus a totals row and a tax strip
      (total taxable, total tax, the resort's current rate and GSTIN; each
      booking's own rate is in Settlements).
    - **Settlements**: one row per checked-out booking; a non-zero
      `outstanding` is highlighted with an icon and text, not colour alone.
  - wide screens show tables; phones show one card per day or booking.
  - loading, empty and error states use the existing `AsyncView`.
- Navigation:
  - `/finance` route inside the signed-in shell. `redirectFor`: sends a user
    with 2+ memberships and no current resort to `/choose-resort` (as for
    `/admin`, `/staff`, `/owner`) and allows only owner, admin and accountant
    at the current resort; everyone else gets `/404`.
  - `landingPathFor`: accountant → `/finance`.
  - `AppShell`: accountants get their own destinations — Finance, Today,
    Rooms (Project B's `/staff/rooms`), Dashboard, Reports. Staff keep theirs.
  - Owner hub: a Finance tile. Admin More screen: a Finance entry.
  - `/owner/reports` export centre adds Collections, Ledger and Settlements,
    using `finance_csv.dart`.
- Desk checkout:
  - `StayRepository.checkout` gains `PaymentMethod method = PaymentMethod.gateway`
    and makes `paymentRef` nullable; it sends `p_method`.
  - `CheckoutScreen` gains `desk` (default false). The `/my-stay/checkout`
    route accepts `extra` as the reservation id (guest) or a
    `DeskCheckoutArgs(reservationId)` (reception); `ReceptionCheckoutScreen`
    passes the latter.
  - In desk mode the screen shows method chips (Cash, Card, UPI, Bank
    transfer, Other; default Cash), an optional Reference field (64 chars),
    and a "Record ₹<balance> and check out" button. It does not call
    `PaymentGateway`. Guest self-checkout is unchanged.
  - After a successful checkout (either mode) the finance providers for the
    resort are invalidated.
- Walk-in sales (`food_sales_screen.dart`, `FoodSale`): `paymentMethod`
  becomes a required `PaymentMethod` (desk values only, default Cash) on the
  add and edit form, and the list shows it. Saving a sale invalidates the
  finance providers.

## Rules

- Every finance figure is scoped to one resort; `p_property_id` is always
  required and the role is asserted at that resort.
- Plain staff cannot call the finance functions; their `report_revenue`,
  `report_occupancy` and `/admin/reports` access is unchanged.
- Guests can never record a desk method; walk-in sales can never be
  `gateway`.
- No existing policy on `payments`, `food_activity_sales` or
  `reservations` is widened. Writes go through `checkout_booking` or the
  existing `food_activity_sales` policies.
- Reports are read-only: they work at a suspended resort (P0020 at an
  archived one). `checkout_booking` keeps P0022 at a suspended resort.
- Days use the resort's timezone; amounts are rounded to 2 decimals;
  cancelled food orders and activity bookings are excluded.

## Testing

- pgTAP `supabase/tests/40_finance_ledger_test.sql` (~40 assertions; 39 is
  Project B's):
  - enum and columns exist; existing payments backfilled to `gateway`;
    walk-in text mapped (`Cash` → `cash`, `NEFT` → `bank_transfer`, `xyz`
    and null → `other`); a walk-in `gateway` sale is rejected;
  - staff checkout with `cash` and a reference writes `gateway = 'desk'`,
    `method = 'cash'`, the reference and `recorded_by`; a guest passing
    `cash` gets P0009; guest self-checkout still writes `mock`/`gateway`; a
    retried checkout writes no second row; two resorts using the same
    reference both succeed; the room is still marked dirty (Project B);
  - Collections: advance and self-checkout balance under `online`, desk
    balance and walk-in sales under `front_desk` by method; a refund is
    negative on the cancel date; a cancelled unpaid hold shows no refund; a
    refund larger than the amount paid is capped;
  - Ledger: nightly and extra-guest amounts, coupon, cleaning fee, food
    orders, walk-in food, activities, walk-in activities and kept
    cancellation fees land in the right category; cancelled orders and
    activities are excluded; room + cleaning tax equals the quote's
    `tax_amount` and their net equals the quote `total`; a coupon larger
    than the subtotal spills onto the cleaning fee; a total-only quote is
    all room gross;
  - Settlements: outstanding is 0 after checkout; desk method and reference
    are shown;
  - `finance_summary` today figures and in-house balance;
  - tenancy: resort-B accountant denied on resort A, plain staff denied,
    null resort id denied, suspended resort readable, archived denied;
    definer allow-list guard passes;
  - a booking paid at 23:30 resort time falls on that resort-local day.
- Flutter:
  - `PaymentMethod` wire and label mapping; `CollectionRow`, `LedgerRow`,
    `SettlementRow`, `FinanceSummary.fromJson`;
  - `finance_csv_test`: header lines, GSTIN fallback, column order, file name;
  - `finance_screen_test` with a fake `FinanceRepository` and a fixed
    current resort: the resort id reaches every call, tabs render, totals
    rows, outstanding highlight, empty and error states, export;
  - `checkout_screen_test` (new): desk mode shows the chips and reference
    and never calls the gateway; guest mode is unchanged;
    `reception_checkout_screen_test`: passes desk args;
  - `food_sales_screen_test`: method required and listed;
  - `router_test`: `/finance` matrix (owner, admin, accountant allowed;
    staff, customer denied; 2+ memberships → `/choose-resort`) and the
    accountant landing; `app_shell_test`: accountant destinations;
    `owner_home_screen_test` / `admin_more_screen_test`: Finance entry.

## Out of scope

Split tenders and a running bill (desk payments during the stay); a
permanent trigger-maintained ledger table with period close (with Razorpay
and GST invoicing); refund payment rows written by `cancel_booking`;
per-category tax rates and tax-inclusive F&B/Spa prices; CGST/SGST/IGST and
HSN/SAC invoicing; spreading room revenue over each night; XLSX and PDF
export; realtime refresh; front-desk staff seeing desk totals; changing
`report_revenue`, which subtracts refunds of cancelled bookings (including
unpaid holds) and so will not match the Ledger exactly.
