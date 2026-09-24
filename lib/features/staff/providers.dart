import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';

/// Every reservation at one resort that the signed-in user may see (RLS
/// scopes this to all reservations at a resort for a member with a role
/// there, and to just their own for a customer -- see
/// `BookingRepository.allBookings`). Keyed by `propertyId` -- a family, not
/// a bare provider, so switching the current resort can never show another
/// resort's cached bookings. Shared by [TodayScreen] and
/// `AdminBookingsScreen`, which each derive their own view from the same
/// underlying list rather than issuing separate queries.
final allBookingsProvider = FutureProvider.family<List<Reservation>, String>(
  (ref, propertyId) =>
      ref.watch(bookingRepositoryProvider).allBookings(propertyId: propertyId),
);

/// The real amount paid so far on one reservation -- see
/// [BookingRepository.paidAmount]. Keyed by reservation id so the admin
/// dashboard's "next arrival" card and any future per-booking balance view
/// can each request their own without colliding.
final paidAmountProvider = FutureProvider.family<num, String>(
  (ref, reservationId) =>
      ref.watch(bookingRepositoryProvider).paidAmount(reservationId),
);
