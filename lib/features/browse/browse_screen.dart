import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/greeting.dart';
import '../../core/location/geo_point.dart';
import '../../core/location/position_service.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/theme_toggle_button.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../core/widgets/staggered_fade_in.dart';
import '../../data/models/app_user.dart';
import '../../data/models/property.dart';
import '../../data/models/resort_search.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/resort_search_repository.dart';
import '../shell/app_shell.dart' show showAccountSheet;
import 'browse_filter_bar.dart';
import 'location_badge.dart';
import 'resort_meta_line.dart';

/// `/`: every bookable resort, searched and sorted by `search_resorts`
/// (0060_guest_search.sql). ResortHub lists every active resort; the
/// 2026-08-13 single-property redirect is superseded by the 2026-09-24
/// tenancy spec.
///
/// The hero and the filter bar always stay on screen. Only the results
/// area below them loads, fails or empties, so a guest typing into the
/// search box never loses the field or its focus.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  /// How long typing must pause before a search runs.
  static const searchDebounce = Duration(milliseconds: 300);

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _text = '';
  ResortSort _sort = ResortSort.recommended;
  String? _selectedAmenity;

  /// The last results that finished loading, shown under a progress bar
  /// while the next search runs (spec decision 20).
  List<ResortSearchResult>? _lastResults;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(BrowseScreen.searchDebounce, () {
      if (mounted) setState(() => _text = value.trim());
    });
  }

  void _onSearchSubmitted(String value) {
    _debounce?.cancel();
    setState(() => _text = value.trim());
  }

  void _clearFilters() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _text = '';
      _selectedAmenity = null;
      _sort = ResortSort.recommended;
    });
  }

  /// Distance needs a position. Without one the sort quietly falls back to
  /// Recommended, and the menu does not offer Distance at all.
  ResortSearchQuery _queryFor(GeoPoint? origin) => ResortSearchQuery(
        text: _text,
        sort: _sort == ResortSort.distance && origin == null
            ? ResortSort.recommended
            : _sort,
        amenities: [?_selectedAmenity],
        origin: origin?.coarse(),
      );

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;
    final origin = ref.watch(currentPositionProvider).value;
    final query = _queryFor(origin);
    final results = ref.watch(resortSearchProvider(query));
    // The chips come from the unfiltered list, so picking one never hides
    // the others.
    final everything = ref.watch(resortSearchProvider(ResortSearchQuery.all));

    final fresh = results.value;
    if (fresh != null) _lastResults = fresh;
    final shown = fresh ?? _lastResults;

    final amenities = <String>{
      for (final r in everything.value ?? const <ResortSearchResult>[])
        ...r.property.amenities,
      ?_selectedAmenity,
    }.toList()
      ..sort();
    final sortOptions = [
      for (final option in ResortSort.values)
        if (option != ResortSort.distance || origin != null) option,
    ];

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(resortSearchProvider),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _BrowseHero(wide: wide)),
          SliverToBoxAdapter(
            child: BrowseFilterBar(
              controller: _searchController,
              onSearchChanged: _onSearchChanged,
              onSearchSubmitted: _onSearchSubmitted,
              sort: query.sort,
              sortOptions: sortOptions,
              onSortChanged: (sort) => setState(() => _sort = sort),
              amenities: amenities,
              selectedAmenity: _selectedAmenity,
              onAmenitySelected: (amenity) =>
                  setState(() => _selectedAmenity = amenity),
              showClear: query.hasFilters,
              onClear: _clearFilters,
            ),
          ),
          if (results.isLoading && shown != null)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(
                key: Key('browse-searching'),
                minHeight: 2,
              ),
            ),
          ..._resultSlivers(context, results, shown, query, wide),
        ],
      ),
    );
  }

  List<Widget> _resultSlivers(
    BuildContext context,
    AsyncValue<List<ResortSearchResult>> results,
    List<ResortSearchResult>? shown,
    ResortSearchQuery query,
    bool wide,
  ) {
    if (results.hasError && !results.isLoading) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: FailureView(
            error: results.error!,
            onRetry: () => ref.invalidate(resortSearchProvider(query)),
          ),
        ),
      ];
    }
    if (shown == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (shown.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: query.hasFilters
              ? _CenteredMessage(
                  icon: Icons.search_off,
                  title: 'No resorts match your search',
                  message: 'Try a different word or clear the filters.',
                  action: TextButton(
                    key: const Key('browse-empty-clear'),
                    onPressed: _clearFilters,
                    child: const Text('Clear filters'),
                  ),
                )
              : const _CenteredMessage(
                  icon: Icons.villa_outlined,
                  title: 'No properties yet',
                  message: 'Ask an admin to add one.',
                ),
        ),
      ];
    }

    Widget card(int i) {
      final result = shown[i];
      return StaggeredFadeIn(
        key: ValueKey(result.property.id),
        index: i,
        child: PropertyCard(
          property: result.property,
          distanceKm: result.distanceKm,
          minPrice: result.minPrice,
          avgRating: result.avgRating,
          reviewCount: result.reviewCount,
          onTap: () => context.go('/property/${result.property.id}'),
        ),
      );
    }

    if (wide) {
      return [
        SliverPadding(
          padding: const EdgeInsets.all(Spacing.md),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: Spacing.md,
              crossAxisSpacing: Spacing.md,
              // 0.76, not 0.82: room for the meta line at the 840 px
              // breakpoint.
              childAspectRatio: 0.76,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => card(i),
              childCount: shown.length,
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.all(Spacing.md),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: card(i),
            ),
            childCount: shown.length,
          ),
        ),
      ),
    ];
  }
}

