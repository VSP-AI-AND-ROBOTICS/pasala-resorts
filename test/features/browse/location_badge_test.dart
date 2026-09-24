import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/location_service.dart';
import 'package:pasala/core/location/place_label.dart';
import 'package:pasala/features/browse/location_badge.dart';

class _FakeLocationService implements LocationService {
  _FakeLocationService(this._resolve);
  final Future<PlaceLabel?> Function() _resolve;
  int callCount = 0;

  @override
  Future<PlaceLabel?> currentPlace() {
    callCount++;
    return _resolve();
  }
}

Widget _appFor(LocationService service) => ProviderScope(
  overrides: [locationServiceProvider.overrideWithValue(service)],
  child: const MaterialApp(
    home: Scaffold(body: Center(child: LocationBadge())),
  ),
);

void main() {
  testWidgets('shows a loading state while the service resolves', (
    tester,
  ) async {
    final service = _FakeLocationService(() => Completer<PlaceLabel?>().future);

    await tester.pumpWidget(_appFor(service));
    await tester.pump();

    expect(find.text('Locating…'), findsOneWidget);
  });

  testWidgets('shows the resolved city and country', (tester) async {
    final service = _FakeLocationService(
      () async => const PlaceLabel(locality: 'Bengaluru', country: 'India'),
    );

    await tester.pumpWidget(_appFor(service));
    await tester.pumpAndSettle();

    expect(find.text('Bengaluru, India'), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });

  testWidgets('shows a "Set location" chip when the service resolves nothing '
      '(denied/error)', (tester) async {
    final service = _FakeLocationService(() async => null);

    await tester.pumpWidget(_appFor(service));
    await tester.pumpAndSettle();

    expect(find.text('Set location'), findsOneWidget);
    expect(find.text('Locating…'), findsNothing);
  });

  testWidgets('tapping "Set location" retries the service', (tester) async {
    var attempt = 0;
    final service = _FakeLocationService(() async {
      attempt++;
      if (attempt == 1) return null;
      return const PlaceLabel(locality: 'Coorg', country: 'India');
    });

    await tester.pumpWidget(_appFor(service));
    await tester.pumpAndSettle();
    expect(find.text('Set location'), findsOneWidget);

    await tester.tap(find.text('Set location'));
    await tester.pumpAndSettle();

    expect(find.text('Coorg, India'), findsOneWidget);
    expect(service.callCount, 2);
  });

  testWidgets('never blocks the page -- renders inside a normal layout '
      'without exceptions', (tester) async {
    final service = _FakeLocationService(
      () async => const PlaceLabel(locality: 'Mysuru', country: 'India'),
    );

    await tester.pumpWidget(_appFor(service));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
