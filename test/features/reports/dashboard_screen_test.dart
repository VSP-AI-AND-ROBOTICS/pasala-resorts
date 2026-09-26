import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/expense.dart';
import 'package:pasala/data/models/food_sale.dart';
import 'package:pasala/data/models/report.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/report_repository.dart';
import 'package:pasala/features/reports/dashboard_screen.dart';

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
/// this test suite. Only `dashboard()` is exercised by [DashboardScreen];
/// `revenue`/`occupancy` are never called from here.
class FakeReportRepository implements ReportRepository {
  DashboardSummary? summary;
  BookingFailure? dashboardFailure;
  final List<String> requestedPropertyIds = [];

  @override
  Future<DashboardSummary> dashboard(String propertyId) async {
    requestedPropertyIds.add(propertyId);
    final failure = dashboardFailure;
    if (failure != null) throw failure;
    return summary!;
  }

  @override
  Future<List<RevenueRow>> revenue(DateTime from, DateTime to, String propertyId) async =>
      [];

  @override
  Future<List<OccupancyRow>> occupancy(
          DateTime from, DateTime to, String propertyId) async =>
      [];

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
      overrides: [
        reportRepositoryProvider.overrideWithValue(repo),
        currentResortProvider.overrideWith(() => _FixedResort(_resort)),
      ],
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
      overrides: [
        reportRepositoryProvider.overrideWithValue(repo),
        currentResortProvider.overrideWith(() => _FixedResort(_resort)),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('You do not have access to do that.'), findsOneWidget);
    expect(find.text('Revenue today'), findsNothing);

    // Riverpod 3's `defaultRetry` auto-retries any FutureProvider whose
    // `create()` threw something that isn't an `Error`/`ProviderException`
    // -- up to 10 times with exponential backoff -- and `NotPermitted` is a
    // plain `BookingFailure`. This screen already has its own Retry button,
    // so `dashboardSummaryProvider` must opt out of that auto-retry: the
    // repository should be hit exactly once for the initial failed load,
    // not up to 11 times before the error UI even appears.
    expect(repo.requestedPropertyIds, hasLength(1));

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
    // ...and exactly one more call for the manual Retry tap, not another
    // burst of internal auto-retries on top of it.
    expect(repo.requestedPropertyIds, hasLength(2));
  });

  // Review Focus #1: the current resort's id must reach the RPC.
  testWidgets('queries the summary scoped to the current resort', (tester) async {
    const otherResort = ResortMembership(
        propertyId: 'p2', resortName: 'Other Resort', role: ResortRole.admin);
    final repo = FakeReportRepository()
      ..summary = const DashboardSummary(
        todayRevenue: 0,
        monthRevenue: 0,
        occupancyPct: 0,
        upcomingArrivals: 0,
        cancellationsThisMonth: 0,
        activeHolds: 0,
      );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        reportRepositoryProvider.overrideWithValue(repo),
        currentResortProvider.overrideWith(() => _FixedResort(otherResort)),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await tester.pumpAndSettle();

    expect(repo.requestedPropertyIds, everyElement('p2'));
  });
}
