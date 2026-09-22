# Guest Stay Experience — Implementation Plan

Design rationale: `docs/superpowers/specs/2026-09-01-guest-stay-experience-design.md`.

Flow: Check-In → My Stay (Order Food, Activities, Service Requests, Report
an Issue, Current Charges, Checkout) → Final Invoice → Review. Compared
against `Single_Farmhouse_Customer_Flow_Without_6th_Concept.docx`'s 26-step
customer journey — this app already had a complete pre-arrival flow
(browse → dates → guests → price → pay → confirmation); this feature is
the missing post-arrival half.

## Tasks

1. **Schema** — migrations `0031`–`0038` (reservation lifecycle gains
   `checked_in`/`checked_out`, food ordering, activity booking, service
   requests, maintenance issues + a `maintenance-photos` Storage bucket,
   reviews, check-in/current-charges/checkout RPCs, dashboard summary
   extension), each paired with a pgTAP test (`supabase/tests/27`–`34`).
2. **Data layer** — new models (`food_item`+`FoodCategory`, `food_order`+
   `FoodOrderItem`, `activity`+`ActivityBooking`, `service_request`,
   `maintenance_issue`, `review`, `current_charges`), new repositories for
   each plus `stay_repository.dart` (check-in/current-charges/checkout/
   `currentStay()`); `reservation.dart` extended with the two new statuses
   and timestamps. `image_picker`/`qr_flutter` added to `pubspec.yaml`.
3. **UI** — `lib/features/stay/`: My Stay hub, food menu + cart + order
   status, activity catalog + booking form + my bookings, service request
   form + my requests, maintenance report + my issues, current charges,
   checkout, final invoice, review. QR code added to the confirmation and
   booking-detail screens (decorative — reception looks up the booking and
   taps Check In, nothing scans it back). Admin gets Check-In, Kitchen
   Orders, Service Requests, and Maintenance screens; staff get their own
   assigned-queue views of the latter three.
4. **Routing** — `/my-stay/*` customer routes, `/admin/check-in`+
   `/admin/kitchen-orders`+`/admin/service-requests`+`/admin/maintenance`
   (admin-only), `/staff/food-orders`+`/staff/service-requests`+
   `/staff/maintenance` (staff-or-above via the existing `/staff` gate).
   "My Stay" added to the customer nav unconditionally.
5. **Verification** — `supabase db reset && supabase test db`,
   `flutter analyze`, `flutter test`.

## Key design decision

Food/activities/services settle at **checkout**, not at booking time.
`get_quote`/`create_hold`/`confirm_booking` are completely untouched —
every extra is priced and recorded independently, and `current_charges`
computes the running total fresh on every call. This matches how the
source document's own checkout section describes billing ("food,
activities and services are included in the final bill... customer pays
remaining balance") and avoids touching the most heavily-tested code path
in the app.

## Result

All eight migrations and their pgTAP tests pass. The only test failures
remaining are the same pre-existing, environment-level anon-ACL issue
already documented in the Owner Flow spec (affects every table equally,
RLS still correctly hides data), plus one unrelated pre-existing failure
in `14_ical_test.sql` (`net._http_response` does not exist locally).
`flutter analyze` is clean.
