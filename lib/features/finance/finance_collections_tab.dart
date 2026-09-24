import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/payment_method.dart';
import '../reports/providers.dart' show ReportFilter;
import 'finance_tables.dart';
import 'providers.dart';

/// One money column of the Collections view: its label on a card, its
/// (shorter) table header, and how to read it off a day.
typedef _Column = ({String label, String header, num Function(CollectionDay) value});

final List<_Column> _columns = [
  (label: 'Online', header: 'Online', value: (d) => d.online),
  for (final m in PaymentMethod.desk)
    (
      label: m.label,
      header: m == PaymentMethod.bankTransfer ? 'Bank' : m.label,
      value: (d) => d.deskFor(m),
    ),
  (label: 'Refunds', header: 'Refunds', value: (d) => d.refunds),
];

String _dayLabel(CollectionDay d) => d.day == null ? 'Total' : formatDate(d.day!);

/// The Collections tab: money in and out per day, online versus desk by
/// method, with refunds and a net. A table on wide screens, one card per
/// day on phones, and a totals row either way.
class FinanceCollectionsTab extends ConsumerWidget {
  const FinanceCollectionsTab({super.key, required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(collectionsProvider(filter));
    Future<void> refresh() => ref.refresh(collectionsProvider(filter).future);
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return AsyncView(
      value: rowsAsync,
      onRetry: () => ref.invalidate(collectionsProvider(filter)),
      empty: () => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            EmptyState(
              icon: Icons.payments_outlined,
              title: 'No collections in this period',
              message: 'Try a wider date range.',
            ),
          ],
        ),
      ),
      data: (rows) {
        final days = collectionsByDay(rows);
        final total = collectionsTotal(days);
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: wide
                ? [_CollectionsTable(days: days, total: total)]
                : [
                    for (final d in days)
                      _CollectionsCard(key: Key('collections-${isoDate(d.day!)}'), day: d),
                    _CollectionsCard(key: const Key('collections-total'), day: total),
                  ],
          ),
        );
      },
    );
  }
}

class _CollectionsTable extends StatelessWidget {
  const _CollectionsTable({required this.days, required this.total});

  final List<CollectionDay> days;
  final CollectionDay total;

  DataRow _row(CollectionDay d, {bool isTotal = false}) {
    final style = isTotal ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return DataRow(cells: [
      DataCell(Text(_dayLabel(d), style: style)),
      for (final c in _columns) DataCell(Text(formatMoney(c.value(d)), style: style)),
      DataCell(Text(formatMoney(d.net), style: style)),
    ]);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('collections-table'),
          columns: [
            const DataColumn(label: Text('Date')),
            for (final c in _columns) DataColumn(label: Text(c.header), numeric: true),
            const DataColumn(label: Text('Net'), numeric: true),
          ],
          rows: [for (final d in days) _row(d), _row(total, isTotal: true)],
        ),
      );
}

class _CollectionsCard extends StatelessWidget {
  const _CollectionsCard({super.key, required this.day});

  final CollectionDay day;

  @override
  Widget build(BuildContext context) {
    final isTotal = day.day == null;
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_dayLabel(day), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            for (final c in _columns)
              if (isTotal || c.value(day) != 0)
                Text('${c.label} ${formatMoney(c.value(day))}'),
            Text('Net ${formatMoney(day.net)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
