import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/reservation.dart';
import '../account/my_bookings_screen.dart' show BookingTile;
import '../staff/providers.dart';

/// The five ways admin can slice the bookings list. Deliberately narrower
/// than [ReservationStatus]: `pendingPayment` has no segment of its own
/// (those rows still show up under `all`) because a not-yet-paid hold that
/// is past its 15-minute window is an edge case, not something an admin
/// scans for day to day.
enum BookingStatusFilter { all, onHold, confirmed, checkedIn, checkedOut, cancelled, blocks }

/// Reservations narrowed to [filter]. `all`/`onHold`/`confirmed`/`cancelled`
/// only ever look at kind `booking` -- i.e. actual guest bookings, whether
/// still on hold, paid, or cancelled -- because listing an admin block
/// alongside them as a "booking" would be misleading; blocks have no
/// customer or quote. [BookingStatusFilter.blocks] is the one dedicated
/// escape hatch: without it, a block could only ever be found (and thus
/// only ever be undone) via psql, since nothing else in the app surfaces its
/// id. Pure and top-level so the filter logic is directly unit-testable
/// without pumping a widget.
List<Reservation> filterBookings(
  List<Reservation> all,
  BookingStatusFilter filter,
) {
  if (filter == BookingStatusFilter.blocks) {
    return all.where((r) => r.kind == ReservationKind.block).toList();
  }
  final bookings = all.where((r) => r.kind == ReservationKind.booking);
  return switch (filter) {
    BookingStatusFilter.all => bookings.toList(),
    BookingStatusFilter.onHold =>
      bookings.where((r) => r.status == ReservationStatus.hold).toList(),
    BookingStatusFilter.confirmed =>
      bookings.where((r) => r.status == ReservationStatus.confirmed).toList(),
    BookingStatusFilter.checkedIn =>
      bookings.where((r) => r.status == ReservationStatus.checkedIn).toList(),
    BookingStatusFilter.checkedOut =>
      bookings.where((r) => r.status == ReservationStatus.checkedOut).toList(),
    BookingStatusFilter.cancelled =>
      bookings.where((r) => r.status == ReservationStatus.cancelled).toList(),
    BookingStatusFilter.blocks => const [], // unreachable, handled above
  };
}

String _filterLabel(BookingStatusFilter filter) => switch (filter) {
  BookingStatusFilter.all => 'All',
  BookingStatusFilter.onHold => 'On hold',
  BookingStatusFilter.confirmed => 'Confirmed',
  BookingStatusFilter.checkedIn => 'Checked in',
  BookingStatusFilter.checkedOut => 'Checked out',
  BookingStatusFilter.cancelled => 'Cancelled',
  BookingStatusFilter.blocks => 'Blocks',
};

/// `/admin/bookings` -- every reservation the admin may see (RLS grants
/// admin/super_admin all rows), filterable by status. Reuses [BookingTile]
/// from the customer's My Bookings screen and taps through to the same
/// `/booking-detail/:id`, whose cancel action is already permitted for
/// admins by `cancel_booking`.
class AdminBookingsScreen extends ConsumerStatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  ConsumerState<AdminBookingsScreen> createState() =>
      _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends ConsumerState<AdminBookingsScreen> {
  BookingStatusFilter _filter = BookingStatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(allBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('All bookings')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: SegmentedButton<BookingStatusFilter>(
              segments: [
                for (final f in BookingStatusFilter.values)
                  ButtonSegment(value: f, label: Text(_filterLabel(f))),
              ],
              selected: {_filter},
              onSelectionChanged: (selection) =>
                  setState(() => _filter = selection.first),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: bookingsAsync,
              onRetry: () => ref.invalidate(allBookingsProvider),
              data: (all) {
                final bookings = filterBookings(all, _filter);
                if (bookings.isEmpty) {
                  // The exact string (including the trailing period) is
                  // asserted verbatim by admin_bookings_screen_test.dart.
                  return const EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No bookings match this filter.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: bookings.length,
                  itemBuilder: (context, i) {
                    final reservation = bookings[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: BookingTile(
                        reservation: reservation,
                        onTap: () =>
                            context.push('/booking-detail/${reservation.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
