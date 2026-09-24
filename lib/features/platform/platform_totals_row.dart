import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// The console's three count cards (REQ-08): Subscribed resorts, Active
/// subscriptions and MRR, from `platform_summary()`. Platform-wide: the
/// search and tier filter never change them. They wrap on a phone.
class PlatformTotalsRow extends ConsumerWidget {
  const PlatformTotalsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalsAsync = ref.watch(platformTotalsProvider);
    final totals = totalsAsync.value;

    // Loading or failed: a dash, never a zero that looks like real data.
    String show(String Function(PlatformTotals t) pick) =>
        totals == null ? '—' : pick(totals);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            _TotalCard(
              key: const Key('total-subscribed'),
              label: 'Subscribed resorts',
              value: show((t) => '${t.subscribed}'),
            ),
            _TotalCard(
              key: const Key('total-active'),
              label: 'Active subscriptions',
              value: show((t) => '${t.active}'),
              detail: totals == null
                  ? null
                  : 'incl. ${totals.trials} trial${totals.trials == 1 ? '' : 's'}',
            ),
            _TotalCard(
              key: const Key('total-mrr'),
              label: 'MRR',
              value: show((t) => formatInr(t.mrrInr)),
            ),
          ],
        ),
        if (totalsAsync.hasError && !totalsAsync.isLoading)
          TextButton.icon(
            key: const Key('totals-retry'),
            onPressed: () => ref.invalidate(platformTotalsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Totals unavailable. Retry'),
          ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    super.key,
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: Spacing.xs),
              Text(value, style: textTheme.headlineSmall),
              if (detail != null)
                Text(detail!,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
