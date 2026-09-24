import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/unit.dart';
import 'package:pasala/features/admin/resort_unit_guard.dart';
import 'package:pasala/features/booking/providers.dart' show unitByIdProvider;

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => const ResortMembership(
        propertyId: 'resort-a',
        resortName: 'Resort A',
        role: ResortRole.admin,
      );
}

Unit _unitAt(String id, String propertyId) => Unit(
      id: id,
      propertyId: propertyId,
      name: 'Cottage',
      capacityBase: 2,
      capacityMax: 4,
      bookingMode: BookingMode.nightly,
      isActive: true,
    );

/// Final review I2: `/admin/rates|block|ota/:unitId` take the unit id from
/// the URL, so the screen behind them must only open for a unit of the
/// current resort.
void main() {
  Widget app() => ProviderScope(
        overrides: [
          currentResortProvider.overrideWith(_FixedResort.new),
          unitByIdProvider('own').overrideWith((ref) async => _unitAt('own', 'resort-a')),
          unitByIdProvider('foreign')
              .overrideWith((ref) async => _unitAt('foreign', 'resort-b')),
          unitByIdProvider('hidden')
              .overrideWith((ref) async => throw const NotFound()),
        ],
        child: const MaterialApp(home: _Pages()),
      );

  testWidgets("a unit of another resort shows not-found, not the screen",
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('foreign'));
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('UNIT SCREEN'), findsNothing);
  });

  testWidgets('a unit the caller cannot read shows not-found', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('hidden'));
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('UNIT SCREEN'), findsNothing);
  });

  testWidgets("a unit of the current resort opens the screen", (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('own'));
    await tester.pumpAndSettle();

    expect(find.text('UNIT SCREEN'), findsOneWidget);
    expect(find.text('Page not found'), findsNothing);
  });
}

/// One button per unit id, each pushing the guarded screen -- the guard is
/// always reached by navigation in the app.
class _Pages extends StatelessWidget {
  const _Pages();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            for (final id in ['own', 'foreign', 'hidden'])
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ResortUnitGuard(
                    unitId: id,
                    child: const Text('UNIT SCREEN'),
                  ),
                )),
                child: Text(id),
              ),
          ],
        ),
      );
}
