import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/expense.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

typedef ExpenseFilter = ({String propertyId, DateTime from, DateTime to});

/// Read access is admin/accountant/super_admin only (see
/// `0027_expenses.sql`) -- a plain staff member never reaches this
/// repository because the router keeps `/owner/*` super_admin-only, but
/// even a forged request still gets P0008 from Postgres, mapped by
/// [_guard] to [NotPermitted] like everywhere else.
class ExpenseRepository {
  ExpenseRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<Expense>> list({
    required String propertyId,
    required DateTime from,
    required DateTime to,
  }) =>
      _guard(() async {
        final rows = await _db
            .from('expenses')
            .select()
            .eq('property_id', propertyId)
            .gte('expense_date', _d(from))
            .lte('expense_date', _d(to))
            .order('expense_date', ascending: false);
        return rows.map(Expense.fromJson).toList();
      });

  Future<void> create(Expense expense) => _guard(() async {
        await _db.from('expenses').insert(expense.toInsert());
      });

  Future<void> update(String id, Expense expense) => _guard(() async {
        await _db.from('expenses').update(expense.toInsert()).eq('id', id);
      });

  Future<void> delete(String id) => _guard(() async {
        await _db.from('expenses').delete().eq('id', id);
      });
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(supabaseProvider)),
);

final expensesProvider = FutureProvider.family<List<Expense>, ExpenseFilter>(
  (ref, filter) => ref.watch(expenseRepositoryProvider).list(
        propertyId: filter.propertyId,
        from: filter.from,
        to: filter.to,
      ),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);
