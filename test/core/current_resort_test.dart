import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const a = ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner);
const b = ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff);

void main() {
  test('single membership is selected automatically', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [a]);
    expect(resolveCurrentResort(u, null), a);
  });

  test('two memberships and nothing remembered: no resort yet', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [a, b]);
    expect(resolveCurrentResort(u, null), isNull);
  });

  test('remembered resort is used when still a member', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [a, b]);
    expect(resolveCurrentResort(u, 'b'), b);
  });

  test('remembered resort the user was removed from is discarded', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [a, b]);
    expect(resolveCurrentResort(u, 'gone'), isNull);
    const single = AppUser(id: 'u', email: 'e', memberships: [a]);
    expect(resolveCurrentResort(single, 'gone'), a);
  });

  test(
      'handleResortAccessLost forgets the current resort and re-fetches the user',
      () async {
    SharedPreferences.setMockInitialValues({});
    const u = AppUser(id: 'u', email: 'e', memberships: [a, b]);
    var fetches = 0;
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) {
        fetches++;
        return Stream.value(u);
      }),
    ]);
    addTearDown(container.dispose);
    // Every provider here is auto-dispose by default (Riverpod 3): without
    // an active listener, a bare `container.read` can dispose the element
    // again before its stream even emits. This keeps the whole chain
    // (currentResortProvider -> currentUserProvider) alive for the test.
    container.listen(currentResortProvider, (_, _) {});

    // Let the overridden `currentUserProvider` stream emit its first value
    // before selecting -- `select` reads it synchronously and a fresh
    // `StreamProvider` starts out loading (`.value == null`) until then.
    await container.read(currentUserProvider.future);
    await container.read(currentResortProvider.notifier).select('b');
    expect(container.read(currentResortProvider), b);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('current_resort_id'), 'b');
    final fetchesBeforeLoss = fetches;

    await handleResortAccessLost(container);

    expect(container.read(currentResortProvider), isNull);
    expect(prefs.getString('current_resort_id'), isNull);
    expect(fetches, greaterThan(fetchesBeforeLoss));
  });
}
