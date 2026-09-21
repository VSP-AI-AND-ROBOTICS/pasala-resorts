import 'dart:math';
import 'package:resorthub/core/models/resort.dart';

class UserCoordinates {
  final double latitude;
  final double longitude;

  const UserCoordinates({required this.latitude, required this.longitude});
}

class LocationService {
  static final LocationService instance = LocationService._internal();

  LocationService._internal();

  // User position in Hyderabad city center (17.3850, 78.4867)
  UserCoordinates defaultUserPosition = const UserCoordinates(
    latitude: 17.3850,
    longitude: 78.4867,
  );

  /// Computes distance in kilometers between two lat/lng points using Haversine Formula
  double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Sorts resorts adhering strictly to BR-05 & BR-06:
  /// 1. Subscription Tier priority: Premium (3) > Super (2) > Basic (1) > Free (0)
  /// 2. If user position is available, proximity distance (closest first) within the same tier group
  /// 3. Fallback to name/rating if no location available
  List<Resort> sortResorts({
    required List<Resort> resorts,
    UserCoordinates? userLocation,
  }) {
    final List<Resort> enrichedResorts = resorts.map<Resort>((r) {
      if (userLocation != null) {
        final dist = calculateDistanceKm(
          userLocation.latitude,
          userLocation.longitude,
          r.latitude,
          r.longitude,
        );
        return r.copyWith(calculatedDistanceKm: dist);
      }
      return r;
    }).toList();

    enrichedResorts.sort((Resort a, Resort b) {
      // Primary: Subscription Tier Priority (Premium > Super > Basic > Free)
      final int tierCompare = b.subscriptionTier.priorityOrder.compareTo(a.subscriptionTier.priorityOrder);
      if (tierCompare != 0) {
        return tierCompare;
      }

      // Secondary: Proximity Distance if location available and significant (>0.5 km)
      if (a.calculatedDistanceKm != null && b.calculatedDistanceKm != null) {
        final diff = (a.calculatedDistanceKm! - b.calculatedDistanceKm!).abs();
        if (diff > 0.5) {
          return a.calculatedDistanceKm!.compareTo(b.calculatedDistanceKm!);
        }
      }

      // Fallback: Rating (higher first) then preserve insertion order (newest first)
      final int ratingCompare = b.rating.compareTo(a.rating);
      if (ratingCompare != 0) {
        return ratingCompare;
      }

      return 0;
    });

    return enrichedResorts;
  }

  /// Detects the nearest resort city matching the given GPS coordinates
  String detectNearestCity({
    required UserCoordinates userLocation,
    required List<Resort> resorts,
  }) {
    if (resorts.isEmpty) return 'All Locations';

    Resort nearest = resorts.first;
    double minDistance = calculateDistanceKm(
      userLocation.latitude,
      userLocation.longitude,
      nearest.latitude,
      nearest.longitude,
    );

    for (final resort in resorts) {
      final dist = calculateDistanceKm(
        userLocation.latitude,
        userLocation.longitude,
        resort.latitude,
        resort.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearest = resort;
      }
    }

    if (nearest.city.toLowerCase() == 'calangute' || nearest.city.toLowerCase() == 'majorda') {
      return 'Goa';
    }
    return nearest.city;
  }
}
