import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/reservation.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/stay_repository.dart';

/// The hub every "in-stay" screen hangs off of -- resolves
/// [currentStayProvider] (a `checked_in` stay if there is one, otherwise the
/// soonest-upcoming `confirmed` one) and shows a tile per capability. A
/// customer with neither active/upcoming stay falls through to
/// [_PostCheckout], which checks for a completed stay still awaiting a
/// review before finally showing the plain empty state -- matching this
/// app's preference for data-driven empty states over hiding the nav tab
/// entirely.
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
          if (stay == null) return const _PostCheckout();
          return _Hub(reservation: stay);
        },
      ),
    );
  }
}

const _noStayEmptyState = EmptyState(
  icon: Icons.holiday_village_outlined,
  title: 'No active or upcoming stay',
  message:
      'Once you have a confirmed booking, everything for your stay will '
      'show up here.',
);

/// Checks for a `checked_out` stay that still has no review, and shows a
/// "how was your stay?" prompt for it instead of the plain empty state --
/// once that review is submitted, [reviewForReservationProvider] resolves
/// non-null and this falls back to the ordinary no-active-stay message.
class _PostCheckout extends ConsumerWidget {
  const _PostCheckout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkedOutAsync = ref.watch(mostRecentCheckedOutProvider);

    return AsyncView(
      value: checkedOutAsync,
      onRetry: () => ref.invalidate(mostRecentCheckedOutProvider),
      data: (reservation) {
        if (reservation == null) return _noStayEmptyState;
        return _ReviewPrompt(reservation: reservation);
      },
    );
  }
}

class _ReviewPrompt extends ConsumerWidget {
  const _ReviewPrompt({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(reviewForReservationProvider(reservation.id));

    return AsyncView(
      value: reviewAsync,
      onRetry: () =>
          ref.invalidate(reviewForReservationProvider(reservation.id)),
      data: (review) {
        if (review != null) return _noStayEmptyState;

        final textTheme = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rate_rounded, size: 48, color: Colors.amber),
                const SizedBox(height: Spacing.md),
                Text('Stay Completed', style: textTheme.titleLarge),
                const SizedBox(height: Spacing.xs),
                Text(
                  'How was your stay?',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.lg),
                FilledButton.icon(
                  key: const Key('write-review-button'),
                  onPressed: () =>
                      context.push('/my-stay/review/${reservation.id}'),
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Write a Review'),
                ),
              ],
            ),
          ),
        );
      },
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
                      // Only present when currentStay's query embedded
                      // `properties(name)` -- tells a guest with stays at
                      // more than one resort which one this hub is for.
                      if (reservation.resortName case final resortName?)
                        Text(
                          resortName,
                          style: textTheme.labelLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
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
