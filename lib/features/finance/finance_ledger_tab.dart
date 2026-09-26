import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/finance.dart';
import '../reports/providers.dart' show ReportFilter;
import 'finance_csv.dart';
import 'finance_tables.dart';
import 'providers.dart';

typedef _Column = ({String label, num Function(LedgerDay) value});

/// Category columns hold taxable amounts, so they add up to Taxable; the
/// category tax columns add up to Tax; and Taxable + Tax = Total.
final List<_Column> _columns = [
  for (final c in LedgerCategory.values) (label: c.label, value: (d) => d.categoryTotal(c)),
  (label: 'Taxable', value: (d) => d.taxable),
  for (final c in LedgerCategory.values) (label: '${c.label} tax', value: (d) => d.taxFor(c)),
  (label: 'Tax', value: (d) => d.tax),
];

String _dayLabel(LedgerDay d) => d.day == null ? 'Total' : formatDate(d.day!);

/// The Ledger tab: revenue earned per day by category (accrual basis),
/// with tax per category -- room tax as fixed in each booking's quote,
/// food and spa tax as stored on each order and sale -- a totals row and a
/// tax strip.
class FinanceLedgerTab extends ConsumerWidget {
  const FinanceLedgerTab({super.key, required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(ledgerProvider(filter));
    final resort = ref.watch(financeSummaryProvider(filter.propertyId)).value?.resort;
    Future<void> refresh() => ref.refresh(ledgerProvider(filter).future);
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return AsyncView(
      value: rowsAsync,
      onRetry: () => ref.invalidate(ledgerProvider(filter)),
      empty: () => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            EmptyState(
              icon: Icons.account_balance_outlined,
              title: 'No revenue in this period',
              message: 'Try a wider date range.',
            ),
          ],
        ),
      ),
      data: (rows) {
        final days = ledgerByDay(rows);
        final total = ledgerTotal(days);
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _TaxStrip(total: total, resort: resort),
              const SizedBox(height: Spacing.md),
              if (wide)
                _LedgerTable(days: days, total: total)
              else ...[
                for (final d in days)
                  _LedgerCard(key: Key('ledger-${isoDate(d.day!)}'), day: d),
                _LedgerCard(key: const Key('ledger-total'), day: total),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TaxStrip extends StatelessWidget {
  const _TaxStrip({required this.total, required this.resort});

  final LedgerDay total;
  final FinanceResort? resort;

  @override
  Widget build(BuildContext context) {
    final r = resort;
    return Card(
      key: const Key('ledger-tax-strip'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Wrap(
          spacing: Spacing.lg,
          runSpacing: Spacing.xs,
          children: [
            Text('Taxable ${formatMoney(total.taxable)}'),
            Text('Tax ${formatMoney(total.tax)}'),
            for (final c in LedgerCategory.values)
              if (total.taxFor(c) != 0)
                Text('${c.label} tax ${formatMoney(total.taxFor(c))}'),
            if (r != null) Text('Room rate ${formatPct(r.taxPct)}%'),
            if (r != null) Text('F&B rate ${formatPct(r.fnbTaxPct)}%'),
            if (r != null) Text('Spa/Activities rate ${formatPct(r.spaTaxPct)}%'),
            if (r != null) Text(gstinLabel(r)),
            Text('Each booking and sale keeps the rate it was made at.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.days, required this.total});

  final List<LedgerDay> days;
  final LedgerDay total;

  DataRow _row(LedgerDay d, {bool isTotal = false}) {
    final style = isTotal ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return DataRow(cells: [
      DataCell(Text(_dayLabel(d), style: style)),
      for (final c in _columns) DataCell(Text(formatMoney(c.value(d)), style: style)),
      DataCell(Text(formatMoney(d.total), style: style)),
    ]);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('ledger-table'),
          columns: [
            const DataColumn(label: Text('Date')),
            for (final c in _columns) DataColumn(label: Text(c.label), numeric: true),
            const DataColumn(label: Text('Total'), numeric: true),
          ],
          rows: [for (final d in days) _row(d), _row(total, isTotal: true)],
        ),
      );
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({super.key, required this.day});

  final LedgerDay day;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: Spacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_dayLabel(day), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Spacing.xs),
              for (final c in LedgerCategory.values)
                if (day.categoryTotal(c) != 0)
                  Text('${c.label} ${formatMoney(day.categoryTotal(c))}'),
              Text('Taxable ${formatMoney(day.taxable)}'),
              Text('Tax ${formatMoney(day.tax)}'),
              for (final c in LedgerCategory.values)
                if (day.taxFor(c) != 0)
                  Text('${c.label} tax ${formatMoney(day.taxFor(c))}',
                      style: Theme.of(context).textTheme.bodySmall),
              Text('Total ${formatMoney(day.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}
