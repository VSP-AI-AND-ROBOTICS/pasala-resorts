import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/property.dart';
import 'providers.dart';

class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);

    return AsyncView(
      value: properties,
      onRetry: () => ref.invalidate(propertiesProvider),
      empty: () => const EmptyState(
        icon: Icons.villa_outlined,
        title: 'No properties yet',
        message: 'Ask an admin to add one.',
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(propertiesProvider),
        child: ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: list.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: PropertyCard(
              property: list[i],
              onTap: () => context.go('/property/${list[i].id}'),
            ),
          ),
        ),
      ),
    );
  }
}

/// A property's header art: its first photo when one exists, otherwise a
/// tinted placeholder carrying the property's initial. Reused by
/// [PropertyCard] (16:9, inside a card) and `PropertyScreen`'s full-width
/// header, so the "broken image never shows a customer an error box" rule
/// only has to be written once.
class PropertyMedia extends StatelessWidget {
  const PropertyMedia({super.key, required this.property});

  final Property property;

  String get _initial =>
      property.name.trim().isEmpty ? '?' : property.name.trim()[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    if (property.images.isEmpty) return _PropertyPlaceholder(initial: _initial);

    return Image.network(
      property.images.first,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _PropertyLoadingBox();
      },
      // A broken or unreachable URL must never surface Flutter's red error
      // box to a customer -- it falls back to the same tinted placeholder
      // used when there is no image at all.
      errorBuilder: (context, error, stackTrace) =>
          _PropertyPlaceholder(initial: _initial),
    );
  }
}

class _PropertyPlaceholder extends StatelessWidget {
  const _PropertyPlaceholder({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PropertyLoadingBox extends StatelessWidget {
  const _PropertyLoadingBox();

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
}

/// Up to four amenity chips styled as metadata rather than actions, with a
/// `+N` chip absorbing the rest. Amenities never appear elsewhere on the
/// card, so styling this once here is enough.
class AmenityWrap extends StatelessWidget {
  const AmenityWrap({super.key, required this.amenities, this.max = 4});

  final List<String> amenities;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (amenities.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final shown = amenities.take(max).toList();
    final overflow = amenities.length - shown.length;

    Widget metaChip(String label) => Chip(
          label: Text(label),
          labelStyle: labelStyle,
          backgroundColor: scheme.surfaceContainerHigh,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
        );

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      children: [
        for (final a in shown) metaChip(a),
        if (overflow > 0) metaChip('+$overflow'),
      ],
    );
  }
}

/// The tallest a card's media area is allowed to get. A plain 16:9 area
/// scales with the card's width, which is fine on a phone but turns into a
/// wall of image on a wide desktop list -- capping the height keeps the card
/// proportioned like a card instead of a banner while staying 16:9 (or
/// narrower) on anything phone-sized.
const double _cardMediaMaxHeight = 220;

class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.property, this.onTap});

  final Property property;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final height = (constraints.maxWidth * 9 / 16)
                    .clamp(0, _cardMediaMaxHeight)
                    .toDouble();
                return SizedBox(
                  width: double.infinity,
                  height: height,
                  child: PropertyMedia(property: property),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(property.name, style: textTheme.titleLarge),
                  if (property.address != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      property.address!,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: Spacing.sm),
                  AmenityWrap(amenities: property.amenities),
                  const SizedBox(height: Spacing.sm),
                  // Belt-and-suspenders: Property.fromJson already normalises
                  // Postgres's `HH:mm:ss` down to `HH:mm`, but this display
                  // line calls normalizeTime again so a directly-constructed
                  // Property (as in tests, or a future caller) can never leak
                  // ":ss" onto the card.
                  Text(
                    'Check-in ${Property.normalizeTime(property.checkInTime)} · '
                    'Check-out ${Property.normalizeTime(property.checkOutTime)}',
                    style:
                        textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
