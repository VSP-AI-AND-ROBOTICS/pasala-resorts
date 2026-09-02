// test/features/browse/property_screen_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_assets.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
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

Widget _appFor() => ProviderScope(
      overrides: [
        propertyProvider('p1').overrideWith((ref) => Future.value(_property)),
        unitsProvider('p1').overrideWith((ref) => Future.value(_units)),
        unitByIdProvider('u1').overrideWith((ref) => Future.value(_unit)),
        unitCalendarSourceProvider
            .overrideWithValue(_NoOccupancyCalendarSource()),
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
}
