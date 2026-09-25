import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/repositories/listing_repository.dart';

import '../support/fake_listing_source.dart';

void main() {
  test('listingSetupProvider asks for the resort it is keyed by', () async {
    final source = FakeListingSource()
      ..setup = listingSetup(done: {SetupStep.units});
    final container = ProviderContainer(
      overrides: [listingSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final a = container.listen(listingSetupProvider('p1'), (_, _) {});
    final b = container.listen(listingSetupProvider('p2'), (_, _) {});
    addTearDown(a.close);
    addTearDown(b.close);

    final setup = await container.read(listingSetupProvider('p1').future);
    await container.read(listingSetupProvider('p2').future);

    expect(setup.doneCount, 1);
    expect(source.setupCalls, ['p1', 'p2']);
  });

  test('myListingApplicationsProvider reads through the seam', () async {
    final source = FakeListingSource()
      ..applications = [listingApplication(name: 'Green Acres')];
    final container = ProviderContainer(
      overrides: [listingSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(myListingApplicationsProvider, (_, _) {});
    addTearDown(sub.close);

    final apps = await container.read(myListingApplicationsProvider.future);

    expect(apps.single.name, 'Green Acres');
    expect(source.applicationsCalls, 1);
  });

  test('pendingListingsProvider reads through the review seam', () async {
    final source = FakeListingReviewSource()
      ..pending = [pendingListing(propertyId: 'r9')];
    final container = ProviderContainer(
      overrides: [listingReviewSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    final pending = await container.read(pendingListingsProvider.future);

    expect(pending.single.propertyId, 'r9');
    expect(source.pendingCalls, 1);
  });
}
