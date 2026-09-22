# Pasala Resorts — Farmhouse UI Redesign

Date: 2026-08-12
Builds on: `2026-07-30-pasala-phase2-design.md` (phase 2 UI/UX overhaul)
Status: approved by user in brainstorming session; ready for implementation planning

## 1. What This Is

Phase 2 gave the app a real design system (colour roles, type scale, spacing,
motion tokens) but no imagery beyond property/unit photos already stored in
the database. This change makes the app visually match the real property —
Pasala Farm House — using the owner's own photos and a real brand logo,
across the customer-facing screens. It is a presentational change only:
no provider, repository, routing, pricing, or Postgres-facing logic changes.

## 2. Scope

**In scope:** login, signup, the app shell's brand mark, browse, property
detail, booking flow chrome (styling only), booking confirmation, and my
bookings — i.e. every screen a customer sees.

**Out of scope:** admin, staff, accountant, and super-admin screens
(dashboard, reports, properties/units/rate-rule management, outbox, OTA
sync, user management). These stay on the current phase-2 styling. Also out
of scope: any change to `lib/data/`, `lib/features/*/providers.dart`, Riverpod
providers, `go_router` route definitions/redirects, Supabase queries/RPCs, or
the booking/hold/payment state machine in `booking_screen.dart`.

## 3. Asset Inventory

