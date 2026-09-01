import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models/report.dart';
import '../reports/providers.dart';

/// `/owner/dashboard` -- the owner's business-at-a-glance view. Reads the
/// exact same `dashboard_summary()` RPC `/admin/dashboard` does (via the
/// same [dashboardSummaryProvider]), plus the three keys
/// `0030_owner_dashboard_summary.sql` added on top: food sales today,
/// expenses this month, and net profit this month. Every figure is
/// computed server-side -- this screen only formats what the server
/// already computed, same discipline as `DashboardScreen`.
class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Business dashboard')),
      body: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cards = _statCards(s);
              final columns = (constraints.maxWidth / 220).floor().clamp(1, 4);
              return GridView.builder(
                padding: const EdgeInsets.all(Spacing.md),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: Spacing.md,
                  crossAxisSpacing: Spacing.md,
                  mainAxisExtent: 180,
                ),
                itemCount: cards.length,
                itemBuilder: (context, i) => cards[i],
              );
            },
          ),
        ),
      ),
    );
  }

  List<_StatCard> _statCards(DashboardSummary s) => [
        _StatCard(
          label: 'Revenue today',
          figure: formatInr(s.todayRevenue),
          caption: 'Confirmed bookings, net of refunds',
        ),
        _StatCard(
          label: 'Revenue this month',
          figure: formatInr(s.monthRevenue),
          caption: 'Month to date',
        ),
        _StatCard(
          label: 'Occupancy',
          figure: '${s.occupancyPct}%',
          caption: 'Average across active units, this month',
        ),
        _StatCard(
          label: 'Food & activity sales today',
          figure: formatInr(s.foodSalesToday),
          caption: 'Across every property',
        ),
        _StatCard(
          label: 'Expenses this month',
          figure: formatInr(s.expensesMonthTotal),
          caption: 'Month to date',
        ),
        _StatCard(
          label: 'Net profit this month',
          figure: formatInr(s.netProfitMonth),
          caption: 'Revenue minus expenses, month to date',
        ),
        _StatCard(
          label: 'Upcoming arrivals',
          figure: '${s.upcomingArrivals}',
          caption: 'Confirmed, next 7 days',
        ),
        _StatCard(
          label: 'Cancellations',
          figure: '${s.cancellationsThisMonth}',
          caption: 'This month',
        ),
        _StatCard(
          label: 'Active holds',
          figure: '${s.activeHolds}',
          caption: 'Not yet expired',
        ),
      ];
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.figure,
    required this.caption,
  });

  final String label;
  final String figure;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(figure, style: textTheme.headlineMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              caption,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
