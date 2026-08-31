# Single-Page Booking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the booking flow directly into the property page (no separate `/book/:unitId` screen, no unit list), collapse seed data to one whole-property unit, and update the one navigation call site that pointed at the retired route.

**Architecture:** `BookingScreen` loses its self-wrapping `Scaffold`/`AppBar` and inner `SingleChildScrollView` so it becomes a plain embeddable widget with its state machine completely untouched; `PropertyScreen` switches its outer container to `SingleChildScrollView` (for the same calendar-nesting reason `BookingScreen` already documented) and embeds `BookingScreen` directly after the amenities section, using `units.single`.

**Tech Stack:** Flutter/Riverpod/go_router, Postgres/pgTAP via Supabase CLI. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-18-single-page-booking-design.md`

## Global Constraints

- The booking state machine itself (hold timers, payment retry, `HoldParams`, `resolveSelectionChange`/`decideHoldAction`, the two documented pre-existing races) must not change — only where its widget tree is mounted.
- Admin/staff screens, the payment gateway, coupons, refunds, iCal, and the outbox are out of scope.
- `units.single` is deliberately not designed to handle a second unit gracefully (per spec section 7) — do not add multi-unit fallback logic.
- The three pre-existing `hold_lifecycle_test.dart` failures (a `pay-button` key-finder issue, present since before this project's redesign work began) must remain exactly those three after every task.
- Run `flutter analyze` with zero new issues after every Dart task before committing. Run `supabase test db` after the seed-data task before committing.

---

### Task 1: `BookingScreen` becomes embeddable

**Files:**
- Modify: `lib/features/booking/booking_screen.dart:832-846` (the `build` method) and the start/end of `_buildBody` (currently starting at line ~847, wrapped in `SingleChildScrollView`)
- Modify: `test/features/booking/hold_lifecycle_test.dart:542-567` (the `bookingApp` test helper's router)

**Interfaces:**
- Consumes: nothing new.
- Produces: `BookingScreen.build()` no longer returns a `Scaffold` — it returns the `unitAsync.when(...)` result directly. `_buildBody` no longer wraps its `Column` in a `SingleChildScrollView`. Task 2 relies on both of these to embed `BookingScreen` inside its own single scrollable.

- [ ] **Step 1: Write the failing test**

Add this test to `test/features/booking/hold_lifecycle_test.dart`, inside `main()` alongside the existing tests (do not remove or alter any existing test):

```dart
  testWidgets('does not wrap itself in its own Scaffold or AppBar', (
    tester,
  ) async {
    final actions = _FakeBookingActions()..quoteToReturn = _quote();
    final gateway = _ScriptedGateway([const PaymentResult.success('ref-1')]);

    await tester.pumpWidget(bookingApp(actions: actions, gateway: gateway));
    await tester.pumpAndSettle();

    // The test's own router route wraps BookingScreen in exactly one
    // Scaffold (see the `bookingApp` helper) -- if BookingScreen still
    // supplied its own, there would be two.
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking/hold_lifecycle_test.dart --plain-name "does not wrap itself"`
Expected: FAIL — `find.byType(Scaffold)` finds 2 (the test's own router-level `Scaffold` you're about to add in Step 3, plus `BookingScreen`'s current self-wrapped one), and/or `find.byType(AppBar)` finds 1 instead of 0. Note: this step's failing state only makes sense once Step 3's test-file router change (adding the wrapping `Scaffold`) is in place — write both edits from this task's Step 1 and the router edit below together, then run this command to observe the failure before Step 4's implementation.

- [ ] **Step 3: Write the implementation**

First, update the test helper so its own router supplies the `Scaffold` `BookingScreen` will stop providing:

```dart
// test/features/booking/hold_lifecycle_test.dart:542-567 — replace:
      final router = GoRouter(
        initialLocation: '/book/${_unit.id}',
        routes: [
          GoRoute(
            path: '/book/:unitId',
            builder: (_, state) =>
                BookingScreen(unitId: state.pathParameters['unitId']!),
          ),
          GoRoute(
            path: '/booking/:id',
            builder: (_, state) => Scaffold(
              body: Text('confirmed:${state.pathParameters['id']}'),
            ),
          ),
        ],
      );
// with:
      final router = GoRouter(
        initialLocation: '/book/${_unit.id}',
        routes: [
          GoRoute(
            path: '/book/:unitId',
            builder: (_, state) => Scaffold(
              body: BookingScreen(unitId: state.pathParameters['unitId']!),
            ),
          ),
          GoRoute(
            path: '/booking/:id',
            builder: (_, state) => Scaffold(
              body: Text('confirmed:${state.pathParameters['id']}'),
            ),
          ),
        ],
      );
```

Now the actual widget change:

```dart
// lib/features/booking/booking_screen.dart — replace:
  @override
  Widget build(BuildContext context) {
    final unitAsync = ref.watch(unitByIdProvider(widget.unitId));
    return Scaffold(
      appBar: AppBar(title: Text(unitAsync.value?.name ?? 'Book')),
      body: unitAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(unitByIdProvider(widget.unitId)),
        ),
        data: (unit) => _buildBody(context, unit),
      ),
    );
  }
