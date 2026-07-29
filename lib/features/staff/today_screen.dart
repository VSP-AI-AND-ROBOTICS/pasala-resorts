import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/failure_view.dart';
import '../../data/models/reservation.dart';
import '../account/my_bookings_screen.dart' show BookingTile;
import 'providers.dart';

typedef TodayLists = ({
  List<Reservation> arrivals,
  List<Reservation> departures,
  List<Reservation> staying,
});

/// Splits confirmed stays into the three lists staff work from. Blocks and
/// cancellations are not guest activity and are excluded, and so is
/// anything short of `confirmed` -- a `hold` is a 15-minute placeholder that
/// may never become a real stay, and `pendingPayment` has not been paid for
/// yet, so neither belongs in a list staff use to plan who is actually
/// arriving, departing, or in house today.
///
/// A stay that both starts and ends today (a single-day slot booking, e.g.
/// a day-use Pool Deck slot) is counted as an arrival only, never as a
/// departure and never as staying. The `start == day` check runs first, so
/// it wins deterministically -- staff scanning the Arrivals section for
/// "who do I need to greet today" will see it there, and it is guaranteed
/// to appear in exactly one section rather than being silently dropped by
/// falling between the arrival/departure/staying checks.
TodayLists partitionToday(List<Reservation> all, DateTime today) {
  final day = DateUtils.dateOnly(today);
  final arrivals = <Reservation>[];
  final departures = <Reservation>[];
  final staying = <Reservation>[];

  for (final r in all) {
    if (r.kind != ReservationKind.booking) continue;
    if (r.status != ReservationStatus.confirmed) continue;

    final start = DateUtils.dateOnly(r.start.toLocal());
    final end = DateUtils.dateOnly(r.end.toLocal());

    if (start == day) {
      arrivals.add(r);
    } else if (end == day) {
      departures.add(r);
    } else if (start.isBefore(day) && end.isAfter(day)) {
      staying.add(r);
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
    final bookings = ref.watch(allBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: bookings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(allBookingsProvider),
        ),
        data: (all) {
          final lists = partitionToday(all, DateTime.now());
          Widget section(String title, List<Reservation> items) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('$title (${items.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('None'),
                    ),
                  for (final r in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: BookingTile(reservation: r),
                    ),
                ],
              );

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allBookingsProvider),
            child: ListView(children: [
              section('Arrivals', lists.arrivals),
              section('Departures', lists.departures),
              section('In house', lists.staying),
            ]),
          );
        },
      ),
    );
  }
}
