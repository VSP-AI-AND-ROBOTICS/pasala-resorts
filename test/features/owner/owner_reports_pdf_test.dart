import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/finance_tables.dart';
import 'package:pasala/features/owner/owner_reports_screen.dart';

import '../../support/fake_finance_source.dart';
import '../../support/fake_pdf_exporter.dart';

const _ownerM = ResortMembership(
  propertyId: 'p1',
  resortName: 'Resort R',
  role: ResortRole.owner,
);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _ownerM;
}

/// The screen opens on this month; the file names follow it.
String _month() {
  final now = DateTime.now();
  return '${isoDate(DateTime(now.year, now.month, 1))}-'
      '${isoDate(DateTime(now.year, now.month + 1, 0))}';
}

Future<void> _pump(
  WidgetTester tester,
  FakeFinanceSource source,
  FakePdfExporter exporter,
  PdfDeliveries deliveries,
) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeSourceProvider.overrideWithValue(source),
        currentResortProvider.overrideWith(_FixedResort.new),
        pdfExporterProvider.overrideWithValue(exporter),
        pdfDelivererProvider.overrideWithValue(deliveries.deliver),
      ],
      child: const MaterialApp(home: OwnerReportsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pdfOn(String title) => find.descendant(
  of: find.widgetWithText(ListTile, title),
  matching: find.byTooltip('Export PDF'),
);

void main() {
  testWidgets(
    'the three finance tiles offer PDF next to CSV; the others do not',
    (tester) async {
      await _pump(
        tester,
        FakeFinanceSource(),
        FakePdfExporter(),
        PdfDeliveries(),
      );

      expect(find.text('EXPORT'), findsOneWidget);
      for (final title in ['Collections', 'Ledger', 'Settlements']) {
        expect(_pdfOn(title), findsOneWidget, reason: title);
      }
      for (final title in [
        'Revenue',
        'Occupancy',
        'Food & activity sales',
        'Expenses',
      ]) {
        expect(_pdfOn(title), findsNothing, reason: title);
      }
      expect(find.byTooltip('Export CSV'), findsNWidgets(7));
    },
  );

  for (final (title, report) in [
    ('Collections', 'collections'),
    ('Ledger', 'ledger'),
    ('Settlements', 'settlements'),
  ]) {
    testWidgets('$title exports this month as PDF', (tester) async {
      final exporter = FakePdfExporter();
      final deliveries = PdfDeliveries();
      await _pump(tester, FakeFinanceSource(), exporter, deliveries);

      await tester.tap(_pdfOn(title));
      await tester.pumpAndSettle();

      expect(exporter.reports.single.title, title);
      expect(deliveries.files.single.$1, 'fin-r-$report-${_month()}.pdf');
      expect(find.text('PDF exported.'), findsOneWidget);
    });
  }

  testWidgets('a refusal is shown and nothing is exported', (tester) async {
    final exporter = FakePdfExporter();
    await _pump(
      tester,
      FakeFinanceSource()..summaryError = const NotAMember(),
      exporter,
      PdfDeliveries(),
    );

    await tester.tap(_pdfOn('Ledger'));
    await tester.pumpAndSettle();

    expect(
      find.text('You no longer have access to this resort.'),
      findsOneWidget,
    );
    expect(exporter.reports, isEmpty);
  });
}
