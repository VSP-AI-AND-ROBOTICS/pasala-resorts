# Pasala Resorts — Single-Page Booking Design

Date: 2026-08-18
Builds on: `2026-08-13-single-property-onboarding-design.md` (single-property
onboarding, occasion note)
Status: approved by user in brainstorming session; ready for implementation
planning

## 1. What This Is

The property page currently lists the farmhouse's units as tappable cards;
tapping one navigates to a separate booking screen (dates → guests → price →
pay) at `/book/:unitId`. With the property already collapsed to a single
bookable entity (the prior onboarding change), the per-unit list and the
extra navigation step are unnecessary indirection: there is exactly one
thing to book, and the customer should see the booking controls on the same
page as the property's photos and amenities, with no tap-through step.

This change does three things:

- **(A)** Merges the booking screen's content directly into the property
  page — no more separate route, no more unit list.
- **(B)** Collapses the six seeded cottage units into one whole-property
  unit, "Pasala Farm House".
- **(C)** Updates the one other place that navigated to the now-retired
  booking route (resuming a live hold from My Bookings).

## 2. Scope

**In scope:** `lib/features/booking/booking_screen.dart` (structural change
only — no state-machine logic touched), `lib/features/browse/
property_screen.dart`, `lib/core/router.dart`, `lib/features/account/
my_bookings_screen.dart`, `supabase/seed.sql`, and the tests that
directly exercise any of these.

**Out of scope:** the booking state machine itself (hold timers, payment
retry, the two documented pre-existing races, `HoldParams`, `resolveSelectionChange`/`decideHoldAction`) — none of that logic changes, only where its
widget tree is mounted. Admin/staff screens, the payment gateway, coupons,
refunds, iCal, and the outbox are untouched.

## 3. Screen Merge

### 3.1 `BookingScreen` becomes embeddable

Today: `build()` returns `Scaffold(appBar: AppBar(title: ...), body:
unitAsync.when(...))`, and the `data` branch (`_buildBody`) wraps its
content in its own `SingleChildScrollView`. That scroll view exists
specifically because a plain `ListView` breaks the availability calendar's
shrink-wrapped `GridView` (documented in the code today) — a `Column` has
no such problem.

Change: `build()` drops the `Scaffold`/`AppBar` and returns the
`unitAsync.when(...)` result directly (unchanged loading spinner and
`FailureView` branches). `_buildBody` drops its own `SingleChildScrollView`,
returning the bare `Column` (unchanged `crossAxisAlignment` and every
section inside it). No other line in this file changes — the hold timer,
`_pay`, `_changeSelection`, `_applyCoupon`, and every existing test's
assertions about this widget's *behavior* are untouched; only its outermost
wrapper is removed.

### 3.2 `PropertyScreen` embeds it

- The outer container changes from `ListView(children: [...])` to
  `SingleChildScrollView(child: Column(children: [...]))` — for the same
  calendar-nesting reason `BookingScreen` itself already documents, now
  that the calendar lives on this page.
- The "Units" `SectionHeader`, the `UnitCard` class, and the `unitPhoto()`
  function are deleted — there is no longer a list to render.
- The existing `unitsProvider(propertyId)` fetch stays (via the existing
  `AsyncView`, keeping its loading/error/empty handling), but its result is
  now used only to obtain the single unit: `units.single`. Its id is passed
  straight into an embedded `BookingScreen(unitId: unit.id)`, appended
  directly after the amenities section.

Page order, top to bottom: photo gallery → name/address/description/
amenities → the booking flow (dates → guests/occasion → price → pay),
exactly as requested — no separate screen, no tap-through.

## 4. Routing & Resume-Hold

- `lib/core/router.dart`: the `GoRoute(path: '/book/:unitId', ...)` entry is
  deleted.
- `lib/features/account/my_bookings_screen.dart`: the hold-resume tap
  target changes from `context.go('/book/${reservation.unitId}')` to
  `context.go('/')`. Browse's existing single-property auto-redirect
  (already built and tested in the prior onboarding change) sends the
  customer straight to the property page. Re-picking the same dates there
  flows through the exact same `resolveSelectionChange`/`decideHoldAction`
  machinery that already reuses a live hold instead of erroring — nothing
  about hold-reuse semantics changes, only the path that gets them back to
  a screen where they can re-pick dates.
- Doc comments in `catalog_repository.dart`, `booking/providers.dart`, and
  `calendar/providers.dart` that reference `/book/:unitId` as context are
  updated to describe the new embedding instead, as part of touching those
  files' surrounding code — not a functional change.

## 5. Seed Data — One Unit

`supabase/seed.sql`'s six units (Dallas, Las Vegas, New York, Boston,
Detroit, Miami) are replaced by one: **"Pasala Farm House"**, capacity
20–40, `nightly` booking mode, id reusing the first cottage's existing
UUID (`b0000000-...-0001`) so the smallest possible diff touches downstream
fixture rows. Its own base/weekend/Diwali rate ladder replaces the six
per-cottage rate rows (same derivation pattern: weekend = base × 1.4,
Diwali override = base × 1.8, same priorities as before). The two fixture
reservations (one confirmed booking, one admin block) are remapped to this
single unit id instead of the two cottage ids they referenced before.

## 6. Testing

- `test/features/booking/hold_lifecycle_test.dart`: its own throwaway test
  router wraps `BookingScreen(...)` in a `Scaffold(body: ...)` itself
  (matching the pattern it already uses for its confirmation-screen stub
  route), since the real widget no longer supplies one. No test assertion
  changes — every existing test in this file continues verifying the same
  hold/payment/race behavior it does today.
- `test/features/browse/property_screen_widget_test.dart`: the
  unit-card-photo test is removed (that UI no longer exists); a new test
  confirms the booking flow's occasion field and guest stepper render
  directly on the property page once the property and its single unit
  resolve.
- `test/features/browse/property_card_test.dart` /
  `property_screen_test.dart`: the `unitPhoto` tests are removed along with
  the function.
- `supabase test db`, `flutter test`, and `flutter analyze` all run clean
  at the end, per this project's established verification standard. The
  three pre-existing, unrelated `hold_lifecycle_test.dart` failures (a
  `pay-button` key-finder issue, present since before this project's
  redesign work began) are expected to remain exactly those three.

## 7. Explicitly Deferred

- No admin UI changes for managing "one unit vs many" — an admin can still
  add more units directly in the database if the business ever needs to.
  Unlike the prior property-level redirect, this change does not add
  auto-detection for a second unit: `units.single` assumes exactly one and
  is not designed to gracefully expand back into a list. Restoring a
  unit-list UI, if ever needed, is a deliberate follow-up change, not
  something this code self-corrects into.
- No change to how `capacity_base`/`capacity_max` drive guest-count limits
  in the booking flow's stepper — the existing logic already reads these
  off whichever unit it's given, so the new unit's 20–40 range flows
  through unchanged.
