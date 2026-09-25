import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/app_user.dart';
import '../data/models/resort_membership.dart';
import '../data/repositories/auth_repository.dart';
import 'router.dart' show landingPathFor;

const _rememberedResortKey = 'current_resort_id';

/// Pure resolution used by [CurrentResort] and by tests: null user -> null;
/// a remembered id matching a membership -> that membership; exactly one
/// membership -> it; otherwise null (a multi-resort user who hasn't picked
/// yet). A remembered id with no matching membership -- the user was
/// removed from that resort since it was last chosen -- is ignored rather
/// than used (Review Focus #4).
ResortMembership? resolveCurrentResort(AppUser? user, String? rememberedId) {
  if (user == null) return null;
  if (rememberedId != null) {
    final remembered = user.membershipFor(rememberedId);
    if (remembered != null) return remembered;
  }
  if (user.memberships.length == 1) return user.memberships.single;
  return null;
}

/// Resolves [user]'s current resort straight from `shared_preferences`,
/// for the two call sites (`login_screen.dart`, `signup_screen.dart`) that
/// navigate immediately after sign-in/sign-up using the just-returned
/// [AppUser] rather than `currentResortProvider`'s own state -- which
/// watches `currentUserProvider`, whose stream hasn't necessarily caught
/// up with the fresh session at that exact moment.
Future<ResortMembership?> loadCurrentResortFor(AppUser user) async {
  final prefs = await SharedPreferences.getInstance();
  return resolveCurrentResort(user, prefs.getString(_rememberedResortKey));
}

/// The resort the signed-in staff member is working in, or null for
/// customers, platform admins, and users with 2+ memberships who have not
/// picked one yet.
///
/// [build] resolves synchronously off whatever remembered id has been
/// loaded from `shared_preferences` so far (`null` on the very first
/// build of a cold app) and kicks off the async load in the background;
/// when that load completes it re-resolves and, if the outcome changed,
/// updates [state] -- so a remembered single choice still applies once
/// storage answers, without ever blocking navigation on it.
class CurrentResort extends Notifier<ResortMembership?> {
  String? _rememberedId;
  bool _loadStarted = false;

  /// Bumped by every call that changes [_rememberedId]/[state] on its own
  /// authority ([select], [clear], and each fresh [_loadRemembered] call).
  /// [_loadRemembered] captures it before awaiting `SharedPreferences` and
  /// checks it again after: if it no longer matches, an explicit [select]
  /// or [clear] (or a newer load) already decided the outcome in the
  /// meantime, so this stale continuation applies nothing instead of
  /// clobbering it -- otherwise a `select` made right after a cold-start
  /// `build()` could be overwritten a moment later by that first load
  /// finally resolving.
  int _generation = 0;

  @override
  ResortMembership? build() {
    final user = ref.watch(currentUserProvider).value;
    if (!_loadStarted) {
      _loadStarted = true;
      _loadRemembered();
    }
    return resolveCurrentResort(user, _rememberedId);
  }

  Future<void> _loadRemembered() async {
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation) return;
    _rememberedId = prefs.getString(_rememberedResortKey);
    final user = ref.read(currentUserProvider).value;
    final resolved = resolveCurrentResort(user, _rememberedId);
    if (resolved != state) state = resolved;
  }

  /// Picks [propertyId] as the current resort -- the user must already
  /// hold a membership there (the choose-resort screen and the resort
  /// switcher only ever offer a signed-in user their own memberships).
  /// Persists the choice to `shared_preferences` so it survives a restart.
  Future<void> select(String propertyId) async {
    final user = ref.read(currentUserProvider).value;
    final membership = user?.membershipFor(propertyId);
    if (membership == null) return;
    _generation++;
    _rememberedId = propertyId;
    state = membership;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedResortKey, propertyId);
  }

  /// Forgets the current resort, both in memory and in `shared_preferences`.
  Future<void> clear() async {
    _generation++;
    _rememberedId = null;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberedResortKey);
  }
}

final currentResortProvider =
    NotifierProvider<CurrentResort, ResortMembership?>(CurrentResort.new);

/// Called wherever a `NotAMember` failure surfaces: the user lost access to
/// the current resort (removed, or the resort was archived). Forget the
/// pick, re-fetch the user, and -- given the app's [router] -- send them to
/// `landingPathFor` the re-fetched memberships.
///
/// The navigation is explicit because the router is built once and only
/// re-checks the current page: clearing the pick moves a user off a resort
/// page to `/choose-resort`, or `/404` with a single (now stale)
/// membership, and nothing there moves them on once the re-fetch lands.
/// A user the re-fetch finds signed out is left to the router's own
/// redirect to `/login`.
Future<void> handleResortAccessLost(
  ProviderContainer container, {
  GoRouter? router,
}) async {
  await container.read(currentResortProvider.notifier).clear();
  container.invalidate(currentUserProvider);
  if (router == null) return;
  final user = await container.read(currentUserProvider.future);
  if (user == null) return;
  router.go(landingPathFor(user, container.read(currentResortProvider)));
}
