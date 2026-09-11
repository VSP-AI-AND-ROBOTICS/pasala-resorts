import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/staff_shift.dart';

void main() {
  group('formatTimeOfDay / parseTimeOfDay', () {
    test('formats and round-trips a morning time', () {
      const time = TimeOfDay(hour: 9, minute: 5);
      expect(formatTimeOfDay(time), '09:05');
      expect(parseTimeOfDay('09:05'), time);
    });

    test('parses a value with seconds, as Postgrest returns for `time`', () {
      expect(parseTimeOfDay('17:30:00'), const TimeOfDay(hour: 17, minute: 30));
    });
  });

  group('StaffShift.fromJson', () {
    test('parses a plain staff_shifts table row (no staff_name)', () {
      final shift = StaffShift.fromJson(const {
        'id': 's1',
        'staff_id': 'u1',
        'shift_date': '2026-09-01',
        'start_time': '09:00:00',
        'end_time': '17:00:00',
        'notes': null,
        'created_at': '2026-08-19T10:00:00Z',
      });

      expect(shift.id, 's1');
      expect(shift.staffId, 'u1');
      expect(shift.staffName, isNull);
      expect(shift.shiftDate, DateTime.parse('2026-09-01'));
      expect(shift.startTime, const TimeOfDay(hour: 9, minute: 0));
      expect(shift.endTime, const TimeOfDay(hour: 17, minute: 0));
    });

    test('parses a list_staff_shifts() row, including staff_name', () {
      final shift = StaffShift.fromJson(const {
        'id': 's2',
        'staff_id': 'u2',
        'staff_name': 'Sita Staff',
        'shift_date': '2026-09-02',
        'start_time': '10:00:00',
        'end_time': '18:00:00',
        'notes': 'cover shift',
        'created_at': '2026-08-19T10:00:00Z',
      });

      expect(shift.staffName, 'Sita Staff');
      expect(shift.notes, 'cover shift');
    });
  });

  test('toInsert never includes id, staff_name, or created_at', () {
    final shift = StaffShift.fromJson(const {
      'id': 's1',
      'staff_id': 'u1',
      'staff_name': 'Sita Staff',
      'shift_date': '2026-09-01',
      'start_time': '09:00:00',
      'end_time': '17:00:00',
      'notes': null,
      'created_at': '2026-08-19T10:00:00Z',
    });

    final payload = shift.toInsert();
    expect(payload.containsKey('id'), isFalse);
    expect(payload.containsKey('staff_name'), isFalse);
    expect(payload.containsKey('created_at'), isFalse);
    expect(payload['staff_id'], 'u1');
    expect(payload['shift_date'], '2026-09-01');
    expect(payload['start_time'], '09:00');
    expect(payload['end_time'], '17:00');
  });
}
