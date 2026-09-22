import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';

/// The signed-in customer's own reservations, newest first. RLS on
/// `reservations` is what actually scopes this to `auth.uid()` --
/// `myBookings()` filters on `customer_id` too, but the database is the real
/// authority (see `BookingRepository.myBookings`).
final myBookingsProvider = FutureProvider<List<Reservation>>(
  (ref) => ref.watch(bookingRepositoryProvider).myBookings(),
);
