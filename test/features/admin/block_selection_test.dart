import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/features/admin/block_dates_screen.dart';
import 'package:pasala/features/calendar/providers.dart';

/// A [UnitCalendarSource] with no occupancy at all, mirroring
/// `_NoOccupancyCalendarSource` in `test/features/booking/hold_lifecycle_test.dart`
/// -- every day in every month renders available so the widget tests below
/// can tap freely without wiring up realtime data.
class _NoOccupancyCalendarSource implements UnitCalendarSource {
  @override
  Stream<List<Reservation>> watchUnit(String unitId) => const Stream.empty();

  @override
  Future<List<Reservation>> fetchUnit(String unitId) async => const [];
}

/// A [BlockDatesAction] fake: records every call and, when [failWith] is
/// set, throws that failure instead of succeeding. Lets tests drive both the
/// happy path and the error-recovery path without touching Supabase, exactly
/// as `_FakeBookingActions` does for the booking flow.
class _FakeBlockDatesAction implements BlockDatesAction {
  final List<({String unitId, List<DateTimeRange> ranges, String reason})>
      calls = [];
  BookingFailure? failWith;

  @override
  Future<List<Reservation>> blockDates({
    required String unitId,
    required List<DateTimeRange> ranges,
    required String reason,
  }) async {
    calls.add((unitId: unitId, ranges: ranges, reason: reason));
    if (failWith != null) throw failWith!;
    return const [];
  }
}

void main() {
  group('collapseToRanges', () {
    test('a single day becomes one range', () {
      final ranges = collapseToRanges({DateTime(2026, 8, 3)});
      expect(ranges, hasLength(1));
      expect(ranges.single.start, DateTime(2026, 8, 3));
      expect(ranges.single.end, DateTime(2026, 8, 3));
    });

    test('adjacent days collapse into one range', () {
      final ranges = collapseToRanges({
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 5),
      });
      expect(ranges, hasLength(1));
      expect(ranges.single.start, DateTime(2026, 8, 3));
      expect(ranges.single.end, DateTime(2026, 8, 5));
    });

    test('a gap splits the selection into two ranges', () {
      final ranges = collapseToRanges({
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 9),
      });
      expect(ranges, hasLength(2));
      expect(ranges.first.end, DateTime(2026, 8, 4));
      expect(ranges.last.start, DateTime(2026, 8, 9));
    });

    test('unsorted input is handled', () {
      final ranges = collapseToRanges({
        DateTime(2026, 8, 5),
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4),
      });
      expect(ranges, hasLength(1));
    });

    // --- Coverage beyond the brief ---

    test('an empty set returns an empty list', () {
      expect(collapseToRanges(const {}), isEmpty);
    });

    test('a run spanning a month boundary collapses into ONE range', () {
      // The classic off-by-one: naive "day-of-month + 1" logic would treat
      // 31 Jan and 1 Feb as non-adjacent. collapseToRanges must use real
      // DateTime subtraction, which handles this correctly.
      final ranges = collapseToRanges({
        DateTime(2026, 1, 30),
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 1),
      });
      expect(ranges, hasLength(1));
      expect(ranges.single.start, DateTime(2026, 1, 30));
      expect(ranges.single.end, DateTime(2026, 2, 1));
    });

    test('a run spanning a year boundary collapses into ONE range', () {
      final ranges = collapseToRanges({
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 1),
      });
      expect(ranges, hasLength(1));
      expect(ranges.single.start, DateTime(2026, 12, 31));
      expect(ranges.single.end, DateTime(2027, 1, 1));
    });
  });

  group('BlockDatesScreen', () {
    // The calendar grid plus the count line, reason field and Save button
    // overflow the default 800x600 test surface, which makes the button
    // "offstage" (below the fold in the ListView's viewport) and therefore
    // invisible to `find` -- see the identical fix and explanation in
    // `rate_rules_screen_test.dart` / `property_form_test.dart`.
    Future<void> useTallSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Widget app({required BlockDatesAction action}) => ProviderScope(
          overrides: [
            unitCalendarSourceProvider
                .overrideWithValue(_NoOccupancyCalendarSource()),
            blockDatesActionProvider.overrideWithValue(action),
          ],
          child: const MaterialApp(home: BlockDatesScreen(unitId: 'unit-1')),
        );

    Finder saveButton() =>
        find.widgetWithText(FilledButton, 'Block selected dates');

    // Move to the next displayed month so every visible day is safely in
    // the future no matter what day the suite happens to run on.
    Future<void> nextMonth(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
    }

    testWidgets('save is disabled with nothing selected and no reason',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app(action: _FakeBlockDatesAction()));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    });

    testWidgets(
        'save stays disabled once a day is selected but the reason is empty',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app(action: _FakeBlockDatesAction()));
      await tester.pumpAndSettle();
      await nextMonth(tester);
      await tester.tap(find.byKey(const Key('day-10')));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    });

    testWidgets('save stays disabled with a reason typed but no day selected',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app(action: _FakeBlockDatesAction()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('block-reason')), 'Owner stay');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    });

    testWidgets('save enables once a day is selected and a reason is typed',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(app(action: _FakeBlockDatesAction()));
      await tester.pumpAndSettle();
      await nextMonth(tester);
      await tester.tap(find.byKey(const Key('day-10')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('block-reason')), 'Owner stay');
      await tester.pumpAndSettle();

      expect(
          tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
    });

    testWidgets(
        'a UnitUnavailable failure surfaces its message and leaves the '
        'selection and reason intact so the admin can adjust and retry',
        (tester) async {
      await useTallSurface(tester);
      final action = _FakeBlockDatesAction()..failWith = const UnitUnavailable();
      await tester.pumpWidget(app(action: action));
      await tester.pumpAndSettle();
      await nextMonth(tester);
      await tester.tap(find.byKey(const Key('day-10')));
      await tester.tap(find.byKey(const Key('day-11')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('block-reason')), 'Maintenance');
      await tester.pumpAndSettle();

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(action.calls, hasLength(1));
      expect(find.text('Those dates were just taken. Pick another slot.'),
          findsOneWidget);
      // Nothing was cleared: the count line still reports both selected
      // days, and the reason text the admin typed is still in the field.
      expect(find.textContaining('2 days selected'), findsOneWidget);
      expect(find.text('Maintenance'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull,
          reason: 'still valid to retry immediately');
    });

    testWidgets(
        'a successful save clears the selection and sends the collapsed '
        'range and trimmed reason', (tester) async {
      await useTallSurface(tester);
      final action = _FakeBlockDatesAction();
      await tester.pumpWidget(app(action: action));
      await tester.pumpAndSettle();
      await nextMonth(tester);
      await tester.tap(find.byKey(const Key('day-10')));
      await tester.tap(find.byKey(const Key('day-11')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('block-reason')), '  Maintenance  ');
      await tester.pumpAndSettle();

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(action.calls, hasLength(1));
      expect(action.calls.single.unitId, 'unit-1');
      expect(action.calls.single.ranges, hasLength(1));
      expect(action.calls.single.reason, 'Maintenance');
      expect(find.text('Dates blocked'), findsOneWidget);
      expect(find.textContaining('0 days selected'), findsOneWidget);
    });
  });
}
