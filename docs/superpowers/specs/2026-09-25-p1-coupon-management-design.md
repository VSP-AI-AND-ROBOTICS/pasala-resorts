# Coupon Management (P1) — Design

## Why

Guests can already type a coupon code on the booking quote sheet
(`lib/features/booking/quote_sheet.dart`), and the server applies it inside
`get_quote` and consumes a use inside `create_hold` (latest definitions in
`supabase/migrations/0045_resort_functions.sql`, validation in
`resolve_coupon`). But nobody in the app can make a coupon:

- `public.coupons` (0012, scoped to a resort in 0043/0045) has no screen.
  Coupons exist only when someone inserts rows with SQL.
- The owner hub (`lib/features/owner/owner_home_screen.dart`) and the admin
  More screen (`lib/features/admin/admin_more_screen.dart`) have no Coupons
  entry.
- `resolve_coupon` matches the code exactly (`c.code = p_code`), and the
  quote sheet sends what the guest typed (`_controller.text.trim()`), so a
  code saved as `SAVE10` fails for a guest who types `save10` on a desktop
  keyboard.

The product owner accepted section P1 of the gap-closing decisions
(2026-09-25): an owner/admin Coupons screen to create, edit, deactivate and
list coupons with their usage count. Fields: code (unique per resort,
uppercase), kind percent|fixed, value, minimum amount (optional), valid
from/until, usage limit (optional), and an optional single guest found by
the email of an existing guest who has booked at the resort (blank means
everyone). Redemption logic stays unchanged.

## Decisions (auto-approved 2026-09-25; judgment calls recorded here)

