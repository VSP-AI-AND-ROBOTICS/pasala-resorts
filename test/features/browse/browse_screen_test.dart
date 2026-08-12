import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/features/browse/browse_screen.dart';
import 'package:pasala/features/browse/providers.dart';

const _properties = [
  Property(
    id: 'a1',
    name: 'Pasala Riverside',
    slug: 'riverside',
    description: null,
    address: null,
    images: [],
    amenities: [],
    checkInTime: '14:00',
    checkOutTime: '11:00',
    isActive: true,
  ),
  Property(
    id: 'a2',
    name: 'Pasala Hilltop',
    slug: 'hilltop',
    description: null,
    address: null,
    images: [],
    amenities: [],
    checkInTime: '14:00',
    checkOutTime: '11:00',
    isActive: true,
  ),
];

Widget _appFor(List<Property> properties) => ProviderScope(
      overrides: [
        propertiesProvider.overrideWith((ref) => Future.value(properties)),
      ],
      child: const MaterialApp(home: Scaffold(body: BrowseScreen())),
    );

void main() {
  testWidgets('shows a hero header above the property list', (tester) async {
    await tester.pumpWidget(_appFor(_properties));
    await tester.pumpAndSettle();

    expect(find.text('Discover your stay'), findsOneWidget);
    expect(find.text('Pasala Riverside'), findsOneWidget);
    expect(find.text('Pasala Hilltop'), findsOneWidget);
  });

  testWidgets('lays properties out in a grid on a wide viewport', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor(_properties));
    await tester.pumpAndSettle();

    expect(find.byType(SliverGrid), findsOneWidget);
  });

  testWidgets('lays properties out in a single column on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor(_properties));
    await tester.pumpAndSettle();

    expect(find.byType(SliverList), findsOneWidget);
  });
}
