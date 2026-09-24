import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/finance.dart';
import '../reports/csv_export.dart';
import '../reports/providers.dart' show ReportFilter;
import 'finance_collections_tab.dart';
import 'finance_csv.dart';
import 'finance_ledger_tab.dart';
import 'finance_settlements_tab.dart';
import 'finance_today_tab.dart';
import 'providers.dart';

DateTimeRange _currentMonth() {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 0),
  );
}

const _loading = 'Still loading -- try again in a moment.';
const _failed = "This report didn't load, so there is nothing to export.";

/// `/finance` -- the current resort's money, for owners, admins and
/// accountants (the router refuses everyone else; the report functions in
/// 0048_finance_ledger.sql refuse them too). Today, Collections (cash
/// basis), Ledger (accrual basis, with room tax) and Settlements, each
/// with pull-to-refresh, and an Export CSV action for the tab on screen.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key, this.initialRange});

  /// The range the dated tabs open on; this month when null.
  final DateTimeRange? initialRange;

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SingleTickerProviderStateMixin {
  /// One entry per tab, in order: its label and the report name used in
  /// the CSV file name.
  static const _tabs = [
    (label: 'Today', report: 'today'),
    (label: 'Collections', report: 'collections'),
    (label: 'Ledger', report: 'ledger'),
    (label: 'Settlements', report: 'settlements'),
  ];

  late final TabController _tabController =
      TabController(length: _tabs.length, vsync: this)..addListener(_onTabChanged);
  late DateTimeRange _range = widget.initialRange ?? _currentMonth();

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The CSV rows of [tab], built from what its provider already holds
  /// (never a second fetch): loading or failed while the tab is.
  AsyncValue<List<List<String>>> _rowsFor(
          int tab, FinanceSummary summary, ReportFilter filter) =>
      switch (tab) {
        0 => AsyncData(todayCsv(summary)),
        1 => ref.read(collectionsProvider(filter)).whenData(
            (rows) => collectionsCsv(summary.resort, filter.from, filter.to, rows)),
        2 => ref.read(ledgerProvider(filter)).whenData(
            (rows) => ledgerCsv(summary.resort, filter.from, filter.to, rows)),
        3 => ref.read(settlementsProvider(filter)).whenData(
            (rows) => settlementsCsv(summary.resort, filter.from, filter.to, rows)),
        _ => throw StateError('Finance has no tab $tab'),
      };

  /// Exports the tab on screen. The resort's name, slug and GSTIN come from
  /// the summary, so nothing is written until both it and the tab's report
  /// have loaded (Review Focus 5).
  void _export(String propertyId) {
    final summaryAsync = ref.read(financeSummaryProvider(propertyId));
    final summary = summaryAsync.value;
    if (summary == null) {
      _show(summaryAsync.hasError ? _failed : _loading);
      return;
    }
    final tab = _tabController.index;
    final filter = _filterFor(propertyId);
    final rowsAsync = _rowsFor(tab, summary, filter);
    final rows = rowsAsync.value;
    if (rows == null) {
      _show(rowsAsync.hasError ? _failed : _loading);
      return;
    }
    final today = summary.resort.today;
    final (from, to) = tab == 0 ? (today, today) : (filter.from, filter.to);
    final filename =
        financeCsvFileName(summary.resort.slug, _tabs[tab].report, from, to);
    final delivered = ref.read(csvDownloaderProvider)(filename, toCsv(rows));
    _show(delivered ? 'CSV exported.' : "CSV export isn't available on this platform yet.");
  }

  @override
  Widget build(BuildContext context) {
    final resort = ref.watch(currentResortProvider);
    if (resort == null) {
      // Only for the moment after sign-out, before the redirect fires.
      return const Scaffold(body: SizedBox.shrink());
    }
    final propertyId = resort.propertyId;
    final filter = _filterFor(propertyId);
    // Keeps the export header (name, slug, GSTIN) loaded on every tab.
    ref.watch(financeSummaryProvider(propertyId));
    final onToday = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          IconButton(
            key: const Key('finance-export'),
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _export(propertyId),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [for (final t in _tabs) Tab(text: t.label)],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!onToday)
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('finance-range'),
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text('${formatDate(_range.start)} – ${formatDate(_range.end)}'),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                FinanceTodayTab(propertyId: propertyId),
                FinanceCollectionsTab(filter: filter),
                FinanceLedgerTab(filter: filter),
                FinanceSettlementsTab(filter: filter),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
