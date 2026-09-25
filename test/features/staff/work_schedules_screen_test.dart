import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/staff_shift.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/staff_shift_repository.dart';
import 'package:pasala/features/staff/work_schedules_screen.dart';

const _staff = AppUser(
  id: 'staff-1',
  email: 'staff@pasala.test',
);

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.staff);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

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
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(listedPropertyIds, everyElement('p1'));
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

  // E2E-shaped bug: /staff/schedules lives inside the router's ShellRoute,
  // so the screen's own context resolves to the shell navigator while
  // showDialog puts the dialog on the root one. The dialog's Close button
  // must pop the dialog, not the page (mirrors
  // lib/features/admin/tasks_screen.dart's ShellRoute regression test).
  testWidgets(
      'closing the shift-details dialog inside a ShellRoute closes the '
      'dialog, not the page', (tester) async {
    final today = DateTime.now();
    final shiftDay = DateTime(today.year, today.month, 15);
    final router = GoRouter(
      initialLocation: '/staff/schedules',
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(path: '/staff', builder: (_, _) => const Text('Staff home')),
            GoRoute(
              path: '/staff/schedules',
              builder: (_, _) => const WorkSchedulesScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        currentResortProvider.overrideWith(_FixedResort.new),
        staffShiftsProvider.overrideWith((ref, filter) async {
          listedPropertyIds.add(filter.propertyId);
          return [
            StaffShift(
              id: 's1',
              staffId: 'staff-1',
              shiftDate: shiftDay,
              startTime: const TimeOfDay(hour: 9, minute: 0),
              endTime: const TimeOfDay(hour: 17, minute: 0),
              notes: 'Front desk',
            ),
          ];
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('shift-day-${shiftDay.day}')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(WorkSchedulesScreen), findsOneWidget);
  });
}
