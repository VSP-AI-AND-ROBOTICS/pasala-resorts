import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';
import 'package:pasala/features/finance/finance_settlements_tab.dart';

import '../../support/fake_finance_source.dart';
import '../../support/fake_invoice_source.dart';
import '../../support/fake_pdf_exporter.dart';

final _filter = (
  from: DateTime(2026, 8, 1),
  to: DateTime(2026, 8, 31),
  propertyId: 'p1',
);

Future<FakeInvoiceSource> _pump(
  WidgetTester tester, {
  required bool wide,
}) async {
  tester.view.physicalSize = wide
      ? const Size(1400, 1200)
      : const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final source = FakeInvoiceSource();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        financeSourceProvider.overrideWithValue(
          FakeFinanceSource()
            ..settlementRows = [
              settlementRow(reservationId: 'r1', room: 5000),
              settlementRow(
                reservationId: 'r2',
                guestName: 'Ravi Rao',
                room: 7000,
              ),
            ],
        ),
        invoiceSourceProvider.overrideWithValue(source),
        pdfExporterProvider.overrideWithValue(FakePdfExporter()),
        pdfDelivererProvider.overrideWithValue(PdfDeliveries().deliver),
      ],
      child: MaterialApp(
        home: Scaffold(body: FinanceSettlementsTab(filter: _filter)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return source;
}

void main() {
  testWidgets('each settlement card has its own invoice PDF', (tester) async {
    final source = await _pump(tester, wide: false);

    expect(find.byTooltip('Invoice PDF'), findsNWidgets(2));
    expect(find.text('Settled'), findsNWidgets(2));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('settlement-r2')),
        matching: find.byTooltip('Invoice PDF'),
      ),
    );
    await tester.pumpAndSettle();

    expect(source.calls, ['r2']);
  });

  testWidgets('the wide table has an Invoice column', (tester) async {
    final source = await _pump(tester, wide: true);

    expect(find.text('Invoice'), findsOneWidget);
    // The table scrolls sideways; bring its last column into view first.
    await tester.ensureVisible(find.byKey(const Key('invoice-pdf-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invoice-pdf-r1')));
    await tester.pumpAndSettle();

    expect(source.calls, ['r1']);
  });
}
