// test/features/browse/property_screen_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/theme/app_assets.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/review.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/data/repositories/review_repository.dart';
import 'package:pasala/features/booking/booking_screen.dart' show BookingScreen;
import 'package:pasala/features/booking/providers.dart' show unitByIdProvider;
import 'package:pasala/features/browse/property_screen.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/calendar/providers.dart'
    show unitCalendarSourceProvider;

const _property = Property(
  id: 'p1',
  name: 'Pasala Dallas Cottage',
  slug: 'dallas-cottage',
  description: 'A themed cottage by the pool.',
  address: null,
  images: [],
  amenities: ['Pool'],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
);

const _unit = Unit(
  id: 'u1',
  propertyId: 'p1',
  name: 'Dallas',
  capacityBase: 2,
  capacityMax: 4,
  bookingMode: BookingMode.nightly,
  isActive: true,
);

const _units = <Unit>[_unit];

/// A [UnitCalendarSource] with no occupied dates at all -- the calendar
/// this screen embeds just needs something to watch; its own occupancy
/// rendering is `availability_calendar_test.dart`'s job, not this file's.
class _NoOccupancyCalendarSource implements UnitCalendarSource {
  @override
  Stream<List<Reservation>> watchUnit(String unitId) => const Stream.empty();

  @override
  Future<List<Reservation>> fetchUnit(String unitId) async => const [];
}

const _otherResortReview = Review(
  id: 'other',
  reservationId: 'res-other',
  customerId: 'c-other',
  farmhouseRating: 1,
  cleanlinessRating: 1,
  foodRating: 1,
  serviceRating: 1,
  activitiesRating: 1,
  overallRating: 1,
  feedback: 'Review of another resort',
);

Widget _appFor({List<Review> reviews = const []}) => ProviderScope(
      overrides: [
        propertyProvider('p1').overrideWith((ref) => Future.value(_property)),
        unitsProvider('p1').overrideWith((ref) => Future.value(_units)),
        unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
        unitCalendarSourceProvider
            .overrideWithValue(_NoOccupancyCalendarSource()),
        // Only p1's reviews belong on p1's page; any other resort's review
        // must never show up here.
        propertyReviewsProvider.overrideWith((ref, propertyId) async =>
            propertyId == 'p1' ? reviews : [_otherResortReview]),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PropertyScreen(propertyId: 'p1')),
      ),
    );

