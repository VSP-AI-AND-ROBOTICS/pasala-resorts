import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/reservation.dart';
import '../booking/booking_screen.dart' show formatHoldRemaining;
import 'providers.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(myBookingsProvider),
        ),
        data: (bookings) {
          if (bookings.isEmpty) {
            return const Center(child: Text('No bookings yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            itemBuilder: (context, i) {
              final reservation = bookings[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: BookingTile(
                  reservation: reservation,
                  // A hold is a 15-minute reservation, not a finished
                  // booking -- there is nothing to view or cancel about it
                  // on a read-only detail screen. `BookingScreen` is the
                  // only place with a live pay/resume affordance, so that is
                  // where a tap on a hold belongs, rather than a dead end.
                  onTap: reservation.isHold
                      ? () => context.go('/book/${reservation.unitId}')
                      : () => context.push('/booking-detail/${reservation.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One reservation row. Reused by Task 21's admin list, so it must not
/// assume anything about the current user beyond what [Reservation] itself
/// carries.
class BookingTile extends StatelessWidget {
  const BookingTile({super.key, required this.reservation, this.onTap});

  final Reservation reservation;
  final VoidCallback? onTap;

  static String statusLabel(ReservationStatus status) => switch (status) {
        ReservationStatus.hold => 'On hold',
        ReservationStatus.pendingPayment => 'Payment due',
        ReservationStatus.confirmed => 'Confirmed',
        ReservationStatus.cancelled => 'Cancelled',
      };

  /// A hold's subtitle is its countdown, never a guest count -- showing
  /// "4 guests" next to a chip that reads "On hold" would make a 15-minute
  /// placeholder look like a real booking. [holdRemaining] is a snapshot
  /// from whenever the list was fetched, not a live ticker (this is a list
  /// row, not `BookingScreen`), so a hold that has since actually expired
  /// still reads as "Hold expiring" rather than a stale positive countdown.
  String? get _holdSubtitle {
    final remaining = reservation.holdRemaining;
    if (remaining != null && remaining > Duration.zero) {
      return 'Held — ${formatHoldRemaining(remaining)}';
    }
    return 'Hold expiring';
  }

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          title: Text('${formatDay(reservation.start.toLocal())} → '
              '${formatDay(reservation.end.toLocal())}'),
          subtitle: reservation.isHold
              ? Text(_holdSubtitle!)
              : reservation.guests == null
                  ? null
                  : Text('${reservation.guests} guests'),
          trailing: Chip(label: Text(statusLabel(reservation.status))),
        ),
      );
}
