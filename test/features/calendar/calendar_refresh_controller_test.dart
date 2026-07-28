import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/calendar/calendar_refresh_controller.dart';

void main() {
  group('CalendarRefreshController', () {
    test('forwards realtime events as they arrive', () async {
      final realtime = StreamController<int>();
      final controller = CalendarRefreshController<int>(
        realtime: realtime.stream,
        fetch: () async => -1,
        interval: const Duration(minutes: 10),
      );
      addTearDown(controller.dispose);

      final events = <int>[];
      final sub = controller.stream.listen(events.add);
      addTearDown(sub.cancel);

      realtime.add(1);
      realtime.add(2);
      await Future<void>.delayed(Duration.zero);

      expect(events, [1, 2]);
      realtime.close();
    });

    test('polls at the configured interval as a fallback', () async {
      var fetchCount = 0;
      final controller = CalendarRefreshController<int>(
        realtime: const Stream<int>.empty(),
        fetch: () async {
          fetchCount++;
          return fetchCount;
        },
        interval: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);

      final events = <int>[];
      final sub = controller.stream.listen(events.add);
      addTearDown(sub.cancel);

      // Give the periodic timer time to fire a handful of times.
      await Future<void>.delayed(const Duration(milliseconds: 110));

      expect(controller.pollCount, greaterThanOrEqualTo(3));
      expect(events, isNotEmpty);
      expect(events, orderedEquals(events.toSet().toList()..sort()));
    });

    test('an external resume signal triggers an immediate poll', () async {
      var fetchCount = 0;
      final resumeController = StreamController<void>();
      final controller = CalendarRefreshController<int>(
        realtime: const Stream<int>.empty(),
        fetch: () async {
          fetchCount++;
          return fetchCount;
        },
        resumeSignals: resumeController.stream,
        // Long enough that the periodic timer alone would not fire during
        // the test, so any poll we see must have come from the signal.
        interval: const Duration(minutes: 10),
      );
      addTearDown(controller.dispose);

      final events = <int>[];
      final sub = controller.stream.listen(events.add);
      addTearDown(sub.cancel);

      expect(controller.pollCount, 0);
      resumeController.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(controller.pollCount, 1);
      expect(events, [1]);
      await resumeController.close();
    });

    test('dispose cancels the timer so it does not keep polling', () async {
      var fetchCount = 0;
      final controller = CalendarRefreshController<int>(
        realtime: const Stream<int>.empty(),
        fetch: () async {
          fetchCount++;
          return fetchCount;
        },
        interval: const Duration(milliseconds: 15),
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.pollCount, greaterThan(0));

      await controller.dispose();
      final pollsAtDispose = controller.pollCount;

      // If the timer were still alive this would pick up several more
      // fires; it must not.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.pollCount, pollsAtDispose);
    });

    test('dispose closes the output stream', () async {
      final controller = CalendarRefreshController<int>(
        realtime: const Stream<int>.empty(),
        fetch: () async => 1,
        interval: const Duration(minutes: 10),
      );

      var done = false;
      final sub = controller.stream.listen((_) {}, onDone: () => done = true);
      addTearDown(sub.cancel);

      await controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue);
    });

    test('dispose cancels the realtime subscription', () async {
      final realtime = StreamController<int>();
      final controller = CalendarRefreshController<int>(
        realtime: realtime.stream,
        fetch: () async => -1,
        interval: const Duration(minutes: 10),
      );

      await controller.dispose();

      // A controller with no listeners left throws if closed while it
      // still has pending listeners; asserting cancellation indirectly by
      // confirming the underlying StreamController can be closed cleanly
      // once its only subscriber (the refresher) is gone.
      expect(realtime.hasListener, isFalse);
      await realtime.close();
    });

    test('errors from fetch are forwarded as stream errors, not swallowed',
        () async {
      final controller = CalendarRefreshController<int>(
        realtime: const Stream<int>.empty(),
        fetch: () async => throw StateError('boom'),
        interval: const Duration(milliseconds: 15),
      );
      addTearDown(controller.dispose);

      final errors = <Object>[];
      final sub = controller.stream.listen(
        (_) {},
        onError: errors.add,
      );
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(errors, isNotEmpty);
      expect(errors.first, isA<StateError>());
    });

    group('monotonic ordering guard (regression: stale poll vs realtime)',
        () {
      test(
          'a poll in flight when a fresher realtime event arrives does not '
          'revert the UI once that poll finally resolves', () async {
        final realtime = StreamController<int>();
        // The poll's fetch does not complete until we let it, so we can
        // control exactly when it resolves relative to the realtime event.
        final inFlight = Completer<int>();
        final resumeController = StreamController<void>();
        final controller = CalendarRefreshController<int>(
          realtime: realtime.stream,
          fetch: () => inFlight.future,
          resumeSignals: resumeController.stream,
          // Long enough that only the manually-triggered poll fires.
          interval: const Duration(minutes: 10),
        );
        addTearDown(controller.dispose);

        final events = <int>[];
        final sub = controller.stream.listen(events.add);
        addTearDown(sub.cancel);

        // Dispatch a poll; it blocks on `inFlight` and is now "in flight".
        resumeController.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty); // poll hasn't resolved yet

        // A newer realtime event arrives while that poll is still pending.
        realtime.add(99);
        await Future<void>.delayed(Duration.zero);
        expect(events, [99]);

        // The stale poll -- dispatched before the realtime event -- now
        // finally resolves with data that predates it.
        inFlight.complete(1);
        await Future<void>.delayed(Duration.zero);

        // The UI must not have reverted to the poll's stale value.
        expect(events, [99]);

        await resumeController.close();
        await realtime.close();
      });

      test('a late-resolving older poll is dropped in favor of a newer one',
          () async {
        final completers = <Completer<int>>[
          Completer<int>(),
          Completer<int>(),
        ];
        var call = 0;
        final resumeController = StreamController<void>();
        final controller = CalendarRefreshController<int>(
          realtime: const Stream<int>.empty(),
          fetch: () => completers[call++].future,
          resumeSignals: resumeController.stream,
          interval: const Duration(minutes: 10),
        );
        addTearDown(controller.dispose);

        final events = <int>[];
        final sub = controller.stream.listen(events.add);
        addTearDown(sub.cancel);

        // Dispatch two polls back to back; both are now in flight.
        resumeController.add(null);
        await Future<void>.delayed(Duration.zero);
        resumeController.add(null);
        await Future<void>.delayed(Duration.zero);

        // The second (newer) poll resolves first, with fresher data.
        completers[1].complete(2);
        await Future<void>.delayed(Duration.zero);
        expect(events, [2]);

        // The first (older) poll resolves late, carrying stale data. It
        // must be dropped rather than overwriting the fresher value.
        completers[0].complete(1);
        await Future<void>.delayed(Duration.zero);
        expect(events, [2]);

        await resumeController.close();
      });
    });
  });
}
