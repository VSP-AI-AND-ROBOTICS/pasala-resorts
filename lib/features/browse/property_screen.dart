import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/unit.dart';
import 'browse_screen.dart' show AmenityWrap, PropertyMedia;
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
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return AsyncView(
      value: property,
      onRetry: () => ref.invalidate(propertyProvider(propertyId)),
      data: (p) => ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: PropertyMedia(property: p),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: textTheme.headlineMedium),
                if (p.address != null) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    p.address!,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (p.description != null) ...[
                  const SizedBox(height: Spacing.md),
                  Text(p.description!, style: textTheme.bodyLarge),
                ],
                const SizedBox(height: Spacing.md),
                AmenityWrap(amenities: p.amenities, max: p.amenities.length),
              ],
            ),
          ),
          const SectionHeader(title: 'Units'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, 0, Spacing.md, Spacing.lg),
            child: AsyncView(
              value: units,
              onRetry: () => ref.invalidate(unitsProvider(propertyId)),
              empty: () => const EmptyState(
                icon: Icons.bed_outlined,
                title: 'No units yet',
                message: 'Ask an admin to add one.',
              ),
              data: (list) => Column(
                children: [
                  for (final unit in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: UnitCard(
                        unit: unit,
                        onTap: () => context.go('/book/${unit.id}'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One unit's card on the property page: name, capacity, and booking mode
/// as metadata rather than a plain [ListTile] row.
class UnitCard extends StatelessWidget {
  const UnitCard({super.key, required this.unit, this.onTap});

  final Unit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(unit.name, style: textTheme.titleMedium),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Sleeps ${unit.capacityBase}–${unit.capacityMax}',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(bookingModeLabel(unit.bookingMode)),
                backgroundColor: scheme.surfaceContainerHigh,
                side: BorderSide.none,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
