# Farmhouse UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle every customer-facing screen (login, signup, browse, property detail, booking flow chrome, confirmation, my bookings) with the owner's real Pasala Farm House photos and brand logo, plus vanilla-Flutter polish animations — presentation only, no backend/provider/routing-logic changes.

**Architecture:** A small shared "premium chrome" layer (`AppAssets` token class, `HeroBackdrop`, `BrandMark`, `StaggeredFadeIn` widgets, extended `EmptyState`) consumed by per-screen edits. No new state management, no new pub.dev dependencies, no changes to `lib/data/` or any `providers.dart`.

**Tech Stack:** Flutter 3.38.9, Riverpod (`flutter_riverpod`), `go_router`, vanilla Flutter animation APIs (`TweenAnimationBuilder`, `Hero`, `AnimatedScale`, `AnimatedOpacity`, `CustomTransitionPage`).

## Global Constraints

- No new pub.dev dependencies (confirmed with the user: vanilla Flutter APIs only).
- No bundled custom font — no font file was supplied; typographic "display" treatment comes from weight/letter-spacing tuning of the existing platform font only.
- Admin/staff/accountant screens are out of scope — do not touch `lib/features/admin/`, `lib/features/reports/`, `lib/features/staff/`, `lib/features/outbox/`, `lib/features/ota/`.
- Never touch `lib/data/`, any `providers.dart`, `router.dart`'s `redirectFor`/`landingPathFor` logic, or the state machine in `lib/features/booking/booking_screen.dart` (hold timers, selection-change handling) — this file inherits new styling automatically via the global theme (`app_theme.dart`) and needs no direct edits.
- Source images live at `C:\pasala images\` (owner-supplied, Windows path) and must be copied into `assets/images/` under descriptive names — never referenced from their original location.
- Every new/modified widget test must pass; existing tests listed in each task must still pass unmodified unless the task explicitly says to extend them.
- Run `flutter analyze` with zero new issues after every task before committing.

---

### Task 1: Bundle the resort's photos and logo as app assets

**Files:**
- Create: `assets/images/logo_mark.jpg`, `assets/images/hero_night_aerial.png`, `assets/images/hero_day_aerial.webp`, `assets/images/cottages_pool_row.webp`, `assets/images/cottages_dallas_vegas.webp`, `assets/images/cottages_boston_detroit.webp`, `assets/images/event_string_lights.webp`, `assets/images/facade_daytime.webp`, `assets/images/patio_firepit_night.webp`, `assets/images/entrance_gate_night.webp` (copied from `C:\pasala images\`)
- Create: `lib/core/theme/app_assets.dart`
- Modify: `pubspec.yaml:74` (right after `uses-material-design: true`)
- Test: `test/core/theme/app_assets_test.dart`

**Interfaces:**
- Produces: `AppAssets` class with `static const String` fields — `logoMark`, `heroNightAerial`, `heroDayAerial`, `cottagesPoolRow`, `cottagesDallasVegas`, `cottagesBostonDetroit`, `eventStringLights`, `facadeDaytime`, `patioFirepitNight`, `entranceGateNight`. Every later task that references an image imports this class rather than a raw string path.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/app_assets_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_assets.dart';

void main() {
  test('every declared asset path exists on disk', () {
    const paths = [
      AppAssets.logoMark,
      AppAssets.heroNightAerial,
      AppAssets.heroDayAerial,
      AppAssets.cottagesPoolRow,
      AppAssets.cottagesDallasVegas,
      AppAssets.cottagesBostonDetroit,
      AppAssets.eventStringLights,
      AppAssets.facadeDaytime,
      AppAssets.patioFirepitNight,
      AppAssets.entranceGateNight,
    ];

    for (final path in paths) {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing');
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/app_assets_test.dart`
Expected: FAIL — `Error: Type 'AppAssets' not found` (the class doesn't exist yet).

- [ ] **Step 3: Copy the image files and write the implementation**

```bash
mkdir -p assets/images
cp "C:/pasala images/1.jpg" assets/images/logo_mark.jpg
cp "C:/pasala images/10.png" assets/images/hero_night_aerial.png
cp "C:/pasala images/5.webp" assets/images/hero_day_aerial.webp
cp "C:/pasala images/2.webp" assets/images/cottages_pool_row.webp
cp "C:/pasala images/3.webp" assets/images/cottages_dallas_vegas.webp
cp "C:/pasala images/4.webp" assets/images/cottages_boston_detroit.webp
cp "C:/pasala images/9.webp" assets/images/event_string_lights.webp
cp "C:/pasala images/7.webp" assets/images/facade_daytime.webp
cp "C:/pasala images/8.webp" assets/images/patio_firepit_night.webp
cp "C:/pasala images/6.webp" assets/images/entrance_gate_night.webp
```

```dart
// lib/core/theme/app_assets.dart

/// Bundled chrome imagery for Pasala Resorts — the brand logo and the
/// property's own photos, used on login/signup/browse/confirmation/empty
/// states. This is separate from `Property.images` (network URLs from the
/// database, rendered by `PropertyMedia`); nothing here ever touches that
/// path.
abstract final class AppAssets {
  static const String logoMark = 'assets/images/logo_mark.jpg';
  static const String heroNightAerial = 'assets/images/hero_night_aerial.png';
  static const String heroDayAerial = 'assets/images/hero_day_aerial.webp';
  static const String cottagesPoolRow = 'assets/images/cottages_pool_row.webp';
  static const String cottagesDallasVegas =
      'assets/images/cottages_dallas_vegas.webp';
  static const String cottagesBostonDetroit =
      'assets/images/cottages_boston_detroit.webp';
  static const String eventStringLights =
      'assets/images/event_string_lights.webp';
  static const String facadeDaytime = 'assets/images/facade_daytime.webp';
  static const String patioFirepitNight =
      'assets/images/patio_firepit_night.webp';
  static const String entranceGateNight =
      'assets/images/entrance_gate_night.webp';
}
```

Modify `pubspec.yaml` — insert directly after line 74 (`uses-material-design: true`):

```yaml
  uses-material-design: true

  assets:
    - assets/images/
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter pub get && flutter test test/core/theme/app_assets_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add assets/images pubspec.yaml pubspec.lock lib/core/theme/app_assets.dart test/core/theme/app_assets_test.dart
git commit -m "feat: bundle Pasala Farm House photos and logo as app assets"
```

---

### Task 2: Add display-type and breakpoint tokens

**Files:**
- Modify: `lib/core/theme/tokens.dart`
- Modify: `lib/core/theme/app_theme.dart:20-27`
- Test: `test/core/theme/display_type_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `PasalaTokens.displayWeight` (`FontWeight`), `PasalaTokens.displayLetterSpacing` (`double`), `PasalaTokens.wideBreakpoint` (`double`, `840`). Later tasks (`AppShell`, `BrowseScreen`) use `PasalaTokens.wideBreakpoint` instead of a hardcoded `840`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/display_type_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/tokens.dart';

void main() {
  test('wideBreakpoint matches the layout breakpoint used across the app', () {
    expect(PasalaTokens.wideBreakpoint, 840.0);
  });

  test('headline styles use the display weight and tracking tokens', () {
    for (final brightness in Brightness.values) {
      final textTheme = buildTheme(brightness).textTheme;
      expect(textTheme.headlineMedium!.fontWeight, PasalaTokens.displayWeight);
      expect(
        textTheme.headlineMedium!.letterSpacing,
        PasalaTokens.displayLetterSpacing,
      );
      expect(textTheme.headlineSmall!.fontWeight, PasalaTokens.displayWeight);
      expect(
        textTheme.headlineSmall!.letterSpacing,
        PasalaTokens.displayLetterSpacing,
      );
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/display_type_test.dart`
Expected: FAIL — `Error: The getter 'displayWeight' isn't defined for the class 'PasalaTokens'`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/theme/tokens.dart — add inside the PasalaTokens class, after `accent`:
  static const double displayLetterSpacing = -0.8;
  static const FontWeight displayWeight = FontWeight.w700;

  /// The single width breakpoint the app treats as "wide" (desktop/tablet
  /// landscape vs. phone) — shared by `AppShell`'s rail/bottom-bar switch
  /// and `BrowseScreen`'s grid/list switch so the two can never disagree.
  static const double wideBreakpoint = 840;
```

```dart
// lib/core/theme/app_theme.dart:20-27 — replace the textTheme block with:
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: PasalaTokens.displayWeight,
        letterSpacing: PasalaTokens.displayLetterSpacing,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: PasalaTokens.displayWeight,
        letterSpacing: PasalaTokens.displayLetterSpacing,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/display_type_test.dart test/core/theme/tokens_test.dart`
Expected: PASS (both files — `tokens_test.dart` must still pass unmodified)

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens.dart lib/core/theme/app_theme.dart test/core/theme/display_type_test.dart
git commit -m "feat: add display-type and shared wide-breakpoint tokens"
```

---

### Task 3: `HeroBackdrop` — full-bleed image with scrim

**Files:**
- Create: `lib/core/widgets/hero_backdrop.dart`
- Test: `test/core/widgets/hero_backdrop_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `HeroBackdrop({required String imageAsset, required Widget child, double scrimOpacity = 0.55})`. Used by login, signup, browse (hero header), and confirmation.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/hero_backdrop_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/hero_backdrop.dart';

void main() {
  testWidgets('renders the background image and the foreground child', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: HeroBackdrop(
        imageAsset: 'assets/images/hero_night_aerial.png',
        child: Center(child: Text('Welcome back')),
      ),
    ));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/hero_backdrop_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'pasala/core/widgets/hero_backdrop.dart'` (file doesn't exist).

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/widgets/hero_backdrop.dart
import 'package:flutter/material.dart';

/// A full-bleed image with a bottom-weighted dark scrim, used behind
/// foreground content on login, signup, browse's header, and the booking
/// confirmation screen. Centralises the scrim gradient so it isn't
/// recomputed three times with slightly different numbers.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({
    super.key,
    required this.imageAsset,
    required this.child,
    this.scrimOpacity = 0.55,
  });

  final String imageAsset;
  final Widget child;
  final double scrimOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(imageAsset, fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: scrimOpacity),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/hero_backdrop_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/hero_backdrop.dart test/core/widgets/hero_backdrop_test.dart
