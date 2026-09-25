import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/coupon.dart';

import '../support/fake_coupon_source.dart';

void main() {
  group('Coupon.fromJson', () {
    test('reads every column list_coupons returns', () {
      final c = Coupon.fromJson(const {
        'id': 'c1',
        'code': 'SUMMER',
        'kind': 'fixed',
        'value': 500,
        'min_booking_value': 5000,
        'valid_from': '2026-10-01',
        'valid_until': '2026-10-31',
        'max_redemptions': 10,
        'redeemed_count': 3,
        'customer_id': 'g1',
        'customer_email': 'gita@example.com',
        'customer_name': 'Gita Guest',
        'is_active': true,
        'status': 'scheduled',
        'created_at': '2026-09-25T10:00:00+00:00',
      });

      expect(c.id, 'c1');
      expect(c.code, 'SUMMER');
      expect(c.kind, CouponKind.fixed);
      expect(c.value, 500);
      expect(c.minAmount, 5000);
      expect(c.validFrom, DateTime(2026, 10, 1));
      expect(c.validUntil, DateTime(2026, 10, 31));
      expect(c.usageLimit, 10);
      expect(c.usedCount, 3);
      expect(c.guest!.userId, 'g1');
      expect(c.guest!.email, 'gita@example.com');
      expect(c.guest!.fullName, 'Gita Guest');
      expect(c.isActive, isTrue);
      expect(c.status, CouponStatus.scheduled);
      expect(c.createdAt, DateTime.utc(2026, 9, 25, 10));
    });

    test('the optional columns may all be null', () {
      final c = Coupon.fromJson(const {
        'id': 'c2',
        'code': 'SAVE10',
        'kind': 'percent',
        'value': 10,
        'min_booking_value': null,
        'valid_from': null,
        'valid_until': null,
        'max_redemptions': null,
        'redeemed_count': 0,
        'customer_id': null,
        'customer_email': null,
        'customer_name': null,
        'is_active': false,
        'status': 'inactive',
        'created_at': '2026-09-25T10:00:00+00:00',
      });

      expect(c.minAmount, isNull);
      expect(c.validFrom, isNull);
      expect(c.validUntil, isNull);
      expect(c.usageLimit, isNull);
      expect(c.guest, isNull);
      expect(c.isActive, isFalse);
      expect(c.status, CouponStatus.inactive);
    });

    test('every status the server sends is understood, and nothing else', () {
      expect(couponStatusFromDb('active'), CouponStatus.active);
      expect(couponStatusFromDb('scheduled'), CouponStatus.scheduled);
      expect(couponStatusFromDb('expired'), CouponStatus.expired);
      expect(couponStatusFromDb('used_up'), CouponStatus.usedUp);
      expect(couponStatusFromDb('inactive'), CouponStatus.inactive);
      expect(() => couponStatusFromDb('bogus'), throwsArgumentError);
      expect(() => couponKindFromDb('bogus'), throwsArgumentError);
      expect(couponKindToDb(CouponKind.percent), 'percent');
      expect(couponKindToDb(CouponKind.fixed), 'fixed');
    });
  });

  group('display', () {
    test('each status has a label and an icon, never colour alone', () {
      expect(CouponStatus.values.map((s) => s.label), [
        'Active',
        'Scheduled',
        'Expired',
        'Used up',
        'Inactive',
      ]);
      for (final s in CouponStatus.values) {
        expect(s.icon, isA<IconData>());
      }
    });

    test('discount, minimum, usage and audience lines', () {
      expect(couponRow(value: 10).discountLabel, '10% off');
      expect(couponRow(value: 12.5).discountLabel, '12.5% off');
      expect(
        couponRow(kind: CouponKind.fixed, value: 500).discountLabel,
        '₹500 off',
      );
      expect(couponRow().minAmountLabel, isNull);
      expect(couponRow(minAmount: 5000).minAmountLabel, 'Min ₹5,000');
      expect(couponRow(usedCount: 3).usageLabel, 'Used 3');
      expect(
        couponRow(usedCount: 3, usageLimit: 10).usageLabel,
        'Used 3 of 10',
      );
      expect(couponRow().audienceLabel, 'Everyone');
      expect(
        couponRow(
          guest: const ResortGuest(
            userId: 'g1',
            email: 'gita@example.com',
            fullName: 'Gita Guest',
          ),
        ).audienceLabel,
        'Only Gita Guest',
      );
      expect(
        couponRow(
          guest: const ResortGuest(userId: 'g1', email: 'gita@example.com'),
        ).audienceLabel,
        'Only gita@example.com',
      );
    });

    test('validity line for every combination of dates', () {
      expect(couponRow().validityLabel, 'No date limits');
      expect(
        couponRow(validFrom: DateTime(2026, 10, 1)).validityLabel,
        'From 1 Oct 2026',
      );
      expect(
        couponRow(validUntil: DateTime(2026, 10, 31)).validityLabel,
        'Until 31 Oct 2026',
      );
      expect(
        couponRow(
          validFrom: DateTime(2026, 10, 1),
          validUntil: DateTime(2026, 10, 31),
        ).validityLabel,
        '1 Oct 2026 – 31 Oct 2026',
      );
    });
  });

  group('CouponDraft.toParams', () {
    test('sends every field, dates as yyyy-MM-dd', () {
      final draft = CouponDraft(
        code: 'SUMMER',
        kind: CouponKind.fixed,
        value: 500,
        minAmount: 5000,
        validFrom: DateTime(2026, 10, 1),
        validUntil: DateTime(2026, 10, 31),
        usageLimit: 10,
        guestId: 'g1',
      );
      expect(draft.toParams(), {
        'p_code': 'SUMMER',
        'p_kind': 'fixed',
        'p_value': 500,
        'p_min_amount': 5000,
        'p_valid_from': '2026-10-01',
        'p_valid_until': '2026-10-31',
        'p_usage_limit': 10,
        'p_customer': 'g1',
      });
    });

    test('sends nulls too: an update replaces the whole coupon', () {
      const draft = CouponDraft(
        code: 'SAVE10',
        kind: CouponKind.percent,
        value: 10,
      );
      expect(draft.toParams(), {
        'p_code': 'SAVE10',
        'p_kind': 'percent',
        'p_value': 10,
        'p_min_amount': null,
        'p_valid_from': null,
        'p_valid_until': null,
        'p_usage_limit': null,
        'p_customer': null,
      });
    });
  });

  test('the code rule matches the server', () {
    expect(normalizeCouponCode('  summer-10 '), 'SUMMER-10');
    expect(couponCodePattern.hasMatch('SUMMER-10'), isTrue);
    expect(couponCodePattern.hasMatch('A_1'), isTrue);
    expect(couponCodePattern.hasMatch('AB'), isFalse);
    expect(couponCodePattern.hasMatch('SAVE 10'), isFalse);
    expect(couponCodePattern.hasMatch('-SAVE'), isFalse);
    expect(couponCodePattern.hasMatch('save10'), isFalse);
    expect(couponCodePattern.hasMatch('A' * 24), isTrue);
    expect(couponCodePattern.hasMatch('A' * 25), isFalse);
  });
}
