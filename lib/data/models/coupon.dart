import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';

/// `public.coupon_kind`: a percentage off, or a fixed rupee amount off.
enum CouponKind { percent, fixed }

/// Unknown text is rejected rather than defaulted -- a silent fallback
/// would hide a server/app mismatch.
CouponKind couponKindFromDb(String raw) => switch (raw) {
  'percent' => CouponKind.percent,
  'fixed' => CouponKind.fixed,
  _ => throw ArgumentError('Unknown coupon kind: $raw'),
};

/// Inverse of [couponKindFromDb].
String couponKindToDb(CouponKind kind) => switch (kind) {
  CouponKind.percent => 'percent',
  CouponKind.fixed => 'fixed',
};

/// Where a coupon stands right now. Worked out by `list_coupons`
/// (0051_coupon_management.sql) in the order `resolve_coupon` checks at
/// booking time: inactive, expired, not yet valid, used up, else active.
enum CouponStatus { active, scheduled, expired, usedUp, inactive }

CouponStatus couponStatusFromDb(String raw) => switch (raw) {
  'active' => CouponStatus.active,
  'scheduled' => CouponStatus.scheduled,
  'expired' => CouponStatus.expired,
  'used_up' => CouponStatus.usedUp,
  'inactive' => CouponStatus.inactive,
  _ => throw ArgumentError('Unknown coupon status: $raw'),
};

/// Label, icon and colour for a [CouponStatus]. The icon and the label
/// always travel with the colour: a status is never told by colour alone.
extension CouponStatusDisplay on CouponStatus {
  String get label => switch (this) {
    CouponStatus.active => 'Active',
    CouponStatus.scheduled => 'Scheduled',
    CouponStatus.expired => 'Expired',
    CouponStatus.usedUp => 'Used up',
    CouponStatus.inactive => 'Inactive',
  };

  IconData get icon => switch (this) {
    CouponStatus.active => Icons.check_circle_outline,
    CouponStatus.scheduled => Icons.schedule,
    CouponStatus.expired => Icons.event_busy_outlined,
    CouponStatus.usedUp => Icons.do_not_disturb_on_outlined,
    CouponStatus.inactive => Icons.pause_circle_outline,
  };

  Color get color => switch (this) {
    CouponStatus.active => const Color(0xFF2E7D32),
    CouponStatus.scheduled => const Color(0xFF1565C0),
    CouponStatus.expired => const Color(0xFF616161),
    CouponStatus.usedUp => const Color(0xFFB26A00),
    CouponStatus.inactive => const Color(0xFF616161),
  };
}

/// The code rule `coupon_check_input` enforces, applied after
/// [normalizeCouponCode]: 3-24 characters from A-Z, 0-9, `-` and `_`,
/// starting with a letter or digit.
final couponCodePattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]{2,23}$');

/// Codes are stored trimmed and upper-case (`coupons_code_upper`).
String normalizeCouponCode(String raw) => raw.trim().toUpperCase();

final _isoDay = DateFormat('yyyy-MM-dd');

String? _isoDayOrNull(DateTime? day) =>
    day == null ? null : _isoDay.format(day);

DateTime? _dayOrNull(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String);

/// A guest who has booked at the resort, as `find_resort_guest` returns
/// them -- or the guest a coupon is restricted to.
class ResortGuest {
  const ResortGuest({required this.userId, required this.email, this.fullName});

  factory ResortGuest.fromJson(Map<String, dynamic> json) => ResortGuest(
    userId: json['user_id'] as String,
    email: json['email'] as String,
    fullName: json['full_name'] as String?,
  );

  final String userId;
  final String email;
  final String? fullName;

  /// The full name, or the email for an account without one.
  String get name {
    final trimmed = fullName?.trim() ?? '';
    return trimmed.isEmpty ? email : trimmed;
  }
}

/// One row of `list_coupons(p_property)`. [validFrom] and [validUntil] are
/// calendar days in the resort's time zone; [usedCount] is the server's
/// `redeemed_count` (live holds included, released holds given back).
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.kind,
    required this.value,
    this.minAmount,
    this.validFrom,
    this.validUntil,
    this.usageLimit,
    this.usedCount = 0,
    this.guest,
    this.isActive = true,
    this.status = CouponStatus.active,
    required this.createdAt,
  });

  factory Coupon.fromJson(Map<String, dynamic> json) {
    final guestId = json['customer_id'] as String?;
    return Coupon(
      id: json['id'] as String,
      code: json['code'] as String,
      kind: couponKindFromDb(json['kind'] as String),
      value: json['value'] as num,
      minAmount: json['min_booking_value'] as num?,
      validFrom: _dayOrNull(json['valid_from']),
      validUntil: _dayOrNull(json['valid_until']),
      usageLimit: json['max_redemptions'] as int?,
      usedCount: json['redeemed_count'] as int,
      guest: guestId == null
          ? null
          : ResortGuest(
              userId: guestId,
              email: json['customer_email'] as String? ?? '',
              fullName: json['customer_name'] as String?,
            ),
      isActive: json['is_active'] as bool,
      status: couponStatusFromDb(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String code;
  final CouponKind kind;
  final num value;
  final num? minAmount;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int? usageLimit;
  final int usedCount;
  final ResortGuest? guest;
  final bool isActive;
  final CouponStatus status;
  final DateTime createdAt;

  String get discountLabel => switch (kind) {
    CouponKind.percent => '${formatPct(value)}% off',
    CouponKind.fixed => '${formatInr(value)} off',
  };

  String? get minAmountLabel =>
      minAmount == null ? null : 'Min ${formatInr(minAmount!)}';

  String get validityLabel => switch ((validFrom, validUntil)) {
    (null, null) => 'No date limits',
    (final DateTime from, null) => 'From ${formatDate(from)}',
    (null, final DateTime until) => 'Until ${formatDate(until)}',
    (final DateTime from, final DateTime until) =>
      '${formatDate(from)} – ${formatDate(until)}',
  };

  String get usageLabel =>
      usageLimit == null ? 'Used $usedCount' : 'Used $usedCount of $usageLimit';

  String get audienceLabel =>
      guest == null ? 'Everyone' : 'Only ${guest!.name}';
}

/// What the form sends to `create_coupon` / `update_coupon`. [validFrom]
/// and [validUntil] are calendar days; the server turns them into whole
/// days in the resort's time zone.
class CouponDraft {
  const CouponDraft({
    required this.code,
    required this.kind,
    required this.value,
    this.minAmount,
    this.validFrom,
    this.validUntil,
    this.usageLimit,
    this.guestId,
  });

  final String code;
  final CouponKind kind;
  final num value;
  final num? minAmount;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int? usageLimit;
  final String? guestId;

  /// The parameters `create_coupon` and `update_coupon` share. Every key is
  /// always sent, nulls included: an update replaces the whole coupon.
  Map<String, dynamic> toParams() => {
    'p_code': code,
    'p_kind': couponKindToDb(kind),
    'p_value': value,
    'p_min_amount': minAmount,
    'p_valid_from': _isoDayOrNull(validFrom),
    'p_valid_until': _isoDayOrNull(validUntil),
    'p_usage_limit': usageLimit,
    'p_customer': guestId,
  };
}
