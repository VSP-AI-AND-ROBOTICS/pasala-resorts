import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/stay_repository.dart';
import '../booking/payment_gateway.dart';

/// The final bill, settled through the same mock [PaymentGateway] seam
/// `booking_screen.dart`'s own `_pay` already uses -- `checkout_booking`
/// never trusts a client-supplied amount, so this screen exists only to
/// show the balance and drive the same charge->confirm flow customers
/// already know from booking.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _busy = false;

  Future<void> _checkout(double balance) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? paymentRef;
      if (balance > 0) {
        final payment = await ref
            .read(paymentGatewayProvider)
            .charge(reservationId: widget.reservationId, amount: balance);
        if (!payment.succeeded) {
          throw InvalidState(payment.failureMessage ?? 'Payment failed');
        }
        paymentRef = payment.reference;
      }
      await ref.read(stayRepositoryProvider).checkout(
            reservationId: widget.reservationId,
            paymentRef: paymentRef ?? 'no-balance-due',
            amount: balance,
          );
      if (!mounted) return;
      ref.invalidate(currentStayProvider);
      // The final invoice re-reads current_charges for this exact
      // reservation id -- without invalidating it here, it would show the
      // cached pre-payment figures (paid ₹0, balance still due) instead of
      // the balance payment `checkout_booking` just recorded.
      ref.invalidate(currentChargesProvider(widget.reservationId));
      context.go('/my-stay/invoice/${widget.reservationId}');
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
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _busy ? null : () => _checkout(charges.balance),
              child: Text(_busy
                  ? 'Processing…'
                  : charges.balance > 0
                      ? 'Pay ${formatInr(charges.balance)} and check out'
                      : 'Check out'),
            ),
          ],
        ),
      ),
    );
  }
}
