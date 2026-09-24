import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/staff_shift.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/staff_shift_repository.dart';
import 'package:pasala/features/staff/time_slots_screen.dart';

const _staff = AppUser(id: 'staff-1', email: 'staff@pasala.test');

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.staff);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

StaffShift _shift(String id, DateTime date, {int hour = 9}) => StaffShift(
      id: id,
      staffId: 'staff-1',
      staffName: 'Sita Staff',
      shiftDate: date,
      startTime: TimeOfDay(hour: hour, minute: 0),
      endTime: TimeOfDay(hour: hour + 8, minute: 0),
    );

final listedPropertyIds = <String>[];

Widget _appFor(List<StaffShift> shifts) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        currentResortProvider.overrideWith(_FixedResort.new),
        staffShiftsProvider.overrideWith((ref, filter) async {
          listedPropertyIds.add(filter.propertyId);
          return shifts;
        }),
      ],
      child: const MaterialApp(home: TimeSlotsScreen()),
    );

void main() {
  group('upcomingShiftsFrom', () {
    test('drops shifts before today and sorts the rest ascending', () {
      final today = DateTime(2026, 9, 5);
      final shifts = [
        _shift('s1', DateTime(2026, 9, 10)),
        _shift('s2', DateTime(2026, 9, 1)), // in the past
        _shift('s3', DateTime(2026, 9, 5)), // today counts as upcoming
        _shift('s4', DateTime(2026, 9, 7)),
      ];

      final result = upcomingShiftsFrom(shifts, today);

      expect(result.map((s) => s.id), ['s3', 's4', 's1']);
    });
  });

  testWidgets('shows an empty state when the staff member has no shifts', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(const []));
    await tester.pumpAndSettle();

    expect(find.text('No shifts assigned yet'), findsOneWidget);
  });

  testWidgets('lists each shift with its date and time range', (tester) async {
    await tester.pumpWidget(_appFor([
      _shift('s1', DateTime(2026, 12, 1), hour: 9),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('09:00'), findsOneWidget);
    expect(find.textContaining('17:00'), findsOneWidget);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(listedPropertyIds, everyElement('p1'));
  });
}
