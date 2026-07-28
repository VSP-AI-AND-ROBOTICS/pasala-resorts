import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/quote.dart';
import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';
import '../booking/providers.dart' show reservationProvider;
import 'providers.dart';

class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationAsync = ref.watch(reservationProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: reservationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(reservationProvider(reservationId)),
        ),
        data: (reservation) => _Detail(reservation: reservation),
      ),
    );
  }
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
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelBookingDialog(),
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
      context.pop();
    } on BookingFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservation = widget.reservation;
    final quote = reservation.quote;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${formatDay(reservation.start.toLocal())} → '
          '${formatDay(reservation.end.toLocal())}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        if (reservation.guests != null)
          Text('${reservation.guests} guests'),
        const SizedBox(height: 16),
        if (quote != null) _QuoteBreakdown(quote: quote),
        const SizedBox(height: 24),
        if (reservation.status == ReservationStatus.confirmed)
          OutlinedButton(
            key: const Key('cancel-booking-button'),
            onPressed: _busy ? null : _cancelBooking,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cancel booking'),
          ),
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
  const _CancelBookingDialog();

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
        title: const Text('Cancel booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your dates will be released immediately so others can book '
              'them. Refund handling is not yet automated in this phase — '
              'our team will follow up separately about any refund.',
            ),
            const SizedBox(height: 16),
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
            child: const Text('Keep booking'),
          ),
          FilledButton(
            key: const Key('confirm-cancel-button'),
            onPressed: () => Navigator.of(context).pop(_reasonController.text),
            child: const Text('Cancel booking'),
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

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Price breakdown', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final line in quote.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                  width: 96,
                  child: Text(formatDay(line.date),
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                Expanded(child: Text(line.label)),
                Text(formatInr(line.amount)),
              ]),
            ),
          for (final line in quote.lines)
            if (line.extraGuests > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(
                    width: 96,
                    child: Text(formatDay(line.date),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Expanded(child: Text('${line.extraGuests} extra guests')),
                  Text(formatInr(line.extraGuestAmount)),
                ]),
              ),
          const Divider(),
          Row(children: [
            const Expanded(child: Text('Cleaning fee')),
            Text(formatInr(quote.cleaningFee)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: Text('Total',
                    style: Theme.of(context).textTheme.titleLarge)),
            Text(formatInr(quote.total),
                style: Theme.of(context).textTheme.titleLarge),
          ]),
        ],
      );
}
