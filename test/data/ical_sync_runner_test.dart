import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/repositories/ical_repository.dart';
import 'package:pasala/data/repositories/ical_sync_runner.dart';

import '../support/fake_ical_source.dart';

void main() {
  const ok = IcalSyncResult(status: 'ok', events: 3);
  const stale = IcalSyncResult(status: 'ok', events: 1);
  const requested = IcalSyncResult(status: 'requested');
  const pending = IcalSyncResult(status: 'pending');

  late List<Duration> waits;
  IcalSyncRunner runner(FakeIcalSource source, {int maxCalls = 8}) =>
      IcalSyncRunner(
        source,
        maxCalls: maxCalls,
        wait: (delay) async => waits.add(delay),
      );

  setUp(() => waits = []);

  test('a result collected by the first call is stale: the second call\'s '
      'result is returned', () async {
    final source = FakeIcalSource()..syncScript = [stale, ok];

    final result = await runner(source).syncNow('f1');

    expect(result, same(ok));
    expect(source.syncCalls, ['f1', 'f1']);
    expect(waits, [const Duration(seconds: 2)]);
  });

  test('keeps calling through requested and pending until a result is '
      'collected', () async {
    final source = FakeIcalSource()..syncScript = [requested, pending, ok];

    final result = await runner(source).syncNow('f1');

    expect(result, same(ok));
    expect(source.syncCalls, hasLength(3));
    expect(waits, hasLength(2));
  });

  test('an error collected after the first call is returned as it is',
      () async {
    const failed = IcalSyncResult(status: 'error', error: 'HTTP 404');
    final source = FakeIcalSource()..syncScript = [requested, failed];

    expect(await runner(source).syncNow('f1'), same(failed));
  });

  test('a failed fetch on the first call is retried by the next ones',
      () async {
    final source = FakeIcalSource()
      ..syncScript = [
        const IcalSyncResult(status: 'error', error: 'fetch failed: dns'),
        requested,
        ok,
      ];

    expect(await runner(source).syncNow('f1'), same(ok));
    expect(source.syncCalls, hasLength(3));
  });

  test('gives up after maxCalls and reports the sync as still pending',
      () async {
    final source = FakeIcalSource()..syncScript = [requested, pending];

    final result = await runner(source, maxCalls: 5).syncNow('f1');

    expect(result.status, 'pending');
    expect(source.syncCalls, hasLength(5));
    expect(waits, hasLength(4));
  });

  test('a failure from the source (e.g. no permission) propagates', () async {
    final source = FakeIcalSource()..syncError = const NotPermitted();

    expect(runner(source).syncNow('f1'), throwsA(isA<NotPermitted>()));
  });
}
