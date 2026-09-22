import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/loading_state.dart';
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
      _
          when r.status == ReservationStatus.hold ||
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
        padding: EdgeInsets.symmetric(vertical: Spacing.xl),
        child: LoadingState(),
      );
    }
    if (asyncReservations.hasError && !asyncReservations.hasValue) {
      // I2: this used to show `error.message` verbatim for ANY
      // BookingFailure -- but UnknownFailure IS a BookingFailure and wraps
      // whatever raw text Postgres or the transport layer produced (see
      // FailureView's own header comment), so a permission error like
      // "permission denied for table reservations" was printed straight to
      // the customer. FailureView.messageFor exists precisely to intercept
      // UnknownFailure and fall back to a generic message; every other
      // BookingFailure's own customer-facing message still passes through
      // unchanged.
      final rawError = asyncReservations.error;
      final message = rawError == null
          ? 'Could not load availability.'
          : FailureView.messageFor(rawError);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
        child: Center(
          child: Text(message, style: TextStyle(color: scheme.error)),
        ),
      );
    }

    final reservations = asyncReservations.value ?? const <Reservation>[];

    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid

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
        const SizedBox(height: Spacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: Spacing.xs,
            crossAxisSpacing: Spacing.xs,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leadingBlanks) return const SizedBox.shrink();
            final day = DateTime(
              month.year,
              month.month,
              i - leadingBlanks + 1,
            );
            final status = statusFor(day, reservations);
            final selectable =
                status == DayStatus.available && onDayTap != null;

            return InkWell(
              key: Key('day-${day.day}'),
              onTap: selectable ? () => onDayTap!(day) : null,
              child: _DayCell(
                day: day.day,
                status: status,
                selected: isSelected(day),
              ),
            );
          },
        ),
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.xs,
          children: [
            for (final status in DayStatus.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: _DayCell(day: null, status: status, selected: false),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Text(_legendLabel(status)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

String _legendLabel(DayStatus status) => switch (status) {
  DayStatus.available => 'Available',
  DayStatus.booked => 'Booked',
  DayStatus.blocked => 'Blocked',
  DayStatus.pending => 'Reserved',
  DayStatus.past => 'Past',
};

/// One calendar cell's visuals for [status]. Every state carries a cue
/// beyond colour so the calendar reads correctly for colour-blind users:
/// available is a plain outlined surface, booked is a solid filled cell,
/// blocked carries a diagonal hatch, on-hold carries a dashed outline, and
/// past is the whole cell at reduced opacity. [day] is null when this is
/// used as a legend swatch rather than a real grid cell.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.status,
    required this.selected,
  });

  final int? day;
  final DayStatus status;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = day == null
        ? const SizedBox.shrink()
        : Text('$day', style: _textStyleFor(scheme));

    Widget cell = switch (status) {
      DayStatus.available => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
          border: Border.all(color: Colors.green.shade700),
        ),
        child: Center(child: label),
      ),
      DayStatus.booked => DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
        ),
        child: Center(child: label),
      ),
      DayStatus.blocked => ClipRRect(
        borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
        child: DecoratedBox(
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _DiagonalHatchPainter(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                ),
              ),
              Center(child: label),
            ],
          ),
        ),
      ),
      DayStatus.pending => CustomPaint(
        painter: _DashedBorderPainter(
          color: scheme.tertiary,
          radius: PasalaTokens.radiusSm,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
          ),
          child: Center(child: label),
        ),
      ),
      DayStatus.past => DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(child: label),
      ),
    };

    // Past is muted at reduced opacity regardless of its underlying shape --
    // it never overlaps with booked/blocked/pending in `statusFor` (the past
    // check runs first and wins), so this only ever mutes the plain style
    // above, but stays written generically in case that ever changes.
    if (status == DayStatus.past) {
      cell = Opacity(opacity: 0.45, child: cell);
    }

    if (selected) {
      // A gap between this ring and the cell it wraps is what makes the
      // selection actually visible: every status branch above already
      // paints its own opaque fill, so nesting the ring flush against it
      // (no padding) would have the ring's own fill painted over entirely
      // and its border sit pixel-on-pixel against the "available" cell's
      // own similarly green border -- selecting a date looked like nothing
      // happened at all. The 3px inset leaves a visible halo regardless of
      // the wrapped cell's own colours.
      cell = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm + 3),
          border: Border.all(color: scheme.primary, width: 2.5),
        ),
        child: cell,
      );
    }
    return cell;
  }

  TextStyle? _textStyleFor(ColorScheme scheme) => switch (status) {
    DayStatus.booked => TextStyle(
      color: scheme.onErrorContainer,
      fontWeight: FontWeight.w700,
    ),
    DayStatus.pending => TextStyle(color: scheme.onTertiaryContainer),
    DayStatus.blocked => TextStyle(color: scheme.onSurfaceVariant),
    DayStatus.available => null,
    DayStatus.past => TextStyle(color: scheme.onSurfaceVariant),
  };
}

/// Diagonal hatch texture for a blocked day -- a shape cue independent of
/// hue, so it still reads for a colour-blind viewer.
class _DiagonalHatchPainter extends CustomPainter {
  const _DiagonalHatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const gap = 6.0;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalHatchPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Dashed rounded-rect outline for an on-hold day -- distinct in shape from
/// the solid borders used elsewhere on the grid, independent of hue.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dashArray = [4.0, 3.0];

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final source = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      var i = 0;
      while (distance < metric.length) {
        final len = _dashArray[i % _dashArray.length];
        if (draw) {
          canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        }
        distance += len;
        draw = !draw;
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
