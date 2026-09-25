import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/coupon.dart';

/// The slice of [CouponRepository] the Coupons screen and its form need.
/// Tests override [couponSourceProvider] with `FakeCouponSource`
/// (test/support/fake_coupon_source.dart) instead of a real client.
abstract class CouponSource {
  Future<List<Coupon>> list(String propertyId);

  /// Returns the new coupon's id.
  Future<String> create(String propertyId, CouponDraft draft);
  Future<void> update(String couponId, CouponDraft draft);
  Future<void> setActive(String couponId, bool active);

  /// The guest with this email who has booked at [propertyId], or null.
  Future<ResortGuest?> findGuest(String propertyId, String email);
}

/// Backs the Coupons screen through the five functions in
/// 0051_coupon_management.sql. Each checks the caller's role at the resort
/// server-side, so this repository checks nothing itself; refusals arrive
/// as P0002/P0020/P0022/P0033 through [mapPostgrestError].
class CouponRepository implements CouponSource {
  CouponRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<Coupon>> list(String propertyId) => _guard(() async {
    final rows =
        await _db.rpc('list_coupons', params: {'p_property': propertyId})
            as List<dynamic>;
    return rows.map((e) => Coupon.fromJson(e as Map<String, dynamic>)).toList();
  });

  @override
  Future<String> create(String propertyId, CouponDraft draft) =>
      _guard(() async {
        final id = await _db.rpc(
          'create_coupon',
          params: {'p_property': propertyId, ...draft.toParams()},
        );
        return id as String;
      });

  @override
  Future<void> update(String couponId, CouponDraft draft) => _guard(() async {
    await _db.rpc(
      'update_coupon',
      params: {'p_coupon': couponId, ...draft.toParams()},
    );
  });

  @override
  Future<void> setActive(String couponId, bool active) => _guard(() async {
    await _db.rpc(
      'set_coupon_active',
      params: {'p_coupon': couponId, 'p_active': active},
    );
  });

  @override
  Future<ResortGuest?> findGuest(String propertyId, String email) =>
      _guard(() async {
        final rows =
            await _db.rpc(
                  'find_resort_guest',
                  params: {'p_property': propertyId, 'p_email': email.trim()},
                )
                as List<dynamic>;
        if (rows.isEmpty) return null;
        return ResortGuest.fromJson(rows.first as Map<String, dynamic>);
      });
}

final couponRepositoryProvider = Provider<CouponRepository>(
  (ref) => CouponRepository(ref.watch(supabaseProvider)),
);

/// The [CouponSource] seam every screen calls through.
final couponSourceProvider = Provider<CouponSource>(
  (ref) => ref.watch(couponRepositoryProvider),
);

/// The coupons of one resort, keyed by property id so switching resort
/// never shows another resort's coupons. `autoDispose`: the list refetches
/// every time the screen is opened, and the screen invalidates it after
/// its own writes.
final couponsProvider = FutureProvider.autoDispose.family<List<Coupon>, String>(
  (ref, propertyId) => ref.watch(couponSourceProvider).list(propertyId),
);
