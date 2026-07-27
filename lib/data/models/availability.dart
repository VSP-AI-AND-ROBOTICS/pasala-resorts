import 'package:flutter/material.dart' show DateTimeRange;

import 'reservation.dart';
import 'unit.dart';

class UnitAvailability {
  const UnitAvailability({
    required this.unitId,
    required this.propertyId,
    required this.unitName,
    required this.bookingMode,
    required this.isAvailable,
    required this.busyPeriods,
  });

  final String unitId;
  final String propertyId;
  final String unitName;
  final BookingMode bookingMode;
  final bool isAvailable;
  final List<DateTimeRange> busyPeriods;

  factory UnitAvailability.fromJson(Map<String, dynamic> json) =>
      UnitAvailability(
        unitId: json['unit_id'] as String,
        propertyId: json['property_id'] as String,
        unitName: json['unit_name'] as String,
        bookingMode: BookingMode.values.byName(json['booking_mode'] as String),
        isAvailable: json['is_available'] as bool,
        busyPeriods: (json['busy_periods'] as List<dynamic>? ?? [])
            .map((raw) {
              final p = parsePeriod(raw as String);
              return DateTimeRange(start: p.start.toLocal(), end: p.end.toLocal());
            })
            .toList(),
      );
}
