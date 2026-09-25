import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/pdf/pdf_delivery.dart';
import '../../core/pdf/pdf_exporter.dart';
import '../../core/pdf/report_pdf.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/finance_repository.dart';
import '../finance/finance_csv.dart';
import '../finance/finance_pdf.dart';
import '../finance/providers.dart';
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

enum _OwnerReportKind {
  revenue,
  occupancy,
  foodSales,
  expenses,
  collections,
  ledger,
  settlements,
}

/// `/owner/reports` -- the consolidated export center: Revenue, Occupancy,
/// Food & Activity Sales, Expenses, and the three finance reports
/// (Collections, Ledger, Settlements, from 0048_finance_ledger.sql), all
/// exportable as CSV through `csv_export.dart` and [csvDownloaderProvider],
/// and the three finance reports as PDF too (`finance_pdf.dart`).
/// Deliberately separate from `ReportsScreen` (which the Owner hub's
/// Revenue/Occupancy tiles link to directly for a live day-by-day view) and
/// from `/finance` (which shows the finance reports on screen) -- this
/// screen's job is bulk export across every report this app has.
class OwnerReportsScreen extends ConsumerStatefulWidget {
  const OwnerReportsScreen({super.key});

  @override
  ConsumerState<OwnerReportsScreen> createState() => _OwnerReportsScreenState();
}

class _OwnerReportsScreenState extends ConsumerState<OwnerReportsScreen> {
  DateTimeRange _range = _currentMonth();
  bool _pdfBusy = false;

  ReportFilter _reportFilter(String propertyId) =>
      (from: _range.start, to: _range.end, propertyId: propertyId);
  FoodSalesReportFilter _foodFilter(String propertyId) =>
      (from: _range.start, to: _range.end, propertyId: propertyId);
  ExpensesReportFilter _expensesFilter(String propertyId) =>
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _deliver(String filename, List<List<String>> rows) {
    final delivered = ref.read(csvDownloaderProvider)(filename, toCsv(rows));
    _showMessage(
      delivered ? 'CSV exported.' : "CSV export isn't available on this platform yet.",
    );
  }

  Future<void> _export(_OwnerReportKind kind, String propertyId, String resortName) async {
    if (kind == _OwnerReportKind.collections ||
        kind == _OwnerReportKind.ledger ||
        kind == _OwnerReportKind.settlements) {
      return _exportFinance(kind, propertyId);
    }

    final List<List<String>> rows;
    final String label;

    switch (kind) {
      case _OwnerReportKind.revenue:
        final data =
            await ref.read(revenueReportProvider(_reportFilter(propertyId)).future);
        label = 'revenue';
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
      case _OwnerReportKind.occupancy:
        final data =
            await ref.read(occupancyReportProvider(_reportFilter(propertyId)).future);
        label = 'occupancy';
        rows = [
          ['Unit', 'Nights available', 'Nights booked', 'Occupancy %'],
          for (final r in data)
            [r.unitName, '${r.nightsAvailable}', '${r.nightsBooked}', '${r.occupancyPct}'],
        ];
      case _OwnerReportKind.foodSales:
        final data =
            await ref.read(foodSalesReportProvider(_foodFilter(propertyId)).future);
        label = 'food-activity-sales';
        rows = [
          ['Day', 'Category', 'Items sold', 'Gross'],
          for (final r in data)
            [formatDate(r.day), r.category.name, '${r.itemsSold}', formatInr(r.gross)],
        ];
      case _OwnerReportKind.expenses:
        final data =
            await ref.read(expensesReportProvider(_expensesFilter(propertyId)).future);
        label = 'expenses';
        rows = [
          ['Day', 'Category', 'Total'],
          for (final r in data) [formatDate(r.day), r.category, formatInr(r.total)],
        ];
      case _OwnerReportKind.collections:
      case _OwnerReportKind.ledger:
      case _OwnerReportKind.settlements:
        return;
    }

    if (!mounted) return;
    _deliver('pasala-$label-${_isoDate(_range.start)}-${_isoDate(_range.end)}.csv', rows);
  }

  /// The finance reports read [financeSourceProvider] directly -- a fresh
  /// query per export -- and take the resort's name, slug and GSTIN from
  /// `finance_summary` for the header and file name.
  Future<void> _exportFinance(_OwnerReportKind kind, String propertyId) async {
    final source = ref.read(financeSourceProvider);
    final from = _range.start;
    final to = _range.end;
    try {
      final resort = (await source.summary(propertyId)).resort;
      final (String report, List<List<String>> rows) = switch (kind) {
        _OwnerReportKind.collections => (
            'collections',
            collectionsCsv(resort, from, to, await source.collections(from, to, propertyId)),
          ),
        _OwnerReportKind.ledger => (
            'ledger',
            ledgerCsv(resort, from, to, await source.ledger(from, to, propertyId)),
          ),
        _ => (
            'settlements',
            settlementsCsv(resort, from, to, await source.settlements(from, to, propertyId)),
          ),
      };
      if (!mounted) return;
      _deliver(financeCsvFileName(resort.slug, report, from, to), rows);
    } on BookingFailure catch (e) {
      if (mounted) _showMessage(FailureView.messageFor(e));
    }
  }

