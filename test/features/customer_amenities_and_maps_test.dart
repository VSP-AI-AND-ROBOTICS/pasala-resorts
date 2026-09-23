import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/models/resort.dart';
import 'package:pasala/core/services/mock_data_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Customer Resort Amenities & Google Maps Tests', () {
    late MockDataStore store;

    setUp(() {
      store = MockDataStore.instance;
    });

    test('1. All resorts have populated amenities with popular amenities', () {
      final resorts = store.resorts.values.toList();
      expect(resorts.isNotEmpty, isTrue);

      for (final resort in resorts) {
        expect(resort.amenities.isNotEmpty, isTrue,
            reason: '${resort.name} should have amenities');
        final hasKnownAmenity = resort.amenities.any((a) {
          final lower = a.toLowerCase();
          return lower.contains('wifi') ||
              lower.contains('pool') ||
              lower.contains('restaurant') ||
              lower.contains('park') ||
              lower.contains('spa') ||
              lower.contains('view');
        });
        expect(hasKnownAmenity, isTrue,
            reason: '${resort.name} should include standard searchable amenities');
      }
    });

    test('2. Amenity toggle filtering filters resorts correctly', () {
      final allResorts = store.resorts.values.toList();

      // Filter by Swimming Pool
      final poolResorts = allResorts.where((r) {
        return r.amenities.any((a) => a.toLowerCase().contains('pool'));
      }).toList();
      expect(poolResorts.isNotEmpty, isTrue);
      expect(poolResorts.length, lessThanOrEqualTo(allResorts.length));

      // Filter by Free Wi-Fi
      final wifiResorts = allResorts.where((r) {
        return r.amenities.any((a) => a.toLowerCase().contains('wi-fi') || a.toLowerCase().contains('wifi'));
      }).toList();
      expect(wifiResorts.isNotEmpty, isTrue);

      // Filter by both Swimming Pool and Free Wi-Fi
      final poolAndWifiResorts = allResorts.where((r) {
        final hasPool = r.amenities.any((a) => a.toLowerCase().contains('pool'));
        final hasWifi = r.amenities.any((a) => a.toLowerCase().contains('wi-fi') || a.toLowerCase().contains('wifi'));
        return hasPool && hasWifi;
      }).toList();
      expect(poolAndWifiResorts.isNotEmpty, isTrue);
      expect(poolAndWifiResorts.length, lessThanOrEqualTo(poolResorts.length));
    });

    test('3. Google Maps redirection URL formats search query accurately', () {
      final resort = store.resorts['resort-grand-palms']!;
      final queryParts = [resort.name, resort.address, resort.city, resort.state]
          .where((s) => s.trim().isNotEmpty)
          .join(', ');
      final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': queryParts});

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['query'], contains('Grand Palms Beach Resort'));
      expect(uri.queryParameters['query'], contains('Goa'));
    });

    test('4. Taj Falaknuma Palace Resort in Hyderabad has Maps query and full amenities', () {
      final falaknuma = store.resorts['resort-taj-falaknuma']!;
      expect(falaknuma.city, 'Hyderabad');
      expect(falaknuma.state, 'Telangana');

      final queryParts = [falaknuma.name, falaknuma.address, falaknuma.city, falaknuma.state]
          .where((s) => s.trim().isNotEmpty)
          .join(', ');
      final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': queryParts});

      expect(uri.queryParameters['query'], contains('Taj Falaknuma Palace Resort'));
      expect(uri.queryParameters['query'], contains('Hyderabad'));
      expect(falaknuma.amenities, contains('Free Wi-Fi'));
      expect(falaknuma.amenities, contains('Swimming Pool'));
    });
  });
}
