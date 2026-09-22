import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/staff_performance.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

typedef StaffPerformanceFilter = ({String? staffId, DateTime from, DateTime to});

class StaffPerformanceRepository {
  StaffPerformanceRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<StaffPerformance>> summary({
    String? staffId,
    required DateTime from,
    required DateTime to,
  }) =>
      _guard(() async {
        final rows = await _db.rpc('staff_performance_summary', params: {
          'p_staff_id': staffId,
          'p_from': _d(from),
          'p_to': _d(to),
        }) as List<dynamic>;
        return rows
            .map((e) => StaffPerformance.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}

final staffPerformanceRepositoryProvider = Provider<StaffPerformanceRepository>(
  (ref) => StaffPerformanceRepository(ref.watch(supabaseProvider)),
);

final staffPerformanceProvider =
    FutureProvider.family<List<StaffPerformance>, StaffPerformanceFilter>(
  (ref, filter) => ref.watch(staffPerformanceRepositoryProvider).summary(
        staffId: filter.staffId,
        from: filter.from,
        to: filter.to,
      ),
);
