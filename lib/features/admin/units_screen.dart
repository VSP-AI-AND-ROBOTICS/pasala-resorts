import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/unit.dart';
import '../browse/property_screen.dart' show bookingModeLabel;
import '../browse/providers.dart';
import 'unit_form_screen.dart';

/// Admin's per-property unit list. Reachable at `/admin/units/:propertyId`
/// from `AdminPropertiesScreen`. The overflow menu's `Rates`, `Block dates`
/// and `OTA sync` items link to `/admin/rates/:unitId`,
/// `/admin/block/:unitId` and `/admin/ota/:unitId` respectively.
class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitsProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Units')),
      body: AsyncView(
        value: units,
        onRetry: () => ref.invalidate(unitsProvider(propertyId)),
        empty: () => const EmptyState(
          icon: Icons.bed_outlined,
          title: 'No units yet',
          message: 'Add one with the button below.',
        ),
        data: (list) => ListView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final unit = list[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Card(
                child: ListTile(
                  title: Text(unit.name),
                  subtitle: Text(
                    'Sleeps ${unit.capacityBase}–${unit.capacityMax} · '
                    '${bookingModeLabel(unit.bookingMode)}'
                    '${unit.isActive ? '' : ' · Inactive'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) =>
                        _onMenuSelected(context, unit, value),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'rates', child: Text('Rates')),
                      PopupMenuItem(value: 'block', child: Text('Block dates')),
                      PopupMenuItem(value: 'ota', child: Text('OTA sync')),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UnitFormScreen(propertyId: propertyId),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(BuildContext context, Unit unit, String value) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                UnitFormScreen(propertyId: propertyId, existing: unit),
          ),
        );
      case 'rates':
        context.push('/admin/rates/${unit.id}');
      case 'block':
        context.push('/admin/block/${unit.id}');
      case 'ota':
        context.push('/admin/ota/${unit.id}');
    }
  }
}
