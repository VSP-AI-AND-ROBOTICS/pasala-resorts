> Superseded by 2026-09-24-resorthub-tenancy-design.md

# Pasala Resorts — Single-Property Onboarding & Occasion Design

Date: 2026-08-13
Builds on: `2026-08-12-farmhouse-ui-redesign-design.md` (photo/logo/animation redesign)
Status: approved by user in brainstorming session; ready for implementation planning

## 1. What This Is

The previous redesign restyled every customer-facing screen with the real
Pasala Farm House photos and logo, but the app underneath still models a
multi-property catalog seeded with two fictional placeholder farmhouses
("Pasala Riverside", "Pasala Hilltop") predating those real photos, and the
customer flow starts cold on a login form with no branded entry sequence.

This change does four things, in dependency order:

- **(A)** Replaces the placeholder seed data with the one real property
  (backend: migration-adjacent seed change + a pgTAP test rewrite).
- **(B)** Adds a free-text "occasion" note to the booking flow (backend:
  new migration + RPC parameter; frontend: one new field, two new display
  sites).
- **(C)** Adds a dedicated branded splash screen and a Sign In / Sign Up
  chooser screen ahead of the existing login/signup forms.
- **(D)** Makes a signed-in customer land directly on the one property's
  detail page instead of a list screen.

(B), (C), and (D) are independent of each other but (D) and parts of (B)'s
testing depend on (A)'s single-property seed data existing first — hence
one plan, executed in this order, rather than four separate spec cycles.

## 2. Scope

**In scope:** `supabase/seed.sql`, one new migration, `create_hold`'s
signature, `lib/data/models/reservation.dart`, `lib/core/router.dart`,
`lib/features/browse/browse_screen.dart`, `lib/features/booking/
booking_screen.dart`, `lib/features/account/booking_detail_screen.dart`,
`lib/features/booking/confirmation_screen.dart`, two new screens (splash,
auth chooser), and `supabase/tests/10_reports_test.sql`.

**Out of scope:** admin/staff/accountant screens, the payment gateway seam,
coupon/refund/advance-balance logic, iCal sync, the outbox — none of these
are touched by adding one text field and changing which screen a customer
lands on. The prior redesign's shared widgets (`HeroBackdrop`, `BrandMark`,
`StaggeredFadeIn`, `AppSplashOverlay`, extended `EmptyState`) are reused,
not re-designed.

## 3. Backend Changes

### 3.1 Seed data replacement

`supabase/seed.sql`: remove the `Pasala Riverside` (`a0000000-...-01`) and
`Pasala Hilltop` (`a0000000-...-02`) property rows and every unit/rate-rule
row that references them. Insert one `Pasala Farm House` property, with
units named after the real photographed cottage rows: Dallas, Las Vegas,
New York, Boston, Detroit, Miami — following the same column shape
(amenities, check-in/out times, rate rules) the removed rows already used,
so no other part of the seed file's structure changes.

### 3.2 `occasion` field

New migration `supabase/migrations/0020_reservation_occasion.sql`:

