# Guest Stay Experience — Design

## Why

The app had a complete, well-tested pre-arrival flow (browse → dates →
guests → price → pay → confirmation) but nothing that happens after a
guest actually arrives. Compared against
`Single_Farmhouse_Customer_Flow_Without_6th_Concept.docx`'s 26-step
customer journey, everything from step 15 ("Arrival / Check-In") through
step 24 ("Review") was entirely unbuilt: QR check-in, an in-stay hub,
food ordering, activity booking, service requests, maintenance reporting,
a running bill, checkout with balance payment, a final invoice, a review.

## Scope decisions (confirmed before implementation)

- **Login stays email + password** — no SMS provider exists anywhere in
  this project; the outbox's own header already says nothing has ever
  been sent. Building OTP UI with nothing behind it would be exactly the
  kind of unbuilt-feature fakery this codebase deliberately avoids
  everywhere else.
- **Check-in is a reception lookup, not camera scanning** — the guest's
  confirmation/booking-detail screens show a real (decorative) QR code;
  reception finds the booking and taps Check In. This is one of the
  source doc's own two accepted methods ("shows QR code **or** booking
  details").
- **Full flow built in one pass**, per the user's own ask.

## Key design decision: extras settle at checkout, not at booking

The doc's step 7 ("Add Extra Services") lets a customer add food/
activities before paying, and step 8 folds them into the initial total.
Building that would mean teaching `get_quote`/`confirm_booking` — the
most heavily tested, race-proof code in this app — to price food and
activities, for a feature that's really about the stay, not the booking.

Instead: **`get_quote`/`create_hold`/`confirm_booking` are untouched.** A
guest can add food, book activities, or request a service/report an issue
from the moment their booking is `confirmed` (before arrival counts too,
satisfying "Add Extra Services") through `checked_in`. Everything beyond
the original stay quote is a running tab, settled in one new RPC at
**checkout**, exactly as the doc's own checkout section describes ("food,
activities and services are included in the final bill... customer pays
remaining balance"). Lower risk, matches how a real front desk runs a
tab, and reuses zero code paths that would put existing booking-flow
tests at risk.

## Database (migrations `0031`–`0038`)

- **`0031_stay_lifecycle.sql`** — adds `checked_in`/`checked_out` to
  `reservation_status` (its own migration/transaction — a new enum value
  can't be referenced in the same transaction it's added in) plus
  `checked_in_at`/`checked_out_at timestamptz` + a
  `checked_out_at > checked_in_at` check constraint.
