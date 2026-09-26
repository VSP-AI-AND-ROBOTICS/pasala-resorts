import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/repositories/stay_repository.dart';
import '../booking/providers.dart' show reservationProvider;
import '../invoice/invoice_pdf_button.dart';
import 'included_tax_line.dart';

/// Itemized final invoice, with its PDF (`InvoicePdfButton`). The guest
/// lands here after self-checkout, and reception after a desk checkout.
class FinalInvoiceScreen extends ConsumerWidget {
  const FinalInvoiceScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationAsync = ref.watch(reservationProvider(reservationId));
    final chargesAsync = ref.watch(currentChargesProvider(reservationId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Final Invoice')),
      body: AsyncView(
        value: reservationAsync,
        data: (reservation) => AsyncView(
          value: chargesAsync,
          data: (charges) => ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Booking ${reservation.id.substring(0, 8)}',
                          style: textTheme.titleMedium),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        '${formatDay(reservation.start.toLocal())} → '
                        '${formatDay(reservation.end.toLocal())}',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const Divider(height: Spacing.lg),
                      Row(children: [
                        const Expanded(child: Text('Farmhouse stay')),
                        Text(formatInr(charges.stayAmount)),
                      ]),
                      const SizedBox(height: Spacing.xs),
                      Row(children: [
                        const Expanded(child: Text('Food')),
                        Text(formatInr(charges.foodAmount)),
                      ]),
                      if (charges.foodTax > 0)
                        IncludedTaxLine(
                            key: const Key('invoice-food-tax'), amount: charges.foodTax),
                      const SizedBox(height: Spacing.xs),
                      Row(children: [
                        const Expanded(child: Text('Activities')),
                        Text(formatInr(charges.activityAmount)),
                      ]),
                      if (charges.activityTax > 0)
                        IncludedTaxLine(
                            key: const Key('invoice-activity-tax'),
                            amount: charges.activityTax),
                      const Divider(),
                      Row(children: [
                        Expanded(child: Text('Final amount', style: textTheme.titleMedium)),
                        Text(formatInr(charges.total), style: textTheme.titleMedium),
                      ]),
                      const SizedBox(height: Spacing.xs),
                      Row(children: [
                        const Expanded(child: Text('Paid')),
                        Text(formatInr(charges.paid)),
                      ]),
                      const SizedBox(height: Spacing.xs),
                      Row(children: [
                        const Expanded(child: Text('Balance')),
                        Text(formatInr(charges.balance)),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              InvoicePdfButton(reservationId: reservationId),
              const SizedBox(height: Spacing.sm),
              FilledButton(
                onPressed: () =>
                    context.push('/my-stay/review/$reservationId'),
                child: const Text('Leave a review'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
