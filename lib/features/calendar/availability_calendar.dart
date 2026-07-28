import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/models/reservation.dart';
import 'providers.dart';

enum DayStatus { available, booked, blocked, pending, past }

/// Decides one day's status. Pure so the rule is testable without a widget.
/// A day counts as occupied when the reservation covers its check-in moment,
/// so an 11:00 checkout leaves that day available for a 14:00 arrival.
DayStatus statusFor(
  DateTime day,
  List<Reservation> reservations, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final dayStart = DateTime(day.year, day.month, day.day);
  final todayStart = DateTime(now.year, now.month, now.day);
  if (dayStart.isBefore(todayStart)) return DayStatus.past;

  final dayEnd = dayStart.add(const Duration(days: 1));
  var result = DayStatus.available;

  for (final r in reservations) {
    if (r.status == ReservationStatus.cancelled) continue;
    final start = r.start.toLocal();
    final end = r.end.toLocal();
    // Overlap test against the calendar day, excluding a checkout that
    // lands at or before this day's start.
    if (!start.isBefore(dayEnd) || !end.isAfter(dayStart)) continue;
    // A stay ending during this day frees it for the next arrival. The
    // noon cutoff is a stand-in for "this reservation's checkout landed in
    // the morning of `day`, so it no longer occupies `day`". It is safe
    // for every checkout time this app produces: property check_out_time
    // (11:00 Riverside, 10:00 Hilltop) and the `night`/`full_day` slot end
    // times (09:00/08:00) are all comfortably before noon.
    //
    // `start.isBefore(dayStart)` is the guard that keeps this from ever
    // firing for a same-day reservation: a `day` slot (09:00-18:00) never
    // starts before its own day, so it can never be freed by this clause —
    // it always falls through to the marking logic below and is reported
    // booked for the entire day, including its 18:00 end. A hypothetical
    // reservation that started earlier and also ends at 18:00 today is
    // likewise NOT freed, because 18:00 fails `isBefore(noon)` — see the
    // regression tests in availability_calendar_test.dart pinning both
    // cases.
    //
    // Known residual gap: this function only sees `day` and the raw
    // reservation timestamps, not which property or slot type produced
    // them. On a unit with booking_mode `both` (e.g. Whole Villa), a
    // nightly guest checking out at 11:00 frees the whole day here, even
    // though a `day` slot for the same date starts at 09:00 — two hours
    // before that checkout. The calendar would show the day as fully
    // available when a 09:00 arrival would actually collide until 11:00.
    // Fixing this precisely needs the property's check_out_time or the
    // requested slot's start time, neither of which this signature
    // carries (Task 16/20 depend on the signature as specified). The
    // database's exclusion constraint (23P01) is the actual backstop for
    // that gap; this calendar remains a day-granularity approximation.
    if (end.isBefore(dayStart.add(const Duration(hours: 12))) &&
        start.isBefore(dayStart)) {
      continue;
    }

    final status = switch (r) {
      _ when r.kind == ReservationKind.block => DayStatus.blocked,
      _ when r.status == ReservationStatus.hold ||
              r.status == ReservationStatus.pendingPayment =>
        DayStatus.pending,
      _ => DayStatus.booked,
    };
    // Booked outranks blocked outranks pending when several overlap.
    if (status == DayStatus.booked) return DayStatus.booked;
    if (status == DayStatus.blocked || result == DayStatus.available) {
      result = status;
    }
  }
  return result;
}

class AvailabilityCalendar extends ConsumerWidget {
  const AvailabilityCalendar({
    super.key,
    required this.unitId,
    required this.month,
    this.selectedStart,
    this.selectedEnd,
    this.onDayTap,
  });

  final String unitId;
  final DateTime month;
  final DateTime? selectedStart;
  final DateTime? selectedEnd;
  final void Function(DateTime day)? onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReservations = ref.watch(unitReservationsProvider(unitId));
    final scheme = Theme.of(context).colorScheme;

    // Loading with nothing to show yet, and hard errors with no cached
    // data: don't crash, don't silently render an all-available grid.
    if (asyncReservations.isLoading && !asyncReservations.hasValue) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (asyncReservations.hasError && !asyncReservations.hasValue) {
      final error = asyncReservations.error;
      final message =
          error is BookingFailure ? error.message : 'Could not load availability.';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(message, style: TextStyle(color: scheme.error)),
        ),
      );
    }

    final reservations = asyncReservations.value ?? const <Reservation>[];

    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid

    Color colorFor(DayStatus s) => switch (s) {
          DayStatus.available => scheme.surfaceContainerHighest,
          DayStatus.booked => scheme.errorContainer,
          DayStatus.blocked => scheme.outlineVariant,
          DayStatus.pending => scheme.tertiaryContainer,
          DayStatus.past => scheme.surface,
        };

    bool isSelected(DateTime d) {
      final s = selectedStart, e = selectedEnd;
      if (s == null) return false;
      if (e == null) return DateUtils.isSameDay(d, s);
      return !d.isBefore(DateUtils.dateOnly(s)) &&
          !d.isAfter(DateUtils.dateOnly(e));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(child: Center(child: Text(label))),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leadingBlanks) return const SizedBox.shrink();
            final day = DateTime(month.year, month.month, i - leadingBlanks + 1);
            final status = statusFor(day, reservations);
            final selectable =
                status == DayStatus.available && onDayTap != null;

            return InkWell(
              key: Key('day-${day.day}'),
              onTap: selectable ? () => onDayTap!(day) : null,
              child: Container(
                decoration: BoxDecoration(
                  color: colorFor(status),
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected(day)
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: status == DayStatus.past
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                          : null,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, children: [
          for (final (status, label) in [
            (DayStatus.available, 'Available'),
            (DayStatus.booked, 'Booked'),
            (DayStatus.blocked, 'Blocked'),
            (DayStatus.pending, 'On hold'),
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12,
                  decoration: BoxDecoration(
                      color: colorFor(status),
                      borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 4),
              Text(label),
            ]),
        ]),
      ],
    );
  }
}