/// The results area's empty states. This is a plain `Column`, not
/// `EmptyState`: `SliverFillRemaining(hasScrollBody: false)` measures its
/// child's intrinsic height, and `EmptyState`'s `LayoutBuilder` cannot
/// report one.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: Spacing.md),
            Text(title,
                style: textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.sm),
            Text(
              message,
              style:
                  textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: Spacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _BrowseHero extends ConsumerWidget {
  const _BrowseHero({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final greeting = greetingLine(DateTime.now(), user?.fullName);

    return SizedBox(
      // Taller on wide/web layouts so the hero doesn't look like a thin
      // strip on a desktop-width browser window (spec section 7).
      height: wide ? 280 : 200,
      child: HeroBackdrop(
        imageAsset: AppAssets.heroDayAerial,
        scrimOpacity: 0.35,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // White icon so the toggle reads against the hero photo's
                  // scrim, matching the profile button beside it rather than
                  // whatever color the current theme would otherwise pick.
                  IconTheme(
                    data: const IconThemeData(color: Colors.white),
                    child: const ThemeToggleButton(),
                  ),
                  IconButton(
                    key: const Key('browse-hero-profile'),
                    tooltip: 'Account',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    iconSize: 22,
                    icon: const Icon(
                      Icons.account_circle_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () => _openAccount(context, ref, user),
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: PasalaTokens.displayWeight,
                      letterSpacing: PasalaTokens.displayLetterSpacing,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'Discover your stay',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  const LocationBadge(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The hero's profile button: for a signed-in guest, the shared account
  /// sheet (`showAccountSheet`, also used by `AppShell`'s customer/admin
  /// profile avatars -- there is no separate account screen/route to push
  /// to); for a signed-out guest, straight to `/login` rather than a sheet
  /// with nothing signed-in to show.
  void _openAccount(BuildContext context, WidgetRef ref, AppUser? user) {
    if (user == null) {
      context.go('/login');
    } else {
      showAccountSheet(context, ref);
    }
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

  String get _initial => property.name.trim().isEmpty
      ? '?'
      : property.name.trim()[0].toUpperCase();

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
  Widget build(BuildContext context) =>
      Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);
}

/// The icon shown alongside an amenity's label. Pure so it's testable
/// without a widget, and falls back to a generic icon for anything an
/// admin adds that isn't in this list -- an unrecognised amenity must
/// never crash or render blank.
IconData amenityIcon(String label) => switch (label.toLowerCase()) {
  'pool' => Icons.pool,
  'wi-fi' || 'wifi' => Icons.wifi,
  'barbecue' => Icons.outdoor_grill,
  'parking' => Icons.local_parking,
  'garden' || 'lawn' => Icons.grass,
  'bonfire' => Icons.local_fire_department,
  'spacious' => Icons.aspect_ratio,
  _ => Icons.check_circle_outline,
};

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
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final shown = amenities.take(max).toList();
    final overflow = amenities.length - shown.length;

    Widget metaChip(String label, {IconData? icon}) => Chip(
      avatar: icon != null
          ? Icon(icon, size: 16, color: scheme.onSurfaceVariant)
          : null,
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
        for (final a in shown) metaChip(a, icon: amenityIcon(a)),
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
  const PropertyCard({
    super.key,
    required this.property,
    this.onTap,
    this.distanceKm,
    this.minPrice,
    this.avgRating,
    this.reviewCount = 0,
  });

  final Property property;
  final VoidCallback? onTap;

  /// What `search_resorts` adds on the browse screen, shown by
  /// [ResortMetaLine]. These are null on admin screens that reuse this
  /// card, and then the line renders nothing.
  final double? distanceKm;
  final num? minPrice;
  final double? avgRating;
  final int reviewCount;

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
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      ResortMetaLine(
                        avgRating: widget.avgRating,
                        reviewCount: widget.reviewCount,
                        distanceKm: widget.distanceKm,
                        minPrice: widget.minPrice,
                      ),
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
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
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
