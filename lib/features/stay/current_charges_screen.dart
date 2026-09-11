import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/repositories/stay_repository.dart';

/// Live breakdown from `current_charges`, laid out like `QuoteSheet`'s own
/// price breakdown -- every figure here is a server computation, never
/// derived in Dart.
class CurrentChargesScreen extends ConsumerWidget {
  const CurrentChargesScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chargesAsync = ref.watch(currentChargesProvider(reservationId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Current Charges')),
      body: AsyncView(
        value: chargesAsync,
        onRetry: () => ref.invalidate(currentChargesProvider(reservationId)),
        data: (charges) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Expanded(child: Text('Farmhouse stay')),
                      Text(formatInr(charges.stayAmount)),
                    ]),
                    const SizedBox(height: Spacing.xs),
                    Row(children: [
                      const Expanded(child: Text('Food')),
                      Text(formatInr(charges.foodAmount)),
                    ]),
                    const SizedBox(height: Spacing.xs),
                    Row(children: [
                      const Expanded(child: Text('Activities')),
                      Text(formatInr(charges.activityAmount)),
                    ]),
                    const Divider(),
                    Row(children: [
                      Expanded(
                          child: Text('Current Total', style: textTheme.titleMedium)),
                      Text(formatInr(charges.total), style: textTheme.titleMedium),
                    ]),
                    const SizedBox(height: Spacing.xs),
                    Row(children: [
                      Expanded(
                        child: Text('Already paid',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                      Text(formatInr(charges.paid)),
                    ]),
                    const SizedBox(height: Spacing.sm),
                    Row(children: [
                      Expanded(child: Text('Balance due', style: textTheme.titleLarge)),
                      Text(
                        formatInr(charges.balance),
                        style: textTheme.titleLarge?.copyWith(color: scheme.primary),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
