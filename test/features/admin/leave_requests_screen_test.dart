import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/leave_request.dart';
import 'package:pasala/data/repositories/leave_request_repository.dart';
import 'package:pasala/data/repositories/profile_directory_repository.dart';
import 'package:pasala/features/admin/leave_requests_screen.dart';

/// In-memory stand-in for [LeaveRequestRepository], mirroring
/// `FakeStaffShiftRepository` in `staff_shifts_screen_test.dart`.
class FakeLeaveRequestRepository implements LeaveRequestRepository {
  final List<LeaveRequest> store = [];
  final List<String> decidedIds = [];

  @override
  Future<List<LeaveRequest>> list({
    String? staffId,
    LeaveStatus? status,
  }) async =>
      store.where((r) {
        if (staffId != null && r.staffId != staffId) return false;
        if (status != null && r.status != status) return false;
        return true;
      }).toList();

  @override
  Future<void> create({
    required String staffId,
    required DateTimeRange range,
    String? reason,
  }) async {
    throw UnimplementedError('admin never creates a leave request');
  }

  @override
  Future<void> decide({required String id, required bool approved}) async {
    decidedIds.add(id);
    final index = store.indexWhere((r) => r.id == id);
    final existing = store[index];
    store[index] = LeaveRequest(
      id: existing.id,
      staffId: existing.staffId,
      staffName: existing.staffName,
      startDate: existing.startDate,
      endDate: existing.endDate,
      reason: existing.reason,
      status: approved ? LeaveStatus.approved : LeaveStatus.rejected,
      decidedBy: 'admin-1',
      decidedAt: DateTime(2026, 8, 20),
    );
  }
}

final _staffProfile = AdminProfile(
  id: 'staff-1',
  email: 'staff@pasala.test',
  isStaffOrAbove: true,
  fullName: 'Sita Staff',
  createdAt: DateTime(2026, 1, 1),
);

Widget _appFor(FakeLeaveRequestRepository repo) => ProviderScope(
      overrides: [
        leaveRequestRepositoryProvider.overrideWithValue(repo),
        adminProfilesProvider.overrideWith((ref) async => [_staffProfile]),
      ],
      child: const MaterialApp(home: LeaveRequestsScreen()),
    );

void main() {
  testWidgets('defaults to showing only pending requests', (tester) async {
    final repo = FakeLeaveRequestRepository()
      ..store.addAll([
        LeaveRequest(
          id: 'l1',
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          startDate: DateTime(2026, 9, 10),
          endDate: DateTime(2026, 9, 12),
          status: LeaveStatus.pending,
        ),
        LeaveRequest(
          id: 'l2',
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 2),
          status: LeaveStatus.approved,
        ),
      ]);

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leave-row-l1')), findsOneWidget);
    expect(find.byKey(const Key('leave-row-l2')), findsNothing);
  });

  testWidgets('shows an empty state when there are no pending requests', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(FakeLeaveRequestRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No pending requests'), findsOneWidget);
  });

  testWidgets('approving a pending request calls decide(approved: true) '
      'and it disappears from the pending view', (tester) async {
    final repo = FakeLeaveRequestRepository()
      ..store.add(LeaveRequest(
        id: 'l1',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 12),
        status: LeaveStatus.pending,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approve-l1')));
    await tester.pumpAndSettle();

    expect(repo.decidedIds, ['l1']);
    expect(find.byKey(const Key('leave-row-l1')), findsNothing);
  });

  testWidgets('switching the status filter to All shows a decided request',
      (tester) async {
    final repo = FakeLeaveRequestRepository()
      ..store.add(LeaveRequest(
        id: 'l2',
        staffId: 'staff-1',
        staffName: 'Sita Staff',
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 2),
        status: LeaveStatus.approved,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leave-row-l2')), findsNothing);

    await tester.tap(find.byKey(const Key('leave-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leave-row-l2')), findsOneWidget);
  });
}
