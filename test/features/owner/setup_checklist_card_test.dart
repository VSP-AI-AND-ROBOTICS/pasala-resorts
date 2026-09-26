import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/listing_repository.dart';
import 'package:pasala/features/owner/setup_checklist_card.dart';

import '../../support/fake_listing_source.dart';

const _owner = AppUser(id: 'o1', email: 'owner@example.com');

Future<List<SetupStep>> _pump(
  WidgetTester tester,
  FakeListingSource source,
) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final opened = <SetupStep>[];
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      listingSourceProvider.overrideWithValue(source),
      currentUserProvider.overrideWith((ref) => Stream.value(_owner)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SetupChecklistCard(
            propertyId: 'p1',
            resortName: 'Green Acres',
            onOpenStep: (step) async => opened.add(step),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return opened;
}

Icon _stepIcon(WidgetTester tester, SetupStep step) => tester.widget<Icon>(
    find
        .descendant(
            of: find.byKey(Key('setup-step-${step.name}')),
            matching: find.byType(Icon))
        .first);

void main() {
  testWidgets('shows progress and every step, in words as well as icons',
      (tester) async {
    final source = FakeListingSource()
      ..setup = listingSetup(done: {SetupStep.photos, SetupStep.units});
    await _pump(tester, source);

    expect(find.text('Finish setting up Green Acres'), findsOneWidget);
    expect(find.text('2 of 6 done'), findsOneWidget);
    for (final step in SetupStep.values) {
      expect(find.text(step.title), findsOneWidget);
    }
    expect(_stepIcon(tester, SetupStep.photos).semanticLabel, 'Done');
    expect(_stepIcon(tester, SetupStep.tax).semanticLabel, 'Not done');
    expect(source.setupCalls, ['p1']);
  });

  testWidgets('Submit for review stays off until every step is done',
      (tester) async {
    final source = FakeListingSource()
      ..setup = listingSetup(done: {SetupStep.photos});
    await _pump(tester, source);

    final button =
        tester.widget<ButtonStyleButton>(find.byKey(const Key('setup-submit')));
    expect(button.onPressed, isNull);
    expect(find.text('Complete every step to submit.'), findsOneWidget);
  });

  testWidgets('a complete checklist submits and then shows the submission',
      (tester) async {
    final source = FakeListingSource()..setup = listingSetup(done: allSetupSteps);
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('setup-submit')));
    await tester.pumpAndSettle();

    expect(source.submitCalls, ['p1']);
    expect(find.text('Submitted for review.'), findsOneWidget);
    expect(find.byKey(const Key('setup-submitted')), findsOneWidget);
    expect(
        find.text('Submitted for review on 25 Sep 2026. '
            'We will email you when it is decided.'),
        findsOneWidget);
    expect(find.byKey(const Key('setup-submit')), findsNothing);
    expect(source.setupCalls, ['p1', 'p1']);
  });

  testWidgets('a refusal from the server is shown as written', (tester) async {
    final source = FakeListingSource()
      ..setup = listingSetup(done: allSetupSteps)
      ..submitError =
          const ListingBlocked('Finish the setup checklist before submitting.');
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('setup-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Finish the setup checklist before submitting.'),
        findsOneWidget);
  });

  testWidgets('a step opens its screen and the checklist refreshes on return',
      (tester) async {
    final source = FakeListingSource()..setup = listingSetup();
    final opened = await _pump(tester, source);

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();

    expect(opened, [SetupStep.photos]);
    expect(source.setupCalls, ['p1', 'p1']);
  });

  testWidgets('a resort approved meanwhile says it is live', (tester) async {
    final source = FakeListingSource()
      ..setup = listingSetup(status: 'active', done: allSetupSteps);
    await _pump(tester, source);

    expect(find.text('Your resort is live'), findsOneWidget);
    expect(find.byKey(const Key('setup-live-refresh')), findsOneWidget);
    expect(find.text('Add photos'), findsNothing);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    final source = FakeListingSource()..setupError = const NetworkFailure();
    await _pump(tester, source);

    expect(find.text('Could not load your setup checklist'), findsOneWidget);
    source.setupError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('0 of 6 done'), findsOneWidget);
  });
}