git commit -m "feat: add HeroBackdrop shared widget"
```

---

### Task 4: `BrandMark` — the Pasala Resorts logo widget

**Files:**
- Create: `lib/core/widgets/brand_mark.dart`
- Test: `test/core/widgets/brand_mark_test.dart`

**Interfaces:**
- Consumes: `AppAssets.logoMark` (Task 1), `PasalaTokens.radiusSm` (existing).
- Produces: `enum BrandMarkSize { splash, appBar }` and `BrandMark({BrandMarkSize size = BrandMarkSize.appBar, bool showWordmark = true})`. Used by `AppShell`'s app bar, login/signup, and `AppSplashOverlay`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/brand_mark_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/brand_mark.dart';

void main() {
  testWidgets('carries an accessible label naming the resort', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BrandMark())));

    expect(find.bySemanticsLabel('Pasala Resorts'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('shows the wordmark text by default', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BrandMark())));

    expect(find.text('Pasala Resorts'), findsOneWidget);
  });

  testWidgets('hides the wordmark text when showWordmark is false', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BrandMark(showWordmark: false)),
    ));

    expect(find.text('Pasala Resorts'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/brand_mark_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'pasala/core/widgets/brand_mark.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/widgets/brand_mark.dart
import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/tokens.dart';

enum BrandMarkSize { splash, appBar }

/// The Pasala Resorts logo mark (emblem + wordmark image), shown in the
/// app shell's app bar, on login/signup, and in the cold-start splash
/// moment. A single place to change if the mark or its accessible label
/// ever changes.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = BrandMarkSize.appBar,
    this.showWordmark = true,
  });

  final BrandMarkSize size;
  final bool showWordmark;

  double get _imageSize => switch (size) {
        BrandMarkSize.splash => 96,
        BrandMarkSize.appBar => 28,
      };

  @override
  Widget build(BuildContext context) {
    final mark = Semantics(
      label: 'Pasala Resorts',
      image: true,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
        child: Image.asset(
          AppAssets.logoMark,
          width: _imageSize,
          height: _imageSize,
          fit: BoxFit.cover,
        ),
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: Spacing.sm),
        Text('Pasala Resorts', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/brand_mark_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/brand_mark.dart test/core/widgets/brand_mark_test.dart
git commit -m "feat: add BrandMark shared widget"
```

