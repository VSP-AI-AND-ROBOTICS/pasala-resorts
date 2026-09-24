import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import 'csv_download.dart';
import 'csv_export.dart';
import 'providers.dart';

DateTimeRange _currentMonth() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0);
  return DateTimeRange(start: start, end: end);
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `/admin/reports` -- revenue and occupancy over a chosen date range and
/// property, exportable as CSV. PDF export is explicitly deferred (see
/// `csv_export.dart`); there is no disabled/greyed-out PDF button standing
/// in for it, because a button that exists only to fail is worse than no
/// button.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTimeRange _range = _currentMonth();
  ReportKind _kind = ReportKind.revenue;

  ReportFilter _filterFor(String propertyId) =>
      (from: _range.start, to: _range.end, propertyId: propertyId);

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Builds the CSV from whatever the relevant provider has already
  /// resolved (`.value`, per Riverpod 3.3.2 -- never `valueOrNull`) rather
  /// than re-fetching, and hands it to [downloadCsv]. A `null` value means
  /// the table has not finished loading yet, which the export button
  /// cannot outrace -- it is right next to a table that is either showing
  /// data or an [EmptyState]/[LoadingState] already.
  void _exportCsv(String propertyId, String resortName) {
    final List<List<String>> rows;
    final String kindLabel;
    final filter = _filterFor(propertyId);

    if (_kind == ReportKind.revenue) {
      final data = ref.read(revenueReportProvider(filter)).value;
      if (data == null) {
        _showMessage('Still loading -- try again in a moment.');
        return;
      }
      kindLabel = 'revenue';
      rows = [
        ['Day', 'Property', 'Bookings', 'Gross', 'Refunded', 'Net'],
        for (final r in data)
          [
            formatDate(r.day),
            resortName,
            '${r.bookings}',
            formatInr(r.gross),
            formatInr(r.refunded),
            formatInr(r.net),
          ],
      ];
    } else {
      final data = ref.read(occupancyReportProvider(filter)).value;
      if (data == null) {
        _showMessage('Still loading -- try again in a moment.');
        return;
      }
      kindLabel = 'occupancy';
      rows = [
        ['Unit', 'Nights available', 'Nights booked', 'Occupancy %'],
        for (final r in data)
          [
            r.unitName,
            '${r.nightsAvailable}',
            '${r.nightsBooked}',
            '${r.occupancyPct}',
          ],
      ];
    }

    final csv = toCsv(rows);
    final filename =
        'pasala-$kindLabel-${_isoDate(_range.start)}-${_isoDate(_range.end)}.csv';
    final delivered = downloadCsv(filename, csv);
    _showMessage(
      delivered ? 'CSV exported.' : "CSV export isn't available on this platform yet.",
    );
  }

  @override
  Widget build(BuildContext context) {
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final resort = ref.watch(currentResortProvider)!;
    final filter = _filterFor(resort.propertyId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            key: const Key('export-csv-button'),
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportCsv(resort.propertyId, resort.resortName),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: OutlinedButton.icon(
              key: const Key('change-dates-button'),
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                '${formatDate(_range.start)} – ${formatDate(_range.end)}',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: SegmentedButton<ReportKind>(
              segments: const [
                ButtonSegment(
                    value: ReportKind.revenue, label: Text('Revenue')),
                ButtonSegment(
                    value: ReportKind.occupancy, label: Text('Occupancy')),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.first),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Expanded(
            child: _kind == ReportKind.revenue
                ? _RevenueTable(filter: filter, resortName: resort.resortName)
                : _OccupancyTable(filter: filter),
          ),
        ],
      ),
    );
  }
}

class _RevenueTable extends ConsumerWidget {
  const _RevenueTable({required this.filter, required this.resortName});

  final ReportFilter filter;
  final String resortName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(revenueReportProvider(filter));

    return AsyncView(
      value: rows,
      onRetry: () => ref.invalidate(revenueReportProvider(filter)),
      empty: () => const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'No revenue in this period',
        message: 'Try a wider date range.',
      ),
      data: (list) => SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Day')),
              DataColumn(label: Text('Property')),
              DataColumn(label: Text('Bookings'), numeric: true),
              DataColumn(label: Text('Gross'), numeric: true),
              DataColumn(label: Text('Refunded'), numeric: true),
              DataColumn(label: Text('Net'), numeric: true),
            ],
            rows: [
              for (final r in list)
                DataRow(cells: [
                  DataCell(Text(formatDate(r.day))),
                  DataCell(Text(resortName)),
                  DataCell(Text('${r.bookings}')),
                  DataCell(Text(formatInr(r.gross))),
                  DataCell(Text(formatInr(r.refunded))),
                  DataCell(Text(formatInr(r.net))),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _OccupancyTable extends ConsumerWidget {
  const _OccupancyTable({required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(occupancyReportProvider(filter));

    return AsyncView(
      value: rows,
      onRetry: () => ref.invalidate(occupancyReportProvider(filter)),
      empty: () => const EmptyState(
        icon: Icons.pie_chart_outline,
        title: 'No occupancy data in this period',
        message: 'Try a wider date range.',
      ),
      data: (list) => SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Unit')),
              DataColumn(label: Text('Nights available'), numeric: true),
              DataColumn(label: Text('Nights booked'), numeric: true),
              DataColumn(label: Text('Occupancy %'), numeric: true),
            ],
            rows: [
              for (final r in list)
                DataRow(cells: [
                  DataCell(Text(r.unitName)),
                  DataCell(Text('${r.nightsAvailable}')),
                  DataCell(Text('${r.nightsBooked}')),
                  DataCell(Text('${r.occupancyPct}')),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
