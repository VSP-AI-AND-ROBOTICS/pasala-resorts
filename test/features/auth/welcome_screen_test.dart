// test/features/auth/welcome_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/theme/app_assets.dart';
import 'package:pasala/features/auth/welcome_screen.dart';

void main() {
  Widget appFor() {
    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: '/login', builder: (_, _) => const Text('Login screen')),
        GoRoute(path: '/signup', builder: (_, _) => const Text('Signup screen')),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('Sign In navigates to /login', (tester) async {
    await tester.pumpWidget(appFor());

    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('Sign Up navigates to /signup', (tester) async {
    await tester.pumpWidget(appFor());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Signup screen'), findsOneWidget);
  });

  testWidgets('shows the ResortHub name, not the old Pasala Resorts brand', (
    tester,
  ) async {
    await tester.pumpWidget(appFor());

    expect(find.text('ResortHub'), findsOneWidget);
    expect(find.text('Pasala Resorts'), findsNothing);
  });

  // NOTE (round-1 review, see task-21-report.md "Fixes -- round 1"): this
  // test checks the WIDGET TREE only -- that exactly one `Image` widget
  // exists and its *layout box* starts at x = 0 on a narrow surface. It
  // does **not** pin the "duplicated left strip" visual bug named in the
  // brief (Step 3) and the design spec
  // (docs/superpowers/specs/2026-09-24-resorthub-tenancy-design.md:286:
  // "Fix the welcome screen rendering a strip of the hero image at the
  // left edge"). That artifact, if real, would be a painted/CanvasKit-
  // level duplicate within this single Image's render box, not a second
  // widget or an offset layout box -- `tester.getTopLeft()` cannot see
  // either kind of paint-level duplication, and this exact assertion
  // already passed against the pre-fix code (see the RED run recorded in
  // task-21-report.md). No code change in lib/core/widgets/
  // hero_backdrop.dart, and none in the diff that produced commit
  // 2a03f66, touches hero paint/rendering: there is exactly one
  // `Image.asset` inside a `Stack(fit: StackFit.expand)` both before and
  // after that commit.
  //
  // This assertion is kept because it does guard a real regression class
  // (a second hero Image widget appearing, or the surviving one shifting
  // off the left edge in the widget tree) -- but it must not be read as
  // verification that the painted strip bug is fixed. This track's
  // environment constraints prohibit starting the app or a server, so
  // that verification could not be completed from this worktree.
  //
  // OPEN ITEM -- flagged to the controller: confirm with a live-browser
  // (web/CanvasKit) or golden-image check once environment constraints
  // allow it, before treating brief Step 3 ("find the cause of the
  // duplicated left strip ... and fix it") as resolved.
  testWidgets(
    'hero image: no duplicate widget, and its layout box is flush with '
    'the left edge on a narrow surface (layout-only check -- does not '
    'pin the painted "duplicated left strip" bug; see NOTE above)',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(appFor());
      await tester.pumpAndSettle();

      final heroImage = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                AppAssets.heroNightAerial,
      );
      expect(heroImage, findsOneWidget);
      expect(tester.getTopLeft(heroImage).dx, 0);
    },
  );
}
