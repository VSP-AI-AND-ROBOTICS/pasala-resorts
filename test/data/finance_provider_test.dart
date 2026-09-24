import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/providers.dart';

import '../support/fake_finance_source.dart';

void main() {
  test('every finance provider reads the resort it is keyed by', () async {
    final source = FakeFinanceSource();
    final container = ProviderContainer(
      overrides: [financeSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final filter = (
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 31),
      propertyId: 'p1',
    );
    final subs = <ProviderSubscription<Object?>>[
      container.listen(financeSummaryProvider('p1'), (_, _) {}),
      container.listen(collectionsProvider(filter), (_, _) {}),
      container.listen(ledgerProvider(filter), (_, _) {}),
      container.listen(settlementsProvider(filter), (_, _) {}),
    ];
    addTearDown(() {
      for (final s in subs) {
        s.close();
      }
    });

    await container.read(financeSummaryProvider('p1').future);
    await container.read(collectionsProvider(filter).future);
    await container.read(ledgerProvider(filter).future);
    await container.read(settlementsProvider(filter).future);

    expect(source.summaryCalls, ['p1']);
    expect(source.collectionsCalls, [filter]);
    expect(source.ledgerCalls, [filter]);
    expect(source.settlementsCalls, [filter]);
  });

  test(
    'switching resort asks for the other resort, not a cached one',
    () async {
      final source = FakeFinanceSource();
      final container = ProviderContainer(
        overrides: [financeSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);
      final a = container.listen(financeSummaryProvider('p1'), (_, _) {});
      final b = container.listen(financeSummaryProvider('p2'), (_, _) {});
      addTearDown(a.close);
      addTearDown(b.close);

      await container.read(financeSummaryProvider('p1').future);
      await container.read(financeSummaryProvider('p2').future);

      expect(source.summaryCalls, ['p1', 'p2']);
    },
  );
}
