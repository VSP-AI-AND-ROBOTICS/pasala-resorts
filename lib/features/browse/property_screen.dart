import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/property.dart';
import '../../data/models/unit.dart';
import '../booking/booking_screen.dart';
import 'browse_screen.dart' show AmenityWrap, PropertyMedia;
import 'providers.dart';

/// Label shown on a unit's booking-mode chip. Pure so it can be tested
/// without touching the network.
String bookingModeLabel(BookingMode mode) => switch (mode) {
      BookingMode.nightly => 'Nightly',
      BookingMode.slot => 'Slots',
      BookingMode.both => 'Nightly or slots',
    };

/// Every bundled farmhouse photo, shown as a swipeable gallery on the
/// property page. Deliberately separate from [Property.images] (the
/// database-backed network photo `PropertyMedia` renders) -- these are
/// bundled app assets, not per-property data, so the same 8 photos show on
/// every property page regardless of what that property's own `images`
/// column holds.
const _galleryPhotos = [
  AppAssets.heroDayAerial,
  AppAssets.heroNightAerial,
  AppAssets.cottagesPoolRow,
  AppAssets.cottagesDallasVegas,
  AppAssets.cottagesBostonDetroit,
  AppAssets.eventStringLights,
  AppAssets.facadeDaytime,
  AppAssets.patioFirepitNight,
];

/// A swipeable gallery whose first page is the property's own (network or
/// placeholder) photo -- carrying the same `Hero` tag [PropertyCard] uses,
/// so the shared-element transition from Browse still lands here -- followed
/// by one page per bundled farmhouse photo, with dot indicators showing
/// position.
class PropertyGallery extends StatefulWidget {
  const PropertyGallery({super.key, required this.property});

  final Property property;

  @override
  State<PropertyGallery> createState() => _PropertyGalleryState();
}

class _PropertyGalleryState extends State<PropertyGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = 1 + _galleryPhotos.length;
    return SizedBox(
      height: 280,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: pageCount,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Hero(
                  tag: 'property-media-${widget.property.id}',
                  child: PropertyMedia(property: widget.property),
                );
              }
              return Image.asset(_galleryPhotos[i - 1], fit: BoxFit.cover);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < pageCount; i++)
                  AnimatedContainer(
                    duration: PasalaTokens.motionFast,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 10 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
      // A plain SingleChildScrollView, not a ListView: the embedded
      // booking flow's availability calendar has its own shrink-wrapped
      // GridView, which breaks when nested inside a ListView's sliver
      // machinery (see `booking_screen.dart`'s own note on this). There
      // must be exactly one scrollable ancestor between here and the
      // calendar.
      data: (p) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PropertyGallery(property: p),
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
                // Exactly one bookable unit is assumed here -- `.single`
                // throws if a second unit is ever added, deliberately (see
                // spec section 7): this screen shows the booking flow
                // inline for one unit, and does not attempt to fall back
                // to a unit-picker if that assumption stops holding.
                data: (list) => BookingScreen(unitId: list.single.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
