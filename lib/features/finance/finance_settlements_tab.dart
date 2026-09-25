import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/finance.dart';
import '../invoice/invoice_pdf_button.dart';
import '../reports/providers.dart' show ReportFilter;
import 'finance_tables.dart';
import 'providers.dart';

/// `Cash · R-101`: how the desk balance was taken.
String _deskLine(SettlementRow r) =>
    [r.deskMethod?.label, r.deskReference].whereType<String>().join(' · ');

/// The Settlements tab: one row per booking checked out in the range, with
/// its whole bill and how it was paid. A non-zero outstanding carries an
/// icon and text, never colour alone.
class FinanceSettlementsTab extends ConsumerWidget {
  const FinanceSettlementsTab({super.key, required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(settlementsProvider(filter));
    Future<void> refresh() => ref.refresh(settlementsProvider(filter).future);
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

    return AsyncView(
      value: rowsAsync,
      onRetry: () => ref.invalidate(settlementsProvider(filter)),
      empty: () => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No checkouts in this period',
              message: 'Bookings checked out in this range show up here.',
            ),
          ],
        ),
      ),
      data: (rows) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: wide
              ? [_SettlementsTable(rows: rows)]
              : [for (final r in rows) _SettlementCard(key: Key('settlement-${r.reservationId}'), row: r)],
        ),
      ),
    );
  }
}

class _OutstandingFlag extends StatelessWidget {
  const _OutstandingFlag({required this.row});

  final SettlementRow row;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Row(
      key: Key('outstanding-${row.reservationId}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_outlined, size: 18, color: color),
        const SizedBox(width: Spacing.xs),
        Text('Outstanding ${formatMoney(row.outstanding)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({super.key, required this.row});

  final SettlementRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.guestName} · ${r.unitName}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('${formatDate(r.arrival)} → ${formatDate(r.departure)}'),
            const SizedBox(height: Spacing.xs),
            Text('Total ${formatMoney(r.total)}'),
            Text('Advance ${formatMoney(r.advancePaid)}'),
            if (r.balanceOnline != 0) Text('Balance online ${formatMoney(r.balanceOnline)}'),
            if (r.balanceDesk != 0)
              Text('Balance at desk ${formatMoney(r.balanceDesk)} (${_deskLine(r)})'),
            if (r.recordedByName != null) Text('Recorded by ${r.recordedByName}'),
            const SizedBox(height: Spacing.xs),
            Row(children: [
              Expanded(
                child: r.outstanding != 0
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: _OutstandingFlag(row: r),
                      )
                    : const Text('Settled'),
              ),
              InvoicePdfButton(
                reservationId: r.reservationId,
                style: InvoicePdfButtonStyle.icon,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SettlementsTable extends StatelessWidget {
  const _SettlementsTable({required this.rows});

  final List<SettlementRow> rows;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('settlements-table'),
          columns: const [
            DataColumn(label: Text('Guest')),
            DataColumn(label: Text('Unit')),
            DataColumn(label: Text('Arrival')),
            DataColumn(label: Text('Departure')),
            DataColumn(label: Text('Room'), numeric: true),
            DataColumn(label: Text('Cleaning'), numeric: true),
            DataColumn(label: Text('Tax'), numeric: true),
            DataColumn(label: Text('Food'), numeric: true),
            DataColumn(label: Text('Activities'), numeric: true),
            DataColumn(label: Text('Total'), numeric: true),
            DataColumn(label: Text('Advance'), numeric: true),
            DataColumn(label: Text('Online'), numeric: true),
            DataColumn(label: Text('Desk'), numeric: true),
            DataColumn(label: Text('Method')),
            DataColumn(label: Text('Reference')),
            DataColumn(label: Text('Outstanding')),
            DataColumn(label: Text('Invoice')),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(Text(r.guestName)),
                DataCell(Text(r.unitName)),
                DataCell(Text(formatDate(r.arrival))),
                DataCell(Text(formatDate(r.departure))),
                DataCell(Text(formatMoney(r.room))),
                DataCell(Text(formatMoney(r.cleaningFee))),
                DataCell(Text('${formatMoney(r.tax)} (${formatPct(r.taxPct)}%)')),
                DataCell(Text(formatMoney(r.food))),
                DataCell(Text(formatMoney(r.activities))),
                DataCell(Text(formatMoney(r.total))),
                DataCell(Text(formatMoney(r.advancePaid))),
                DataCell(Text(formatMoney(r.balanceOnline))),
                DataCell(Text(formatMoney(r.balanceDesk))),
                DataCell(Text(r.deskMethod?.label ?? '')),
                DataCell(Text(r.deskReference ?? '')),
                DataCell(r.outstanding != 0
                    ? _OutstandingFlag(row: r)
                    : Text(formatMoney(0))),
                DataCell(InvoicePdfButton(
                  reservationId: r.reservationId,
                  style: InvoicePdfButtonStyle.icon,
                )),
              ]),
          ],
        ),
      );
}
