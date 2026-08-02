import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/quote.dart';
import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';
import '../booking/providers.dart' show reservationProvider;
import '../staff/providers.dart' show allBookingsProvider;
import 'providers.dart';

class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationAsync = ref.watch(reservationProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: AsyncView(
        value: reservationAsync,
        onRetry: () => ref.invalidate(reservationProvider(reservationId)),
        data: (reservation) => _Detail(reservation: reservation),
      ),
    );
  }
}

/// A single grouped section of the detail screen: a card with its own
/// padding. Every section on this screen (stay, guests, price, actions) uses
/// this so the page reads as a stack of related cards rather than one long
/// unbroken column of text.
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: child,
        ),
      );
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.reservation});

  final Reservation reservation;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  bool _busy = false;

  /// Opens the confirmation dialog and, if the customer confirms with a
  /// reason, calls `cancel_booking`. Phase 1 has no refund engine, so the
  /// dialog is deliberately silent on any refund amount or timing -- it only
  /// promises what `cancel_booking` actually does today: the dates are
  /// released immediately. Inventing a refund policy here would be a promise
  /// this screen cannot keep.
  Future<void> _cancelBooking() async {
    final isBlock = widget.reservation.kind == ReservationKind.block;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelBookingDialog(isBlock: isBlock),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(bookingActionsProvider).cancel(
            reservationId: widget.reservation.id,
            reason: reason,
          );
      if (!mounted) return;
      ref.invalidate(myBookingsProvider);
      // allBookingsProvider backs both the admin and staff lists, so a
      // cancel here must invalidate it too or those screens keep showing a
      // now-stale status until something else happens to refresh them.
      ref.invalidate(allBookingsProvider);
      context.pop();
    } on BookingFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservation = widget.reservation;
    final quote = reservation.quote;
    final isBlock = reservation.kind == ReservationKind.block;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        // The stay: dates, and -- for a real booking -- who it's for. A
        // block has no guests and no quote -- it exists purely to keep a
        // unit off the calendar, so those rows are simply omitted rather
        // than showing a blank "null guests" or an empty money table.
        _DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isBlock) ...[
                Chip(
                  label: const Text('Admin block'),
                  backgroundColor: scheme.surfaceContainerHigh,
                  side: BorderSide.none,
                ),
                const SizedBox(height: Spacing.sm),
              ],
              Text(
                '${formatDay(reservation.start.toLocal())} → '
                '${formatDay(reservation.end.toLocal())}',
                style: textTheme.headlineSmall,
              ),
              if (reservation.guests != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  '${reservation.guests} guests',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (isBlock && reservation.blockReason != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  'Reason: ${reservation.blockReason}',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (quote != null) ...[
          const SizedBox(height: Spacing.lg),
          _DetailCard(child: _QuoteBreakdown(quote: quote)),
        ],
        if (reservation.status == ReservationStatus.confirmed) ...[
          const SizedBox(height: Spacing.lg),
          _DetailCard(
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('cancel-booking-button'),
                onPressed: _busy ? null : _cancelBooking,
                child: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isBlock ? 'Remove block' : 'Cancel booking'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The reason-entry dialog for cancelling a booking. Owns its own
/// [TextEditingController] and disposes it in [State.dispose] -- tied to the
/// dialog route's own element lifecycle -- rather than the caller disposing
/// it immediately after `showDialog` resolves. `showDialog`'s Future
/// completes as soon as the route is popped, which is BEFORE the pop's
/// reverse (fade/scale) transition finishes animating the dialog off
/// screen; a still-animating `TextField` keeps its controller attached and
/// listening for a few more frames, so an eagerly-disposed controller was
/// used-after-dispose and crashed the widget tree on the way out.
class _CancelBookingDialog extends StatefulWidget {
  const _CancelBookingDialog({required this.isBlock});

  /// True when the reservation being cancelled is an admin block, not a
  /// customer booking -- there is no refund to talk about, so the dialog's
  /// copy must not promise a follow-up that will never happen.
  final bool isBlock;

  @override
  State<_CancelBookingDialog> createState() => _CancelBookingDialogState();
}

class _CancelBookingDialogState extends State<_CancelBookingDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.isBlock ? 'Remove block' : 'Cancel booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.isBlock
                ? 'These dates will be released immediately and become '
                    'bookable again.'
                : 'Your dates will be released immediately so others can '
                    'book them. Refund handling is not yet automated in '
                    'this phase — our team will follow up separately about '
                    'any refund.'),
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('cancel-reason-field'),
              controller: _reasonController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('keep-booking-button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.isBlock ? 'Keep block' : 'Keep booking'),
          ),
          FilledButton(
            key: const Key('confirm-cancel-button'),
            onPressed: () => Navigator.of(context).pop(_reasonController.text),
            child: Text(widget.isBlock ? 'Remove block' : 'Cancel booking'),
          ),
        ],
      );
}

/// The stored quote's breakdown, laid out like `QuoteSheet` minus the pay
/// button -- this screen never re-derives a price, it only displays the
/// figures the server already computed at booking time.
class _QuoteBreakdown extends StatelessWidget {
  const _QuoteBreakdown({required this.quote});

  final Quote quote;

  static const _dateColumnWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Price breakdown', style: textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        for (final line in quote.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Row(children: [
              SizedBox(
                width: _dateColumnWidth,
                child: Text(
                  formatDay(line.date),
                  style:
                      textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(child: Text(line.label)),
              Text(formatInr(line.amount)),
            ]),
          ),
        for (final line in quote.lines)
          if (line.extraGuests > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(children: [
                SizedBox(
                  width: _dateColumnWidth,
                  child: Text(
                    formatDay(line.date),
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Expanded(child: Text('${line.extraGuests} extra guests')),
                Text(formatInr(line.extraGuestAmount)),
              ]),
            ),
        const Divider(),
        Row(children: [
          Expanded(
              child: Text('Cleaning fee',
                  style:
                      textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
          Text(formatInr(quote.cleaningFee)),
        ]),
        const SizedBox(height: Spacing.sm),
        Row(children: [
          Expanded(child: Text('Total', style: textTheme.titleLarge)),
          Text(formatInr(quote.total), style: textTheme.titleLarge),
        ]),
      ],
    );
  }
}
