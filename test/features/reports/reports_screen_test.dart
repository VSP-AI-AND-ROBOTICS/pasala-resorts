import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/expense.dart';
import 'package:pasala/data/models/food_sale.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/report.dart';
import 'package:pasala/data/models/slot_type.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/catalog_repository.dart';
import 'package:pasala/data/repositories/report_repository.dart';
import 'package:pasala/features/reports/providers.dart';
import 'package:pasala/features/reports/reports_screen.dart';

/// In-memory stand-in for [ReportRepository], mirroring the
/// `FakeCatalogRepository`/`FakeRateRepository` pattern used elsewhere in
/// this test suite. `dashboard()` is never called from [ReportsScreen].
///
/// [revenueFilters]/[occupancyFilters] record every [ReportFilter] the
/// screen actually asked for, in call order -- this is what lets a test
/// prove the date-range and property controls really do change what gets
/// fetched, rather than just changing what's displayed in the control
/// itself while the underlying query silently stays put.
class FakeReportRepository implements ReportRepository {
  List<RevenueRow> revenueRows = [];
  List<OccupancyRow> occupancyRows = [];
  final List<ReportFilter> revenueFilters = [];
  final List<ReportFilter> occupancyFilters = [];

  @override
  Future<DashboardSummary> dashboard() => throw UnimplementedError();

  @override
  Future<List<RevenueRow>> revenue(DateTime from, DateTime to,
      [String? propertyId]) async {
    revenueFilters.add((from: from, to: to, propertyId: propertyId));
    return revenueRows;
  }

  @override
  Future<List<OccupancyRow>> occupancy(DateTime from, DateTime to,
      [String? propertyId]) async {
    occupancyFilters.add((from: from, to: to, propertyId: propertyId));
    return occupancyRows;
  }

  @override
  Future<List<FoodSalesReportRow>> foodSales(DateTime from, DateTime to,
          [String? propertyId]) async =>
      [];

  @override
  Future<List<ExpensesReportRow>> expenses(DateTime from, DateTime to,
          [String? propertyId]) async =>
      [];
}

/// Only `properties()` is exercised here -- [ReportsScreen] uses it for the
/// property filter dropdown.
class FakeCatalogRepository implements CatalogRepository {
  List<Property> propertiesStore = [];

  @override
  Future<List<Property>> properties() async => propertiesStore;

  @override
  Future<Property> property(String id) => throw UnimplementedError();

  @override
  Future<Unit> unit(String id) => throw UnimplementedError();

  @override
  Future<List<Unit>> units(String propertyId) => throw UnimplementedError();

  @override
  Future<List<SlotType>> slotTypes(String propertyId) =>
      throw UnimplementedError();

  @override
  Future<Property> upsertProperty(Property property, {String? id}) =>
      throw UnimplementedError();

  @override
  Future<Unit> upsertUnit(Unit unit, {String? id}) =>
      throw UnimplementedError();

  @override
  Future<void> updateSettings(String propertyId, Map<String, dynamic> fields) =>
      throw UnimplementedError();
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FakeReportRepository reports,
    FakeCatalogRepository? catalog,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        reportRepositoryProvider.overrideWithValue(reports),
        catalogRepositoryProvider.overrideWithValue(catalog ?? FakeCatalogRepository()),
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
    final catalog = FakeCatalogRepository()
      ..propertiesStore = [
        const Property(
          id: 'p1',
          name: 'Pasala Riverside',
          slug: 'riverside',
          description: null,
          address: null,
          images: [],
          amenities: [],
          checkInTime: '14:00',
          checkOutTime: '11:00',
          isActive: true,
        ),
      ];

    await pump(tester, reports: repo, catalog: catalog);

    expect(find.text('Pasala Riverside'), findsOneWidget);
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

  // Carried forward from Task 6's review: nothing previously proved the
  // date-range and property filters actually change what's *fetched* --
  // only that the controls themselves update. A filter that silently does
  // nothing produces a confidently wrong report, which is the exact failure
  // this whole feature exists to prevent. This drives both real controls
  // (the property dropdown, and the actual Material date-range picker in
  // its keyboard-input mode) and asserts against `FakeReportRepository`'s
  // recorded call history, not just what's on screen.
  testWidgets(
      'the property dropdown and the date range picker both change the '
      'filter the repository is actually queried with', (tester) async {
    final repo = FakeReportRepository();
    final catalog = FakeCatalogRepository()
      ..propertiesStore = [
        const Property(
          id: 'p1',
          name: 'Prop One',
          slug: 'p1',
          description: null,
          address: null,
          images: [],
          amenities: [],
          checkInTime: '14:00',
          checkOutTime: '11:00',
          isActive: true,
        ),
        const Property(
          id: 'p2',
          name: 'Prop Two',
          slug: 'p2',
          description: null,
          address: null,
          images: [],
          amenities: [],
          checkInTime: '14:00',
          checkOutTime: '11:00',
          isActive: true,
        ),
      ];

    await pump(tester, reports: repo, catalog: catalog);

    final initial = repo.revenueFilters.last;
    expect(initial.propertyId, isNull,
        reason: 'starts on "All properties"');

    // === the property dropdown ============================================
    await tester.tap(find.byKey(const Key('property-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prop Two'));
    await tester.pumpAndSettle();

    final afterProperty = repo.revenueFilters.last;
    expect(afterProperty.propertyId, 'p2',
        reason: 'selecting a property in the dropdown must re-query the '
            'repository scoped to that property, not just relabel the '
            'button');
    expect(afterProperty.propertyId, isNot(initial.propertyId));

    // === the date range picker =============================================
    await tester.tap(find.byKey(const Key('change-dates-button')));
    await tester.pumpAndSettle();
    // The default calendar grid is unwieldy to drive directly in a test;
    // Material's date-range picker offers an equivalent keyboard-input mode
    // via this toggle, which is exercised here instead.
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '09/01/2026');
    await tester.enterText(fields.at(1), '09/30/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final afterRange = repo.revenueFilters.last;
    expect(afterRange.from, isNot(afterProperty.from));
    expect(afterRange.to, isNot(afterProperty.to));
    expect(afterRange.from, DateTime(2026, 9, 1));
    expect(afterRange.to, DateTime(2026, 9, 30));
    // The property selected earlier must survive the date-range change --
    // proof the two filters compose rather than one silently resetting the
    // other.
    expect(afterRange.propertyId, 'p2');
  });
}
