import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/attendance_record.dart';

void main() {
  group('AttendanceRecord.fromJson', () {
    test('parses a plain table row (no embedded profiles), still checked in', () {
      final record = AttendanceRecord.fromJson(const {
        'id': 'a1',
        'staff_id': 'u1',
        'work_date': '2026-09-10',
        'check_in_at': '2026-09-10T09:00:00Z',
        'check_out_at': null,
      });

      expect(record.id, 'a1');
      expect(record.staffId, 'u1');
      expect(record.staffName, isNull);
      expect(record.workDate, DateTime.parse('2026-09-10'));
      expect(record.checkInAt, DateTime.parse('2026-09-10T09:00:00Z'));
      expect(record.checkOutAt, isNull);
      expect(record.isCheckedIn, isTrue);
    });

    test('parses a row with an embedded profiles object and a checkout', () {
      final record = AttendanceRecord.fromJson(const {
        'id': 'a2',
        'staff_id': 'u2',
        'profiles': {'full_name': 'Sita Staff'},
        'work_date': '2026-09-11',
        'check_in_at': '2026-09-11T09:00:00Z',
        'check_out_at': '2026-09-11T17:00:00Z',
      });

      expect(record.staffName, 'Sita Staff');
      expect(record.checkOutAt, DateTime.parse('2026-09-11T17:00:00Z'));
      expect(record.isCheckedIn, isFalse);
    });
  });
}
