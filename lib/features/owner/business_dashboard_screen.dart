import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../reports/providers.dart';

/// `/owner/dashboard` -- the owner's business-at-a-glance view. Reads the
/// exact same `dashboard_summary()` RPC `/admin/dashboard` does (via the
/// same [dashboardSummaryProvider]), plus the three keys
/// `0030_owner_dashboard_summary.sql` added on top: food sales today,
/// expenses this month, and net profit this month. Every figure is
/// computed server-side -- this screen only formats what the server
/// already computed, same discipline as `DashboardScreen`.
///
/// Grouped into three eyebrow-labeled sections (Today / This Month /
/// Operations) rather than one flat 9-tile grid -- the groupings mirror how
/// an owner actually thinks about the business (cash today vs. the month's
/// trend vs. what's operationally in flight), and Net Profit is colored red
/// when the month is running at a loss, a real signal rather than
/// decoration.
class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final summary = ref.watch(dashboardSummaryProvider(propertyId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Business dashboard')),
      body: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(dashboardSummaryProvider(propertyId)),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardSummaryProvider(propertyId)),
          child: ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _eyebrow(context, 'TODAY'),
              const SizedBox(height: Spacing.sm),
              _MetricRow(metrics: [
                (
                  icon: Icons.currency_rupee,
                  label: 'Revenue today',
                  value: formatInr(s.todayRevenue),
                  caption: 'Confirmed bookings, net of refunds',
                  color: scheme.primary,
                ),
                (
                  icon: Icons.restaurant_outlined,
                  label: 'Food & activity sales',
                  value: formatInr(s.foodSalesToday),
                  caption: 'Across every property',
                  color: scheme.primary,
                ),
              ]),
              const SizedBox(height: Spacing.lg),
              _eyebrow(context, 'THIS MONTH'),
              const SizedBox(height: Spacing.sm),
              _MetricRow(metrics: [
                (
                  icon: Icons.trending_up,
                  label: 'Revenue',
                  value: formatInr(s.monthRevenue),
                  caption: 'Month to date',
                  color: scheme.primary,
                ),
                (
                  icon: Icons.receipt_long_outlined,
                  label: 'Expenses',
                  value: formatInr(s.expensesMonthTotal),
                  caption: 'Month to date',
                  color: scheme.onSurfaceVariant,
                ),
                (
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Net profit',
                  value: formatInr(s.netProfitMonth),
                  caption: 'Revenue minus expenses',
                  color: s.netProfitMonth < 0 ? scheme.error : scheme.primary,
                ),
              ]),
              const SizedBox(height: Spacing.lg),
              _eyebrow(context, 'OPERATIONS'),
              const SizedBox(height: Spacing.sm),
              _MetricRow(metrics: [
                (
                  icon: Icons.pie_chart_outline,
                  label: 'Occupancy',
                  value: '${s.occupancyPct}%',
                  caption: 'Average across active units',
                  color: scheme.tertiary,
                ),
                (
                  icon: Icons.flight_land_outlined,
                  label: 'Upcoming arrivals',
                  value: '${s.upcomingArrivals}',
                  caption: 'Confirmed, next 7 days',
                  color: scheme.tertiary,
                ),
                (
                  icon: Icons.cancel_outlined,
                  label: 'Cancellations',
                  value: '${s.cancellationsThisMonth}',
                  caption: 'This month',
                  color: scheme.onSurfaceVariant,
                ),
                (
                  icon: Icons.hourglass_empty,
                  label: 'Active holds',
                  value: '${s.activeHolds}',
                  caption: 'Not yet expired',
                  color: scheme.onSurfaceVariant,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _eyebrow(BuildContext context, String text) => Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
    );

typedef _Metric = ({
  IconData icon,
  String label,
  String value,
  String caption,
  Color color,
});

/// A responsive row of [_MetricCard]s -- wraps onto a new line on narrow
/// widths rather than squeezing, since these cards carry a caption line
/// each and don't compress well.
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 200).floor().clamp(1, 4);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: Spacing.sm,
              crossAxisSpacing: Spacing.sm,
              mainAxisExtent: 130,
            ),
            itemCount: metrics.length,
            itemBuilder: (context, i) => _MetricCard(metric: metrics[i]),
          );
        },
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon, color: metric.color, size: 20),
            const SizedBox(height: Spacing.sm),
            Text(metric.value,
                style: textTheme.titleLarge
                    ?.copyWith(color: metric.color, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(metric.label, style: textTheme.bodySmall),
            Text(
              metric.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
