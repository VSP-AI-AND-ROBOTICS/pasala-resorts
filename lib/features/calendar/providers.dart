import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';

/// Live reservations for one unit. An admin block or a competing booking
/// updates every open calendar without a refresh.
final unitReservationsProvider =
    StreamProvider.family<List<Reservation>, String>(
  (ref, unitId) => ref.watch(bookingRepositoryProvider).watchUnit(unitId),
);
