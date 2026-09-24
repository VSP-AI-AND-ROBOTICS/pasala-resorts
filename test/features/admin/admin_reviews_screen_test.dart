import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/review.dart';
import 'package:pasala/data/repositories/review_repository.dart';
import 'package:pasala/features/admin/admin_reviews_screen.dart';

Review _review(
  String id, {
  int overallRating = 5,
  String feedback = '',
  DateTime? createdAt,
}) =>
    Review(
      id: id,
      reservationId: 'res-$id',
      customerId: 'cust-$id',
      farmhouseRating: overallRating,
      cleanlinessRating: overallRating,
      foodRating: overallRating,
      serviceRating: overallRating,
      activitiesRating: overallRating,
      overallRating: overallRating,
      feedback: feedback,
      createdAt: createdAt,
    );

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => const ResortMembership(
      propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);
}

void main() {
  // The current resort (p1) has [reviews]; any other resort has only a
  // review that must never show up here.
  Widget app(List<Review> reviews) => ProviderScope(
        overrides: [
          currentResortProvider.overrideWith(_FixedResort.new),
          propertyReviewsProvider.overrideWith((ref, propertyId) async =>
              propertyId == 'p1'
                  ? reviews
                  : [_review('x', feedback: 'Review of another resort')]),
        ],
        child: const MaterialApp(home: AdminReviewsScreen()),
      );

  testWidgets('an empty result shows a clear message, not a blank screen',
      (tester) async {
    await tester.pumpWidget(app(const []));
    await tester.pumpAndSettle();

    expect(find.text('No reviews yet'), findsOneWidget);
  });

  testWidgets('lists every review with its rating and feedback',
      (tester) async {
    final reviews = [
      _review('1', overallRating: 5, feedback: 'Wonderful stay!'),
      _review('2', overallRating: 3, feedback: 'It was okay.'),
    ];
    await tester.pumpWidget(app(reviews));
    await tester.pumpAndSettle();

    expect(find.text('5/5'), findsOneWidget);
    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('"Wonderful stay!"'), findsOneWidget);
    expect(find.text('"It was okay."'), findsOneWidget);
  });

  testWidgets("lists only the current resort's reviews", (tester) async {
    await tester.pumpWidget(app([_review('1', feedback: 'Lovely pool.')]));
    await tester.pumpAndSettle();

    expect(find.text('"Lovely pool."'), findsOneWidget);
    expect(find.text('"Review of another resort"'), findsNothing);
  });
}
