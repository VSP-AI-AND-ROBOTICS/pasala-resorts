import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/admin_profile.dart';
import 'package:pasala/data/models/staff_performance.dart';
import 'package:pasala/data/repositories/profile_directory_repository.dart';
import 'package:pasala/data/repositories/staff_performance_repository.dart';
import 'package:pasala/features/owner/staff_performance_screen.dart';

class FakeStaffPerformanceRepository implements StaffPerformanceRepository {
  List<StaffPerformance> results = const [];

  @override
  Future<List<StaffPerformance>> summary({
    String? staffId,
    required DateTime from,
    required DateTime to,
  }) async =>
      staffId == null ? results : results.where((r) => r.staffId == staffId).toList();
}

final _staffProfile = AdminProfile(
  id: 'staff-1',
  email: 'staff@pasala.test',
  isStaffOrAbove: true,
  fullName: 'Sita Staff',
  createdAt: DateTime.utc(2026, 1, 1),
);

Widget _appFor(FakeStaffPerformanceRepository repo) => ProviderScope(
      overrides: [
        staffPerformanceRepositoryProvider.overrideWithValue(repo),
        adminProfilesProvider.overrideWith((ref) async => [_staffProfile]),
      ],
      child: const MaterialApp(home: StaffPerformanceScreen()),
    );

void main() {
  testWidgets('shows an empty state when no staff have data yet', (tester) async {
    await tester.pumpWidget(_appFor(FakeStaffPerformanceRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No staff to show'), findsOneWidget);
  });

  testWidgets('shows a metrics card per staff member', (tester) async {
    final repo = FakeStaffPerformanceRepository()
      ..results = const [
        StaffPerformance(
          staffId: 'staff-1',
          staffName: 'Sita Staff',
          tasksAssigned: 5,
          tasksCompleted: 3,
          completionRatePct: 60,
          avgCompletionHours: 4.5,
          daysPresent: 20,
          leaveDaysApproved: 2,
          avgCheckinDelayMinutes: 10,
        ),
      ];

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsOneWidget);
    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
  });
}
