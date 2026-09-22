import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/property.dart';
import '../browse/providers.dart';
import '../reports/csv_download.dart';
import '../reports/csv_export.dart';
import '../reports/providers.dart';
import 'providers.dart';

DateTimeRange _currentMonth() {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 0),
  );
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

enum _OwnerReportKind { revenue, occupancy, foodSales, expenses }

/// `/owner/reports` -- the consolidated export center: Revenue, Occupancy,
/// Food & Activity Sales, and Expenses, all exportable as CSV, reusing
/// `csv_export.dart`/`csv_download.dart` exactly as `ReportsScreen` does.
/// Deliberately separate from `ReportsScreen` (which the Owner hub's
/// Revenue/Occupancy tiles link to directly for a live day-by-day view) --
/// this screen's job is bulk export across every report this app has,
/// including the two new ledgers `ReportsScreen` doesn't know about.
class OwnerReportsScreen extends ConsumerStatefulWidget {
  const OwnerReportsScreen({super.key});

  @override
  ConsumerState<OwnerReportsScreen> createState() => _OwnerReportsScreenState();
}

class _OwnerReportsScreenState extends ConsumerState<OwnerReportsScreen> {
  DateTimeRange _range = _currentMonth();
  String? _propertyId;

  ReportFilter get _reportFilter =>
      (from: _range.start, to: _range.end, propertyId: _propertyId);
  FoodSalesReportFilter get _foodFilter =>
      (from: _range.start, to: _range.end, propertyId: _propertyId);
  ExpensesReportFilter get _expensesFilter =>
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export(_OwnerReportKind kind, Map<String, String> propertyName) async {
    final List<List<String>> rows;
    final String label;

    switch (kind) {
      case _OwnerReportKind.revenue:
        final data = await ref.read(revenueReportProvider(_reportFilter).future);
        label = 'revenue';
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
      case _OwnerReportKind.occupancy:
        final data = await ref.read(occupancyReportProvider(_reportFilter).future);
        label = 'occupancy';
        rows = [
          ['Unit', 'Nights available', 'Nights booked', 'Occupancy %'],
          for (final r in data)
            [r.unitName, '${r.nightsAvailable}', '${r.nightsBooked}', '${r.occupancyPct}'],
        ];
      case _OwnerReportKind.foodSales:
        final data = await ref.read(foodSalesReportProvider(_foodFilter).future);
        label = 'food-activity-sales';
        rows = [
          ['Day', 'Category', 'Items sold', 'Gross'],
          for (final r in data)
            [formatDate(r.day), r.category.name, '${r.itemsSold}', formatInr(r.gross)],
        ];
      case _OwnerReportKind.expenses:
        final data = await ref.read(expensesReportProvider(_expensesFilter).future);
        label = 'expenses';
        rows = [
          ['Day', 'Category', 'Total'],
          for (final r in data) [formatDate(r.day), r.category, formatInr(r.total)],
        ];
    }

    if (!mounted) return;
    final csv = toCsv(rows);
    final filename = 'pasala-$label-${_isoDate(_range.start)}-${_isoDate(_range.end)}.csv';
    final delivered = downloadCsv(filename, csv);
    _showMessage(
      delivered ? 'CSV exported.' : "CSV export isn't available on this platform yet.",
    );
  }

  @override
  Widget build(BuildContext context) {
    final properties = ref.watch(propertiesProvider).value ?? const <Property>[];
    final propertyName = {for (final p in properties) p.id: p.name};
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Text('DATE RANGE & PROPERTY',
              style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Wrap(
                spacing: Spacing.md,
                runSpacing: Spacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      '${formatDate(_range.start)} – ${formatDate(_range.end)}',
                    ),
                  ),
                  DropdownButton<String?>(
                    value: _propertyId,
                    hint: const Text('All properties'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All properties')),
                      for (final p in properties)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (value) => setState(() => _propertyId = value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text('EXPORT AS CSV',
              style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: Spacing.sm),
          _ReportTile(
            icon: Icons.trending_up_outlined,
            title: 'Revenue',
            subtitle: 'Bookings, gross and net revenue by day and property',
            color: scheme.primary,
            onExport: () => _export(_OwnerReportKind.revenue, propertyName),
          ),
          _ReportTile(
            icon: Icons.pie_chart_outline,
            title: 'Occupancy',
            subtitle: 'Nights booked vs. available, by unit',
            color: scheme.tertiary,
            onExport: () => _export(_OwnerReportKind.occupancy, propertyName),
          ),
          _ReportTile(
            icon: Icons.restaurant_outlined,
            title: 'Food & activity sales',
            subtitle: 'Items sold and gross, by day and category',
            color: scheme.primary,
            onExport: () => _export(_OwnerReportKind.foodSales, propertyName),
          ),
          _ReportTile(
            icon: Icons.receipt_long_outlined,
            title: 'Expenses',
            subtitle: 'Totals by day and category',
            color: scheme.onSurfaceVariant,
            onExport: () => _export(_OwnerReportKind.expenses, propertyName),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onExport,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
        trailing: IconButton(
          tooltip: 'Export CSV',
          icon: const Icon(Icons.download_outlined),
          onPressed: onExport,
        ),
      ),
    );
  }
}
