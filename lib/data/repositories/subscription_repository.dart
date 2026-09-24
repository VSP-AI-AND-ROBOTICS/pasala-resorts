import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/subscription.dart';

/// A resort's own plan, for its owners and admins. Tests override
/// [resortPlanSourceProvider] with `FakeResortPlanSource`
/// (test/support/fake_resort_plan_source.dart).
abstract class ResortPlanSource {
  /// Null when the resort has no subscription row. Anyone who is not an
  /// owner or admin of [propertyId] gets P0020 ([NotAMember]).
  Future<ResortPlan?> resortPlan(String propertyId);
}

/// Reads `my_resort_subscription(p_property)` (0049_subscriptions.sql).
class SubscriptionRepository implements ResortPlanSource {
  SubscriptionRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<ResortPlan?> resortPlan(String propertyId) => _guard(() async {
    final rows =
        await _db.rpc(
              'my_resort_subscription',
              params: {'p_property': propertyId},
            )
            as List<dynamic>;
    return rows.isEmpty
        ? null
        : ResortPlan.fromRow(rows.first as Map<String, dynamic>);
  });
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(ref.watch(supabaseProvider)),
);

/// The [ResortPlanSource] seam every screen calls through.
final resortPlanSourceProvider = Provider<ResortPlanSource>(
  (ref) => ref.watch(subscriptionRepositoryProvider),
);

/// One resort's plan, keyed by property id so switching resort never shows
/// another resort's plan. `autoDispose`: Settings refetches it every time
/// it opens, so a change the platform admin made shows up.
final resortPlanProvider = FutureProvider.autoDispose
    .family<ResortPlan?, String>(
      (ref, propertyId) =>
          ref.watch(resortPlanSourceProvider).resortPlan(propertyId),
    );
