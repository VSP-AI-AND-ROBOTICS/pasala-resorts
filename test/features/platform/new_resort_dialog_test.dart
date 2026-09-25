import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/new_resort_dialog.dart';

import '../../support/fake_platform_source.dart';

Future<void> _open(WidgetTester tester, FakePlatformSource source) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [platformSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const NewResortDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _fillNameAndOwner(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('new-resort-name')), 'Resort E');
  await tester.enterText(
      find.byKey(const Key('new-resort-owner-email')), 'owner@x.com');
}

Future<void> _create(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('by default the resort starts a 30-day Starter trial',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);

    await _fillNameAndOwner(tester);
    await _create(tester);

    expect(source.createCalls,
        [('Resort E', 'owner@x.com', SubscriptionTier.starter, 30)]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a chosen tier and trial length are sent', (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);

    await _fillNameAndOwner(tester);
    await tester.tap(find.byKey(const Key('new-resort-tier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pro').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-resort-trial-days')), '14');
    await _create(tester);

    expect(source.createCalls,
        [('Resort E', 'owner@x.com', SubscriptionTier.pro, 14)]);
  });

  testWidgets('with the trial switched off the resort starts active',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);

    await _fillNameAndOwner(tester);
    await tester.tap(find.byKey(const Key('new-resort-trial')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-resort-trial-days')), findsNothing);
    await _create(tester);

    expect(source.createCalls,
        [('Resort E', 'owner@x.com', SubscriptionTier.starter, 0)]);
  });

  testWidgets('a trial length outside 1 to 365 days is refused',
      (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);
    await _fillNameAndOwner(tester);

    for (final days in ['0', '366', 'abc', '']) {
      await tester.enterText(
          find.byKey(const Key('new-resort-trial-days')), days);
      await _create(tester);
      expect(find.text('Enter a trial of 1 to 365 days.'), findsOneWidget,
          reason: 'days "$days"');
    }
    expect(source.createCalls, isEmpty);
  });

  testWidgets('a missing name is refused', (tester) async {
    final source = FakePlatformSource();
    await _open(tester, source);

    await tester.enterText(
        find.byKey(const Key('new-resort-owner-email')), 'owner@x.com');
    await _create(tester);

    expect(find.text('Enter a name and an owner email.'), findsOneWidget);
    expect(source.createCalls, isEmpty);
  });

  testWidgets('a server refusal keeps the dialog open with its message',
      (tester) async {
    final source = FakePlatformSource()
      ..createError = const InvalidState('A trial is 0 to 365 days.');
    await _open(tester, source);

    await _fillNameAndOwner(tester);
    await _create(tester);

    expect(find.text('A trial is 0 to 365 days.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
