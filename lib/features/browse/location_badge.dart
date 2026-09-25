import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/location_service.dart';
import '../../core/location/position_service.dart';
import '../../core/theme/tokens.dart';

/// Shows the guest's approximate location ("City, Country") in the browse
/// hero, resolved through [currentPlaceProvider]/[LocationService]. Renders
/// over the hero's photo scrim, so its text stays white/white70 regardless
/// of the app's light/dark theme -- matching the rest of the hero's fixed
/// on-photo text.
///
/// Never blocks the page: while resolving it shows a small inline spinner
/// with "Locating…", and on denial/error a "Set location" chip that retries
/// on tap -- the badge itself is the only thing that changes, everything
/// else in the hero and the property list underneath render regardless.
class LocationBadge extends ConsumerWidget {
  const LocationBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(currentPlaceProvider);

    return place.when(
      loading: () => const _LocatingIndicator(),
      error: (_, _) => _SetLocationChip(onTap: () => _retry(ref)),
      data: (label) => label == null
          ? _SetLocationChip(onTap: () => _retry(ref))
          : _PlaceLabelText(text: '${label.locality}, ${label.country}'),
    );
  }

  /// "Set location" asks again for both the badge's place and the
  /// position behind the browse screen's Distance sort, so granting the
  /// permission here enables both.
  static void _retry(WidgetRef ref) {
    ref.invalidate(currentPlaceProvider);
    ref.invalidate(currentPositionProvider);
  }
}

class _LocatingIndicator extends StatelessWidget {
  const _LocatingIndicator();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(Colors.white70),
        ),
      ),
      SizedBox(width: Spacing.xs),
      Text(
        'Locating…',
        style: TextStyle(color: Colors.white70, fontSize: 13),
      ),
    ],
  );
}

class _PlaceLabelText extends StatelessWidget {
  const _PlaceLabelText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.location_on, color: Colors.white, size: 16),
      const SizedBox(width: Spacing.xs),
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _SetLocationChip extends StatelessWidget {
  const _SetLocationChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: const Icon(Icons.location_off, size: 16, color: Colors.white),
    label: const Text('Set location', style: TextStyle(color: Colors.white)),
    backgroundColor: Colors.white.withValues(alpha: 0.15),
    side: const BorderSide(color: Colors.white38),
    visualDensity: VisualDensity.compact,
    onPressed: onTap,
  );
}