1. **Writes go through security definer functions** (`create_coupon`,
   `update_coupon`, `set_coupon_active`), not direct table writes. The guest
   rule (booked at this resort) and friendly per-field errors need server-side
   validation, and each change writes an audit row. The existing
   `coupons_write` RLS policy (owner/admin at the row's resort, 0044) is kept
   as is: it is no wider than the functions, and `11_coupons_test.sql` and
   `37_tenancy_isolation_test.sql` rely on it.
2. **Codes** are trimmed and upper-cased by the server. A code is 3–24
   characters from `A–Z`, `0–9`, `-` and `_`, and starts with a letter or
   digit. Codes are unique per resort. The existing
   `coupons_property_code_key` constraint enforces this, and a duplicate is
   reported as `code_taken`, whatever case was typed. A new table check,
   `coupons_code_upper`, keeps every stored code upper-case and trimmed. The
   migration normalises existing codes first. It skips any code whose
   normalised form would collide with another code at the same resort. The
   check is then validated only if nothing non-conforming is left.
3. **The guest's coupon field sends the code upper-cased.** `resolve_coupon`,
   `get_quote` and `create_hold` are not touched.
4. **Dates are whole days in the resort's time zone** (`properties.timezone`).
   "Valid from D" is stored as 00:00 on D. "Valid until D" is stored as the
   last microsecond of D. Both are optional. `list_coupons` returns them as
   dates. A legacy timestamp is shown as its local date and is snapped to
   whole days when the coupon is next edited.
5. **The usage count is `redeemed_count`.** This is the same counter
   `create_hold` increments. It includes uses held by live holds, and a
   cancelled or expired hold gives its use back (0016). An edit cannot set
   the usage limit below the current count (`usage_limit_below_used`). The
   check sits in the same `UPDATE` statement, so it cannot race a booking.
6. **An eligible guest** is an account with a reservation at the resort of
   kind `booking` and status `confirmed`, `checked_in` or `checked_out`.
   Holds, pending payments and cancelled bookings do not count. The lookup
   `find_resort_guest` matches the email case-insensitively after trimming,
   and returns only eligible guests. It therefore reveals nothing about
   accounts that never booked at that resort. When a coupon is edited and
   keeps the guest it already had, that guest is not checked again, because
   their booking may have been cancelled since.
7. **No delete.** Coupons are deactivated and reactivated. Deleting would
   cascade to `coupon_redemptions` and erase history. Deactivating asks for
   confirmation. Reactivating does not.
8. **Roles.** Owner and admin can read and write. Staff, accountants, guests
   and the platform admin get nothing (P0020). At a suspended resort, reading
   works but writes raise P0022. At an archived resort, everything raises
   P0020.
9. **The status is worked out on the server** by `list_coupons`, in the same
   order as `resolve_coupon`: `inactive`, then `expired`, then `scheduled`
   (not yet valid), then `used_up`, else `active`.
10. **Route `/admin/coupons`.** The existing `/admin/*` rule in `redirectFor`
    already admits owner and admin only, so the router role matrix does not
    change. There is a Coupons tile on the owner hub and on the admin More
    screen.
11. **Edits change future quotes only.** A reservation keeps the
    `quote.coupon` snapshot it was priced with. The code itself can be edited.
12. **Audit.** `audit_log` gets a row for each change (entity `coupon`,
    actions `create`, `update`, `activate`, `deactivate`), holding the row
    before and after.
13. **One error code, P0033 `coupon_invalid`.** The message is a single
    reason word. `lib/core/errors.dart` turns it into readable copy.
14. **Test placement.** Cross-resort checks live in the new
    `42_coupon_management_test.sql`. `37_tenancy_isolation_test.sql` gains
    only the new names in its definer allow-list, so that projects running in
    parallel do not collide on 37's plan count.
15. **Bounds.** The value and the minimum amount must be below
    10,000,000,000, the range of `numeric(12,2)`. Larger values are reported
    as `value_invalid` / `min_amount_invalid`, not as a raw overflow.

## Data model — `supabase/migrations/0051_coupon_management.sql`

- No new tables or columns. `public.coupons` already has `property_id`,
  `code`, `kind`, `value`, `min_booking_value`, `valid_from`, `valid_to`,
  `max_redemptions`, `redeemed_count`, `customer_id` and `is_active`.
- Existing codes are normalised as described in decision 2.
- New check `coupons_code_upper check (code = upper(btrim(code)))`, added
  `not valid` and then validated if no row violates it.

## Functions (`search_path = public, pg_temp`; each public one is security definer, revoked from public and anon, granted to authenticated, and added to the definer allow-list in `37_tenancy_isolation_test.sql`)

- `list_coupons(p_property uuid)` returns
  `table (id uuid, code text, kind public.coupon_kind, value numeric,
  min_booking_value numeric, valid_from date, valid_until date,
  max_redemptions int, redeemed_count int, customer_id uuid,
  customer_email text, customer_name text, is_active boolean, status text,
  created_at timestamptz)`. It asserts read access for `owner, admin`.
  Inactive coupons are listed last, and newer coupons come first.
- `find_resort_guest(p_property uuid, p_email text)` returns
  `table (user_id uuid, email text, full_name text)`, with zero or one row.
  It asserts read access for `owner, admin`.
- `create_coupon(p_property uuid, p_code text, p_kind public.coupon_kind,
  p_value numeric, p_min_amount numeric default null,
  p_valid_from date default null, p_valid_until date default null,
  p_usage_limit int default null, p_customer uuid default null)` returns
  the new coupon's `uuid`. It asserts write access for `owner, admin` at
  `p_property`.
- `update_coupon(p_coupon uuid, <the same eight fields>)` returns `void`.
  An unknown coupon raises P0002. The function reads the coupon's
  `property_id` and asserts write access for `owner, admin` at **that**
  resort. The update replaces the whole coupon, so a null clears that
  optional field.
- `set_coupon_active(p_coupon uuid, p_active boolean)` returns `void`. An
  unknown coupon raises P0002, and a null `p_active` raises P0005. The
  resort comes from the row, as in `update_coupon`.
- Internal helpers with invoker rights. They are revoked from public, anon
  and authenticated, and only the definer functions above call them.
  - `coupon_check_input(...)` validates the input and returns the normalised
    code.
  - `is_resort_guest(p_property, p_user)` is the rule from decision 6.
- P0033 reasons: `code_invalid`, `code_taken`, `kind_required`,
  `value_invalid`, `min_amount_invalid`, `dates_invalid`,
  `usage_limit_invalid`, `usage_limit_below_used`, `guest_not_eligible`.

## App

- `lib/data/models/coupon.dart`:
  - `CouponKind` (percent, fixed) and `CouponStatus` (active, scheduled,
    expired, usedUp, inactive), each with converters from and to the
    database. `CouponStatus` also carries a label, an icon and a colour.
  - `Coupon.fromJson`, with the display strings `discountLabel`,
    `minAmountLabel`, `validityLabel`, `usageLabel` and `audienceLabel`.
  - `CouponDraft.toParams()`, `ResortGuest`, `couponCodePattern` and
    `normalizeCouponCode`.
- `lib/data/repositories/coupon_repository.dart`:
  - The `CouponSource` seam (`list`, `create`, `update`, `setActive`,
    `findGuest`) and `CouponRepository`, which sends errors through
    `_guard`/`mapPostgrestError`.
  - Providers `couponSourceProvider` and
    `couponsProvider.autoDispose.family`, keyed by property id.
- `lib/core/errors.dart`: `CouponInvalid(reason)` for P0033, with copy for
  each reason.
- `lib/features/admin/coupons_screen.dart` at `/admin/coupons`:
  - A list of cards, one per coupon. Each card shows:
    - the code;
    - a status chip with an icon and a label, so status is never shown by
      colour alone;
    - the discount (`10% off` / `₹500 off`) and `Min ₹5,000`;
    - validity (`1 Oct 2026 – 31 Oct 2026`, `From …`, `Until …` or
      `No date limits`);
    - usage (`Used 3 of 10` / `Used 3`) and the audience (`Everyone` /
      `Only <guest>`).
  - Tapping a card edits the coupon. Deactivate asks for confirmation;
    Activate does not.
  - A "New coupon" button, pull-to-refresh, and empty and error states.
- `lib/features/admin/coupon_form.dart`: a full-screen dialog to create or
  edit a coupon.
  - Fields: code (upper-cased as typed); Percentage / Fixed amount; discount;
    optional minimum; Valid from / Valid until pickers, each with a clear
    button; optional usage limit; Everyone / One guest, where One guest takes
    an email and a Find button.
  - The form checks the same rules as the server before sending. A server
    refusal stays on the form with its message.
- Navigation: `/admin/coupons` is registered in `lib/core/router.dart`. The
  owner hub and admin More each get a "Coupons" tile.
- `quote_sheet.dart` upper-cases the code before applying it.

## Rules

- `update_coupon` and `set_coupon_active` take a coupon id, read its
  `property_id` and assert the role at that resort, never at a resort the
  client supplied. `create_coupon`, `list_coupons` and `find_resort_guest`
  take the resort id and assert the role there.
- No existing policy on `coupons`, `coupon_redemptions`, `reservations` or
  `profiles` is widened. Guest emails and names are read only through the
  definer functions.
- `resolve_coupon`, `get_quote`, `create_hold`, `cancel_booking` and
  `release_reservation_coupon` are unchanged.

## Testing

- pgTAP `supabase/tests/42_coupon_management_test.sql` (89 assertions):
  - the contract: signatures, parameter names, OUT columns, definer and
    search_path, grants, the internal helpers, and the table check;
  - normalisation and every P0033 reason;
  - the role matrix (owner/admin write; staff, accountant, guest and platform
    admin get P0020);
  - another resort can reuse a code but cannot read or write this resort's
    coupons;
  - the eligible-guest rule (confirmed yes; hold, cancelled and
    other-resort no), and a kept guest is not re-checked;
  - the usage limit cannot drop below uses taken;
  - whole-day dates in the resort's time zone;
  - a deactivated coupon is refused by `get_quote` (P0010), and a
    reactivated one discounts again;
  - status derivation and ordering, audit rows, and suspended and archived
    resorts;
  - the definer allow-list guard in 37 passes.
- Flutter:
  - model parsing and labels, `CouponDraft.toParams`, and the code rule;
  - the provider is keyed by resort;
  - P0033 copy;
  - the form: create, edit, local validation, guest lookup found and not
    found, changing the email clears a match, the usage limit floor, a server
    refusal, and cancel;
  - the screen: cards, empty and error states, create or edit refreshes the
    list, the deactivate confirmation inside a ShellRoute, activate, and a
    refused toggle;
  - the router registers `/admin/coupons`, owner and admin reach it, and
    staff and accountants get `/404`;
  - the owner hub and admin More tiles;
  - the quote sheet upper-cases the code.

## Out of scope

Deleting coupons; bulk or auto-generated codes; per-unit or per-date-range
restrictions beyond valid from/until; coupons for several named guests; a
redemption history screen, beyond the count; changing how redemption works.
