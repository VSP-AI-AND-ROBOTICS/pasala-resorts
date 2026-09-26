import 'package:pasala/data/models/coupon.dart';
import 'package:pasala/data/repositories/coupon_repository.dart';

/// In-memory [CouponSource]. Set [coupons]/[guests] for what the server
/// would return, an `...Error` to make that call throw, and read the call
/// logs to assert what a screen asked for.
class FakeCouponSource implements CouponSource {
  List<Coupon> coupons = [];

  /// Guests [findGuest] knows, keyed by the exact email it is asked for.
  Map<String, ResortGuest> guests = {};
  Object? listError;
  Object? createError;
  Object? updateError;
  Object? setActiveError;
  Object? findGuestError;

  final List<String> listCalls = [];
  final List<(String, CouponDraft)> createCalls = [];
  final List<(String, CouponDraft)> updateCalls = [];
  final List<(String, bool)> setActiveCalls = [];
  final List<(String, String)> findGuestCalls = [];

  @override
  Future<List<Coupon>> list(String propertyId) async {
    listCalls.add(propertyId);
    if (listError != null) throw listError!;
    return coupons;
  }

  @override
  Future<String> create(String propertyId, CouponDraft draft) async {
    createCalls.add((propertyId, draft));
    if (createError != null) throw createError!;
    return 'coupon-new';
  }

  @override
  Future<void> update(String couponId, CouponDraft draft) async {
    updateCalls.add((couponId, draft));
    if (updateError != null) throw updateError!;
  }

  @override
  Future<void> setActive(String couponId, bool active) async {
    setActiveCalls.add((couponId, active));
    if (setActiveError != null) throw setActiveError!;
  }

  @override
  Future<ResortGuest?> findGuest(String propertyId, String email) async {
    findGuestCalls.add((propertyId, email));
    if (findGuestError != null) throw findGuestError!;
    return guests[email];
  }
}

/// A coupon with defaults for a plain, active 10% code for everyone;
/// override only what a test is about.
Coupon couponRow({
  String id = 'c1',
  String code = 'SAVE10',
  CouponKind kind = CouponKind.percent,
  num value = 10,
  num? minAmount,
  DateTime? validFrom,
  DateTime? validUntil,
  int? usageLimit,
  int usedCount = 0,
  ResortGuest? guest,
  bool isActive = true,
  CouponStatus status = CouponStatus.active,
}) => Coupon(
  id: id,
  code: code,
  kind: kind,
  value: value,
  minAmount: minAmount,
  validFrom: validFrom,
  validUntil: validUntil,
  usageLimit: usageLimit,
  usedCount: usedCount,
  guest: guest,
  isActive: isActive,
  status: status,
  createdAt: DateTime.utc(2026, 9, 1),
);
