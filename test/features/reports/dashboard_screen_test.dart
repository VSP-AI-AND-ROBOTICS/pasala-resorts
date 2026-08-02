import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/report.dart';
import 'package:pasala/data/repositories/report_repository.dart';
import 'package:pasala/features/reports/dashboard_screen.dart';

/// In-memory stand-in for [ReportRepository], mirroring the
/// `FakeCatalogRepository`/`FakeRateRepository` pattern used elsewhere in
/// this test suite. Only `dashboard()` is exercised by [DashboardScreen];
/// `revenue`/`occupancy` are never called from here.
class FakeReportRepository implements ReportRepository {
  DashboardSummary? summary;
  BookingFailure? dashboardFailure;

  @override
  Future<DashboardSummary> dashboard() async {
    final failure = dashboardFailure;
    if (failure != null) throw failure;
    return summary!;
  }

  @override
  Future<List<RevenueRow>> revenue(DateTime from, DateTime to,
          [String? propertyId]) async =>
      [];

  @override
  Future<List<OccupancyRow>> occupancy(DateTime from, DateTime to,
          [String? propertyId]) async =>
      [];
}

void main() {
  testWidgets(
      'renders every stat card with its label, formatted figure, and '
      'caption -- money via formatInr, nothing recomputed in Dart',
      (tester) async {
    final repo = FakeReportRepository()
      ..summary = const DashboardSummary(
        todayRevenue: 11500,
        monthRevenue: 234500,
        occupancyPct: 62.5,
        upcomingArrivals: 3,
        cancellationsThisMonth: 1,
        activeHolds: 2,
      );

    await tester.pumpWidget(ProviderScope(
      overrides: [reportRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Revenue today'), findsOneWidget);
    expect(find.text('₹11,500'), findsOneWidget);
    expect(find.text('Revenue this month'), findsOneWidget);
    expect(find.text('₹2,34,500'), findsOneWidget);
    expect(find.text('Occupancy'), findsOneWidget);
    expect(find.text('62.5%'), findsOneWidget);
    expect(find.text('Upcoming arrivals'), findsOneWidget);
    expect(find.text('Cancellations'), findsOneWidget);
    expect(find.text('Active holds'), findsOneWidget);
  });

  testWidgets('a failure never leaks raw server text, and Retry re-fetches',
      (tester) async {
    final repo = FakeReportRepository()..dashboardFailure = const NotPermitted();

    await tester.pumpWidget(ProviderScope(
      overrides: [reportRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('You do not have access to do that.'), findsOneWidget);
    expect(find.text('Revenue today'), findsNothing);

    repo.dashboardFailure = null;
    repo.summary = const DashboardSummary(
      todayRevenue: 5000,
      monthRevenue: 15000,
      occupancyPct: 0,
      upcomingArrivals: 0,
      cancellationsThisMonth: 0,
      activeHolds: 0,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Revenue today'), findsOneWidget);
    expect(find.text('₹5,000'), findsOneWidget);
    expect(find.text('₹15,000'), findsOneWidget);
  });
}