---

### Task 5: `StaggeredFadeIn` — index-staggered list entrance

**Files:**
- Create: `lib/core/widgets/staggered_fade_in.dart`
- Test: `test/core/widgets/staggered_fade_in_test.dart`

**Interfaces:**
- Consumes: `PasalaTokens.motionBase` (existing).
- Produces: `StaggeredFadeIn({required int index, required Widget child})`. Used by `BrowseScreen`'s property list and `MyBookingsScreen`'s booking list.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/staggered_fade_in_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/staggered_fade_in.dart';

void main() {
  testWidgets('renders its child fully visible once settled', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: StaggeredFadeIn(index: 3, child: Text('item')),
    ));

    await tester.pumpAndSettle();

    expect(find.text('item'), findsOneWidget);
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 1.0);
  });

  testWidgets('a later index takes longer to finish than an earlier one', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(children: [
        StaggeredFadeIn(index: 0, child: Text('first')),
        StaggeredFadeIn(index: 5, child: Text('second')),
      ]),
    ));

    await tester.pump(const Duration(milliseconds: 260));

    final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(opacities[0].opacity, 1.0);
    expect(opacities[1].opacity, lessThan(1.0));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/staggered_fade_in_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'pasala/core/widgets/staggered_fade_in.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/widgets/staggered_fade_in.dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Fades and slides [child] into place, finishing later for higher
/// [index] values so a list's items appear to cascade in rather than pop
/// in all at once. The stagger is capped so a long list doesn't take
/// seconds to finish animating.
class StaggeredFadeIn extends StatelessWidget {
  const StaggeredFadeIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const _stepMs = 60;
  static const _maxDelayMs = 480;

