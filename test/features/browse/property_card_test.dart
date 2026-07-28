import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/features/browse/browse_screen.dart';

void main() {
  const property = Property(
    id: 'a1',
    name: 'Pasala Riverside',
    slug: 'riverside',
    description: 'Riverside farmhouse with private pool.',
    address: 'Shamirpet, Hyderabad',
    images: [],
    amenities: ['Pool', 'Wi-Fi'],
    checkInTime: '14:00',
    checkOutTime: '11:00',
    isActive: true,
  );

  testWidgets('renders name, address, and amenities', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyCard(property: property)),
    ));

    expect(find.text('Pasala Riverside'), findsOneWidget);
    expect(find.text('Shamirpet, Hyderabad'), findsOneWidget);
    expect(find.text('Pool'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);
  });

  testWidgets('shows check-in and check-out times', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyCard(property: property)),
    ));

    expect(find.textContaining('14:00'), findsOneWidget);
  });

  testWidgets('renders without error when address is null and amenities '
      'are empty', (tester) async {
    const bareProperty = Property(
      id: 'a2',
      name: 'Pasala Hilltop',
      slug: 'hilltop',
      description: null,
      address: null,
      images: [],
      amenities: [],
      checkInTime: '15:00',
      checkOutTime: '10:00',
      isActive: true,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyCard(property: bareProperty)),
    ));

    expect(find.text('Pasala Hilltop'), findsOneWidget);
    expect(find.textContaining('15:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
