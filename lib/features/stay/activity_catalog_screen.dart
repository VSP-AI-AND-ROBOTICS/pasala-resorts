import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/repositories/activity_repository.dart';
import '../booking/providers.dart' show unitByIdProvider, reservationProvider;

class ActivityCatalogScreen extends ConsumerWidget {
  const ActivityCatalogScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationAsync = ref.watch(reservationProvider(reservationId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activities'),
        actions: [
          IconButton(
            tooltip: 'My bookings',
            icon: const Icon(Icons.event_available_outlined),
            onPressed: () => context.push('/my-stay/activities/bookings',
                extra: reservationId),
          ),
        ],
      ),
      body: AsyncView(
        value: reservationAsync,
        data: (reservation) {
          final unitAsync = ref.watch(unitByIdProvider(reservation.unitId));
          return AsyncView(
            value: unitAsync,
            data: (unit) => _Catalog(
              propertyId: unit.propertyId,
              reservationId: reservationId,
            ),
          );
        },
      ),
    );
  }
}

class _Catalog extends ConsumerWidget {
  const _Catalog({required this.propertyId, required this.reservationId});

  final String propertyId;
  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(activityCatalogProvider(propertyId));

    return AsyncView(
      value: activitiesAsync,
      empty: () => const EmptyState(
        icon: Icons.hiking_outlined,
        title: 'No activities are set up yet',
      ),
      data: (activities) => ListView.builder(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: activities.length,
        itemBuilder: (context, i) {
          final activity = activities[i];
          return Card(
            margin: const EdgeInsets.only(bottom: Spacing.sm),
            child: ListTile(
              title: Text(activity.name),
              subtitle: Text(activity.description ?? ''),
              trailing: Text(
                activity.pricePerPerson == 0
                    ? 'Free'
                    : '${formatInr(activity.pricePerPerson)}/person',
              ),
              onTap: () => context.push(
                '/my-stay/activities/book/${activity.id}',
                extra: (reservationId: reservationId, activity: activity),
              ),
            ),
          );
        },
      ),
    );
  }
}
