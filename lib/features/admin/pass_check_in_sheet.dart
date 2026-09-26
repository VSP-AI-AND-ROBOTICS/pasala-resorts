import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/reservation.dart';
import '../../data/models/room_status.dart';
import '../../data/models/verified_pass.dart';
import 'admin_bookings_screen.dart' show bookingCode;

/// Why a verified booking has no "Check in guest" button.
String passStatusLine(ReservationStatus status) => switch (status) {
      ReservationStatus.checkedIn => 'Already checked in',
      ReservationStatus.checkedOut => 'This stay has already checked out',
      ReservationStatus.cancelled => 'This booking was cancelled',
      _ => 'This booking is not confirmed yet',
    };

/// What reception sees after a guest's pass is verified (P3): whose
/// booking it is, the room warning if any, and "Check in guest" for a
/// confirmed booking. Pops `true` when reception taps it; the check-in
/// screen then runs its usual check-in.
class PassCheckInSheet extends StatelessWidget {
  const PassCheckInSheet({super.key, required this.pass, this.roomWarning});

  final VerifiedPass pass;
  final String? roomWarning;

  @override
  Widget build(BuildContext context) {
    final r = pass.reservation;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (pass.unitName != null) pass.unitName!,
      '${formatDay(r.start.toLocal())} → ${formatDay(r.end.toLocal())}',
      '${r.guests ?? '—'} guests',
      'Booking ${bookingCode(r.id)}',
    ].join(' · ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: scheme.primary),
                const SizedBox(width: Spacing.sm),
                Text('Pass verified', style: textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(r.customerName ?? 'Guest', style: textTheme.headlineSmall),
            if (r.customerPhone case final phone?) Text(phone),
            const SizedBox(height: Spacing.xs),
            Text(details, style: textTheme.bodyMedium),
            if (roomWarning case final warning?)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Chip(
                  key: const Key('pass-room-warning'),
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.warning_amber_outlined,
                      size: 18, color: RoomStatus.cleaning.color),
                  label: Text(warning),
                ),
              ),
            const SizedBox(height: Spacing.lg),
            if (r.status == ReservationStatus.confirmed)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('pass-check-in'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Check in guest'),
                ),
              )
            else
              Text(
                passStatusLine(r.status),
                key: const Key('pass-status'),
                style: textTheme.titleSmall,
              ),
          ],
        ),
      ),
    );
  }
}
