import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models/report.dart';
import 'providers.dart';

/// `/admin/dashboard` -- the staff landing page for "how is the business
/// doing right now". Every number comes straight from `dashboard_summary()`;
/// nothing here adds, subtracts, or divides -- [formatInr] only formats
/// what the server already computed.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final summary = ref.watch(dashboardSummaryProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(dashboardSummaryProvider(propertyId)),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardSummaryProvider(propertyId)),
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
                  // A fixed height (rather than childAspectRatio) so a
                  // card's content -- label, headline-sized figure, caption
                  // -- always has enough room regardless of column count.
                  // At narrow widths a ratio-based height shrinks along
                  // with the width and the fixed-size text no longer fits,
                  // overflowing the card.
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
