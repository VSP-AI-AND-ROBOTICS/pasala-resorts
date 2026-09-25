import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/report.dart';
import '../../data/repositories/report_repository.dart';

/// Keyed by the current resort's property id, so switching resorts cannot
/// show another resort's cached dashboard figures.
final dashboardSummaryProvider = FutureProvider.family<DashboardSummary, String>(
  (ref, propertyId) => ref.watch(reportRepositoryProvider).dashboard(propertyId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

/// The two report kinds [ReportsScreen] can show, backing its
/// `SegmentedButton`. PDF is deliberately not a third option here -- see
/// `csv_export.dart` -- there is nothing to add until it ships.
enum ReportKind { revenue, occupancy }

/// Keys [revenueReportProvider]/[occupancyReportProvider]. A plain record
/// gets free structural equality, so re-selecting the same range does not
/// trigger a refetch -- exactly what a `FutureProvider.family` key needs.
typedef ReportFilter = ({DateTime from, DateTime to, String propertyId});

final revenueReportProvider =
    FutureProvider.family<List<RevenueRow>, ReportFilter>(
  (ref, filter) => ref
      .watch(reportRepositoryProvider)
      .revenue(filter.from, filter.to, filter.propertyId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

final occupancyReportProvider =
    FutureProvider.family<List<OccupancyRow>, ReportFilter>(
  (ref, filter) => ref
      .watch(reportRepositoryProvider)
      .occupancy(filter.from, filter.to, filter.propertyId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);
