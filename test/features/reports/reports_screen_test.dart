import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/report.dart';
import 'package:pasala/data/models/slot_type.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/data/repositories/catalog_repository.dart';
import 'package:pasala/data/repositories/report_repository.dart';
import 'package:pasala/features/reports/reports_screen.dart';

/// In-memory stand-in for [ReportRepository], mirroring the
/// `FakeCatalogRepository`/`FakeRateRepository` pattern used elsewhere in
/// this test suite. `dashboard()` is never called from [ReportsScreen].
class FakeReportRepository implements ReportRepository {
  List<RevenueRow> revenueRows = [];
  List<OccupancyRow> occupancyRows = [];

  @override
  Future<DashboardSummary> dashboard() => throw UnimplementedError();

  @override
  Future<List<RevenueRow>> revenue(DateTime from, DateTime to,
          [String? propertyId]) async =>
      revenueRows;

  @override
  Future<List<OccupancyRow>> occupancy(DateTime from, DateTime to,
          [String? propertyId]) async =>
      occupancyRows;
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
}
