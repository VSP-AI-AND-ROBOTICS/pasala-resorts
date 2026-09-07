import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/stay_repository.dart';
import '../staff/providers.dart' show allBookingsProvider;

/// `/admin/check-in` -- every `confirmed` booking, one-tap Check In. The
/// doc's own accepted method: reception looks up the booking (by name or
/// the guest's QR/booking-id) and taps Check In -- no camera scanning.
class ReceptionCheckinScreen extends ConsumerWidget {
  const ReceptionCheckinScreen({super.key});

  Future<void> _checkIn(WidgetRef ref, BuildContext context, String id) async {
    try {
      await ref.read(stayRepositoryProvider).checkIn(id);
      ref.invalidate(todaysArrivalsProvider);
      ref.invalidate(checkedInProvider);
      // The admin dashboard's Farmhouse Status / Today's Focus cards read
      // from this same list -- without invalidating it here, a fresh
      // check-in never shows as OCCUPIED until something else happens to
      // refetch it.
      ref.invalidate(allBookingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Checked in')));
      }
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arrivalsAsync = ref.watch(todaysArrivalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Check-In')),
      body: AsyncView(
        value: arrivalsAsync,
        onRetry: () => ref.invalidate(todaysArrivalsProvider),
        empty: () => const EmptyState(
          icon: Icons.how_to_reg_outlined,
          title: 'No bookings waiting to check in',
        ),
        data: (bookings) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: bookings.length,
          itemBuilder: (context, i) {
            final b = bookings[i];
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: ListTile(
                title: Text(b.customerName ?? 'Guest'),
                subtitle: Text(
                  '${formatDay(b.start.toLocal())} → ${formatDay(b.end.toLocal())} · '
                  '${b.guests ?? '—'} guests · Booking ${b.id.substring(0, 8)}',
                ),
                trailing: FilledButton(
                  onPressed: () => _checkIn(ref, context, b.id),
                  child: const Text('Check In'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
