enum BookingMode { nightly, slot, both }

class Unit {
  const Unit({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.capacityBase,
    required this.capacityMax,
    required this.bookingMode,
    required this.isActive,
    this.description,
  });

  final String id;
  final String propertyId;
  final String name;
  final String? description;
  final int capacityBase;
  final int capacityMax;
  final BookingMode bookingMode;
  final bool isActive;

  bool get supportsNightly => bookingMode != BookingMode.slot;
  bool get supportsSlots => bookingMode != BookingMode.nightly;

  factory Unit.fromJson(Map<String, dynamic> json) => Unit(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        capacityBase: (json['capacity_base'] as num).toInt(),
        capacityMax: (json['capacity_max'] as num).toInt(),
        bookingMode: BookingMode.values.byName(json['booking_mode'] as String),
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toInsert() => {
        'property_id': propertyId,
        'name': name,
        'description': description,
        'capacity_base': capacityBase,
        'capacity_max': capacityMax,
        'booking_mode': bookingMode.name,
        'is_active': isActive,
      };
}
