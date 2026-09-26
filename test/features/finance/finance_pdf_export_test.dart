import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/finance_screen.dart';

import '../../support/fake_finance_source.dart';
import '../../support/fake_pdf_exporter.dart';

const _resort = ResortMembership(
  propertyId: 'p1',
  resortName: 'Resort R',
  role: ResortRole.accountant,
);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

final _august = DateTimeRange(
  start: DateTime(2026, 8, 1),
  end: DateTime(2026, 8, 31),
);

Future<void> _pump(
  WidgetTester tester, {
  required FakeFinanceSource source,
  required FakePdfExporter exporter,
  required PdfDeliveries deliveries,
}) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        financeSourceProvider.overrideWithValue(source),
        currentResortProvider.overrideWith(_FixedResort.new),
        pdfExporterProvider.overrideWithValue(exporter),
        pdfDelivererProvider.overrideWithValue(deliveries.deliver),
      ],
      child: MaterialApp(home: FinanceScreen(initialRange: _august)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final tab = find.widgetWithText(Tab, label);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Today has no PDF export; the three reports do', (tester) async {
    await _pump(
      tester,
      source: FakeFinanceSource(),
      exporter: FakePdfExporter(),
      deliveries: PdfDeliveries(),
    );

    expect(find.byKey(const Key('finance-export-pdf')), findsNothing);
    expect(find.byKey(const Key('finance-export')), findsOneWidget);
    for (final label in ['Collections', 'Ledger', 'Settlements']) {
      await _openTab(tester, label);
      expect(find.byTooltip('Export PDF'), findsOneWidget, reason: label);
    }
  });

  for (final (label, title, report) in [
    ('Collections', 'Collections', 'collections'),
    ('Ledger', 'Ledger', 'ledger'),
    ('Settlements', 'Settlements', 'settlements'),
  ]) {
    testWidgets('$label exports its own PDF for the chosen range', (
      tester,
    ) async {
      final exporter = FakePdfExporter();
      final deliveries = PdfDeliveries();
      await _pump(
        tester,
        source: FakeFinanceSource()
          ..collectionRows = [collectionRow(amount: 5000)]
          ..ledgerRows = [ledgerRow(gross: 1000)]
          ..settlementRows = [settlementRow(room: 1000)],
        exporter: exporter,
        deliveries: deliveries,
      );
      await _openTab(tester, label);

      await tester.tap(find.byKey(const Key('finance-export-pdf')));
      await tester.pumpAndSettle();

      final pdf = exporter.reports.single;
      expect(pdf.title, title);
      expect(pdf.rows, isNotEmpty);
      expect(
        deliveries.files.single.$1,
        'fin-r-$report-2026-08-01-2026-08-31.pdf',
      );
      expect(find.text('PDF exported.'), findsOneWidget);
    });
  }

  testWidgets('a platform that cannot take the file says so', (tester) async {
    await _pump(
      tester,
      source: FakeFinanceSource(),
      exporter: FakePdfExporter(),
      deliveries: PdfDeliveries(delivers: false),
    );
    await _openTab(tester, 'Collections');

    await tester.tap(find.byKey(const Key('finance-export-pdf')));
    await tester.pumpAndSettle();

    expect(
      find.text("PDF export isn't available on this platform yet."),
      findsOneWidget,
    );
  });

  testWidgets('a rendering failure is reported, not thrown', (tester) async {
    await _pump(
      tester,
      source: FakeFinanceSource(),
      exporter: FakePdfExporter()..error = StateError('font'),
      deliveries: PdfDeliveries(),
    );
    await _openTab(tester, 'Ledger');

    await tester.tap(find.byKey(const Key('finance-export-pdf')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't create the PDF. Try again."), findsOneWidget);
  });

  testWidgets('a report that failed to load exports nothing', (tester) async {
    final exporter = FakePdfExporter();
    // NetworkFailure, not NotAMember: NotAMember's FailureView side effect
    // clears currentResortProvider (lib/core/widgets/failure_view.dart),
    // which this test does not want to exercise -- same choice the sibling
    // CSV test makes at finance_screen_test.dart's "Export after a failed
    // load says so and writes nothing".
    await _pump(
      tester,
      source: FakeFinanceSource()..settlementsError = const NetworkFailure(),
      exporter: exporter,
      deliveries: PdfDeliveries(),
    );
    await _openTab(tester, 'Settlements');

    await tester.tap(find.byKey(const Key('finance-export-pdf')));
    await tester.pumpAndSettle();

    expect(
      find.text("This report didn't load, so there is nothing to export."),
      findsOneWidget,
    );
    expect(exporter.reports, isEmpty);
  });

  testWidgets('a second tap while a PDF is being made does nothing', (
    tester,
  ) async {
    final hold = Completer<void>();
    final exporter = FakePdfExporter()..hold = hold;
    final deliveries = PdfDeliveries();
    await _pump(
      tester,
      source: FakeFinanceSource(),
      exporter: exporter,
      deliveries: deliveries,
    );
    await _openTab(tester, 'Collections');

    await tester.tap(find.byKey(const Key('finance-export-pdf')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('finance-export-pdf')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(exporter.reports, hasLength(1));

    hold.complete();
    await tester.pumpAndSettle();
    expect(deliveries.files, hasLength(1));
  });
}
