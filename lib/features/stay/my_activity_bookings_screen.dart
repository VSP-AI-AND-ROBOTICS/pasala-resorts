import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/activity.dart';
import '../../data/repositories/activity_repository.dart';

class MyActivityBookingsScreen extends ConsumerWidget {
  const MyActivityBookingsScreen({super.key, required this.reservationId});

  final String reservationId;

  Future<void> _cancel(WidgetRef ref, BuildContext context, String id) async {
    try {
      await ref.read(activityRepositoryProvider).cancelBooking(id);
      ref.invalidate(myActivityBookingsProvider(reservationId));
    } on BookingFailure catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myActivityBookingsProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('My Activity Bookings')),
      body: AsyncView(
        value: bookingsAsync,
        onRetry: () => ref.invalidate(myActivityBookingsProvider(reservationId)),
        empty: () => const EmptyState(
          icon: Icons.event_available_outlined,
          title: 'No activities booked yet',
        ),
        data: (bookings) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: bookings.length,
          itemBuilder: (context, i) {
            final b = bookings[i];
            final cancelled = b.status == ActivityBookingStatus.cancelled;
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: ListTile(
                title: Text(b.activityName ?? 'Activity'),
                subtitle: Text(
                  '${formatDay(b.bookingDate)} · ${b.startTime} · '
                  '${b.people} people · ${formatInr(b.amount)}',
                ),
                trailing: cancelled
                    ? const Chip(label: Text('Cancelled'), side: BorderSide.none)
                    : TextButton(
                        onPressed: () => _cancel(ref, context, b.id),
                        child: const Text('Cancel'),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
