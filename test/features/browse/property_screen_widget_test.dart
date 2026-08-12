import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/features/browse/property_screen.dart';
import 'package:pasala/features/browse/providers.dart';

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

const _units = <Unit>[
  Unit(
    id: 'u1',
    propertyId: 'p1',
    name: 'Dallas',
    capacityBase: 2,
    capacityMax: 4,
    bookingMode: BookingMode.nightly,
    isActive: true,
  ),
];

void main() {
  testWidgets('wraps the header media in a Hero tagged with the property id', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyProvider('p1').overrideWith((ref) => Future.value(_property)),
          unitsProvider('p1').overrideWith((ref) => Future.value(_units)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PropertyScreen(propertyId: 'p1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag == 'property-media-p1'),
      findsOneWidget,
    );
  });
}
