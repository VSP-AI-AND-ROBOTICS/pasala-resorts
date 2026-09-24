import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/finance_tables.dart';
import 'package:pasala/features/finance/providers.dart';
import 'package:pasala/features/owner/owner_reports_screen.dart';

import '../../support/fake_finance_source.dart';

const _ownerM =
    ResortMembership(propertyId: 'p1', resortName: 'Resort R', role: ResortRole.owner);

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

Future<List<(String, String)>> _pump(WidgetTester tester, FakeFinanceSource source) async {
  final files = <(String, String)>[];
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      financeSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(_FixedResort.new),
      csvDownloaderProvider.overrideWithValue((name, csv) {
        files.add((name, csv));
        return true;
      }),
    ],
    child: const MaterialApp(home: OwnerReportsScreen()),
  ));
  await tester.pumpAndSettle();
  return files;
}

Future<void> _export(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, title), matching: find.byTooltip('Export CSV')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the finance reports next to the existing four', (tester) async {
    await _pump(tester, FakeFinanceSource());

    for (final title in [
      'Revenue',
      'Occupancy',
      'Food & activity sales',
      'Expenses',
      'Collections',
      'Ledger',
      'Settlements',
    ]) {
      expect(find.widgetWithText(ListTile, title), findsOneWidget, reason: title);
    }
  });

  testWidgets('Collections exports this month of the current resort with its header',
      (tester) async {
    final source = FakeFinanceSource()
      ..collectionRows = [
        collectionRow(day: DateTime(2026, 8, 5), source: CollectionSource.refund, amount: -1500),
      ];
    final files = await _pump(tester, source);

    await _export(tester, 'Collections');

    final (name, csv) = files.single;
    expect(name, 'fin-r-collections-${_month()}.csv');
    expect(csv, startsWith('Resort R,GSTIN 29ABCDE1234F1Z5\r\nPeriod,'));
    expect(csv, contains('2026-08-05,online,refund,gateway,1,-1500.00\r\n'));
    expect(source.collectionsCalls.single.propertyId, 'p1');
    expect(source.summaryCalls, ['p1']);
    expect(find.text('CSV exported.'), findsOneWidget);
  });

  testWidgets('Ledger and Settlements export under their own names', (tester) async {
    final source = FakeFinanceSource()
      ..ledgerRows = [ledgerRow(gross: 3000)]
      ..settlementRows = [settlementRow(room: 3000)];
    final files = await _pump(tester, source);

    await _export(tester, 'Ledger');
    await _export(tester, 'Settlements');

    expect(files.map((f) => f.$1), [
      'fin-r-ledger-${_month()}.csv',
      'fin-r-settlements-${_month()}.csv',
    ]);
    expect(files[0].$2, contains('Date,Category,Source,Gross,Discount,Taxable,Tax,Net\r\n'));
    expect(files[1].$2, contains('\r\nr1,Gita Guest,Cottage 1,'));
  });

  testWidgets('a failed finance export says why and writes nothing', (tester) async {
    final files =
        await _pump(tester, FakeFinanceSource()..collectionsError = const NetworkFailure());

    await _export(tester, 'Collections');

    expect(files, isEmpty);
    expect(find.text('Cannot reach the server. Check your connection.'), findsOneWidget);
  });
}
