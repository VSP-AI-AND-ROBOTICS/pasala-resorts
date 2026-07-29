import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/failure_view.dart';
import '../../data/models/unit.dart';
import '../browse/property_screen.dart' show bookingModeLabel;
import '../browse/providers.dart';
import 'unit_form_screen.dart';

/// Admin's per-property unit list. Reachable at `/admin/units/:propertyId`
/// from `AdminPropertiesScreen`. The overflow menu's `Rates` and
/// `Block dates` items link to `/admin/rates/:unitId` and
/// `/admin/block/:unitId`, which arrive in Tasks 19 and 20 -- until then
/// tapping them hits the router's not-found page, which is expected.
class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitsProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Units')),
      body: units.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(unitsProvider(propertyId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No units yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final unit = list[i];
              return Card(
                child: ListTile(
                  title: Text(unit.name),
                  subtitle: Text(
                    'Sleeps ${unit.capacityBase}–${unit.capacityMax} · '
                    '${bookingModeLabel(unit.bookingMode)}'
                    '${unit.isActive ? '' : ' · Inactive'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => _onMenuSelected(context, unit, value),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'rates', child: Text('Rates')),
                      PopupMenuItem(
                          value: 'block', child: Text('Block dates')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => UnitFormScreen(propertyId: propertyId),
        )),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(BuildContext context, Unit unit, String value) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              UnitFormScreen(propertyId: propertyId, existing: unit),
        ));
      case 'rates':
        context.go('/admin/rates/${unit.id}');
      case 'block':
        context.go('/admin/block/${unit.id}');
    }
  }
}
