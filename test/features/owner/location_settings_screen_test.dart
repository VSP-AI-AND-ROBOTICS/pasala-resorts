import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/position_service.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/catalog_repository.dart';
import 'package:pasala/features/owner/location_settings_screen.dart';

import '../../support/fake_position_service.dart';

/// Records `updateSettings`; every other member is unused here.
class _RecordingCatalog implements CatalogRepository {
  final List<(String, Map<String, dynamic>)> updates = [];
  Object? error;

  @override
  Future<void> updateSettings(
      String propertyId, Map<String, dynamic> fields) async {
    updates.add((propertyId, fields));
    if (error != null) throw error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Property _property({double? lat, double? lng}) => Property(
      id: 'p1',
      name: 'Pasala Farm House',
      slug: 'pasala-farm-house',
      description: null,
      address: null,
      images: const [],
      amenities: const [],
      checkInTime: '14:00',
      checkOutTime: '11:00',
      isActive: true,
      latitude: lat,
      longitude: lng,
    );

/// Pushes the screen from a launcher page, so that Save's `pop` has
/// somewhere to go back to.
Future<void> _open(
  WidgetTester tester, {
  required Property property,
  required _RecordingCatalog catalog,
  FakePositionService? position,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(catalog),
      positionServiceProvider
          .overrideWithValue(position ?? FakePositionService()),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LocationSettingsScreen(property: property),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  group('parseCoordinates', () {
    test('both empty clears the location', () {
      final r = parseCoordinates('  ', '');
      expect(r.point, isNull);
      expect(r.error, isNull);
    });

    test('a trimmed valid pair parses', () {
      final r = parseCoordinates(' 17.385044 ', '78.486671');
      expect(r.point, const GeoPoint(17.385044, 78.486671));
      expect(r.error, isNull);
    });

    test('only one of the two is refused', () {
      expect(parseCoordinates('17.3', '').error,
          'Enter both latitude and longitude, or leave both empty.');
      expect(parseCoordinates('', '78.4').error,
          'Enter both latitude and longitude, or leave both empty.');
    });

    test('a comma decimal or text is refused', () {
      expect(parseCoordinates('17,385', '78.48').error,
          'Latitude and longitude must be numbers, like 17.385 and 78.4867.');
      expect(parseCoordinates('north', '78.48').error,
          'Latitude and longitude must be numbers, like 17.385 and 78.4867.');
    });

    test('out of range, NaN or swapped coordinates are refused', () {
      const message = 'Latitude must be between -90 and 90, '
          'and longitude between -180 and 180.';
      expect(parseCoordinates('91', '78').error, message);
      expect(parseCoordinates('17', '181').error, message);
      expect(parseCoordinates('NaN', '78').error, message);
      expect(parseCoordinates('178.48', '17.38').error, message);
    });
  });

  testWidgets('prefills the saved coordinates', (tester) async {
    await _open(tester,
        property: _property(lat: 17.385044, lng: 78.486671),
        catalog: _RecordingCatalog());

    expect(_fieldText(tester, 'location-lat'), '17.385044');
    expect(_fieldText(tester, 'location-lng'), '78.486671');
  });

  testWidgets('"Use my current location" fills both fields from a precise fix',
      (tester) async {
    final position =
        FakePositionService(precise: const GeoPoint(17.3850441, 78.4866712));
    await _open(tester,
        property: _property(), catalog: _RecordingCatalog(), position: position);

    await tester.tap(find.byKey(const Key('location-use-current')));
    await tester.pumpAndSettle();

    expect(position.preciseCalls, 1);
    expect(position.approximateCalls, 0);
    expect(_fieldText(tester, 'location-lat'), '17.385044');
    expect(_fieldText(tester, 'location-lng'), '78.486671');
  });

  testWidgets('an unavailable location says what to do and changes nothing',
      (tester) async {
    await _open(tester,
        property: _property(lat: 1, lng: 2), catalog: _RecordingCatalog());

    await tester.tap(find.byKey(const Key('location-use-current')));
    await tester.pumpAndSettle();

    expect(
        find.text('Could not get your location. '
            'Allow location access, or type the coordinates.'),
        findsOneWidget);
    expect(_fieldText(tester, 'location-lat'), '1.000000');
  });

  testWidgets('Save sends both coordinates and closes', (tester) async {
    final catalog = _RecordingCatalog();
    await _open(tester, property: _property(), catalog: catalog);

    await tester.enterText(find.byKey(const Key('location-lat')), '17.385044');
    await tester.enterText(find.byKey(const Key('location-lng')), '78.486671');
    await tester.tap(find.byKey(const Key('location-save')));
    await tester.pumpAndSettle();

    // Records compare their fields with ==, and a Map's == is identity,
    // so check the two parts separately.
    expect(catalog.updates.single.$1, 'p1');
    expect(catalog.updates.single.$2, {'lat': 17.385044, 'lng': 78.486671});
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('clearing both fields removes the location', (tester) async {
    final catalog = _RecordingCatalog();
    await _open(tester,
        property: _property(lat: 17.3, lng: 78.4), catalog: catalog);

    await tester.enterText(find.byKey(const Key('location-lat')), '');
    await tester.enterText(find.byKey(const Key('location-lng')), '');
    await tester.tap(find.byKey(const Key('location-save')));
    await tester.pumpAndSettle();

    expect(catalog.updates.single.$1, 'p1');
    expect(catalog.updates.single.$2, {'lat': null, 'lng': null});
  });

  testWidgets('an invalid form shows the reason and sends nothing',
      (tester) async {
    final catalog = _RecordingCatalog();
    await _open(tester, property: _property(), catalog: catalog);

    await tester.enterText(find.byKey(const Key('location-lat')), '17.385');
    await tester.tap(find.byKey(const Key('location-save')));
    await tester.pumpAndSettle();

    expect(find.text('Enter both latitude and longitude, or leave both empty.'),
        findsOneWidget);
    expect(catalog.updates, isEmpty);
    expect(find.byType(LocationSettingsScreen), findsOneWidget);
  });

  testWidgets('a refused save shows the failure and stays open',
      (tester) async {
    final catalog = _RecordingCatalog()..error = const ResortSuspended();
    await _open(tester, property: _property(), catalog: catalog);

    await tester.enterText(find.byKey(const Key('location-lat')), '17.3');
    await tester.enterText(find.byKey(const Key('location-lng')), '78.4');
    await tester.tap(find.byKey(const Key('location-save')));
    await tester.pumpAndSettle();

    expect(find.text(const ResortSuspended().message), findsOneWidget);
    expect(find.byType(LocationSettingsScreen), findsOneWidget);
  });
}
