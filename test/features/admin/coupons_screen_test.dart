import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/coupon.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/coupon_repository.dart';
import 'package:pasala/features/admin/coupon_form.dart';
import 'package:pasala/features/admin/coupons_screen.dart';

import '../../support/fake_coupon_source.dart';

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership _value;
  @override
  ResortMembership? build() => _value;
}

const _adminM = ResortMembership(
    propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

const _gita = ResortGuest(
    userId: 'g1', email: 'gita@example.com', fullName: 'Gita Guest');

final _coupons = [
  couponRow(
    id: 'c1',
    code: 'SAVE10',
    value: 10,
    usageLimit: 10,
    usedCount: 3,
    validUntil: DateTime(2026, 10, 31),
  ),
  couponRow(
    id: 'c2',
    code: 'VIPGITA',
    kind: CouponKind.fixed,
    value: 500,
    minAmount: 5000,
    validFrom: DateTime(2026, 10, 1),
    guest: _gita,
    status: CouponStatus.scheduled,
  ),
  couponRow(
    id: 'c3',
    code: 'OLD',
    isActive: false,
    status: CouponStatus.inactive,
  ),
];

/// Mounts the screen inside a ShellRoute, as the real router does, so a
/// dialog that popped the screen's navigator instead of itself would blank
/// the page (the bug fixed in 66792f0).
Future<void> _pump(WidgetTester tester, FakeCouponSource source) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/admin/coupons',
    routes: [
      ShellRoute(
        builder: (_, _, child) => Scaffold(body: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, _) => const Text('Admin home')),
          GoRoute(
              path: '/admin/coupons',
              builder: (_, _) => const CouponsScreen()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      couponSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(() => _FixedResort(_adminM)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Finder _inTile(String id, Finder matching) => find.descendant(
    of: find.byKey(Key('coupon-tile-$id')), matching: matching);

void main() {
  testWidgets('shows each coupon with its status, discount, dates, usage and '
      'audience', (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    expect(source.listCalls, ['p1']);
    expect(find.text('Coupons'), findsOneWidget);

    expect(_inTile('c1', find.text('SAVE10')), findsOneWidget);
    expect(_inTile('c1', find.text('Active')), findsOneWidget);
    expect(_inTile('c1', find.byIcon(Icons.check_circle_outline)),
        findsOneWidget);
    expect(_inTile('c1', find.text('10% off')), findsOneWidget);
    expect(_inTile('c1', find.text('Until 31 Oct 2026')), findsOneWidget);
    expect(_inTile('c1', find.text('Used 3 of 10 · Everyone')), findsOneWidget);
    expect(_inTile('c1', find.text('Deactivate')), findsOneWidget);

    expect(_inTile('c2', find.text('Scheduled')), findsOneWidget);
    expect(_inTile('c2', find.text('₹500 off · Min ₹5,000')), findsOneWidget);
    expect(_inTile('c2', find.text('From 1 Oct 2026')), findsOneWidget);
    expect(_inTile('c2', find.text('Used 0 · Only Gita Guest')),
        findsOneWidget);

    expect(_inTile('c3', find.text('Inactive')), findsOneWidget);
    expect(_inTile('c3', find.text('No date limits')), findsOneWidget);
    expect(_inTile('c3', find.text('Activate')), findsOneWidget);
  });

  testWidgets('no coupons yet shows the empty state', (tester) async {
    await _pump(tester, FakeCouponSource());

    expect(find.text('No coupons yet'), findsOneWidget);
    expect(find.byKey(const Key('new-coupon')), findsOneWidget);
  });

  testWidgets('a load error shows the reason and retries', (tester) async {
    final source = FakeCouponSource()..listError = const NetworkFailure();
    await _pump(tester, source);

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
    source.listError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(source.listCalls, ['p1', 'p1']);
    expect(find.text('No coupons yet'), findsOneWidget);
  });

  testWidgets('New coupon opens the form, and a save refreshes the list',
      (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('new-coupon')));
    await tester.pumpAndSettle();
    expect(find.byType(CouponForm), findsOneWidget);

    await tester.enterText(find.byKey(const Key('coupon-code')), 'FESTIVE');
    await tester.enterText(find.byKey(const Key('coupon-value')), '12');
    await tester.ensureVisible(find.byKey(const Key('coupon-save')));
    await tester.tap(find.byKey(const Key('coupon-save')));
    await tester.pumpAndSettle();

    expect(source.createCalls.single.$1, 'p1');
    expect(source.createCalls.single.$2.code, 'FESTIVE');
    expect(find.byType(CouponForm), findsNothing);
    expect(source.listCalls, ['p1', 'p1']);
    expect(find.text('Coupon created'), findsOneWidget);
  });

  testWidgets('tapping a coupon opens it for editing; closing refetches '
      'nothing', (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    await tester.tap(_inTile('c1', find.text('SAVE10')));
    await tester.pumpAndSettle();
    expect(find.text('Edit SAVE10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('coupon-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(CouponForm), findsNothing);
    expect(find.byType(CouponsScreen), findsOneWidget);
    expect(source.listCalls, ['p1']);
  });

  testWidgets('Deactivate asks first; inside a ShellRoute the dialog closes, '
      'not the page', (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    // Cancel first: the dialog closes, the page stays, nothing is sent.
    await tester.tap(find.byKey(const Key('coupon-toggle-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate SAVE10?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CouponsScreen), findsOneWidget);
    expect(source.setActiveCalls, isEmpty);

    // Confirm: deactivated, the dialog closes, the page stays and refetches.
    await tester.tap(find.byKey(const Key('coupon-toggle-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Deactivate')));
    await tester.pumpAndSettle();

    expect(source.setActiveCalls, [('c1', false)]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CouponsScreen), findsOneWidget);
    expect(source.listCalls, ['p1', 'p1']);
    expect(find.text('SAVE10 deactivated'), findsOneWidget);
  });

  testWidgets('Activate needs no confirmation', (tester) async {
    final source = FakeCouponSource()..coupons = _coupons;
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('coupon-toggle-c3')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(source.setActiveCalls, [('c3', true)]);
    expect(find.text('OLD is active again'), findsOneWidget);
  });

  testWidgets('a refused toggle shows the reason and changes nothing',
      (tester) async {
    final source = FakeCouponSource()
      ..coupons = _coupons
      ..setActiveError = const ResortSuspended();
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('coupon-toggle-c3')));
    await tester.pumpAndSettle();

    expect(find.text('This resort is suspended — changes are disabled.'),
        findsOneWidget);
    expect(source.listCalls, ['p1']);
  });
}
