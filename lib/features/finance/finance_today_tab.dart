import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models/payment_method.dart';
import 'finance_tables.dart';
import 'providers.dart';

/// The Today tab: money in and out today in the resort's own timezone,
/// room, food & drink and spa tax, and what the guests in house still owe.
/// Everything comes from one `finance_summary` call.
class FinanceTodayTab extends ConsumerWidget {
  const FinanceTodayTab({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(financeSummaryProvider(propertyId));
    Future<void> refresh() => ref.refresh(financeSummaryProvider(propertyId).future);

    return AsyncView(
      value: summaryAsync,
      onRetry: () => ref.invalidate(financeSummaryProvider(propertyId)),
      data: (s) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Text('Today, ${formatDate(s.resort.today)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.md,
              children: [
                _FigureCard(
                  key: const Key('today-online'),
                  icon: PaymentMethod.gateway.icon,
                  label: 'Online collected',
                  value: formatMoney(s.onlineCollected),
                ),
                _FigureCard(
                  key: const Key('today-desk'),
                  icon: Icons.point_of_sale_outlined,
                  label: 'Desk collected',
                  value: formatMoney(s.deskCollected),
                  lines: [
                    for (final m in PaymentMethod.desk)
                      '${m.label} ${formatMoney(s.deskByMethod[m] ?? 0)}',
                  ],
                ),
                _FigureCard(
                  key: const Key('today-refunds'),
                  icon: Icons.undo_outlined,
                  label: 'Refunds',
                  value: formatMoney(s.refunds),
                ),
                _FigureCard(
                  key: const Key('today-net'),
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Net collected',
                  value: formatMoney(s.netCollected),
                ),
                _FigureCard(
                  key: const Key('today-room-tax'),
                  icon: Icons.receipt_long_outlined,
                  label: 'Room tax',
                  value: formatMoney(s.roomTax),
                ),
                _FigureCard(
                  key: const Key('today-food-tax'),
                  icon: Icons.restaurant_outlined,
                  label: 'F&B tax',
                  value: formatMoney(s.foodTax),
                ),
                _FigureCard(
                  key: const Key('today-spa-tax'),
                  icon: Icons.spa_outlined,
                  label: 'Spa tax',
                  value: formatMoney(s.spaTax),
                ),
                _FigureCard(
                  key: const Key('today-in-house'),
                  icon: Icons.hotel_outlined,
                  label: 'In-house guests',
                  value: '${s.inHouseCount}',
                  lines: ['Unpaid balance ${formatMoney(s.inHouseBalance)}'],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.lines = const [],
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 280,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(child: Text(label, style: textTheme.labelLarge)),
              ]),
              const SizedBox(height: Spacing.sm),
              Text(value,
                  style: textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(line, style: textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
