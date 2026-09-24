import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/attendance_record.dart';
import 'package:pasala/data/repositories/attendance_repository.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/staff/daily_status_screen.dart';

const _staff = AppUser(id: 'staff-1', email: 'staff@pasala.test');

AttendanceRecord _record(
  String id,
  DateTime day, {
  int checkInHour = 9,
  int? checkOutHour,
}) =>
    AttendanceRecord(
      id: id,
      staffId: 'staff-1',
      workDate: DateTime(day.year, day.month, day.day),
      checkInAt: DateTime(day.year, day.month, day.day, checkInHour),
      checkOutAt: checkOutHour == null
          ? null
          : DateTime(day.year, day.month, day.day, checkOutHour),
    );

/// In-memory stand-in for [AttendanceRepository], mirroring
/// `FakeLeaveRequestRepository`.
class FakeAttendanceRepository implements AttendanceRepository {
  final List<AttendanceRecord> store = [];
  final List<String> checkInCalls = [];
  final List<String> checkOutCalls = [];
  int _idCounter = 0;
  BookingFailure? checkInFailure;

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
    checkInCalls.add(staffId);
    final failure = checkInFailure;
    if (failure != null) throw failure;
    final now = DateTime.now();
    store.add(AttendanceRecord(
      id: 'attendance-${_idCounter++}',
      staffId: staffId,
      workDate: DateTime(now.year, now.month, now.day),
      checkInAt: now,
    ));
  }

  @override
  Future<void> checkOut({required String id}) async {
    checkOutCalls.add(id);
    final index = store.indexWhere((r) => r.id == id);
    final existing = store[index];
    store[index] = AttendanceRecord(
      id: existing.id,
      staffId: existing.staffId,
      workDate: existing.workDate,
      checkInAt: existing.checkInAt,
      checkOutAt: DateTime.now(),
    );
  }
}

Widget _appFor(FakeAttendanceRepository repo) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        attendanceRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: DailyStatusScreen()),
    );

void main() {
  group('todayRecordFrom / pastRecordsFrom', () {
    final today = DateTime(2026, 9, 10);

    test('todayRecordFrom finds the record matching today\'s date', () {
      final records = [
        _record('a1', today.subtract(const Duration(days: 1))),
        _record('a2', today),
      ];

      expect(todayRecordFrom(records, today)?.id, 'a2');
    });

    test('todayRecordFrom returns null when there is no record today', () {
      final records = [_record('a1', today.subtract(const Duration(days: 1)))];

      expect(todayRecordFrom(records, today), isNull);
    });

    test('pastRecordsFrom excludes today and sorts newest first', () {
      final records = [
        _record('a1', today.subtract(const Duration(days: 2))),
        _record('a2', today),
        _record('a3', today.subtract(const Duration(days: 1))),
      ];

      expect(pastRecordsFrom(records, today).map((r) => r.id), ['a3', 'a1']);
    });
  });

  testWidgets('shows a Check In button when there is no record today', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeAttendanceRepository()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('check-in-button')), findsOneWidget);
    expect(find.byKey(const Key('check-out-button')), findsNothing);
  });

  testWidgets('tapping Check In calls checkIn and shows the Check Out button',
      (tester) async {
    final repo = FakeAttendanceRepository();
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('check-in-button')));
    await tester.pumpAndSettle();

    expect(repo.checkInCalls, ['staff-1']);
    expect(find.byKey(const Key('check-out-button')), findsOneWidget);
    expect(find.byKey(const Key('check-in-button')), findsNothing);
  });

  testWidgets(
      'tapping Check Out calls checkOut and shows the checked-out summary '
      'with no button', (tester) async {
    final now = DateTime.now();
    final repo = FakeAttendanceRepository()
      ..store.add(_record('a1', now, checkInHour: 9));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('check-out-button')));
    await tester.pumpAndSettle();

    expect(repo.checkOutCalls, ['a1']);
    expect(find.byKey(const Key('check-out-button')), findsNothing);
    expect(find.byKey(const Key('check-in-button')), findsNothing);
  });

  testWidgets('shows past records in the history list', (tester) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final repo = FakeAttendanceRepository()
      ..store.add(_record('a1', yesterday, checkInHour: 9, checkOutHour: 17));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('9:00'), findsOneWidget);
    expect(find.textContaining('5:00'), findsOneWidget);
  });
}