- `alter table public.reservations add column occasion text;` — nullable,
  no default beyond `null`, no constraint (a blank occasion is not an
  error state, it's the common case).
- `create or replace function public.create_hold(...)` gains one new
  parameter, `p_occasion text default null`, appended after the existing
  `p_coupon_code` parameter (so every existing caller that doesn't pass it
  keeps working unmodified), and the function's `insert into
  public.reservations (...)` gains `occasion` in its column and value
  lists, set to `p_occasion`.
- No RLS or grant changes: `occasion` is just another column on a table
  customers already reach exclusively through this `security definer` RPC.

### 3.3 `10_reports_test.sql` rewrite

This file currently proves `report_revenue`/`report_occupancy` don't leak
one property's figures into another's by inserting fixture bookings under
the real seeded Riverside/Hilltop properties. With those rows gone, the
file inserts its own two throwaway properties (its own UUIDs, own units,
own bookings) inline at the top of the test, and the rest of the file's
assertions are otherwise unchanged — the guarantee being tested (per-
property scoping) has nothing to do with what the app's real seed data
looks like, so decoupling the test from it is a correctness improvement,
not just a workaround.

## 4. New Screens

### 4.1 Splash screen

`lib/features/splash/splash_screen.dart` (new): the first route the app
shows. Reuses `HeroBackdrop` with the `entrance_gate_night` photo (bundled
but unused since the prior redesign round) and `BrandMark` centered over
it. After a brief delay (built from `PasalaTokens.motionBase`, the same
token family every other timing in this app uses), it navigates to the new
auth chooser screen. This is a distinct screen from `AppSplashOverlay`
(the existing cold-start flash layered via `MaterialApp.router`'s
`builder`) — that overlay is a very brief branding flash on top of
whatever screen loads first; this is a real, dedicated first screen in the
navigation stack. Both exist; they serve different moments.

### 4.2 Auth chooser screen

`lib/features/auth/welcome_screen.dart` (new): also built on `HeroBackdrop`
+ `BrandMark`, with two actions — "Sign In" (`FilledButton`, navigates to
`/login`) and "Sign Up" (`OutlinedButton`, navigates to `/signup`). The
existing `login_screen.dart`/`signup_screen.dart` are unchanged, including
their own mutual "Create an account" / "Already have an account" links —
a signed-out user can still deep-link directly to either.

### 4.3 Router changes

`lib/core/router.dart`:

- Add `/splash` and `/welcome` as top-level routes (same shape as `/login`
  and `/404` — outside the `ShellRoute`, using the existing `fadeSlidePage`
  transition helper).
- Change `GoRouter`'s `initialLocation` from `/` to `/splash`.
- `redirectFor`'s signed-out branch currently reads:
  `if (user == null) return loggingIn ? null : '/login';` — this must also
  let `/splash` and `/welcome` through unredirected for a signed-out user,
  the same way `/login`/`/signup` already are via the `loggingIn` flag.
  Concretely: the check broadens from "is this `/login` or `/signup`" to
  "is this one of the four pre-auth screens" (`/splash`, `/welcome`,
  `/login`, `/signup`), all four exempted from the forced `/login` bounce.
- `landingPathFor` and every other branch of `redirectFor` (admin/staff
  path gating) are unchanged — this only affects where a signed-out user
  is allowed to sit before authenticating.

### 4.4 Home behavior (single-property landing)

No router redirect is added for this — the router change in 4.3 is only
about the pre-auth screens. Instead, `lib/features/browse/
browse_screen.dart`'s existing `data: (list) => ...` branch gets one new
check: if `list.length == 1`, schedule (via a post-frame callback, so it
doesn't happen mid-build) `context.go('/property/${list.single.id}')`
instead of rendering the grid/list, showing a brief loading state in the
meantime. `landingPathFor` keeps sending every customer to `/` unchanged.
If a second property is ever seeded, this same code path stops
redirecting and falls through to the existing grid/list rendering
automatically — no hardcoded property ID anywhere, and no route that
becomes wrong the day a second property exists.

## 5. Booking Flow — the "occasion" Field

- `lib/features/booking/booking_screen.dart`: one new `TextEditingController`
  (`_occasion`), rendered as an optional text field ("Occasion (optional)",
  helper text along the lines of "Tell us what you're celebrating") in the
  same step as the existing guest-count stepper.
- `HoldParams` (the record identifying "what a hold was created for") gains
  an `occasion` field, included in its equality/hash exactly like
  `couponCode` and `guests` are today — so editing the occasion field while
  a hold is already active flows through the exact same `_applyChange` path
  guest-count changes already use, not a new state transition. Unlike
  guests, an occasion change never touches `get_quote` or the displayed
  price — it's metadata, not a pricing input.
- `HoldActions.createHold` (and the underlying repository call to
  `create_hold`) passes `occasion: params.occasion` through to the new
  `p_occasion` RPC parameter from Section 3.2.
- `lib/data/models/reservation.dart`: new nullable `occasion` field, parsed
  from the RPC/row response the same way `blockReason`/`cancelReason`
  already are (a plain nullable string read from the JSON map).
- Display: `confirmation_screen.dart`'s `_Confirmed` widget shows a line
  ("For: <occasion>") under the stay dates only when
  `reservation.occasion` is non-empty. `booking_detail_screen.dart` gets
  the identical conditional line in its own detail list. Nothing renders
  when occasion is null or blank — this is not a required field and must
  never look like one.
- No changes to `MockGateway`, `RazorpayGateway`, or the payment step —
  occasion is booking metadata captured before payment, not a payment
  concern, and doesn't affect the advance/balance split.

## 6. Testing

- **pgTAP**: a test (either appended to the existing reservations test file
  or a new one alongside the migration) confirms `create_hold` accepts and
  persists `p_occasion`, and that a caller omitting it still gets `null`
  stored — proving the parameter is backward compatible with every
  existing caller. `10_reports_test.sql` is re-run against its rewritten
  self-contained fixtures (Section 3.3) and must still pass with the same
  per-property-scoping guarantee it proved before.
- **Flutter widget tests**:
  - New: `SplashScreen` shows the brand mark and background and navigates
    onward after its delay.
  - New: the auth chooser screen's two buttons navigate to `/login` and
    `/signup` respectively.
  - `BrowseScreen`'s existing test file gains a single-property case
    (asserts the resulting `GoRouter` location is `/property/<id>`, not a
    rendered list) alongside its current multi-property grid/list cases,
    which remain as regression coverage for if a second property is ever
    added.
  - `booking_screen.dart`'s existing suite (`hold_lifecycle_test.dart` and
    siblings) gets the occasion field's presence, optionality, and
    pass-through into `createHold` asserted, without altering any existing
    hold/payment assertion.
  - `confirmation_screen_test.dart` and the booking-detail test gain one
    occasion-shown and one occasion-absent case each.
- **Manual walkthrough**: against a freshly reset local stack
  (`supabase db reset`, which picks up the new seed data and migration),
  walk the full path end-to-end: splash → chooser → sign in → land
  directly on Pasala Farm House → book a unit with an occasion note → pay
  → confirmation shows the occasion → My Bookings / booking detail shows
  it too.
- **Known baseline carried forward**: the three pre-existing
  `hold_lifecycle_test.dart` failures noted during the prior redesign round
  (a `pay-button` key finder issue, unrelated to styling) are re-confirmed
  as still present and still unrelated — not silently folded into this
  change's definition of "done," and not something this change is expected
  to fix.

## 7. Explicitly Deferred

- A picklist-style occasion selector (fixed categories like
  Birthday/Anniversary/Corporate) was considered and rejected in favor of
  free text — no category taxonomy to design or maintain.
- Persisting occasion anywhere admin-editable (e.g., letting staff amend it
  after booking) is not part of this change — it's captured once at
  booking time, the same as guest count is today before a hold exists.
- Re-supporting multiple properties in the customer-facing flow is not
  removed capability-wise (Section 4.4's redirect is self-correcting), but
  no UI is added in this change to let a customer switch between
  properties, since there is exactly one.
