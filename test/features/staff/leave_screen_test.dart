import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/leave_request.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/leave_request_repository.dart';
import 'package:pasala/features/staff/leave_screen.dart';

const _staff = AppUser(id: 'staff-1', email: 'staff@pasala.test', role: UserRole.staff);

/// In-memory stand-in for [LeaveRequestRepository], mirroring
/// `FakeStaffShiftRepository`.
class FakeLeaveRequestRepository implements LeaveRequestRepository {
  final List<LeaveRequest> store = [];
  final List<Map<String, dynamic>> createCalls = [];
  int _idCounter = 0;
  BookingFailure? createFailure;

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
    createCalls.add({'staffId': staffId, 'range': range, 'reason': reason});
    final failure = createFailure;
    if (failure != null) throw failure;
    store.add(LeaveRequest(
      id: 'leave-${_idCounter++}',
      staffId: staffId,
      startDate: range.start,
      endDate: range.end,
      reason: reason,
      status: LeaveStatus.pending,
    ));
  }

  @override
  Future<void> decide({required String id, required bool approved}) async {
    throw UnimplementedError('staff never decides a leave request');
  }
}

Widget _appFor(FakeLeaveRequestRepository repo) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        leaveRequestRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: LeaveScreen()),
    );

void main() {
  testWidgets('shows an empty state when the staff member has no requests',
      (tester) async {
    await tester.pumpWidget(_appFor(FakeLeaveRequestRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No leave requests yet'), findsOneWidget);
  });

  testWidgets('lists an existing request with its date range, reason, and '
      'status', (tester) async {
    final repo = FakeLeaveRequestRepository()
      ..store.add(LeaveRequest(
        id: 'l1',
        staffId: 'staff-1',
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 12),
        reason: 'Family trip',
        status: LeaveStatus.pending,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Family trip'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('the FAB opens the submit-leave form', (tester) async {
    await tester.pumpWidget(_appFor(FakeLeaveRequestRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Request leave'), findsOneWidget);
    expect(find.byKey(const Key('leave-form-reason')), findsOneWidget);
  });
}
