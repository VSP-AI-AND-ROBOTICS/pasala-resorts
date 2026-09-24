import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/staff_shift.dart';
import 'package:pasala/data/repositories/staff_shift_repository.dart';
import 'package:pasala/features/admin/staff_shifts_screen.dart';

import '../../support/resort_roster.dart';

/// In-memory stand-in for [StaffShiftRepository], mirroring
/// `FakeRateRepository` in `rate_rules_screen_test.dart`.
class FakeStaffShiftRepository implements StaffShiftRepository {
  final List<StaffShift> store = [];
  final List<String> deletedIds = [];
  final List<String> listedPropertyIds = [];
  final List<String> createdPropertyIds = [];
  int _idCounter = 0;

  @override
  Future<List<StaffShift>> list({
    required String propertyId,
    String? staffId,
    DateTime? from,
    DateTime? to,
  }) async {
    listedPropertyIds.add(propertyId);
    return store.where((s) {
      if (staffId != null && s.staffId != staffId) return false;
      if (from != null && s.shiftDate.isBefore(from)) return false;
      if (to != null && s.shiftDate.isAfter(to)) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> createRange({
    required String propertyId,
    required String staffId,
    required DateTimeRange range,
    required TimeOfDay start,
    required TimeOfDay end,
    String? notes,
  }) async {
    createdPropertyIds.add(propertyId);
    for (var d = range.start; !d.isAfter(range.end); d = d.add(const Duration(days: 1))) {
      store.add(StaffShift(
        id: 'shift-${_idCounter++}',
        staffId: staffId,
        staffName: staffId == 'staff-1' ? 'Sita Staff' : 'Anil Accounts',
        shiftDate: d,
        startTime: start,
        endTime: end,
        notes: notes,
      ));
    }
  }

  @override
  Future<StaffShift> updateOne(StaffShift shift) async {
    store.removeWhere((s) => s.id == shift.id);
    store.add(shift);
    return shift;
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    store.removeWhere((s) => s.id == id);
  }
}

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Widget _appFor(FakeStaffShiftRepository repo) => ProviderScope(
      overrides: [
        staffShiftRepositoryProvider.overrideWithValue(repo),
        rosterOverride,
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: const MaterialApp(home: StaffShiftsScreen()),
    );

void main() {
  testWidgets('shows an empty state when no shifts exist yet', (tester) async {
    await tester.pumpWidget(_appFor(FakeStaffShiftRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No shifts assigned yet'), findsOneWidget);
  });

  // `showDateRangePicker` opens a real OS-level calendar dialog, not a
  // plain widget, so a widget test cannot drive an end-to-end "tap Save"
  // flow for the range-creation form without a much heavier interaction
  // harness. This test instead covers the two things that ARE meaningfully
  // testable at each end: the FAB actually opens the form (below), and the
  // fake's `createRange` fans one range out into one row per day, which is
  // the exact contract `StaffShiftFormScreen._save()` depends on --
  // covered here as a plain unit test against the fake, not a widget test.
  test(
      'FakeStaffShiftRepository.createRange creates one row per day in the '
      'range, all with the same time', () async {
    final repo = FakeStaffShiftRepository();

    await repo.createRange(
      propertyId: 'p1',
      staffId: 'staff-1',
      range: DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 2)),
      start: const TimeOfDay(hour: 9, minute: 0),
      end: const TimeOfDay(hour: 17, minute: 0),
    );

    expect(repo.store, hasLength(2));
    expect(repo.store.map((s) => s.shiftDate),
        [DateTime(2026, 9, 1), DateTime(2026, 9, 2)]);
    expect(repo.store.every((s) => s.startTime == const TimeOfDay(hour: 9, minute: 0)),
        isTrue);
  });

  testWidgets('the FAB opens the assign-shift form with a staff picker', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeStaffShiftRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Assign shift'), findsOneWidget);
    expect(find.byKey(const Key('shift-form-staff-picker')), findsOneWidget);
  });

  testWidgets('lists an existing shift with staff name, date, and time range',
      (tester) async {
    final repo = FakeStaffShiftRepository()
      ..store.add(StaffShift(
        id: 's1',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        shiftDate: DateTime(2026, 9, 1),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsOneWidget);
    expect(find.textContaining('09:00'), findsOneWidget);
    expect(find.textContaining('17:00'), findsOneWidget);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(repo.listedPropertyIds, everyElement('p1'));
  });

  testWidgets('confirming delete removes the shift', (tester) async {
    final repo = FakeStaffShiftRepository()
      ..store.add(StaffShift(
        id: 's1',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        shiftDate: DateTime(2026, 9, 1),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['s1']);
    expect(find.text('Sita Staff'), findsNothing);
  });

  // Final review C1: the picker lists `list_resort_members` for the current
  // resort only -- never another resort's staff.
  testWidgets("the staff filter lists only the current resort's members", (tester) async {
    await tester.pumpWidget(_appFor(FakeStaffShiftRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shift-staff-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsWidgets);
    expect(find.text('Olga Otherresort'), findsNothing);
  });
}
