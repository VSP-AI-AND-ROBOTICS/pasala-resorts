import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';

/// Every reservation the signed-in user may see (RLS scopes this to all
/// reservations for staff/accountant/admin/super_admin, and to just their
/// own for a customer -- see `BookingRepository.allBookings`). Shared by
/// [TodayScreen] and `AdminBookingsScreen`, which each derive their own view
/// from the same underlying list rather than issuing separate queries.
final allBookingsProvider = FutureProvider<List<Reservation>>(
  (ref) => ref.watch(bookingRepositoryProvider).allBookings(),
);
