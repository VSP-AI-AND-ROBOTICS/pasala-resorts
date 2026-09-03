import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/refund_rule.dart';

/// CRUD over `refund_rules` -- this table has been admin-configurable only
/// via Supabase Studio/psql since phase 2 (see the README's "Known
/// limitations"); this is its first Dart access of any kind.
class RefundRuleRepository {
  RefundRuleRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<RefundRule>> list(String propertyId) => _guard(() async {
        final rows = await _db
            .from('refund_rules')
            .select()
            .eq('property_id', propertyId)
            // `.order()` defaults to descending in postgrest-dart --
            // `ascending: true` shows the ladder shortest-notice first.
            .order('min_days_before', ascending: true);
        return rows.map(RefundRule.fromJson).toList();
      });

  Future<void> create(RefundRule rule) => _guard(() async {
        await _db.from('refund_rules').insert(rule.toInsert());
      });

  Future<void> update(String id, RefundRule rule) => _guard(() async {
        await _db.from('refund_rules').update(rule.toInsert()).eq('id', id);
      });

  Future<void> delete(String id) => _guard(() async {
        await _db.from('refund_rules').delete().eq('id', id);
      });
}

final refundRuleRepositoryProvider = Provider<RefundRuleRepository>(
  (ref) => RefundRuleRepository(ref.watch(supabaseProvider)),
);

final refundRulesProvider = FutureProvider.family<List<RefundRule>, String>(
  (ref, propertyId) => ref.watch(refundRuleRepositoryProvider).list(propertyId),
);
