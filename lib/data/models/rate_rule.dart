enum RateKind { base, weekend, override_ }

RateKind rateKindFromDb(String raw) => switch (raw) {
      'base' => RateKind.base,
      'weekend' => RateKind.weekend,
      'override' => RateKind.override_,
      _ => throw ArgumentError('unknown rate kind $raw'),
    };

String rateKindToDb(RateKind kind) => switch (kind) {
      RateKind.base => 'base',
      RateKind.weekend => 'weekend',
      RateKind.override_ => 'override',
    };

class RateRule {
  const RateRule({
    required this.id,
    required this.unitId,
    required this.kind,
    required this.price,
    required this.extraGuestPrice,
    required this.cleaningFee,
    required this.priority,
    this.label,
    this.slotTypeId,
    this.validFrom,
    this.validTo,
    this.weekdays = const [],
  });

  final String id;
  final String unitId;
  final RateKind kind;
  final String? label;
  final String? slotTypeId;
  final DateTime? validFrom;
  final DateTime? validTo;
  final List<int> weekdays;
  final num price;
  final num extraGuestPrice;
  final num cleaningFee;
  final int priority;

  factory RateRule.fromJson(Map<String, dynamic> json) => RateRule(
        id: json['id'] as String,
        unitId: json['unit_id'] as String,
        kind: rateKindFromDb(json['kind'] as String),
        label: json['label'] as String?,
        slotTypeId: json['slot_type_id'] as String?,
        validFrom: json['valid_from'] == null
            ? null
            : DateTime.parse(json['valid_from'] as String),
        validTo: json['valid_to'] == null
            ? null
            : DateTime.parse(json['valid_to'] as String),
        weekdays:
            (json['weekdays'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
        price: json['price'] as num,
        extraGuestPrice: json['extra_guest_price'] as num,
        cleaningFee: json['cleaning_fee'] as num,
        priority: (json['priority'] as num).toInt(),
      );

  Map<String, dynamic> toInsert() => {
        'unit_id': unitId,
        'kind': rateKindToDb(kind),
        'label': label,
        'slot_type_id': slotTypeId,
        'valid_from': validFrom?.toIso8601String().substring(0, 10),
        'valid_to': validTo?.toIso8601String().substring(0, 10),
        'weekdays': weekdays.isEmpty ? null : weekdays,
        'price': price,
        'extra_guest_price': extraGuestPrice,
        'cleaning_fee': cleaningFee,
        'priority': priority,
      };
}
