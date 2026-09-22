import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/attendance_record.dart';
import 'package:pasala/data/repositories/attendance_repository.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/staff/working_hours_screen.dart';

const _staff = AppUser(id: 'staff-1', email: 'staff@pasala.test', role: UserRole.staff);

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

Widget _appFor(List<AttendanceRecord> records) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        attendanceRecordsProvider.overrideWith((ref, filter) async => records
            .where((r) =>
                filter.staffId == null || r.staffId == filter.staffId)
            .toList()),
      ],
      child: const MaterialApp(home: WorkingHoursScreen()),
    );

void main() {
  group('hoursForRecord', () {
    test('an 8-hour completed day', () {
      final record = _record('a1', DateTime(2026, 9, 10), checkInHour: 9, checkOutHour: 17);
      expect(hoursForRecord(record), 8.0);
    });

    test('null for a day with no check-out yet', () {
      final record = _record('a1', DateTime(2026, 9, 10), checkInHour: 9);
      expect(hoursForRecord(record), isNull);
    });
  });

  group('totalHours', () {
    final monday = DateTime(2026, 9, 7);

    test('sums only completed records within range', () {
      final records = [
        _record('a1', monday, checkInHour: 9, checkOutHour: 17), // 8h
        _record('a2', monday.add(const Duration(days: 1)),
            checkInHour: 9, checkOutHour: 13), // 4h
        _record('a3', monday.add(const Duration(days: 2)), checkInHour: 9), // open
      ];

      expect(totalHours(records, monday, monday.add(const Duration(days: 6))), 12.0);
    });

    test('excludes records outside the range', () {
      final records = [
        _record('a1', monday.subtract(const Duration(days: 1)),
            checkInHour: 9, checkOutHour: 17),
      ];

      expect(totalHours(records, monday, monday.add(const Duration(days: 6))), 0.0);
    });
  });

  group('formatHours', () {
    test('whole hours', () => expect(formatHours(8.0), '8h'));
    test('hours and minutes', () => expect(formatHours(7.5), '7h 30m'));
    test('zero', () => expect(formatHours(0), '0h'));
  });

  testWidgets('shows an empty state when no days are completed yet', (tester) async {
    await tester.pumpWidget(_appFor(const []));
    await tester.pumpAndSettle();

    expect(find.text('No completed days yet'), findsOneWidget);
  });

  testWidgets('lists a completed day with its computed hours', (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await tester.pumpWidget(_appFor([
      _record('a1', yesterday, checkInHour: 9, checkOutHour: 17),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('8h'), findsWidgets);
  });
}
