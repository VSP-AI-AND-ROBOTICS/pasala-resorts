# Pasala Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the delivered booking core into a presentable product with the revenue and operations features that do not require a third-party account — a real design system, reports, coupons, refunds, a notification outbox, and iCal OTA sync.

**Architecture:** Unchanged from phase 1 and deliberately so. Business logic lives in Postgres behind `SECURITY DEFINER` RPC with RLS and an explicit grant beside every policy; Flutter is a thin client whose widgets never import the Supabase SDK and never perform arithmetic on money. Everything new follows those rules. External providers are reached only through interfaces whose default implementation is honest about not being configured.

**Tech Stack:** Flutter 3.38.9 / Dart 3.10.8, Riverpod 3.3.2, go_router, supabase_flutter 2.16.0, Postgres 17 with `btree_gist` and `pg_cron`, pgTAP.

**Spec:** `docs/superpowers/specs/2026-07-30-pasala-phase2-design.md`

## Global Constraints

- Delivered phase 1 state that must keep passing: **134 pgTAP assertions across 9 files**, **180 Flutter tests**, `flutter analyze` clean, Android/iOS/web all building.
- Widgets never import `package:supabase_flutter`. Repositories in `lib/data/repositories/` are the boundary.
- **No arithmetic on money in Dart.** Coupons, refunds, advances and report figures are computed in SQL and displayed verbatim.
- Every table gets an explicit `grant` beside its RLS policies. A policy without a grant fails closed at 42501 and never runs.
- Every new RPC is `SECURITY DEFINER` with `set search_path = public, pg_temp`, and takes caller identity from `auth.uid()`.
- Every new SQLSTATE raised in SQL is added to `mapPostgrestError` in `lib/core/errors.dart` in the same task, with a test.
- pgTAP role discipline: `request.jwt.claims` does not change the effective Postgres role. Pair `set local role authenticated|anon` with the claims line, and switch back after any `set local role postgres`. Assert absence with out-of-band counts, not `throws_ok('42501')` — 42501 comes from the grant layer or a WITH CHECK violation.
- Use `is distinct from`, never `<>`, when either side can be NULL. Two production defects in phase 1 came from this.
- **The product may never misrepresent its own state.** An unsent notification says unsent. A mock payment is never labelled paid. A stubbed integration is never described as connected.
- Riverpod 3.3.2 exposes `AsyncValue.value`, not `valueOrNull`.
- Screens surface `BookingFailure` through `FailureView.messageFor`, including in `SnackBar`s.
- TDD: failing test first, run it, watch it fail for the right reason, then implement.
- Commit at the end of every task with the message given in the task.

## File Structure

**Database** (`supabase/migrations/`)
- `0011_design_tokens_seed.sql` — property/unit image seed data for the UI work.
- `0012_coupons.sql` — `coupons`, `coupon_redemptions`, `get_quote` coupon support.
- `0013_refund_policy.sql` — `refund_rules`, `compute_refund`, cancellation recording.
- `0014_advance_policy.sql` — advance/balance split on `confirm_booking`.
- `0015_reports.sql` — reporting views and RPC.
- `0016_outbox.sql` — `outbox`, templates, transition triggers.
- `0017_ical.sql` — `ical_feeds`, import staging, conflict recording.

**Flutter**
- `lib/core/theme/` — `tokens.dart`, `app_theme.dart`, `spacing.dart`.
- `lib/core/widgets/` — shared presentational widgets (`failure_view.dart` exists).
- `lib/features/reports/`, `lib/features/coupons/`, `lib/features/outbox/`, `lib/features/ota/` — new feature folders following the existing convention.
- `lib/data/models/` and `lib/data/repositories/` — one model and one repository per new aggregate.

Workstreams are ordered so that each is independently shippable: if the night runs short, an unstarted workstream costs nothing already built.

---

### Task 1: Design tokens and theme

**Files:**
- Create: `lib/core/theme/tokens.dart`, `lib/core/theme/spacing.dart`
- Modify: `lib/core/theme/app_theme.dart`
- Test: `test/core/theme/tokens_test.dart`

**Interfaces:**
- Produces: `PasalaTokens` (colour roles, radii, durations), `Spacing` (`xs` 4, `sm` 8, `md` 16, `lg` 24, `xl` 32, `xxl` 48), and `buildTheme(Brightness)` returning a fully configured `ThemeData`. Every later UI task consumes these and introduces no literal colours, radii or paddings of its own.

- [ ] **Step 1: Write the failing test**

`test/core/theme/tokens_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/tokens.dart';

double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final l1 = lum(a), l2 = lum(b);
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('body text on surface passes WCAG AA in both brightnesses', () {
    for (final brightness in Brightness.values) {
      final scheme = buildTheme(brightness).colorScheme;
      expect(_contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(4.5),
          reason: 'onSurface/surface failed for $brightness');
      expect(_contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5),
          reason: 'onPrimary/primary failed for $brightness');
    }
  });

  test('spacing scale is monotonic and starts at 4', () {
    const values = [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl];
    expect(values.first, 4.0);
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThan(values[i - 1]));
    }
  });

  test('theme applies the token radius to cards and buttons', () {
    final theme = buildTheme(Brightness.light);
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(PasalaTokens.radiusMd));
  });
}
```

