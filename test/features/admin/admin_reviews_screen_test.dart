import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  Widget app(List<Review> reviews) => ProviderScope(
        overrides: [
          allReviewsProvider.overrideWith((ref) async => reviews),
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
}
