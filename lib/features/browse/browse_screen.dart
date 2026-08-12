import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../core/widgets/staggered_fade_in.dart';
import '../../data/models/property.dart';
import 'providers.dart';

class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);
    final wide = MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;

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
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _BrowseHero(wide: wide)),
            if (wide)
              SliverPadding(
                padding: const EdgeInsets.all(Spacing.md),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: Spacing.md,
                    crossAxisSpacing: Spacing.md,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => StaggeredFadeIn(
                      key: ValueKey(list[i].id),
                      index: i,
                      child: PropertyCard(
                        property: list[i],
                        onTap: () => context.go('/property/${list[i].id}'),
                      ),
                    ),
                    childCount: list.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(Spacing.md),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: StaggeredFadeIn(
                        key: ValueKey(list[i].id),
                        index: i,
                        child: PropertyCard(
                          property: list[i],
                          onTap: () => context.go('/property/${list[i].id}'),
                        ),
                      ),
                    ),
                    childCount: list.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrowseHero extends StatelessWidget {
  const _BrowseHero({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Taller on wide/web layouts so the hero doesn't look like a thin
      // strip on a desktop-width browser window (spec section 7).
      height: wide ? 280 : 200,
      child: HeroBackdrop(
        imageAsset: AppAssets.heroDayAerial,
        scrimOpacity: 0.35,
        child: const Padding(
          padding: EdgeInsets.all(Spacing.lg),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              'Discover your stay',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: PasalaTokens.displayWeight,
                letterSpacing: PasalaTokens.displayLetterSpacing,
              ),
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
    // Without a semantics label a screen reader announces either nothing
    // (the Image.network path) or just the bare initial letter (the
    // placeholder path) -- neither tells a screen-reader user which
    // property this card is for. Both paths get the property's name plus a
    // short descriptor instead, applied once here rather than inside
    // [_PropertyPlaceholder] itself -- that widget is also reused as
    // Image.network's errorBuilder result, and wrapping it there too would
    // nest a second, conflicting Semantics node under this one whenever a
    // photo URL fails to load.
    if (property.images.isEmpty) {
      return Semantics(
        label: '${property.name}, no photo available',
        image: true,
        // Otherwise the placeholder's own "initial letter" Text widget
        // merges its literal text ("P") into this label instead of being
        // silenced by it, and a screen reader reads both.
        excludeSemantics: true,
        child: _PropertyPlaceholder(initial: _initial),
      );
    }

    return Semantics(
      label: '${property.name} property photo',
      image: true,
      excludeSemantics: true,
      child: Image.network(
        property.images.first,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // This widget already supplies the semantics above; without this,
        // Image.network would additionally wrap itself in its own
        // semantics node (unlabelled, since no `semanticLabel` is passed),
        // producing a redundant nested image node either way.
        excludeFromSemantics: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const _PropertyLoadingBox();
        },
        // A broken or unreachable URL must never surface Flutter's red error
        // box to a customer -- it falls back to the same tinted placeholder
        // used when there is no image at all.
        errorBuilder: (context, error, stackTrace) =>
            _PropertyPlaceholder(initial: _initial),
      ),
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

class PropertyCard extends StatefulWidget {
  const PropertyCard({super.key, required this.property, this.onTap});

  final Property property;
  final VoidCallback? onTap;

  @override
  State<PropertyCard> createState() => _PropertyCardState();
}

class _PropertyCardState extends State<PropertyCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final property = widget.property;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.02 : 1.0,
        duration: PasalaTokens.motionFast,
        curve: Curves.easeOut,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
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
                      child: Hero(
                        tag: 'property-media-${property.id}',
                        child: PropertyMedia(property: property),
                      ),
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
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
