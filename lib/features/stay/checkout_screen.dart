import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/payment_method.dart';
import '../../data/repositories/room_status_repository.dart';
import '../../data/repositories/stay_repository.dart';
import '../booking/payment_gateway.dart';
import '../finance/providers.dart';
import '../staff/providers.dart' show allBookingsProvider;

/// Builds the guest's own `/my-stay/checkout` from its route `extra`, the
/// reservation id. Reception's desk checkout is `/admin/check-out/:id`.
Widget checkoutScreenFor(Object? extra) => switch (extra) {
      final String reservationId => CheckoutScreen(reservationId: reservationId),
      _ => throw ArgumentError.value(extra, 'extra', 'checkout needs a reservation id'),
    };

/// The final bill. A guest settles it through the same [PaymentGateway]
/// `booking_screen.dart`'s own `_pay` uses (Razorpay, or the mock without
/// keys). At the desk ([desk]) reception records how the guest paid -- the
/// method and an optional receipt or UTR number -- and the gateway is
/// never called.
/// `checkout_booking` never trusts a client-supplied amount, and refuses a
/// desk method from anyone who is not staff at the booking's resort.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.reservationId, this.desk = false});

  final String reservationId;

  /// Reception's desk checkout rather than the guest's own.
  final bool desk;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _busy = false;
  PaymentMethod _method = PaymentMethod.cash;
  final _reference = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _checkout(double balance) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final stay = ref.read(stayRepositoryProvider);
      if (widget.desk) {
        final reference = _reference.text.trim();
        await stay.checkout(
          reservationId: widget.reservationId,
          paymentRef: balance > 0 && reference.isNotEmpty ? reference : null,
          amount: balance,
          // Nothing due writes no payment, so there is no method to record.
          method: balance > 0 ? _method : PaymentMethod.gateway,
        );
      } else {
        String? paymentRef;
        if (balance > 0) {
          final payment = await ref.read(paymentGatewayProvider).charge(
                reservationId: widget.reservationId,
                amount: balance,
                purpose: PaymentPurpose.balance,
              );
          if (!payment.succeeded) {
            throw InvalidState(payment.failureMessage ?? 'Payment failed');
          }
          paymentRef = payment.reference;
        }
        await stay.checkout(
          reservationId: widget.reservationId,
          paymentRef: paymentRef ?? 'no-balance-due',
          amount: balance,
        );
      }
      if (!mounted) return;
      ref.invalidate(currentStayProvider);
      // The final invoice re-reads current_charges for this exact
      // reservation id -- without invalidating it here, it would show the
      // cached pre-payment figures (paid ₹0, balance still due) instead of
      // the balance payment `checkout_booking` just recorded.
      ref.invalidate(currentChargesProvider(widget.reservationId));
      // Collections, settlements and today's figures include this payment.
      invalidateFinance(ref);
      if (widget.desk) {
        // Reception's own views of this booking: the check-out queue and the
        // dashboard's bookings drop it, and checkout_booking marks the room
        // for cleaning. (The desk screen is reached by URL, not pushed from
        // the check-out list, so the list cannot refetch on return.)
        ref.invalidate(checkedInProvider);
        ref.invalidate(allBookingsProvider);
        ref.invalidate(roomBoardProvider);
      }
      context.go('/my-stay/invoice/${widget.reservationId}');
    } on BookingFailure catch (e) {
      if (!mounted) return;
      // The balance may have changed under an online payment (a food order
      // placed meanwhile leaves the payment unapplied and refunded), so
      // show the current figure before the guest tries again.
      if (!widget.desk) {
        ref.invalidate(currentChargesProvider(widget.reservationId));
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _buttonLabel(double balance) {
    if (_busy) return 'Processing…';
    if (balance <= 0) return 'Check out';
    return widget.desk
        ? 'Record ${formatInr(balance)} and check out'
        : 'Pay ${formatInr(balance)} and check out';
  }

  Widget _deskPayment(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Payment method', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final m in PaymentMethod.desk)
                    ChoiceChip(
                      key: Key('desk-method-${m.wire}'),
                      avatar: Icon(m.icon, size: 18),
                      label: Text(m.label),
                      selected: _method == m,
                      onSelected: _busy ? null : (_) => setState(() => _method = m),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: const Key('desk-reference'),
                controller: _reference,
                enabled: !_busy,
                maxLength: 64,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                  helperText: 'Receipt, card slip or UTR number',
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final chargesAsync = ref.watch(currentChargesProvider(widget.reservationId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: AsyncView(
        value: chargesAsync,
        onRetry: () => ref.invalidate(currentChargesProvider(widget.reservationId)),
        data: (charges) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Final bill', style: textTheme.titleMedium),
                    const SizedBox(height: Spacing.md),
                    Row(children: [
                      const Expanded(child: Text('Total charges')),
                      Text(formatInr(charges.total)),
                    ]),
                    const SizedBox(height: Spacing.xs),
                    Row(children: [
                      const Expanded(child: Text('Paid so far')),
                      Text(formatInr(charges.paid)),
                    ]),
                    const Divider(),
                    Row(children: [
                      Expanded(child: Text('Balance to pay', style: textTheme.titleLarge)),
                      Text(
                        formatInr(charges.balance),
                        style: textTheme.titleLarge?.copyWith(color: scheme.primary),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            if (widget.desk && charges.balance > 0) ...[
              const SizedBox(height: Spacing.md),
              _deskPayment(context),
            ],
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _busy ? null : () => _checkout(charges.balance),
              child: Text(_buttonLabel(charges.balance)),
            ),
          ],
        ),
      ),
    );
  }
}
