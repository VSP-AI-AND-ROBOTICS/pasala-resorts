import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/property.dart';
import '../browse/providers.dart';
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
  String? _propertyId;
  ReportKind _kind = ReportKind.revenue;

  ReportFilter get _filter =>
      (from: _range.start, to: _range.end, propertyId: _propertyId);

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
  void _exportCsv(Map<String, String> propertyName) {
    final List<List<String>> rows;
    final String kindLabel;

    if (_kind == ReportKind.revenue) {
      final data = ref.read(revenueReportProvider(_filter)).value;
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
            propertyName[r.propertyId] ?? r.propertyId,
            '${r.bookings}',
            formatInr(r.gross),
            formatInr(r.refunded),
            formatInr(r.net),
          ],
      ];
    } else {
      final data = ref.read(occupancyReportProvider(_filter)).value;
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
    final properties =
        ref.watch(propertiesProvider).value ?? const <Property>[];
    final propertyName = {for (final p in properties) p.id: p.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            key: const Key('export-csv-button'),
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportCsv(propertyName),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('change-dates-button'),
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    '${formatDate(_range.start)} – ${formatDate(_range.end)}',
                  ),
                ),
                DropdownButton<String?>(
                  key: const Key('property-filter'),
                  value: _propertyId,
                  hint: const Text('All properties'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All properties')),
                    for (final p in properties)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (value) => setState(() => _propertyId = value),
                ),
              ],
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
                ? _RevenueTable(filter: _filter, propertyName: propertyName)
                : _OccupancyTable(filter: _filter),
          ),
        ],
      ),
    );
  }
}

class _RevenueTable extends ConsumerWidget {
  const _RevenueTable({required this.filter, required this.propertyName});

  final ReportFilter filter;
  final Map<String, String> propertyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(revenueReportProvider(filter));

    return AsyncView(
      value: rows,
      onRetry: () => ref.invalidate(revenueReportProvider(filter)),
      empty: () => const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'No revenue in this period',
        message: 'Try a wider date range or a different property.',
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
                  DataCell(Text(propertyName[r.propertyId] ?? r.propertyId)),
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
        message: 'Try a wider date range or a different property.',
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
