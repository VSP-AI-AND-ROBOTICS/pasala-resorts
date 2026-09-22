import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/rate_rule.dart';

class RateRepository {
  RateRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<RateRule>> forUnit(String unitId) => _guard(() async {
        final rows = await _db
            .from('rate_rules')
            .select()
            .eq('unit_id', unitId)
            .order('priority', ascending: false);
        return rows.map(RateRule.fromJson).toList();
      });

  Future<RateRule> upsert(RateRule rule, {String? id}) => _guard(() async {
        final payload = rule.toInsert();
        final row = id == null
            ? await _db.from('rate_rules').insert(payload).select().single()
            : await _db
                .from('rate_rules')
                .update(payload)
                .eq('id', id)
                .select()
                .single();
        return RateRule.fromJson(row);
      });

  Future<void> delete(String id) => _guard(() async {
        await _db.from('rate_rules').delete().eq('id', id);
      });
}

final rateRepositoryProvider = Provider<RateRepository>(
  (ref) => RateRepository(ref.watch(supabaseProvider)),
);

final rateRulesProvider = FutureProvider.family<List<RateRule>, String>(
  (ref, unitId) => ref.watch(rateRepositoryProvider).forUnit(unitId),
);