- **`0032_food_ordering.sql`** — `food_categories`/`food_items` (plain
  admin-managed catalog, readable by anyone signed in), `food_orders`/
  `food_order_items` (name/price **snapshotted at order time**, the same
  server-prices-everything principle `get_quote` already established).
  `place_food_order(p_reservation_id, p_items, p_notes)` SECURITY DEFINER:
  checks ownership and that status is `confirmed`/`checked_in`, prices
  every line from `food_items.price` server-side. Kitchen fulfilment is a
  plain UPDATE gated to staff-or-above (kitchen doesn't need admin).
- **`0033_activity_booking.sql`** — `activities` (per-person price,
  per-slot capacity) and `activity_bookings` (price snapshotted as
  `price_per_person * people`). `book_activity(...)`: same ownership/
  status gate, locks the **activity row** (not an aggregate — `for
  update` cannot target one directly) before summing existing bookings
  for that slot against `capacity_per_slot`. The owning customer can
  cancel their own booking directly (no RPC needed — nothing left to
  re-price once cancelled).
- **`0034_service_requests.sql`** — `service_requests`, mirroring
  `0024_tasks.sql`'s write-enforcement shape: RLS's own UPDATE policy
  stays permissive (`using (true)`) so it can admit both staff-or-above
  and the assigned staff member on a row either can see; the trigger is
  what actually restricts what each side may change, raising an explicit
  `42501` rather than silently affecting zero rows (same reasoning as
  `tasks_enforce_write`'s DELETE branch). New here: assigning
  `assigned_staff_id` from `null` auto-bumps status to `assigned`.
- **`0035_maintenance_issues.sql`** — `maintenance_issues`, same shape as
  service requests plus `priority`/`photo_url`. First-ever Storage bucket
  in this app (`maintenance-photos`, declared in `config.toml`): a
  customer may upload only under `{their own uid}/...`, staff-or-above can
  read anything in the bucket, and nobody may update/delete an uploaded
  photo (a report is immutable evidence — a corrected photo is a new
  report).
- **`0036_reviews.sql`** — `reviews` (`reservation_id` unique), insertable
  once per reservation, only by its owning customer, only once
  `status = 'checked_out'`. No update/delete — a submitted review is
  immutable, matching every consumer review platform's own behaviour.
- **`0037_stay_checkout.sql`** — `check_in_booking` (staff-or-above,
  idempotent, `confirmed → checked_in`), `current_charges` (stay quote +
  live non-cancelled food/activity sums − payments captured, computed
  fresh every call, never stored), `checkout_booking` (staff-or-above,
  requires `checked_in`, requires the payment amount matches
  `current_charges`'s balance exactly, records a `payments` row with
  `kind = 'balance'` — the first use of that enum value — sets
  `checked_out`). Both `check_in_booking` and `checkout_booking` stamp
  their timestamp with `clock_timestamp()`, not `now()` — `now()` is
  frozen at transaction start, so calling both inside one transaction
  (as pgTAP's own tests do) would otherwise set `checked_out_at` equal to
  `checked_in_at` and fail the strict `>` check constraint even though the
  two calls happened in the intended order.
- **`0038_stay_dashboard_summary.sql`** — `dashboard_summary()` gains
  `checked_in_today`/`checked_out_today`/`currently_in_house`, purely
  additive.

## Known pre-existing issues found during verification

Same environment/version-drift issue already documented in the Owner
Flow spec: this local Postgres/Supabase image grants `anon`/
`authenticated` broad default table privileges via
`ALTER DEFAULT PRIVILEGES`, so several `anon`-cannot-SELECT assertions
fail across the whole app (RLS still correctly hides the data — no real
leak). Confirmed still present and unrelated to this feature; left
unfixed, same as before. Also: `14_ical_test.sql` fails locally on
`relation "net._http_response" does not exist` — pre-existing and
unrelated to this feature (`pg_net`'s response table isn't present in
this local image).

## Flutter

- `lib/features/stay/` — customer screens, following the existing
  `ConsumerWidget`/`FutureProvider`/`AsyncView`/`FailureView`/`EmptyState`
  pattern throughout.
- New models: `food_item.dart` (+`FoodCategory`), `food_order.dart`
  (+`FoodOrderItem`), `activity.dart` (+`ActivityBooking`),
  `service_request.dart`, `maintenance_issue.dart`, `review.dart`,
  `current_charges.dart` — plain hand-written classes, matching
  `report.dart`'s style. `reservation.dart` gained the two new statuses
  and `checkedInAt`/`checkedOutAt`.
- New repositories, each following `task_repository.dart`'s `_guard` +
  `Provider`/`FutureProvider.family` shape, plus `stay_repository.dart`
  (`currentStay()` resolves a `checked_in` reservation first, falling back
  to the soonest-upcoming `confirmed` one).
- `image_picker`/`qr_flutter` added to `pubspec.yaml` — the app's first
  file upload and first QR display, both purely additive.
- `lib/features/admin/`: `reception_checkin_screen.dart`,
  `kitchen_orders_screen.dart`, `service_requests_screen.dart`,
  `maintenance_issues_screen.dart` — admin-only for now (kitchen/check-in
  could arguably be staff-or-above like `/admin/dashboard`, but starting
  admin-only and widening later is the safer default). `lib/features/staff/`
  gets each staff member's own assigned-queue view of the same three.
- `lib/core/router.dart` — `/my-stay/*` routes (reachable by any signed-in
  user, same as `/bookings`); `/admin/check-in`+`/admin/kitchen-orders`+
  `/admin/service-requests`+`/admin/maintenance` (admin-only);
  `/staff/food-orders`+`/staff/service-requests`+`/staff/maintenance`
  (already covered by the existing staff-or-above `/staff` gate).
- `lib/features/shell/app_shell.dart` — "My Stay" added to the customer
  nav unconditionally, matching this app's preference for data-driven
  empty states over conditionally hidden nav items.
