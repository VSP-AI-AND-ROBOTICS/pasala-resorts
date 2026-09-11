/// One tier of a property's cancellation-refund ladder (`refund_rules`).
/// The rule that applies to an actual cancellation is the one with the
/// greatest `minDaysBefore` that does not exceed the real number of days
/// before check-in -- see `compute_refund` (0013_refund_policy.sql) for the
/// authoritative selection logic; this model only carries what the owner
/// edits, it never re-derives a refund itself.
class RefundRule {
  const RefundRule({
    required this.id,
    required this.propertyId,
    required this.minDaysBefore,
    required this.refundPct,
  });

  final String id;
  final String propertyId;
  final int minDaysBefore;
  final num refundPct;

  factory RefundRule.fromJson(Map<String, dynamic> json) => RefundRule(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        minDaysBefore: (json['min_days_before'] as num?)?.toInt() ?? 0,
        refundPct: (json['refund_pct'] as num?) ?? 0,
      );

  Map<String, dynamic> toInsert() => {
        'property_id': propertyId,
        'min_days_before': minDaysBefore,
        'refund_pct': refundPct,
      };
}
