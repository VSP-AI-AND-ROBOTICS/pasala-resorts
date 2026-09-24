import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/admin/reception_checkin_screen.dart';

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Reservation _booking({String? customerName}) => Reservation(
      id: '3f2a1b9c-0000-0000-0000-000000000000',
      unitId: 'u1',
      start: DateTime(2026, 9, 14),
      end: DateTime(2026, 9, 16),
      kind: ReservationKind.booking,
      status: ReservationStatus.confirmed,
      customerName: customerName,
      guests: 2,
    );

void main() {
  final listedPropertyIds = <String>[];

  Widget appFor(List<Reservation> arrivals) => ProviderScope(
        overrides: [
          todaysArrivalsProvider.overrideWith((ref, propertyId) async {
            listedPropertyIds.add(propertyId);
            return arrivals;
          }),
          currentResortProvider.overrideWith(_FixedResort.new),
        ],
        child: const MaterialApp(home: ReceptionCheckinScreen()),
      );

  // I9: this screen previously showed only a date range and an internal
  // booking id -- reception had no way to identify WHO they were checking
  // in without cross-referencing a booking id by hand. Reproduced live: a
  // real guest ("Ravi Kumar") appeared here as an anonymous date range.
  testWidgets('shows the guest\'s real name when the query returns one',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(listedPropertyIds, everyElement('p1'));
  });

  testWidgets('falls back to "Guest" only when no name is available',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: null)]));
    await tester.pumpAndSettle();

    expect(find.text('Guest'), findsOneWidget);
  });

  testWidgets('the date range and guest count still show in the subtitle',
      (tester) async {
    await tester.pumpWidget(appFor([_booking(customerName: 'Ravi Kumar')]));
    await tester.pumpAndSettle();

    expect(find.textContaining('14 Sep'), findsOneWidget);
    expect(find.textContaining('2 guests'), findsOneWidget);
  });
}
