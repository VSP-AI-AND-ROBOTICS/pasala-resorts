import 'package:flutter/material.dart';

/// `HH:mm` (24-hour, no seconds) -- the exact convention
/// `property_form_screen.dart` already uses for `Property.checkInTime`/
/// `checkOutTime`, kept identical here so the app never has two different
/// time-of-day text formats.
String formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Parses either `HH:mm` or `HH:mm:ss` (Postgrest serialises a Postgres
/// `time` column with seconds) into a [TimeOfDay] -- only the first two
/// components are read, so a `:00` seconds suffix is silently ignored
/// rather than crashing `int.parse`.
TimeOfDay parseTimeOfDay(String raw) {
  final parts = raw.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

/// One assigned shift. [staffName] is populated only when this came from
/// `list_staff_shifts()` (the RPC every screen actually reads through) --
/// `null` is never treated as an error, just "not fetched with a name."
class StaffShift {
  const StaffShift({
    required this.id,
    required this.staffId,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    this.staffName,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String staffId;
  final String? staffName;
  final DateTime shiftDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String? notes;
  final DateTime? createdAt;

  factory StaffShift.fromJson(Map<String, dynamic> json) => StaffShift(
        id: json['id'] as String,
        staffId: json['staff_id'] as String,
        staffName: json['staff_name'] as String?,
        shiftDate: DateTime.parse(json['shift_date'] as String),
        startTime: parseTimeOfDay(json['start_time'] as String),
        endTime: parseTimeOfDay(json['end_time'] as String),
        notes: json['notes'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  /// Payload for an insert/update -- deliberately excludes `id` (server-
  /// assigned on insert, unchanged on update via a separate `.eq('id', ...)`
  /// clause), `staff_name` (a read-only join result, not a column), and
  /// `created_at` (server-assigned default).
  Map<String, dynamic> toInsert() => {
        'staff_id': staffId,
        'shift_date': shiftDate.toIso8601String().substring(0, 10),
        'start_time': formatTimeOfDay(startTime),
        'end_time': formatTimeOfDay(endTime),
        'notes': notes,
      };
}
