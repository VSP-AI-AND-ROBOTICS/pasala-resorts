import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/data/models/review.dart';
import 'package:pasala/data/repositories/review_repository.dart';
import 'package:pasala/features/stay/review_screen.dart';

/// Records every `submit` call instead of touching Supabase.
class _FakeReviewRepository implements ReviewRepository {
  final List<String> submittedFor = [];

  @override
  Future<void> submit({
    required String reservationId,
    required int farmhouseRating,
    required int cleanlinessRating,
    required int foodRating,
    required int serviceRating,
    required int activitiesRating,
    required int overallRating,
    String feedback = '',
  }) async {
    submittedFor.add(reservationId);
  }

  @override
  Future<Review?> forReservation(String reservationId) async => null;

  @override
  Future<List<Review>> forProperty(String propertyId) async => const [];
}

void main() {
  testWidgets(
      'submitting a review returns to My Stay, not Bookings', (tester) async {
    final fake = _FakeReviewRepository();
    final router = GoRouter(
      initialLocation: '/my-stay/review/res-1',
      routes: [
        GoRoute(
          path: '/my-stay/review/:id',
          builder: (_, state) =>
              ReviewScreen(reservationId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/my-stay', builder: (_, _) => const Text('MY STAY')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewRepositoryProvider.overrideWithValue(fake),
          reviewForReservationProvider('res-1').overrideWith((ref) async => null),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();

    expect(fake.submittedFor, ['res-1']);
    expect(find.text('MY STAY'), findsOneWidget);
  });
}