  @override
  Widget build(BuildContext context) {
    final delay = Duration(
      milliseconds: (index * _stepMs).clamp(0, _maxDelayMs),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: PasalaTokens.motionBase + delay,
      curve: Curves.easeOut,
      builder: (context, value, animatedChild) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: animatedChild,
        ),
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/staggered_fade_in_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/staggered_fade_in.dart test/core/widgets/staggered_fade_in_test.dart
git commit -m "feat: add StaggeredFadeIn shared widget"
```

---

### Task 6: Extend `EmptyState` with an optional illustration image

**Files:**
- Modify: `lib/core/widgets/empty_state.dart`
- Test: `test/core/widgets/empty_state_test.dart`

**Interfaces:**
- Consumes: nothing new (accepts a raw asset path string, so it stays decoupled from `AppAssets`).
- Produces: `EmptyState`'s new optional `image` (`String?`) parameter — when set, replaces the icon with a small rounded illustration. Used by `MyBookingsScreen` (Task 15).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/empty_state.dart';

void main() {
  testWidgets('shows the icon when no image is given', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyState(icon: Icons.event_busy_outlined, title: 'No bookings yet'),
      ),
    ));

    expect(find.byIcon(Icons.event_busy_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the image instead of the icon when one is given', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No bookings yet',
          image: 'assets/images/facade_daytime.webp',
        ),
      ),
    ));

    expect(find.byIcon(Icons.event_busy_outlined), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/empty_state_test.dart`
Expected: FAIL — `Error: No named parameter with the name 'image'`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/widgets/empty_state.dart — full replacement
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Shown when a query succeeded and returned nothing. Distinct from an
/// error: nothing is wrong, there is simply nothing yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.image,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// An optional bundled illustration asset path. When set, it replaces
  /// [icon] entirely rather than sitting alongside it.
  final String? image;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(PasalaTokens.radiusMd),
                child: Image.asset(
                  image!,
                  width: 160,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              )
            else
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/empty_state_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/empty_state.dart test/core/widgets/empty_state_test.dart
git commit -m "feat: let EmptyState show a bundled illustration image"
```

---

### Task 7: App shell — brand mark in the app bar

**Files:**
- Modify: `lib/features/shell/app_shell.dart:65-69`
- Modify: `test/features/shell/app_shell_test.dart`

**Interfaces:**
- Consumes: `BrandMark` (Task 4), `PasalaTokens.wideBreakpoint` (Task 2).
- Produces: nothing new for later tasks — this is a leaf change.

- [ ] **Step 1: Write the failing test**

Add this test to `test/features/shell/app_shell_test.dart` (add the import at the top, and the test at the end of `main()`, alongside the existing four tests — do not remove or alter those):

```dart
// add to the import list at the top:
import 'package:pasala/core/widgets/brand_mark.dart';

// add inside main(), after the existing tests:
  testWidgets('shows the brand mark in the app bar', (tester) async {
    await tester.pumpWidget(_appFor(_customer));
    await tester.pumpAndSettle();

    expect(find.byType(BrandMark), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/shell/app_shell_test.dart`
Expected: FAIL — `findsOneWidget` fails with `findsNothing` (no `BrandMark` in the tree yet).

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/shell/app_shell.dart — add import near the top:
import '../../core/widgets/brand_mark.dart';
```

```dart
// lib/features/shell/app_shell.dart:65-69 — replace:
    final wide = MediaQuery.sizeOf(context).width >= 840;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pasala Resorts'),
// with:
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const BrandMark(),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/shell/app_shell_test.dart`
Expected: PASS (all five tests, including the four pre-existing ones)

- [ ] **Step 5: Commit**

```bash
git add lib/features/shell/app_shell.dart test/features/shell/app_shell_test.dart
git commit -m "feat: show the brand mark in the app shell's app bar"
```

---

### Task 8: `AppSplashOverlay` — branded cold-start moment

**Files:**
- Create: `lib/core/widgets/app_splash_overlay.dart`
- Modify: `lib/main.dart`
- Test: `test/core/widgets/app_splash_overlay_test.dart`

**Interfaces:**
- Consumes: `BrandMark` (Task 4), `PasalaTokens.motionBase` (existing).
- Produces: `AppSplashOverlay({required Widget child})`, wired into `PasalaApp` via `MaterialApp.router`'s `builder`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/app_splash_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/tokens.dart';
import 'package:pasala/core/widgets/app_splash_overlay.dart';
import 'package:pasala/core/widgets/brand_mark.dart';

void main() {
  testWidgets('shows the brand mark, then removes itself after the fade', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: AppSplashOverlay(child: Text('home content')),
    ));

    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.text('home content'), findsOneWidget);

    await tester.pump(PasalaTokens.motionBase * 3);
    await tester.pump(PasalaTokens.motionBase);

    expect(find.byType(BrandMark), findsNothing);
    expect(find.text('home content'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/app_splash_overlay_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'pasala/core/widgets/app_splash_overlay.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/widgets/app_splash_overlay.dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'brand_mark.dart';

/// A brief branded fade-in shown once per cold start, layered on top of
/// whatever [child] the router first builds. Purely cosmetic — it does
/// not gate on or wait for auth state, so it can never block navigation
/// if a network call is slow.
class AppSplashOverlay extends StatefulWidget {
  const AppSplashOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<AppSplashOverlay> createState() => _AppSplashOverlayState();
}

class _AppSplashOverlayState extends State<AppSplashOverlay> {
  bool _showOverlay = true;
  double _opacity = 1;

  @override
  void initState() {
    super.initState();
    Future.delayed(PasalaTokens.motionBase, () {
      if (mounted) setState(() => _opacity = 0);
    });
    Future.delayed(PasalaTokens.motionBase * 2, () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showOverlay)
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _opacity,
              duration: PasalaTokens.motionBase,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const Center(
                  child: BrandMark(
                    size: BrandMarkSize.splash,
                    showWordmark: false,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

```dart
// lib/main.dart — full replacement
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_splash_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: PasalaApp()));
}

class PasalaApp extends ConsumerWidget {
  const PasalaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Pasala Resorts',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) =>
            AppSplashOverlay(child: child ?? const SizedBox()),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/app_splash_overlay_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/app_splash_overlay.dart lib/main.dart test/core/widgets/app_splash_overlay_test.dart
git commit -m "feat: add a branded cold-start splash overlay"
```

---

### Task 9: Fade-slide page transitions for customer-facing routes

**Files:**
- Modify: `lib/core/router.dart`
- Test: `test/core/router_transition_test.dart`

**Interfaces:**
- Consumes: `PasalaTokens.motionBase` (existing).
- Produces: `fadeSlidePage(Widget child, GoRouterState state)` returning a `CustomTransitionPage<void>` — a public top-level function in `router.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/router_transition_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/router.dart';

void main() {
  testWidgets(
      'fadeSlidePage wraps the destination in a fade and slide transition',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        GoRoute(
          path: '/a',
          pageBuilder: (_, state) => fadeSlidePage(const Text('Screen A'), state),
        ),
        GoRoute(
          path: '/b',
          pageBuilder: (_, state) => fadeSlidePage(const Text('Screen B'), state),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('Screen A'), findsOneWidget);

    router.go('/b');
    await tester.pump();

    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('Screen B'), findsOneWidget);
    expect(find.text('Screen A'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/router_transition_test.dart`
Expected: FAIL — `Error: The function 'fadeSlidePage' isn't defined`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/router.dart — add imports at the top, alongside the existing ones:
import 'package:flutter/material.dart';

import 'theme/tokens.dart';
```

```dart
// lib/core/router.dart — add this function above `routerProvider`:

/// A fade + slight upward slide, used for every customer-facing route so
/// navigation reads as one continuous surface rather than a hard cut.
/// Admin/staff routes keep GoRouter's default transition — this is a
/// customer-facing polish detail, not a platform-wide behaviour change.
Page<void> fadeSlidePage(Widget child, GoRouterState state) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: PasalaTokens.motionBase,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
```

Now replace `builder:` with `pageBuilder:` for the customer-facing routes only. In the `routes:` list of `routerProvider`:

```dart
// replace:
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
// with:
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => fadeSlidePage(const LoginScreen(), state),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (_, state) => fadeSlidePage(const SignupScreen(), state),
      ),
```

```dart
// replace:
          GoRoute(path: '/', builder: (_, _) => const BrowseScreen()),
          GoRoute(
            path: '/property/:id',
            builder: (_, state) =>
                PropertyScreen(propertyId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/book/:unitId',
            builder: (_, state) =>
                BookingScreen(unitId: state.pathParameters['unitId']!),
          ),
          GoRoute(
            path: '/booking/:id',
            builder: (_, state) =>
                ConfirmationScreen(reservationId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/bookings', builder: (_, _) => const MyBookingsScreen()),
          GoRoute(
            path: '/booking-detail/:id',
            builder: (_, state) =>
                BookingDetailScreen(reservationId: state.pathParameters['id']!),
          ),
// with:
          GoRoute(
            path: '/',
            pageBuilder: (_, state) => fadeSlidePage(const BrowseScreen(), state),
          ),
          GoRoute(
            path: '/property/:id',
            pageBuilder: (_, state) => fadeSlidePage(
              PropertyScreen(propertyId: state.pathParameters['id']!),
              state,
            ),
          ),
          GoRoute(
            path: '/book/:unitId',
            pageBuilder: (_, state) => fadeSlidePage(
              BookingScreen(unitId: state.pathParameters['unitId']!),
              state,
            ),
          ),
          GoRoute(
            path: '/booking/:id',
            pageBuilder: (_, state) => fadeSlidePage(
              ConfirmationScreen(reservationId: state.pathParameters['id']!),
              state,
            ),
          ),
          GoRoute(
            path: '/bookings',
            pageBuilder: (_, state) =>
                fadeSlidePage(const MyBookingsScreen(), state),
          ),
          GoRoute(
            path: '/booking-detail/:id',
            pageBuilder: (_, state) => fadeSlidePage(
              BookingDetailScreen(reservationId: state.pathParameters['id']!),
              state,
            ),
          ),
```

Every other route (`/404`, all `/admin/*`, `/staff`) keeps its existing `builder:` — do not touch those lines.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/router_transition_test.dart test/core/router_test.dart`
Expected: PASS (both — `router_test.dart` tests the pure `redirectFor` function and is untouched by this change)

- [ ] **Step 5: Commit**

```bash
git add lib/core/router.dart test/core/router_transition_test.dart
git commit -m "feat: fade-slide page transitions on customer-facing routes"
```

---

### Task 10: Login screen redesign

**Files:**
- Modify: `lib/features/auth/login_screen.dart`
- Modify: `test/features/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: `HeroBackdrop` (Task 3), `BrandMark`/`BrandMarkSize` (Task 4), `AppAssets.heroNightAerial` (Task 1).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Add to `test/features/auth/login_screen_test.dart` (add the import, add the test — keep the two existing tests untouched):

```dart
// add to the import list at the top:
import 'package:pasala/core/widgets/brand_mark.dart';

// add inside main(), after the existing tests:
  testWidgets('shows the brand mark above the heading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.byType(BrandMark), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: FAIL — `findsOneWidget` fails with `findsNothing`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/auth/login_screen.dart — full replacement
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/router.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../data/repositories/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(_email.text.trim(), _password.text);
      if (mounted) context.go(landingPathFor(user));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: HeroBackdrop(
        imageAsset: AppAssets.heroNightAerial,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: PasalaTokens.motionBase,
                curve: Curves.easeOut,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 24),
                    child: child,
                  ),
                ),
                child: Card(
                  color: scheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BrandMark(
                            size: BrandMarkSize.splash,
                            showWordmark: false,
                          ),
                          const SizedBox(height: Spacing.md),
                          Text(
                            'Pasala Resorts',
                            style: textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            'Welcome back',
                            style: textTheme.bodyLarge
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.xl),
                          TextFormField(
                            key: const Key('login-email'),
                            controller: _email,
                            decoration: const InputDecoration(labelText: 'Email'),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter your email'
                                : null,
                          ),
                          const SizedBox(height: Spacing.sm),
                          TextFormField(
                            key: const Key('login-password'),
                            controller: _password,
                            decoration:
                                const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter your password'
                                : null,
                          ),
                          const SizedBox(height: Spacing.lg),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: const Text('Sign in'),
                          ),
                          TextButton(
                            onPressed: () => context.go('/signup'),
                            child: const Text('Create an account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: PASS (all three tests, including the two pre-existing ones)

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/login_screen.dart test/features/auth/login_screen_test.dart
git commit -m "feat: redesign login screen with hero photo and brand mark"
```

---

### Task 11: Signup screen redesign

**Files:**
- Modify: `lib/features/auth/signup_screen.dart`
- Modify: `test/features/auth/signup_screen_test.dart`

**Interfaces:**
- Consumes: same as Task 10.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Add to `test/features/auth/signup_screen_test.dart` (add the import, add the test — keep the two existing tests untouched):

```dart
// add to the import list at the top:
import 'package:pasala/core/widgets/brand_mark.dart';

// add inside main(), after the existing tests:
  testWidgets('shows the brand mark above the heading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    expect(find.byType(BrandMark), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/signup_screen_test.dart`
Expected: FAIL — `findsOneWidget` fails with `findsNothing`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/auth/signup_screen.dart — full replacement
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/router.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../data/repositories/auth_repository.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await ref.read(authRepositoryProvider).signUp(
            email: _email.text.trim(),
            password: _password.text,
            fullName: _name.text.trim(),
          );
      if (mounted) context.go(landingPathFor(user));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: HeroBackdrop(
        imageAsset: AppAssets.heroNightAerial,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: PasalaTokens.motionBase,
                curve: Curves.easeOut,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 24),
                    child: child,
                  ),
                ),
                child: Card(
                  color: scheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BrandMark(
                            size: BrandMarkSize.splash,
                            showWordmark: false,
                          ),
                          const SizedBox(height: Spacing.md),
                          Text(
                            'Pasala Resorts',
                            style: textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            'Create your account',
                            style: textTheme.bodyLarge
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.xl),
                          TextFormField(
                            key: const Key('signup-name'),
                            controller: _name,
                            decoration:
                                const InputDecoration(labelText: 'Full name'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: Spacing.sm),
                          TextFormField(
                            key: const Key('signup-email'),
                            controller: _email,
                            decoration: const InputDecoration(labelText: 'Email'),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter your email'
                                : null,
                          ),
                          const SizedBox(height: Spacing.sm),
                          TextFormField(
                            key: const Key('signup-password'),
                            controller: _password,
                            decoration:
                                const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            validator: (v) => (v == null || v.length < 8)
                                ? 'Use at least 8 characters'
                                : null,
                          ),
                          const SizedBox(height: Spacing.lg),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: const Text('Create account'),
                          ),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child:
                                const Text('Already have an account? Sign in'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/auth/signup_screen_test.dart`
Expected: PASS (all three tests, including the two pre-existing ones)

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/signup_screen.dart test/features/auth/signup_screen_test.dart
git commit -m "feat: redesign signup screen with hero photo and brand mark"
```

---

### Task 12: Browse screen — hero header, responsive grid, animated cards

**Files:**
- Modify: `lib/features/browse/browse_screen.dart`
- Create: `test/features/browse/browse_screen_test.dart`

**Interfaces:**
- Consumes: `HeroBackdrop` (Task 3), `StaggeredFadeIn` (Task 5), `AppAssets.heroDayAerial` (Task 1), `PasalaTokens.wideBreakpoint`/`displayWeight`/`displayLetterSpacing`/`motionFast` (Task 2/existing).
- Produces: `PropertyCard` becomes a `StatefulWidget` (same public constructor: `PropertyCard({Key? key, required Property property, VoidCallback? onTap})`) with a hover scale effect and a `Hero(tag: 'property-media-${property.id}', ...)` around its media — Task 13 (`PropertyScreen`) matches this exact tag format.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/browse/browse_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/features/browse/browse_screen.dart';
import 'package:pasala/features/browse/providers.dart';

const _properties = [
  Property(
    id: 'a1',
    name: 'Pasala Riverside',
    slug: 'riverside',
    description: null,
    address: null,
    images: [],
    amenities: [],
    checkInTime: '14:00',
    checkOutTime: '11:00',
    isActive: true,
  ),
  Property(
    id: 'a2',
    name: 'Pasala Hilltop',
    slug: 'hilltop',
    description: null,
    address: null,
    images: [],
    amenities: [],
    checkInTime: '14:00',
    checkOutTime: '11:00',
    isActive: true,
  ),
];

Widget _appFor(List<Property> properties) => ProviderScope(
      overrides: [
        propertiesProvider.overrideWith((ref) => Future.value(properties)),
      ],
      child: const MaterialApp(home: Scaffold(body: BrowseScreen())),
    );

void main() {
  testWidgets('shows a hero header above the property list', (tester) async {
    await tester.pumpWidget(_appFor(_properties));
    await tester.pumpAndSettle();

    expect(find.text('Discover your stay'), findsOneWidget);
    expect(find.text('Pasala Riverside'), findsOneWidget);
    expect(find.text('Pasala Hilltop'), findsOneWidget);
  });

  testWidgets('lays properties out in a grid on a wide viewport', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor(_properties));
    await tester.pumpAndSettle();

    expect(find.byType(SliverGrid), findsOneWidget);
  });

  testWidgets('lays properties out in a single column on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor(_properties));
    await tester.pumpAndSettle();

    expect(find.byType(SliverList), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/browse/browse_screen_test.dart`
Expected: FAIL — `find.text('Discover your stay')` finds nothing; `SliverGrid`/`SliverList` are not present (the current screen uses a plain `ListView.builder`).

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/browse/browse_screen.dart — full replacement
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../core/widgets/staggered_fade_in.dart';
import '../../data/models/property.dart';
import 'providers.dart';

class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return AsyncView(
      value: properties,
      onRetry: () => ref.invalidate(propertiesProvider),
      empty: () => const EmptyState(
        icon: Icons.villa_outlined,
        title: 'No properties yet',
        message: 'Ask an admin to add one.',
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(propertiesProvider),
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _BrowseHero()),
            if (wide)
              SliverPadding(
                padding: const EdgeInsets.all(Spacing.md),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 420,
                    mainAxisSpacing: Spacing.md,
                    crossAxisSpacing: Spacing.md,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => StaggeredFadeIn(
                      key: ValueKey(list[i].id),
                      index: i,
                      child: PropertyCard(
                        property: list[i],
                        onTap: () => context.go('/property/${list[i].id}'),
                      ),
                    ),
                    childCount: list.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(Spacing.md),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: StaggeredFadeIn(
                        key: ValueKey(list[i].id),
                        index: i,
                        child: PropertyCard(
                          property: list[i],
                          onTap: () => context.go('/property/${list[i].id}'),
                        ),
                      ),
                    ),
                    childCount: list.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrowseHero extends StatelessWidget {
  const _BrowseHero();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;
    return SizedBox(
      // Taller on wide/web layouts so the hero doesn't look like a thin
      // strip on a desktop-width browser window (spec section 7).
      height: wide ? 280 : 200,
      child: HeroBackdrop(
        imageAsset: AppAssets.heroDayAerial,
        scrimOpacity: 0.35,
        child: const Padding(
          padding: EdgeInsets.all(Spacing.lg),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              'Discover your stay',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: PasalaTokens.displayWeight,
                letterSpacing: PasalaTokens.displayLetterSpacing,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A property's header art: its first photo when one exists, otherwise a
/// tinted placeholder carrying the property's initial. Reused by
/// [PropertyCard] (16:9, inside a card) and `PropertyScreen`'s full-width
/// header, so the "broken image never shows a customer an error box" rule
/// only has to be written once.
class PropertyMedia extends StatelessWidget {
  const PropertyMedia({super.key, required this.property});

  final Property property;

  String get _initial =>
      property.name.trim().isEmpty ? '?' : property.name.trim()[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    // Without a semantics label a screen reader announces either nothing
    // (the Image.network path) or just the bare initial letter (the
    // placeholder path) -- neither tells a screen-reader user which
    // property this card is for. Both paths get the property's name plus a
    // short descriptor instead, applied once here rather than inside
    // [_PropertyPlaceholder] itself -- that widget is also reused as
    // Image.network's errorBuilder result, and wrapping it there too would
    // nest a second, conflicting Semantics node under this one whenever a
    // photo URL fails to load.
    if (property.images.isEmpty) {
      return Semantics(
        label: '${property.name}, no photo available',
        image: true,
        // Otherwise the placeholder's own "initial letter" Text widget
        // merges its literal text ("P") into this label instead of being
        // silenced by it, and a screen reader reads both.
        excludeSemantics: true,
        child: _PropertyPlaceholder(initial: _initial),
      );
    }

    return Semantics(
      label: '${property.name} property photo',
      image: true,
      excludeSemantics: true,
      child: Image.network(
        property.images.first,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // This widget already supplies the semantics above; without this,
        // Image.network would additionally wrap itself in its own
        // semantics node (unlabelled, since no `semanticLabel` is passed),
        // producing a redundant nested image node either way.
        excludeFromSemantics: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const _PropertyLoadingBox();
        },
        // A broken or unreachable URL must never surface Flutter's red error
        // box to a customer -- it falls back to the same tinted placeholder
        // used when there is no image at all.
        errorBuilder: (context, error, stackTrace) =>
            _PropertyPlaceholder(initial: _initial),
      ),
    );
  }
}

class _PropertyPlaceholder extends StatelessWidget {
  const _PropertyPlaceholder({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PropertyLoadingBox extends StatelessWidget {
  const _PropertyLoadingBox();

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
}

/// Up to four amenity chips styled as metadata rather than actions, with a
/// `+N` chip absorbing the rest. Amenities never appear elsewhere on the
/// card, so styling this once here is enough.
class AmenityWrap extends StatelessWidget {
  const AmenityWrap({super.key, required this.amenities, this.max = 4});

  final List<String> amenities;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (amenities.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final shown = amenities.take(max).toList();
    final overflow = amenities.length - shown.length;

    Widget metaChip(String label) => Chip(
          label: Text(label),
          labelStyle: labelStyle,
          backgroundColor: scheme.surfaceContainerHigh,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
        );

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      children: [
        for (final a in shown) metaChip(a),
        if (overflow > 0) metaChip('+$overflow'),
      ],
    );
  }
}

/// The tallest a card's media area is allowed to get. A plain 16:9 area
/// scales with the card's width, which is fine on a phone but turns into a
/// wall of image on a wide desktop list -- capping the height keeps the card
/// proportioned like a card instead of a banner while staying 16:9 (or
/// narrower) on anything phone-sized.
const double _cardMediaMaxHeight = 220;

class PropertyCard extends StatefulWidget {
  const PropertyCard({super.key, required this.property, this.onTap});

  final Property property;
  final VoidCallback? onTap;

  @override
  State<PropertyCard> createState() => _PropertyCardState();
}

class _PropertyCardState extends State<PropertyCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final property = widget.property;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.02 : 1.0,
        duration: PasalaTokens.motionFast,
        curve: Curves.easeOut,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final height = (constraints.maxWidth * 9 / 16)
                        .clamp(0, _cardMediaMaxHeight)
                        .toDouble();
                    return SizedBox(
                      width: double.infinity,
                      height: height,
                      child: Hero(
                        tag: 'property-media-${property.id}',
                        child: PropertyMedia(property: property),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(property.name, style: textTheme.titleLarge),
                      if (property.address != null) ...[
                        const SizedBox(height: Spacing.xs),
                        Text(
                          property.address!,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: Spacing.sm),
                      AmenityWrap(amenities: property.amenities),
                      const SizedBox(height: Spacing.sm),
                      // Belt-and-suspenders: Property.fromJson already normalises
                      // Postgres's `HH:mm:ss` down to `HH:mm`, but this display
                      // line calls normalizeTime again so a directly-constructed
                      // Property (as in tests, or a future caller) can never leak
                      // ":ss" onto the card.
                      Text(
                        'Check-in ${Property.normalizeTime(property.checkInTime)} · '
                        'Check-out ${Property.normalizeTime(property.checkOutTime)}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/browse/browse_screen_test.dart test/features/browse/property_card_test.dart`
Expected: PASS (both — `property_card_test.dart` must still pass unmodified)

- [ ] **Step 5: Commit**

```bash
git add lib/features/browse/browse_screen.dart test/features/browse/browse_screen_test.dart
git commit -m "feat: browse screen hero header, responsive grid, animated cards"
```

---

### Task 13: Property detail — shared-element hero transition

**Files:**
- Modify: `lib/features/browse/property_screen.dart:36-41`
- Modify: `test/features/browse/property_card_test.dart`
- Create: `test/features/browse/property_screen_widget_test.dart`

**Interfaces:**
- Consumes: `Hero` tag format `'property-media-${id}'` established in Task 12.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/browse/property_card_test.dart` (add inside `main()`, after the existing tests — keep those untouched):

```dart
  testWidgets('wraps its media in a Hero tagged with the property id', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyCard(property: property)),
    ));

    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag == 'property-media-a1'),
      findsOneWidget,
    );
  });
```

```dart
// test/features/browse/property_screen_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/features/browse/property_screen.dart';
import 'package:pasala/features/browse/providers.dart';

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

const _units = <Unit>[
  Unit(
    id: 'u1',
    propertyId: 'p1',
    name: 'Dallas',
    capacityBase: 2,
    capacityMax: 4,
    bookingMode: BookingMode.nightly,
    isActive: true,
  ),
];

void main() {
  testWidgets('wraps the header media in a Hero tagged with the property id', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyProvider('p1').overrideWith((ref) => Future.value(_property)),
          unitsProvider('p1').overrideWith((ref) => Future.value(_units)),
        ],
        child: const MaterialApp(home: PropertyScreen(propertyId: 'p1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag == 'property-media-p1'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/browse/property_card_test.dart test/features/browse/property_screen_widget_test.dart`
Expected: FAIL — no `Hero` with the expected tag exists yet in `property_screen.dart` (the `property_card_test.dart` addition already passes from Task 12's change, so only the new file fails).

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/browse/property_screen.dart:36-41 — replace:
          AspectRatio(
            aspectRatio: 16 / 9,
            child: PropertyMedia(property: p),
          ),
// with:
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Hero(
              tag: 'property-media-${p.id}',
              child: PropertyMedia(property: p),
            ),
          ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/browse/property_card_test.dart test/features/browse/property_screen_widget_test.dart test/features/browse/property_screen_test.dart`
Expected: PASS (all three files)

- [ ] **Step 5: Commit**

```bash
git add lib/features/browse/property_screen.dart test/features/browse/property_card_test.dart test/features/browse/property_screen_widget_test.dart
git commit -m "feat: shared-element hero transition from browse to property detail"
```

---

### Task 14: Booking confirmation — hero backdrop and checkmark animation

**Files:**
- Modify: `lib/features/booking/confirmation_screen.dart`
- Create: `test/features/booking/confirmation_screen_test.dart`

**Interfaces:**
- Consumes: `HeroBackdrop` (Task 3), `AppAssets.eventStringLights` (Task 1).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/booking/confirmation_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/features/booking/confirmation_screen.dart';
import 'package:pasala/features/booking/providers.dart';

final _reservation = Reservation(
  id: 'r1',
  unitId: 'u1',
  start: DateTime.utc(2026, 8, 20),
  end: DateTime.utc(2026, 8, 22),
  kind: ReservationKind.booking,
  status: ReservationStatus.confirmed,
  guests: 2,
);

const _unit = Unit(
  id: 'u1',
  propertyId: 'p1',
  name: 'Dallas Cottage',
  capacityBase: 2,
  capacityMax: 4,
  bookingMode: BookingMode.nightly,
  isActive: true,
);

Widget _appFor() {
  final router = GoRouter(
    initialLocation: '/booking/r1',
    routes: [
      GoRoute(
        path: '/booking/:id',
        builder: (_, state) =>
            ConfirmationScreen(reservationId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/bookings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      reservationProvider('r1').overrideWith((ref) => Future.value(_reservation)),
      unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows the unit name and stay dates once confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.text('Dallas Cottage'), findsOneWidget);
    expect(find.textContaining('Aug'), findsWidgets);
  });

  testWidgets('animates the checkmark in with a scale transition', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pump();

    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking/confirmation_screen_test.dart`
Expected: FAIL — `find.byType(TweenAnimationBuilder<double>)` finds nothing (the current screen has no animation).

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/booking/confirmation_screen.dart — full replacement
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../data/models/reservation.dart';
import 'providers.dart';

class ConfirmationScreen extends ConsumerWidget {
  const ConfirmationScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationAsync = ref.watch(reservationProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking confirmed')),
      body: AsyncView(
        value: reservationAsync,
        onRetry: () => ref.invalidate(reservationProvider(reservationId)),
        data: (reservation) => _Confirmed(reservation: reservation),
      ),
    );
  }
}

class _Confirmed extends ConsumerWidget {
  const _Confirmed({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitAsync = ref.watch(unitByIdProvider(reservation.unitId));
    final quote = reservation.quote;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return HeroBackdrop(
      imageAsset: AppAssets.eventStringLights,
      scrimOpacity: 0.7,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: PasalaTokens.motionBase,
                      curve: Curves.elasticOut,
                      builder: (context, value, child) => Transform.scale(
                        scale: value,
                        child: child,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(Spacing.md),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          color: scheme.onPrimaryContainer,
                          size: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text(
                      unitAsync.value?.name ?? 'Your booking',
                      style: textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      '${formatDay(reservation.start.toLocal())} – '
                      '${formatDay(reservation.end.toLocal())}',
                      style: textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (quote != null) ...[
                      const SizedBox(height: Spacing.sm),
                      Text(
                        formatInr(quote.total),
                        style: textTheme.titleLarge
                            ?.copyWith(color: scheme.primary),
                      ),
                    ],
                    const SizedBox(height: Spacing.xl),
                    FilledButton(
                      onPressed: () => context.go('/bookings'),
                      child: const Text('View my bookings'),
                    ),
                    const SizedBox(height: Spacing.sm),
                    OutlinedButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Browse more'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/booking/confirmation_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/confirmation_screen.dart test/features/booking/confirmation_screen_test.dart
git commit -m "feat: hero backdrop and checkmark animation on booking confirmation"
```

---

### Task 15: My Bookings — empty-state illustration and staggered list

**Files:**
- Modify: `lib/features/account/my_bookings_screen.dart`
- Create: `test/features/account/my_bookings_screen_test.dart`

**Interfaces:**
- Consumes: `EmptyState.image` (Task 6), `StaggeredFadeIn` (Task 5), `AppAssets.facadeDaytime` (Task 1).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/account/my_bookings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/account/my_bookings_screen.dart';
import 'package:pasala/features/account/providers.dart';

void main() {
  testWidgets('shows the facade illustration in the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myBookingsProvider
              .overrideWith((ref) => Future.value(const <Reservation>[])),
        ],
        child: const MaterialApp(home: MyBookingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No bookings yet'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shows bookings with a staggered entrance wrapper', (
    tester,
  ) async {
    final reservation = Reservation(
      id: 'r1',
      unitId: 'u1',
      start: DateTime(2026, 8, 3, 14),
      end: DateTime(2026, 8, 5, 11),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      guests: 2,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myBookingsProvider.overrideWith((ref) => Future.value([reservation])),
        ],
        child: const MaterialApp(home: MyBookingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmed'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/account/my_bookings_screen_test.dart`
Expected: FAIL — `find.byType(Image)` finds nothing in the empty state (the current `EmptyState` call has no `image`).

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/account/my_bookings_screen.dart:1-54 — replace the imports and MyBookingsScreen class with:
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/staggered_fade_in.dart';
import '../../data/models/reservation.dart';
import '../booking/booking_screen.dart' show formatHoldRemaining;
import 'providers.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: AsyncView(
        value: bookingsAsync,
        onRetry: () => ref.invalidate(myBookingsProvider),
        empty: () => const EmptyState(
          icon: Icons.event_busy_outlined,
          image: AppAssets.facadeDaytime,
          title: 'No bookings yet',
          message: 'Your stays will appear here.',
        ),
        data: (bookings) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: bookings.length,
          itemBuilder: (context, i) {
            final reservation = bookings[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: StaggeredFadeIn(
                key: ValueKey(reservation.id),
                index: i,
                child: BookingTile(
                  reservation: reservation,
                  // A hold is a 15-minute reservation, not a finished
                  // booking -- there is nothing to view or cancel about it
                  // on a read-only detail screen. `BookingScreen` is the
                  // only place with a live pay/resume affordance, so that is
                  // where a tap on a hold belongs, rather than a dead end.
                  onTap: reservation.isHold
                      ? () => context.go('/book/${reservation.unitId}')
                      : () => context.push('/booking-detail/${reservation.id}'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
```

The `BookingTile` class below `MyBookingsScreen` in the same file is unchanged — leave it exactly as it is.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/account/my_bookings_screen_test.dart test/features/account/booking_tile_test.dart`
Expected: PASS (both — `booking_tile_test.dart` constructs `BookingTile` directly and must still pass unmodified)

- [ ] **Step 5: Commit**

```bash
git add lib/features/account/my_bookings_screen.dart test/features/account/my_bookings_screen_test.dart
git commit -m "feat: My Bookings empty-state illustration and staggered list entrance"
```

---

### Task 16: Full-suite verification and manual walkthrough

**Files:** none (verification only)

**Interfaces:** none

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full automated test suite**

Run: `flutter test`
Expected: every test passes, including all files touched in Tasks 1–15 and every pre-existing test in the suite (in particular `test/core/router_test.dart`, `test/core/theme/tokens_test.dart`, `test/features/shell/app_shell_test.dart`, `test/features/browse/property_screen_test.dart`, `test/features/account/booking_tile_test.dart`, and the full `test/features/booking/` and `test/features/admin/` suites, none of which this plan touches).

- [ ] **Step 3: Manual browser walkthrough — narrow viewport**

Run: `make run-web`, open the app, resize the browser to roughly 400px wide (or use the browser devtools' mobile emulation), then walk:

1. Land on `/login` — confirm the night aerial photo fills the background, the logo mark appears above "Pasala Resorts", and the form panel is legible.
2. Tap "Create an account" — confirm the fade-slide transition, and that `/signup` matches the same visual treatment.
3. Sign in with `ravi@example.com` / `password123` — confirm landing on `/` (Browse) shows the daytime aerial hero with "Discover your stay", and property cards fade in as a single column.
4. Tap a property card — confirm the shared-element photo transition into the property detail screen.
5. Start a booking, reach `/booking/:id` (confirmation) — confirm the event-lights background and the checkmark's pop-in animation.
6. Go to `/bookings` — confirm existing bookings list renders (or, for an account with none, the facade illustration in the empty state).

- [ ] **Step 4: Manual browser walkthrough — wide viewport**

Resize to a desktop width (≥ 1000px) and repeat steps 3–6 above, additionally confirming:
- Browse's property list renders as a multi-column grid, not a single column.
- The app shell shows the navigation rail (not the bottom bar) with the brand mark still visible in the app bar.

- [ ] **Step 5: Commit (only if the walkthrough surfaced a formatting fix)**

If `dart format --output=none --set-exit-if-changed .` reports any file needing formatting, run `dart format .` and commit:

```bash
git add -A
git commit -m "chore: format farmhouse redesign files"
```

If nothing needed fixing, skip this step — there is nothing to commit.
