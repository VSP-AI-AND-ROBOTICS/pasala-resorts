import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/staff_shift.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/staff_shift_repository.dart';
import 'package:pasala/features/staff/work_schedules_screen.dart';

const _staff = AppUser(
  id: 'staff-1',
  email: 'staff@pasala.test',
  role: UserRole.staff,
);

Widget _appFor(List<StaffShift> shifts) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
    staffShiftsProvider.overrideWith((ref, filter) async => shifts),
  ],
  child: const MaterialApp(home: WorkSchedulesScreen()),
);

void main() {
  group('hasShiftOn', () {
    final shifts = [
      StaffShift(
        id: 's1',
        staffId: 'staff-1',
        shiftDate: DateTime(2026, 9, 10),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      ),
    ];

    test('true for a day with a shift', () {
      expect(hasShiftOn(DateTime(2026, 9, 10), shifts), isTrue);
    });

    test('false for a day with no shift', () {
      expect(hasShiftOn(DateTime(2026, 9, 11), shifts), isFalse);
    });

    test('ignores time-of-day when comparing the calendar date', () {
      expect(hasShiftOn(DateTime(2026, 9, 10, 23, 59), shifts), isTrue);
    });
  });

  testWidgets('a day with a shift is tappable and shows its details', (
    tester,
  ) async {
    final today = DateTime.now();
    final shiftDay = DateTime(today.year, today.month, 15);
    await tester.pumpWidget(
      _appFor([
        StaffShift(
          id: 's1',
          staffId: 'staff-1',
          shiftDate: shiftDay,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          notes: 'Front desk',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('shift-day-${shiftDay.day}')));
    await tester.pumpAndSettle();

    expect(find.text('Front desk'), findsOneWidget);
    expect(find.textContaining('09:00'), findsOneWidget);
  });

  testWidgets('a day with no shift is not tappable', (tester) async {
    await tester.pumpWidget(_appFor(const []));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    await tester.tap(find.byKey(Key('shift-day-${today.day}')));
    await tester.pumpAndSettle();

    // No dialog opened -- nothing to show for a shift-free day.
    expect(find.byType(AlertDialog), findsNothing);
  });
}
