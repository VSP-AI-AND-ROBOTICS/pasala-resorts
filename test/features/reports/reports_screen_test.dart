import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/expense.dart';
import 'package:pasala/data/models/food_sale.dart';
import 'package:pasala/data/models/report.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/report_repository.dart';
import 'package:pasala/features/reports/providers.dart';
import 'package:pasala/features/reports/reports_screen.dart';

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

/// In-memory stand-in for [ReportRepository], mirroring the
/// `FakeCatalogRepository`/`FakeRateRepository` pattern used elsewhere in
/// this test suite. `dashboard()` is never called from [ReportsScreen].
///
/// [revenueFilters]/[occupancyFilters] record every [ReportFilter] the
/// screen actually asked for, in call order -- this is what lets a test
/// prove the date-range control really does change what gets fetched,
/// rather than just changing what's displayed in the control itself while
/// the underlying query silently stays put.
class FakeReportRepository implements ReportRepository {
  List<RevenueRow> revenueRows = [];
  List<OccupancyRow> occupancyRows = [];
  final List<ReportFilter> revenueFilters = [];
  final List<ReportFilter> occupancyFilters = [];

  @override
  Future<DashboardSummary> dashboard(String propertyId) => throw UnimplementedError();

  @override
  Future<List<RevenueRow>> revenue(
      DateTime from, DateTime to, String propertyId) async {
    revenueFilters.add((from: from, to: to, propertyId: propertyId));
    return revenueRows;
  }

  @override
  Future<List<OccupancyRow>> occupancy(
      DateTime from, DateTime to, String propertyId) async {
    occupancyFilters.add((from: from, to: to, propertyId: propertyId));
    return occupancyRows;
  }

  @override
  Future<List<FoodSalesReportRow>> foodSales(
          DateTime from, DateTime to, String propertyId) async =>
      [];

  @override
  Future<List<ExpensesReportRow>> expenses(
          DateTime from, DateTime to, String propertyId) async =>
      [];
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FakeReportRepository reports,
    ResortMembership resort = _resort,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        reportRepositoryProvider.overrideWithValue(reports),
        currentResortProvider.overrideWith(() => _FixedResort(resort)),
      ],
      child: const MaterialApp(home: ReportsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'an empty period shows an EmptyState, not an error and not a table '
      'of zeros', (tester) async {
    await pump(tester, reports: FakeReportRepository());

    expect(find.text('No revenue in this period'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
  });

  testWidgets('renders revenue rows with money via formatInr', (tester) async {
    final repo = FakeReportRepository()
      ..revenueRows = [
        RevenueRow(
          day: DateTime(2026, 8, 1),
          propertyId: 'p1',
          bookings: 2,
          gross: 20000,
          refunded: 2000,
          net: 18000,
        ),
      ];

    await pump(tester, reports: repo);

    expect(find.text('Pasala'), findsOneWidget);
    expect(find.text('₹20,000'), findsOneWidget);
  });

  testWidgets('switching to Occupancy shows occupancy columns, not revenue '
      'ones', (tester) async {
    final repo = FakeReportRepository()
      ..occupancyRows = [
        const OccupancyRow(
          unitId: 'u1',
          unitName: 'Garden Room',
          nightsAvailable: 30,
          nightsBooked: 6,
          occupancyPct: 20.0,
        ),
      ];

    await pump(tester, reports: repo);

    await tester.tap(find.text('Occupancy'));
    await tester.pumpAndSettle();

    expect(find.text('Garden Room'), findsOneWidget);
    expect(find.text('Nights booked'), findsOneWidget);
    expect(find.text('Gross'), findsNothing);
  });

  testWidgets(
      'exporting on a platform with no download primitive says so, rather '
      'than silently doing nothing', (tester) async {
    final repo = FakeReportRepository()
      ..revenueRows = [
        RevenueRow(
          day: DateTime(2026, 8, 1),
          propertyId: 'p1',
          bookings: 1,
          gross: 5000,
          refunded: 0,
          net: 5000,
        ),
      ];

    await pump(tester, reports: repo);

    await tester.tap(find.byKey(const Key('export-csv-button')));
    await tester.pump();

    expect(
      find.text("CSV export isn't available on this platform yet."),
      findsOneWidget,
    );
  });

  // Review Focus #1: the current resort's id, not some hardcoded or global
  // property, must reach the repository -- and switching resorts must
  // query the new resort, not the old one.
  testWidgets('queries the report scoped to the current resort', (tester) async {
    const otherResort = ResortMembership(
        propertyId: 'p2', resortName: 'Other Resort', role: ResortRole.admin);
    final repo = FakeReportRepository();

    await pump(tester, reports: repo, resort: otherResort);

    expect(repo.revenueFilters, isNotEmpty);
    expect(repo.revenueFilters.every((f) => f.propertyId == 'p2'), isTrue);
  });

  // Carried forward from Task 6's review: nothing previously proved the
  // date-range filter actually changes what's *fetched* -- only that the
  // control itself updates. A filter that silently does nothing produces a
  // confidently wrong report, which is the exact failure this whole
  // feature exists to prevent. This drives the actual Material
  // date-range picker in its keyboard-input mode and asserts against
  // `FakeReportRepository`'s recorded call history, not just what's on
  // screen.
  testWidgets(
      'the date range picker changes the filter the repository is '
      'actually queried with', (tester) async {
    final repo = FakeReportRepository();

    await pump(tester, reports: repo);

    final initial = repo.revenueFilters.last;
    expect(initial.propertyId, 'p1');

    await tester.tap(find.byKey(const Key('change-dates-button')));
    await tester.pumpAndSettle();
    // The default calendar grid is unwieldy to drive directly in a test;
    // Material's date-range picker offers an equivalent keyboard-input mode
    // via this toggle, which is exercised here instead.
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();

    // The screen defaults to the current month, so a hardcoded range
    // would equal that default whenever the suite runs in the same month.
    // Pick the month two before today instead: always distinct from the
    // default, always inside the picker's 2020-2100 bounds.
    final now = DateTime.now();
    final pickedFrom = DateTime(now.year, now.month - 2, 1);
    final pickedTo = DateTime(now.year, now.month - 1, 0);
    String mdy(DateTime d) => '${d.month.toString().padLeft(2, '0')}/'
        '${d.day.toString().padLeft(2, '0')}/${d.year}';

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), mdy(pickedFrom));
    await tester.enterText(fields.at(1), mdy(pickedTo));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final afterRange = repo.revenueFilters.last;
    expect(afterRange.from, isNot(initial.from));
    expect(afterRange.to, isNot(initial.to));
    expect(afterRange.from, pickedFrom);
    expect(afterRange.to, pickedTo);
    expect(afterRange.propertyId, 'p1');
  });
}