Add `import 'dart:math' as math;` at the top.

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/theme/tokens_test.dart`
Expected: FAIL — `tokens.dart` does not exist.

- [ ] **Step 3: Write the tokens**

`lib/core/theme/spacing.dart`:

```dart
/// The only spacing values this app uses. A widget that needs a gap picks
/// one of these; it does not invent a number.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}
```

`lib/core/theme/tokens.dart`:

```dart
import 'package:flutter/material.dart';

/// Design tokens for Pasala Resorts.
///
/// The palette is warm and land-facing rather than corporate blue: a deep
/// green for primary actions, a clay accent for highlights, and a bone
/// surface that photographs of the property sit on without fighting them.
abstract final class PasalaTokens {
  static const Color seed = Color(0xFF2E6B4F);
  static const Color accent = Color(0xFFC2703D);

  static const double radiusSm = 8;
  static const double radiusMd = 16;
  static const double radiusLg = 28;

  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionBase = Duration(milliseconds: 250);

  /// Minimum interactive size, per WCAG 2.5.5 and Material guidance.
  static const double minTapTarget = 48;
}
```

- [ ] **Step 4: Rewrite the theme**

`lib/core/theme/app_theme.dart` — replace the whole file:

```dart
import 'package:flutter/material.dart';

import 'spacing.dart';
import 'tokens.dart';

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: PasalaTokens.seed,
    brightness: brightness,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PasalaTokens.radiusMd),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, PasalaTokens.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, PasalaTokens.minTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.md,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
      ),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: Spacing.lg),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
      ),
    ),
  );
}
```

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `flutter test && flutter analyze`
Expected: all pass, analyze clean. If the contrast assertion fails, adjust the token colours until it passes — do NOT lower the threshold.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme test/core/theme
git commit -m "feat(ui): add design tokens, spacing scale, and a real theme"
```

---

### Task 2: Shared presentational widgets

**Files:**
- Create: `lib/core/widgets/empty_state.dart`, `lib/core/widgets/loading_state.dart`, `lib/core/widgets/section_header.dart`, `lib/core/widgets/async_view.dart`
- Test: `test/core/widgets/async_view_test.dart`

**Interfaces:**
- Consumes: `Spacing`, `PasalaTokens` (Task 1); `FailureView` (existing).
- Produces:
  - `EmptyState({required IconData icon, required String title, String? message, Widget? action})`
  - `LoadingState({String? message})`
  - `SectionHeader({required String title, String? subtitle, Widget? trailing})`
  - `AsyncView<T>({required AsyncValue<T> value, required Widget Function(T) data, Widget Function()? empty, VoidCallback? onRetry})` — the single place `AsyncValue` is unwrapped from here on. It renders `LoadingState` while loading, `FailureView` on error with the retry callback, `empty()` when supplied and the data is an empty `Iterable`, and `data(value)` otherwise.

- [ ] **Step 1: Write the failing test**

`test/core/widgets/async_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/widgets/async_view.dart';

void main() {
  Widget host(AsyncValue<List<String>> value, {Widget Function()? empty}) =>
      MaterialApp(
        home: Scaffold(
          body: AsyncView<List<String>>(
            value: value,
            empty: empty,
            data: (items) => Text('items:${items.length}'),
          ),
        ),
      );

  testWidgets('loading renders a progress indicator', (tester) async {
    await tester.pumpWidget(host(const AsyncValue.loading()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error renders the failure message, not the raw error', (tester) async {
    await tester.pumpWidget(host(
      AsyncValue.error(
        const UnknownFailure('permission denied for table reservations'),
        StackTrace.empty,
      ),
    ));
    await tester.pump();
    expect(find.textContaining('reservations'), findsNothing);
  });

  testWidgets('empty builder is used for an empty list', (tester) async {
    await tester.pumpWidget(host(
      const AsyncValue.data(<String>[]),
      empty: () => const Text('nothing here'),
    ));
    expect(find.text('nothing here'), findsOneWidget);
    expect(find.text('items:0'), findsNothing);
  });

  testWidgets('data builder is used for a non-empty list', (tester) async {
    await tester.pumpWidget(host(const AsyncValue.data(<String>['a', 'b'])));
    expect(find.text('items:2'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/widgets/async_view_test.dart`
Expected: FAIL — `async_view.dart` does not exist.

- [ ] **Step 3: Write the widgets**

`lib/core/widgets/loading_state.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/spacing.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: Spacing.md),
              Text(message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      );
}
```

`lib/core/widgets/empty_state.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// Shown when a query succeeded and returned nothing. Distinct from an
/// error: nothing is wrong, there is simply nothing yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: Spacing.md),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                message!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Spacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
```

`lib/core/widgets/section_header.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/spacing.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.lg, Spacing.md, Spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}
```

`lib/core/widgets/async_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'failure_view.dart';
import 'loading_state.dart';

/// The single place an [AsyncValue] is unwrapped in this app.
///
/// Centralising it means loading and error presentation cannot drift between
/// screens, and no screen can accidentally render a raw error object — the
/// error branch always goes through [FailureView], which strips server text
/// from an [UnknownFailure].
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.empty,
    this.onRetry,
    this.loadingMessage,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget Function()? empty;
  final VoidCallback? onRetry;
  final String? loadingMessage;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => LoadingState(message: loadingMessage),
        error: (error, _) => FailureView(error: error, onRetry: onRetry),
        data: (resolved) {
          if (empty != null && resolved is Iterable && resolved.isEmpty) {
            return empty!();
          }
          return data(resolved);
        },
      );
}
```

