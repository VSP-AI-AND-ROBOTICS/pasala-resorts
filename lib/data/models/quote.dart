class QuoteLine {
  const QuoteLine({
    required this.date,
    required this.label,
    required this.amount,
    required this.extraGuests,
    required this.extraGuestAmount,
  });

  final DateTime date;
  final String label;
  final num amount;
  final int extraGuests;
  final num extraGuestAmount;

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
        date: DateTime.parse('${json['date']}T00:00:00Z'),
        label: json['label'] as String,
        amount: json['amount'] as num,
        extraGuests: (json['extra_guests'] as num?)?.toInt() ?? 0,
        extraGuestAmount: json['extra_guest_amount'] as num? ?? 0,
      );
}

/// A coupon applied to a [Quote] server-side, inside `get_quote`. [discount]
/// is already rounded and capped by the server -- never recomputed from
/// [kind]/[value] in Dart; those two are shown for context only.
class AppliedCoupon {
  const AppliedCoupon({
    required this.code,
    required this.kind,
    required this.value,
    required this.discount,
  });

  final String code;

  /// `'percent'` or `'fixed'`, straight from `public.coupon_kind`.
  final String kind;
  final num value;
  final num discount;

  factory AppliedCoupon.fromJson(Map<String, dynamic> json) => AppliedCoupon(
        code: json['code'] as String,
        kind: json['kind'] as String,
        value: json['value'] as num,
        discount: json['discount'] as num,
      );
}

class Quote {
  const Quote({
    required this.currency,
    required this.guests,
    required this.lines,
    required this.subtotal,
    required this.cleaningFee,
    required this.total,
    this.coupon,
  });

  final String currency;
  final int guests;
  final List<QuoteLine> lines;
  final num subtotal;
  final num cleaningFee;
  final AppliedCoupon? coupon;

  /// Server-computed, already net of [coupon]'s discount when one is
  /// applied. Never derived from [lines]/[coupon] in Dart — the server is
  /// the only authority on price.
  final num total;

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        currency: json['currency'] as String? ?? 'INR',
        guests: (json['guests'] as num).toInt(),
        lines: (json['lines'] as List<dynamic>)
            .map((e) => QuoteLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        subtotal: json['subtotal'] as num,
        cleaningFee: json['cleaning_fee'] as num,
        coupon: json['coupon'] == null
            ? null
            : AppliedCoupon.fromJson(json['coupon'] as Map<String, dynamic>),
        total: json['total'] as num,
      );
}