// with:
  @override
  Widget build(BuildContext context) {
    final unitAsync = ref.watch(unitByIdProvider(widget.unitId));
    return unitAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FailureView(
        error: e,
        onRetry: () => ref.invalidate(unitByIdProvider(widget.unitId)),
      ),
      data: (unit) => _buildBody(context, unit),
    );
  }
```

And `_buildBody`'s wrapper — the method currently ends with (reading from where the `slotSelector`/`remaining`/`textTheme`/`scheme` locals are computed):

```dart
// lib/features/booking/booking_screen.dart — replace:
    // A plain Column inside a SingleChildScrollView, not a ListView: a
    // ListView's Sliver machinery builds children lazily by cache extent,
    // and the calendar's own shrink-wrapped GridView (nested sliver inside
    // a sliver list item) throws that lazy accounting off -- items further
    // down silently never get built, no matter how large `cacheExtent` is
    // set. A Column always builds every child eagerly.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
// with:
    // A plain Column, not a ListView: a ListView's Sliver machinery builds
    // children lazily by cache extent, and the calendar's own
    // shrink-wrapped GridView (nested sliver inside a sliver list item)
    // throws that lazy accounting off -- items further down silently never
    // get built, no matter how large `cacheExtent` is set. This widget is
    // embedded inside `PropertyScreen`'s own single `SingleChildScrollView`
    // (see `property_screen.dart`) rather than owning one itself, for the
    // same reason -- there must be exactly one scrollable ancestor between
    // here and the calendar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
```

And its matching closing braces — the method currently ends with:

```dart
// lib/features/booking/booking_screen.dart — replace the final three lines
// of _buildBody (after the Section 4 "Pay" _NumberedSection's closing):
        ],
      ),
    );
  }
// with:
      ],
    );
  }
```

(This removes one level of closing — `),` for the `Column` plus `);` for the outer `SingleChildScrollView` collapses to a single `];` for the `Column`'s children followed by `);` closing the `Column` itself, since `Column` is now the direct return value.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/booking/hold_lifecycle_test.dart`
Expected: PASS — every test in the file, including the new one and the three pre-existing, unrelated failures (still exactly those three — a `pay-button` key-finder issue).

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/booking_screen.dart test/features/booking/hold_lifecycle_test.dart
git commit -m "refactor(booking): make BookingScreen embeddable, drop its own Scaffold"
```

---

### Task 2: `PropertyScreen` embeds the booking flow, drops the unit list

**Files:**
- Modify: `lib/features/browse/property_screen.dart` (full rewrite of the file's structure — see below)
- Modify: `test/features/browse/property_screen_test.dart` (remove the `unitPhoto` tests)
- Modify: `test/features/browse/property_screen_widget_test.dart` (add provider overrides every test needs now that `BookingScreen` is embedded; replace the unit-card-photo test)

**Interfaces:**
- Consumes: `BookingScreen` (Task 1, now embeddable), `unitByIdProvider` (from `lib/features/booking/providers.dart`), `unitCalendarSourceProvider` (from `lib/features/calendar/providers.dart`).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing tests**

First, `test/features/browse/property_screen_test.dart` loses its `unitPhoto` group (the function is being deleted) — replace the whole file with:

```dart
// test/features/browse/property_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/features/browse/property_screen.dart';

