import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/report.dart';
import '../../data/repositories/report_repository.dart';

final dashboardSummaryProvider = FutureProvider<DashboardSummary>(
  (ref) => ref.watch(reportRepositoryProvider).dashboard(),
);

/// The two report kinds [ReportsScreen] can show, backing its
/// `SegmentedButton`. PDF is deliberately not a third option here -- see
/// `csv_export.dart` -- there is nothing to add until it ships.
enum ReportKind { revenue, occupancy }

/// Keys [revenueReportProvider]/[occupancyReportProvider]. A plain record
/// gets free structural equality, so re-selecting the same range/property
/// does not trigger a refetch -- exactly what a `FutureProvider.family` key
/// needs.
typedef ReportFilter = ({DateTime from, DateTime to, String? propertyId});

final revenueReportProvider =
    FutureProvider.family<List<RevenueRow>, ReportFilter>(
  (ref, filter) => ref
      .watch(reportRepositoryProvider)
      .revenue(filter.from, filter.to, filter.propertyId),
);

final occupancyReportProvider =
    FutureProvider.family<List<OccupancyRow>, ReportFilter>(
  (ref, filter) => ref
      .watch(reportRepositoryProvider)
      .occupancy(filter.from, filter.to, filter.propertyId),
);
