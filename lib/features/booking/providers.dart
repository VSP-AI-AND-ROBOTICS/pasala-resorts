import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/models/unit.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/catalog_repository.dart';

/// The unit being booked. `BookingScreen` only ever has a `unitId` (from the
/// `/book/:unitId` route), so it needs this rather than the property-scoped
/// `unitsProvider` in `features/browse/providers.dart`.
final unitByIdProvider = FutureProvider.family<Unit, String>(
  (ref, unitId) => ref.watch(catalogRepositoryProvider).unit(unitId),
);

/// A single reservation by id, used by `ConfirmationScreen` after
/// `confirm_booking` redirects to `/booking/:id`.
final reservationProvider = FutureProvider.family<Reservation, String>(
  (ref, id) => ref.watch(bookingRepositoryProvider).reservation(id),
);
