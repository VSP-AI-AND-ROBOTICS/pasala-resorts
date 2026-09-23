import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

  testWidgets(
    'does not overflow a grid tile with a long address and many amenities',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const longAddressProperty = Property(
        id: 'a3',
        name: 'Pasala Overlook',
        slug: 'overlook',
        description: null,
        address:
            '1234 Extremely Long Winding Countryside Road, Near the Old '
            'Bridge, Beyond the Third Hill, Sector 7, Farmhouse District',
        images: [],
        amenities: [
          'Swimming pool',
          'Bonfire pit',
          'Free parking',
          'Air conditioning',
          'Board games',
          'Pet friendly',
        ],
        checkInTime: '14:00',
        checkOutTime: '11:00',
        isActive: true,
      );

      await tester.pumpWidget(_appFor([..._properties, longAddressProperty]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'redirects straight to the property page when there is exactly one',
    (tester) async {
      const property = Property(
        id: 'solo-1',
        name: 'Pasala Farm House',
        slug: 'pasala-farm-house',
        description: null,
        address: null,
        images: [],
        amenities: [],
        checkInTime: '14:00',
        checkOutTime: '11:00',
        isActive: true,
      );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const BrowseScreen()),
          GoRoute(
            path: '/property/:id',
            builder: (_, state) =>
                Text('Property page: ${state.pathParameters['id']}'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            propertiesProvider.overrideWith((ref) => Future.value([property])),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Property page: solo-1'), findsOneWidget);
      expect(find.text('Pasala Farm House'), findsNothing);
    },
  );

  testWidgets('filters properties when an amenity chip is selected', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const propertiesWithAmenities = [
      Property(
        id: 'p1',
        name: 'Pasala Pool Villa',
        slug: 'pool-villa',
        description: null,
        address: null,
        images: [],
        amenities: ['Pool', 'Wi-Fi'],
        checkInTime: '14:00',
        checkOutTime: '11:00',
        isActive: true,
      ),
      Property(
        id: 'p2',
        name: 'Pasala Mountain Cabin',
        slug: 'mountain-cabin',
        description: null,
        address: null,
        images: [],
        amenities: ['Wi-Fi'],
        checkInTime: '14:00',
        checkOutTime: '11:00',
        isActive: true,
      ),
    ];

    await tester.pumpWidget(_appFor(propertiesWithAmenities));
    await tester.pumpAndSettle();

    expect(find.text('Pasala Pool Villa'), findsOneWidget);
    expect(find.text('Pasala Mountain Cabin'), findsOneWidget);
    expect(find.text('Pool'), findsWidgets);

    // Tap the 'Pool' filter chip
    await tester.tap(find.widgetWithText(FilterChip, 'Pool'));
    await tester.pumpAndSettle();

    // Now only Pasala Pool Villa is shown
    expect(find.text('Pasala Pool Villa'), findsOneWidget);
    expect(find.text('Pasala Mountain Cabin'), findsNothing);

    // Tap 'All' chip to reset
    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pumpAndSettle();

    expect(find.text('Pasala Pool Villa'), findsOneWidget);
    expect(find.text('Pasala Mountain Cabin'), findsOneWidget);
  });
}
