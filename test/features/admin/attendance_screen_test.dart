import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/attendance_record.dart';
import 'package:pasala/data/repositories/attendance_repository.dart';
import 'package:pasala/data/repositories/user_admin_repository.dart';
import 'package:pasala/features/admin/attendance_screen.dart';

/// In-memory stand-in for [AttendanceRepository], mirroring
/// `FakeLeaveRequestRepository` in `leave_requests_screen_test.dart`.
class FakeAttendanceRepository implements AttendanceRepository {
  final List<AttendanceRecord> store = [];

  @override
  Future<List<AttendanceRecord>> list({
    String? staffId,
    DateTime? date,
  }) async =>
      store.where((r) {
        if (staffId != null && r.staffId != staffId) return false;
        if (date != null && !DateUtils.isSameDay(r.workDate, date)) return false;
        return true;
      }).toList();

  @override
  Future<void> checkIn({required String staffId}) async {
    throw UnimplementedError('admin never checks anyone in');
  }

  @override
  Future<void> checkOut({required String id}) async {
    throw UnimplementedError('admin never checks anyone out');
  }
}

final _staffProfile = AdminProfile(
  id: 'staff-1',
  email: 'staff@pasala.test',
  role: UserRole.staff,
  fullName: 'Sita Staff',
  createdAt: DateTime(2026, 1, 1),
);

Widget _appFor(FakeAttendanceRepository repo) => ProviderScope(
      overrides: [
        attendanceRepositoryProvider.overrideWithValue(repo),
        adminProfilesProvider.overrideWith((ref) async => [_staffProfile]),
      ],
      child: const MaterialApp(home: AttendanceScreen()),
    );

void main() {
  final today = DateTime.now();

  testWidgets('defaults to showing today\'s records only', (tester) async {
    final repo = FakeAttendanceRepository()
      ..store.addAll([
        AttendanceRecord(
          id: 'a1',
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          workDate: DateTime(today.year, today.month, today.day),
          checkInAt: DateTime(today.year, today.month, today.day, 9),
        ),
        AttendanceRecord(
          id: 'a2',
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          workDate: DateTime(today.year, today.month, today.day - 1),
          checkInAt: DateTime(today.year, today.month, today.day - 1, 9),
          checkOutAt: DateTime(today.year, today.month, today.day - 1, 17),
        ),
      ]);

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attendance-row-a1')), findsOneWidget);
    expect(find.byKey(const Key('attendance-row-a2')), findsNothing);
  });

  testWidgets('shows an empty state when nobody has checked in that day', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeAttendanceRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No attendance records'), findsOneWidget);
  });

  testWidgets('shows still-checked-in and checked-out states distinctly', (
    tester,
  ) async {
    final repo = FakeAttendanceRepository()
      ..store.add(AttendanceRecord(
        id: 'a1',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        workDate: DateTime(today.year, today.month, today.day),
        checkInAt: DateTime(today.year, today.month, today.day, 9),
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Still checked in'), findsOneWidget);
  });
}
