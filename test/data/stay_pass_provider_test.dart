import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';

import '../support/fake_stay_pass_source.dart';

void main() {
  test('stayPassProvider asks once per booking and keeps the pass', () async {
    final fake = FakeStayPassSource()..tokens['res-1'] = 'rh1.abc';
    final container = ProviderContainer(
      overrides: [stayPassSourceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(await container.read(stayPassProvider('res-1').future), 'rh1.abc');
    expect(await container.read(stayPassProvider('res-1').future), 'rh1.abc');
    expect(fake.issueCalls, ['res-1']);
  });

  test('each booking has its own pass', () async {
    final fake = FakeStayPassSource();
    final container = ProviderContainer(
      overrides: [stayPassSourceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(await container.read(stayPassProvider('a').future), 'rh1.fake-a');
    expect(await container.read(stayPassProvider('b').future), 'rh1.fake-b');
  });

  test('a failed issue surfaces the typed failure', () async {
    final fake = FakeStayPassSource()..issueError = const NetworkFailure();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [stayPassSourceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(stayPassProvider('res-1').future),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
