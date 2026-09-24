import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/widgets/failure_view.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets("shows a BookingFailure's own curated message", (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FailureView(error: UnitUnavailable()),
    ));

    expect(find.text(const UnitUnavailable().message), findsOneWidget);
  });

  testWidgets(
      'never renders the raw server text carried by UnknownFailure '
      '(the carried-forward fix for Task 16)', (tester) async {
    const raw = 'permission denied for table reservations';
    await tester.pumpWidget(const MaterialApp(
      home: FailureView(error: UnknownFailure(raw)),
    ));

    expect(find.textContaining(raw), findsNothing);
    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('falls back to a generic message for a non-BookingFailure error',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FailureView(error: 'raw exception string'),
    ));

    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('shows a retry button when onRetry is supplied', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: FailureView(error: const NotFound(), onRetry: () => tapped = true),
    ));

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(tapped, isTrue);
  });

  testWidgets('shows no retry button when onRetry is omitted', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FailureView(error: NotFound()),
    ));

    expect(find.text('Retry'), findsNothing);
  });

  // Review Focus #4: a remembered current resort the user has since been
  // removed from must be discarded, not used -- surfaced here as a
  // NotAMember failure, which forgets the pick (handleResortAccessLost)
  // once its message is shown.
  testWidgets(
      'a NotAMember failure shows its message and forgets the stale '
      'current resort', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const a = ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner);
    const b = ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff);
    const user = AppUser(id: 'u', email: 'e', memberships: [a, b]);
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
    ]);
    addTearDown(container.dispose);
    // Every provider here is auto-dispose by default (Riverpod 3): keep
    // the chain alive before the widget tree (which would otherwise do
    // this via its own `ref.watch`) exists yet.
    container.listen(currentResortProvider, (_, _) {});
    await container.read(currentUserProvider.future);
    await container.read(currentResortProvider.notifier).select('b');
    expect(container.read(currentResortProvider), b);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FailureView(error: NotAMember())),
    ));
    await tester.pumpAndSettle();

    expect(find.text(const NotAMember().message), findsOneWidget);
    expect(container.read(currentResortProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('current_resort_id'), isNull);
  });
}
