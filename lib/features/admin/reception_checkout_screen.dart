import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/repositories/stay_repository.dart';

/// `/admin/check-out` -- every `checked_in` guest, one tap through to the
/// same `CheckoutScreen` a customer's own self-checkout uses, in desk mode
/// at `/admin/check-out/:reservationId` -- `checkout_booking` already
/// permits staff-or-above, so this is reception settling the final bill on
/// the guest's behalf rather than a separate code path.
///
/// Check Out uses `context.go`, not `push`: go_router only puts declarative
/// locations in the browser's address bar, so a pushed checkout left the
/// URL at `/admin/check-out` and a reload lost it. The desk route is a
/// child of this one, so `go` still stacks it above the list (with a back
/// arrow). A successful checkout refetches this list itself.
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
                  // Desk checkout: reception records the method and
                  // reference instead of charging the guest's gateway.
                  onPressed: () => context.go('/admin/check-out/${g.id}'),
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