If `FailureView`'s constructor differs from `FailureView(error:, onRetry:)`, adapt the call rather than changing `FailureView` — read the file first.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `flutter test && flutter analyze`
Expected: all pass, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets test/core/widgets
git commit -m "feat(ui): add shared empty, loading, section and async-view widgets"
```

---

### Task 3: Rebuild the customer-facing screens on the design system

**Files:**
- Modify: `lib/features/browse/browse_screen.dart`, `lib/features/browse/property_screen.dart`, `lib/features/account/my_bookings_screen.dart`, `lib/features/account/booking_detail_screen.dart`, `lib/features/auth/login_screen.dart`, `lib/features/auth/signup_screen.dart`, `lib/features/shell/app_shell.dart`
- Test: `test/features/browse/property_card_test.dart` (existing, extend), `test/features/ui/responsive_test.dart` (new)

**Interfaces:**
- Consumes: `PasalaTokens`, `Spacing`, `AsyncView`, `EmptyState`, `SectionHeader` (Tasks 1–2).
- Produces: no new public API. Every modified screen renders through `AsyncView` and uses only token spacing.

The flows do not change. Phase 1 tested them and they work; this task changes how they look, not what they do. Every existing test must still pass without being edited — if one breaks, the change went too far.

- [ ] **Step 1: Write the failing test**

`test/features/ui/responsive_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/tokens.dart';

