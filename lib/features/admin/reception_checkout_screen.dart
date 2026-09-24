import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/repositories/stay_repository.dart';
import '../staff/providers.dart' show allBookingsProvider;
import '../stay/checkout_screen.dart' show DeskCheckoutArgs;

/// `/admin/check-out` -- every `checked_in` guest, one tap through to the
/// same [CheckoutScreen] (`/my-stay/checkout`) a customer's own self-checkout
/// uses -- `checkout_booking` already permits staff-or-above, so this is
/// reception settling the final bill on the guest's behalf rather than a
/// separate code path.
class ReceptionCheckoutScreen extends ConsumerWidget {
  const ReceptionCheckoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final checkedInAsync = ref.watch(checkedInProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Check-Out')),
      body: AsyncView(
        value: checkedInAsync,
        onRetry: () => ref.invalidate(checkedInProvider(propertyId)),
        empty: () => const EmptyState(
          icon: Icons.logout_outlined,
          title: 'No guests currently checked in',
        ),
        data: (guests) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: guests.length,
          itemBuilder: (context, i) {
            final g = guests[i];
            return Card(
              margin: const EdgeInsets.only(bottom: Spacing.sm),
              child: ListTile(
                title: Text(g.customerName ?? 'Guest'),
                subtitle: Text(
                  '${formatDay(g.start.toLocal())} → ${formatDay(g.end.toLocal())} · '
                  '${g.guests ?? '—'} guests',
                ),
                trailing: FilledButton(
                  onPressed: () async {
                    // Desk checkout: reception records the method and
                    // reference instead of charging the guest's gateway.
                    await context.push('/my-stay/checkout',
                        extra: DeskCheckoutArgs(g.id));
                    if (context.mounted) {
                      ref.invalidate(checkedInProvider(propertyId));
                      // See the matching comment in reception_checkin_screen.dart
                      // -- the dashboard's own cards read this same list.
                      ref.invalidate(allBookingsProvider);
                    }
                  },
                  child: const Text('Check Out'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
