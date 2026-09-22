/// The result of `compute_refund(reservation_id)`: what a reservation would
/// be refunded if cancelled right now. [refundAmount] is already computed
/// server-side (`quote.total * refundPct / 100`, rounded) -- never
/// re-derived in Dart, the same rule every other money figure in this app
/// follows.
class RefundQuote {
  const RefundQuote({
    required this.daysBefore,
    required this.refundPct,
    required this.refundAmount,
    this.ruleId,
  });

  final int daysBefore;
  final num refundPct;

  /// Zero -- not a special "no refund" sentinel -- when no rule matches or
  /// the reservation carries no priceable quote. Displayed verbatim, so a
  /// customer within the no-refund window sees an explicit ₹0, not a hidden
  /// or omitted line.
  final num refundAmount;

  /// Null when no `refund_rules` tier matched (e.g. the property has none
  /// configured) -- distinct from a tier matching at 0%, which still sets
  /// this.
  final String? ruleId;

  factory RefundQuote.fromJson(Map<String, dynamic> json) => RefundQuote(
        daysBefore: (json['days_before'] as num).toInt(),
        refundPct: json['refund_pct'] as num? ?? 0,
        refundAmount: json['refund_amount'] as num? ?? 0,
        ruleId: json['rule_id'] as String?,
      );
}