void main() {
  testWidgets(
    'the gallery has one page per bundled photo, with no property-media '
    'placeholder page',
    (tester) async {
      await tester.pumpWidget(_appFor());
      await tester.pumpAndSettle();

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.positions, isNotEmpty);
      expect(
        (pageView.childrenDelegate as SliverChildBuilderDelegate).childCount,
        8,
      );
      expect(
        find.byWidgetPredicate((w) => w is Hero && w.tag == 'property-media-p1'),
        findsNothing,
      );
    },
  );

  testWidgets('the first gallery page is the night aerial photo', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    final firstPageImage = tester.widget<Image>(find.byType(Image).first);
    expect(
      (firstPageImage.image as AssetImage).assetName,
      AppAssets.heroNightAerial,
    );
  });

  testWidgets(
    'the booking flow renders directly on the property page, for the '
    'single unit -- no separate screen, no unit list',
    (tester) async {
      await tester.pumpWidget(_appFor());
      await tester.pumpAndSettle();

      expect(find.text('Dates'), findsOneWidget);
      // findsWidgets (rather than findsOneWidget) asserts the "Guests" step
      // is present without over-specifying exactly how many places its
      // label appears inside `_PlanYourStayCard`.
      expect(find.text('Guests'), findsWidgets);
      expect(find.byKey(const Key('occasion-field')), findsOneWidget);
      // Pay is no longer its own numbered section -- once a quote exists,
      // the Price section's own button is the payment action, so there is
      // no separate fourth step to assert on.
      expect(find.text('Price'), findsOneWidget);
    },
  );

  testWidgets('shows a friendly message when there are no reviews yet', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.text('Customer Reviews'), findsOneWidget);
    expect(
      find.text('No reviews yet -- be the first to share your stay.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows the average rating and up to 3 of the newest reviews, with '
    'each guest\'s first name',
    (tester) async {
      final reviews = [
        Review(
          id: 'r1',
          reservationId: 'res-1',
          customerId: 'c1',
          farmhouseRating: 5,
          cleanlinessRating: 5,
          foodRating: 5,
          serviceRating: 5,
          activitiesRating: 5,
          overallRating: 5,
          feedback: 'Wonderful stay!',
          customerFirstName: 'Ramesh',
        ),
        Review(
          id: 'r2',
          reservationId: 'res-2',
          customerId: 'c2',
          farmhouseRating: 4,
          cleanlinessRating: 4,
          foodRating: 4,
          serviceRating: 4,
          activitiesRating: 4,
          overallRating: 4,
          feedback: 'Very good.',
          customerFirstName: 'Sneha',
        ),
      ];
      await tester.pumpWidget(_appFor(reviews: reviews));
      await tester.pumpAndSettle();

      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('(2 reviews)'), findsOneWidget);
      expect(find.text('Ramesh'), findsOneWidget);
      expect(find.text('Sneha'), findsOneWidget);
      expect(find.text('Wonderful stay!'), findsOneWidget);
      expect(find.byKey(const Key('view-all-reviews-button')), findsOneWidget);
    },
  );

  testWidgets('gallery shows counter badge indicating current photo index', (tester) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.text('1 / 8'), findsOneWidget);
  });

  testWidgets('renders address row with clickable maps navigation link', (tester) async {
    const propertyWithAddress = Property(
      id: 'p1',
      name: 'Pasala Dallas Cottage',
      slug: 'dallas-cottage',
      description: 'A themed cottage by the pool.',
      address: 'Near Kanakapura Road, Bengaluru',
      images: [],
      amenities: ['Pool'],
      checkInTime: '14:00',
      checkOutTime: '11:00',
      isActive: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyProvider('p1').overrideWith((ref) => Future.value(propertyWithAddress)),
          unitsProvider('p1').overrideWith((ref) => Future.value(_units)),
          unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
          unitCalendarSourceProvider.overrideWithValue(_NoOccupancyCalendarSource()),
          propertyReviewsProvider.overrideWith((ref, propertyId) async => []),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PropertyScreen(propertyId: 'p1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Near Kanakapura Road, Bengaluru'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets(
    "shows only this property's reviews, and View All Reviews opens this "
    "property's review list",
    (tester) async {
      final router = GoRouter(
        initialLocation: '/property/p1',
        routes: [
          GoRoute(
            path: '/property/:id',
            builder: (_, state) => Scaffold(
              body: PropertyScreen(propertyId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/property/:id/reviews',
            builder: (_, state) =>
                Text('REVIEWS OF ${state.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          propertyProvider('p1').overrideWith((ref) => Future.value(_property)),
          unitsProvider('p1').overrideWith((ref) => Future.value(_units)),
          unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
          unitCalendarSourceProvider
              .overrideWithValue(_NoOccupancyCalendarSource()),
          propertyReviewsProvider.overrideWith((ref, propertyId) async =>
              propertyId == 'p1'
                  ? [
                      const Review(
                        id: 'r1',
                        reservationId: 'res-1',
                        customerId: 'c1',
                        farmhouseRating: 5,
                        cleanlinessRating: 5,
                        foodRating: 5,
                        serviceRating: 5,
                        activitiesRating: 5,
                        overallRating: 5,
                        feedback: 'Wonderful stay!',
                      ),
                    ]
                  : [_otherResortReview]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Wonderful stay!'), findsOneWidget);
      expect(find.text('Review of another resort'), findsNothing);

      final button = find.byKey(const Key('view-all-reviews-button'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('REVIEWS OF p1'), findsOneWidget);
    },
  );
  // E2E bug (guest.spec.ts "opening a resort with more than one unit"):
  // the units builder used `list.single`, which throws StateError ("Too many
  // elements") for any resort with a second unit, so its whole booking
  // section never rendered and a guest could not book it at all.
  group('a resort with more than one unit', () {
    const lakeVilla = Unit(
      id: 'u2',
      propertyId: 'p1',
      name: 'Lake Villa',
      capacityBase: 4,
      capacityMax: 8,
      bookingMode: BookingMode.nightly,
      isActive: true,
    );

    Widget multiUnitApp() => ProviderScope(
          overrides: [
            propertyProvider('p1')
                .overrideWith((ref) => Future.value(_property)),
            unitsProvider('p1')
                .overrideWith((ref) => Future.value([_unit, lakeVilla])),
            unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
            unitByIdProvider('u2')
                .overrideWith((ref) => Future.value(lakeVilla)),
            unitCalendarSourceProvider
                .overrideWithValue(_NoOccupancyCalendarSource()),
            propertyReviewsProvider
                .overrideWith((ref, propertyId) async => []),
          ],
          child: const MaterialApp(
            home: Scaffold(body: PropertyScreen(propertyId: 'p1')),
          ),
        );

    testWidgets(
        'renders a unit picker and the booking flow for the first unit, '
        'without throwing', (tester) async {
      await tester.pumpWidget(multiUnitApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('unit-picker')), findsOneWidget);
      expect(find.byKey(const Key('unit-choice-u1')), findsOneWidget);
      expect(find.byKey(const Key('unit-choice-u2')), findsOneWidget);
      expect(find.text('Dallas'), findsWidgets);
      expect(find.text('Lake Villa'), findsWidgets);
      // Exactly one "Sleeps" line: the selected unit's.
      expect(find.textContaining('Sleeps'), findsOneWidget);
      expect(find.textContaining('2–4'), findsOneWidget);
      final booking = tester.widget<BookingScreen>(find.byType(BookingScreen));
      expect(booking.unitId, 'u1');
      expect(find.text('Dates'), findsOneWidget);
    });

    testWidgets('choosing another unit books that unit instead',
        (tester) async {
      await tester.pumpWidget(multiUnitApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('unit-choice-u2')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('4–8'), findsOneWidget);
      expect(find.textContaining('2–4'), findsNothing);
      final booking = tester.widget<BookingScreen>(find.byType(BookingScreen));
      expect(booking.unitId, 'u2');
    });
  });

  testWidgets('a single-unit resort shows no unit picker', (tester) async {
    await tester.pumpWidget(_appFor());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unit-picker')), findsNothing);
    expect(find.textContaining('Sleeps'), findsOneWidget);
    expect(tester.widget<BookingScreen>(find.byType(BookingScreen)).unitId,
        'u1');
  });
}
