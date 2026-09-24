import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/attendance_record.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/attendance_repository.dart';
import 'package:pasala/features/admin/attendance_screen.dart';

import '../../support/resort_roster.dart';

/// In-memory stand-in for [AttendanceRepository], mirroring
/// `FakeLeaveRequestRepository` in `leave_requests_screen_test.dart`.
class FakeAttendanceRepository implements AttendanceRepository {
  final List<AttendanceRecord> store = [];
  final List<String> listedPropertyIds = [];

  @override
  Future<List<AttendanceRecord>> list({
    required String propertyId,
    String? staffId,
    DateTime? date,
  }) async {
    listedPropertyIds.add(propertyId);
    return store.where((r) {
      if (staffId != null && r.staffId != staffId) return false;
      if (date != null && !DateUtils.isSameDay(r.workDate, date)) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> checkIn({required String propertyId, required String staffId}) async {
    throw UnimplementedError('admin never checks anyone in');
  }

  @override
  Future<void> checkOut({required String id}) async {
    throw UnimplementedError('admin never checks anyone out');
  }
}

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Widget _appFor(FakeAttendanceRepository repo) => ProviderScope(
      overrides: [
        attendanceRepositoryProvider.overrideWithValue(repo),
        rosterOverride,
        currentResortProvider.overrideWith(_FixedResort.new),
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
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(repo.listedPropertyIds, everyElement('p1'));
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

  // Final review C1: the picker lists `list_resort_members` for the current
  // resort only -- never another resort's staff.
  testWidgets("the staff filter lists only the current resort's members", (tester) async {
    await tester.pumpWidget(_appFor(FakeAttendanceRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('attendance-staff-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsWidgets);
    expect(find.text('Olga Otherresort'), findsNothing);
  });
}