void main() {
  group('bookingModeLabel', () {
    test('nightly mode reads Nightly', () {
      expect(bookingModeLabel(BookingMode.nightly), 'Nightly');
    });

    test('slot mode reads Slots', () {
      expect(bookingModeLabel(BookingMode.slot), 'Slots');
    });

    test('both mode reads Nightly or slots', () {
      expect(bookingModeLabel(BookingMode.both), 'Nightly or slots');
    });
  });
}
```

Second, `test/features/browse/property_screen_widget_test.dart` needs new provider overrides on every test (the embedded `BookingScreen` now watches `unitByIdProvider`/`unitCalendarSourceProvider` on build) and its unit-card-photo test replaced. Replace the whole file with:

```dart
// test/features/browse/property_screen_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/features/booking/providers.dart' show unitByIdProvider;
import 'package:pasala/features/browse/property_screen.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/calendar/providers.dart'
    show unitCalendarSourceProvider;

const _property = Property(
  id: 'p1',
  name: 'Pasala Dallas Cottage',
  slug: 'dallas-cottage',
  description: 'A themed cottage by the pool.',
  address: null,
  images: [],
  amenities: ['Pool'],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
);

const _unit = Unit(
  id: 'u1',
  propertyId: 'p1',
  name: 'Dallas',
  capacityBase: 2,
  capacityMax: 4,
  bookingMode: BookingMode.nightly,
  isActive: true,
);

const _units = <Unit>[_unit];

/// A [UnitCalendarSource] with no occupied dates at all -- the calendar
/// this screen embeds just needs something to watch; its own occupancy
/// rendering is `availability_calendar_test.dart`'s job, not this file's.
class _NoOccupancyCalendarSource implements UnitCalendarSource {
  @override
  Stream<List<Reservation>> watchUnit(String unitId) => const Stream.empty();

  @override
  Future<List<Reservation>> fetchUnit(String unitId) async => const [];
}

Widget _appFor() => ProviderScope(
      overrides: [
        propertyProvider('p1').overrideWith((ref) => Future.value(_property)),
        unitsProvider('p1').overrideWith((ref) => Future.value(_units)),
        unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
        unitCalendarSourceProvider
            .overrideWithValue(_NoOccupancyCalendarSource()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PropertyScreen(propertyId: 'p1')),
      ),
    );

void main() {
  testWidgets('wraps the header media in a Hero tagged with the property id', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag == 'property-media-p1'),
      findsOneWidget,
    );
  });

  testWidgets('the gallery carries the property Hero as its first page, '
      'plus one page per bundled photo', (tester) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.positions, isNotEmpty);
    expect(
      (pageView.childrenDelegate as SliverChildBuilderDelegate).childCount,
      9,
    );
    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag == 'property-media-p1'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the booking flow renders directly on the property page, for the '
    'single unit -- no separate screen, no unit list',
    (tester) async {
      await tester.pumpWidget(_appFor());
      await tester.pumpAndSettle();

      expect(find.text('Dates'), findsOneWidget);
      expect(find.text('Guests'), findsOneWidget);
      expect(find.byKey(const Key('occasion-field')), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('Pay'), findsOneWidget);
    },
  );
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/browse/property_screen_test.dart test/features/browse/property_screen_widget_test.dart`
Expected: FAIL — `property_screen_widget_test.dart`'s new "the booking flow renders directly" test fails (`find.text('Dates')` etc. find nothing, since `PropertyScreen` still renders the old unit list). The other two tests in that file may also fail or error at this point since `PropertyScreen` doesn't yet know about `unitByIdProvider`/`unitCalendarSourceProvider` — that's expected; they'll pass once Step 3 lands.

- [ ] **Step 3: Write the implementation**

Full replacement of `lib/features/browse/property_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/property.dart';
import '../../data/models/unit.dart';
import '../booking/booking_screen.dart';
import 'browse_screen.dart' show AmenityWrap, PropertyMedia;
import 'providers.dart';

