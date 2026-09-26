import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/resort_search.dart';
import 'package:pasala/data/repositories/resort_search_repository.dart';

import '../support/fake_resort_search_source.dart';

void main() {
  test(
    'resortSearchProvider asks the source for the query it is keyed by',
    () async {
      final source = FakeResortSearchSource()
        ..results = [searchResult(id: 'r1')];
      final container = ProviderContainer(
        overrides: [resortSearchSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);
      const query = ResortSearchQuery(text: 'lake', sort: ResortSort.rating);
      final sub = container.listen(resortSearchProvider(query), (_, _) {});
      addTearDown(sub.close);

      final rows = await container.read(resortSearchProvider(query).future);

      expect(rows.single.property.id, 'r1');
      expect(source.calls, [query]);
    },
  );

  test('an equal query built separately reuses the same search', () async {
    final source = FakeResortSearchSource();
    final container = ProviderContainer(
      overrides: [resortSearchSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final first = ResortSearchQuery(amenities: List.of(['Pool']));
    final second = ResortSearchQuery(amenities: List.of(['Pool']));
    final sub = container.listen(resortSearchProvider(first), (_, _) {});
    addTearDown(sub.close);

    await container.read(resortSearchProvider(first).future);
    await container.read(resortSearchProvider(second).future);

    expect(source.calls, hasLength(1));
  });
}
