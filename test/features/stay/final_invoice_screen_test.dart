import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/booking/providers.dart';
import 'package:pasala/features/stay/final_invoice_screen.dart';

import '../../support/fake_invoice_source.dart';
import '../../support/fake_pdf_exporter.dart';

// A full uuid: the screen shows `id.substring(0, 8)`.
const _id = '3f2a9c1b-0000-4000-8000-000000000001';

final _reservation = Reservation.fromJson(const {
  'id': '44444444-0000-4000-8000-000000000051',
  'unit_id': 'u1',
  'period': '["2026-08-03 08:30:00+00","2026-08-04 05:30:00+00")',
  'kind': 'booking',
  'status': 'checked_out',
});

Future<void> _pump(WidgetTester tester, CurrentCharges charges) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      reservationProvider.overrideWith((ref, id) async => _reservation),
      currentChargesProvider.overrideWith((ref, id) async => charges),
    ],
    child: MaterialApp(home: FinalInvoiceScreen(reservationId: _reservation.id)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers the PDF above "Leave a review"', (tester) async {
    final source = FakeInvoiceSource();
    final deliveries = PdfDeliveries();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reservationProvider(_id).overrideWith(
            (ref) async => Reservation(
              id: _id,
              unitId: 'u1',
              start: DateTime.utc(2026, 8, 10, 8, 30),
              end: DateTime.utc(2026, 8, 12, 5, 30),
              kind: ReservationKind.booking,
              status: ReservationStatus.checkedOut,
            ),
          ),
          currentChargesProvider(_id).overrideWith(
            (ref) async => const CurrentCharges(
              stayAmount: 10640,
              foodAmount: 840,
              activityAmount: 1180,
              total: 12660,
              paid: 12660,
              balance: 0,
            ),
          ),
          invoiceSourceProvider.overrideWithValue(source),
          pdfExporterProvider.overrideWithValue(FakePdfExporter()),
          pdfDelivererProvider.overrideWithValue(deliveries.deliver),
        ],
        child: const MaterialApp(home: FinalInvoiceScreen(reservationId: _id)),
      ),
    );
    await tester.pumpAndSettle();

    final pdf = find.byKey(const Key('invoice-pdf-button'));
    expect(pdf, findsOneWidget);
    expect(
      tester.getTopLeft(pdf).dy,
      lessThan(tester.getTopLeft(find.text('Leave a review')).dy),
    );

    await tester.tap(pdf);
    await tester.pumpAndSettle();
    expect(source.calls, [_id]);
    expect(deliveries.files.single.$1, 'invoice-FIN-R-3F2A9C1B.pdf');
  });

  testWidgets('shows the tax inside food and inside activities', (tester) async {
    await _pump(
        tester,
        const CurrentCharges(
          stayAmount: 5000,
          foodAmount: 525,
          foodTax: 25,
          activityAmount: 2360,
          activityTax: 360,
          total: 7885,
          paid: 7885,
          balance: 0,
        ));

    expect(
        find.descendant(
            of: find.byKey(const Key('invoice-food-tax')),
            matching: find.text('Includes tax ₹25.00')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('invoice-activity-tax')),
            matching: find.text('Includes tax ₹360.00')),
        findsOneWidget);
    expect(find.text('₹7,885'), findsNWidgets(2)); // Final amount and Paid
  });

  testWidgets('no tax line when there is no tax', (tester) async {
    await _pump(
        tester,
        const CurrentCharges(
          stayAmount: 3000,
          foodAmount: 0,
          activityAmount: 0,
          total: 3000,
          paid: 3000,
          balance: 0,
        ));

    expect(find.textContaining('Includes tax'), findsNothing);
  });
}
