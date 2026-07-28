import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/booking_repository.dart';
import 'package:pasala/features/calendar/providers.dart';

/// A [UnitCalendarSource] that never touches Supabase: `watchUnit` returns
/// a stream we control by hand, and `fetchUnit` just counts calls. This is
/// the fake `unitCalendarSourceProvider` (see providers.dart) exists to
/// make possible -- without it, testing `unitReservationsProvider`'s
/// lifecycle would require a real `SupabaseClient`.
class _FakeCalendarSource implements UnitCalendarSource {
  final StreamController<List<Reservation>> _realtime =
      StreamController<List<Reservation>>.broadcast();

  int fetchCount = 0;

  @override
  Stream<List<Reservation>> watchUnit(String unitId) => _realtime.stream;

  @override
  Future<List<Reservation>> fetchUnit(String unitId) async {
    fetchCount++;
    return const <Reservation>[];
  }

  Future<void> close() => _realtime.close();
}

/// Simulates a platform app-lifecycle message, exactly as Flutter's own
/// `AppLifecycleListener` tests do (see
/// `packages/flutter/test/widgets/app_lifecycle_listener_test.dart`). This
/// is the only way to drive `AppLifecycleListener.onResume` from a test
/// without a running widget tree.
Future<void> _setAppLifecycleState(AppLifecycleState state) async {
  final message = const StringCodec().encodeMessage(state.toString());
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('flutter/lifecycle', message, (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Establish a known starting lifecycle state so a later transition to
    // `resumed` is a genuine change (mirrors Flutter's own listener tests).
    await _setAppLifecycleState(AppLifecycleState.paused);
    await _setAppLifecycleState(AppLifecycleState.detached);
  });

  group('unitReservationsProvider lifecycle', () {
    const unitId = 'unit-1';

    test(
        'disposing the container cancels the poll timer and disposes the '
        'AppLifecycleListener -- no work happens after disposal', () async {
      final source = _FakeCalendarSource();
      final container = ProviderContainer(
        overrides: [
          unitCalendarSourceProvider.overrideWithValue(source),
          calendarRefreshIntervalProvider
              .overrideWithValue(const Duration(milliseconds: 15)),
        ],
      );

      final sub =
          container.listen(unitReservationsProvider(unitId), (_, _) {});

      // Let the fallback timer fire a few times so we know it's alive.
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(source.fetchCount, greaterThan(0));

      // Sanity-check the AppLifecycleListener wiring while still alive: a
      // resume transition must trigger an extra poll.
      final beforeResume = source.fetchCount;
      await _setAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(source.fetchCount, greaterThan(beforeResume));

      // Back to a non-resumed state so the next resumed transition (after
      // disposal, below) is a genuine change again.
      await _setAppLifecycleState(AppLifecycleState.paused);

      sub.close();
      container.dispose();
      final countAtDispose = source.fetchCount;

      // If the timer were still alive, this would pick up several more
      // fires (interval is 15ms; this waits for ~5 more cycles).
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(source.fetchCount, countAtDispose);

      // If the AppLifecycleListener were still attached, resuming would
      // trigger one more poll via its onResume callback. It must not.
      await _setAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(source.fetchCount, countAtDispose);

      await source.close();
    });

    test(
        'rapidly disposing and re-watching does not leave two timers '
        'running for the same unitId', () async {
      final source = _FakeCalendarSource();
      final container = ProviderContainer(
        overrides: [
          unitCalendarSourceProvider.overrideWithValue(source),
          calendarRefreshIntervalProvider
              .overrideWithValue(const Duration(milliseconds: 15)),
        ],
      );
      addTearDown(container.dispose);

      var sub = container.listen(unitReservationsProvider(unitId), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Stop watching, then wait just long enough for autoDispose's
      // scheduled teardown (a zero-duration Timer -- see
      // ProviderScheduler.scheduleProviderDispose) to actually run, so the
      // first instance's `CalendarRefreshController` and its `Timer.periodic`
      // are genuinely disposed before we watch again. This simulates
      // rapidly navigating away from and back to `/book/:unitId`.
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Re-watch the same unitId: a fresh provider instance, fresh
      // CalendarRefreshController, fresh Timer.periodic.
      sub = container.listen(unitReservationsProvider(unitId), (_, _) {});
      addTearDown(sub.close);

      final before = source.fetchCount;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      final polledDuringWindow = source.fetchCount - before;

      // One live 15ms timer over a 90ms window fires about 6 times. If the
      // first instance's timer had leaked instead of being cancelled, two
      // concurrent timers would push this close to double.
      expect(polledDuringWindow, lessThan(9));

      await source.close();
    });
  });
}
