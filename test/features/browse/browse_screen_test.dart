import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/location/location_service.dart';
import 'package:pasala/core/location/place_label.dart';
import 'package:pasala/core/theme/theme_toggle_button.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/browse/browse_screen.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [LocationService] that resolves instantly with no location -- the
/// hero's own badge behaviour is covered separately by
/// `location_badge_test.dart`; every other test in this file just needs
/// `pumpAndSettle` to terminate instead of waiting on the real
/// `DeviceLocationService`'s platform channels (which have no host
/// implementation under `flutter test`).
class _FakeLocationService implements LocationService {
  @override
  Future<PlaceLabel?> currentPlace() async => null;
}

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

Widget _appFor(List<Property> properties, {AppUser? user}) => ProviderScope(
      overrides: [
        propertiesProvider.overrideWith((ref) => Future.value(properties)),
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        currentUserProvider.overrideWith((ref) => Stream.value(user)),
      ],
      child: const MaterialApp(home: Scaffold(body: BrowseScreen())),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
    'stays on the list -- and shows the card -- with exactly one active '
    'resort (ResortHub lists every resort; no more single-property '
    'redirect)',
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
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: BrowseScreen()),
          ),
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
            locationServiceProvider.overrideWithValue(_FakeLocationService()),
            currentUserProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pasala Farm House'), findsOneWidget);
      expect(find.textContaining('Property page:'), findsNothing);
    },
  );

  testWidgets(
    'lists every active resort -- both cards render -- with two properties',
    (tester) async {
      await tester.pumpWidget(_appFor(_properties));
      await tester.pumpAndSettle();

      expect(find.text('Pasala Riverside'), findsOneWidget);
      expect(find.text('Pasala Hilltop'), findsOneWidget);
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

  group('hero greeting', () {
    testWidgets('greets a signed-in user by their first name', (tester) async {
      await tester.pumpWidget(
        _appFor(
          _properties,
          user: const AppUser(
            id: 'u1',
            email: 'ravi@pasala.test',
            fullName: 'Ravi Kumar',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').endsWith(', Ravi'),
        ),
        findsOneWidget,
      );
      expect(find.text('Discover your stay'), findsOneWidget);
    });

    testWidgets('shows "Welcome" for a signed-out guest', (tester) async {
      await tester.pumpWidget(_appFor(_properties));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
    });
  });

  group('hero profile button', () {
    testWidgets(
      "opens the signed-in user's account sheet",
      (tester) async {
        await tester.pumpWidget(
          _appFor(
            _properties,
            user: const AppUser(
              id: 'u1',
              email: 'ravi@pasala.test',
              fullName: 'Ravi Kumar',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('browse-hero-profile')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('account-sheet-sign-out')),
          findsOneWidget,
        );
      },
    );

    testWidgets('sends a signed-out guest to /login', (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: BrowseScreen()),
          ),
          GoRoute(path: '/login', builder: (_, _) => const Text('Login screen')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            propertiesProvider.overrideWith((ref) => Future.value(_properties)),
            locationServiceProvider.overrideWithValue(_FakeLocationService()),
            currentUserProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('browse-hero-profile')));
      await tester.pumpAndSettle();

      expect(find.text('Login screen'), findsOneWidget);
    });
  });

  group('hero location badge', () {
    testWidgets('renders the location badge in the hero', (tester) async {
      await tester.pumpWidget(_appFor(_properties));
      await tester.pumpAndSettle();

      expect(find.text('Set location'), findsOneWidget);
    });
  });

  group('hero theme toggle', () {
    testWidgets(
      'shows the theme toggle in the action row, before the profile button',
      (tester) async {
        await tester.pumpWidget(_appFor(_properties));
        await tester.pumpAndSettle();

        expect(find.byType(ThemeToggleButton), findsOneWidget);

        final actionRow = tester.widget<Row>(
          find.ancestor(
            of: find.byType(ThemeToggleButton),
            matching: find.byType(Row),
          ),
        );
        final toggleIndex = actionRow.children.indexWhere(
          (w) => w is IconTheme && w.child is ThemeToggleButton,
        );
        final profileIndex = actionRow.children.indexWhere(
          (w) => w.key == const Key('browse-hero-profile'),
        );
        expect(toggleIndex, greaterThanOrEqualTo(0));
        expect(profileIndex, greaterThanOrEqualTo(0));
        expect(toggleIndex, lessThan(profileIndex));
      },
    );
  });
}
