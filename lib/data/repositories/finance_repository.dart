import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/finance.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The slice of [FinanceRepository] the Finance screen and the owner export
/// centre need. Tests override [financeSourceProvider] with
/// `FakeFinanceSource` (test/support/fake_finance_source.dart) instead of a
/// real client.
abstract class FinanceSource {
  Future<FinanceSummary> summary(String propertyId);
  Future<List<CollectionRow>> collections(
    DateTime from,
    DateTime to,
    String propertyId,
  );
  Future<List<LedgerRow>> ledger(DateTime from, DateTime to, String propertyId);
  Future<List<SettlementRow>> settlements(
    DateTime from,
    DateTime to,
    String propertyId,
  );
}

/// Backs the Finance screen through the four report functions in
/// 0048_finance_ledger.sql. Each asserts owner/admin/accountant at
/// `p_property_id` server-side, so this repository checks nothing itself;
/// refusals arrive as P0020 through [mapPostgrestError].
class FinanceRepository implements FinanceSource {
  FinanceRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Map<String, dynamic> _range(DateTime from, DateTime to, String propertyId) =>
      {'p_from': _d(from), 'p_to': _d(to), 'p_property_id': propertyId};

  @override
  Future<FinanceSummary> summary(String propertyId) => _guard(() async {
    final json = await _db.rpc(
      'finance_summary',
      params: {'p_property_id': propertyId},
    );
    return FinanceSummary.fromJson(json as Map<String, dynamic>);
  });

  @override
  Future<List<CollectionRow>> collections(
    DateTime from,
    DateTime to,
    String propertyId,
  ) => _guard(() async {
    final rows =
        await _db.rpc(
              'report_collections',
              params: _range(from, to, propertyId),
            )
            as List<dynamic>;
    return rows
        .map((e) => CollectionRow.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<List<LedgerRow>> ledger(
    DateTime from,
    DateTime to,
    String propertyId,
  ) => _guard(() async {
    final rows =
        await _db.rpc('report_ledger', params: _range(from, to, propertyId))
            as List<dynamic>;
    return rows
        .map((e) => LedgerRow.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<List<SettlementRow>> settlements(
    DateTime from,
    DateTime to,
    String propertyId,
  ) => _guard(() async {
    final rows =
        await _db.rpc(
              'report_settlements',
              params: _range(from, to, propertyId),
            )
            as List<dynamic>;
    return rows
        .map((e) => SettlementRow.fromJson(e as Map<String, dynamic>))
        .toList();
  });
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(supabaseProvider)),
);

/// The [FinanceSource] seam every screen calls through.
final financeSourceProvider = Provider<FinanceSource>(
  (ref) => ref.watch(financeRepositoryProvider),
);
