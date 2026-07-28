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
  });
}