/// Label shown on a unit's booking-mode chip. Pure so it can be tested
/// without touching the network.
String bookingModeLabel(BookingMode mode) => switch (mode) {
      BookingMode.nightly => 'Nightly',
      BookingMode.slot => 'Slots',
      BookingMode.both => 'Nightly or slots',
    };

/// Every bundled farmhouse photo, shown as a swipeable gallery on the
/// property page. Deliberately separate from [Property.images] (the
/// database-backed network photo `PropertyMedia` renders) -- these are
/// bundled app assets, not per-property data, so the same 8 photos show on
/// every property page regardless of what that property's own `images`
/// column holds.
const _galleryPhotos = [
  AppAssets.heroDayAerial,
  AppAssets.heroNightAerial,
  AppAssets.cottagesPoolRow,
  AppAssets.cottagesDallasVegas,
  AppAssets.cottagesBostonDetroit,
  AppAssets.eventStringLights,
  AppAssets.facadeDaytime,
  AppAssets.patioFirepitNight,
];

/// A swipeable gallery whose first page is the property's own (network or
/// placeholder) photo -- carrying the same `Hero` tag [PropertyCard] uses,
/// so the shared-element transition from Browse still lands here -- followed
/// by one page per bundled farmhouse photo, with dot indicators showing
/// position.
class PropertyGallery extends StatefulWidget {
  const PropertyGallery({super.key, required this.property});

  final Property property;

  @override
  State<PropertyGallery> createState() => _PropertyGalleryState();
}

