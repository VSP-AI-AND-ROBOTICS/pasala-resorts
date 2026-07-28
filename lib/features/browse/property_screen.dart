import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/failure_view.dart';
import '../../data/models/unit.dart';
import 'providers.dart';

/// Label shown on a unit's booking-mode chip. Pure so it can be tested
/// without touching the network.
String bookingModeLabel(BookingMode mode) => switch (mode) {
      BookingMode.nightly => 'Nightly',
      BookingMode.slot => 'Slots',
      BookingMode.both => 'Nightly or slots',
    };

class PropertyScreen extends ConsumerWidget {
  const PropertyScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final property = ref.watch(propertyProvider(propertyId));
    final units = ref.watch(unitsProvider(propertyId));

    return property.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FailureView(
        error: e,
        onRetry: () => ref.invalidate(propertyProvider(propertyId)),
      ),
      data: (p) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(p.name, style: Theme.of(context).textTheme.headlineSmall),
          if (p.description != null) ...[
            const SizedBox(height: 8),
            Text(p.description!),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final a in p.amenities) Chip(label: Text(a)),
            ],
          ),
          const SizedBox(height: 24),
          Text('Units', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          units.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: FailureView(
                error: e,
                onRetry: () => ref.invalidate(unitsProvider(propertyId)),
              ),
            ),
            data: (list) => Column(
              children: [
                for (final unit in list)
                  ListTile(
                    title: Text(unit.name),
                    subtitle: Text(
                      'Sleeps ${unit.capacityBase}–${unit.capacityMax}',
                    ),
                    trailing: Chip(
                      label: Text(bookingModeLabel(unit.bookingMode)),
                    ),
                    onTap: () => context.go('/book/${unit.id}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
