// test/features/browse/property_screen_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_assets.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/review.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/data/repositories/review_repository.dart';
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

Widget _appFor({List<Review> reviews = const []}) => ProviderScope(
      overrides: [
        propertyProvider('p1').overrideWith((ref) => Future.value(_property)),
        unitsProvider('p1').overrideWith((ref) => Future.value(_units)),
        unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
        unitCalendarSourceProvider
            .overrideWithValue(_NoOccupancyCalendarSource()),
        allReviewsProvider.overrideWith((ref) => Future.value(reviews)),
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
          allReviewsProvider.overrideWith((ref) => Future.value([])),
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
}
