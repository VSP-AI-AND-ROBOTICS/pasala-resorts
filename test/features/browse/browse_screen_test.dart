import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 exports `Override` from misc.dart only (as in
// checkout_screen_test.dart).
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/location_service.dart';
import 'package:pasala/core/location/place_label.dart';
import 'package:pasala/core/location/position_service.dart';
import 'package:pasala/core/theme/theme_toggle_button.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_search.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/resort_search_repository.dart';
import 'package:pasala/features/browse/browse_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_position_service.dart';
import '../../support/fake_resort_search_source.dart';

/// A [LocationService] that resolves instantly with no place. The badge
/// has its own tests (`location_badge_test.dart`); here it only has to
/// settle.
class _FakeLocationService implements LocationService {
  @override
  Future<PlaceLabel?> currentPlace() async => null;
}

final _twoResorts = [
  searchResult(id: 'a1', name: 'Pasala Riverside'),
  searchResult(id: 'a2', name: 'Pasala Hilltop'),
];

final _catalog = [
  searchResult(
    id: 'r1',
    name: 'Lakeview Retreat',
    address: 'Gandipet Road, Hyderabad',
    amenities: ['Pool', 'Wi-Fi'],
    distanceKm: 12.3,
    minPrice: 4000,
    avgRating: 4.5,
    reviewCount: 2,
  ),
  searchResult(
    id: 'r2',
    name: 'Hilltop Farm',
    address: 'Nandi Hills, Bengaluru',
    amenities: ['Wi-Fi', 'Bonfire'],
  ),
];

FakeResortSearchSource _sourceFor(List<ResortSearchResult> all) =>
    FakeResortSearchSource()..respond = respondLikeServer(all);

List<Override> _overrides(
  FakeResortSearchSource source, {
  AppUser? user,
  PositionService? position,
}) =>
    [
      resortSearchSourceProvider.overrideWithValue(source),
      locationServiceProvider.overrideWithValue(_FakeLocationService()),
      positionServiceProvider
          .overrideWithValue(position ?? FakePositionService()),
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
    ];

Widget _appFor(
  FakeResortSearchSource source, {
  AppUser? user,
  PositionService? position,
}) =>
    ProviderScope(
      // Riverpod 3 retries failed providers by default; without this an
      // error state never settles.
      retry: (_, _) => null,
      overrides: _overrides(source, user: user, position: position),
      child: const MaterialApp(home: Scaffold(body: BrowseScreen())),
    );

/// A tall, phone-width (list layout) view, so that every card in these
/// tests is built and on screen. The filter bar pushes the second card
/// below an 800x600 view.
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('browse-search')), text);
  await tester.pump(BrowseScreen.searchDebounce);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a hero header above the property list', (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
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

    await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
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

    await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
    await tester.pumpAndSettle();

    expect(find.byType(SliverList), findsOneWidget);
  });

  for (final width in [1400.0, 840.0]) {
    testWidgets(
      'does not overflow a grid tile with a long address, many amenities and '
      'a meta line at ${width.toInt()} px',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final longOne = searchResult(
          id: 'a3',
          name: 'Pasala Overlook',
          address: '1234 Extremely Long Winding Countryside Road, Near the Old '
              'Bridge, Beyond the Third Hill, Sector 7, Farmhouse District',
          amenities: [
            'Swimming pool',
            'Bonfire pit',
            'Free parking',
            'Air conditioning',
            'Board games',
            'Pet friendly',
          ],
          distanceKm: 123.4,
          minPrice: 125000,
          avgRating: 4.8,
          reviewCount: 120,
        );

        await tester.pumpWidget(_appFor(_sourceFor([..._twoResorts, longOne])));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'stays on the list -- and shows the card -- with exactly one active '
    'resort (ResortHub lists every resort; no single-property redirect)',
    (tester) async {
      _useTallView(tester);
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
          overrides: _overrides(_sourceFor(
              [searchResult(id: 'solo-1', name: 'Pasala Farm House')])),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pasala Farm House'), findsOneWidget);
      expect(find.textContaining('Property page:'), findsNothing);
    },
  );

  testWidgets('tapping a card opens that resort', (tester) async {
    _useTallView(tester);
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
        overrides: _overrides(_sourceFor(_catalog)),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hilltop Farm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hilltop Farm'));
    await tester.pumpAndSettle();

    expect(find.text('Property page: r2'), findsOneWidget);
  });

  testWidgets('cards show the rating, distance and price search returned',
      (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(_appFor(_sourceFor(_catalog)));
    await tester.pumpAndSettle();

    expect(find.text('4.5 (2)'), findsOneWidget);
    expect(find.text('12 km'), findsOneWidget);
    expect(find.text('from ₹4,000 / night'), findsOneWidget);
  });

  group('amenity chips', () {
    testWidgets('an amenity chip filters on the server, and All resets it',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _sourceFor(_catalog);

      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Pool'));
      await tester.pumpAndSettle();

      expect(source.calls.last.amenities, ['Pool']);
      expect(find.text('Lakeview Retreat'), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'All'));
      await tester.pumpAndSettle();

      expect(find.text('Lakeview Retreat'), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsOneWidget);
    });

    testWidgets('choosing a chip keeps every other chip on offer',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_appFor(_sourceFor(_catalog)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Bonfire'));
      await tester.pumpAndSettle();

      expect(find.text('Lakeview Retreat'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Pool'), findsOneWidget);
    });
  });

  group('search box', () {
    testWidgets('searches once typing pauses for the debounce', (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('browse-search')), 'lake');
      await tester.pump(
          BrowseScreen.searchDebounce - const Duration(milliseconds: 1));
      expect(source.calls.where((q) => q.text == 'lake'), isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(source.calls.last.text, 'lake');
      expect(find.text('Lakeview Retreat'), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsNothing);
    });

    testWidgets('pressing search on the keyboard searches at once',
        (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('browse-search')), 'nandi');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(source.calls.last.text, 'nandi');
      expect(find.text('Hilltop Farm'), findsOneWidget);
      expect(find.text('Lakeview Retreat'), findsNothing);
    });

    testWidgets(
        'keeps the previous results under a progress bar while the next '
        'search loads, and the search box keeps its focus', (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      final gate = Completer<void>();
      source.hold = gate.future;
      await tester.enterText(find.byKey(const Key('browse-search')), 'lake');
      await tester.pump(BrowseScreen.searchDebounce);
      await tester.pump();

      expect(find.byKey(const Key('browse-searching')), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );

      source.hold = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('browse-searching')), findsNothing);
      expect(find.text('Hilltop Farm'), findsNothing);
      expect(find.text('Lakeview Retreat'), findsOneWidget);
    });

    testWidgets(
        'no match shows the empty state, and Clear filters brings every '
        'resort back', (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      await _search(tester, 'zzz');

      expect(find.text('No resorts match your search'), findsOneWidget);
      expect(find.text('Try a different word or clear the filters.'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('browse-empty-clear')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('browse-search')))
            .controller!
            .text,
        '',
      );
      // The unfiltered search is still alive (the chips watch it), so
      // clearing shows it again without a new call.
      expect(find.text('Lakeview Retreat'), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsOneWidget);
    });

    testWidgets('the bar offers Clear filters only while something narrows '
        'the list', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(_appFor(_sourceFor(_catalog)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browse-clear-filters')), findsNothing);

      await _search(tester, 'lake');
      expect(find.byKey(const Key('browse-clear-filters')), findsOneWidget);

      await tester.tap(find.byKey(const Key('browse-clear-filters')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browse-clear-filters')), findsNothing);
      expect(find.text('Hilltop Farm'), findsOneWidget);
    });
  });

  group('sort', () {
    testWidgets('without a position there is no Distance option',
        (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('browse-sort')));
      await tester.pumpAndSettle();

      expect(find.text('Distance'), findsNothing);
      expect(find.text('Rating'), findsWidgets);

      await tester.tap(find.text('Price: low to high').last);
      await tester.pumpAndSettle();

      expect(source.calls.last.sort, ResortSort.priceLow);
    });

    testWidgets(
        'with a position, Distance is offered and every search sends the '
        'rounded position', (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(
        source,
        position: FakePositionService(
            approximate: const GeoPoint(17.38512, 78.48671)),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('browse-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Distance').last);
      await tester.pumpAndSettle();

      expect(source.calls.last.sort, ResortSort.distance);
      final withOrigin = source.calls.where((q) => q.origin != null).toList();
      expect(withOrigin, isNotEmpty);
      expect(withOrigin.every((q) => q.origin == const GeoPoint(17.39, 78.49)),
          isTrue);
    });
  });

  testWidgets('a failed search shows the failure and Retry searches again',
      (tester) async {
    _useTallView(tester);
    final source = _sourceFor(_catalog)..error = const NetworkFailure();
    await tester.pumpWidget(_appFor(source));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    source.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Lakeview Retreat'), findsOneWidget);
  });

  testWidgets('with no resorts at all it says so', (tester) async {
    await tester.pumpWidget(_appFor(FakeResortSearchSource()));
    await tester.pumpAndSettle();

    expect(find.text('No properties yet'), findsOneWidget);
  });

  group('hero greeting', () {
    testWidgets('greets a signed-in user by their first name', (tester) async {
      await tester.pumpWidget(
        _appFor(
          _sourceFor(_twoResorts),
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
      await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
    });
  });

  group('hero profile button', () {
    testWidgets("opens the signed-in user's account sheet", (tester) async {
      await tester.pumpWidget(
        _appFor(
          _sourceFor(_twoResorts),
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

      expect(find.byKey(const Key('account-sheet-sign-out')), findsOneWidget);
    });

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
          overrides: _overrides(_sourceFor(_twoResorts)),
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
      await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
      await tester.pumpAndSettle();

      expect(find.text('Set location'), findsOneWidget);
    });
  });

  group('hero theme toggle', () {
    testWidgets(
      'shows the theme toggle in the action row, before the profile button',
      (tester) async {
        await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
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
