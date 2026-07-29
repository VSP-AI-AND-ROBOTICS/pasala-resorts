import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/failure_view.dart';
import '../../data/models/reservation.dart';
import '../account/my_bookings_screen.dart' show BookingTile;
import '../staff/providers.dart';

/// The four ways admin can slice the bookings list. Deliberately narrower
/// than [ReservationStatus]: `pendingPayment` has no segment of its own
/// (those rows still show up under `all`) because a not-yet-paid hold that
/// is past its 15-minute window is an edge case, not something an admin
/// scans for day to day.
enum BookingStatusFilter { all, onHold, confirmed, cancelled }

/// Reservations of kind `booking` -- i.e. actual guest bookings, whether
/// still on hold, paid, or cancelled -- narrowed to [filter]. Admin blocks
/// (`ReservationKind.block`) are deliberately excluded: they have no
/// customer or quote and already have their own screen at
/// `/admin/block/:unitId`, so listing them here as "bookings" would be
/// misleading. Pure and top-level so the filter logic is directly
/// unit-testable without pumping a widget.
List<Reservation> filterBookings(
  List<Reservation> all,
  BookingStatusFilter filter,
) {
  final bookings = all.where((r) => r.kind == ReservationKind.booking);
  return switch (filter) {
    BookingStatusFilter.all => bookings.toList(),
    BookingStatusFilter.onHold =>
      bookings.where((r) => r.status == ReservationStatus.hold).toList(),
    BookingStatusFilter.confirmed => bookings
        .where((r) => r.status == ReservationStatus.confirmed)
        .toList(),
    BookingStatusFilter.cancelled => bookings
        .where((r) => r.status == ReservationStatus.cancelled)
        .toList(),
  };
}

String _filterLabel(BookingStatusFilter filter) => switch (filter) {
      BookingStatusFilter.all => 'All',
      BookingStatusFilter.onHold => 'On hold',
      BookingStatusFilter.confirmed => 'Confirmed',
      BookingStatusFilter.cancelled => 'Cancelled',
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
            padding: const EdgeInsets.all(16),
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
            child: bookingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => FailureView(
                error: e,
                onRetry: () => ref.invalidate(allBookingsProvider),
              ),
              data: (all) {
                final bookings = filterBookings(all, _filter);
                if (bookings.isEmpty) {
                  return const Center(
                      child: Text('No bookings match this filter.'));
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
