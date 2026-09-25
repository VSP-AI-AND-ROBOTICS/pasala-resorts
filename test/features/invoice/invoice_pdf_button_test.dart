import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';
import 'package:pasala/features/invoice/invoice_pdf_button.dart';

import '../../support/fake_invoice_source.dart';
import '../../support/fake_pdf_exporter.dart';

Future<void> _pump(
  WidgetTester tester, {
  required FakeInvoiceSource source,
  required FakePdfExporter exporter,
  required PdfDeliveries deliveries,
  InvoicePdfButtonStyle style = InvoicePdfButtonStyle.button,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      invoiceSourceProvider.overrideWithValue(source),
      pdfExporterProvider.overrideWithValue(exporter),
      pdfDelivererProvider.overrideWithValue(deliveries.deliver),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: InvoicePdfButton(reservationId: 'r1', style: style),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('builds, renders and delivers the invoice', (tester) async {
    final source = FakeInvoiceSource();
    final exporter = FakePdfExporter();
    final deliveries = PdfDeliveries();
    await _pump(
      tester,
      source: source,
      exporter: exporter,
      deliveries: deliveries,
    );

    await tester.tap(find.text('Download invoice (PDF)'));
    await tester.pumpAndSettle();

    expect(source.calls, ['r1']);
    expect(exporter.invoices.single.number, 'FIN-R-3F2A9C1B');
    expect(deliveries.files.single.$1, 'invoice-FIN-R-3F2A9C1B.pdf');
    expect(deliveries.files.single.$2, FakePdfExporter.bytes);
    expect(find.text('Invoice FIN-R-3F2A9C1B is ready.'), findsOneWidget);
  });

  testWidgets('shows the refusal from the invoice builder', (tester) async {
    final source = FakeInvoiceSource()
      ..error = const InvalidState(
        'An invoice is available once the guest has checked in.',
      );
    final exporter = FakePdfExporter();
    await _pump(
      tester,
      source: source,
      exporter: exporter,
      deliveries: PdfDeliveries(),
    );

    await tester.tap(find.byKey(const Key('invoice-pdf-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('An invoice is available once the guest has checked in.'),
      findsOneWidget,
    );
    expect(exporter.invoices, isEmpty);
  });

  testWidgets('says so when the device cannot take the file', (tester) async {
    await _pump(
      tester,
      source: FakeInvoiceSource(),
      exporter: FakePdfExporter(),
      deliveries: PdfDeliveries(delivers: false),
    );

    await tester.tap(find.byKey(const Key('invoice-pdf-button')));
    await tester.pumpAndSettle();

    expect(
      find.text("Invoice download isn't available on this device yet."),
      findsOneWidget,
    );
  });

  testWidgets('a renderer failure reads as a retryable error', (tester) async {
    final deliveries = PdfDeliveries();
    await _pump(
      tester,
      source: FakeInvoiceSource(),
      exporter: FakePdfExporter()..error = StateError('font'),
      deliveries: deliveries,
    );

    await tester.tap(find.byKey(const Key('invoice-pdf-button')));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't create the invoice PDF. Try again."),
      findsOneWidget,
    );
    expect(deliveries.files, isEmpty);
  });

  testWidgets('a second tap while working does nothing', (tester) async {
    final hold = Completer<void>();
    final source = FakeInvoiceSource()..hold = hold;
    final deliveries = PdfDeliveries();
    await _pump(
      tester,
      source: source,
      exporter: FakePdfExporter(),
      deliveries: deliveries,
    );

    await tester.tap(find.byKey(const Key('invoice-pdf-button')));
    await tester.pump();
    expect(find.text('Preparing invoice…'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('invoice-pdf-button')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(source.calls, ['r1']);

    hold.complete();
    await tester.pumpAndSettle();
    expect(deliveries.files, hasLength(1));
    expect(find.text('Download invoice (PDF)'), findsOneWidget);
  });

  testWidgets('the icon style is an "Invoice PDF" button', (tester) async {
    final deliveries = PdfDeliveries();
    await _pump(
      tester,
      source: FakeInvoiceSource(),
      exporter: FakePdfExporter(),
      deliveries: deliveries,
      style: InvoicePdfButtonStyle.icon,
    );

    expect(find.byKey(const Key('invoice-pdf-r1')), findsOneWidget);
    await tester.tap(find.byTooltip('Invoice PDF'));
    await tester.pumpAndSettle();
    expect(deliveries.files.single.$1, 'invoice-FIN-R-3F2A9C1B.pdf');
  });
}
