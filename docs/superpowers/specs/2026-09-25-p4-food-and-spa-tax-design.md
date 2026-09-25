# Food and Spa Tax (P4) — Design

## Why

GST applies to what a resort sells besides rooms: food and drink, and spa
and activity sessions. Resorts price these with the tax already included
(the menu says ₹210, the guest pays ₹210), but they still have to report
how much of that is tax.

Today only rooms are taxed:
- `properties.tax_pct` (`0025_property_settings.sql`) is the room rate.
  `get_quote` adds it on top of the room subtotal and cleaning fee, and the
  quote keeps `tax_pct`/`tax_amount`.
- `food_orders`, `food_order_items`, `activity_bookings` and
  `food_activity_sales` store only amounts. Nothing records the tax inside
  them.
- `report_ledger` (`0048_finance_ledger.sql`) puts the whole amount of every
  food, activity and walk-in line in `gross` with `tax = 0`, and
  `finance_summary.room_tax` is "all of today's Ledger tax".
- The owner's Taxes screen (`lib/features/owner/tax_settings_screen.dart`)
  edits the room rate and GSTIN only.
- The guest's Current Charges and Final Invoice screens show Food and
  Activities totals with no tax.

This project adds a food & drink rate and a spa & activities rate per
resort. Each sale records its tax when it is made, and the Ledger, the
Today tab and the guest's bill show that tax by category.

## Decisions (agreed 2026-09-25)

Accepted by the product owner (auto-approved):

1. **Two new rates per resort**: `properties.fnb_tax_pct` and
   `properties.spa_tax_pct`, `numeric`, default 0, allowed range 0 to 28.
2. **Prices include tax.** The tax inside a price is
   `price × pct / (100 + pct)`, rounded to paise (2 decimals). The price the
   guest pays does not change.
3. **Tax is stored on the row when it is sold or ordered.** `food_orders`,
   `food_order_items`, `activity_bookings` and `food_activity_sales` each
   gain `tax_pct` and `tax_amount`. A later rate change does not rewrite
   them.
4. **The owner's Taxes screen edits both rates.**
5. **The Finance Ledger and the invoices show tax per category.**
6. **Rows that exist before this migration have tax 0.**

Judgment calls made while writing this spec:

7. **Triggers fill the tax columns, not the RPCs.** A `before insert or
   update` trigger on each of the four tables sets `tax_pct` and
   `tax_amount`. So `place_food_order`, `book_activity` and the walk-in
   sales form (a plain RLS insert) work unchanged, and nothing a client
   sends in `tax_pct` or `tax_amount` is kept.
8. **The rate is fixed when the row is inserted.** On insert, the trigger
   reads the resort's current rate: food & drink for food orders, their
   items and `food` walk-in sales; spa & activities for activity bookings
   and `activity` walk-in sales. On update, the stored `tax_pct` is kept
   and `tax_amount` is worked out again from the row's amount (so a
   correction to a walk-in sale's amount keeps the rate it was sold at).
   The one exception is a walk-in sale whose category is changed: it takes
   the current rate of its new category.
9. **Order tax is worked out on the order total.**
   `food_orders.tax_amount = inclusive_tax(total, tax_pct)`. Each item has
   its own `tax_amount` on its `line_total`, at the order's rate. The
   items' taxes can differ from the order's by a paisa of rounding. The
   order's figure is the one every report and bill adds up.
10. **One helper does the maths**: `public.inclusive_tax(p_amount numeric,
    p_pct numeric) returns numeric`, `immutable`, not `security definer`.
11. **Out-of-range rates raise P0035 `tax_rate_out_of_range`** from a
    `before insert or update` trigger on `properties`. `check` constraints
    back it up. The app shows "Food and spa tax rates must be between 0%
    and 28%." The Taxes screen checks the range before saving, so the
    server error is a backstop.
12. **Who may change the rates** does not change: the owner or an admin of
    the resort, through the existing `properties_update` policy. The screen
    stays in the owner's settings.
13. **Ledger rows for food, activities and walk-ins are split into pre-tax
    and tax**: `gross = amount − tax_amount`, `discount = 0`,
    `taxable = gross`, `tax = tax_amount`, `net = amount`. Net is the same
    as before this project, so Collections, Settlements and the checkout
    balance do not move.
14. **`finance_summary.room_tax` means room tax only again**: the `room`
    and `ancillary` categories. `finance_summary` gains `food_tax`,
    `spa_tax`, and the resort's two new rates in its `resort` block.
