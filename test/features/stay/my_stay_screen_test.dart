import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/review.dart';
import 'package:pasala/data/repositories/review_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/stay/my_stay_screen.dart';

final _checkedOut = Reservation(
  id: 'res-1',
  unitId: 'u1',
  start: DateTime(2026, 8, 1),
  end: DateTime(2026, 8, 3),
  kind: ReservationKind.booking,
  status: ReservationStatus.checkedOut,
);

Widget _app({
  Reservation? currentStay,
  Reservation? mostRecentCheckedOut,
  Review? existingReview,
}) {
  final router = GoRouter(
    initialLocation: '/my-stay',
    routes: [
      GoRoute(path: '/my-stay', builder: (_, _) => const MyStayScreen()),
      GoRoute(
        path: '/my-stay/review/:id',
        builder: (_, _) => const Text('REVIEW SCREEN'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      currentStayProvider.overrideWith((ref) async => currentStay),
      mostRecentCheckedOutProvider.overrideWith(
          (ref) async => mostRecentCheckedOut),
      if (mostRecentCheckedOut != null)
        reviewForReservationProvider(mostRecentCheckedOut.id)
            .overrideWith((ref) async => existingReview),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
      'shows the plain empty state when there is no active/upcoming stay '
      'and nothing awaiting review', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('No active or upcoming stay'), findsOneWidget);
  });

  testWidgets(
      'prompts for a review when the most recent stay is checked out and '
      'has no review yet', (tester) async {
    await tester.pumpWidget(_app(mostRecentCheckedOut: _checkedOut));
    await tester.pumpAndSettle();

    expect(find.text('Stay Completed'), findsOneWidget);
    expect(find.text('How was your stay?'), findsOneWidget);
    expect(find.byKey(const Key('write-review-button')), findsOneWidget);
    expect(find.text('No active or upcoming stay'), findsNothing);
  });

  testWidgets(
      'falls back to the plain empty state once that stay already has a '
      'review', (tester) async {
    final review = Review(
      id: 'rev-1',
      reservationId: 'res-1',
      customerId: 'cust-1',
      farmhouseRating: 5,
      cleanlinessRating: 5,
      foodRating: 5,
      serviceRating: 5,
      activitiesRating: 5,
      overallRating: 5,
      feedback: '',
    );
    await tester.pumpWidget(_app(
      mostRecentCheckedOut: _checkedOut,
      existingReview: review,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Stay Completed'), findsNothing);
    expect(find.text('No active or upcoming stay'), findsOneWidget);
  });

  testWidgets('tapping "Write a Review" opens the review screen for that '
      'reservation', (tester) async {
    await tester.pumpWidget(_app(mostRecentCheckedOut: _checkedOut));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('write-review-button')));
    await tester.pumpAndSettle();

    expect(find.text('REVIEW SCREEN'), findsOneWidget);
  });
}
