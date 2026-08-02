import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/report.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Every call here hits a staff-gated RPC (`report_revenue`,
/// `report_occupancy`, `dashboard_summary`) -- a customer never reaches
/// this repository because the router already refuses `/admin/*` for
/// anyone but an admin, but even a forged request still gets P0008 from
/// Postgres, mapped by [_guard] to [NotPermitted] like everywhere else.
class ReportRepository {
  ReportRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<DashboardSummary> dashboard() => _guard(() async {
        final json = await _db.rpc('dashboard_summary');
        return DashboardSummary.fromJson(json as Map<String, dynamic>);
      });

  Future<List<RevenueRow>> revenue(
    DateTime from,
    DateTime to, [
    String? propertyId,
  ]) =>
      _guard(() async {
        final rows = await _db.rpc('report_revenue', params: {
          'p_from': _d(from),
          'p_to': _d(to),
          'p_property_id': propertyId,
        }) as List<dynamic>;
        return rows
            .map((e) => RevenueRow.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<List<OccupancyRow>> occupancy(
    DateTime from,
    DateTime to, [
    String? propertyId,
  ]) =>
      _guard(() async {
        final rows = await _db.rpc('report_occupancy', params: {
          'p_from': _d(from),
          'p_to': _d(to),
          'p_property_id': propertyId,
        }) as List<dynamic>;
        return rows
            .map((e) => OccupancyRow.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(supabaseProvider)),
);
