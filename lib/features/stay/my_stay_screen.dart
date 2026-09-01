import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/reservation.dart';
import '../../data/repositories/stay_repository.dart';

/// The hub every "in-stay" screen hangs off of -- resolves
/// [currentStayProvider] (a `checked_in` stay if there is one, otherwise the
/// soonest-upcoming `confirmed` one) and shows a tile per capability. A
/// customer with neither sees a plain empty state rather than a dead end,
/// matching this app's preference for data-driven empty states over hiding
/// the nav tab entirely.
class MyStayScreen extends ConsumerWidget {
  const MyStayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stayAsync = ref.watch(currentStayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Stay')),
      body: AsyncView(
        value: stayAsync,
        onRetry: () => ref.invalidate(currentStayProvider),
        data: (stay) {
          if (stay == null) {
            return const EmptyState(
              icon: Icons.holiday_village_outlined,
              title: 'No active or upcoming stay',
              message: 'Once you have a confirmed booking, everything for '
                  'your stay will show up here.',
            );
          }
          return _Hub(reservation: stay);
        },
      ),
    );
  }
}

class _Hub extends StatelessWidget {
  const _Hub({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final checkedIn = reservation.status == ReservationStatus.checkedIn;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Chip(
                        label: Text(checkedIn ? 'Checked in' : 'Confirmed'),
                        backgroundColor: checkedIn
                            ? scheme.primaryContainer
                            : scheme.tertiaryContainer,
                        side: BorderSide.none,
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        '${formatDay(reservation.start.toLocal())} → '
                        '${formatDay(reservation.end.toLocal())}',
                        style: textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(Spacing.xs),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
                  ),
                  child: QrImageView(data: reservation.id, size: 64),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        _Tile(
          icon: Icons.restaurant_outlined,
          label: 'Order Food',
          onTap: () => context.push('/my-stay/food', extra: reservation.id),
        ),
        _Tile(
          icon: Icons.hiking_outlined,
          label: 'Activities',
          onTap: () =>
              context.push('/my-stay/activities', extra: reservation.id),
        ),
        _Tile(
          icon: Icons.room_service_outlined,
          label: 'Service Requests',
          onTap: () => context.push('/my-stay/service-requests',
              extra: reservation.id),
        ),
        _Tile(
          icon: Icons.build_outlined,
          label: 'Report an Issue',
          onTap: () =>
              context.push('/my-stay/maintenance', extra: reservation.id),
        ),
        _Tile(
          icon: Icons.receipt_long_outlined,
          label: 'Current Charges',
          onTap: () =>
              context.push('/my-stay/charges', extra: reservation.id),
        ),
        if (checkedIn)
          _Tile(
            icon: Icons.door_front_door_outlined,
            label: 'Checkout',
            onTap: () =>
                context.push('/my-stay/checkout', extra: reservation.id),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: Spacing.sm),
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
