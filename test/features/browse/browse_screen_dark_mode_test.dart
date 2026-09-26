import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/location_service.dart';
import 'package:pasala/core/location/place_label.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/resort_search_repository.dart';
import 'package:pasala/features/browse/browse_screen.dart';

import '../../support/fake_resort_search_source.dart';

class _FakeLocationService implements LocationService {
  @override
  Future<PlaceLabel?> currentPlace() async =>
      const PlaceLabel(locality: 'Bengaluru', country: 'India');
}

void main() {
  testWidgets(
    'renders the browse screen in dark mode without exceptions',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            resortSearchSourceProvider.overrideWithValue(
              FakeResortSearchSource()
                ..results = [
                  searchResult(
                    id: 'a1',
                    name: 'Pasala Riverside',
                    amenities: ['Pool'],
                    distanceKm: 4,
                    minPrice: 3500,
                    avgRating: 4.2,
                    reviewCount: 5,
                  ),
                ],
            ),
            locationServiceProvider.overrideWithValue(_FakeLocationService()),
            currentUserProvider.overrideWith(
              (ref) => Stream.value(
                const AppUser(
                  id: 'u1',
                  email: 'ravi@pasala.test',
                  fullName: 'Ravi Kumar',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: ThemeMode.dark,
            home: const Scaffold(body: BrowseScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Pasala Riverside'), findsOneWidget);

      final context = tester.element(find.byType(BrowseScreen));
      expect(Theme.of(context).brightness, Brightness.dark);
    },
  );
}
