import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/models/resort.dart';
import 'package:pasala/features/discovery/services/location_service.dart';

void main() {
  group('Customer Resort Discovery Sorting Tests (BR-05 & BR-06)', () {
    late LocationService locationService;

    setUp(() {
      locationService = LocationService.instance;
    });

    test('BR-05: Premium tier resorts MUST prioritize higher than Super, Basic, and Free', () {
      final freeResort = const Resort(
        id: 'r-free',
        name: 'Free Resort',
        slug: 'free',
        description: 'Free tier',
        address: 'Addr',
        city: 'Goa',
        state: 'Goa',
        country: 'India',
        latitude: 15.5,
        longitude: 73.8,
        contactEmail: 'free@resort.com',
        contactPhone: '123',
        subscriptionTier: SubscriptionTier.free,
        status: 'active',
        imageUrls: [],
        amenities: [],
      );

      final premiumResort = const Resort(
        id: 'r-premium',
        name: 'Premium Resort',
        slug: 'premium',
        description: 'Premium tier',
        address: 'Addr',
        city: 'Goa',
        state: 'Goa',
        country: 'India',
        latitude: 15.6,
        longitude: 73.9,
        contactEmail: 'premium@resort.com',
        contactPhone: '123',
        subscriptionTier: SubscriptionTier.premium,
        status: 'active',
        imageUrls: [],
        amenities: [],
      );

      final superResort = const Resort(
        id: 'r-super',
        name: 'Super Resort',
        slug: 'super',
        description: 'Super tier',
        address: 'Addr',
        city: 'Goa',
        state: 'Goa',
        country: 'India',
        latitude: 15.5,
        longitude: 73.8,
        contactEmail: 'super@resort.com',
        contactPhone: '123',
        subscriptionTier: SubscriptionTier.superTier,
        status: 'active',
        imageUrls: [],
        amenities: [],
      );

      final resorts = [freeResort, superResort, premiumResort];

      final sorted = locationService.sortResorts(resorts: resorts);

      expect(sorted[0].subscriptionTier, SubscriptionTier.premium);
      expect(sorted[1].subscriptionTier, SubscriptionTier.superTier);
      expect(sorted[2].subscriptionTier, SubscriptionTier.free);
    });

    test('BR-06: Distance proximity sorts closest resorts first within the same tier group', () {
      // User position in Panaji, Goa (15.4909, 73.8278)
      final userPos = const UserCoordinates(latitude: 15.4909, longitude: 73.8278);

      final farPremium = const Resort(
        id: 'r-far',
        name: 'Far Premium Resort',
        slug: 'far',
        description: 'Far',
        address: 'Addr',
        city: 'Mumbai',
        state: 'MH',
        country: 'India',
        latitude: 19.0760, // ~450km away
        longitude: 72.8777,
        contactEmail: 'far@resort.com',
        contactPhone: '123',
        subscriptionTier: SubscriptionTier.premium,
        status: 'active',
        imageUrls: [],
        amenities: [],
      );

      final nearPremium = const Resort(
        id: 'r-near',
        name: 'Near Premium Resort',
        slug: 'near',
        description: 'Near',
        address: 'Addr',
        city: 'Calangute',
        state: 'Goa',
        country: 'India',
        latitude: 15.5497, // ~10km away
        longitude: 73.7536,
        contactEmail: 'near@resort.com',
        contactPhone: '123',
        subscriptionTier: SubscriptionTier.premium,
        status: 'active',
        imageUrls: [],
        amenities: [],
      );

      final sorted = locationService.sortResorts(
        resorts: [farPremium, nearPremium],
        userLocation: userPos,
      );

      expect(sorted[0].id, 'r-near');
      expect(sorted[1].id, 'r-far');
      expect(sorted[0].calculatedDistanceKm! < sorted[1].calculatedDistanceKm!, isTrue);
    });
  });
}