  /// A finance report as PDF: a fresh query per export, like
  /// [_exportFinance]; one at a time.
  Future<void> _exportFinancePdf(_OwnerReportKind kind, String propertyId) async {
    if (_pdfBusy) return;
    final source = ref.read(financeSourceProvider);
    final exporter = ref.read(pdfExporterProvider);
    final deliver = ref.read(pdfDelivererProvider);
    final from = _range.start;
    final to = _range.end;
    setState(() => _pdfBusy = true);
    try {
      final resort = (await source.summary(propertyId)).resort;
      final ReportPdf report = switch (kind) {
        _OwnerReportKind.collections => collectionsPdf(
            resort, from, to, await source.collections(from, to, propertyId)),
        _OwnerReportKind.ledger =>
          ledgerPdf(resort, from, to, await source.ledger(from, to, propertyId)),
        _ => settlementsPdf(
            resort, from, to, await source.settlements(from, to, propertyId)),
      };
      final delivered = await deliver(report.fileName, await exporter.report(report));
      if (mounted) {
        _showMessage(delivered
            ? 'PDF exported.'
            : "PDF export isn't available on this platform yet.");
      }
    } on BookingFailure catch (e) {
      if (mounted) _showMessage(FailureView.messageFor(e));
    } catch (_) {
      if (mounted) _showMessage("Couldn't create the PDF. Try again.");
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final resort = ref.watch(currentResortProvider)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    void export(_OwnerReportKind kind) =>
        _export(kind, resort.propertyId, resort.resortName);
    void exportPdf(_OwnerReportKind kind) => _exportFinancePdf(kind, resort.propertyId);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Text('DATE RANGE',
              style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  '${formatDate(_range.start)} – ${formatDate(_range.end)}',
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text('EXPORT',
              style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: Spacing.sm),
          _ReportTile(
            icon: Icons.trending_up_outlined,
            title: 'Revenue',
            subtitle: 'Bookings, gross and net revenue by day',
            color: scheme.primary,
            onExport: () => export(_OwnerReportKind.revenue),
          ),
          _ReportTile(
            icon: Icons.pie_chart_outline,
            title: 'Occupancy',
            subtitle: 'Nights booked vs. available, by unit',
            color: scheme.tertiary,
            onExport: () => export(_OwnerReportKind.occupancy),
          ),
          _ReportTile(
            icon: Icons.restaurant_outlined,
            title: 'Food & activity sales',
            subtitle: 'Items sold and gross, by day and category',
            color: scheme.primary,
            onExport: () => export(_OwnerReportKind.foodSales),
          ),
          _ReportTile(
            icon: Icons.receipt_long_outlined,
            title: 'Expenses',
            subtitle: 'Totals by day and category',
            color: scheme.onSurfaceVariant,
            onExport: () => export(_OwnerReportKind.expenses),
          ),
          _ReportTile(
            icon: Icons.payments_outlined,
            title: 'Collections',
            subtitle: 'Money in and out by day, online and desk, by method',
            color: scheme.primary,
            onExport: () => export(_OwnerReportKind.collections),
            onExportPdf: () => exportPdf(_OwnerReportKind.collections),
            pdfBusy: _pdfBusy,
          ),
          _ReportTile(
            icon: Icons.account_balance_outlined,
            title: 'Ledger',
            subtitle: 'Revenue by category with room tax',
            color: scheme.tertiary,
            onExport: () => export(_OwnerReportKind.ledger),
            onExportPdf: () => exportPdf(_OwnerReportKind.ledger),
            pdfBusy: _pdfBusy,
          ),
          _ReportTile(
            icon: Icons.fact_check_outlined,
            title: 'Settlements',
            subtitle: 'Checked-out bookings and how they were paid',
            color: scheme.onSurfaceVariant,
            onExport: () => export(_OwnerReportKind.settlements),
            onExportPdf: () => exportPdf(_OwnerReportKind.settlements),
            pdfBusy: _pdfBusy,
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
    this.onExportPdf,
    this.pdfBusy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onExport;

  /// Shows an Export PDF button next to CSV when set.
  final VoidCallback? onExportPdf;
  final bool pdfBusy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final csv = IconButton(
      tooltip: 'Export CSV',
      icon: const Icon(Icons.download_outlined),
      onPressed: onExport,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
        trailing: onExportPdf == null
            ? csv
            : Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Export PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: pdfBusy ? null : onExportPdf,
                ),
                csv,
              ]),
      ),
    );
  }
}