void main() {
  testWidgets('every interactive control meets the minimum tap target',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Column(
          children: [
            FilledButton(onPressed: () {}, child: const Text('Book')),
            OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
          ],
        ),
      ),
    ));

    for (final type in [FilledButton, OutlinedButton]) {
      final size = tester.getSize(find.byType(type));
      expect(size.height, greaterThanOrEqualTo(PasalaTokens.minTapTarget),
          reason: '$type is below the minimum tap target');
    }
  });
}
```

- [ ] **Step 2: Run it to make sure it fails or passes**

Run: `flutter test test/features/ui/responsive_test.dart`
Expected: PASS if Task 1's theme is applied correctly. This test guards Task 1's work against regression during the visual rewrite; if it fails, fix the theme before touching screens.

- [ ] **Step 3: Rebuild the browse screen**

`PropertyCard` becomes image-led. Read the current file first, then restructure so each card is: a 16:9 image area (`property.images.first` when present, otherwise a tinted placeholder carrying the property's initial), the name as `titleLarge`, the address as `bodyMedium` in `onSurfaceVariant`, an amenity `Wrap` limited to four chips with a `+N` overflow chip, and check-in/check-out as a single muted line. Wrap the list in `AsyncView` with an `EmptyState` reading `No properties yet` / `Ask an admin to add one.`

Image loading uses `Image.network` with a `loadingBuilder` showing a neutral box and an `errorBuilder` falling back to the placeholder — a broken image URL must never render a Flutter error box to a customer.

- [ ] **Step 4: Rebuild the remaining customer screens**

Apply the same treatment, keeping every widget key and every visible string that an existing test asserts on:
- `property_screen.dart`: a header image, description, amenity wrap, then a `SectionHeader('Units')` and one card per unit with capacity and mode.
- `my_bookings_screen.dart`: `AsyncView` + `EmptyState` reading `No bookings yet` / `Your stays will appear here.`
- `booking_detail_screen.dart`: group the stay, guests, price breakdown and actions into cards separated by `Spacing.lg`.
- `login_screen.dart` / `signup_screen.dart`: centre the form in a `ConstrainedBox(maxWidth: 420)`, add the property name as a heading, keep every field key.
- `app_shell.dart`: keep the rail/bar switch; apply token spacing.

- [ ] **Step 5: Run the whole suite**

Run: `flutter test && flutter analyze`
Expected: all 180+ tests pass with NO edits to existing test files. An existing test that now fails means a key or a string changed that should not have.

- [ ] **Step 6: Commit**

```bash
git add lib/features test/features/ui
git commit -m "feat(ui): rebuild customer screens on the design system"
```

---

### Task 4: Rebuild the booking flow and admin screens

**Files:**
- Modify: `lib/features/booking/booking_screen.dart`, `lib/features/booking/quote_sheet.dart`, `lib/features/booking/confirmation_screen.dart`, `lib/features/admin/*.dart`, `lib/features/staff/today_screen.dart`, `lib/features/calendar/availability_calendar.dart`
- Test: `test/features/booking/quote_sheet_test.dart` (existing, must still pass)

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: no new public API.

- [ ] **Step 1: Restructure the booking screen into visible steps**

The flow is already correct; make its structure legible. Render as a vertical sequence of numbered sections — `1 Dates`, `2 Guests`, `3 Price`, `4 Pay` — where a section that cannot yet be acted on is visibly muted rather than absent, so the customer can see what is coming. The hold countdown banner becomes a prominent, persistent surface using `colorScheme.tertiaryContainer`, with its resume and cancel actions as buttons rather than text.

Keep every widget key and every message string asserted by the existing booking tests. Run them continuously while working.

- [ ] **Step 2: Make the calendar legible**

`availability_calendar.dart` currently paints day cells in flat container colours. Give each state a distinct treatment that does not rely on colour alone, since colour-only encoding fails for colour-blind users: available is a plain surface, booked is a filled error-tone cell, blocked carries a diagonal hatch or an icon, on-hold carries a dashed outline, past is muted with reduced opacity. Keep the legend and extend it to match.

Do NOT change `statusFor` — it is pure, tested, and consumed by two other screens.

- [ ] **Step 3: Rebuild the admin screens**

`admin_home_screen.dart` becomes a card grid rather than a list of `ListTile`s. `units_screen.dart`, `rate_rules_screen.dart`, `block_dates_screen.dart`, `admin_bookings_screen.dart` and `today_screen.dart` each get `AsyncView`, an `EmptyState`, and token spacing. `today_screen.dart`'s three sections get `SectionHeader` with the count as a subtitle.

- [ ] **Step 4: Run the whole suite**

Run: `flutter test && flutter analyze`
Expected: all pass, no existing test edited.

- [ ] **Step 5: Verify on web at three widths**

Run `make run-web`, then confirm at 375, 768 and 1280 CSS pixels that no layout overflows and the navigation switches from bar to rail. Browser automation in this environment cannot focus Flutter-web text fields and clicks are unreliable — use deep-link navigation plus a localStorage session swap for signed-in views, and report which method verified what. Capture a screenshot at each width.

- [ ] **Step 6: Commit**

```bash
git add lib/features
git commit -m "feat(ui): rebuild booking, calendar, and admin screens on the design system"
```

---

### Task 5: Reports and dashboard — database

**Files:**
- Create: `supabase/migrations/0015_reports.sql`, `supabase/tests/10_reports_test.sql`

**Interfaces:**
- Produces:
  - `public.report_revenue(p_from date, p_to date, p_property_id uuid default null) returns table(day date, property_id uuid, bookings int, gross numeric, refunded numeric, net numeric)`
  - `public.report_occupancy(p_from date, p_to date, p_property_id uuid default null) returns table(unit_id uuid, unit_name text, nights_available int, nights_booked int, occupancy_pct numeric)`
  - `public.dashboard_summary() returns jsonb` with keys `today_revenue`, `month_revenue`, `occupancy_pct`, `upcoming_arrivals`, `cancellations_this_month`, `active_holds`
  - All three are `SECURITY DEFINER`, callable by staff and above only, raising P0008 otherwise.

- [ ] **Step 1: Write the failing test**

`supabase/tests/10_reports_test.sql`:

```sql
begin;
select plan(6);

select has_function('public','dashboard_summary','dashboard_summary() exists');
select has_function('public','report_revenue','report_revenue() exists');
select has_function('public','report_occupancy','report_occupancy() exists');

insert into auth.users (id, email)
values ('cccc0000-0000-0000-0000-000000000001','repcust@example.com'),
       ('cccc0000-0000-0000-0000-000000000002','repstaff@example.com');

update public.profiles set role = 'staff'
  where id = 'cccc0000-0000-0000-0000-000000000002';

-- a customer must not be able to read the business's numbers
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$select public.dashboard_summary()$$,
  'P0008', null, 'a customer cannot read the dashboard');

-- staff can
set local request.jwt.claims to
  '{"sub":"cccc0000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$select public.dashboard_summary()$$,
  'staff can read the dashboard');

select is(
  (select jsonb_typeof(public.dashboard_summary() -> 'month_revenue')),
  'number',
  'month_revenue is a number');

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `function public.dashboard_summary() does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/0015_reports.sql`:

```sql
-- Reporting is read-only and staff-gated. Every figure is computed here so
-- that no client ever performs arithmetic on money.

create function public.assert_staff()
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_staff_or_above() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;
end;
$$;

create function public.report_revenue(
  p_from        date,
  p_to          date,
  p_property_id uuid default null
) returns table (
  day         date,
  property_id uuid,
  bookings    int,
  gross       numeric,
  refunded    numeric,
  net         numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_staff();

  return query
  select
    (lower(r.period) at time zone p.timezone)::date as day,
    p.id,
    count(*)::int,
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status = 'confirmed'), 0),
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status = 'cancelled'), 0),
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status = 'confirmed'), 0)
  from public.reservations r
  join public.units u on u.id = r.unit_id
  join public.properties p on p.id = u.property_id
  where r.kind = 'booking'
    and r.quote is not null
    and (lower(r.period) at time zone p.timezone)::date between p_from and p_to
    and (p_property_id is null or p.id = p_property_id)
  group by 1, 2
  order by 1;
end;
$$;

create function public.report_occupancy(
  p_from        date,
  p_to          date,
  p_property_id uuid default null
) returns table (
  unit_id         uuid,
  unit_name       text,
  nights_available int,
  nights_booked    int,
  occupancy_pct    numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_span int := greatest((p_to - p_from), 1);
begin
  perform public.assert_staff();

  return query
  select
    u.id,
    u.name,
    v_span,
    coalesce((
      select sum(
        least(upper(r.period)::date, p_to)
        - greatest(lower(r.period)::date, p_from)
      )::int
      from public.reservations r
      where r.unit_id = u.id
        and r.kind = 'booking'
        and r.status = 'confirmed'
        and r.period && tstzrange(p_from::timestamptz, p_to::timestamptz, '[)')
    ), 0),
    round(
      coalesce((
        select sum(
          least(upper(r.period)::date, p_to)
          - greatest(lower(r.period)::date, p_from)
        )::numeric
        from public.reservations r
        where r.unit_id = u.id
          and r.kind = 'booking'
          and r.status = 'confirmed'
          and r.period && tstzrange(p_from::timestamptz, p_to::timestamptz, '[)')
      ), 0) * 100 / v_span, 1)
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.is_active
    and (p_property_id is null or p.id = p_property_id)
  order by u.name;
end;
$$;

create function public.dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_month_start date := date_trunc('month', v_today)::date;
begin
  perform public.assert_staff();

  return jsonb_build_object(
    'today_revenue', coalesce((
      select sum(net) from public.report_revenue(v_today, v_today)), 0),
    'month_revenue', coalesce((
      select sum(net) from public.report_revenue(v_month_start, v_today)), 0),
    'occupancy_pct', coalesce((
      select round(avg(occupancy_pct), 1)
      from public.report_occupancy(v_month_start, v_today)), 0),
    'upcoming_arrivals', (
      select count(*)::int from public.reservations
      where kind = 'booking' and status = 'confirmed'
        and lower(period) >= now()
        and lower(period) < now() + interval '7 days'),
    'cancellations_this_month', (
      select count(*)::int from public.reservations
      where kind = 'booking' and status = 'cancelled'
        and cancelled_at >= v_month_start),
    'active_holds', (
      select count(*)::int from public.reservations
      where status = 'hold' and hold_expires_at > now())
  );
end;
$$;

grant execute on function public.report_revenue    to authenticated;
grant execute on function public.report_occupancy  to authenticated;
grant execute on function public.dashboard_summary to authenticated;
```

Note the `net` column repeats `gross` for now because refunds do not exist until Task 7; Task 7 updates it to subtract `refund_amount` and adds an assertion. Leave the column in place so the report's shape does not change under the UI later.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: your 6 assertions pass and the existing 134 still pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0015_reports.sql supabase/tests/10_reports_test.sql
git commit -m "feat(db): add revenue, occupancy, and dashboard reporting"
```

---

### Task 6: Reports and dashboard — Flutter

**Files:**
- Create: `lib/data/models/report.dart`, `lib/data/repositories/report_repository.dart`, `lib/features/reports/dashboard_screen.dart`, `lib/features/reports/reports_screen.dart`, `lib/features/reports/providers.dart`, `lib/features/reports/csv_export.dart`
- Modify: `lib/core/router.dart`, `lib/features/admin/admin_home_screen.dart`
- Test: `test/data/report_test.dart`, `test/features/reports/csv_export_test.dart`

**Interfaces:**
- Consumes: the three RPCs from Task 5; `AsyncView`, `EmptyState`, `SectionHeader` (Task 2).
- Produces:
  - `DashboardSummary` with `num todayRevenue, monthRevenue, occupancyPct; int upcomingArrivals, cancellationsThisMonth, activeHolds`
  - `RevenueRow`, `OccupancyRow`
  - `ReportRepository.dashboard()`, `.revenue(from, to, propertyId)`, `.occupancy(from, to, propertyId)`
  - `String toCsv(List<List<String>> rows)` — RFC 4180 quoting
  - Routes `/admin/dashboard` and `/admin/reports`

- [ ] **Step 1: Write the failing tests**

`test/features/reports/csv_export_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/reports/csv_export.dart';

void main() {
  test('quotes fields containing a comma', () {
    expect(toCsv([['a', 'b,c']]), 'a,"b,c"\r\n');
  });

  test('escapes embedded quotes by doubling them', () {
    expect(toCsv([['say "hi"']]), '"say ""hi"""\r\n');
  });

  test('quotes fields containing a newline', () {
    expect(toCsv([['line1\nline2']]), '"line1\nline2"\r\n');
  });

  test('emits one CRLF-terminated record per row', () {
    expect(toCsv([['a'], ['b']]), 'a\r\nb\r\n');
  });
}
```

`test/data/report_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/report.dart';

void main() {
  test('parses the dashboard payload', () {
    final summary = DashboardSummary.fromJson(const {
      'today_revenue': 11500.00,
      'month_revenue': 234500.00,
      'occupancy_pct': 62.5,
      'upcoming_arrivals': 3,
      'cancellations_this_month': 1,
      'active_holds': 2,
    });

    expect(summary.todayRevenue, 11500.00);
    expect(summary.occupancyPct, 62.5);
    expect(summary.upcomingArrivals, 3);
  });

  test('treats a null money figure as zero, never as a crash', () {
    final summary = DashboardSummary.fromJson(const {
      'today_revenue': null,
      'month_revenue': 0,
      'occupancy_pct': 0,
      'upcoming_arrivals': 0,
      'cancellations_this_month': 0,
      'active_holds': 0,
    });

    expect(summary.todayRevenue, 0);
  });
}
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `flutter test test/data/report_test.dart test/features/reports/csv_export_test.dart`
Expected: FAIL — the URIs do not exist.

- [ ] **Step 3: Write the CSV encoder**

`lib/features/reports/csv_export.dart`:

```dart
/// RFC 4180 CSV. Excel and Google Sheets both accept CRLF records and
/// doubled quotes; anything looser corrupts a cell containing a comma,
/// which in this app means any address or property name.
String toCsv(List<List<String>> rows) {
  final buffer = StringBuffer();
  for (final row in rows) {
    buffer.write(row.map(_field).join(','));
    buffer.write('\r\n');
  }
  return buffer.toString();
}

String _field(String value) {
  final needsQuotes =
      value.contains(',') || value.contains('"') || value.contains('\n');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}
```

- [ ] **Step 4: Write the models and repository**

`lib/data/models/report.dart` holds `DashboardSummary`, `RevenueRow` and `OccupancyRow`, each with a `fromJson` that coerces money with `(json['x'] as num?) ?? 0` — a null figure renders as zero rather than throwing, because an empty period is normal.

`lib/data/repositories/report_repository.dart` follows the existing `_guard` pattern exactly: every call wrapped, every error rethrown through `mapPostgrestError`, a Riverpod provider at the bottom.

- [ ] **Step 5: Write the screens**

`dashboard_screen.dart`: a responsive grid of stat cards — revenue today, revenue this month, occupancy, upcoming arrivals, cancellations, active holds — each a `Card` with a label, a large figure via `formatInr` for money, and a muted caption. Wrap in `AsyncView`.

`reports_screen.dart`: a date-range picker defaulting to the current month, a property filter, a `SegmentedButton` choosing Revenue or Occupancy, a data table, and an Export CSV action that builds the rows with `toCsv` and shares them via `Share.shareXFiles` — add `share_plus` to `pubspec.yaml`. PDF export is explicitly deferred; the button must not exist rather than existing and failing.

Add both routes inside the `ShellRoute`, gated to admins by the existing redirect, and link them from `admin_home_screen.dart`.

- [ ] **Step 6: Run everything**

Run: `flutter test && flutter analyze`
Expected: all pass, clean.

- [ ] **Step 7: Commit**

```bash
git add lib test
git commit -m "feat(app): add admin dashboard and reports with CSV export"
```

---

### Task 7: Coupons

**Files:**
- Create: `supabase/migrations/0012_coupons.sql`, `supabase/tests/11_coupons_test.sql`
- Modify: `lib/core/errors.dart`, `lib/data/repositories/booking_repository.dart`, `lib/features/booking/booking_screen.dart`
- Test: `test/core/errors_test.dart`

**Interfaces:**
- Produces:
  - `coupons(id, code unique, kind coupon_kind, value numeric, valid_from, valid_to, max_redemptions, min_booking_value, customer_id, is_active, created_at)` where `coupon_kind` is `percent|fixed`
  - `coupon_redemptions(id, coupon_id, reservation_id unique, customer_id, amount numeric, redeemed_at)`
  - `get_quote(..., p_coupon_code text default null)` — an added trailing parameter, so existing calls keep working
  - `create_hold(..., p_coupon_code text default null)`
  - New SQLSTATEs: `P0010` coupon not found or inactive, `P0011` coupon expired, `P0012` coupon usage limit reached, `P0013` booking below the coupon minimum
  - Quote JSON gains `coupon` — either `null` or `{code, kind, value, discount}` — and `total` is net of the discount

- [ ] **Step 1: Write the failing test**

`supabase/tests/11_coupons_test.sql` — assert, at minimum: a percent coupon reduces the total by the right amount; a fixed coupon does the same; an expired coupon raises P0011; a coupon past `max_redemptions` raises P0012; a booking under `min_booking_value` raises P0013; an unknown code raises P0010; a coupon restricted to another customer raises P0010 for this one; and the discount is stored in the reservation's `quote`. Use worked numbers, e.g. base 10000 + 1500 cleaning with a 10% coupon gives a discount of 1150 and a total of 10350 — verify against the actual `get_quote` implementation rather than trusting this arithmetic, and if it differs, report which is right before changing either.

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `relation "public.coupons" does not exist`.

- [ ] **Step 3: Write the migration**

Create the enum, both tables, their grants and policies (customers may read only active coupons by exact code lookup; admins manage), then extend `get_quote` with the trailing `p_coupon_code` parameter. The discount applies to `subtotal + cleaning_fee`, is rounded to 2 decimal places, is never allowed to exceed the total, and is recorded in the returned JSON under `coupon`. `create_hold` passes the code through and records a `coupon_redemptions` row inside the same transaction as the hold, so a redemption cannot exist without a reservation.

Redemption counting must be race-safe: the `max_redemptions` check and the insert happen in one statement, or the check is enforced by a partial unique index rather than a read-then-write.

- [ ] **Step 4: Map the new error codes**

Add `P0010`–`P0013` to `mapPostgrestError` as `InvalidState` with the server message preserved, since these messages are customer-facing and safe. Add a test per code.

- [ ] **Step 5: Add the coupon field to the booking flow**

A text field above the quote sheet with an Apply action. On success the sheet re-renders showing a discount line and the new total. On failure the message is shown inline, the previous quote stays visible, and the customer can continue without the coupon.

- [ ] **Step 6: Run everything**

Run: `supabase db reset && supabase test db && flutter test && flutter analyze`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add supabase lib test
git commit -m "feat: add coupons applied server-side inside the quote"
```

---

### Task 8: Refund policy and the advance/balance split

**Files:**
- Create: `supabase/migrations/0013_refund_policy.sql`, `supabase/tests/12_refunds_test.sql`
- Modify: `supabase/migrations/0015_reports.sql` behaviour via a new migration, `lib/features/account/booking_detail_screen.dart`

**Interfaces:**
- Produces:
  - `refund_rules(id, property_id, min_days_before int, refund_pct numeric, created_at)` — the matching rule is the one with the greatest `min_days_before` not exceeding the actual days before check-in
  - `compute_refund(p_reservation_id uuid) returns jsonb` → `{days_before, refund_pct, refund_amount, rule_id}`
  - `cancel_booking` records `refund_amount` and `refund_pct` on the reservation
  - `confirm_booking` accepts an advance: the amount must be at least the property's advance minimum and at most the quoted total, replacing the current exact-total equality check
  - `properties` gains `advance_pct numeric not null default 100` — 100 preserves today's behaviour exactly

- [ ] **Step 1: Write the failing test**

`supabase/tests/12_refunds_test.sql` — assert: the default ladder (full over 7 days, 50% within 7, none within 48 hours) picks the right rule at 10 days, 5 days and 1 day before check-in; the computed amount matches the stored quote total times the percentage; cancelling records both the percentage and the amount; a property with no rules yields a zero refund rather than an error; and `confirm_booking` accepts an advance of exactly `advance_pct` of the total, rejects one below it with P0009, and rejects one above the total with P0009.

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `relation "public.refund_rules" does not exist`.

- [ ] **Step 3: Write the migration**

Include a seed of the default ladder for every existing property. `compute_refund` must use `is distinct from` wherever a NULL can appear, and must return a zero refund with a null `rule_id` when no rule matches, never NULL arithmetic.

- [ ] **Step 4: Show the refund in the UI**

The cancellation dialog gains a computed line: `You will be refunded ₹X (Y% of ₹Z).` — fetched from `compute_refund` before the dialog opens, never computed in Dart. When the amount is zero, say so plainly rather than hiding the line. Keep the existing honest note that refund processing is not automated.

- [ ] **Step 5: Run everything**

Run: `supabase db reset && supabase test db && flutter test && flutter analyze`

- [ ] **Step 6: Commit**

```bash
git add supabase lib test
git commit -m "feat: add refund policy and the advance/balance split"
```

---

### Task 9: Notification outbox

**Files:**
- Create: `supabase/migrations/0016_outbox.sql`, `supabase/tests/13_outbox_test.sql`, `lib/data/models/outbox_message.dart`, `lib/data/repositories/outbox_repository.dart`, `lib/features/outbox/outbox_screen.dart`
- Modify: `lib/core/router.dart`, `lib/features/admin/admin_home_screen.dart`

**Interfaces:**
- Produces:
  - `outbox(id, reservation_id, channel outbox_channel, recipient text, template text, subject text, body text, status outbox_status, attempts int, last_error text, created_at, sent_at)` where `channel` is `email|sms|whatsapp` and `status` is `pending|sent|failed|skipped`
  - A trigger on `reservations` status transitions enqueuing the SRS messages: booking confirmation, payment success, cancellation
  - `render_template(p_template text, p_reservation_id uuid) returns jsonb` → `{subject, body}`
  - Route `/admin/outbox`

- [ ] **Step 1: Write the failing test**

`supabase/tests/13_outbox_test.sql` — assert: confirming a booking enqueues exactly one `booking_confirmation` row in `pending`; cancelling enqueues a `cancellation` row; the rendered body contains the guest name, the unit name and the stay dates; a customer cannot read the outbox and staff can; and no row is ever enqueued with an empty recipient.

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `relation "public.outbox" does not exist`.

- [ ] **Step 3: Write the migration**

Templates live in a `outbox_templates(name primary key, channel, subject_template, body_template)` table so copy can change without a migration. `render_template` does simple `{{placeholder}}` substitution over a jsonb context built from the reservation, unit, property and customer. The status default is `pending`, and nothing in this phase moves a row to `sent` — that is the honest state until a provider exists.

- [ ] **Step 4: Build the admin outbox screen**

A list grouped by status, each row showing channel, recipient, template and time. A prominent banner at the top reads: `No delivery provider is configured. Messages are queued but not sent.` That banner is not decoration — it is the product telling the truth about itself, and it must not be removable by configuration alone.

- [ ] **Step 5: Run everything**

Run: `supabase db reset && supabase test db && flutter test && flutter analyze`

- [ ] **Step 6: Commit**

```bash
git add supabase lib test
git commit -m "feat: add notification outbox with honest unsent state"
```

---

### Task 10: iCal export and import

**Files:**
- Create: `supabase/migrations/0017_ical.sql`, `supabase/tests/14_ical_test.sql`, `lib/data/models/ical_feed.dart`, `lib/data/repositories/ical_repository.dart`, `lib/features/ota/ical_screen.dart`
- Modify: `lib/core/router.dart`

**Interfaces:**
- Produces:
  - `ical_feeds(id, unit_id, url text, label text, is_active, last_synced_at, last_error, created_at)`
  - `ical_export(p_unit_id uuid) returns text` — a VCALENDAR document listing busy periods as VEVENTs with no guest identity
  - `ical_import_event(p_unit_id uuid, p_uid text, p_start timestamptz, p_end timestamptz) returns jsonb` → `{status, reservation_id, conflict}` where status is `created|updated|conflict|unchanged`
  - Route `/admin/ota/:unitId`

- [ ] **Step 1: Write the failing test**

`supabase/tests/14_ical_test.sql` — assert: `ical_export` for a unit with one confirmed booking contains `BEGIN:VCALENDAR`, exactly one `BEGIN:VEVENT`, the correct `DTSTART`/`DTEND` in UTC `yyyymmddThhmmssZ` form, and NO guest name or email anywhere in the output; a cancelled booking does not appear; importing an event creates an `ota` reservation blocking those dates; re-importing the same UID is `unchanged` rather than creating a duplicate; and an imported event overlapping a confirmed booking returns `conflict` and creates nothing.

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `function public.ical_export(uuid) does not exist`.

- [ ] **Step 3: Write the migration**

`ical_export` builds the document with `string_agg`, folding lines at 75 octets per RFC 5545. Store the external `UID` on the reservation — add `external_uid text` to `reservations` with a unique index on `(unit_id, external_uid)` where `external_uid is not null` — so re-import is idempotent. A conflict is recorded in `ical_feeds.last_error` and returned, never silently resolved.

The import polling job itself requires outbound HTTP, which Postgres cannot do without `pg_net`. Check whether `pg_net` is available in this local stack; if it is, schedule the poll with `pg_cron`. If it is not, implement `ical_import_event` so it can be driven by an admin pressing Sync in the UI, and say plainly in the report and the README that automatic polling is not yet wired.

- [ ] **Step 4: Build the OTA screen**

Per unit: the export URL with a copy action and a one-line explanation of where to paste it in Airbnb; a list of import feeds with add, remove and Sync; last sync time and last error shown honestly.

- [ ] **Step 5: Run everything**

Run: `supabase db reset && supabase test db && flutter test && flutter analyze`

- [ ] **Step 6: Commit**

```bash
git add supabase lib test
git commit -m "feat: add iCal export and import for OTA calendar sync"
```

---

### Task 11: Razorpay adapter behind the existing seam

**Files:**
- Create: `lib/features/booking/razorpay_gateway.dart`
- Test: `test/features/booking/razorpay_gateway_test.dart`

**Interfaces:**
- Consumes: `PaymentGateway`, `PaymentResult` (phase 1).
- Produces: `RazorpayGateway implements PaymentGateway`, selected only when a key is supplied.

This task writes the adapter and does NOT enable it. There is no merchant account, so it cannot be exercised end to end, and pretending otherwise would violate the honesty constraint.

- [ ] **Step 1: Write the failing test**

The test asserts that `RazorpayGateway` with an empty key throws a clear configuration error rather than silently failing, and that `paymentGatewayProvider` returns `MockGateway` when no key is defined — so a misconfigured build cannot quietly take fake payments in production.

- [ ] **Step 2: Run it, implement, run again**

- [ ] **Step 3: Commit**

```bash
git add lib/features/booking test/features/booking
git commit -m "feat(payments): add an inert Razorpay adapter behind the gateway seam"
```

---

### Task 12: README, verification, and the honest status report

**Files:**
- Modify: `README.md`
- Create: `docs/STATUS.md`

- [ ] **Step 1: Run everything and record the real numbers**

```bash
supabase db reset && supabase test db
flutter test
flutter analyze
flutter build web
flutter build apk --debug --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=<local anon key>
```

Record actual output. A failure is reported, not retried until green.

- [ ] **Step 2: Update the README**

Document every feature added, the new `make` targets if any, and extend Known Limitations with everything this phase did not deliver.

- [ ] **Step 3: Write `docs/STATUS.md`**

A single page the owner can read: what works today, what is stubbed and why, and precisely what is needed from them to go live — the Razorpay account, the Supabase billing, the Meta verification, the channel manager — with the consequence of each still being missing. No optimism, no hedging.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/STATUS.md
git commit -m "docs: record phase 2 status and what remains blocked on accounts"
```

---

## Spec Coverage

| Spec section | Tasks |
|---|---|
| §3A UI/UX overhaul | 1, 2, 3, 4 |
| §3B Reports and dashboard | 5, 6 |
| §3C Coupons, refunds, advance/balance | 7, 8 |
| §3D Notification outbox | 9 |
| §3E iCal import/export | 10 |
| §2 Hard boundary — payment stub | 11 |
| §2 Hard boundary — honest status | 9 (banner), 12 (STATUS.md) |
| §4 Architectural continuity | every task's constraints |
| §5 Testing | every task |
| §6 Success criteria | 3, 4 (UI), 6 (reports), 7 (coupon), 8 (refund), 9 (outbox), 10 (iCal), 12 (suite) |

## Execution Notes

- Tasks 1 and 2 are prerequisites for 3 and 4; do them in order.
- Tasks 5–6, 7, 8, 9, 10 and 11 are independent of each other and of the UI work. Any of them can be cut without stranding another.
- Task 12 runs last and reports whatever actually landed.