15. **`current_charges` gains `food_tax` and `activity_tax`**, the tax
    inside `food_amount` and `activity_amount`. `total` and `balance` do
    not change, because the tax is already inside the amounts. P2 (PDF
    invoices) reads these keys for its per-category tax lines.
16. **No new security definer functions.** The trigger functions run with
    the caller's rights. Inside `place_food_order` and `book_activity`
    that is the function owner. For a walk-in sale it is the staff member,
    who can read their own resort's `properties` row. The definer
    allow-list in `37_tenancy_isolation_test.sql` does not change.
17. **Walk-in sales show their tax** in the Food & activity sales list
    ("Includes tax ₹22.50"), so the front desk can check it. The in-stay
    ordering and activity screens do not change.
18. **Settlements do not change.** Its `food` and `activities` columns stay
    tax-inclusive, and its `tax` column stays room tax. The per-category
    tax of one booking is on the guest's bill (`current_charges`) and the
    Ledger.

## Data model — `supabase/migrations/0053_food_spa_tax.sql`

- `properties` gains:
  - `fnb_tax_pct numeric(5,2) not null default 0`, constraint
    `properties_fnb_tax_pct_range check (fnb_tax_pct >= 0 and fnb_tax_pct <= 28)`
  - `spa_tax_pct numeric(5,2) not null default 0`, constraint
    `properties_spa_tax_pct_range check (spa_tax_pct >= 0 and spa_tax_pct <= 28)`
- `food_orders`, `food_order_items`, `activity_bookings` and
  `food_activity_sales` each gain:
  - `tax_pct numeric(5,2) not null default 0`, check `0..28`
  - `tax_amount numeric(12,2) not null default 0`, check `>= 0`
  - Adding the columns with a default fills every existing row with 0 and
    fires no trigger.
- No new tables, no new grants on tables, no policy changes.

## Functions and triggers

- `public.inclusive_tax(p_amount numeric, p_pct numeric) returns numeric` —
  `immutable`, `language sql`, `set search_path = public, pg_temp`:
  `round(coalesce(p_amount, 0) * coalesce(p_pct, 0) / (100 + coalesce(p_pct, 0)), 2)`.
  Revoked from `public` and `anon`, granted to `authenticated` (the
  walk-in trigger runs as the staff member and calls it).
- Trigger functions (`language plpgsql`, `set search_path = public, pg_temp`,
  not `security definer`, `execute` revoked from `public, anon, authenticated`):
  - `food_orders_set_tax()` on `food_orders` (trigger
    `food_orders_set_tax`, `before insert or update`): on insert
    `tax_pct` = the fnb rate of the reservation's resort (read through
    `reservation_id`, so it does not depend on trigger order); on update
    `tax_pct = old.tax_pct`; always `tax_amount = inclusive_tax(total, tax_pct)`.
  - `food_order_items_set_tax()` on `food_order_items`: on insert
    `tax_pct` = its order's `tax_pct`; on update the old one; always
    `tax_amount = inclusive_tax(line_total, tax_pct)`.
  - `activity_bookings_set_tax()` on `activity_bookings`: on insert the spa
    rate of the reservation's resort; on update the old one; always
    `tax_amount = inclusive_tax(amount, tax_pct)`.
  - `food_activity_sales_set_tax()` on `food_activity_sales`: on insert,
    or when `category` changes, the rate for the category (`food` → fnb,
    `activity` → spa) of `property_id`'s resort; otherwise the old one;
    always `tax_amount = inclusive_tax(amount, tax_pct)`.
  - `properties_check_service_tax()` on `properties` (`before insert or
    update of fnb_tax_pct, spa_tax_pct`): raises **P0035
    `tax_rate_out_of_range`** when either rate is null or outside 0..28.
- `current_charges(p_reservation_id)` — body copied from its latest
  definition (`0045_resort_functions.sql`); adds `food_tax` (sum of
  `tax_amount` of non-cancelled food orders) and `activity_tax` (same for
  activity bookings) to the returned object. Access is unchanged.
- `report_ledger(p_from, p_to, p_property_id)` — body copied from
  `0048_finance_ledger.sql`; the `in_stay_order`, `walk_in` and
  `activity_booking` lines use `gross = amount − tax_amount` and
  `tax = tax_amount`. Signature, columns, ordering and access unchanged.
- `finance_summary(p_property_id)` — body copied from
  `0048_finance_ledger.sql`; `room_tax` sums the Ledger's `room` and
  `ancillary` tax; new keys `food_tax` (`food_beverage` tax) and `spa_tax`
  (`spa_activities` tax); `resort` gains `fnb_tax_pct` and `spa_tax_pct`.

## App

