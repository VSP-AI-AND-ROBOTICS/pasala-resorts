import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/coupon.dart';
import 'package:pasala/data/repositories/coupon_repository.dart';
import 'package:pasala/features/admin/coupon_form.dart';

import '../../support/fake_coupon_source.dart';

const _gita = ResortGuest(
    userId: 'g1', email: 'gita@example.com', fullName: 'Gita Guest');

/// Opens the form from a button, the way the Coupons screen does, and
/// returns the list the form's result lands in. [picks] answers the date
/// pickers, in order.
Future<List<bool>> _open(
  WidgetTester tester,
  FakeCouponSource source, {
  Coupon? coupon,
  List<DateTime?> picks = const [],
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final results = <bool>[];
  final queue = [...picks];
  await tester.pumpWidget(ProviderScope(
    overrides: [couponSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async => results.add(await showCouponForm(
                context,
                propertyId: 'p1',
                coupon: coupon,
                pickDate: (_, _) async =>
                    queue.isEmpty ? null : queue.removeAt(0),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Finder _foundGuest(String text) => find.descendant(
    of: find.byKey(const Key('coupon-guest-found')), matching: find.text(text));

void main() {
  testWidgets('creates a percentage coupon for everyone, code upper-cased as '
      'typed', (tester) async {
    final source = FakeCouponSource();
    final results = await _open(tester, source);

    expect(find.text('New coupon'), findsOneWidget);
    await _type(tester, 'coupon-code', 'summer-10');
    expect(find.text('SUMMER-10'), findsOneWidget);
    await _type(tester, 'coupon-value', '15');
    await _tapKey(tester, 'coupon-save');

    final (propertyId, draft) = source.createCalls.single;
    expect(propertyId, 'p1');
    expect(draft.toParams(), {
      'p_code': 'SUMMER-10',
      'p_kind': 'percent',
      'p_value': 15,
      'p_min_amount': null,
      'p_valid_from': null,
      'p_valid_until': null,
      'p_usage_limit': null,
      'p_customer': null,
    });
    expect(results, [true]);
    expect(find.byType(CouponForm), findsNothing);
  });

  testWidgets('a fixed-amount coupon with every optional field',
      (tester) async {
    final source = FakeCouponSource();
    await _open(tester, source,
        picks: [DateTime(2026, 10, 1), DateTime(2026, 10, 31)]);

    await _type(tester, 'coupon-code', 'DIWALI');
    await tester.tap(find.text('Fixed amount'));
    await tester.pumpAndSettle();
    expect(find.text('Discount (₹)'), findsOneWidget);
    await _type(tester, 'coupon-value', '500');
    await _type(tester, 'coupon-min-amount', '5000');
    await _tapKey(tester, 'coupon-valid-from');
    await _tapKey(tester, 'coupon-valid-until');
    expect(find.text('1 Oct 2026'), findsOneWidget);
    expect(find.text('31 Oct 2026'), findsOneWidget);
    await _type(tester, 'coupon-usage-limit', '10');
    await _tapKey(tester, 'coupon-save');

    expect(source.createCalls.single.$2.toParams(), {
      'p_code': 'DIWALI',
      'p_kind': 'fixed',
      'p_value': 500,
      'p_min_amount': 5000,
      'p_valid_from': '2026-10-01',
      'p_valid_until': '2026-10-31',
      'p_usage_limit': 10,
      'p_customer': null,
    });
  });

  testWidgets('a bad code, a zero discount or a percentage above 100 never '
      'reaches the server', (tester) async {
    final source = FakeCouponSource();
    final results = await _open(tester, source);

    await _type(tester, 'coupon-code', 'ab');
    await _type(tester, 'coupon-value', '0');
    await _tapKey(tester, 'coupon-save');
    expect(find.text('Use 3–24 letters, numbers, - or _.'), findsOneWidget);
    expect(find.text('Enter a discount above 0.'), findsOneWidget);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _type(tester, 'coupon-value', '150');
    await _tapKey(tester, 'coupon-save');
    expect(find.text('A percentage can be at most 100.'), findsOneWidget);

    expect(source.createCalls, isEmpty);
    expect(results, isEmpty);
  });

  testWidgets('an end date before the start date is refused on the form',
      (tester) async {
    final source = FakeCouponSource();
    await _open(tester, source,
        picks: [DateTime(2026, 10, 10), DateTime(2026, 10, 1)]);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _type(tester, 'coupon-value', '10');
    await _tapKey(tester, 'coupon-valid-from');
    await _tapKey(tester, 'coupon-valid-until');
    await _tapKey(tester, 'coupon-save');

    expect(find.byKey(const Key('coupon-dates-error')), findsOneWidget);
    expect(find.text('The end date must be on or after the start date.'),
        findsOneWidget);
    expect(source.createCalls, isEmpty);
  });

  testWidgets('a picked date can be cleared again', (tester) async {
    final source = FakeCouponSource();
    await _open(tester, source, picks: [DateTime(2026, 10, 1)]);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _type(tester, 'coupon-value', '10');
    await _tapKey(tester, 'coupon-valid-from');
    expect(find.text('1 Oct 2026'), findsOneWidget);
    await _tapKey(tester, 'coupon-valid-from-clear');
    expect(find.text('Any time'), findsOneWidget);
    await _tapKey(tester, 'coupon-save');

    expect(source.createCalls.single.$2.validFrom, isNull);
  });

  testWidgets('finds a guest who booked here and makes the coupon theirs only',
      (tester) async {
    final source = FakeCouponSource()..guests = {'gita@example.com': _gita};
    await _open(tester, source);

    await _type(tester, 'coupon-code', 'VIPGITA');
    await _type(tester, 'coupon-value', '20');
    await tester.tap(find.text('One guest'));
    await tester.pumpAndSettle();
    await _type(tester, 'coupon-guest-email', '  gita@example.com ');
    await _tapKey(tester, 'coupon-guest-find');

    expect(source.findGuestCalls, [('p1', 'gita@example.com')]);
    expect(_foundGuest('Gita Guest'), findsOneWidget);

    await _tapKey(tester, 'coupon-save');
    expect(source.createCalls.single.$2.guestId, 'g1');
  });

  testWidgets('an email with no booking here is reported and blocks saving',
      (tester) async {
    final source = FakeCouponSource();
    final results = await _open(tester, source);

    await _type(tester, 'coupon-code', 'VIPMEERA');
    await _type(tester, 'coupon-value', '20');
    await tester.tap(find.text('One guest'));
    await tester.pumpAndSettle();
    await _type(tester, 'coupon-guest-email', 'meera@example.com');
    await _tapKey(tester, 'coupon-guest-find');
    expect(find.text('No guest with that email has booked at this resort.'),
        findsOneWidget);

    await _tapKey(tester, 'coupon-save');
    expect(find.text('Find the guest first, or choose Everyone.'),
        findsOneWidget);
    expect(source.createCalls, isEmpty);
    expect(results, isEmpty);
  });

  testWidgets('changing the email after a match clears the match; Everyone '
      'saves without a guest', (tester) async {
    final source = FakeCouponSource()..guests = {'gita@example.com': _gita};
    await _open(tester, source);

    await _type(tester, 'coupon-code', 'VIPGITA');
    await _type(tester, 'coupon-value', '20');
    await tester.tap(find.text('One guest'));
    await tester.pumpAndSettle();
    await _type(tester, 'coupon-guest-email', 'gita@example.com');
    await _tapKey(tester, 'coupon-guest-find');
    expect(_foundGuest('Gita Guest'), findsOneWidget);

    await _type(tester, 'coupon-guest-email', 'other@example.com');
    expect(find.byKey(const Key('coupon-guest-found')), findsNothing);
    await _tapKey(tester, 'coupon-save');
    expect(find.text('Find the guest first, or choose Everyone.'),
        findsOneWidget);
    expect(source.createCalls, isEmpty);

    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'coupon-save');
    expect(source.createCalls.single.$2.guestId, isNull);
  });

  testWidgets('edit shows the coupon and saves every field back with its id',
      (tester) async {
    final source = FakeCouponSource();
    final existing = couponRow(
      id: 'c9',
      code: 'VIPGITA',
      kind: CouponKind.fixed,
      value: 500,
      minAmount: 5000,
      validFrom: DateTime(2026, 10, 1),
      validUntil: DateTime(2026, 10, 31),
      usageLimit: 10,
      usedCount: 3,
      guest: _gita,
    );
    final results = await _open(tester, source, coupon: existing);

    expect(find.text('Edit VIPGITA'), findsOneWidget);
    expect(find.text('Used 3 so far'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(_foundGuest('Gita Guest'), findsOneWidget);
    await _type(tester, 'coupon-value', '750');
    await _tapKey(tester, 'coupon-save');

    final (id, draft) = source.updateCalls.single;
    expect(id, 'c9');
    expect(draft.toParams(), {
      'p_code': 'VIPGITA',
      'p_kind': 'fixed',
      'p_value': 750,
      'p_min_amount': 5000,
      'p_valid_from': '2026-10-01',
      'p_valid_until': '2026-10-31',
      'p_usage_limit': 10,
      'p_customer': 'g1',
    });
    expect(source.createCalls, isEmpty);
    expect(results, [true]);
  });

  testWidgets('the usage limit cannot go below the uses already taken',
      (tester) async {
    final source = FakeCouponSource();
    await _open(tester, source,
        coupon: couponRow(
            id: 'c5',
            code: 'OLD5',
            kind: CouponKind.fixed,
            value: 500,
            usageLimit: 5,
            usedCount: 3));

    await _type(tester, 'coupon-usage-limit', '2');
    await _tapKey(tester, 'coupon-save');

    expect(find.text('Already used 3 times — the limit cannot be lower.'),
        findsOneWidget);
    expect(source.updateCalls, isEmpty);
  });

  testWidgets('a server refusal stays on the form with its message',
      (tester) async {
    final source = FakeCouponSource()..createError = CouponInvalid('code_taken');
    final results = await _open(tester, source);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _type(tester, 'coupon-value', '10');
    await _tapKey(tester, 'coupon-save');

    expect(find.byKey(const Key('coupon-form-error')), findsOneWidget);
    expect(find.text('That code is already in use at this resort.'),
        findsOneWidget);
    expect(find.byType(CouponForm), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('closing the form saves nothing', (tester) async {
    final source = FakeCouponSource();
    final results = await _open(tester, source);

    await _type(tester, 'coupon-code', 'SAVE10');
    await _tapKey(tester, 'coupon-cancel');

    expect(results, [false]);
    expect(source.createCalls, isEmpty);
    expect(find.byType(CouponForm), findsNothing);
  });
}
