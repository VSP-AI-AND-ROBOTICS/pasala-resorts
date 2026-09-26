import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';
import 'package:pasala/features/account/booking_detail_screen.dart';
import 'package:pasala/features/booking/providers.dart'
    show reservationProvider;

import '../../support/fake_invoice_source.dart';
import '../../support/fake_pdf_exporter.dart';

Reservation _reservation(
  ReservationStatus status, {
  ReservationKind kind = ReservationKind.booking,
}) => Reservation(
  id: 'r1',
  unitId: 'u1',
  start: DateTime.utc(2026, 8, 10, 8, 30),
  end: DateTime.utc(2026, 8, 12, 5, 30),
  kind: kind,
  status: status,
  guests: 2,
  quote: kind == ReservationKind.booking
      ? Quote(
          currency: 'INR',
          guests: 2,
          lines: [
            QuoteLine(
              date: DateTime.utc(2026, 8, 10),
              label: 'Weekday rate',
              amount: 5000,
              extraGuests: 0,
              extraGuestAmount: 0,
            ),
          ],
          subtotal: 5000,
          cleaningFee: 0,
          total: 5000,
        )
      : null,
);

Future<(FakeInvoiceSource, PdfDeliveries)> _open(
  WidgetTester tester,
  Reservation reservation,
) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final source = FakeInvoiceSource();
  final deliveries = PdfDeliveries();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reservationProvider(
          reservation.id,
        ).overrideWith((ref) async => reservation),
        invoiceSourceProvider.overrideWithValue(source),
        pdfExporterProvider.overrideWithValue(FakePdfExporter()),
        pdfDelivererProvider.overrideWithValue(deliveries.deliver),
      ],
      child: MaterialApp(
        home: BookingDetailScreen(reservationId: reservation.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (source, deliveries);
}

void main() {
  for (final status in [
    ReservationStatus.checkedIn,
    ReservationStatus.checkedOut,
  ]) {
    testWidgets('a ${status.name} booking offers its invoice', (tester) async {
      final (source, deliveries) = await _open(tester, _reservation(status));

      await tester.tap(find.byKey(const Key('invoice-pdf-button')));
      await tester.pumpAndSettle();

      expect(source.calls, ['r1']);
      expect(deliveries.files.single.$1, 'invoice-FIN-R-3F2A9C1B.pdf');
    });
  }

  for (final status in [
    ReservationStatus.hold,
    ReservationStatus.pendingPayment,
    ReservationStatus.confirmed,
    ReservationStatus.cancelled,
  ]) {
    testWidgets('a ${status.name} booking has no invoice yet', (tester) async {
      await _open(tester, _reservation(status));
      expect(find.byKey(const Key('invoice-pdf-button')), findsNothing);
    });
  }

  testWidgets('an OTA row never offers an invoice', (tester) async {
    await _open(
      tester,
      _reservation(ReservationStatus.checkedIn, kind: ReservationKind.ota),
    );
    expect(find.byKey(const Key('invoice-pdf-button')), findsNothing);
  });
}
