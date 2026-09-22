import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/leave_request.dart';

void main() {
  group('leaveStatusFromDb / leaveStatusToDb', () {
    test('round-trips all three values', () {
      for (final status in LeaveStatus.values) {
        expect(leaveStatusFromDb(leaveStatusToDb(status)), status);
      }
    });
  });

  group('LeaveRequest.fromJson', () {
    test('parses a plain table row (no embedded profiles)', () {
      final request = LeaveRequest.fromJson(const {
        'id': 'l1',
        'staff_id': 'u1',
        'start_date': '2026-09-10',
        'end_date': '2026-09-12',
        'reason': 'Family trip',
        'status': 'pending',
        'decided_by': null,
        'decided_at': null,
        'created_at': '2026-08-20T10:00:00Z',
      });

      expect(request.id, 'l1');
      expect(request.staffId, 'u1');
      expect(request.staffName, isNull);
      expect(request.startDate, DateTime.parse('2026-09-10'));
      expect(request.endDate, DateTime.parse('2026-09-12'));
      expect(request.reason, 'Family trip');
      expect(request.status, LeaveStatus.pending);
      expect(request.decidedBy, isNull);
      expect(request.decidedAt, isNull);
    });

    test('parses a row with an embedded profiles object, including '
        'staff_name and a decided request', () {
      final request = LeaveRequest.fromJson(const {
        'id': 'l2',
        'staff_id': 'u2',
        'profiles': {'full_name': 'Sita Staff'},
        'start_date': '2026-09-18',
        'end_date': '2026-09-18',
        'reason': null,
        'status': 'approved',
        'decided_by': 'admin-1',
        'decided_at': '2026-08-21T09:00:00Z',
        'created_at': '2026-08-20T10:00:00Z',
      });

      expect(request.staffName, 'Sita Staff');
      expect(request.status, LeaveStatus.approved);
      expect(request.decidedBy, 'admin-1');
      expect(request.decidedAt, DateTime.parse('2026-08-21T09:00:00Z'));
    });
  });

  test('toInsert never includes id, status, decided_by, decided_at, or '
      'staff_name', () {
    final request = LeaveRequest.fromJson(const {
      'id': 'l1',
      'staff_id': 'u1',
      'profiles': {'full_name': 'Sita Staff'},
      'start_date': '2026-09-10',
      'end_date': '2026-09-12',
      'reason': 'Family trip',
      'status': 'pending',
      'decided_by': null,
      'decided_at': null,
      'created_at': '2026-08-20T10:00:00Z',
    });

    final payload = request.toInsert();
    expect(payload.keys.toSet(),
        {'staff_id', 'start_date', 'end_date', 'reason'});
    expect(payload['staff_id'], 'u1');
    expect(payload['start_date'], '2026-09-10');
    expect(payload['end_date'], '2026-09-12');
    expect(payload['reason'], 'Family trip');
  });
}