class _PropertyGalleryState extends State<PropertyGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = 1 + _galleryPhotos.length;
    return SizedBox(
      height: 280,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: pageCount,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Hero(
                  tag: 'property-media-${widget.property.id}',
                  child: PropertyMedia(property: widget.property),
                );
              }
              return Image.asset(_galleryPhotos[i - 1], fit: BoxFit.cover);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < pageCount; i++)
                  AnimatedContainer(
                    duration: PasalaTokens.motionFast,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 10 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PropertyScreen extends ConsumerWidget {
  const PropertyScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final property = ref.watch(propertyProvider(propertyId));
    final units = ref.watch(unitsProvider(propertyId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return AsyncView(
      value: property,
      onRetry: () => ref.invalidate(propertyProvider(propertyId)),
      // A plain SingleChildScrollView, not a ListView: the embedded
      // booking flow's availability calendar has its own shrink-wrapped
      // GridView, which breaks when nested inside a ListView's sliver
      // machinery (see `booking_screen.dart`'s own note on this). There
      // must be exactly one scrollable ancestor between here and the
      // calendar.
      data: (p) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PropertyGallery(property: p),
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: textTheme.headlineMedium),
                  if (p.address != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      p.address!,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (p.description != null) ...[
                    const SizedBox(height: Spacing.md),
                    Text(p.description!, style: textTheme.bodyLarge),
                  ],
                  const SizedBox(height: Spacing.md),
                  AmenityWrap(amenities: p.amenities, max: p.amenities.length),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, 0, Spacing.md, Spacing.lg),
              child: AsyncView(
                value: units,
                onRetry: () => ref.invalidate(unitsProvider(propertyId)),
                empty: () => const EmptyState(
                  icon: Icons.bed_outlined,
                  title: 'No units yet',
                  message: 'Ask an admin to add one.',
                ),
                // Exactly one bookable unit is assumed here -- `.single`
                // throws if a second unit is ever added, deliberately (see
                // spec section 7): this screen shows the booking flow
                // inline for one unit, and does not attempt to fall back
                // to a unit-picker if that assumption stops holding.
                data: (list) => BookingScreen(unitId: list.single.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Note this deletes `UnitCard` and `unitPhoto` entirely — they no longer exist anywhere in the file.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/browse/property_screen_test.dart test/features/browse/property_screen_widget_test.dart`
Expected: PASS — all tests in both files.

- [ ] **Step 5: Commit**

```bash
git add lib/features/browse/property_screen.dart test/features/browse/property_screen_test.dart test/features/browse/property_screen_widget_test.dart
git commit -m "feat(property): embed the booking flow inline, remove the unit list"
```

---

### Task 3: Retire the `/book/:unitId` route

**Files:**
- Modify: `lib/core/router.dart:160-166` (remove the `GoRoute`)
- Modify: `lib/features/account/my_bookings_screen.dart:50-52` (the resume-hold tap target)
- Modify: `lib/data/repositories/catalog_repository.dart:33` (doc comment)
- Modify: `lib/features/booking/providers.dart:9` (doc comment)
- Modify: `lib/features/calendar/providers.dart:14` (doc comment)
- Test: no new test file — the two behaviors this task changes (route removed, resume-hold destination) are covered by Task 2's property-page test (embedded booking flow exists at `/property/:id`) and by manual verification in Task 5; router.dart's existing `router_test.dart` doesn't reference `/book/:unitId` today and needs no change.

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Confirm the current behavior before changing it**

Run: `grep -n "book/:unitId" lib/core/router.dart lib/features/account/my_bookings_screen.dart`
Expected output before this task:
```
lib/core/router.dart:161:            path: '/book/:unitId',
lib/features/account/my_bookings_screen.dart:51:                      ? () => context.go('/book/${reservation.unitId}')
```

- [ ] **Step 2: Remove the route**

```dart
// lib/core/router.dart:160-166 — delete entirely:
          GoRoute(
            path: '/book/:unitId',
            pageBuilder: (_, state) => fadeSlidePage(
              BookingScreen(unitId: state.pathParameters['unitId']!),
              state,
            ),
          ),
```

Since `BookingScreen` is no longer referenced anywhere in `router.dart` after this deletion, also remove its now-unused import:

```dart
// lib/core/router.dart — delete:
import '../features/booking/booking_screen.dart';
```

- [ ] **Step 3: Update the resume-hold navigation target**

```dart
// lib/features/account/my_bookings_screen.dart:50-52 — replace:
                  onTap: reservation.isHold
                      ? () => context.go('/book/${reservation.unitId}')
                      : () => context.push('/booking-detail/${reservation.id}'),
// with:
                  // A hold is a 15-minute reservation, not a finished
                  // booking -- there is nothing to view or cancel about it
                  // on a read-only detail screen. The property page is now
                  // the only place with a live pay/resume affordance (the
                  // booking flow is embedded there for the property's one
                  // unit), so a tap on a hold goes to `/` -- Browse's
                  // existing single-property redirect lands the customer
                  // on that page, where re-picking the held dates reuses
                  // the live hold via the same `resolveSelectionChange`
                  // machinery every other selection change already uses.
                  onTap: reservation.isHold
                      ? () => context.go('/')
                      : () => context.push('/booking-detail/${reservation.id}'),
```

(The existing comment immediately above this `onTap` in the file, which currently reads "...`BookingScreen` is the only place with a live pay/resume affordance, so that is where a tap on a hold belongs, rather than a dead end." — this whole comment block is replaced by the new one shown above; do not leave both.)

- [ ] **Step 4: Update the three stale doc comments**

```dart
// lib/data/repositories/catalog_repository.dart:33 — replace:
  /// arrives with a `unitId` (from `/book/:unitId`) and needs the unit's
// with:
  /// arrives with a `unitId` (from the booking flow embedded on the
  /// property page) and needs the unit's
```

```dart
// lib/features/booking/providers.dart:9 — replace:
/// `/book/:unitId` route), so it needs this rather than the property-scoped
// with:
/// property page's embedded booking flow), so it needs this rather than the
/// property-scoped
```

(Read the full sentence each of these fragments sits in before editing — these are excerpts of longer doc comments, and the replacement text must still read grammatically as a complete sentence in context.)

```dart
// lib/features/calendar/providers.dart:14 — replace:
/// This calendar is customer-facing (`/book/:unitId`, reached from every
// with:
/// This calendar is customer-facing (embedded in the booking flow on the
/// property page, reached from every
```

- [ ] **Step 5: Run tests to verify nothing broke**

Run: `flutter test test/core/router_test.dart test/features/account/`
Expected: PASS — `router_test.dart` has no assertions about `/book/:unitId` today (confirmed absent), and `test/features/account/my_bookings_screen_test.dart` (confirmed, by inspection, to contain no assertion on the resume-hold navigation target today) is unaffected by this change either way.

Run: `flutter analyze`
Expected: `No issues found!` (confirms the removed `BookingScreen` import from `router.dart` isn't needed elsewhere in that file, and no other file references the deleted route).

- [ ] **Step 6: Commit**

```bash
git add lib/core/router.dart lib/features/account/my_bookings_screen.dart lib/data/repositories/catalog_repository.dart lib/features/booking/providers.dart lib/features/calendar/providers.dart
git commit -m "feat(routing): retire /book/:unitId, resume-hold goes through the property page"
```

---

### Task 4: Seed data — collapse six units into one

**Files:**
- Modify: `supabase/seed.sql:66-107` (the units/rate_rules block established by the prior single-property onboarding change)

**Interfaces:**
- Consumes: nothing new.
- Produces: one seeded unit, id `b0000000-0000-0000-0000-000000000001`, name "Pasala Farm House". Task 5's manual walkthrough relies on this.

- [ ] **Step 1: Confirm the current state**

Run: `supabase db reset && psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '\"')" -c "select name from public.units order by name;"`
Expected output before this task: six rows — Boston, Dallas, Detroit, Las Vegas, Miami, New York.

- [ ] **Step 2: Replace the units/rate_rules block**

```sql
-- supabase/seed.sql — replace the units insert:
insert into public.units
  (id, property_id, name, capacity_base, capacity_max, booking_mode)
values
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'Dallas', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
   'Las Vegas', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',
   'New York', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001',
   'Boston', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001',
   'Detroit', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001',
   'Miami', 20, 40, 'slot');

-- base rates for every unit
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority)
values
  ('b0000000-0000-0000-0000-000000000001','base','Weekday', 6000, 800, 800,0),
  ('b0000000-0000-0000-0000-000000000002','base','Weekday', 6000, 800, 800,0),
  ('b0000000-0000-0000-0000-000000000003','base','Weekday', 6500, 900, 800,0),
  ('b0000000-0000-0000-0000-000000000004','base','Weekday', 6000, 800, 800,0),
  ('b0000000-0000-0000-0000-000000000005','base','Weekday', 6000, 800, 800,0),
  ('b0000000-0000-0000-0000-000000000006','base','Weekday',12000, 400,1500,0);
-- with:
insert into public.units
  (id, property_id, name, capacity_base, capacity_max, booking_mode)
values
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'Pasala Farm House', 20, 40, 'nightly');

-- base rate for the one whole-property unit
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority)
values
  ('b0000000-0000-0000-0000-000000000001','base','Weekday',18000,1000,2500,0);
```

The weekend-uplift and Diwali-override `insert ... select ... from public.rate_rules where kind = 'base'` statements immediately below this block are unchanged — they automatically pick up whatever `base` rows exist, so they now derive exactly one weekend row and one Diwali row instead of six each.

Update the two fixture reservations further down to reference the one remaining unit id (they currently reference `b0000000-...-0001` for the booking and `b0000000-...-0002` for the block — the second one no longer exists):

```sql
-- supabase/seed.sql — replace:
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, source)
values
  ('b0000000-0000-0000-0000-000000000001',
   public.build_period('b0000000-0000-0000-0000-000000000001',
                       current_date + 7, current_date + 9),
   'booking','confirmed','10000000-0000-0000-0000-000000000005',2,'app');

insert into public.reservations
  (unit_id, period, kind, status, block_reason, source)
values
  ('b0000000-0000-0000-0000-000000000002',
   public.build_period('b0000000-0000-0000-0000-000000000002',
                       current_date + 14, current_date + 16),
   'block','confirmed','Deep cleaning','admin');
-- with:
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, source)
values
  ('b0000000-0000-0000-0000-000000000001',
   public.build_period('b0000000-0000-0000-0000-000000000001',
                       current_date + 7, current_date + 9),
   'booking','confirmed','10000000-0000-0000-0000-000000000005',2,'app');

insert into public.reservations
  (unit_id, period, kind, status, block_reason, source)
values
  ('b0000000-0000-0000-0000-000000000001',
   public.build_period('b0000000-0000-0000-0000-000000000001',
                       current_date + 14, current_date + 16),
   'block','confirmed','Deep cleaning','admin');
```

(The booking fixture's unit id was already `...0001` and needs no change; only the block fixture's unit id changes from `...0002` to `...0001`. Both fixture reservations now reference the same single unit — since `reservations_no_overlap` excludes by `(unit_id, period)`, this is fine as long as their date ranges don't overlap, which they don't: `current_date + 7..9` and `current_date + 14..16`.)

- [ ] **Step 3: Run the check again**

Run: `supabase db reset && psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '\"')" -c "select name, capacity_base, capacity_max, booking_mode from public.units;"`
Expected: exactly one row — `Pasala Farm House | 20 | 40 | nightly`.

Also run: `supabase test db`
Expected: full suite passes. `06_booking_flow_test.sql`, `11_coupons_test.sql`, `12_refunds_test.sql`, and `13_outbox_test.sql` all insert their own fixture units and don't depend on the seeded ones, so none of them should be affected — confirm this by checking the full pass count matches the pre-change baseline (380 tests).

- [ ] **Step 4: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat: collapse the six seeded cottages into one whole-property unit"
```

---

### Task 5: Full-suite verification and manual walkthrough

**Files:** none (verification only)

**Interfaces:** none

- [ ] **Step 1: Backend verification**

Run: `supabase db reset && supabase test db`
Expected: every pgTAP test file passes (380 tests, matching the pre-change baseline — this task changed no schema, only seed data).

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Full automated Flutter test suite**

Run: `flutter test`
Expected: every test passes except the three pre-existing `hold_lifecycle_test.dart` failures — confirm by name via `flutter test 2>&1 | grep "\[E\]"` that it is still exactly those same three test descriptions (a `pay-button` key-finder issue), not a different set and not more than three.

- [ ] **Step 4: Manual browser walkthrough**

Run: `make run-web`, then walk the full path end-to-end:

1. Sign in as `ravi@example.com` / `password123` — confirm landing goes straight to the Pasala Farm House property page (single-property redirect, unaffected by this plan).
2. Confirm the property page shows, top to bottom: the photo gallery, name/address/description/amenities, then directly below — no tap, no navigation — the booking flow: "Dates" section with the calendar, "Guests" section with the stepper and the occasion field, "Price" section, "Pay" section.
3. Pick an available date range, enter a guest count and an occasion note, and complete a payment. Confirm it lands on the confirmation screen showing the occasion, exactly as before.
4. Go to "My Bookings", find a still-live hold if one exists (or create one by starting a booking and closing the app before paying), and tap it. Confirm it navigates to `/` and then straight back to the Pasala Farm House property page (not a 404, not a separate booking screen).
5. Confirm the browser's address bar never shows `/book/...` at any point in this walkthrough.

- [ ] **Step 5: Commit (only if the walkthrough surfaced a formatting fix)**

If `dart format --output=none --set-exit-if-changed .` reports any file needing formatting, run `dart format .` and commit:

```bash
git add -A
git commit -m "chore: format single-page booking files"
```

If nothing needed fixing, skip this step — there is nothing to commit.
