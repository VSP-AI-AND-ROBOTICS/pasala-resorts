import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../booking/providers.dart' show unitByIdProvider;
import '../shell/not_found_screen.dart';

/// Wraps a screen reached at `/admin/rates|block|ota/:unitId`, whose unit
/// id comes straight from the URL: [child] is only built once the unit is
/// known to belong to the current resort. A unit of another resort -- which
/// `units_read` still shows to anyone while that resort is active -- or one
/// the caller cannot read at all shows [NotFoundScreen] instead, so a
/// pasted URL never opens another resort's rates, blocking or OTA sync.
class ResortUnitGuard extends ConsumerWidget {
  const ResortUnitGuard({super.key, required this.unitId, required this.child});

  final String unitId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resortId = ref.watch(currentResortProvider)?.propertyId;
    final unit = ref.watch(unitByIdProvider(unitId));
    return unit.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const NotFoundScreen(),
      data: (u) => resortId != null && u.propertyId == resortId
          ? child
          : const NotFoundScreen(),
    );
  }
}