Source folder: `C:\pasala images\` (owner-supplied). Copied into
`assets/images/` under descriptive names and declared in `pubspec.yaml`.

| Source file | Renamed asset | Content | Usage |
|---|---|---|---|
| `1.jpg` | `logo_mark.jpg` | Gold mandala emblem + "PASALA RESORTS" wordmark on deep-green background | Splash brand moment, app-bar brand mark, overlay mark on login/signup |
| `10.png` | `hero_night_aerial.png` | Cinematic night/rain aerial shot, resort lit up, signage visible | Login & signup full-bleed background |
| `5.webp` | `hero_day_aerial.webp` | Aerial daytime shot of the pool courtyard | Browse screen header hero |
| `2.webp` | `cottages_pool_row.webp` | Daytime pool + themed cottage row | Property card / detail imagery rotation |
| `3.webp` | `cottages_dallas_vegas.webp` | Dallas/Las Vegas/New York themed cottage row | Property card / detail imagery rotation |
| `4.webp` | `cottages_boston_detroit.webp` | Boston/Miami/Detroit themed cottage row | Property card / detail imagery rotation |
| `9.webp` | `event_string_lights.webp` | Event/wedding string-lights setup | Booking confirmation background |
| `7.webp` | `facade_daytime.webp` | Daytime facade + playground | My Bookings empty state illustration |
| `8.webp` | `patio_firepit_night.webp` | Night patio + fire pit | Held in reserve, not wired to a screen in this phase |
| `6.webp` | `entrance_gate_night.webp` | Night entrance gate, backlit sign | Held in reserve, not wired to a screen in this phase |

The two "held in reserve" images are copied in and declared as assets so a
follow-up change can use them without another asset-handling round, but
nothing in this phase's screens references them. This is not scope creep —
declaring an unused asset costs nothing at runtime — but no screen may be
built around them without a new decision.

The properties/units table's own `image_url` data (surfaced today via
`PropertyMedia`'s `Image.network` + tinted-placeholder fallback) is
completely untouched. This phase only adds the app's own chrome imagery
alongside it.

## 4. Shared Components & Theme Changes

- **`lib/core/theme/app_assets.dart`** (new): a token class listing every
  bundled image path (`AppAssets.heroNightAerial`, `AppAssets.logoMark`,
  etc.) so no screen hardcodes a string path.
- **`lib/core/theme/tokens.dart`**: add `displayFontFamily` (defaults to the
  platform font family — no bundled font file was provided — with tuned
  letter-spacing/weight applied only in `app_theme.dart`'s headline/title
  styles) and promote the `840`-wide breakpoint currently inlined in
  `AppShell` into a shared `PasalaTokens.wideBreakpoint` constant.
- **`lib/core/theme/app_theme.dart`**: headline/title text styles get the
  display treatment (larger, tighter tracking, heavier weight); body text
  styles are untouched.
- **`lib/core/widgets/hero_backdrop.dart`** (new): `HeroBackdrop` widget —
  full-bleed `Image.asset` + bottom-weighted gradient scrim + a content slot.
  Used by login, signup, and confirmation so the scrim/gradient logic lives
  in one place instead of being duplicated three times.
- **`lib/core/widgets/brand_mark.dart`** (new): renders `logo_mark.jpg` at a
  couple of standard sizes (splash-size, app-bar-size), wrapped in
  `Semantics(label: 'Pasala Resorts')` since it's a meaningful image, not
  decorative.
- **`lib/core/widgets/empty_state.dart`**: extended with an optional `image`
  parameter (an `AssetImage` shown above the existing icon/title/message)
  so `EmptyState` can carry the My Bookings illustration without a fork.
- **A splash moment**: on top of Flutter's existing native launch screen, a
  brief in-app branded moment (`BrandMark` fade-in, ~600ms via
  `AnimatedOpacity`, using `PasalaTokens.motionBase`) the first time the
  router resolves post-auth-check. No new package, no change to the
  auth-check logic itself — purely a widget wrapped around the existing
  resolution point.

None of the above touches `lib/data/`, any `providers.dart`, `router.dart`'s
redirect logic, or any Supabase-calling code.

## 5. Screen-by-Screen Changes

**Login / Signup** (`lib/features/auth/login_screen.dart`,
`signup_screen.dart`)
`HeroBackdrop` with `hero_night_aerial.png` full-bleed, `BrandMark` (~96px)
centered above the heading text. The form itself sits in a
`surfaceContainerLow`-tinted, rounded, elevated panel floating over the
image — never directly on the photo — so text contrast doesn't depend on
hardcoded white-on-photo colors. The panel fades and slides up on screen
entry. All existing `Form`/`TextFormField`/validation/`_submit()` logic is
unchanged; only the `Scaffold.body` composition around it changes.

**App shell** (`lib/features/shell/app_shell.dart`)
The app-bar's `Text('Pasala Resorts')` becomes `BrandMark` at app-bar size
(small logo image beside the wordmark text — the emblem alone reads as
abstract at 24px). Navigation rail/bottom bar, role-based destination lists,
and sign-out button are unchanged.

**Browse** (`lib/features/browse/browse_screen.dart`)
A `HeroBackdrop` header (`hero_day_aerial.webp`, ~200px tall, "Discover your
stay" overlay title) above the property list. `PropertyCard` gets rounder
corners consistent with updated radius tokens, a hover elevation/scale
effect on web/desktop (`MouseRegion` + `AnimatedScale`), and a staggered
fade-in as cards build (`TweenAnimationBuilder`, small per-index delay,
capped so a long list doesn't stagger for seconds). On wide layouts
(`>= PasalaTokens.wideBreakpoint`), cards lay out in a 2-column grid instead
of a single column. `PropertyMedia`'s existing `Image.network` +
placeholder-fallback logic is untouched — only the chrome around it changes.

**Property detail** (`lib/features/browse/property_screen.dart`)
The header media area gets a `Hero` tag matching the tapped `PropertyCard`'s
image, producing a shared-element transition from Browse. `UnitCard` styling
brought in line with the new card language (same radius/elevation as
`PropertyCard`).

**Booking flow** (`lib/features/booking/booking_screen.dart`,
`quote_sheet.dart`)
Styling-only pass: card/button chrome updated to match new tokens. No
changes to the state machine, hold-timer logic, selection-change handling,
or either of the two documented pre-existing races (rapid-tap interleaving,
same-priority rate-rule ranking) — this file's logic is not touched beyond
what's needed to apply visual tokens.

**Confirmation** (`lib/features/booking/confirmation_screen.dart`)
`HeroBackdrop` using `event_string_lights.webp` behind the existing success
card. The checkmark icon gets a scale+fade "pop" entrance animation.

**My Bookings** (`lib/features/account/my_bookings_screen.dart`)
Empty state passes `facade_daytime.webp` into the extended `EmptyState`'s
new `image` parameter instead of relying on the icon alone. List rows
(`BookingTile`) get the same staggered fade-in as `PropertyCard`.

**Account**: there is no separate account screen in this codebase — account
management is covered by My Bookings plus the sign-out action already in the
app shell's app bar. No new screen is created.

## 6. Animation Strategy

All vanilla Flutter APIs — no new pub.dev dependencies. All animations are
purely presentational; none introduce new interaction state or new
in-flight-request handling, so none can create a new race beyond the two
already documented in `README.md`.

- **Screen transitions**: a custom `PageRouteBuilder` (fade + slight
  slide) applied at the router level for customer-facing routes only,
  replacing the default Material transition.
- **List entrance**: `TweenAnimationBuilder` with a per-index delay offset
  (capped) for `PropertyCard` and `BookingTile`.
- **Shared element**: `Hero` wrapping `PropertyMedia` between `PropertyCard`
  and `PropertyScreen`'s header image.
- **Micro-interactions**: `AnimatedScale`/`AnimatedOpacity` for button press
  and card hover states; `AnimatedOpacity` for the splash brand-mark and the
  confirmation checkmark.
- All durations use the existing `PasalaTokens.motionFast` (150ms) /
  `motionBase` (250ms) constants — no new arbitrary duration values.

## 7. Responsive Strategy

Reuses the `840`-wide breakpoint already established in `AppShell`,
promoted to `PasalaTokens.wideBreakpoint` so it's defined once and consumed
by both `AppShell` and the new responsive behaviour below:

- `HeroBackdrop` height scales up on wide/web layouts.
- Browse's `PropertyCard` list becomes a 2-column `GridView` at
  `wideBreakpoint` and above, single column below it.
- Login/signup panels keep their existing 420px max-width constraint on all
  sizes.

## 8. Testing & Verification

- `flutter analyze` and `flutter test` run after each screen's changes.
  Existing widget tests for login, signup, and browse are checked for
  finders that assume the current literal layout (e.g. a test locating the
  app-bar title via `find.text('Pasala Resorts')` would break once that
  becomes a `BrandMark` widget) and updated to find the new structure rather
  than being weakened.
- Manual verification via `make run-web` of the full customer path: login →
  signup → browse → property detail → booking flow start → confirmation →
  my bookings, checked at both a narrow (phone-width) and wide (desktop)
  viewport.
- No backend/database change in this phase, so `supabase test db` is not
  re-run as part of this work.

## 9. Explicitly Deferred

- Admin/staff/accountant screen restyling (out of scope, see Section 2).
- A bundled custom display font — no font file was supplied; the platform
  font is used with tuned typographic treatment instead. Adding a real font
  file is a follow-up if one is provided later.
- `patio_firepit_night.webp` and `entrance_gate_night.webp` are bundled but
  not wired into any screen (Section 3) — available for a future change,
  not part of this one.
