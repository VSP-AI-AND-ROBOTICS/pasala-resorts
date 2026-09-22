enum SlotCode { day, night, fullDay }

SlotCode _slotCode(String raw) => switch (raw) {
      'day' => SlotCode.day,
      'night' => SlotCode.night,
      'full_day' => SlotCode.fullDay,
      _ => throw ArgumentError('unknown slot code $raw'),
    };

class SlotType {
  const SlotType({
    required this.id,
    required this.propertyId,
    required this.code,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String propertyId;
  final SlotCode code;
  final String startTime;
  final String endTime;

  String get label => switch (code) {
        SlotCode.day => 'Day ($startTime–$endTime)',
        SlotCode.night => 'Night ($startTime–$endTime)',
        SlotCode.fullDay => 'Full day ($startTime–$endTime)',
      };

  factory SlotType.fromJson(Map<String, dynamic> json) => SlotType(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        code: _slotCode(json['code'] as String),
        startTime: (json['start_time'] as String).substring(0, 5),
        endTime: (json['end_time'] as String).substring(0, 5),
      );
}
