import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/room_status.dart';
import '../../data/repositories/room_status_repository.dart';
import '../../data/repositories/stay_repository.dart';
import '../staff/providers.dart' show allBookingsProvider;

/// The warning reception sees on a booking whose room is not ready. A
/// warning only: check-in is never blocked on room state (room status
/// spec, decision 10). Null when the room is ready or its state is
/// unknown.
String? roomWarningFor(RoomBoardEntry? room) => switch (room?.state) {
      RoomState.dirty => 'Room not cleaned yet',
      RoomState.outOfOrder => 'Maintenance: ${room?.reason ?? 'out of order'}',
      _ => null,
    };

/// `/admin/check-in` -- every `confirmed` booking, one-tap Check In. The
/// doc's own accepted method: reception looks up the booking (by name or
/// the guest's QR/booking-id) and taps Check In -- no camera scanning.
/// A booking whose room still needs cleaning or is in maintenance carries
/// a warning chip (see [roomWarningFor]).
class ReceptionCheckinScreen extends ConsumerWidget {
  const ReceptionCheckinScreen({super.key});

  Future<void> _checkIn(
    WidgetRef ref,
    BuildContext context,
    String id,
    String propertyId,
  ) async {
    try {
      await ref.read(stayRepositoryProvider).checkIn(id);
      ref.invalidate(todaysArrivalsProvider(propertyId));
      ref.invalidate(checkedInProvider(propertyId));
      // The admin dashboard's Farmhouse Status / Today's Focus cards read
      // from this same list -- without invalidating it here, a fresh
      // check-in never shows as OCCUPIED until something else happens to
      // refetch it.
      ref.invalidate(allBookingsProvider);
      // The room is Occupied now.
      ref.invalidate(roomBoardProvider(propertyId));
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
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final arrivalsAsync = ref.watch(todaysArrivalsProvider(propertyId));
    // The board only adds warnings: while it loads, or if it fails, the
    // list shows without them and check-in works as before.
    final rooms = ref.watch(roomBoardProvider(propertyId)).value ??
        const <RoomBoardEntry>[];
    final roomByUnit = {for (final r in rooms) r.unitId: r};

    return Scaffold(
      appBar: AppBar(title: const Text('Check-In')),
      body: AsyncView(
        value: arrivalsAsync,
        onRetry: () => ref.invalidate(todaysArrivalsProvider(propertyId)),
        empty: () => const EmptyState(
          icon: Icons.how_to_reg_outlined,
          title: 'No bookings waiting to check in',
        ),
        data: (bookings) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: bookings.length,
          itemBuilder: (context, i) {
            final b = bookings[i];
            final warning = roomWarningFor(roomByUnit[b.unitId]);
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: ListTile(
                title: Text(b.customerName ?? 'Guest'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatDay(b.start.toLocal())} → ${formatDay(b.end.toLocal())} · '
                      '${b.guests ?? '—'} guests · Booking ${b.id.substring(0, 8)}',
                    ),
                    if (warning != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.xs),
                        child: Chip(
                          key: Key('room-warning-${b.id}'),
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.warning_amber_outlined,
                              size: 18, color: RoomStatus.cleaning.color),
                          label: Text(warning),
                        ),
                      ),
                  ],
                ),
                trailing: FilledButton(
                  onPressed: () => _checkIn(ref, context, b.id, propertyId),
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
