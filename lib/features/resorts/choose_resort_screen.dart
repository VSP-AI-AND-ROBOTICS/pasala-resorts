import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/resort_membership.dart';
import '../../data/repositories/auth_repository.dart';

/// `/choose-resort` -- shown to a signed-in user with 2+ resort
/// memberships who hasn't picked one yet (see `resolveCurrentResort` and
/// `redirectFor`). Lists each membership's resort name and role label;
/// picking one calls `currentResortProvider.notifier.select`, and the
/// router's own redirect (which watches `currentResortProvider`) carries
/// the user onward from there via `landingPathFor`, so this screen never
/// navigates itself.
class ChooseResortScreen extends ConsumerWidget {
  const ChooseResortScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final memberships = user?.memberships ?? const <ResortMembership>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a resort')),
      body: ListView.separated(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: memberships.length,
        separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
        itemBuilder: (context, i) {
          final membership = memberships[i];
          return Card(
            child: ListTile(
              key: Key('choose-resort-${membership.propertyId}'),
              leading: const Icon(Icons.apartment_outlined),
              title: Text(membership.resortName),
              subtitle: Text(resortRoleLabel(membership.role)),
              onTap: () => ref
                  .read(currentResortProvider.notifier)
                  .select(membership.propertyId),
            ),
          );
        },
      ),
    );
  }
}