- Models (read-only additions; every new field defaults to 0 when the key
  is missing, so an older server still parses):
  - `Property.fnbTaxPct`, `Property.spaTaxPct` (`fnb_tax_pct`, `spa_tax_pct`).
  - `CurrentCharges.foodTax`, `CurrentCharges.activityTax`.
  - `FinanceResort.fnbTaxPct`, `FinanceResort.spaTaxPct`;
    `FinanceSummary.foodTax`, `FinanceSummary.spaTax`.
  - `FoodSale.taxPct`, `FoodSale.taxAmount` — read from the row, never sent
    in `toInsert()`.
- `lib/core/errors.dart`: `TaxRateOutOfRange` for P0035, copy "Food and spa
  tax rates must be between 0% and 28%."
- Taxes screen (`tax_settings_screen.dart`, reached from Owner Settings →
  Taxes, subtitle "Room, food and spa tax rates, GSTIN"):
  - fields: "Room tax rate (%)" (existing, 0..100, "Added on top of the
    room price at booking time"), "Food & drink tax (%)" and "Spa &
    activities tax (%)" (0..28, "Already included in menu prices" /
    "Already included in activity prices"), GSTIN (existing)
  - a note: "Each order and sale keeps the rate it was made at. Changing
    a rate affects new sales only."
  - Save sends `tax_pct`, `fnb_tax_pct`, `spa_tax_pct`, `gstin` in one
    `updateSettings` call; a value that is not a number, or out of range,
    shows an inline error and saves nothing
- Finance screen:
  - Ledger: `LedgerDay` keeps tax per category. Phone cards list
    "<category> tax ₹x" under "Tax" for each category with tax. The wide
    table gains "Room tax", "F&B tax", "Spa/Activities tax" and
    "Ancillary tax" columns before "Tax". The tax strip lists the tax of
    each category that has any, and the rates as "Room rate 12%",
    "F&B rate 5%", "Spa/Activities rate 18%".
  - Today: "F&B tax" and "Spa tax" cards next to "Room tax".
  - Today CSV gains `F&B tax` and `Spa tax` lines after `Room tax`. The
    Ledger CSV already has one row per category with its tax.
  - Owner export centre: Ledger subtitle "Revenue and tax by category".
- Guest bill: Current Charges and Final Invoice show "Includes tax ₹x.xx"
  under Food and under Activities when that tax is above 0.
- Food & activity sales list: the row subtitle ends with "Includes tax
  ₹x.xx" when the sale's tax is above 0.

## Rules

- A client never sets tax. The triggers overwrite `tax_pct` and
  `tax_amount` on every insert and update.
- The rate is read from the resort of the row (through its reservation,
  order or `property_id`), never from a client-supplied resort.
- No policy on `properties`, `food_orders`, `food_order_items`,
  `activity_bookings` or `food_activity_sales` is widened.
- Suspended resort: rates are read-only for the resort (the existing
  `properties_update` policy needs write access); reports stay readable.

## Testing

- pgTAP `supabase/tests/44_food_spa_tax_test.sql` (67 assertions):
  columns, types, checks and defaults; existing rows have tax 0;
  `inclusive_tax` values and rounding; owner sets rates, staff cannot;
  P0035 above 28 and below 0; a guest's order and its items get the fnb
  rate; a staff update that tries to zero the tax is overwritten; a rate
  change leaves earlier orders alone and applies to the next one; activity
  bookings get the spa rate and keep it when cancelled; walk-in sales
  ignore client-sent tax, keep their rate when the amount is corrected,
  and take the new category's rate when the category changes;
  `current_charges` tax keys; `report_ledger` pre-tax/tax split with
  `taxable + tax = net`; `finance_summary` room, food and spa tax and the
  rates.
- The existing suites (`22`, `26`, `28`, `29`, `33`, `35`, `37`, `40`) pass
  unchanged: every fixture resort has rates of 0.
- Flutter: model parsing (new keys and missing keys); `TaxRateOutOfRange`
  mapping; Taxes screen (prefill, save payload, range and non-number
  errors, server error); Ledger per-category tax (tables, cards, strip,
  wide table); Today cards and CSV; Current Charges and Final Invoice tax
  lines; walk-in sale subtitle.

## Out of scope

Tax-exclusive pricing for food or spa; per-item or per-activity rates
(HSN/SAC codes); CGST/SGST/IGST split; tax on the cancellation fee; tax
columns in Settlements; showing "prices include tax" on the menu and
activity catalog; PDF invoices (P2 reads the new `current_charges` keys);
recomputing old rows at a new rate.
