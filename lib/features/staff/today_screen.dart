import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/reservation.dart';
import '../account/my_bookings_screen.dart' show BookingTile;
import 'providers.dart';

typedef TodayLists = ({
  List<Reservation> arrivals,
  List<Reservation> departures,
  List<Reservation> staying,
});

/// Splits confirmed and checked-in stays into the three lists staff work
/// from. Blocks and cancellations are not guest activity and are excluded,
/// and so is anything short of `confirmed` -- a `hold` is a 15-minute
/// placeholder that may never become a real stay, and `pendingPayment` has
/// not been paid for yet, so neither belongs in a list staff use to plan
/// who is actually arriving, departing, or in house today. `checkedOut` is
/// excluded too -- once a guest has left, they are no longer today's work.
///
/// `checkedIn` is deliberately NOT excluded, unlike the rest: a guest who
/// has already arrived is exactly who staff need to see in "In house" (so
/// housekeeping/food service know who's on the property) and in
/// "Departures" once their stay ends today (so reception knows who still
/// needs to check out). Originally this only handled `confirmed`, so the
/// instant a guest checked in they silently vanished from every section of
/// this screen for the rest of their stay -- reproduced live: a guest
/// checked in for a multi-night stay showed nowhere on staff's Today
/// screen, not even "In house". Same bug class as I6 in
/// `report_revenue`/`report_occupancy` (0042_report_include_stay_lifecycle.sql),
/// just never applied here.
///
/// A `confirmed` stay that both starts and ends today (a single-day slot
/// booking, e.g. a day-use Pool Deck slot) is counted as an arrival only,
/// never as a departure and never as staying -- the `start == day` check
/// runs first, so it wins deterministically. A `checkedIn` guest has, by
/// definition, already arrived, so "have they left yet" is the only
/// question that matters for them: `end == day` puts them in Departures,
/// anything later puts them in In house, regardless of when they arrived.
TodayLists partitionToday(List<Reservation> all, DateTime today) {
  final day = DateUtils.dateOnly(today);
  final arrivals = <Reservation>[];
  final departures = <Reservation>[];
  final staying = <Reservation>[];

  for (final r in all) {
    if (r.kind != ReservationKind.booking) continue;

    final start = DateUtils.dateOnly(r.start.toLocal());
    final end = DateUtils.dateOnly(r.end.toLocal());

    switch (r.status) {
      case ReservationStatus.confirmed:
        if (start == day) {
          arrivals.add(r);
        } else if (end == day) {
          departures.add(r);
        } else if (start.isBefore(day) && end.isAfter(day)) {
          staying.add(r);
        }
      case ReservationStatus.checkedIn:
        if (end == day) {
          departures.add(r);
        } else if (end.isAfter(day)) {
          staying.add(r);
        }
      default:
        break;
    }
  }
  return (arrivals: arrivals, departures: departures, staying: staying);
}

/// `/staff` landing page. Reachable only by `isStaffOrAbove` users -- the
/// router redirects everyone else to `/404`, and RLS on `reservations` is
/// what actually enforces that a customer's `allBookings()` call only ever
/// returns their own rows regardless.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final bookings = ref.watch(allBookingsProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: AsyncView(
        value: bookings,
        onRetry: () => ref.invalidate(allBookingsProvider(propertyId)),
        data: (all) {
          final lists = partitionToday(all, DateTime.now());
          final scheme = Theme.of(context).colorScheme;

          if (lists.arrivals.isEmpty &&
              lists.departures.isEmpty &&
              lists.staying.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(allBookingsProvider(propertyId)),
              child: ListView(
                children: const [
                  EmptyState(
                    icon: Icons.task_alt_outlined,
                    title: 'Nothing on today',
                    message: 'No arrivals, departures, or in-house guests.',
                  ),
                ],
              ),
            );
          }

          Widget section(String title, List<Reservation> items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: title, subtitle: '${items.length}'),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: Text(
                    'None',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final r in items)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.xs,
                  ),
                  child: BookingTile(reservation: r),
                ),
            ],
          );

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(allBookingsProvider(propertyId)),
            child: ListView(
              children: [
                section('Arrivals', lists.arrivals),
                section('Departures', lists.departures),
                section('In house', lists.staying),
                const SizedBox(height: Spacing.md),
              ],
            ),
          );
        },
      ),
    );
  }
}
