import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/property.dart';
import '../../data/models/review.dart';
import '../../data/models/unit.dart';
import '../../data/repositories/review_repository.dart';
import '../booking/booking_screen.dart';
import 'browse_screen.dart' show AmenityWrap;
import 'gallery_viewer_screen.dart';
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
/// database-backed network photo `PropertyMedia` renders, used elsewhere by
/// `PropertyCard`) -- these are bundled app assets, not per-property data,
/// so the same 8 photos show on every property page regardless of what that
/// property's own `images` column holds. The cinematic night aerial leads
/// (it's the strongest shot), rather than following alphabetical/upload
/// order.
const _galleryPhotos = [
  AppAssets.heroNightAerial,
  AppAssets.heroDayAerial,
  AppAssets.cottagesPoolRow,
  AppAssets.cottagesDallasVegas,
  AppAssets.cottagesBostonDetroit,
  AppAssets.eventStringLights,
  AppAssets.facadeDaytime,
  AppAssets.patioFirepitNight,
];

/// A swipeable gallery of the bundled farmhouse photos, with dot indicators
/// showing position. Does not render the property's own database-backed
/// photo at all -- with no `images` set on the seeded property, that page
/// only ever showed the tinted-placeholder fallback, not a real photo, so
/// it added a dead first page rather than useful content.
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
    final pageCount = _galleryPhotos.length;
    return SizedBox(
      height: 280,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: pageCount,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) =>
                Image.asset(_galleryPhotos[i], fit: BoxFit.cover),
          ),
          Positioned(
            top: Spacing.md,
            right: Spacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '${_page + 1} / $pageCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // A single Column, not two independently `bottomCenter`-aligned
          // Stack children -- Stack positions each child by [alignment]
          // on its own, so a button and the dot row as separate children
          // would land on top of each other instead of stacking.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: OutlinedButton.icon(
                  key: const Key('view-gallery-button'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GalleryViewerScreen(
                        photos: _galleryPhotos,
                        initialPage: _page,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('View Gallery'),
                ),
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
                    InkWell(
                      borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
                      onTap: () async {
                        final query = Uri.encodeComponent('${p.name}, ${p.address}');
                        final mapsUrl = Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=$query',
                        );
                        // No canLaunchUrl gate: on Android 11+ it returns
                        // false for https unless the manifest declares a
                        // matching <queries> entry, making the tap a silent
                        // no-op.
                        await launchUrl(mapsUrl,
                            mode: LaunchMode.externalApplication);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 18, color: scheme.primary),
                            const SizedBox(width: Spacing.xs),
                            Flexible(
                              child: Text(
                                p.address!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.primary,
                                  decoration: TextDecoration.underline,
                                  decorationColor:
                                      scheme.primary.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                            const SizedBox(width: Spacing.xs),
                            Icon(Icons.open_in_new,
                                size: 14, color: scheme.primary),
                          ],
                        ),
                      ),
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
                // One unit books inline exactly as before; two or more get
                // a picker above the same inline booking flow (see
                // [_UnitBooking]) -- a multi-unit resort must not throw.
                data: (list) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _UnitBooking(units: list),
                    const SizedBox(height: Spacing.xl),
                    const _ExperiencesSection(),
                    const SizedBox(height: Spacing.xl),
                    _AboutSection(property: p),
                    const SizedBox(height: Spacing.lg),
                    _LocationSection(property: p),
                    const SizedBox(height: Spacing.lg),
                    _ReviewsSection(propertyId: p.id),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bookable part of the property page: which unit, how many it sleeps,
/// and the inline [BookingScreen] for it. A single-unit resort shows no
/// picker at all -- just that unit's booking flow, as it always has. With
/// two or more units, a row of choice chips (one per unit, first selected
/// by default) picks which unit the flow below books; the [BookingScreen]
/// is keyed by unit id so switching units starts a fresh selection rather
/// than carrying one unit's dates/quote/hold over to another.
class _UnitBooking extends StatefulWidget {
  const _UnitBooking({required this.units});

  /// Never empty -- [AsyncView]'s `empty:` handles that case.
  final List<Unit> units;

  @override
  State<_UnitBooking> createState() => _UnitBookingState();
}

class _UnitBookingState extends State<_UnitBooking> {
  String? _selectedId;

  Unit get _selected => widget.units.firstWhere(
        (u) => u.id == _selectedId,
        orElse: () => widget.units.first,
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final unit = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.units.length > 1) ...[
          Text('Choose your stay', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          Wrap(
            key: const Key('unit-picker'),
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final u in widget.units)
                ChoiceChip(
                  key: Key('unit-choice-${u.id}'),
                  label: Text(u.name),
                  selected: u.id == unit.id,
                  onSelected: (_) => setState(() => _selectedId = u.id),
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
        ],
        Row(
          children: [
            Icon(Icons.people_alt_outlined,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: Spacing.xs),
            Text.rich(
              TextSpan(
                style: textTheme.bodyMedium,
                children: [
                  const TextSpan(text: 'Sleeps '),
                  TextSpan(
                    text: '${unit.capacityBase}–${unit.capacityMax}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' Guests'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        BookingScreen(key: ValueKey(unit.id), unitId: unit.id),
      ],
    );
  }
}

/// One tile in the [_ExperiencesSection] row: a bundled photo (the closest
/// real match this property has for the label -- there is no dedicated
/// "Games" or "Outdoor Fun" photo among the bundled assets, so those two
/// reuse a general exterior shot) with its label overlaid.
typedef _ExperienceTile = ({String label, String photo});

const _experienceTiles = <_ExperienceTile>[
  (label: 'Pool', photo: AppAssets.cottagesPoolRow),
  (label: 'Bonfire', photo: AppAssets.patioFirepitNight),
  (label: 'Games', photo: AppAssets.facadeDaytime),
  (label: 'Outdoor Fun', photo: AppAssets.eventStringLights),
];

/// A decorative row of on-site experiences. Deliberately not tappable --
/// real activity booking only exists once a stay is `checked_in` (see
/// `lib/features/stay/activity_catalog_screen.dart`), and this screen has
/// no active stay to book against yet, so nothing here should look like a
/// working link to it.
class _ExperiencesSection extends StatelessWidget {
  const _ExperiencesSection();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star, size: 20, color: scheme.primary),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text('Experiences', style: textTheme.titleMedium),
            ),
            Text(
              'View All',
              style: textTheme.labelLarge?.copyWith(color: scheme.primary),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.primary),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _experienceTiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: Spacing.sm),
            itemBuilder: (context, i) {
              final tile = _experienceTiles[i];
              return ClipRRect(
                borderRadius: BorderRadius.circular(PasalaTokens.radiusMd),
                child: SizedBox(
                  width: 130,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(tile.photo, fit: BoxFit.cover),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: Spacing.xs,
                        bottom: Spacing.xs,
                        child: Text(
                          tile.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A short, tap-to-expand blurb about the farmhouse. Hardcoded rather than
/// a new `properties` column: this app already treats bundled marketing
/// copy for its one property as static content, the same way the gallery
/// photos above are bundled assets rather than database rows (see
/// `_galleryPhotos`'s own doc comment).
const _aboutBlurb = 'Escape the city and enjoy a peaceful stay surrounded '
    'by nature. Perfect for family gatherings, celebrations and relaxation.';

class _AboutSection extends StatefulWidget {
  const _AboutSection({required this.property});

  final Property property;

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      key: const Key('about-farmhouse-toggle'),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: scheme.primary),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child:
                    Text('About the Farmhouse', style: textTheme.titleMedium),
              ),
              Icon(_expanded ? Icons.expand_less : Icons.chevron_right,
                  color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            _aboutBlurb,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style:
                textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The full postal address, including the Plus Code and pincode -- shown
/// here for display. The property header above shows `property.address`,
/// a shorter version for display alongside the name; this section always
/// shows the full address.
const _fullAddress =
    'HP7F+7FF, Keesara - Bommalaramaram Rd, Rangapuram, Telangana 508126';

/// The property's actual Google Maps listing (Customer ID), taken from the
/// real "PASALA RESORTS" business URL -- this opens the verified listing
/// itself (name, photos, reviews) rather than a text-search guess, so it
/// can never resolve to a nearby-but-wrong pin the way a text query can.
const _mapsCid = '2274879085776535515';

/// Address + a link out to the device's default maps app. No in-app map
/// and no new location data -- the address is already a plain string, so
/// a maps search URL is the entire integration.
class _LocationSection extends StatelessWidget {
  const _LocationSection({required this.property});

  final Property property;

  Future<void> _openMap() async {
    final uri = Uri.https('www.google.com', '/maps', {'cid': _mapsCid});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.location_on_outlined, size: 20, color: scheme.primary),
        const SizedBox(width: Spacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Location', style: textTheme.titleMedium),
              Text(
                _fullAddress,
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
            key: const Key('view-on-map-button'),
            onPressed: _openMap,
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('View on Map'),
          ),
      ],
    );
  }
}

/// The average overall rating plus the 2 most recent reviews -- social
/// proof shown near the bottom of the page, right where a customer who has
/// already read About/Location and is deciding whether to book would look
/// for it. "View All Reviews" opens this property's full list at
/// `/property/:id/reviews`. `reviews_read` (0044_resort_policies.sql) is
/// what makes every guest's review of this property visible here, not just
/// the customer's own.
class _ReviewsSection extends ConsumerWidget {
  const _ReviewsSection({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(propertyReviewsProvider(propertyId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star, size: 20, color: scheme.primary),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text('Customer Reviews', style: textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        AsyncView(
          value: reviewsAsync,
          data: (reviews) {
            if (reviews.isEmpty) {
              return Text(
                'No reviews yet -- be the first to share your stay.',
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              );
            }
            final average =
                reviews.map((r) => r.overallRating).reduce((a, b) => a + b) /
                    reviews.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber, size: 22),
                    const SizedBox(width: Spacing.xs),
                    Text(average.toStringAsFixed(1),
                        style: textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      '(${reviews.length} review${reviews.length == 1 ? '' : 's'})',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                for (final review in reviews.take(3)) ...[
                  _ReviewPreview(review: review),
                  const SizedBox(height: Spacing.sm),
                ],
                OutlinedButton(
                  key: const Key('view-all-reviews-button'),
                  onPressed: () => context.push('/property/$propertyId/reviews'),
                  child: const Text('View All Reviews'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ReviewPreview extends StatelessWidget {
  const _ReviewPreview({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Icon(
                    i <= review.overallRating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  ),
                const SizedBox(width: Spacing.xs),
                Text(review.customerFirstName ?? 'Guest',
                    style: textTheme.labelLarge),
                const Spacer(),
                if (review.createdAt != null)
                  Text(formatDate(review.createdAt!.toLocal()),
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            if (review.feedback.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                review.feedback,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
