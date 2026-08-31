import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/staggered_fade_in.dart';
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
      body: AsyncView(
        value: bookingsAsync,
        onRetry: () => ref.invalidate(myBookingsProvider),
        empty: () => const EmptyState(
          icon: Icons.event_busy_outlined,
          image: AppAssets.facadeDaytime,
          title: 'No bookings yet',
          message: 'Your stays will appear here.',
        ),
        data: (bookings) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: bookings.length,
          itemBuilder: (context, i) {
            final reservation = bookings[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: StaggeredFadeIn(
                key: ValueKey(reservation.id),
                index: i,
                child: BookingTile(
                  reservation: reservation,
                  // A hold is a 15-minute reservation, not a finished
                  // booking -- there is nothing to view or cancel about it
                  // on a read-only detail screen. The booking flow is now
                  // embedded on the property page rather than living at its
                  // own route, so a tap on a hold goes to `/` -- Browse's
                  // existing single-property redirect lands the customer
                  // on that page. Note: this does not automatically resume
                  // the specific held dates -- BookingScreen does not
                  // recover an existing server-side hold on mount, and the
                  // calendar disables tapping the customer's own currently
                  // -held dates. This is a pre-existing limitation (the
                  // retired /book/:unitId route had the same gap), not
                  // something this change fixes; it only ensures the tap
                  // lands somewhere live instead of a dead route.
                  onTap: reservation.isHold
                      ? () => context.go('/')
                      : () => context.push('/booking-detail/${reservation.id}'),
                ),
              ),
            );
          },
        ),
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
        ReservationStatus.hold => 'Reserved',
        ReservationStatus.pendingPayment => 'Payment due',
        ReservationStatus.confirmed => 'Confirmed',
        ReservationStatus.cancelled => 'Cancelled',
      };

  /// A hold's subtitle is its countdown, never a guest count -- showing
  /// "4 guests" next to a chip that reads "Reserved" would make a 15-minute
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

  /// The status chip's tint. Cancelled reads as muted/negative, confirmed as
  /// the brand colour, and hold/payment-due as a neutral "needs attention"
  /// tone -- a customer should be able to tell these apart at a glance,
  /// without reading the label.
  (Color background, Color foreground) _statusColors(ColorScheme scheme) =>
      switch (reservation.status) {
        ReservationStatus.confirmed => (
            scheme.primaryContainer,
            scheme.onPrimaryContainer
          ),
        ReservationStatus.cancelled => (
            scheme.surfaceContainerHigh,
            scheme.onSurfaceVariant
          ),
        ReservationStatus.hold ||
        ReservationStatus.pendingPayment =>
          (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (background, foreground) = _statusColors(scheme);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        onTap: onTap,
        title: Text(
          '${formatDay(reservation.start.toLocal())} → '
          '${formatDay(reservation.end.toLocal())}',
          style: textTheme.titleMedium,
        ),
        subtitle: switch ((reservation.isHold, reservation.guests)) {
          (true, _) => Text(_holdSubtitle!,
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          (false, null) => null,
          (false, final guests?) => Text('$guests guests',
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        },
        trailing: Chip(
          label: Text(statusLabel(reservation.status)),
          labelStyle: textTheme.labelLarge?.copyWith(color: foreground),
          backgroundColor: background,
          side: BorderSide.none,
        ),
      ),
    );
  }
}
