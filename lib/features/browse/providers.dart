import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/property.dart';
import '../../data/models/slot_type.dart';
import '../../data/models/unit.dart';
import '../../data/repositories/catalog_repository.dart';

final propertiesProvider = FutureProvider<List<Property>>(
  (ref) => ref.watch(catalogRepositoryProvider).properties(),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

final propertyProvider = FutureProvider.family<Property, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).property(id),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

final unitsProvider = FutureProvider.family<List<Unit>, String>(
  (ref, propertyId) => ref.watch(catalogRepositoryProvider).units(propertyId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

final slotTypesProvider = FutureProvider.family<List<SlotType>, String>(
  (ref, propertyId) =>
      ref.watch(catalogRepositoryProvider).slotTypes(propertyId),
);
